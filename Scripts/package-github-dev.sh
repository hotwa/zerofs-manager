#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-"$PROJECT_ROOT/dist"}"
CONFIGURATION="${CONFIGURATION:-release}"
SIGNING_MODE="${SIGNING_MODE:-adhoc}"
APP_PATH="$DIST_DIR/ZeroFS Manager.app"
ZIP_PATH="$DIST_DIR/ZeroFS-Manager-dev-$SIGNING_MODE.zip"
DMG_PATH="$DIST_DIR/ZeroFS-Manager-dev-$SIGNING_MODE.dmg"
STAGING="$DIST_DIR/github-dev-staging"

# Default ad-hoc output: ZeroFS-Manager-dev-adhoc.dmg

usage() {
  cat <<'USAGE'
Usage: Scripts/package-github-dev.sh

Builds GitHub-style development artifacts:
- dist/ZeroFS Manager.app
- dist/ZeroFS-Manager-dev-adhoc.zip
- dist/ZeroFS-Manager-dev-adhoc.dmg

Environment:
  CONFIGURATION=release|debug
  SIGNING_MODE=adhoc|unsigned
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$SIGNING_MODE" != "adhoc" && "$SIGNING_MODE" != "unsigned" ]]; then
  echo "SIGNING_MODE must be adhoc or unsigned; got: $SIGNING_MODE" >&2
  exit 2
fi

export CONFIGURATION
if [[ "$SIGNING_MODE" == "unsigned" ]]; then
  ADHOC_SIGN=0 VERIFY_CODESIGN=0 "$PROJECT_ROOT/Scripts/build-app.sh" --configuration "$CONFIGURATION"
else
  "$PROJECT_ROOT/Scripts/build-app.sh" --configuration "$CONFIGURATION"
  "$PROJECT_ROOT/Scripts/sign-app-adhoc.sh" "$APP_PATH"
fi

if [[ "$SIGNING_MODE" == "unsigned" ]]; then
  VERIFY_CODESIGN=0 "$PROJECT_ROOT/Scripts/verify-bundle.sh" "$APP_PATH"
else
  "$PROJECT_ROOT/Scripts/verify-bundle.sh" "$APP_PATH"
fi

rm -f "$ZIP_PATH" "$DMG_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$PROJECT_ROOT/LICENSE" "$STAGING/LICENSE.txt"
cat > "$STAGING/README-GITHUB-DEV.txt" <<'README'
This is a GitHub-style development build.
It is not signed with Apple Developer ID.
macOS Gatekeeper may block it.
For development/testing only.

The app includes reviewed helper scripts inside the app bundle and opens them
from the UI when a technical user chooses manual sudo workflows.

Technical users can remove quarantine for local development testing:

xattr -dr com.apple.quarantine "/Applications/ZeroFS Manager.app"
open "/Applications/ZeroFS Manager.app"

This is not official user-facing installation guidance and does not replace
Developer ID signing, notarization, stapling, or SMAppService approval testing.
ZeroFS itself is not bundled; install it separately.
ZeroFS Manager is licensed under Apache License 2.0; see LICENSE.txt.
README

hdiutil create \
  -volname "ZeroFS Manager Dev" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "GitHub-style development build outputs:"
echo "  App: $APP_PATH"
echo "  Zip: $ZIP_PATH"
echo "  DMG: $DMG_PATH"
