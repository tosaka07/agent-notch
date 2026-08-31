#!/usr/bin/env bash
# Draw the raster artwork.
#
# `scripts/make_icon_layers.swift` draws it from the same formula as
# `Glyph.ringCellIndices`. There is no logo-specific drawing rule: it is just the
# ring with the middle 5 cells of the top edge removed.
#
#   ./scripts/make_icons.sh
#     -> Resources/AppIcon/{icon-1024,layer-foreground,layer-background}.png
#
# # This is no longer the app icon
# The app icon is `Resources/AppIcon/AgentNotch.icon`, compiled by Xcode via `build_app.sh`;
# its layers are the SVGs in `Resources/AppIcon/layers/`. This script survives
# because `icon-1024.png` is the logo in README.md, and because drawing the mark
# from the same formula as the UI keeps a check on the hand-authored SVGs.
#
# The AppIcon.icns it used to assemble is gone: a single flat image cannot vary by
# dark/clear/tinted, which is exactly what the .icon exists to do.
set -euo pipefail

cd "$(dirname "$0")/.."
out="Resources/AppIcon"
mkdir -p "$out"

echo "▸ drawing layers"
swift scripts/make_icon_layers.swift "$out"

echo "✓ $out/icon-1024.png"
