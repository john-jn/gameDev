# Spreading Fire (design draft)

Status: **proposal**, not implemented. It would replace the fixed fire schedule in `scripts/hazard_manager.gd`.

## Goal

Make time the main threat. Today each round has a fixed number of fires (3 in round 1, up to 6), each placed so that no group is ever stranded. The only way to lose survivors is walking through smoke, so slow planning costs points but rarely costs the round.

With spreading fire, the disaster grows the whole round and will eventually take every road except the safe zone. The player always *can* lose, as in Tetris, if they let the fire get ahead of them. Hesitating has a visible cost.

## Core rules

1. **Starting fires.** Each round begins with 1–3 starting fires, placed far from every group and from the safe zone.
2. **Grace period.** The fire does not spread for the first few seconds, so the player can read the map. The round clock is already running.
3. **Spread.** On each spread tick, the fire moves onto road tiles next to tiles already burning. It never jumps to a random tile elsewhere on the map.
4. **Warning (smolder).** A tile chosen to catch fire smolders first (it flashes for a short time) before it burns. Smoke still marks the road tiles next to a fire, so the danger edge stays visible.
5. **The safe zone never burns.** Fire stops at its border.
6. **The fire speeds up.** The time between spread ticks shrinks during a round and starts lower each round.
7. **Rubble closures** do not burn and do not carry fire. They act as natural firebreaks.

## What fire does to groups

| Tile | Effect |
|---|---|
| Smoke (next to fire), moving | −1 survivor per tile entered (unchanged) |
| Smoke (next to fire), standing still | −1 survivor every 2 s (see below) |
| Smoldering | No effect yet. It is a warning. |
| Burning | **The whole group is lost** |

This applies to every group, **including groups that haven't been dispatched yet**. A group waiting at its start tile is consumed if the fire reaches it. "I'll get to Group C later" becomes a real risk.

### Smoke damage over time

In the current build, smoke is only checked when a group *enters* a tile, and `SurvivorGroup.step()` does nothing unless the group is moving. A fire that appears next to a waiting group turns the group's tile into smoke, but the group takes no damage until it is dispatched. The new rule closes that gap:

- **Drain while standing still.** A group that is not moving (waiting, halted, or stopped with STOP) loses 1 survivor every **2 s** while its tile is smoke. If it reaches 0 survivors, it is lost.
- **Delay before the first loss.** The first survivor dies after the full interval, not the moment smoke appears, so the player has time to react.
- **No double charge.** Moving groups keep the per-tile rule. The drain timer only runs while a group stands still and resets when it moves or leaves the smoke.
- **Clear feedback.** The group's badge flashes amber or shows a countdown ring, and each loss shows a "-1" popup and a log line, as smoke losses do today.
- **Round 1.** A slower drain (every 4 s) or none at all, to match the tutorial.

This gives waiting groups a warning stage before the fire reaches them, and it makes the player think about *where* to press STOP, not just whether to.

## STOP control

- While a group is **moving**, the UNDO button becomes **STOP**. While a route is being **planned**, it stays UNDO.
- STOP puts the group into the existing `BLOCKED` state, so the current reroute flow (draw a detour from the group's tile, then DISPATCH) works unchanged.
- There is no automatic halt when fire lands on a route (from round 2 on, see below). The player has to notice and react.
- **Note for implementation:** `SurvivorGroup.step()` only checks for a halt at tile boundaries. Either make STOP take effect mid-move, or make sure the smolder warning lasts longer than one tile of travel (0.4 s at `SPEED = 2.5`).

## Fairness rules

The fire must feel readable, never random.

- A spread tick never ignites a tile within **N tiles of a moving group's position along its route**, unless that tile was already smoldering. This means a fire never appears right in front of a team with no warning.
- A group always starts the round with at least one clean route to safety (the map generator already checks this).
- The old guarantee "a group can never be stranded" is replaced by **"a group is never stranded if the player acts in time."**

## Round 1 (tutorial)

Round 1 stays forgiving so players learn the reroute flow before mistakes are deadly:

- Very slow spread and a long grace period.
- **Auto-halt kept:** a group stops by itself before a burning tile, as it does today.
- Fire is lethal from round 2 on.

## Win / lose

Unchanged: a round fails when fewer than half of all survivors reach safety. Spreading fire makes that outcome much more likely when the player stalls. A group taken by fire delivers 0 survivors.

## Tuning (starting values, playtest these)

All values should live in one place (as `HazardManager.setup()` does now) so they are easy to change.

| Round | Starting fires | Grace (s) | Spread interval start → min (s) | Smolder (s) | Smoke drain (s) | Lethal fire |
|---|---|---|---|---|---|---|
| 1 | 1 | 12 | 6.0 → 4.0 | 2.0 | 4.0 (or off) | No (auto-halt) |
| 2 | 1 | 10 | 5.0 → 3.0 | 1.8 | 2.0 | Yes |
| 3 | 2 | 8 | 4.5 → 2.5 | 1.6 | 2.0 | Yes |
| 4 | 2 | 7 | 4.0 → 2.0 | 1.5 | 2.0 | Yes |
| 5+ | 3 | 6 | 3.5 → 1.5 | 1.5 | 2.0 | Yes |

Other knobs:

- **Tiles per tick:** how many tiles catch per tick (start at 1, or one per active fire front).
- **Interval ramp:** how fast the interval drops from start to min within a round (for example, linear over 60 s).
- **Minimum distance from groups for fire spread (N):** start at 3 tiles, about 1.2 s of travel.

## Implementation sketch

- **`hazard_manager.gd`:** replace `events_remaining` and the cooldown schedule with a spread tick. Each tick:
  1. Collect road tiles next to burning tiles (not safe, not burning, not rubble).
  2. Remove tiles that break the fairness rules.
  3. Pick one (or more) with the seeded RNG and mark it smoldering.
  4. Ignite tiles whose smolder timer has run out.
  The per-candidate `has_path` checks in `_can_block` are no longer needed for spread tiles.
- **`city_map.gd`:** add a smolder set (tile → time left) next to `fires`, with an `is_smoldering()` query.
- **`survivor_group.gd`:** a burning tile kills the group (`State.LOST`). Check groups that are waiting or blocked too, not only moving ones. Add a manual `stop()`. Add a smoke drain timer: `step()` currently returns early unless the group is moving, so non-moving groups need their own branch that counts down while `map.is_smoke(tile)` and emits a `"casualty"` event each interval (resetting when the group moves or the tile clears).
- **`game.gd`:** the UNDO/STOP button changes by context. `_on_hazard` only calls `request_halt` in round 1.
- **`map_view.gd` / `map_painter.gd`:** draw smoldering tiles, for example a pulsing ember overlay.
- **Tests:** update `test_generation.gd`. The current checks assume a fixed fire count and that groups are never stranded.

## Open questions

- Should a fire burn out after a while (leaving passable ash), or stay forever?
- Should smoke kill faster as the fire grows?
- Should the score reward finishing a round early (time bonus), now that time is the main pressure?
- Is there a place for an endless mode (one map, fire never stops, survive as long as possible)?
