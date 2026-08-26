#!/usr/bin/env bash
# Run every static check used by CI.
#
# swift-format catches source layout and style findings, while only the compiler
# can diagnose type-checked warnings. Treating those warnings as errors keeps
# them in the Lint step with the compiler's normal file/line/code-frame output.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/swift-format.sh lint
swift build --build-tests -Xswiftc -warnings-as-errors
