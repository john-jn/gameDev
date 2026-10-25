# Evac Grid (prototype)

A top-down disaster evacuation puzzle. You are a remote rescue operator: you plan routes on a city grid, and survivor groups follow them to the safe zone.

## Run

1. Open Godot 4.6+ (Godot 4.7.2 was used for today's validation), click **Import**, and pick this folder's `project.godot`.
2. Press **F5** (Run Project). The main menu opens first; use **START GAME** or open **SETTINGS** to adjust volume.

No plugins or external runtime dependencies are required; project art and audio are included in the repository.

## How to play

1. **Tap a team row or yellow circle** (a survivor group; the badge is its head count). The selected team stays highlighted while it is moving.
2. **Tap or drag along adjacent road tiles** to the green **SAFE** zone. Valid next tiles are outlined. Tap an earlier route tile to cut the route back to it.
3. Press **DISPATCH** (Enter). The group walks your route tile by tile.
4. **The fire spreads.** Each round starts with a few fires. After a short grace period they creep along the roads, faster as the round goes on. A tile about to catch fire **smolders** (pulsing embers) for a moment first. New fires are also **reported** at random places during the round ("FIRE REPORTED"), smolder a little longer, then spread like the rest.
5. **STOP / DISPATCH / CLEAR.** The shared buttons are centered below **YOUR TEAMS**. STOP halts the selected moving group; DISPATCH sends the selected route; CLEAR removes the current planned route. Z/Backspace also stops a moving group or undoes the last route step.
6. Open the in-game **SETTINGS** button for volume or **END GAME**. Main-menu settings do not show END GAME.
7. When every group is safe or lost, review the complete score panel. A no-safe-route result can show **VIEW MAP**, **NEXT ROUND**, or **MAIN MENU**; the map view has **ROUND OPTIONS** to return to that result panel.

What fire and smoke do:

- **Round 1 (training):** fire is not deadly. A group stops by itself before a burning tile, and the fire never traps a group.
- **Round 2 onward:** a group on a burning tile is lost with everyone in it, and there is no automatic stop. You have to press STOP.
- **Smoke** (road next to a fire) costs one survivor per smoke tile walked onto. A group **standing still** in smoke also loses one survivor every 2 s (4 s in round 1); an amber ring around the group counts down to the next loss.

Keys: Enter/Space dispatch, Z/Backspace undo (STOP while a group moves), C clear, Tab next group, Esc deselect, V map style (dispatch map / debug shapes).

## Tutorial

A guided practice round on the hand-authored training map, with no fire and no score. A pop-up over the map walks through select a team, draw a route, dispatch, watch it arrive, then the same for the second team. The pop-up moves to the other edge of the map so it never covers the highlighted tile. Pulsing brackets on the map and a pulsing DISPATCH button show where to act, and each step waits for the player to do it.

- **Reach it:** the **TUTORIAL** button on the main menu, or the one-time "NEW HERE?" offer when a player with no saved best score presses START GAME. The offer is shown once; progress is stored in `user://tutorial.cfg`.
- **Code:** `scripts/tutorial.gd` (state machine and coach card), small hooks in `game.gd` (`_start_tutorial`, `_exit_tutorial`, `tutorial.tick`), and `MapView.guide_tiles` for the highlights.
- **Test:** `godot --headless --path . --script res://tests/test_tutorial.gd` plays the whole lesson through the real game scene.

## Scoring

| Source | Points |
|---|---|
| Survivor rescued | +50 each |
| Route efficiency | up to +100 per group: 100 × shortest ÷ drawn length, measured at each dispatch |
| Planning speed | +80 − 4/s per first dispatch. The **PLAN CLOCK** runs from round start or the last dispatch |
| Hazard response | +80 − 6/s per detour, timed from when the fire appeared or the group was stopped |
| Casualty | −60 per survivor lost to smoke or fire |
| Round clear | +50 × round when the round succeeds |

A normal round succeeds while deaths do not outnumber the survivors still alive. If no safe route remains, waiting or blocked groups are counted as trapped/lost first; **NEXT ROUND** is available only when people saved strictly outnumber people lost. Equal saved/lost numbers are game over.

## Runs and game over

Each play-through is a **run**, like classic Tetris: it starts at round 1 and lasts until a round is failed.

- A failed round shows **GAME OVER** with the final score (points banked from completed rounds), the round reached, the people saved during the run (the failed round included) and the best score. **NEW BEST!** appears when the run beat it.
- **TRY AGAIN** starts a new run: round 1, score 0, new random maps.
- **VIEW MAP** opens the final map, and **ROUND OPTIONS** returns to the result choices. **MAIN MENU** returns to the start screen.
- The best score and the round it reached are saved on the device (`user://best_score.cfg`). A missing or broken file counts as no best yet and never stops the game.

## Progression

- **Round 1:** a hand-authored training map with 2 groups, slow non-lethal fire and a 12 s grace period.
- **Round 2 onward:** seeded Physarum layouts organized into uneven city blocks with side streets, cross-links and wider avenues. Maps get gradually wider, with more groups (up to 5), more road closures and more pre-placed fires. The fire spreads sooner and faster, and more fires are reported during the round.

Fire tuning per round (all in `HazardManager.setup()`; round 5 onward uses the round 5 row):

| Round | Starting fires | Grace (s) | Spread interval (s) | Smolder (s) | Smoke drain (s) | Spot fires | First spot (s) | Spot gap (s) | Spot warning (s) | Lethal |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 12 | 6.0 → 4.0 | 2.0 | 4.0 | 2 | 20 | 15–20 | 3.0 | No |
| 2 | 1 | 10 | 5.0 → 3.0 | 1.8 | 2.0 | 3 | 15 | 12–15 | 3.0 | Yes |
| 3 | 2 | 8 | 4.5 → 2.5 | 1.6 | 2.0 | 3 | 12 | 10–13 | 2.5 | Yes |
| 4 | 2 | 7 | 4.0 → 2.0 | 1.5 | 2.0 | 4 | 10 | 8–11 | 2.5 | Yes |
| 5+ | 3 | 6 | 3.5 → 1.5 | 1.5 | 2.0 | 5 | 8 | 6–9 | 2.5 | Yes |

- **Starting fires** count the map's pre-placed fires, and are topped up to the number above, far from every group and the safe zone.
- **Spread:** after the grace period, each connected patch of fire grows by one tile per tick. The interval between ticks shrinks linearly over 60 s.
- **Spot fires** land on a random road tile at least 4 tiles from every group and the safe zone.

## Code layout

| File | Responsibility |
|---|---|
| `scenes/main.tscn` | Single scene: a root `Control` running `game.gd` (its inspector holds the map style settings) |
| `scripts/game.gd` | Round and run flow (game over, best score), operator actions including STOP, UI construction and refresh, choice of map style |
| `scripts/city_map.gd` | Grid data, fires, smoldering tiles and smoke, BFS pathfinding, robustness check; holds the city plan and safe-zone designation |
| `scripts/map_generator.gd` | Hand-authored round 1 and seeded Physarum/city-block rounds with safety validation |
| `scripts/physarum_sim.gd` | Seeded slime-mould agent simulation: randomized colony center, trail map, diffusion/decay, food attractors |
| `scripts/city_layout.gd` | City plan for a finished map: building and park lots, the safe-zone building, road classes. Never changes a tile |
| `scripts/city_building.gd` | One lot: footprint, variant, rotation, entrances, safe-zone designation |
| `scripts/route_validator.gd` | Route legality: start tile, contiguity, no fire or buildings, ends in SAFE |
| `scripts/survivor_group.gd` | Group state machine, tile-by-tile movement, STOP, smoke and fire effects |
| `scripts/hazard_manager.gd` | Fire per round: starting fires, spread with smolder warnings and the fairness rule, spot fires; all tuning in `setup()` |
| `scripts/tutorial.gd` | Guided tutorial: step state machine, coach card, first-launch offer |
| `scripts/score_keeper.gd` | Score buckets and the result breakdown |
| `scripts/map_view.gd` | What is drawn where: static city layer, per-frame overlay layer, mouse and touch input |
| `scripts/map_painter.gd` | How each map object looks: primitive painters for both styles, lot geometry, legend icons |
| `scripts/visual_theme.gd` | Every map colour, width and proportion plus optional art slots, as one Resource |
| `tests/test_generation.gd` | Map generation, gameplay and game-flow regression tests (headless) |
| `tests/test_city_layout.gd` | City plan, footprint geometry, safe zones, rendering and input tests (headless) |
| `tests/capture_screenshots.gd` | Saves PNGs of the real game in both styles for checking the look by eye |

## Procedural generation

1. Pick the map size and put a 3x3 safe zone, ringed by road, one tile in from a random edge.
2. Pick the colony center at random, keeping the whole spawn disc at least `CENTER_MARGIN` tiles from every edge and (when it fits) 4+ tiles from the safe zone.
3. Scatter food sources evenly over the whole map, plus a strong one at the safe zone, and run the Physarum agents (sense, turn, move, deposit; the trail diffuses and decays). Run length grows with the distance from the center to the farthest corner, so off-center colonies still reach the far side.
4. Turn trail veins into roads. Nodes are the colony center, the food and the colony's own junctions (trail peaks). Links come from their Gabriel graph: its spanning tree always, other links only where the colony grew a vein. Each link is carved as the cheapest path over the trail.
5. Clean up and reinforce: drop roads cut off from safety, thin 2x2 blobs, carve bypasses around single points of failure, prune dead ends.
6. Shared with the lattice: place survivors, close short road segments, pre-place fires, validate.

Up to 12 Physarum attempts are made, each with a new center; then up to 40 street-lattice attempts; then the hand-authored map.

**Seeds.** Each round draws one map seed from the game RNG, and every attempt derives its own RNG from (seed, round, attempt), so `MapGenerator.build_from_seed(round, seed)` rebuilds a map exactly. The seed, attempt, colony center and source are printed to stdout at round start. `godot -- --seed=N` replays a whole session (maps and hazards).

7. Only a map that passes validation gets its city plan (see *Visual architecture*). The plan reads the tiles and changes none of them, and it draws from the RNG last, so seeds still rebuild the same tiles.

**Tests.** Run both from the project folder; each exits 0 when every check passes.

- `godot --headless --path . --script res://tests/test_generation.gd` (add `-- --seeds=N` for more maps per round) checks hundreds of generated maps: solvability, detours, reproducibility, center bounds, fallbacks, city-plan validity, map-view alignment and the real game scene. It also tests the fire rules (only road burns, spread only to neighbours, smolder timing, the fairness rule, spot-fire schedule and placement, spread per patch), the group effects (fire, smoke drain, STOP), automated play-throughs that compare three fire setups, a full run (play, bank, next round, game over, new run) and the best-score file. The game tests use a scratch best-score file, so they never touch a real best score.
- `godot --headless --path . --script res://tests/test_city_layout.gd` checks the city plan, footprint geometry against roads, safe-zone designation, that no gameplay script references visual code, drawing in every theme, and route planning with pointer events in both styles.
- `godot --path . --script res://tests/capture_screenshots.gd -- --out=C:/shots` (needs a window, not `--headless`) saves snapshots of rounds 1/3/6/9 in both styles, plus one using stand-in art in the asset slots. Headless tests cannot show what the map looks like; this does.

After adding a new `class_name` script, run `godot --headless --path . --import` once (or open the editor) so command-line runs can find the class.

## Visual architecture

The map is drawn from logical data through one swappable theme. No external art is needed, and none is loaded.

```
MapGenerator -> CityMap tiles, fires, survivors      <- gameplay reads only these
             -> CityLayout -> CityMap.buildings, road_class, road_closures (city plan)
MapView (what is drawn where) -> MapPainter (how it looks) -> VisualTheme (colours, sizes, art slots)
```

Gameplay scripts never reference `MapView`, `MapPainter`, `VisualTheme`, colours or textures (`test_city_layout.gd` checks this). Swapping the look cannot change routes, hazards, survivors or scores.

**Two map styles**, both pure primitive shapes:

| Style | Look |
|---|---|
| `DISPATCH_STYLE` (default) | Dark dispatch city map: curbed dark roads with centre dashes and avenue lane dividers, lighter block ground, outlined building footprints with rooftop patterns, stippled parks, hatched closed roads |
| `DEBUG_SHAPES` | The original flat prototype (light road tiles, one dark square per building tile), plus lavender lot outlines and entrance marks |

Switch styles with **V** in game, or set **Visual Style** on the `Main` node in `scenes/main.tscn` for start-up. You can also run `godot -- --visual=debug` (or `--visual=dispatch`). Every colour and size lives in `visual_theme.gd`: `VisualTheme.dispatch_style()` uses the property defaults, and `debug_shapes()` overrides them with the prototype palette.

**Logical objects and their stand-in shapes**

| Object | Data | Drawn by | Art slot |
|---|---|---|---|
| Road | `Tile.ROAD`, `RoadClass` STREET / AVENUE (two-lane) | `MapPainter.draw_road` | (none yet) |
| Closed road | `CityMap.road_closures` (a BUILDING tile) | `draw_closed_road` | (none yet) |
| Building | `CityBuilding` kind BUILDING: footprint, variant, rotation, entrances | `draw_lot` | `building_textures[variant]` |
| Park | `CityBuilding` kind PARK | `draw_lot` | `park_texture` |
| Safe zone | a building designated `SAFE_ZONE` (its tiles are SAFE) | `draw_lot` + `draw_safe_zone` highlight | the building's own |
| Fire / smoke | `CityMap.fires`, `is_smoke()` | `draw_fire`, `draw_smoke` | `fire_texture` |
| Smoldering tile | `CityMap.smolders` | `draw_smolder` (pulsing embers, faster near ignition) | (none yet) |
| Survivor group | `SurvivorGroup` (amber countdown ring while draining in smoke) | `draw_survivor` | `survivor_texture` |
| Route, hover, alerts | game state pushed into `MapView` | `MapView._draw_overlay` | (none yet) |

`MapView` draws the city (ground, roads, lots) on a layer that is redrawn only when the map, its layout, the theme or the view size changes. Hazards, routes, survivors and popups are redrawn every frame on a layer above it. Neither layer takes input. All drawing and all input use the same tile <-> screen transform.

**Adding art later**

1. Import the image into the project, e.g. `assets/buildings/office_a.png`.
2. In the FileSystem dock, create a new `VisualTheme` resource (it starts as `DISPATCH_STYLE`). Add images to **Building Textures**: one per variant, indexed by `CityBuilding.variant` and wrapping around. Fill **Park/Survivor/Fire Texture** as needed. Empty slots keep their primitive shapes.
3. Assign the `.tres` to **Visual Theme Override** on `Main`. It is used whenever its Style matches the active style.

A building texture is stretched over the footprint's bounds, clipped to its outline, and turned so the bottom edge of the image faces the lot's main entrance. Anything beyond a flat texture (animated fire, particles, building scenes, road tiles by connection pattern) is a change to one painter in `map_painter.gd`, or a new node layer in `map_view.gd`. Every lot already has a stable `id`, footprint, `parts()` (one rectangle, or two for an L), `variant`, `rotation` and `entrance`, so map generation, pathfinding and `game.gd` do not change.

**City plan** (`city_layout.gd`, built after a map passes validation)

- A block is a connected group of BUILDING (or PARK) tiles. Each block is cut into lots from 1x1 to 3x3 of weighted random size. Some 1- and 2-tile lots then merge into a neighbour, forming L-shaped footprints. Closed roads are never lots.
- Each lot gets one of 5 variants. Its `entrances` are the open road tiles touching it, and its `rotation` faces its main entrance.
- Every road tile is a STREET, or an AVENUE where it is part of a 2x2 block of road (the two-lane avenues the Physarum grid lays down).
- Footprints are drawn pulled in from roads (`building_road_setback`) and from neighbouring lots (`building_gap`), so a building never covers a road tile. Tests check this geometrically for every lot of sample maps from each round, in both styles.
- `CityLayout.find_problems(map)` lists any broken invariant. The regression tests run it on every generated map.

**Safe zones are a designation, not an asset.** The generator still places the 3x3 safe plaza ringed by road, and `CityLayout` turns each group of SAFE tiles into a building of an ordinary variant designated `SAFE_ZONE`. `map.designate_safe_zone(building)` does the same for any BUILDING lot with an open road entrance (check with `map.can_be_safe_zone()`): its tiles become SAFE, so pathfinding and `RouteValidator` accept it as a destination through its entrances. The green glow, fill, entrance strips and SAFE label are drawn by `MapView` for every designated building. Setting `safe_highlight_enabled = false` on the theme hides them and changes nothing else.

## Guarantees and assumptions

- Every generated map is checked so each group has a path to safety, and still has one if any single tile on its shortest route is blocked. Every open road also stays connected to the safe zone. Any change that breaks this is reverted. If Physarum generation fails, the street lattice is used, and if that fails too, the hand-authored map.
- Starting fires leave every group a path to safety (and a detour too, when one can be found). From round 2 the spreading fire may later cut a group off: you are never trapped if you act in time, but a group left too long can be.
- Only plain road burns. The safe zone and rubble closures never smolder or catch fire.
- **Fairness:** no new fire (spread or spot) starts on a moving group's route from its current tile to 3 tiles ahead. A tile that was already smoldering still ignites.
- **Round 1:** fire never ignites under a group or cuts a group's last path to safety; such a tile keeps smoldering until it is clear. A group stops at the next tile boundary rather than walking into fire.
- **STOP** takes effect at once and never carries a group onto a tile it had not reached yet.
- Smoke (road tiles next to a fire) can be walked through but costs one survivor per tile, and drains groups that stand in it. This makes the trade-off between a short route and a safe route explicit.
- Routes may pass through tiles where other groups are waiting. Tapping a group's tile only switches selection when it isn't a valid next step for the current route.
- Touch input uses Godot's default "emulate mouse from touch".
