# App icon layers (Icon Composer source)

Group **A · 前景レイヤー（透明背景）** of the `App Icon Layers` design doc, one file per layer, for
assembling the icon in Icon Composer.

Imported from the Claude Design project
`56ba0959-1e3d-4821-b3aa-7cc2fe8f9141` (`assets/app-icon/`). Filenames are kept as-is so a layer
here can be traced back to the design doc.

These are **hand-authored source**, not build output — `scripts/make_icons.sh` does not regenerate
them. It draws its own `layer-foreground.png` / `layer-background.png` from
`scripts/make_icon_layers.swift`, which is a separate, PNG-based path to the same artwork.

## Geometry

Every file is 1024×1024 with an identical `viewBox`, and all coordinates are integer multiples of
the 13×13 grid, so layers line up exactly when stacked — no alignment step in Icon Composer.

| | cell | pitch | note |
|---|---|---|---|
| `01`, `02`, `03` | 32 | 48 | dots (32 dot + 16 gap) |
| `04`, `05` | 48 | 48 | solid, gapless |

## The layers

| file | fill | what it is |
|---|---|---|
| `01-layer-ring.svg` | `#FFFFFF` | the ring, with the middle 5 cells of the top edge removed — that gap *is* the notch |
| `02-layer-core.svg` | `#FFFFFF` | the centre 3×3 pupil |
| `03-layer-notch-cut.svg` | `#EC3013` | the 5 removed cells, plus one row above, filled in accent red |
| `04-layer-solid.svg` | `#FFFFFF` | gapless disc — the small-size substitute, because the ring's dots close up below ~32 px |
| `05-layer-solid-notch-cut.svg` | `#EC3013` | the notch block for the solid disc |

`01`+`02`+`03` and `04`+`05` are **alternatives, not a single stack**: the first is the dots
treatment, the second the solid one.

## Stacking

Reproduced from the project's own composed 1024 files (`20`–`22`), bottom to top:

| variant | plate | layers |
|---|---|---|
| dark (`20`) | `#0E0E10` | `01` at `#FFFFFF`, then `02` at `#FFFFFF` **opacity 0.35** |
| light (`22`) | `#F3F2F2` | `01` at `#201E1D`, then `02` at `#201E1D` **opacity 0.35** |
| red (`21`) | `#EC3013` | `04` at `#FFFFFF` only — no core, no notch layer |

Two things do not survive in the layer files and have to be set in Icon Composer:

- **`02-layer-core.svg` ships at full opacity.** Every composed variant draws it at **35%**. Left at
  100% the pupil reads as a solid block instead of a recessed centre.
- **Only the dark variant's colours are baked in.** The light variant recolours `01`/`02` to
  `#201E1D`; there is no separate ink-coloured layer file.

None of `20`–`22` use `03` or `05`. In the shipped compositions the notch is negative space, showing
the plate through the gap. The red notch layers exist for a composition that wants the notch called
out on a non-red plate.
