#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

select_xcode_for_xctest() {
  if xcrun --find xctest >/dev/null 2>&1; then
    return 0
  fi

  local default_xcode="/Applications/Xcode.app/Contents/Developer"
  if [[ -d "$default_xcode" ]]; then
    export DEVELOPER_DIR="$default_xcode"
  fi

  if ! xcodebuild -version >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Full Xcode is required for local XCTest execution.
Install Xcode, then accept its license with:
  sudo xcodebuild -license accept
EOF
    exit 1
  fi

  if ! xcrun --find xctest >/dev/null 2>&1; then
    echo "XCTest runner is unavailable even after selecting DEVELOPER_DIR=$DEVELOPER_DIR" >&2
    exit 1
  fi
}

select_xcode_for_xctest

swift build
swift test --enable-xctest
swift run ZeroFSProbeTests
swift run ZeroFSManagerChecks

echo "SwiftPM tests, probe regression tests, and project checks passed."

"$PROJECT_ROOT/Scripts/build-app.sh"
"$PROJECT_ROOT/Scripts/verify-bundle.sh" "$PROJECT_ROOT/dist/ZeroFS Manager.app"
if command -v openspec >/dev/null 2>&1; then
  openspec validate build-distributable-zerofs-manager --strict
else
  echo "openspec not found; skipping OpenSpec validation."
fi

echo "Local verification passed"
