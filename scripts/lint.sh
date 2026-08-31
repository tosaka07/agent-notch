#!/usr/bin/env bash
# Run every static check used by CI.
#
# swift-format catches source layout and style findings, while only the compiler
# can diagnose type-checked warnings. Treating those warnings as errors keeps
# them in the Lint step with the compiler's normal file/line/code-frame output.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/swift-format.sh lint

# `Bundle.module` must never reach the sources.
#
# SwiftPM's generated accessor looks for the resource bundle directly under
# `Bundle.main.bundleURL` and then at the absolute build path baked in at
# compile time. Inside a `.app` neither holds, so it resolves to the build
# directory on the machine that compiled the binary and traps everywhere else —
# a crash that only appears once someone else runs the shipped app. Resource
# lookups go through `ResourceBundle` instead.
#
# Comment lines are excluded so the explanation above can name the thing it bans.
# `\b` is spelled out as an explicit character class because git's regex engine
# does not honour it.
if git grep -nI --untracked -E '(^|[^A-Za-z0-9_])(Bundle)?\.module($|[^A-Za-z0-9_])' -- '*.swift' \
  | grep -vE '^[^:]*:[0-9]+: *//'; then
  echo "the .module resource bundle does not resolve inside a .app — use ResourceBundle instead" >&2
  exit 1
fi

swift build --build-tests -Xswiftc -warnings-as-errors
