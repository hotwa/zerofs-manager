#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-"$PROJECT_ROOT/dist/ZeroFS Manager.app"}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
HELPER_PLIST="$APP_PATH/Contents/Library/LaunchDaemons/com.zerofs.manager.helper.plist"

fail() {
  echo "Bundle verification failed: $*" >&2
  exit 1
}

[[ -d "$APP_PATH" ]] || fail "missing app bundle: $APP_PATH"
[[ -x "$APP_PATH/Contents/MacOS/ZeroFSManagerApp" ]] || fail "missing main executable"
[[ -x "$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper" ]] || fail "missing helper executable"
[[ -x "$APP_PATH/Contents/MacOS/ZeroFSProbeTool" ]] || fail "missing background probe executable"
[[ ! -e "$APP_PATH/Contents/Resources/zerofs/zerofs" ]] || fail "ZeroFS must not be embedded in the GUI bundle"
[[ -f "$APP_PATH/Contents/Info.plist" ]] || fail "missing Info.plist"
[[ -f "$APP_PATH/Contents/Resources/ZeroFSManager.icns" ]] || fail "missing app icon"
[[ -f "$HELPER_PLIST" ]] || fail "missing helper LaunchDaemon plist"
[[ -f "$APP_PATH/Contents/Resources/Entitlements/ZeroFSManagerApp.distribution.entitlements" ]] || fail "missing distribution app entitlements"
[[ -f "$APP_PATH/Contents/Resources/Entitlements/ZeroFSPrivilegedHelper.entitlements" ]] || fail "missing helper entitlements"

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
plutil -lint "$HELPER_PLIST" >/dev/null

MAIN_EXEC="$("$PLIST_BUDDY" -c "Print :CFBundleExecutable" "$APP_PATH/Contents/Info.plist")"
APP_ICON="$("$PLIST_BUDDY" -c "Print :CFBundleIconFile" "$APP_PATH/Contents/Info.plist")"
BUNDLE_ID="$("$PLIST_BUDDY" -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")"
[[ "$MAIN_EXEC" == "ZeroFSManagerApp" ]] || fail "unexpected CFBundleExecutable: $MAIN_EXEC"
[[ "$APP_ICON" == "ZeroFSManager" ]] || fail "unexpected CFBundleIconFile: $APP_ICON"

if [[ "${VERIFY_CODESIGN:-1}" == "1" ]]; then
  [[ -f "$APP_PATH/Contents/_CodeSignature/CodeResources" ]] || fail "missing signed resource seal"
  if ! codesign --verify --deep --strict --verbose=4 "$APP_PATH"; then
    fail "strict codesign verification failed"
  fi
  SIGNING_IDENTIFIER="$(codesign -dv "$APP_PATH" 2>&1 | awk -F= '/^Identifier=/{print $2; exit}')"
  [[ "$SIGNING_IDENTIFIER" == "$BUNDLE_ID" ]] || fail "unexpected signing identifier: $SIGNING_IDENTIFIER"
fi

LABEL="$("$PLIST_BUDDY" -c "Print :Label" "$HELPER_PLIST")"
BUNDLE_PROGRAM="$("$PLIST_BUDDY" -c "Print :BundleProgram" "$HELPER_PLIST")"
MACH_SERVICE="$("$PLIST_BUDDY" -c "Print :MachServices:com.zerofs.manager.helper" "$HELPER_PLIST")"
ASSOCIATED="$("$PLIST_BUDDY" -c "Print :AssociatedBundleIdentifiers:0" "$HELPER_PLIST")"

[[ "$LABEL" == "com.zerofs.manager.helper" ]] || fail "unexpected helper label: $LABEL"
[[ "$BUNDLE_PROGRAM" == "Contents/MacOS/ZeroFSPrivilegedHelper" ]] || fail "BundleProgram must be bundle-relative helper path"
[[ "$MACH_SERVICE" == "true" ]] || fail "missing MachServices entry for helper"
[[ "$ASSOCIATED" == "com.zerofs.manager" ]] || fail "unexpected AssociatedBundleIdentifiers value: $ASSOCIATED"

if grep -R -E "secret-value|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY" "$APP_PATH/Contents" >/dev/null; then
  fail "bundle contains a known secret fixture"
fi

echo "Bundle verification passed: $APP_PATH"
