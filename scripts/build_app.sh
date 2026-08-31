#!/usr/bin/env bash
# Assemble build/AgentNotch.app with Xcode.
#
# Xcode builds the shipped bundle, not `swift build`. SwiftPM's generated
# resource accessor looks for a package's resource bundle directly under
# Bundle.main.bundleURL and then at the absolute build directory of the machine
# that compiled it. Inside a .app the first cannot exist — bundles placed at the
# app root fail codesign with "unsealed contents present in the bundle root" —
# and the second exists only for whoever built it. A SwiftPM-built .app
# therefore resolves resources on the build machine and traps on launch
# everywhere else, dependencies included, and those cannot be patched. Xcode's
# accessor searches Bundle.main.resourceURL and has none of this problem.
#
#   ./scripts/build_app.sh                  # debug
#   ./scripts/build_app.sh release
#   ./scripts/build_app.sh release --build-version 1.2.3 --build-number 7
#
# Output: build/AgentNotch.app, with the agent-notch CLI embedded in
# Contents/MacOS where the installed hooks expect it.
#
# This script stops at an unsigned bundle. build_release.sh signs, notarizes,
# staples, and packages. Never distribute build/AgentNotch.app directly.
set -euo pipefail

cd "$(dirname "$0")/.."

configuration="Debug"
case "${1:-debug}" in
  debug) configuration="Debug"; shift || true ;;
  release) configuration="Release"; shift || true ;;
  --*) ;;
  *)
    echo "Unknown configuration: $1 (expected debug or release)" >&2
    exit 1
    ;;
esac

app="build/AgentNotch.app"
derived="xcode/.xcode-build"

./scripts/generate_xcodeproj.sh "$@"

echo "▸ xcodebuild -configuration $configuration"
rm -rf "$derived"
(
  cd xcode
  xcodebuild clean build \
    -scheme AgentNotchApp \
    -destination "generic/platform=macOS" \
    -configuration "$configuration" \
    -derivedDataPath .xcode-build
)

rm -rf "$app"
mkdir -p "$(dirname "$app")"
ditto "$derived/Build/Products/$configuration/AgentNotch.app" "$app"

echo "✓ $app"
echo "  open $app"
