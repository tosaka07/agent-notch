#!/usr/bin/env bash
# Run swift-format over the project's Swift sources.
#
#   ./scripts/swift-format.sh format          # rewrite in place
#   ./scripts/swift-format.sh lint            # check only, non-zero on findings
#   ./scripts/swift-format.sh format FILE...  # limit to specific files
#   ./scripts/swift-format.sh lint FILE...
#
# swift-format ships with the Swift 6 toolchain, so there is nothing to install:
# it is invoked as `swift format` (with a space). Pinning it to the toolchain
# also means CI and local runs cannot drift to different formatter versions.
#
# `.build` and other generated trees are excluded by listing the source
# directories explicitly — swift-format has no ignore-file mechanism.
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:-lint}"
shift || true

sources=("$@")
if [ ${#sources[@]} -eq 0 ]; then
  sources=(AgentNotch AgentNotchApp AgentNotchCore AgentNotchCLI AgentNotchTests Package.swift)
fi

case "$mode" in
  format)
    swift format --in-place --parallel --recursive "${sources[@]}"
    ;;
  lint)
    # --strict turns findings into a non-zero exit so CI and the git hook fail.
    swift format lint --strict --parallel --recursive "${sources[@]}"
    ;;
  *)
    echo "usage: $0 {format|lint} [files...]" >&2
    exit 2
    ;;
esac
