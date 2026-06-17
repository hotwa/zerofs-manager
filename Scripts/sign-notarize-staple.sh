#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-"$PROJECT_ROOT/dist"}"
APP_PATH="${APP_PATH:-"$DIST_DIR/ZeroFS Manager.app"}"
DMG_PATH="${DMG_PATH:-"$DIST_DIR/ZeroFS-Manager-distribution.dmg"}"
CONFIGURATION="${CONFIGURATION:-release}"
export CONFIGURATION
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-}}"
APP_ENTITLEMENTS="$PROJECT_ROOT/Resources/Entitlements/ZeroFSManagerApp.distribution.entitlements"
HELPER_ENTITLEMENTS="$PROJECT_ROOT/Resources/Entitlements/ZeroFSPrivilegedHelper.entitlements"

fail() {
  echo "Distribution packaging failed: $*" >&2
  exit 2
}

verify_code_signature() {
  local path="$1"
  codesign --verify --strict --verbose=4 "$path" || \
    fail "codesign verification failed for $path. Check for unsigned nested code, invalid entitlements, or a modified binary after signing."
}

verify_hardened_runtime() {
  local path="$1"
  codesign -dv "$path" 2>&1 | grep -q "Runtime Version" || \
    fail "missing hardened runtime on $path"
}

if [[ -z "$IDENTITY" || -z "${DEVELOPMENT_TEAM:-}" || -z "$NOTARY_PROFILE" ]]; then
  echo "Official release signing is unavailable because Developer ID is not configured."
  echo "Skipping official release path."
  exit 0
fi

security find-identity -v -p codesigning | grep -F "$IDENTITY" >/dev/null || fail "Developer ID identity not found in keychain: $IDENTITY"

if plutil -extract com.apple.security.get-task-allow raw -o - "$APP_ENTITLEMENTS" 2>/dev/null | grep -q true; then
  fail "distribution entitlements must not enable get-task-allow"
fi

"$PROJECT_ROOT/Scripts/build-app.sh"
"$PROJECT_ROOT/Scripts/verify-bundle.sh" "$APP_PATH"

codesign --force --timestamp --options runtime --entitlements "$HELPER_ENTITLEMENTS" --sign "$IDENTITY" \
  "$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"
verify_code_signature "$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"
verify_hardened_runtime "$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"
codesign --force --timestamp --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$IDENTITY" \
  "$APP_PATH/Contents/MacOS/ZeroFSProbeTool"
verify_code_signature "$APP_PATH/Contents/MacOS/ZeroFSProbeTool"
verify_hardened_runtime "$APP_PATH/Contents/MacOS/ZeroFSProbeTool"
codesign --force --timestamp --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$IDENTITY" \
  "$APP_PATH/Contents/MacOS/ZeroFSManagerApp"
verify_code_signature "$APP_PATH/Contents/MacOS/ZeroFSManagerApp"
verify_hardened_runtime "$APP_PATH/Contents/MacOS/ZeroFSManagerApp"
codesign --force --timestamp --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=4 "$APP_PATH" || \
  fail "deep app verification failed. Check unsigned nested code, helper plist path, hardened runtime, and whether bundle contents changed after signing."
verify_hardened_runtime "$APP_PATH"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "ZeroFS Manager" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=4 "$DMG_PATH" || fail "DMG signature verification failed"

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

xcrun stapler staple "$DMG_PATH" || fail "stapling failed; inspect the notarytool log and confirm the DMG was accepted"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH" || \
  fail "Gatekeeper verification failed after stapling; test again on a clean macOS account or machine"

echo "Created signed and notarized distribution DMG: $DMG_PATH"
