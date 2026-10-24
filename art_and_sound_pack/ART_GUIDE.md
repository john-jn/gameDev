# Evac Grid: Art Guide

For the art members. Images in this folder:

| File | What it is |
|---|---|
| `asset_sheet.png` | Everything the game needs, with today's placeholder shown for each item |
| `building_sheet_spec.png` | Full spec for the connecting building and road sprites |
| `templates/building_autotile_template.png` | 512 x 640 template to paint over (one per building style) |
| `templates/road_autotile_template.png` | 512 x 512 template to paint over (street and avenue) |

Status key: **TEMP** = drawn by code as a placeholder, needs real art. **NEW** = does not exist yet.

Most map visuals are still code-drawn placeholders. The edited building sheet is now connected as the first in-game art asset.

## General rules
- PNG, transparent background (except templates), top-down view, no perspective, light from the top-left.
- Use the shared palette: BG_DARK `#0A1F23`, PANEL `#0E2C2E`, TEAL `#1C4F4E`,
  TEAL_MID `#348270`, MINT `#96F2D8`, WHITE `#EEFFFA`, CYAN `#50C8FF`,
  GREEN `#50FFAA`.
- Tiles are square. Draw at **128 x 128 per tile**; the game scales it down (a tile is about 20 to 40 px on screen).
- Texture filtering is Nearest; avoid fractional sprite sizing. UI indicators and the header logo render at their native dimensions.
- File names in lowercase with underscores.
- Put finished art in `assets/art/`.

## Map art

| # | Asset | Size | Status | Notes |
|---|---|---|---|---|
| 1 | Buildings: 5 styles x 20 connecting pieces | 512 x 640 sheet per style (128 px cells) | TEMP | Modular, so any lot shape (1x1 to 3x3, L shapes) joins seamlessly. Rules in `building_sheet_spec.png`; paint over the building template |
| 2 | Park | 256 x 256 + 128 x 128 cell | DONE | `park_v2.png` is drawn once across a rectangular 2 x 2 lot with no extra border; `park_grass_cell.png` fills other park footprints |
| 3 | Survivor markers | 64 x 64 (group A/B), 128 x 128 (fallback) | DONE | `survivor_group_a.png` and `survivor_group_b.png` identify map groups; code draws head-count badges |
| 4 | Fire | 128 x 128 frames | DONE | `fire_sheet.png` has 8 animated frames; centered smoke draws behind it and a thin dashed cyan ring marks the threat |
| 5 | Smoke | 128 x 128 frames | DONE | `smoke_overlay_sheet.png` has four looping frames at 4 fps, centered on each affected road cell below fire |
| 6 | Roads: street + avenue, 16 connecting pieces each | 512 x 512 sheet | DONE | `road_street.png` and `road_avenue.png` |
| 7 | Closed road | 128 x 128 | DONE | `closed_road.png`, striped barrier |
| 8 | Safe zone | 512 x 640 sheet + 384 x 384 overlay | PARTIAL | `safe_zone.png` overlay is connected; base building sheet is still needed |
| 9 | Route trail | 64 x 64 each | DONE | `route_start.png`, `route_straight.png`, `route_corner.png`, and `route_end_arrow.png` form the planned path, scaled to one map cell |
| 10 | Selection effects | 96 x 96 frames; 80 x 80 brackets | DONE | `pulse_ring_sheet.png` animates around the selected group; `select_brackets.png` frames the hovered tile |
| 11 | Door overlay | 128 x 32 | NEW | Front of a lot, faces south |
| 12 | Roof props x6 | 64 x 64 each | NEW | Vent, AC unit, water tank, skylight, antenna, solar panel |

## Interface art

| # | Asset | Size | Status | Notes |
|---|---|---|---|---|
| 12 | Tablet frame | 1229 x 768 | DONE | `ui/tablet_frame_slim.png`, 9-slice with 32 px margins |
| 13 | Header logo | 112 x 34 | DONE | `ui/logo_header_1x.png`, shown at native 1x size |
| 14 | App icon | 256 x 256 | DONE | `app_icon.png`, configured as the project icon |
| 15 | Buttons, 4 states | 768 x 64 sheet | DONE | `buttons_sheet.png`, four 192 x 64 nine-slice states; 20 px texture and 12 px content margins |
| 16 | Status lights | 32 x 32, 5 colours, on and off | DONE | `status_lights_sheet.png` |
| 17 | Star icons | 64 x 64, on and off | DONE | `star_icons_sheet.png`, results rating |
| 18 | Legend icons | 32 x 32 | DONE | `legend_icons_sheet.png`, fire, smoke, road, team |
| 19 | Title background | 1229 x 768 | READY | `title_background.png`; not used because there is no title screen |
| 20 | Alert icon | 64 x 64 | DONE | `alert_icon.png`, fire alert bar |
| 21 | Group indicators | 24 x 24 each | DONE | `ui/group_a_light.png` and `ui/group_b_light.png` |
| 22 | People lost indicators | 24 x 24 each | DONE | `ui/people_lost_empty.png` and `ui/people_lost_filled.png` |

## Fonts
| Asset | Status |
|---|---|
| Rajdhani Medium and Bold (UI) | DONE |
| Digital or 7-segment font for the clock and score | TEMP (uses the system monospace font) |

## Optional polish
- A sparkle when a team reaches the safe zone.

## How art plugs in (for developers)
`scripts/visual_theme.gd` has optional slots for whole-lot building textures, per-tile building autotile sheets, street and avenue road sheets, parks, survivor markers, fire, smoke, closed roads, safe zones and route arrows. An empty slot draws the code-made shape; a filled slot uses the art. The current art is assigned through `assets/art/dispatch_theme.tres`.

Building and road autotile sheets are drawn one piece per tile. Building sheets also support inner-corner overlays. Fire sprite sheets animate; smoke sheets provide tile-to-tile variants. Optional trees and roof props are not wired up yet.

## Checklist
- [ ] Building sheets, 5 styles (100 pieces)
- [ ] Park and safe zone sheets
- [x] Street and avenue road sheets
- [x] Survivor marker, fire, smoke, closed road
- [ ] Door overlay, roof props, trees
- [x] Logo and app icon
- [x] Slim tablet frame and native-size team/loss indicators
- [x] Buttons, lights, stars, icons
