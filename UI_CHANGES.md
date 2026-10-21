# UI Update: Tablet Look and Easier Controls

## What changed (the simple version)

- **It looks like a tablet now.** The game sits inside a black tablet frame with a camera dot and a home bar.
- **Control-panel style.** The side panel is split into small boxes with lights, like the bomb in *Keep Talking and Nobody Explodes*.
- **Less reading, more looking.**
  - Each team has a coloured light: yellow = needs a route, blue = on the way, red = fire, green = safe.
  - The route box shows one short line, like "Route ready! 18 tiles, 100% direct".
  - A row of red lights shows how many people were lost.
- **Bigger DISPATCH button.** It glows green when your route is ready.
- **Clock and score look like digital screens.** Time is a red LCD display.
- **New font.** The whole game uses Rajdhani, a squared, techy font.
- **Easier words.** "Hazard response" is now "Quick detours". Team states say things like "needs a route".
- **Help is hidden.** The legend and key list are behind a **? LEGEND / KEYS** button.
- **Slower fires in Round 1.** There are only 3 fires. The first one comes after about 11 to 14 seconds, and the rest come every 9 to 14 seconds. Later rounds get faster.
- **New results screen.** It shows a green or red banner, "8 / 9" people saved with one light per person, a 3-light rating, the score lines, and a big round score.
- **Fire alert bar.** It is shorter and has a blinking light.

Nothing about how the game plays changed, except the slower fires in the early rounds.

---

# Technical Report

## Summary

A UI-only reskin of `scripts/game.gd`, plus a new widget script, a font asset, and a retune of the hazard schedule. Map generation, pathfinding, route validation and the scoring formulas are unchanged. Only the score *labels* changed.

## Files

| File | Change |
|---|---|
| `scripts/game.gd` | Rebuilt `_build_ui`, `_update_ui` and `_show_results`; new helpers `_add_module`, `_build_group_rows`, `_on_group_row_pressed`, `_group_led_color`; palette and constants |
| `scripts/ui_widgets.gd` (new) | `UiWidgets.Screw`, `Led`, `Lcd` (drawing-only controls) |
| `assets/fonts/Rajdhani-Medium.ttf`, `Rajdhani-Bold.ttf` (new) | UI font (SIL OFL) |
| `scripts/hazard_manager.gd` | Gentler, round-scaled fire schedule |
| `scripts/score_keeper.gd` | Plain-language labels in `breakdown()` |
| `tests/test_generation.gd` | Retry button text check now expects `TRY AGAIN` |
| `EVAC_GRID.md` | Hazard schedule description updated |

## UI structure (`game.gd`)

- **Frame:** a full-rect `PanelContainer` (corner radius 36, thicker top and bottom margins) holds an inset `screen` `PanelContainer` with `clip_contents`. The camera `Led` and the home bar sit on a separate input-transparent overlay. The page background is `#06080c`.
- **Theme:** `_build_ui` sets a `Theme` on the root with Rajdhani Medium as the default font (size 16) and Rajdhani Bold for `Button` (size 18). If the font files fail to load, the theme falls back to the engine default. `_label` adds +2 to every requested font size because the face runs small.
- **Top bar:** `Lcd` labels for plan clock, time, score and round. Plan-clock colour keeps the old thresholds (green above 40 points, amber above 0, red at 0).
- **Side panel modules** (`_add_module` returns a titled, framed `VBoxContainer`):
  - *YOUR TEAMS:* one row per group, an `Led` plus a toggle-style `Button`. Rows are rebuilt each round in `_build_group_rows` (called from `_start_round`) because the group count varies. Pressing a row calls `_select_group`. LED colour comes from `_group_led_color`; `BLOCKED` groups blink at about 1.7 Hz.
  - *PLAN THE ROUTE:* a route-state `Led` (grey, amber = drawing, red = invalid, green = ready), a one-line status, the hint line, the DISPATCH button (modulate pulse when `can_dispatch`), and UNDO/CLEAR.
  - *PEOPLE LOST:* `MAX_STRIKES` (6) LEDs lit from `scorer.lost`.
  - *OPS LOG:* shows the last `LOG_SHOWN` (3) of the `LOG_LINES` (6) stored lines.
  - A help `Button` toggles `help_box`, which holds the legend and the key list.
- **Removed:** the `lbl_group` and `lbl_groups` paragraph labels. The step strip (1 PICK A TEAM, 2 DRAW ROUTE, 3 DISPATCH) was added and then removed.
- **Alert bar:** `alert_panel` now contains an `HBoxContainer` with a blinking `Led` (`alert_led`) and a shorter message.
- **Results card:**
  - `result_panel` has a coloured banner (`result_banner`, `result_led`, `lbl_result_title`, `lbl_result_sub`), an `Lcd` "people saved" readout, a three-LED rating, a row of one LED per survivor (`result_pips`), the score rows in a framed grid, an `Lcd` round score, a note and the button.
  - Rating: 0 stars if the round failed, otherwise 3 if all were saved, 2 if at least 75% were saved, 1 otherwise.
  - The panel fades in with a 0.3 s tween on `modulate:a`.

## Hazard schedule (`hazard_manager.gd`)

| | Before | After |
|---|---|---|
| Fires per round | 6 | `min(6, 2 + round)`, so round 1 has 3 |
| `min_delay` | `max(0.65, 2.2 - 0.12 * (round - 1))` | `max(2.0, 9.0 - 1.0 * (round - 1))` |
| `max_delay` | `min_delay + max(0.7, 1.5 - 0.08 * (round - 1))` | `min_delay + max(1.5, 5.0 - 0.5 * (round - 1))` |
| First fire | `rand(0.5 to 1.0) * min_delay` | `rand(1.2 to 1.6) * min_delay` (about 11 to 14 s in round 1) |

Fire placement logic (`_pick_tile`, `_can_block`) is unchanged, so the guarantee that no group can be stranded still holds.

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
- Not verified: interactive play, the fire alert bar and the failure results card with the new font, or small window sizes.

## Known leftovers

- `UiWidgets.Screw` and `ScoreKeeper._times_text` are unused.
- `README.md` is still only a title. `EVAC_GRID.md` still describes the older side-panel wording in its "How to play" section.
- Godot needs a one-time project import (`godot --headless --path . --import`) so the new `UiWidgets` class is registered. Opening the project in the editor does this.
