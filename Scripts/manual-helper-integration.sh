#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/ZeroFS Manager.app}"
LABEL="${LABEL:-com.zerofs.manager.helper}"
HELPER_PATH="$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"
PLIST_PATH="$APP_PATH/Contents/Library/LaunchDaemons/$LABEL.plist"

echo "Manual helper integration checklist"
echo "App: $APP_PATH"
echo "Label: $LABEL"
echo

[[ -d "$APP_PATH" ]] || {
  echo "Install the app into /Applications before testing SMAppService registration." >&2
  exit 2
}
[[ -x "$HELPER_PATH" ]] || {
  echo "Missing helper executable: $HELPER_PATH" >&2
  exit 2
}
[[ -f "$PLIST_PATH" ]] || {
  echo "Missing helper plist: $PLIST_PATH" >&2
  exit 2
}

plutil -lint "$PLIST_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true
"$HELPER_PATH" --health

echo
echo "Launch the app, trigger helper install/update, and approve it in:"
echo "System Settings > General > Login Items & Extensions"
echo
echo "After approval, inspect launchd and XPC service state:"
launchctl print "system/$LABEL" || true
log show --style compact --last 10m --predicate 'process == "ZeroFSPrivilegedHelper"' || true
