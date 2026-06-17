#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_NAME="${APP_NAME:-ZeroFS Manager}"
BUNDLE_ID="${BUNDLE_ID:-com.zerofs.manager}"
DIST_DIR="${DIST_DIR:-"$PROJECT_ROOT/dist"}"
APP_PATH="$DIST_DIR/$APP_NAME.app"
APP_ICON="$PROJECT_ROOT/Resources/App/ZeroFSManager.icns"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration|-c)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --app-path)
      APP_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "CONFIGURATION must be debug or release; got: $CONFIGURATION" >&2
  exit 2
fi

cd "$PROJECT_ROOT"

if [[ ! -f "$APP_ICON" ]]; then
  python3 "$PROJECT_ROOT/Scripts/generate-visual-assets.py"
fi

swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p \
  "$APP_PATH/Contents/MacOS" \
  "$APP_PATH/Contents/Resources/Scripts" \
  "$APP_PATH/Contents/Resources/docs" \
  "$APP_PATH/Contents/Resources/Entitlements" \
  "$APP_PATH/Contents/Resources/Templates" \
  "$APP_PATH/Contents/Library/LaunchDaemons"

cp "$PROJECT_ROOT/Resources/App/Info.plist" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
cp "$APP_ICON" "$APP_PATH/Contents/Resources/ZeroFSManager.icns"

cp "$BIN_PATH/ZeroFSManagerApp" "$APP_PATH/Contents/MacOS/ZeroFSManagerApp"
cp "$BIN_PATH/ZeroFSPrivilegedHelper" "$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"
chmod 755 "$APP_PATH/Contents/MacOS/ZeroFSManagerApp" "$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"

cp "$PROJECT_ROOT/Resources/LaunchDaemons/com.zerofs.manager.helper.plist" \
  "$APP_PATH/Contents/Library/LaunchDaemons/com.zerofs.manager.helper.plist"
cp "$PROJECT_ROOT/Resources/LaunchDaemons/zerofs-profile.plist.template" \
  "$APP_PATH/Contents/Resources/Templates/zerofs-profile.plist.template"
cp "$PROJECT_ROOT/Resources/Templates/zerofs.toml.template" \
  "$APP_PATH/Contents/Resources/Templates/zerofs.toml.template"
cp "$PROJECT_ROOT/Resources/Templates/zerofs.env.template" \
  "$APP_PATH/Contents/Resources/Templates/zerofs.env.template"
cp "$PROJECT_ROOT/Resources/Entitlements/"*.entitlements \
  "$APP_PATH/Contents/Resources/Entitlements/"
for script in manual-mount-test.sh manual-performance-test.sh manual-install-launchdaemon-debug.sh manual-uninstall-launchdaemon-debug.sh inspect-signature.sh; do
  if [[ -f "$PROJECT_ROOT/Scripts/$script" ]]; then
    cp "$PROJECT_ROOT/Scripts/$script" "$APP_PATH/Contents/Resources/Scripts/$script"
    chmod 755 "$APP_PATH/Contents/Resources/Scripts/$script"
  fi
done
cp "$PROJECT_ROOT/docs/troubleshooting.md" "$APP_PATH/Contents/Resources/docs/troubleshooting.md"
cp "$PROJECT_ROOT/LICENSE" "$APP_PATH/Contents/Resources/LICENSE.txt"

printf "APPL????" > "$APP_PATH/Contents/PkgInfo"

if [[ "${ADHOC_SIGN:-1}" == "1" ]]; then
  codesign --force --deep --sign - "$APP_PATH" >/dev/null
fi

"$PROJECT_ROOT/Scripts/verify-bundle.sh" "$APP_PATH"
echo "Built $APP_PATH"
echo "ZeroFS is an external dependency; the app will detect zerofs on PATH at runtime."
