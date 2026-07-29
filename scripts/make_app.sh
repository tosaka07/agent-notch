#!/usr/bin/env bash
# Assemble the distributable .app bundle.
#
# `swift build` only produces a bare executable, with no Info.plist and no icon
# (so no icon in the Dock or Finder, and LSUIElement has no effect). This script
# wraps it into a proper bundle.
#
# The icon comes from `Resources/AppIcon/AgentNotch.icon`, the Icon Composer document.
# SwiftPM cannot compile it, so `actool` is invoked here — this script is the only
# place the app icon is produced.
#
#   ./scripts/make_app.sh            # release build
#   ./scripts/make_app.sh debug      # debug build (for launch checks)
#
# Output: build/AgentNotch.app
#
# The bundle is neither signed nor notarized, so Gatekeeper will block it. On
# first launch, right-click the app in Finder and choose Open to allow it.
set -euo pipefail

cd "$(dirname "$0")/.."
config="${1:-release}"
app="build/AgentNotch.app"
distribution="development"
if [ "$config" = "release" ]; then
  distribution="production"
fi

echo "▸ swift build -c $config"
swift build -c "$config" --product AgentNotch
binary="$(swift build -c "$config" --product AgentNotch --show-bin-path)/AgentNotch"

# Bundle the CLI that installs the hooks as well. If the hooks pointed at
# .build outside the bundle, every hook would break the moment the build is
# cleaned.
echo "▸ swift build -c $config --product agent-notch"
swift build -c "$config" --product agent-notch
cli="$(swift build -c "$config" --product agent-notch --show-bin-path)/agent-notch"

echo "▸ assembling bundle"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/AgentNotch"
cp "$cli" "$app/Contents/MacOS/agent-notch"

# Compile the Icon Composer document straight into the bundle.
#
# `actool` emits two things from one .icon, and the bundle needs both: `Assets.car`
# carries the layered icon that macOS renders with Liquid Glass (adapting to
# dark/clear/tinted), and `AgentNotch.icns` is the flat fallback for anything that
# only understands the old format — Finder's list view, for one.
#
# actool reports failures as a plist on stdout and does not always exit non-zero,
# so the output is only surfaced when the expected files are missing.
echo "▸ compiling AgentNotch.icon"
icon_plist="$(mktemp -t agentnotch-icon-plist)"
icon_log="$(mktemp -t agentnotch-icon-log)"
xcrun actool Resources/AppIcon/AgentNotch.icon \
  --compile "$app/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AgentNotch \
  --output-partial-info-plist "$icon_plist" \
  >"$icon_log" 2>&1 || true
if [ ! -f "$app/Contents/Resources/Assets.car" ] \
  || [ ! -f "$app/Contents/Resources/AgentNotch.icns" ]; then
  echo "actool did not produce the icon:" >&2
  cat "$icon_log" >&2
  exit 1
fi
rm -f "$icon_plist" "$icon_log"

# Carry over the resource bundles SPM generates (sounds, etc.).
for bundle in "$(dirname "$binary")"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$app/Contents/Resources/"
done

# Use the repository's Info.plist and only add the icon reference.
#
# Both keys are required and are not interchangeable: CFBundleIconFile points at the
# .icns fallback, while CFBundleIconName names the icon inside Assets.car and is what
# gets the Liquid Glass treatment. With only the former the app silently falls back to
# the flat icon. These are the two keys actool writes into its partial Info.plist.
cp AgentNotch/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AgentNotch" "$app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AgentNotch" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AgentNotch" "$app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AgentNotch" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable AgentNotch" "$app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string AgentNotch" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :AgentNotchDistributionChannel $distribution" "$app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :AgentNotchDistributionChannel string $distribution" "$app/Contents/Info.plist"

# Nudge Finder into picking up the new icon.
touch "$app"

echo "✓ $app"
if [ "$distribution" = "production" ]; then
  echo "  release packaging must expose Contents/MacOS/agent-notch on PATH as agent-notch"
fi
echo "  open $app"
