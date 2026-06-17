#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-"$PROJECT_ROOT/dist/ZeroFS Manager.app"}"
DMG_PATH="${DMG_PATH:-"$PROJECT_ROOT/dist/ZeroFS-Manager-distribution.dmg"}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-}}"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "$NOTARY_PROFILE" || -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Official release signing is unavailable because Developer ID is not configured."
  echo "Skipping official release path."
  exit 0
fi

codesign --verify --deep --strict --verbose=4 "$APP_PATH"
spctl -a -vv "$APP_PATH"
if [[ -f "$DMG_PATH" ]]; then
  spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
fi
