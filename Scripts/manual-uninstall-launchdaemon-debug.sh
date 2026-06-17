#!/usr/bin/env bash
set -euo pipefail

LABEL="com.zerofs.manager.helper.debug"
PLIST_PATH="/Library/LaunchDaemons/$LABEL.plist"

echo "Removing manual launchd debug path only."
echo "This is not the official SMAppService authorization path."

sudo launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
sudo rm -f "$PLIST_PATH"
echo "Removed $LABEL"
