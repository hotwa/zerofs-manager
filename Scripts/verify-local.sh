#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

swift build
swift run ZeroFSManagerChecks

echo "XCTest/Swift Testing modules are not available in this Command Line Tools environment; ZeroFSManagerChecks is the local test runner for this scaffold."

"$PROJECT_ROOT/Scripts/build-app.sh"
"$PROJECT_ROOT/Scripts/verify-bundle.sh" "$PROJECT_ROOT/dist/ZeroFS Manager.app"
openspec validate build-distributable-zerofs-manager --strict

echo "Local verification passed"
