#!/usr/bin/env bash
set -euo pipefail

LABEL="${1:-com.zerofs.manager.helper}"
APP_PATH="${APP_PATH:-/Applications/ZeroFS Manager.app}"
HELPER_PATH="$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"

echo "launchctl system status for $LABEL"
launchctl print "system/$LABEL" || true

echo
echo "bundle helper health check"
if [[ -x "$HELPER_PATH" ]]; then
  "$HELPER_PATH" --health || true
else
  echo "helper executable not found at $HELPER_PATH"
fi

echo
echo "signature state"
if [[ -e "$APP_PATH" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true
else
  echo "app bundle not found at $APP_PATH"
fi

echo
echo "recent helper logs"
log show --style compact --last 30m --predicate 'process == "ZeroFSPrivilegedHelper"' || true

echo
echo "XPC connectivity requires a registered and approved Mach service named $LABEL."
echo "Background item state may also require user approval in System Settings > General > Login Items & Extensions."
