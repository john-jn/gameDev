# Evac Grid (prototype)

A top-down disaster evacuation puzzle. You are a remote rescue operator: you plan routes on a city grid, and survivor groups follow them to the safe zone.

## Run

1. Open Godot 4.6 (or any 4.3+), click **Import**, and pick this folder's `project.godot`.
2. Press **F5** (Run Project). The main scene is `res://scenes/main.tscn`.

No plugins or external assets are used.

## How to play

1. **Tap a yellow circle** (a survivor group; the badge is its head count).
2. **Tap or drag along adjacent road tiles** to the green **SAFE** zone. Valid next tiles are outlined. Tap an earlier route tile to cut the route back to it.
3. Press **DISPATCH** (Enter). The group walks your route tile by tile.
4. **FIRE!** Hazards arrive on a real-time timer, even before a group moves. A fire can block an active route; the group stops, the blocked segment flashes red, and an alert banner appears. Draw a detour from the group's current tile and dispatch again.
5. When every group is safe or lost, a score breakdown appears. Press **Next Round** to continue.

Keys: Enter dispatch, Z/Backspace undo, C clear, Tab next group, Esc deselect, V map style (dispatch map / debug shapes).

## Scoring

| Source | Points |
|---|---|
| Survivor rescued | +50 each |
| Route efficiency | up to +100 per group: 100 × shortest ÷ drawn length, measured at each dispatch |
| Planning speed | +80 − 4/s per first dispatch. The **PLAN CLOCK** runs from round start or the last dispatch |
| Hazard response | +80 − 6/s per detour, timed from when the fire appeared |
| Casualty | −60 per survivor (each smoke tile walked through costs one) |
| Round clear | +50 × round, if at least half the survivors got out |

If fewer than half the survivors are saved, the round fails, its points are not banked, and you can retry it.

## Progression

- **Round 1:** a hand-authored training map with 2 groups and a timed hazard schedule.
- **Round 2 onward:** seeded Physarum layouts organized into uneven city blocks with side streets, cross-links and wider avenues. Maps get gradually wider, with more groups (up to 6), more road closures, pre-existing fires, and a progressively faster timed hazard schedule (3 slow fires in round 1, rising to 6 per round; round 1 gets a ~11-14s grace period).

## Code layout

| File | Responsibility |
|---|---|
| `scenes/main.tscn` | Single scene: a root `Control` running `game.gd` (its inspector holds the map style settings) |
| `scripts/game.gd` | Round flow, operator actions, UI construction and refresh, choice of map style |
| `scripts/city_map.gd` | Grid data, fires and smoke, BFS pathfinding, robustness check; holds the city plan and safe-zone designation |
| `scripts/map_generator.gd` | Hand-authored round 1 and seeded Physarum/city-block rounds with safety validation |
| `scripts/physarum_sim.gd` | Seeded slime-mould agent simulation: randomized colony center, trail map, diffusion/decay, food attractors |
| `scripts/city_layout.gd` | City plan for a finished map: building and park lots, the safe-zone building, road classes. Never changes a tile |
| `scripts/city_building.gd` | One lot: footprint, variant, rotation, entrances, safe-zone designation |
| `scripts/route_validator.gd` | Route legality: start tile, contiguity, no fire or buildings, ends in SAFE |
| `scripts/survivor_group.gd` | Group state machine and tile-by-tile movement |
| `scripts/hazard_manager.gd` | Places timed fires, only where every active group keeps a detour |
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

- `godot --headless --path . --script res://tests/test_generation.gd` (add `-- --seeds=N` for more maps per round) checks hundreds of generated maps: solvability, detours, reproducibility, center bounds, fallbacks, city-plan validity, live-hazard play-throughs, map-view alignment, the real game scene, and a full round (play, bank, next, fail, retry).
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
| Survivor group | `SurvivorGroup` | `draw_survivor` | `survivor_texture` |
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
- An in-run fire is only placed where every active group still has a route to safety, so no group can be stranded.
- When a fire cuts a route, the group stops at the next tile boundary rather than walking up to the fire.
- Smoke (road tiles next to a fire) can be walked through but costs one survivor per tile. This makes the trade-off between a short route and a safe route explicit.
- Routes may pass through tiles where other groups are waiting. Tapping a group's tile only switches selection when it isn't a valid next step for the current route.
- Touch input uses Godot's default "emulate mouse from touch".
