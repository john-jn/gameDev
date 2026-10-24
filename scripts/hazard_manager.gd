class_name HazardManager
extends RefCounted
## Spreading fire (see FIRE_SPREAD.md). A round starts with a few fires far
## from every group and from the safe zone. After a grace period the fire
## creeps along the road network: each spread tick marks road tiles next to a
## burning tile as smoldering, and a smoldering tile ignites when its timer
## runs out. Ticks come faster as the round goes on, so a player who stalls is
## eventually overrun. Only plain road burns (CityMap.can_burn), so the safe
## zone and rubble closures are never touched.
##
## Spot fires (see SPOT_FIRES.md) start new sources on random road tiles on
## their own timer, so no part of the map stays safe for long. Each one
## smolders for `spot_warning` seconds, then burns and spreads like the rest.
##
## Fairness: a new smolder never lands on a moving group's route within
## `fair_distance` tiles ahead of it, so fire never appears right in front of
## a team without warning. Tiles that were already smoldering still ignite.
## From round 2 fire is lethal and groups get no auto-halt. Round 1 is the
## tutorial: fire cannot kill, so it also never ignites under a group or cuts
## a group's last path to safety (otherwise the round could never end).

## Tuning, set per round by setup().
var start_fires := 1         ## fires burning at round start (fires pre-placed by the map count)
var grace := 12.0            ## seconds before the first spread tick
var interval_start := 6.0    ## seconds between spread ticks when spreading begins...
var interval_min := 4.0      ## ...shrinking linearly to this over `ramp_time`
var ramp_time := 60.0        ## seconds of spreading for the interval to reach `interval_min`
var smolder_time := 2.0      ## warning time before a smoldering tile ignites
var smoke_drain := 4.0       ## seconds per survivor lost while standing in smoke (0 = off)
var fire_lethal := false     ## burning tiles kill groups; otherwise groups auto-halt before fire
var tiles_per_tick := 1      ## tiles that start smoldering on each spread tick
var fair_distance := 3       ## route tiles ahead of a moving group where no new smolder may start
var start_min_distance := 6  ## Manhattan distance from groups and the safe zone for starting fires
var spread_per_front := true ## each connected fire patch spreads `tiles_per_tick`, not the whole map
## Spot fires (see SPOT_FIRES.md): new fire sources started at random road
## tiles during the round, which then spread like any other fire.
var spot_fires := 2          ## spot fires per round
var spot_first := 20.0       ## seconds from round start to the first spot fire
var spot_gap_min := 15.0     ## each later gap is drawn from [spot_gap_min, spot_gap_max]
var spot_gap_max := 20.0
var spot_warning := 3.0      ## smolder time for a spot fire (longer: it can appear anywhere)
var spot_min_distance := 4   ## Manhattan distance from groups and the safe zone (closer than 4 = "within 3 tiles")

## Spot fires placed during the last update(), for the game to announce.
var spotted: Array[Vector2i] = []

var _rng: RandomNumberGenerator
var _clock := 0.0         ## seconds since the round started
var _tick := 0.0          ## seconds until the next spread tick, after the grace period
var _started := false     ## starting fires placed
var _spot_at := -1.0      ## round time of the next spot fire attempt
var _spots_placed := 0    ## spot fires placed this round
var seconds_to_next_event: float:
	get:
		var spread_delay := maxf(grace - _clock, 0.0) if _clock < grace else maxf(_tick, 0.0)
		var spot_delay := INF
		if _spots_placed < spot_fires:
			var spot_time := spot_first if _spot_at < 0.0 else _spot_at
			spot_delay = maxf(spot_time - _clock, 0.0)
		return minf(spread_delay, spot_delay)
var next_event_progress: float:
	get:
		if _clock < grace:
			return clampf(_clock / maxf(grace, 0.01), 0.0, 1.0)
		var interval := spread_interval()
		return clampf(1.0 - _tick / maxf(interval, 0.01), 0.0, 1.0)


