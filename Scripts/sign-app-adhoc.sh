#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-"$PROJECT_ROOT/dist/ZeroFS Manager.app"}}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 2
fi

echo "Ad-hoc signing GitHub-style dev build:"
echo "  $APP_PATH"
echo "This is not Developer ID signing and will not make Gatekeeper treat the app as an official release."

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"

echo "Ad-hoc signature verified for dev build."
