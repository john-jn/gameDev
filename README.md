# Evac Grid

Evac Grid is a top-down disaster-evacuation puzzle built with Godot. You are a remote rescue operator who plans routes through a generated city grid and dispatches survivor groups to a safe zone while fires spread in real time.

## Requirements

- Godot 4.6 or newer
- Windows, macOS, or Linux
- No plugins or external runtime dependencies

The project targets Godot 4.6. The standard Godot 4.7.2 editor is also suitable for opening the project.

## Run the game

### From the Godot editor

1. Launch the standard Godot executable, not the `_console.exe` version.
2. Click **Import**.
3. Select `project.godot` in this folder.
4. Click **Import & Edit**.
5. Press **F6** or **F5** to run the game.

The configured main scene is `scenes/main.tscn`.

### From PowerShell

From the project folder, run Godot with the path to your Godot executable:

```powershell
& "C:\Path\To\Godot_v4.7.2-stable_win64.exe" --editor --path .
```

For the project location used during development:

```powershell
& "C:\Users\John Janiel\Downloads\Godot_v4.7.2-stable_win64.exe" --editor --path "C:\Users\John Janiel\Downloads\gameDev"
```

If Godot is added to your PATH, the shorter command works:

```powershell
godot --editor --path .
```

## How to play

1. Select a yellow survivor group. The badge shows how many people are in the group.
2. Click or drag across adjacent road tiles toward the green **SAFE** zone. Valid next tiles are highlighted.
3. Click an earlier route tile to shorten the route back to that point.
4. Press **DISPATCH** or **Enter**. The group follows the route tile by tile.
5. Watch for fire alerts. A fire can block an active route, stopping the group at the next tile boundary.
6. Select the blocked group, draw a detour from its current position, and dispatch again.
7. When every group is safe or lost, review the score and choose **Next Round**. Failed rounds can be retried.

Fires are timed hazards and begin arriving even if no group has been dispatched. Smoke tiles can be crossed, but each smoke tile costs one survivor, so a short route is not always the safest route.

## Controls

| Input | Action |
|---|---|
| Mouse click or touch | Select groups and draw routes |
| Mouse drag | Extend or erase a route |
| Enter or Space | Dispatch the selected route |
| Z or Backspace | Undo the last route segment |
| C | Clear the current route |
| Tab | Select the next available group |
| Escape | Deselect and clear the route |
| V | Toggle dispatch-map and debug-shape visual styles |

## Scoring

| Source | Points |
|---|---:|
| People saved | +50 per survivor |
| Short routes | Up to +100 per group, based on shortest route versus drawn route |
| Fast planning | Up to +80 on the first dispatch, reduced over time |
| Quick detours | Up to +80 after a fire, reduced over response time |
| People lost | -60 per survivor lost to smoke |
| Round bonus | +50 multiplied by the round number when at least half of all survivors escape |

A round succeeds when at least half of the survivors reach safety. Successful rounds bank their points and advance the game. Failed rounds do not bank points and can be retried.

## Progression

- **Round 1 — Training:** A hand-authored map with two groups and a slower hazard schedule.
- **Round 2 onward:** Seeded procedural city layouts with uneven blocks, side streets, cross-links, avenues, more groups, road closures, pre-existing fires, and faster hazards.
- The number of timed fires increases up to six per round. Round 1 has three slower fires and approximately an 11–14 second grace period before the first timed fire.

## Visual presentation

The default interface uses a dark dispatch-tablet style with a control-panel layout, digital displays, status LEDs, a route-planning panel, an operations log, and a results card. The game includes two map styles:

- **Dispatch map:** Dark roads, centre dashes, avenue lane markings, building footprints, parks, closed-road markings, and hazard overlays.
- **Debug shapes:** The original flat prototype style, useful for debugging map geometry.

Press **V** during play to switch styles. The startup style can also be changed on the `Main` node in `scenes/main.tscn`, or from the command line:

```powershell
godot --path . -- --visual=dispatch
godot --path . -- --visual=debug
```

The visual theme is separate from gameplay logic. Optional art can be assigned through `VisualTheme` resources; empty art slots fall back to primitive shapes.

## Procedural generation

Generated rounds use a seeded Physarum, or slime-mould, simulation to form road networks around a city colony and food sources. The generator then converts the trail network into roads, cleans up disconnected areas, adds bypasses, places city blocks and buildings, and validates the result.

The generator guarantees that:

- Every survivor group has a route to safety.
- A single blocked tile on a shortest route cannot make the map unsolvable.
- Timed fires are placed only when every active group retains a possible route to safety.
- If procedural generation fails validation, the game falls back to a street lattice and then to the hand-authored map.

Maps can be reproduced from their seed. To replay a session with a fixed seed:

```powershell
godot --path . -- --seed=12345
```

## Project structure

| Path | Responsibility |
|---|---|
| `project.godot` | Godot project configuration and main-scene entry point |
| `scenes/main.tscn` | Main scene running the game controller |
| `scripts/game.gd` | Round flow, input, UI, dispatching, and game state |
| `scripts/city_map.gd` | Grid data, pathfinding, fires, smoke, and safety checks |
| `scripts/map_generator.gd` | Training map and seeded procedural map generation |
| `scripts/physarum_sim.gd` | Physarum road-network simulation |
| `scripts/city_layout.gd` | Buildings, parks, road classes, and safe-zone designation |
| `scripts/city_building.gd` | Individual building and park lot data |
| `scripts/route_validator.gd` | Route legality and destination validation |
| `scripts/survivor_group.gd` | Survivor movement and group state machine |
| `scripts/hazard_manager.gd` | Timed fire placement and route-safety checks |
| `scripts/score_keeper.gd` | Score buckets and results breakdown |
| `scripts/map_view.gd` | Map drawing, overlays, mouse, and touch input |
| `scripts/map_painter.gd` | Primitive map-object rendering |
| `scripts/visual_theme.gd` | Colors, dimensions, styles, and optional art slots |
| `scripts/ui_widgets.gd` | Custom screws, LEDs, and LCD-style widgets |
| `tests/test_generation.gd` | Generation, gameplay, and round-flow regression tests |
| `tests/test_city_layout.gd` | City-plan, geometry, rendering, and input tests |
| `tests/capture_screenshots.gd` | Windowed screenshot capture for visual checks |
| `tools/` | Asset-sheet and drawing utilities |
| `assets/` | Fonts and project art assets |

## Tests and development commands

Run these commands from the project folder:

```powershell
# Import/register project resources once, if needed
godot --headless --path . --import

# Run generation and gameplay regression tests
godot --headless --path . --script res://tests/test_generation.gd

# Run city-layout, geometry, rendering, and input tests
godot --headless --path . --script res://tests/test_city_layout.gd

# Capture visual screenshots; this requires a window, so do not use --headless
godot --path . --script res://tests/capture_screenshots.gd -- --out=C:/shots
```

The generation test accepts `-- --seeds=N` to test additional generated maps. The screenshot test writes PNG files to the directory supplied through `--out`.

## Design notes

Gameplay reads logical map data only. Drawing and visual styling are handled by `MapView`, `MapPainter`, and `VisualTheme`, which keeps visual changes from affecting routes, hazards, survivor placement, or scoring.

The game supports mouse and touch input through Godot's input handling. A new `class_name` script may require one project import before headless scripts can discover it:

```powershell
godot --headless --path . --import
```