func setup(round_num: int, rng: RandomNumberGenerator) -> void:
	_rng = rng
	# Per-round table from FIRE_SPREAD.md; round 5 onward uses the last row.
	# [start fires, grace s, interval start s, interval min s, smolder s, smoke drain s, lethal]
	var rows := [
		[1, 12.0, 6.0, 4.0, 2.0, 4.0, false],
		[1, 10.0, 5.0, 3.0, 1.8, 2.0, true],
		[2, 8.0, 4.5, 2.5, 1.6, 2.0, true],
		[2, 7.0, 4.0, 2.0, 1.5, 2.0, true],
		[3, 6.0, 3.5, 1.5, 1.5, 2.0, true],
	]
	var row: Array = rows[clampi(round_num - 1, 0, rows.size() - 1)]
	start_fires = row[0]
	grace = row[1]
	interval_start = row[2]
	interval_min = row[3]
	smolder_time = row[4]
	smoke_drain = row[5]
	fire_lethal = row[6]
	tiles_per_tick = 1
	ramp_time = 60.0
	fair_distance = 3
	start_min_distance = 6
	spread_per_front = true
	# Spot fires from SPOT_FIRES.md; round 5 onward uses the last row.
	# [spot fires, first s, gap min s, gap max s, warning s]
	var spot_rows := [
		[2, 20.0, 15.0, 20.0, 3.0],
		[3, 15.0, 12.0, 15.0, 3.0],
		[3, 12.0, 10.0, 13.0, 2.5],
		[4, 10.0, 8.0, 11.0, 2.5],
		[5, 8.0, 6.0, 9.0, 2.5],
	]
	var spot: Array = spot_rows[clampi(round_num - 1, 0, spot_rows.size() - 1)]
	spot_fires = spot[0]
	spot_first = spot[1]
	spot_gap_min = spot[2]
	spot_gap_max = spot[3]
	spot_warning = spot[4]
	spot_min_distance = 4
	spotted.clear()
	_clock = 0.0
	_tick = 0.0
	_started = false
	_spot_at = -1.0
	_spots_placed = 0


## Kept as a compatibility hook for callers from the old dispatch-driven model.
## The fire runs on the round clock and never waits for a dispatch.
func on_dispatch() -> void:
	pass


## Seconds between spread ticks right now.
func spread_interval() -> float:
	var k := clampf((_clock - grace) / ramp_time, 0.0, 1.0) if ramp_time > 0.0 else 1.0
	return lerpf(interval_start, interval_min, k)


## Lights fires until `start_fires` are burning, on road tiles far from every
## group and from the safe zone. Each one must leave every group a path to
## safety, and preferably a detour too (as the map generator guarantees).
## Called once at round start (update() does it if nobody did). Returns the
## tiles it lit.
func place_starting_fires(map: CityMap, groups: Array[SurvivorGroup]) -> Array[Vector2i]:
	_started = true
	var lit: Array[Vector2i] = []
	if map.fires.size() >= start_fires:
		return lit
	var anchors: Array[Vector2i] = []
	for g in groups:
		if g.is_active():
			anchors.append(g.tile)
			anchors.append(g.next_tile())
	for y in map.height:
		for x in map.width:
			if map.is_safe(Vector2i(x, y)):
				anchors.append(Vector2i(x, y))
	var reach := {}  # tile -> Manhattan distance to the nearest anchor
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if not map.can_burn(p) or map.is_fire(p):
				continue
			var d := 1 << 30
			for a in anchors:
				d = mini(d, absi(a.x - p.x) + absi(a.y - p.y))
			reach[p] = d
	# Relax step by step on small maps: first the distance (never closer than
	# 3 tiles, so no group starts the round standing in smoke), then the
	# detour requirement.
	for need_detour in [true, false]:
		for min_d in range(start_min_distance, 2, -1):
			var candidates: Array[Vector2i] = []
			for p in reach:
				if reach[p] >= min_d and not map.is_fire(p):
					candidates.append(p)
			MapGenerator.shuffle(candidates, _rng)
			for p in candidates:
				if map.fires.size() >= start_fires:
					return lit
				map.add_fire(p)
				if _all_have_path(map, groups, false) and (not need_detour or _all_robust(map, groups)):
					lit.append(p)
				else:
					map.remove_fire(p)
	return lit


## Advances the fire by `delta` seconds. Returns the tiles that ignited; new
## spot fires (still smoldering) are left in `spotted`.
func update(delta: float, map: CityMap, groups: Array[SurvivorGroup]) -> Array[Vector2i]:
	var ignited: Array[Vector2i] = []
	spotted.clear()
	if not _started:
		place_starting_fires(map, groups)
	_clock += delta
	# Burn down smolder timers before spreading, so a tile picked this frame
	# waits its full warning time.
	for p in map.smolders.keys():
		var left: float = map.smolders[p] - delta
		if left > 0.0 or not _may_ignite(map, p, groups):
			map.smolders[p] = maxf(left, 0.0)
			continue
		map.add_fire(p)
		ignited.append(p)
	# Spot fires keep their own timer, alongside the spread and its grace period.
	if _spots_placed < spot_fires:
		if _spot_at < 0.0:
			_spot_at = spot_first
		if _clock >= _spot_at:
			if _place_spot_fire(map, groups):
				_spots_placed += 1
				_spot_at = _clock + _rng.randf_range(spot_gap_min, spot_gap_max)
			else:
				_spot_at = _clock + 0.35  # nowhere valid right now; retry without using it up
	if _clock < grace:
		return ignited
	_tick -= delta
	if _tick <= 0.0:
		_tick = spread_interval()
		_spread(map, groups)
	return ignited


