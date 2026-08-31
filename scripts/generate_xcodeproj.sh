#!/usr/bin/env bash
# Generate xcode/AgentNotch.xcodeproj from xcode/project.yml.
#
# The project file is not committed: Xcode is only how the release .app is
# built, not how the app is developed, and a generated pbxproj in review diffs
# earns nothing. `project.yml` is the source of truth and this script is the
# only thing that turns it into a project.
#
#   ./scripts/generate_xcodeproj.sh                           # a local build
#   ./scripts/generate_xcodeproj.sh --build-version 1.2.3 --build-number 7
#
# The version lands in CFBundleShortVersionString and the build number in
# CFBundleVersion, both through build settings that Info.plist expands.
set -euo pipefail

cd "$(dirname "$0")/.."

# 0.0.0 marks a bundle that did not come from build_release.sh, so a local
# build can never be mistaken for a release.
build_version="0.0.0"
build_number="1"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-version)
      build_version="${2:-}"
      shift 2
      ;;
    --build-number)
      build_number="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$build_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "--build-version must use the form 1.2.3" >&2
  exit 1
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "--build-number must be a positive integer" >&2
  exit 1
fi

# mise owns the pinned XcodeGen in mise.toml. A copy already on PATH is used as
# is, so the script works on a machine that installed it some other way.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen() { command xcodegen "$@"; }
elif command -v mise >/dev/null 2>&1; then
  xcodegen() { mise x -- xcodegen "$@"; }
else
  echo "XcodeGen is required. Install mise and run 'mise install'," >&2
  echo "or install XcodeGen directly: brew install xcodegen" >&2
  exit 1
fi

export XCODEGEN_AGENT_NOTCH_VERSION="$build_version"
export XCODEGEN_AGENT_NOTCH_BUILD_NUMBER="$build_number"

cd xcode
xcodegen --quiet
echo "✓ xcode/AgentNotch.xcodeproj ($build_version build $build_number)"
