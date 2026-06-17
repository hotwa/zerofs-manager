#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/ZeroFS Manager.app}"
LABEL="com.zerofs.manager.helper.debug"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"
HELPER_PATH="$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"
TMP_PLIST="$(mktemp)"

cleanup() {
  rm -f "$TMP_PLIST"
}
trap cleanup EXIT

echo "manual launchd debug path only."
echo "This is for lower-level helper/launchd testing and is not the official SMAppService authorization path."
echo "Label: $LABEL"

[[ -x "$HELPER_PATH" ]] || {
  echo "Helper executable not found: $HELPER_PATH" >&2
  exit 2
}

cat > "$TMP_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_PATH</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ZEROFS_MANAGER_HELPER_MACH_SERVICE_NAME</key>
    <string>$LABEL</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>MachServices</key>
  <dict>
    <key>$LABEL</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

plutil -lint "$TMP_PLIST"
sudo cp "$TMP_PLIST" "$PLIST_PATH"
sudo chown root:wheel "$PLIST_PATH"
sudo chmod 644 "$PLIST_PATH"
sudo launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
sudo launchctl bootstrap system "$PLIST_PATH"
sudo launchctl print "system/$LABEL"