## One spread tick, picked with the seeded RNG. With `spread_per_front` each
## connected patch of fire grows by up to `tiles_per_tick` tiles; otherwise
## the whole map shares `tiles_per_tick`.
func _spread(map: CityMap, groups: Array[SurvivorGroup]) -> void:
	if not spread_per_front:
		_spread_from(map, groups, map.fires.keys())
		return
	# Patches spread one after another. A tile one patch picks is already
	# smoldering when the next patch looks, so no tile is picked twice.
	for patch in _fire_patches(map):
		_spread_from(map, groups, patch)


## Burning tiles grouped into 4-connected patches, in a stable order.
func _fire_patches(map: CityMap) -> Array:
	var patches := []
	var seen := {}
	for start in map.fires:
		if seen.has(start):
			continue
		seen[start] = true
		var patch: Array[Vector2i] = [start]
		var i := 0
		while i < patch.size():
			var cur := patch[i]
			i += 1
			for d in CityMap.DIRS:
				var n: Vector2i = cur + d
				if map.fires.has(n) and not seen.has(n):
					seen[n] = true
					patch.append(n)
		patches.append(patch)
	return patches


## Up to `tiles_per_tick` road tiles next to `burning` start smoldering.
func _spread_from(map: CityMap, groups: Array[SurvivorGroup], burning: Array) -> void:
	var front: Array[Vector2i] = []
	var seen := {}
	for f in burning:
		for d in CityMap.DIRS:
			var p: Vector2i = f + d
			if seen.has(p) or not map.can_burn(p) or map.is_fire(p) or map.is_smoldering(p):
				continue
			seen[p] = true
			if not _near_moving_group(p, groups):
				front.append(p)
	MapGenerator.shuffle(front, _rng)
	var picked := 0
	for p in front:
		if picked >= tiles_per_tick:
			break
		if _may_ignite(map, p, groups):
			map.add_smolder(p, smolder_time)
			picked += 1


## Starts one spot fire on a random road tile that is not burning or
## smoldering, outside every moving group's fairness window, at least
## `spot_min_distance` from every group and the safe zone, and (in round 1)
## allowed to ignite by _may_ignite(). It smolders for `spot_warning` seconds
## before it burns. Returns false if no tile qualifies.
func _place_spot_fire(map: CityMap, groups: Array[SurvivorGroup]) -> bool:
	var anchors: Array[Vector2i] = []
	for g in groups:
		if g.is_active():
			anchors.append(g.tile)
			anchors.append(g.next_tile())
	for y in map.height:
		for x in map.width:
			if map.is_safe(Vector2i(x, y)):
				anchors.append(Vector2i(x, y))
	var candidates: Array[Vector2i] = []
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if not map.can_burn(p) or map.is_fire(p) or map.is_smoldering(p) or _near_moving_group(p, groups):
				continue
			var far := true
			for a in anchors:
				if absi(a.x - p.x) + absi(a.y - p.y) < spot_min_distance:
					far = false
					break
			if far:
				candidates.append(p)
	MapGenerator.shuffle(candidates, _rng)
	for p in candidates:
		if _may_ignite(map, p, groups):
			map.add_smolder(p, spot_warning)
			spotted.append(p)
			return true
	return false


## Fairness rule: true if `p` is on a moving group's route, from its current
## tile up to `fair_distance` tiles ahead.
func _near_moving_group(p: Vector2i, groups: Array[SurvivorGroup]) -> bool:
	for g in groups:
		if g.state != SurvivorGroup.State.MOVING:
			continue
		for i in range(g.index, mini(g.index + fair_distance, g.path.size() - 1) + 1):
			if g.path[i] == p:
				return true
	return false


## Lethal fire may burn anywhere. Non-lethal (tutorial) fire must not ignite
## under a group or cut any group's last path to safety; such a tile simply
## waits (keeps smoldering) until it is clear.
func _may_ignite(map: CityMap, p: Vector2i, groups: Array[SurvivorGroup]) -> bool:
	if fire_lethal:
		return true
	for g in groups:
		if g.is_active() and (p == g.tile or p == g.stop_tile() or p == g.next_tile()):
			return false
	var left: float = map.smolders.get(p, -1.0)
	map.add_fire(p)
	var ok := _all_have_path(map, groups, true)
	map.remove_fire(p)
	if left >= 0.0:
		map.smolders[p] = left
	return ok


func _all_have_path(map: CityMap, groups: Array[SurvivorGroup], from_stop: bool) -> bool:
	for g in groups:
		if g.is_active() and not map.has_path(g.stop_tile() if from_stop else g.tile):
			return false
	return true


func _all_robust(map: CityMap, groups: Array[SurvivorGroup]) -> bool:
	for g in groups:
		if g.is_active() and not map.is_robust(g.tile):
			return false
	return true
