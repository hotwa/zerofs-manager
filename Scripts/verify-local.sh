#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

swift build
swift test
swift run ZeroFSProbeTests
swift run ZeroFSManagerChecks

echo "SwiftPM tests, probe regression tests, and project checks passed."

"$PROJECT_ROOT/Scripts/build-app.sh"
"$PROJECT_ROOT/Scripts/verify-bundle.sh" "$PROJECT_ROOT/dist/ZeroFS Manager.app"
openspec validate build-distributable-zerofs-manager --strict

echo "Local verification passed"
