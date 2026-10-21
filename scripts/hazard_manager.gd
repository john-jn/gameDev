class_name HazardManager
extends RefCounted
## Spawns fires during a run on a real-time schedule. Hazards begin counting
## down when the round starts, even if the operator has not dispatched a group.
## Each fire is sampled from the whole open road network instead of targeting
## a moving group's route. It is still placed only where EVERY active group
## keeps a path to safety afterwards, so a group can never be stranded.

var events_remaining := 0
var min_delay := 2.0
var max_delay := 3.5
var _cooldown := -1.0  ## seconds until the next attempt
var _rng: RandomNumberGenerator


func setup(round_num: int, rng: RandomNumberGenerator) -> void:
	_rng = rng
	# Keep a finite number of alerts per round. Later rounds make the same
	# pressure arrive sooner, rather than making hazards track the player.
	# Round 1 is a gentle tutorial: 3 slow fires, the first after a long grace period.
	events_remaining = mini(6, 2 + round_num)
	min_delay = maxf(2.0, 9.0 - 1.0 * (round_num - 1))
	max_delay = min_delay + maxf(1.5, 5.0 - 0.5 * (round_num - 1))
	_cooldown = _rng.randf_range(min_delay * 1.2, min_delay * 1.6)


## Kept as a compatibility hook for callers from the old dispatch-driven model.
## The timer is already armed by setup() and never waits for a dispatch.
func on_dispatch() -> void:
	pass


## Returns the tile that caught fire this frame, or CityMap.NO_TILE.
func update(delta: float, map: CityMap, groups: Array[SurvivorGroup]) -> Vector2i:
	if events_remaining <= 0:
		return CityMap.NO_TILE
	_cooldown -= delta
	if _cooldown > 0.0:
		return CityMap.NO_TILE
	var any_active := false
	for g in groups:
		if g.is_active():
			any_active = true
	if not any_active:
		return CityMap.NO_TILE
	var tile := _pick_tile(map, groups)
	if tile == CityMap.NO_TILE:
		_cooldown = 0.35  # no safe candidate right now; retry without rearming
		return CityMap.NO_TILE
	map.add_fire(tile)
	events_remaining -= 1
	_cooldown = _rng.randf_range(min_delay, max_delay) if events_remaining > 0 else 0.0
	return tile


func _pick_tile(map: CityMap, groups: Array[SurvivorGroup]) -> Vector2i:
	# Seeded shuffling (not Array.shuffle(), which uses the global RNG) samples
	# the complete city road network. A route may be hit by chance, but it is no
	# longer selected as the hazard's preferred target.
	var open_roads: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if map.is_street(p) and not map.is_safe(p) and not map.is_fire(p) and not map.is_intersection(p):
				open_roads.append(p)
	MapGenerator.shuffle(open_roads, _rng)
	for p in open_roads:
		if _can_block(map, p, groups):
			return p
	return CityMap.NO_TILE


func _can_block(map: CityMap, p: Vector2i, groups: Array[SurvivorGroup]) -> bool:
	if map.is_fire(p) or map.is_safe(p) or not map.is_street(p):
		return false
	# Test the actual post-fire state, rather than only checking whether a group
	# can currently reach the candidate. This works for waiting, moving and
	# already-blocked groups alike.
	map.add_fire(p)
	for g in groups:
		if not g.is_active():
			continue
		if p == g.tile or p == g.stop_tile() or p == g.next_tile():
			map.remove_fire(p)
			return false
		if not map.has_path(g.stop_tile()):
			map.remove_fire(p)
			return false
	map.remove_fire(p)
	return true
