#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${APP_PATH:-"$PROJECT_ROOT/dist/ZeroFS Manager.app"}}"
MODE="${ZEROFS_MANAGER_DISTRIBUTION_MODE:-github-dev}"

usage() {
  cat <<'USAGE'
Usage: Scripts/inspect-signature.sh ["dist/ZeroFS Manager.app"]

Inspects macOS code signing state for a dev or release app bundle.
In github-dev mode, Gatekeeper/spctl failure is reported as a warning.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -e "$APP_PATH" ]]; then
  echo "Path not found: $APP_PATH" >&2
  exit 2
fi

echo "Codesigning identities:"
security find-identity -v -p codesigning || true
echo

echo "Signature details:"
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
printf "%s\n" "$SIGNATURE_DETAILS"
echo

classification="unknown signed"
if printf "%s\n" "$SIGNATURE_DETAILS" | grep -q "code object is not signed"; then
  classification="unsigned"
elif printf "%s\n" "$SIGNATURE_DETAILS" | grep -q "Signature=adhoc"; then
  classification="ad-hoc"
elif printf "%s\n" "$SIGNATURE_DETAILS" | grep -q "Authority=Developer ID Application"; then
  classification="Developer ID Application"
elif printf "%s\n" "$SIGNATURE_DETAILS" | grep -q "Authority=Apple Development"; then
  classification="Apple Development"
elif printf "%s\n" "$SIGNATURE_DETAILS" | grep -q "Authority="; then
  classification="self-signed or non-Apple signed"
fi
echo "Signature classification: $classification"

if printf "%s\n" "$SIGNATURE_DETAILS" | grep -q "TeamIdentifier=not set"; then
  echo "No Apple TeamIdentifier. This is expected for GitHub-style dev builds and not valid for official release."
fi
echo

echo "Strict codesign verification:"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
VERIFY_STATUS=$?
echo

echo "Gatekeeper assessment:"
set +e
spctl --assess --type execute --verbose=4 "$APP_PATH"
SPCTL_STATUS=$?
set -e
if [[ "$SPCTL_STATUS" -ne 0 ]]; then
  if [[ "$MODE" == "github-dev" ]]; then
    echo "Warning: spctl assessment failed as expected for github-dev mode. This does not block dev builds."
  else
    echo "spctl assessment failed in official-release mode." >&2
    exit "$SPCTL_STATUS"
  fi
fi

exit "$VERIFY_STATUS"
