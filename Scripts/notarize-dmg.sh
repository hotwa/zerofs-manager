#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:-${DMG_PATH:-"$PROJECT_ROOT/dist/ZeroFS-Manager-distribution.dmg"}}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${NOTARY_KEYCHAIN_PROFILE:-}}"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "$NOTARY_PROFILE" || -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Official release signing is unavailable because Developer ID is not configured."
  echo "Skipping official release path."
  exit 0
fi

[[ -f "$DMG_PATH" ]] || {
  echo "DMG not found: $DMG_PATH" >&2
  exit 2
}

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
