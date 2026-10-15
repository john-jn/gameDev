class_name HazardManager
extends RefCounted
## Spawns fires during a run. Each fire lands on the not-yet-walked part of a
## moving group's route (so the operator has to react), but only on a tile
## where EVERY active group still has a path to safety afterwards. A group can
## therefore never be stranded by a hazard.

var events_remaining := 0
var min_delay := 2.0
var max_delay := 3.5
var _cooldown := -1.0  ## seconds until the next attempt; < 0 means disarmed
var _rng: RandomNumberGenerator


func setup(round_num: int, rng: RandomNumberGenerator) -> void:
	_rng = rng
	events_remaining = mini(1 + floori((round_num - 1) / 2.0), 5)
	min_delay = maxf(0.8, 2.2 - 0.15 * (round_num - 1))
	max_delay = min_delay + 1.5
	_cooldown = -1.0


## Called whenever a route is dispatched; arms the hazard timer.
func on_dispatch() -> void:
	if events_remaining > 0 and _cooldown < 0.0:
		_cooldown = _rng.randf_range(min_delay, max_delay)


## Returns the tile that caught fire this frame, or CityMap.NO_TILE.
func update(delta: float, map: CityMap, groups: Array[SurvivorGroup]) -> Vector2i:
	if events_remaining <= 0 or _cooldown < 0.0:
		return CityMap.NO_TILE
	_cooldown -= delta
	if _cooldown > 0.0:
		return CityMap.NO_TILE
	var any_moving := false
	for g in groups:
		if g.state == SurvivorGroup.State.MOVING and not g.halt_requested:
			any_moving = true
	if not any_moving:
		_cooldown = -1.0  # wait for the next dispatch
		return CityMap.NO_TILE
	var tile := _pick_tile(map, groups)
	if tile == CityMap.NO_TILE:
		_cooldown = 0.5  # nothing suitable right now; retry shortly
		return CityMap.NO_TILE
	map.add_fire(tile)
	events_remaining -= 1
	_cooldown = _rng.randf_range(min_delay, max_delay) if events_remaining > 0 else -1.0
	return tile


func _pick_tile(map: CityMap, groups: Array[SurvivorGroup]) -> Vector2i:
	var movers: Array[SurvivorGroup] = []
	for g in groups:
		if g.state == SurvivorGroup.State.MOVING and not g.halt_requested:
			movers.append(g)
	movers.shuffle()
	for g in movers:
		# Leave at least one free tile between the group's stop tile and the fire,
		# and never block the final step into the safe zone.
		var cands: Array[Vector2i] = []
		for i in range(g.index + 3, g.path.size() - 1):
			var p := g.path[i]
			if not map.is_safe(p):
				cands.append(p)
		cands.shuffle()
		for p in cands:
			if _can_block(map, p, groups):
				return p
	return CityMap.NO_TILE


func _can_block(map: CityMap, p: Vector2i, groups: Array[SurvivorGroup]) -> bool:
	if map.is_fire(p) or map.is_safe(p) or not map.is_street(p):
		return false
	for g in groups:
		if not g.is_active():
			continue
		if p == g.tile or p == g.stop_tile() or p == g.next_tile():
			return false
		if not map.has_path(g.stop_tile(), p):
			return false
	return true
