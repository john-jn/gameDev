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

- **Round 1:** a hand-authored training map with 2 groups and a timed hazard schedule.
- **Round 2 onward:** seeded Physarum layouts organized into uneven city blocks with side streets, cross-links and wider avenues. Maps get gradually wider, with more groups (up to 6), more road closures, pre-existing fires, and a progressively faster timed hazard schedule (6 randomized alerts per round).

## Code layout

| File | Responsibility |
|---|---|
| `scenes/main.tscn` | Single scene: a root `Control` running `game.gd` |
| `scripts/game.gd` | Round flow, operator actions, UI construction and refresh |
| `scripts/city_map.gd` | Grid data, fires and smoke, BFS pathfinding, robustness check |
| `scripts/map_generator.gd` | Hand-authored round 1 and seeded Physarum/city-block rounds with safety validation |
| `scripts/route_validator.gd` | Route legality: start tile, contiguity, no fire or buildings, ends in SAFE |
| `scripts/survivor_group.gd` | Group state machine and tile-by-tile movement |
| `scripts/hazard_manager.gd` | Places timed fires, only where every active group keeps a detour |
| `scripts/score_keeper.gd` | Score buckets and the result breakdown |
| `scripts/map_view.gd` | Top-down drawing, mouse and touch input, legend symbols |

## Guarantees and assumptions

- Every generated map is checked so each group has a path to safety, and still has one if any single tile on its shortest route is blocked. Every open road also stays connected to the safe zone. Any change that breaks this is reverted. If generation fails, the hand-authored map is used.
- An in-run fire is only placed where every active group still has a route to safety, so no group can be stranded.
- When a fire cuts a route, the group stops at the next tile boundary rather than walking up to the fire.
- Smoke (road tiles next to a fire) can be walked through but costs one survivor per tile. This makes the trade-off between a short route and a safe route explicit.
- Routes may pass through tiles where other groups are waiting. Tapping a group's tile only switches selection when it isn't a valid next step for the current route.
- Touch input uses Godot's default "emulate mouse from touch".
