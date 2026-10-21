# Evac Grid: Art Guide

For the art members. Images in this folder:

| File | What it is |
|---|---|
| `asset_sheet.png` | Everything the game needs, with today's placeholder shown for each item |
| `building_sheet_spec.png` | Full spec for the connecting building and road sprites |
| `templates/building_autotile_template.png` | 512 x 640 template to paint over (one per building style) |
| `templates/road_autotile_template.png` | 512 x 512 template to paint over (street and avenue) |

Status key: **TEMP** = drawn by code as a placeholder, needs real art. **NEW** = does not exist yet.

The game currently has **no image art**. Everything on the map is drawn by code (`scripts/map_painter.gd`). The only real files are the UI font (Rajdhani, open licence) and one reference image (`assets/dispatch_map_ref.png`).

## General rules
- PNG, transparent background (except templates), top-down view, no perspective, light from the top-left.
- Match the map's look: dark teal and cyan outlines on a dark background.
- Tiles are square. Draw at **128 x 128 per tile**; the game scales it down (a tile is about 20 to 40 px on screen).
- File names in lowercase with underscores.
- Put finished art in `assets/art/`.

## Map art

| # | Asset | Size | Status | Notes |
|---|---|---|---|---|
| 1 | Buildings: 5 styles x 20 connecting pieces | 512 x 640 sheet per style (128 px cells) | TEMP | Modular, so any lot shape (1x1 to 3x3, L shapes) joins seamlessly. Rules in `building_sheet_spec.png`; paint over the building template |
| 2 | Park | 512 x 640 sheet | TEMP | Same layout as buildings. Grass and paths. Trees x3 as separate 64 x 64 sprites |
| 3 | Survivor marker | 128 x 128 | TEMP | People or a yellow pin. The head count badge is drawn by code |
| 4 | Fire | 128 x 128, 4 to 6 frames | TEMP | Flickering flames on a road tile |
| 5 | Smoke | 128 x 128, 2 to 3 variants | TEMP | Soft grey overlay for tiles next to a fire |
| 6 | Roads: street + avenue, 16 connecting pieces each | 512 x 512 sheet | TEMP | Paint over the road template |
| 7 | Closed road | 128 x 128 | TEMP | Striped barrier or rubble |
| 8 | Safe zone | 512 x 640 sheet + 384 x 384 overlay | TEMP | Same layout as buildings, plus a green cross and helipad overlay |
| 9 | Route arrow | 64 x 64 | TEMP | Optional; the route is a drawn line today |
| 10 | Door overlay | 128 x 32 | NEW | Front of a lot, faces south |
| 11 | Roof props x6 | 64 x 64 each | NEW | Vent, AC unit, water tank, skylight, antenna, solar panel |

## Interface art

| # | Asset | Size | Status | Notes |
|---|---|---|---|---|
| 12 | Tablet frame | 1280 x 800 | TEMP | Code-drawn today. Optional real frame (9-slice border) |
| 13 | Logo "EVAC GRID" | 512 x 128 | NEW | Title screen and top bar |
| 14 | App icon | 256 x 256 | TEMP | `icon.svg` is still the Godot default |
| 15 | Buttons, 4 states | 9-slice | TEMP | Normal, hover, pressed, disabled. The dispatch button needs a clear big green look |
| 16 | Status lights | 32 x 32, 5 colours, on and off | TEMP | Code-drawn circles today |
| 17 | Star icons | 64 x 64, on and off | TEMP | Results rating |
| 18 | Legend icons | 32 x 32 | TEMP | Fire, smoke, road, safe zone, team |
| 19 | Title background | 1280 x 800 | NEW | There is no title screen yet |
| 20 | Alert icon | 64 x 64 | NEW | Warning triangle for the fire alert bar |

## Fonts
| Asset | Status |
|---|---|
| Rajdhani Medium and Bold (UI) | DONE |
| Digital or 7-segment font for the clock and score | TEMP (uses the system monospace font) |

## Optional polish
- Fire glow and spark particles.
- A sparkle when a team reaches the safe zone.
- A red flash when a route is blocked.

## How art plugs in (for developers)
`scripts/visual_theme.gd` has four optional slots: `building_textures`, `park_texture`, `survivor_texture`, `fire_texture`. An empty slot draws the code-made shape; a filled slot uses the art. Make a theme `.tres`, fill the slots and set it as **Visual Theme Override** on the game scene.

**Developer task:** the game currently stretches ONE texture over a whole lot. The connecting building and road sheets need a small change in `MapPainter.draw_lot` (and new slots for roads, smoke, closed road and safe zone) to place one piece per tile.

## Checklist
- [ ] Building sheets, 5 styles (100 pieces)
- [ ] Park and safe zone sheets
- [ ] Street and avenue road sheets
- [ ] Survivor marker, fire, smoke, closed road
- [ ] Door overlay, roof props, trees
- [ ] Logo and app icon
- [ ] Buttons, lights, stars, icons (optional)
