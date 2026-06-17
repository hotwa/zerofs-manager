#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-"$PROJECT_ROOT/dist/ZeroFS Manager.app"}}"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Official release signing is unavailable because Developer ID is not configured."
  echo "Skipping official release path."
  exit 0
fi

APP_ENTITLEMENTS="$PROJECT_ROOT/Resources/Entitlements/ZeroFSManagerApp.distribution.entitlements"
HELPER_ENTITLEMENTS="$PROJECT_ROOT/Resources/Entitlements/ZeroFSPrivilegedHelper.entitlements"

[[ -d "$APP_PATH" ]] || "$PROJECT_ROOT/Scripts/build-app.sh" --configuration release

codesign --force --timestamp --options runtime --entitlements "$HELPER_ENTITLEMENTS" --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH/Contents/MacOS/ZeroFSPrivilegedHelper"
codesign --force --timestamp --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH/Contents/MacOS/ZeroFSManagerApp"
codesign --force --timestamp --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
