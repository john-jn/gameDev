# UI Update: Tablet Look and Easier Controls

## What changed (the simple version)

- **Slim tablet frame.** The game uses a 32 px nine-slice frame and a 20 px content inset.
- **Control-panel style.** The side panel is split into small boxes with lights, like the bomb in *Keep Talking and Nobody Explodes*.
- **Less reading, more looking.**
  - Team rows use native-size team icons; text still shows each team's state.
  - The route box shows one short line, like "Route ready! 18 tiles, 100% direct".
  - Native-size empty/filled sprites show people lost.
- **Bigger DISPATCH button.** It pulses in mint and white when your route is ready.
- **Clock and score look like digital screens.** The clock and score are larger; score changes count up and show a short points popup.
- **Shared palette and pixel filtering.** UI colors are centralized in `scripts/ui_colors.gd`, exposed through the compatible `UiPalette` autoload, and applied with `ui_theme.tres`; texture filtering is Nearest.
- **New font.** The whole game uses Rajdhani, a squared, techy font.
- **Easier words.** "Hazard response" is now "Quick detours". Team states say things like "needs a route".
- **Help is hidden.** The legend and key list are behind a **? LEGEND / KEYS** button.
- **Slower fires in Round 1.** There are only 3 fires. The first one comes after about 11 to 14 seconds, and the rest come every 9 to 14 seconds. Later rounds get faster.
- **New results screen.** It shows a success/failure banner, "8 / 9" people saved with one light per person, a 3-light rating, the score lines, and a big round score.
- **Fire alert bar.** It is shorter and has a blinking light.

Nothing about how the game plays changed, except the slower fires in the early rounds.

---

# Technical Report

## Summary

A UI reskin of `scripts/game.gd` and map presentation, plus shared palette and UI sprite assets. Map generation, pathfinding, route validation and the scoring formulas are unchanged. Only the score *labels* changed.

## Files

| File | Change |
|---|---|
| `scripts/game.gd` | Builds the slim nine-slice frame, native-size logo/team/loss sprites, and palette-styled controls |
| `scripts/ui_palette.gd` (new) | Shared UI/map palette and dimmed-map tint |
| `scripts/ui_widgets.gd` | Palette-based `UiWidgets.Screw`, `Led`, and `Lcd` |
| `assets/fonts/Rajdhani-Medium.ttf`, `Rajdhani-Bold.ttf` (new) | UI font (SIL OFL) |
| `scripts/hazard_manager.gd` | Gentler, round-scaled fire schedule |
| `scripts/score_keeper.gd` | Plain-language labels in `breakdown()` |
| `tests/test_generation.gd` | Retry button text check now expects `TRY AGAIN` |
| `EVAC_GRID.md` | Hazard schedule description updated |

## UI structure (`game.gd`)

- **Frame:** a full-rect `NinePatchRect` uses `ui/tablet_frame_slim.png` with 32 px margins. The content sits 20 px inside the frame.
- **Theme:** `_build_ui` sets a `Theme` on the root with Rajdhani Medium as the default font (size 16) and Rajdhani Bold for `Button` (size 18). If the font files fail to load, the theme falls back to the engine default. `_label` adds +2 to every requested font size because the face runs small.
- **Top bar:** `ui/logo_header_1x.png` displays at native 112 x 34 px. `Lcd` labels use the shared palette.
- **Side panel modules** (`_add_module` returns a titled, framed `VBoxContainer`):
  - *YOUR TEAMS:* one native-size team icon plus a toggle-style `Button`. Rows are rebuilt each round; blocked groups blink and pressing a row calls `_select_group`.
  - *PLAN THE ROUTE:* a route-state `Led`, a one-line status, the hint line, the DISPATCH button (modulate pulse when `can_dispatch`), and UNDO/CLEAR.
  - *PEOPLE LOST:* six native-size empty/filled sprites reflect `scorer.lost`.
  - *OPS LOG:* shows the last `LOG_SHOWN` (3) of the `LOG_LINES` (6) stored lines.
  - A help `Button` toggles `help_box`, which holds the legend and the key list.
- **Removed:** the `lbl_group` and `lbl_groups` paragraph labels. The step strip (1 PICK A TEAM, 2 DRAW ROUTE, 3 DISPATCH) was added and then removed.
- **Alert bar:** `alert_panel` contains an `HBoxContainer` with a tinted alert sprite (`alert_led`) and a shorter message.
- **Results card:**
  - `result_panel` has a coloured banner (`result_banner`, `result_led`, `lbl_result_title`, `lbl_result_sub`), an `Lcd` "people saved" readout, a three-LED rating, a row of one LED per survivor (`result_pips`), the score rows in a framed grid, an `Lcd` round score, a note and the button.
  - Rating: 0 stars if the round failed, otherwise 3 if all were saved, 2 if at least 75% were saved, 1 otherwise.
  - The panel fades in with a 0.3 s tween on `modulate:a`.

## Hazard schedule (`hazard_manager.gd`)

Fire now spreads from starting fires along roads after a round-specific grace period. New spread tiles smolder before igniting; spot fires use their own warning timer. The round tuning and safety rules are documented in [`FIRE_SPREAD.md`](./FIRE_SPREAD.md). The map countdown displays time to the next spread or scheduled spot fire.

## Scoring labels (`score_keeper.gd`)

Only the display text changed. Point formulas and constants are the same.

| Old | New |
|---|---|
| Survivors rescued | People saved |
| Route efficiency | Short routes |
| Planning speed | Fast planning |
| Hazard response | Quick detours |
| Casualties | People lost |
| Round clear bonus | Round bonus |

`_times_text` is now unused.

## Verification

- `godot --headless --path . --script res://tests/test_generation.gd`: 5908 checks, 0 failures (includes the real game scene and round flow).
- Screenshots were captured with `--write-movie` for the main view and the results card (the results card used injected sample values).
- The verification above describes the earlier UI baseline. The current polish changes need a fresh Godot run; Godot was unavailable during this update.

## UI/UX polish follow-up

- `ui_theme.tres` is the shared default Theme; adjust the default Label/Button colors and panel style there.
- `scripts/ui_colors.gd` owns the tweakable palette, `BUILDING_DIM`, `GLOBAL_BRIGHTNESS`, and `JUICE_ENABLED`.
- Map rendering uses separate roads, parks, and dimmed building layers. `MapView` adds the rounded team-colored planned route, pointer preview, marker hit tolerance, SAFE/waiting pulses, and countdown indicator.
- The side panel uses team-tinted selection styles, a BBCode-colored `RichTextLabel` log, and short loss feedback. The instruction hint hides after the first successful dispatch.
- `ui/scanline_overlay.gdshader` controls the subtle scanline/vignette; `ui/alert_flash.gdshader` controls the edge flash.
- Project stretch remains `canvas_items` with `expand`; the map view and its parent map area clip their contents.
- Added runtime-only nodes: `/Main/ScanlineOverlay`, `/Main/AlertFlashOverlay`, and `MapView/ParkLayer`, `MapView/BuildingLayer`, `MapView/PlannedRouteLine`. Arrival bursts use temporary `CPUParticles2D` children. No existing art asset was edited.

## Known leftovers

- `ScoreKeeper._times_text` is unused.
- `README.md` is still only a title. `EVAC_GRID.md` still describes the older side-panel wording in its "How to play" section.
- Godot needs a one-time project import (`godot --headless --path . --import`) so the new `UiWidgets` class is registered. Opening the project in the editor does this.
