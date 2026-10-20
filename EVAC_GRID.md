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
4. **FIRE!** A hazard can block an active route. The group stops, the blocked segment flashes red, and an alert banner appears. Draw a detour from the group's current tile and dispatch again.
5. When every group is safe or lost, a score breakdown appears. Press **Next Round** to continue.

Keys: Enter dispatch, Z/Backspace undo, C clear, Tab next group, Esc deselect.

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

- **Round 1:** a hand-authored training map with 2 groups and 1 hazard alert.
- **Round 2 onward:** procedural maps that get gradually wider, with more groups (up to 6), more road closures, pre-existing fires, and more frequent hazard alerts (up to 5 per round).
  Roads are grown by a Physarum (slime mould) simulation that starts from a different, randomly placed colony center every map (see below).

## Code layout

| File | Responsibility |
|---|---|
| `scenes/main.tscn` | Single scene: a root `Control` running `game.gd` |
| `scripts/game.gd` | Round flow, operator actions, UI construction and refresh |
| `scripts/city_map.gd` | Grid data, fires and smoke, BFS pathfinding, robustness check |
| `scripts/map_generator.gd` | Hand-authored round 1; procedural rounds (Physarum roads, lattice fallback) with safety validation |
| `scripts/physarum_sim.gd` | Seeded slime-mould agent simulation: randomized colony center, trail map, diffusion/decay, food attractors |
| `scripts/route_validator.gd` | Route legality: start tile, contiguity, no fire or buildings, ends in SAFE |
| `scripts/survivor_group.gd` | Group state machine and tile-by-tile movement |
| `scripts/hazard_manager.gd` | Places fires on active routes, only where every group keeps a detour |
| `scripts/score_keeper.gd` | Score buckets and the result breakdown |
| `scripts/map_view.gd` | Top-down drawing, mouse and touch input, legend symbols |

## Procedural generation

1. Pick the map size and put a 3x3 safe zone, ringed by road, one tile in from a random edge.
2. Pick the colony center at random, keeping the whole spawn disc at least `CENTER_MARGIN` tiles from every edge and (when it fits) 4+ tiles from the safe zone.
3. Scatter food sources evenly over the whole map, plus a strong one at the safe zone, and run the Physarum agents (sense, turn, move, deposit; the trail diffuses and decays). Run length grows with the distance from the center to the farthest corner, so off-center colonies still reach the far side.
4. Turn trail veins into roads. Nodes are the colony center, the food and the colony's own junctions (trail peaks). Links come from their Gabriel graph: its spanning tree always, other links only where the colony grew a vein. Each link is carved as the cheapest path over the trail.
5. Clean up and reinforce: drop roads cut off from safety, thin 2x2 blobs, carve bypasses around single points of failure, prune dead ends.
6. Shared with the lattice: place survivors, close short road segments, pre-place fires, validate.

Up to 12 Physarum attempts are made, each with a new center; then up to 40 street-lattice attempts; then the hand-authored map.

**Seeds.** Each round draws one map seed from the game RNG, and every attempt derives its own RNG from (seed, round, attempt), so `MapGenerator.build_from_seed(round, seed)` rebuilds a map exactly. The seed, attempt, colony center and source are printed to stdout at round start. `godot -- --seed=N` replays a whole session (maps and hazards).

**Tests.** `godot --headless --path . --script res://tests/test_generation.gd` (add `-- --seeds=N` for more maps per round) checks hundreds of generated maps: solvability, detours, reproducibility, center bounds, fallbacks, live-hazard play-throughs, map-view alignment and the real game scene.

## Guarantees and assumptions

- Every generated map is checked so each group has a path to safety, and still has one if any single tile on its shortest route is blocked. Every open road also stays connected to the safe zone. Any change that breaks this is reverted. If Physarum generation fails, the street lattice is used, and if that fails too, the hand-authored map.
- An in-run fire is only placed where every active group still has a route to safety, so no group can be stranded.
- When a fire cuts a route, the group stops at the next tile boundary rather than walking up to the fire.
- Smoke (road tiles next to a fire) can be walked through but costs one survivor per tile. This makes the trade-off between a short route and a safe route explicit.
- Routes may pass through tiles where other groups are waiting. Tapping a group's tile only switches selection when it isn't a valid next step for the current route.
- Touch input uses Godot's default "emulate mouse from touch".
