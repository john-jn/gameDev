extends SceneTree
## Headless integration tests for procedural map generation and the systems
## that consume generated maps. Run from the project folder:
##   godot --headless --path . --script res://tests/test_generation.gd
## Optional user args (after `--`): --seeds=N (default 20 per round).
## Exits with code 0 when every check passes, 1 otherwise.

const TEST_BEST_PATH := "user://test_best_score.cfg"  ## scratch best-score file for the game tests

var failures := 0
var checks := 0
var seeds_per_round := 20


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds_per_round = arg.substr(8).to_int()
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	test_robust_mask_equivalence()
	test_bulk_generation()
	test_reproducibility()
	test_variation()
	test_center_selection()
	test_boundary_centers()
	test_lattice_fallback()
	test_fire_only_burns_road()
	test_spread_reaches_neighbours_only()
	test_smolder_becomes_fire()
	test_fairness_distance()
	test_fire_kills_waiting_group()
	test_smoke_drain_timing()
	test_stop_backs_off()
	test_spot_fire_schedule()
	test_spot_fire_fairness()
	test_spot_fire_round1_never_traps()
	test_spot_fire_retry()
	test_spread_per_front()
	test_whole_map_spread_unchanged()
	test_gameplay_simulation()
	test_map_view_alignment()
	await test_game_integration()
	await test_round_flow()
	await test_no_safe_route_flow()
	await test_best_score_file()
	await test_main_menu()
	print("\n==== %d checks, %d failures, %.1fs ====" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> bool:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)
	return cond


## Every gameplay guarantee a generated map must satisfy.
func validate_map(m: CityMap, round_num: int, tag: String) -> bool:
	var ok := true
	ok = check(m.survivor_starts.size() == MapGenerator.group_count_for(round_num) or m.gen_info.get("source") == "handmade",
			"%s: group count %d" % [tag, m.survivor_starts.size()]) and ok
	ok = check(m.survivor_sizes.size() == m.survivor_starts.size(), "%s: sizes/starts mismatch" % tag) and ok
	ok = check(m.fires.size() <= start_fire_cap(round_num), "%s: too many fires at round start" % tag) and ok
	ok = check(MapGenerator._layout_ok(m), "%s: layout rules violated" % tag) and ok
	for i in m.survivor_starts.size():
		var s := m.survivor_starts[i]
		ok = check(m.get_tile(s) == CityMap.Tile.ROAD and not m.is_fire(s), "%s: group %d not on open road" % [tag, i]) and ok
		var path := m.find_path(s)
		ok = check(not path.is_empty(), "%s: group %d has no path" % [tag, i]) and ok
		ok = check(m.is_robust(s), "%s: group %d has no detour" % [tag, i]) and ok
		var v := RouteValidator.validate(m, path, s)
		ok = check(v["valid"] and v["complete"], "%s: shortest path for group %d fails RouteValidator: %s" % [tag, i, v["reason"]]) and ok
	var safe_count := 0
	for t in m.tiles:
		if t == CityMap.Tile.SAFE:
			safe_count += 1
	ok = check(safe_count > 0, "%s: no safe zone" % tag) and ok
	# City plan: lots cover exactly the non-road tiles, never a road or start.
	var problems := CityLayout.find_problems(m)
	ok = check(problems.is_empty(), "%s: city layout: %s" % [tag, problems.slice(0, 3)]) and ok
	ok = check(not m.safe_zones().is_empty(), "%s: no safe-zone building" % tag) and ok
	return ok


## Most fires a map may hold at round start: the generator's pre-placed fires,
## topped up by HazardManager to its starting-fire count.
func start_fire_cap(round_num: int) -> int:
	var hz := HazardManager.new()
	hz.setup(round_num, RandomNumberGenerator.new())
	return maxi(MapGenerator.pre_fire_count_for(round_num), hz.start_fires)


func center_bounds(m: CityMap) -> Rect2:
	var r: float = m.gen_info["spawn_radius"]
	var margin := MapGenerator.CENTER_MARGIN + r
	return Rect2(Vector2(margin, margin), Vector2(m.width, m.height) - Vector2(margin, margin) * 2.0)


func road_share(m: CityMap) -> float:
	var roads := 0
	for t in m.tiles:
		if t == CityMap.Tile.ROAD:
			roads += 1
	return float(roads) / m.tiles.size()


# --- Tests -----------------------------------------------------------------------

## CityMap.robust_mask() must agree with is_robust() on every street tile,
## including maps with fires and partly disconnected roads.
func test_robust_mask_equivalence() -> void:
	print("\n[robust mask] single-pass mask vs per-tile is_robust()")
	var compared := 0
	var mismatches := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	var maps: Array[CityMap] = [MapGenerator.build_handmade()]
	for r in range(2, 10):
		maps.append(MapGenerator.build_from_seed(r, 70 + r))
		var lat: CityMap = null
		var attempt := 0
		while lat == null:
			lat = MapGenerator._try_lattice(r, MapGenerator.attempt_rng(70, r, attempt))
			attempt += 1
		maps.append(lat)
	for m in maps:
		for variant in 3:
			# variant 1: extra random fires; variant 2: random closures (may disconnect roads)
			for k in (8 if variant > 0 else 0):
				var p := Vector2i(rng.randi_range(0, m.width - 1), rng.randi_range(0, m.height - 1))
				if m.get_tile(p) == CityMap.Tile.ROAD:
					if variant == 1:
						m.add_fire(p)
					else:
						m.set_tile(p, CityMap.Tile.BUILDING)
			var mask := m.robust_mask()
			for y in m.height:
				for x in m.width:
					var p := Vector2i(x, y)
					if m.get_tile(p) != CityMap.Tile.ROAD:
						continue
					compared += 1
					if (mask[y * m.width + x] == 1) != m.is_robust(p):
						mismatches += 1
	print("  tiles compared: %d, mismatches: %d" % [compared, mismatches])
	check(mismatches == 0, "robust_mask disagrees with is_robust on %d tiles" % mismatches)


func test_bulk_generation() -> void:
	print("\n[bulk] rounds 2-9 x %d seeds" % seeds_per_round)
	var sources := {}
	var attempts := {}
	var total_ms := 0
	var max_ms := 0
	var n := 0
	var bad := 0
	var share_sum := 0.0
	var sizes := {}
	for r in range(2, 10):
		for s in seeds_per_round:
			var seed := 1000 * r + s
			var t := Time.get_ticks_msec()
			var m := MapGenerator.build_from_seed(r, seed)
			var dt := Time.get_ticks_msec() - t
			total_ms += dt
			max_ms = maxi(max_ms, dt)
			n += 1
			var src: String = m.gen_info["source"]
			sources[src] = sources.get(src, 0) + 1
			attempts[m.gen_info["attempt"]] = attempts.get(m.gen_info["attempt"], 0) + 1
			sizes["%dx%d" % [m.width, m.height]] = true
			if not validate_map(m, r, "round %d seed %d" % [r, seed]):
				bad += 1
			if src == "physarum":
				share_sum += road_share(m)
				var c: Vector2 = m.gen_info["center"]
				check(center_bounds(m).grow(0.001).has_point(c), "round %d seed %d: center %s outside %s" % [r, seed, c, center_bounds(m)])
	print("  maps: %d, invalid: %d, sources: %s" % [n, bad, sources])
	print("  attempt histogram: %s" % [attempts])
	print("  map sizes seen: %d distinct  %s" % [sizes.size(), sizes.keys()])
	print("  avg road share (physarum): %.1f%%" % (100.0 * share_sum / maxi(sources.get("physarum", 0), 1)))
	print("  time per map: avg %.0f ms, max %d ms" % [float(total_ms) / n, max_ms])
	check(sources.get("physarum", 0) >= n * 0.95, "physarum should produce at least 95%% of maps (%s)" % [sources])


func test_reproducibility() -> void:
	print("\n[reproducibility]")
	var same := 0
	var total := 0
	for r in [2, 4, 7, 9]:
		for seed in [7, 99, 123456, -5]:
			var a := MapGenerator.build_from_seed(r, seed)
			var b := MapGenerator.build_from_seed(r, seed)
			total += 1
			var eq := a.tiles == b.tiles and a.survivor_starts == b.survivor_starts \
					and a.survivor_sizes == b.survivor_sizes and a.fires.keys() == b.fires.keys() \
					and a.gen_info == b.gen_info and a.width == b.width \
					and a.building_ids == b.building_ids and _lot_signature(a) == _lot_signature(b)
			if check(eq, "round %d seed %d differs between runs" % [r, seed]):
				same += 1
	# build_round draws exactly one seed from the caller's RNG.
	var r1 := RandomNumberGenerator.new()
	r1.seed = 42
	var r2 := RandomNumberGenerator.new()
	r2.seed = 42
	var m1 := MapGenerator.build_round(3, r1)
	var m2 := MapGenerator.build_round(3, r2)
	check(m1.tiles == m2.tiles and r1.randi() == r2.randi(), "build_round with equal RNG state differs")
	var rebuilt := MapGenerator.build_from_seed(3, m1.gen_info["seed"])
	check(rebuilt.tiles == m1.tiles, "logged seed does not rebuild the map")
	print("  identical rebuilds: %d/%d (+ build_round / logged-seed checks)" % [same, total])


func _lot_signature(m: CityMap) -> Array:
	var out := []
	for b in m.buildings:
		out.append([b.kind, b.designation, b.variant, b.rotation, b.cells, b.entrance])
	return out


func test_variation() -> void:
	print("\n[variation] round 5, 30 seeds")
	var centers := {}
	var layouts := {}
	var safe_edges := {}
	var quadrants := [0, 0, 0, 0]
	for seed in 30:
		var m := MapGenerator.build_from_seed(5, 5000 + seed)
		if m.gen_info["source"] != "physarum":
			continue
		var c: Vector2 = m.gen_info["center"]
		centers[Vector2i(c.round())] = true
		layouts[hash(m.tiles)] = true
		quadrants[(1 if c.x >= m.width * 0.5 else 0) + (2 if c.y >= m.height * 0.5 else 0)] += 1
		for y in m.height:
			for x in m.width:
				if m.is_safe(Vector2i(x, y)):
					safe_edges[_edge_of(m, Vector2i(x, y))] = true
	print("  distinct centers: %d, distinct layouts: %d, center quadrants TL/TR/BL/BR: %s, safe-zone edges: %s" % [
		centers.size(), layouts.size(), quadrants, safe_edges.keys()])
	check(centers.size() >= 20, "centers should vary across seeds")
	check(layouts.size() >= 28, "layouts should vary across seeds")
	for q in quadrants:
		check(q > 0, "every map quadrant should host some colony centers")


func _edge_of(m: CityMap, p: Vector2i) -> String:
	var d := [p.y, m.height - 1 - p.y, p.x, m.width - 1 - p.x]
	return ["top", "bottom", "left", "right"][d.find(d.min())]


func test_center_selection() -> void:
	print("\n[center selection] 2000 samples over several map sizes")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var outside := 0
	var near_safe := 0
	for i in 2000:
		var w := rng.randi_range(12, 40)
		var h := rng.randi_range(10, 30)
		var r := clampf(minf(w, h) * 0.12, 1.5, 3.0)
		var safe := Rect2i(Vector2i(1, rng.randi_range(1, h - 4)), Vector2i(3, 3))
		var c := PhysarumSim.pick_center(w, h, r, MapGenerator.CENTER_MARGIN, rng, safe, MapGenerator.CENTER_SAFE_DIST)
		var lo := MapGenerator.CENTER_MARGIN + r
		if c.x < lo - 0.001 or c.y < lo - 0.001 or c.x > w - lo + 0.001 or c.y > h - lo + 0.001:
			outside += 1
		if PhysarumSim._dist_to_rect(c, safe) < MapGenerator.CENTER_SAFE_DIST:
			near_safe += 1
	print("  outside margins: %d, closer than %.0f tiles to safe zone: %d" % [outside, MapGenerator.CENTER_SAFE_DIST, near_safe])
	check(outside == 0, "centers must respect margins + spawn radius")
	# Degenerate map: margins don't fit, so the midpoint is used.
	var tiny := PhysarumSim.pick_center(6, 5, 2.0, 2.0, rng)
	check(tiny == Vector2(3.0, 2.5), "tiny map should fall back to its midpoint, got %s" % tiny)


func test_boundary_centers() -> void:
	print("\n[boundary centers] corners of the allowed region, rounds 2/5/9")
	var built := 0
	var tried := 0
	for r in [2, 5, 9]:
		for corner in 4:
			# Same size draw as _try_physarum, so the forced center fits the map it builds.
			var size := MapGenerator.map_size_for(r, MapGenerator.attempt_rng(77, r, 0))
			var rad := clampf(minf(size.x, size.y) * 0.12, 1.5, 3.0)
			var lo := MapGenerator.CENTER_MARGIN + rad
			var c := Vector2(lo if corner % 2 == 0 else size.x - lo, lo if corner < 2 else size.y - lo)
			# Agents spawned at the extreme center stay on the map for the whole run.
			var sim := PhysarumSim.new()
			var foods: Array[Vector2i] = [Vector2i(1, 1)]
			var weights: Array[float] = [1.0]
			sim.setup(size.x, size.y, c, rad, foods, weights)
			sim._spawn(MapGenerator.attempt_rng(1, r, corner))
			var spawn_ok := true
			for p in sim.agent_positions():
				if p.distance_to(c) > rad + 0.01 or p.x < MapGenerator.CENTER_MARGIN - 0.01 or p.y < MapGenerator.CENTER_MARGIN - 0.01 \
						or p.x > size.x - MapGenerator.CENTER_MARGIN + 0.01 or p.y > size.y - MapGenerator.CENTER_MARGIN + 0.01:
					spawn_ok = false
			check(spawn_ok, "round %d corner %d: agents spawned outside disc/margins" % [r, corner])
			sim.run(MapGenerator.attempt_rng(1, r, corner))
			var in_map := true
			for p in sim.agent_positions():
				if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y:
					in_map = false
			check(in_map, "round %d corner %d: agent left the map" % [r, corner])
			# Full pipeline from the same corner (retrying like build_from_seed
			# does; each attempt draws its own size, so recompute the corner).
			for attempt in MapGenerator.PHYSARUM_ATTEMPTS:
				tried += 1
				var asz := MapGenerator.map_size_for(r, MapGenerator.attempt_rng(77, r, attempt))
				var arad := clampf(minf(asz.x, asz.y) * 0.12, 1.5, 3.0)
				var alo := MapGenerator.CENTER_MARGIN + arad
				var ac := Vector2(alo if corner % 2 == 0 else asz.x - alo, alo if corner < 2 else asz.y - alo)
				var m := MapGenerator._try_physarum(r, MapGenerator.attempt_rng(77, r, attempt), ac)
				if m != null:
					built += 1
					check(m.gen_info["center"] == ac, "forced center not used")
					validate_map(m, r, "round %d forced corner %d" % [r, corner])
					break
	print("  maps built from all 12 extreme centers using %d attempts" % tried)
	check(built == 12, "every extreme center should yield a valid map (%d/12)" % built)


func test_lattice_fallback() -> void:
	print("\n[lattice fallback] direct _try_lattice, rounds 2-9 x 5 seeds")
	var ok := 0
	var made := 0
	for r in range(2, 10):
		for s in 5:
			for attempt in MapGenerator.LATTICE_ATTEMPTS:
				var m := MapGenerator._try_lattice(r, MapGenerator.attempt_rng(s, r, attempt))
				if m != null:
					made += 1
					if validate_map(m, r, "lattice round %d seed %d" % [r, s]):
						ok += 1
					break
	print("  lattice maps: %d/40 built, %d valid" % [made, ok])
	check(made == 40, "lattice fallback should always produce a map")
	var hm := MapGenerator.build_from_seed(1, 0)
	check(hm.gen_info["source"] == "handmade" and validate_map(hm, 1, "handmade"), "round 1 must be the hand-authored map")
	# Fallback chain through build_from_seed: no Physarum budget -> lattice,
	# no budget at all -> hand-authored map. (Expect two engine warnings.)
	MapGenerator.physarum_attempts = 0
	var lat := MapGenerator.build_from_seed(6, 31)
	check(lat.gen_info["source"] == "lattice" and validate_map(lat, 6, "fallback lattice"), "Physarum failure should fall back to the lattice")
	check(MapGenerator.build_from_seed(6, 31).tiles == lat.tiles, "lattice fallback should be reproducible")
	MapGenerator.lattice_attempts = 0
	var last := MapGenerator.build_from_seed(6, 31)
	check(last.gen_info["source"] == "handmade" and last.gen_info["attempt"] == -1, "total failure should fall back to the hand-authored map")
	MapGenerator.physarum_attempts = MapGenerator.PHYSARUM_ATTEMPTS
	MapGenerator.lattice_attempts = MapGenerator.LATTICE_ATTEMPTS
	print("  fallback chain: physarum -> %s -> %s" % [lat.gen_info["source"], last.gen_info["source"]])


## Small hand-built map for the fire unit tests. A main street along y = 2
## ends in a SAFE tile at its east end; a cross street runs down x = 3; a
## rubble closure sits just north of the main street at x = 6. Every other
## tile is a building.
func fire_test_map() -> CityMap:
	var m := CityMap.new()
	m.setup(12, 5, CityMap.Tile.BUILDING)
	for x in 11:
		m.set_tile(Vector2i(x, 2), CityMap.Tile.ROAD)
	for y in 5:
		m.set_tile(Vector2i(3, y), CityMap.Tile.ROAD)
	m.set_tile(Vector2i(11, 2), CityMap.Tile.SAFE)
	m.road_closures[Vector2i(6, 1)] = true
	return m


## A HazardManager with lethal fire, no starting or spot fires, no grace
## period and a fast, fixed spread so the unit tests run quickly.
func fast_hazards(seed: int) -> HazardManager:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hz := HazardManager.new()
	hz.setup(2, rng)
	hz.start_fires = 0
	hz.spot_fires = 0
	hz.grace = 0.0
	hz.interval_start = 0.2
	hz.interval_min = 0.2
	hz.smolder_time = 0.5
	return hz


func test_fire_only_burns_road() -> void:
	print("\n[fire spread] fire never enters the safe zone or rubble")
	var m := fire_test_map()
	var safe := Vector2i(11, 2)
	var rubble := Vector2i(6, 1)
	m.add_fire(safe)
	m.add_fire(rubble)
	m.add_smolder(safe, 1.0)
	m.add_smolder(rubble, 1.0)
	check(not m.is_fire(safe) and not m.is_fire(rubble), "add_fire must refuse the safe zone and rubble")
	check(not m.is_smoldering(safe) and not m.is_smoldering(rubble), "add_smolder must refuse the safe zone and rubble")
	m.add_fire(Vector2i(0, 2))
	var hz := fast_hazards(11)
	var none: Array[SurvivorGroup] = []
	for i in 1200:
		hz.update(0.05, m, none)
		for p in m.fires:
			if not check(m.get_tile(p) == CityMap.Tile.ROAD, "fire on a non-road tile %s" % p):
				return
		for p in m.smolders:
			if not check(m.get_tile(p) == CityMap.Tile.ROAD, "smolder on a non-road tile %s" % p):
				return
	var roads := 0
	for y in m.height:
		for x in m.width:
			if m.get_tile(Vector2i(x, y)) == CityMap.Tile.ROAD:
				roads += 1
	print("  road tiles: %d, burning after 60s: %d" % [roads, m.fires.size()])
	check(m.fires.size() == roads, "left alone, the fire should take every road tile (%d/%d)" % [m.fires.size(), roads])
	check(not m.is_fire(safe) and not m.is_fire(rubble), "the safe zone and rubble must never burn")


func test_spread_reaches_neighbours_only() -> void:
	print("\n[fire spread] new smolders are always next to the fire")
	var m := fire_test_map()
	m.add_fire(Vector2i(0, 2))
	var hz := fast_hazards(12)
	hz.tiles_per_tick = 2
	var none: Array[SurvivorGroup] = []
	var started := 0
	for i in 600:
		var before := m.smolders.duplicate()
		hz.update(0.05, m, none)
		for p in m.smolders:
			if before.has(p):
				continue
			started += 1
			var next_to_fire := false
			for d in CityMap.DIRS:
				if m.is_fire(p + d):
					next_to_fire = true
			check(next_to_fire, "smolder at %s is not next to a burning tile" % p)
	print("  smolders started: %d" % started)
	check(started > 5, "the fire should have spread")


func test_smolder_becomes_fire() -> void:
	print("\n[fire spread] a smoldering tile ignites after its warning time")
	var m := fire_test_map()
	var p := Vector2i(5, 2)
	var hz := fast_hazards(13)
	hz.grace = 999.0  # no spreading: only the timer is under test
	var none: Array[SurvivorGroup] = []
	m.add_smolder(p, 1.0)
	var t := 0.0
	var lit_at := -1.0
	while t < 3.0 and lit_at < 0.0:
		var lit := hz.update(0.05, m, none)
		t += 0.05
		if not lit.is_empty():
			check(lit.size() == 1 and lit[0] == p, "only the smoldering tile should ignite, got %s" % [lit])
			lit_at = t
		elif m.is_fire(p):
			check(false, "tile ignited without being reported")
	print("  smoldered for 1.0s, ignited at %.2fs" % lit_at)
	check(absf(lit_at - 1.0) < 0.06, "ignition should come after 1.0s, got %.2fs" % lit_at)
	check(m.is_fire(p) and not m.is_smoldering(p), "the tile should now burn, not smolder")


## A group walks the main street toward the fire's side of the map while the
## fire spreads fast; no new smolder may start on its route from its current
## tile up to fair_distance tiles ahead.
func test_fairness_distance() -> void:
	print("\n[fire spread] fairness distance ahead of a moving group")
	var exercised := 0
	var violations := 0
	for seed in 20:
		var m := fire_test_map()
		m.add_fire(Vector2i(3, 0))
		var hz := fast_hazards(100 + seed)
		hz.tiles_per_tick = 3
		var g := SurvivorGroup.new(0, "A", Vector2i(0, 2), 5)
		g.fire_lethal = true
		var groups: Array[SurvivorGroup] = [g]
		g.dispatch(m.find_path(g.tile))
		for i in 200:
			if g.state != SurvivorGroup.State.MOVING:
				break
			var window := {}
			for k in range(g.index, mini(g.index + hz.fair_distance, g.path.size() - 1) + 1):
				window[g.path[k]] = true
			for w in window:
				if not m.is_fire(w) and not m.is_smoldering(w):
					for d in CityMap.DIRS:
						if m.is_fire(w + d):
							exercised += 1  # the rule is what keeps this tile clear
							break
			var before := m.smolders.duplicate()
			hz.update(0.05, m, groups)
			for p in m.smolders:
				if not before.has(p) and window.has(p):
					violations += 1
			g.step(0.05, m)
	print("  frames where the rule held back the fire: %d, violations: %d" % [exercised, violations])
	check(violations == 0, "new smolders started inside a moving group's fairness window")
	check(exercised > 0, "the test should actually put fire next to a protected route tile")


func test_fire_kills_waiting_group() -> void:
	print("\n[group effects] a burning tile kills waiting and blocked groups")
	for s in [SurvivorGroup.State.WAITING, SurvivorGroup.State.BLOCKED]:
		var m := fire_test_map()
		var g := SurvivorGroup.new(0, "A", Vector2i(5, 2), 4)
		g.fire_lethal = true
		g.state = s
		check(g.step(0.05, m).is_empty() and g.is_active(), "no fire, no effect")
		m.add_fire(g.tile)
		var events := g.step(0.05, m)
		check(g.state == SurvivorGroup.State.LOST and g.survivors == 0 and g.casualties == 4, "state %d: group should be lost to the fire" % s)
		check(events.size() == 1 and events[0]["type"] == "lost" and events[0]["cause"] == "fire" and events[0]["count"] == 4,
				"state %d: expected one 'lost' fire event, got %s" % [s, events])
	# Training round: fire is not lethal.
	var m2 := fire_test_map()
	var safe_g := SurvivorGroup.new(1, "B", Vector2i(5, 2), 4)
	m2.add_fire(safe_g.tile)
	safe_g.step(0.05, m2)
	check(safe_g.is_active() and safe_g.survivors == 4, "non-lethal fire must not kill")
	# A moving group that walks into fire dies; with lethal fire there is no auto-halt.
	var m3 := fire_test_map()
	var walker := SurvivorGroup.new(2, "C", Vector2i(0, 2), 3)
	walker.fire_lethal = true
	walker.dispatch(m3.find_path(walker.tile))
	m3.add_fire(Vector2i(2, 2))
	for i in 40:
		walker.step(0.05, m3)
	check(walker.state == SurvivorGroup.State.LOST, "a group walking into fire should be lost (state %d at %s)" % [walker.state, walker.tile])


func test_smoke_drain_timing() -> void:
	print("\n[group effects] smoke drain for groups standing still")
	var m := fire_test_map()
	m.add_fire(Vector2i(6, 2))
	var g := SurvivorGroup.new(0, "A", Vector2i(5, 2), 5)  # next to the fire: smoke
	g.smoke_drain = 2.0
	check(m.is_smoke(g.tile), "test setup: group should stand in smoke")
	var losses := 0
	for i in 39:  # 1.95 s
		for ev in g.step(0.05, m):
			if ev["type"] == "casualty":
				losses += 1
	check(losses == 0 and g.survivors == 5, "no loss before the first full interval (lost %d)" % losses)
	for i in 2:  # past 2.0 s
		for ev in g.step(0.05, m):
			if ev["type"] == "casualty":
				losses += 1
	check(losses == 1 and g.survivors == 4, "one loss after the first interval (lost %d)" % losses)
	# Moving resets the timer: stand 1.5 s, dispatch and stop at once (it halts
	# on the same tile without moving), then wait another 1.9 s.
	for i in 30:
		g.step(0.05, m)
	var back: Array[Vector2i] = [Vector2i(5, 2), Vector2i(4, 2), Vector2i(3, 2)]
	g.dispatch(back)
	check(g.smoke_timer == 0.0, "dispatch should reset the smoke timer")
	g.stop(0.0)
	g.step(0.05, m)
	check(g.state == SurvivorGroup.State.BLOCKED and g.tile == Vector2i(5, 2), "STOP at a tile boundary halts in place")
	for i in 38:  # 1.9 s
		g.step(0.05, m)
	check(g.survivors == 4, "timer should restart after moving (survivors %d)" % g.survivors)
	for i in 3:
		g.step(0.05, m)
	check(g.survivors == 3, "loss after a full interval from the reset (survivors %d)" % g.survivors)
	# The timer also resets when the smoke clears.
	for i in 20:
		g.step(0.05, m)
	m.remove_fire(Vector2i(6, 2))
	g.step(0.05, m)
	check(g.smoke_timer == 0.0 and not g.is_draining(m), "timer resets when the tile clears")
	# Draining smoke can empty a group.
	var m2 := fire_test_map()
	m2.add_fire(Vector2i(6, 2))
	var small := SurvivorGroup.new(1, "B", Vector2i(5, 2), 1)
	small.smoke_drain = 2.0
	var lost := false
	for i in 50:
		for ev in small.step(0.05, m2):
			if ev["type"] == "lost":
				lost = ev["cause"] == "smoke"
	check(lost and small.state == SurvivorGroup.State.LOST, "a group drained to zero is lost in the smoke")


func test_stop_backs_off() -> void:
	print("\n[group effects] STOP between tiles walks back to the last tile reached")
	var m := fire_test_map()
	var g := SurvivorGroup.new(0, "A", Vector2i(0, 2), 5)
	g.fire_lethal = true
	g.dispatch(m.find_path(g.tile))
	while not (g.tile == Vector2i(3, 2) and g.t > 0.3):
		g.step(0.05, m)
	# Smoke appears on the reached tile and fire on the next one.
	m.add_fire(Vector2i(3, 1))
	m.add_fire(Vector2i(4, 2))
	g.stop(5.0)
	var halted := {}
	for i in 20:
		for ev in g.step(0.05, m):
			if ev["type"] == "halted":
				halted = ev
	check(g.state == SurvivorGroup.State.BLOCKED and g.tile == Vector2i(3, 2), "group should halt on (3, 2), got state %d at %s" % [g.state, g.tile])
	check(g.survivors == 5, "backing off onto a tile already reached must not cost a survivor")
	check(halted.get("manual", false), "the halt should be reported as a manual STOP")
	check(g.blocked_since == 5.0, "blocked_since should be the STOP time")
	# STOP on a tile boundary halts right there.
	var m2 := fire_test_map()
	var h := SurvivorGroup.new(1, "B", Vector2i(0, 2), 5)
	h.dispatch(m2.find_path(h.tile))
	h.stop(0.0)
	h.step(0.05, m2)
	check(h.state == SurvivorGroup.State.BLOCKED and h.tile == Vector2i(0, 2), "STOP before moving halts in place")


## A one-street map: road along y = 1 from x = 0 to `length - 2`, a SAFE tile
## at its east end, and optionally a one-tile dead-end spur north of the
## street at x = `spur_x` (-1 for none).
func corridor_map(length: int, spur_x: int) -> CityMap:
	var m := CityMap.new()
	m.setup(length, 3, CityMap.Tile.BUILDING)
	for x in length - 1:
		m.set_tile(Vector2i(x, 1), CityMap.Tile.ROAD)
	m.set_tile(Vector2i(length - 1, 1), CityMap.Tile.SAFE)
	if spur_x >= 0:
		m.set_tile(Vector2i(spur_x, 0), CityMap.Tile.ROAD)
	return m


## A spot fire tile is plain road (not safe, not rubble) and more than 3 tiles
## from every active group (where it stands and where it steps next) and from
## the safe zone.
func _spot_tile_ok(m: CityMap, groups: Array[SurvivorGroup], p: Vector2i) -> bool:
	if m.get_tile(p) != CityMap.Tile.ROAD or m.is_road_closure(p):
		return false
	var anchors: Array[Vector2i] = []
	for g in groups:
		if g.is_active():
			anchors.append(g.tile)
			anchors.append(g.next_tile())
	for y in m.height:
		for x in m.width:
			if m.is_safe(Vector2i(x, y)):
				anchors.append(Vector2i(x, y))
	for a in anchors:
		if absi(a.x - p.x) + absi(a.y - p.y) <= 3:
			return false
	return true


## Spot fires on generated maps, with spreading switched off: exactly
## `spot_fires` per round, the first at `spot_first`, later gaps within
## [spot_gap_min, spot_gap_max], each smoldering for `spot_warning` seconds on
## a legal tile.
func test_spot_fire_schedule() -> void:
	print("\n[spot fires] schedule and placement on generated maps, rounds 1-6")
	const DT := 0.05
	var placed := 0
	for r in range(1, 7):
		for s in 3:
			var m := MapGenerator.build_from_seed(r, 4400 + 10 * r + s)
			var rng := RandomNumberGenerator.new()
			rng.seed = 77 + s
			var hz := HazardManager.new()
			hz.setup(r, rng)
			hz.grace = 1e9  # no spreading: only the spot timer is under test
			var groups: Array[SurvivorGroup] = []
			for i in m.survivor_starts.size():
				groups.append(SurvivorGroup.new(i, char(65 + i), m.survivor_starts[i], m.survivor_sizes[i]))
			var times: Array[float] = []
			var t := 0.0
			while t < 200.0:
				hz.update(DT, m, groups)
				t += DT
				for p in hz.spotted:
					times.append(t)
					check(is_equal_approx(m.smolders[p], hz.spot_warning), "round %d: spot fire should smolder for %.1fs, got %.2fs" % [r, hz.spot_warning, m.smolders[p]])
					check(_spot_tile_ok(m, groups, p), "round %d seed %d: spot fire on an illegal tile %s" % [r, s, p])
			placed += times.size()
			check(times.size() == hz.spot_fires, "round %d seed %d: %d spot fires, expected %d" % [r, s, times.size(), hz.spot_fires])
			if times.is_empty():
				continue
			check(times[0] >= hz.spot_first - 0.001 and times[0] < hz.spot_first + DT + 0.001,
					"round %d seed %d: first spot fire at %.2fs, expected %.1fs" % [r, s, times[0], hz.spot_first])
			for i in range(1, times.size()):
				var gap := times[i] - times[i - 1]
				check(gap >= hz.spot_gap_min - 0.001 and gap < hz.spot_gap_max + DT + 0.001,
						"round %d seed %d: spot gap %.2fs outside %.0f-%.0fs" % [r, s, gap, hz.spot_gap_min, hz.spot_gap_max])
	print("  spot fires placed: %d over 18 rounds" % placed)


## One group walks a long corridor. With a wide fairness window, spot fires
## must land outside it even though tiles inside it would otherwise qualify.
func test_spot_fire_fairness() -> void:
	print("\n[spot fires] fairness window")
	var placed := 0
	var inside := 0
	for seed in 30:
		var m := corridor_map(24, -1)
		var rng := RandomNumberGenerator.new()
		rng.seed = 500 + seed
		var hz := HazardManager.new()
		hz.setup(2, rng)
		hz.start_fires = 0
		hz.grace = 1e9
		hz.fair_distance = 8
		hz.spot_fires = 1
		hz.spot_first = 0.0
		var g := SurvivorGroup.new(0, "A", Vector2i(0, 1), 5)
		var groups: Array[SurvivorGroup] = [g]
		g.dispatch(m.find_path(g.tile))
		for i in seed % 10:
			g.step(0.05, m)
		var window := {}
		for k in range(g.index, mini(g.index + hz.fair_distance, g.path.size() - 1) + 1):
			window[g.path[k]] = true
		hz.update(0.05, m, groups)
		for p in hz.spotted:
			placed += 1
			if window.has(p):
				inside += 1
			check(_spot_tile_ok(m, groups, p), "spot fire on an illegal tile %s" % p)
	print("  spot fires placed: %d, inside the window: %d" % [placed, inside])
	check(placed == 30 and inside == 0, "every spot fire should be placed, none inside the fairness window")


## Round 1: a corridor is the group's only way out, with a dead-end spur off
## it. Every corridor tile far enough away would trap the group, so the
## training spot fire must take the spur. Lethal rounds may block the corridor.
func test_spot_fire_round1_never_traps() -> void:
	print("\n[spot fires] round 1 never traps a group")
	var spur := Vector2i(10, 0)
	var on_corridor := 0
	for seed in 20:
		for r in [1, 2]:
			var m := corridor_map(20, spur.x)
			var rng := RandomNumberGenerator.new()
			rng.seed = 600 + seed
			var hz := HazardManager.new()
			hz.setup(r, rng)
			hz.start_fires = 0
			hz.grace = 1e9
			hz.spot_fires = 1
			hz.spot_first = 0.0
			var g := SurvivorGroup.new(0, "A", Vector2i(2, 1), 5)
			g.fire_lethal = hz.fire_lethal
			var groups: Array[SurvivorGroup] = [g]
			hz.update(0.05, m, groups)
			if not check(hz.spotted.size() == 1, "round %d seed %d: a spot fire should be placed" % [r, seed]):
				continue
			var p := hz.spotted[0]
			if r == 1:
				check(p == spur, "round 1 seed %d: spot fire at %s would trap the group" % [seed, p])
				for i in 100:
					hz.update(0.05, m, groups)
				check(m.is_fire(spur) and m.has_path(g.tile), "round 1: after the spot fire burns, the group must keep its way out")
			elif p != spur:
				on_corridor += 1
	print("  lethal-round spot fires on the corridor: %d/20" % on_corridor)
	check(on_corridor > 0, "lethal rounds should be free to block the corridor")


## A waiting group and the safe zone leave no tile far enough away, so the
## spot fire waits and retries every 0.35 s without being used up. Once the
## group is gone, both spot fires still arrive.
func test_spot_fire_retry() -> void:
	print("\n[spot fires] failed placement retries without using up the spot fire")
	var m := corridor_map(9, -1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 700
	var hz := HazardManager.new()
	hz.setup(2, rng)
	hz.start_fires = 0
	hz.grace = 1e9
	hz.spot_fires = 2
	hz.spot_first = 1.0
	hz.spot_gap_min = 1.0
	hz.spot_gap_max = 1.0
	var g := SurvivorGroup.new(0, "A", Vector2i(2, 1), 5)
	var groups: Array[SurvivorGroup] = [g]
	var t := 0.0
	var spots := 0
	while t < 3.0:
		hz.update(0.05, m, groups)
		t += 0.05
		spots += hz.spotted.size()
	check(spots == 0 and hz._spots_placed == 0, "no valid tile: nothing placed or used up (%d placed)" % hz._spots_placed)
	check(hz._spot_at - t <= 0.35 + 0.001 and hz._spot_at > t - 0.06, "next attempt should be within 0.35s (at %.2f, now %.2f)" % [hz._spot_at, t])
	g.state = SurvivorGroup.State.DELIVERED
	var cleared_at := t
	var first_at := -1.0
	while t < 8.0:
		hz.update(0.05, m, groups)
		t += 0.05
		if not hz.spotted.is_empty() and first_at < 0.0:
			first_at = t
		spots += hz.spotted.size()
	print("  first spot fire %.2fs after the tiles cleared, total %d" % [first_at - cleared_at, spots])
	check(first_at >= 0.0 and first_at - cleared_at <= 0.35 + 0.05 + 0.001, "the retry should place the spot fire within 0.35s")
	check(spots == 2, "both spot fires should still arrive after the retries (got %d)" % spots)


func test_spread_per_front() -> void:
	print("\n[spread per front] separate fires each grow every tick")
	var none: Array[SurvivorGroup] = []
	for per_front in [true, false]:
		var m := corridor_map(24, -1)
		m.add_fire(Vector2i(3, 1))
		m.add_fire(Vector2i(13, 1))
		var hz := fast_hazards(21)
		hz.spread_per_front = per_front
		for tick in 3:
			hz._spread(m, none)
			var left := 0
			var right := 0
			for p in m.smolders:
				if p.x < 8:
					left += 1
				else:
					right += 1
			if per_front:
				check(left == 1 and right == 1, "per front, tick %d: each fire should grow by one tile (left %d, right %d)" % [tick, left, right])
			else:
				check(left + right == 1, "whole map, tick %d: one tile in total (left %d, right %d)" % [tick, left, right])
			for p in m.smolders.keys():
				m.add_fire(p)
	# Two fires sharing the one free tile between them can't both pick it.
	for seed in 20:
		var m := corridor_map(24, -1)
		m.add_fire(Vector2i(5, 1))
		m.add_fire(Vector2i(7, 1))
		var hz := fast_hazards(800 + seed)
		hz._spread(m, none)
		check(m.smolders.size() == 2, "seed %d: two fronts should pick two different tiles (%s)" % [seed, m.smolders.keys()])


## With spread_per_front off, _spread() must pick exactly what the previous
## whole-map version did, tick for tick, from the same seeded RNG.
func test_whole_map_spread_unchanged() -> void:
	print("\n[spread per front] off = previous whole-map spread")
	var none: Array[SurvivorGroup] = []
	var ticks := 0
	var mismatches := 0
	for per_tick in [1, 3]:
		var a := MapGenerator.build_from_seed(7, 8800 + per_tick)
		var b := MapGenerator.build_from_seed(7, 8800 + per_tick)
		var start := a.fires.size()
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = 99
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = 99
		var hz := HazardManager.new()
		hz.setup(2, rng_a)
		hz.spread_per_front = false
		hz.tiles_per_tick = per_tick
		for tick in 40:
			hz._spread(a, none)
			_previous_whole_map_spread(b, rng_b, per_tick)
			ticks += 1
			if a.smolders.keys() != b.smolders.keys():
				mismatches += 1
			for p in a.smolders.keys():
				a.add_fire(p)
			for p in b.smolders.keys():
				b.add_fire(p)
		check(a.fires.size() > start + 20, "the fire should have spread (%d -> %d)" % [start, a.fires.size()])
	print("  ticks compared: %d, mismatches: %d" % [ticks, mismatches])
	check(mismatches == 0, "whole-map spread differs from the previous version on %d ticks" % mismatches)


## The spread tick as it was before spread_per_front (no groups, lethal fire).
func _previous_whole_map_spread(m: CityMap, rng: RandomNumberGenerator, per_tick: int) -> void:
	var front: Array[Vector2i] = []
	var seen := {}
	for f in m.fires:
		for d in CityMap.DIRS:
			var p: Vector2i = f + d
			if seen.has(p) or not m.can_burn(p) or m.is_fire(p) or m.is_smoldering(p):
				continue
			seen[p] = true
			front.append(p)
	MapGenerator.shuffle(front, rng)
	for i in mini(per_tick, front.size()):
		m.add_smolder(front[i], 1.0)


## Plays rounds automatically with spreading fire. Like a human operator, the
## bot needs THINK seconds per route, so it dispatches one group at a time
## along its shortest path while the fire spreads. It presses STOP when fire
## or a smoldering tile lies just ahead and then re-routes. Every frame it
## checks the fire rules on real maps: only road burns, spread smolders start
## next to the fire, spot fires keep their distance from groups and the safe
## zone, nothing new starts inside a moving group's fairness window, and in
## round 1 (training) no group is ever stranded or killed by fire. From round
## 2 a group may be stranded; it then waits until the fire or smoke takes it.
## Runs three fire setups so their difficulty can be compared.
func test_gameplay_simulation() -> void:
	print("\n[gameplay simulation] rounds 1-9 x 6 seeds, auto-dispatch with spreading fire")
	_simulate("previous build: whole-map spread, no spot fires", false, false)
	_simulate("spread per front, no spot fires", false, true)
	_simulate("spread per front + spot fires (default)", true, true)


func _simulate(label: String, spots: bool, per_front: bool) -> void:
	const DT := 0.05
	const LIMIT := 300.0
	const THINK := 3.0
	var rounds := 0
	var ignitions := 0
	var stops := 0
	var detours := 0
	var delivered := 0
	var burned := 0
	var smoked := 0
	var stranded := 0
	var unresolved := 0
	var spot_count := 0
	var round_secs := 0.0
	for r in range(1, 10):
		for s in 6:
			var m := MapGenerator.build_from_seed(r, 9000 + 10 * r + s)
			var rng := RandomNumberGenerator.new()
			rng.seed = 31337 + s
			var hz := HazardManager.new()
			hz.setup(r, rng)
			hz.spread_per_front = per_front
			if not spots:
				hz.spot_fires = 0
			var safe_tiles: Array[Vector2i] = []
			for y in m.height:
				for x in m.width:
					if m.is_safe(Vector2i(x, y)):
						safe_tiles.append(Vector2i(x, y))
			var groups: Array[SurvivorGroup] = []
			for i in m.survivor_starts.size():
				var g := SurvivorGroup.new(i, char(65 + i), m.survivor_starts[i], m.survivor_sizes[i])
				g.fire_lethal = hz.fire_lethal
				g.smoke_drain = hz.smoke_drain
				groups.append(g)
			for p in hz.place_starting_fires(m, groups):
				for g in groups:
					check(absi(g.tile.x - p.x) + absi(g.tile.y - p.y) >= 3, "round %d seed %d: starting fire %s too close to group %s" % [r, s, p, g.label])
			check(m.fires.size() >= hz.start_fires, "round %d seed %d: only %d of %d starting fires" % [r, s, m.fires.size(), hz.start_fires])
			for g in groups:
				check(m.has_path(g.tile), "round %d seed %d: starting fires cut group %s off" % [r, s, g.label])
			var scorer := ScoreKeeper.new()
			var stuck := {}
			var time := 0.0
			var next_route := THINK
			rounds += 1
			while time < LIMIT:
				var active := false
				for g in groups:
					if not g.is_active():
						continue
					active = true
					if g.can_plan() and time >= next_route:
						var path := m.find_path(g.tile)
						if path.is_empty():
							if not stuck.has(g):
								stuck[g] = true
								stranded += 1
								check(hz.fire_lethal, "round %d seed %d: training fire stranded group %s" % [r, s, g.label])
							continue
						var v := RouteValidator.validate(m, path, g.tile)
						check(v["valid"] and v["complete"], "round %d: auto route invalid: %s" % [r, v["reason"]])
						if g.state == SurvivorGroup.State.BLOCKED:
							detours += 1
						scorer.record_dispatch(g, 1.0, g.state == SurvivorGroup.State.BLOCKED, path.size() - 1, m.shortest_length(g.tile))
						g.dispatch(path)
						next_route = time + THINK
					elif hz.fire_lethal and g.state == SurvivorGroup.State.MOVING and not g.halt_requested and _fire_just_ahead(m, g, 5):
						g.stop(time)
						stops += 1
				if not active:
					break
				for g in groups:
					for ev in g.step(DT, m):
						match ev["type"]:
							"delivered":
								scorer.record_delivery(g)
							"casualty":
								scorer.record_casualty()
							"lost":
								if ev["cause"] == "fire":
									burned += 1
									check(hz.fire_lethal, "round %d seed %d: training fire killed group %s" % [r, s, g.label])
								else:
									smoked += 1
				var window := {}
				for g in groups:
					if g.state == SurvivorGroup.State.MOVING:
						for k in range(g.index, mini(g.index + hz.fair_distance, g.path.size() - 1) + 1):
							window[g.path[k]] = true
				var before := m.smolders.duplicate()
				var lit := hz.update(DT, m, groups)
				ignitions += lit.size()
				for p in lit:
					check(m.get_tile(p) == CityMap.Tile.ROAD, "round %d seed %d: fire on non-road tile %s" % [r, s, p])
				for p in hz.spotted:
					spot_count += 1
					var nearest := 1 << 30
					for g in groups:
						if g.is_active():
							nearest = mini(nearest, mini(absi(g.tile.x - p.x) + absi(g.tile.y - p.y), absi(g.next_tile().x - p.x) + absi(g.next_tile().y - p.y)))
					for q in safe_tiles:
						nearest = mini(nearest, absi(q.x - p.x) + absi(q.y - p.y))
					check(m.get_tile(p) == CityMap.Tile.ROAD and not m.is_road_closure(p), "round %d seed %d: spot fire on non-road tile %s" % [r, s, p])
					check(nearest > 3, "round %d seed %d: spot fire %s within 3 tiles of a group or the safe zone" % [r, s, p])
					check(not window.has(p), "round %d seed %d: spot fire %s inside a fairness window" % [r, s, p])
				for p in m.smolders:
					if before.has(p) or hz.spotted.has(p):
						continue
					var next_to_fire := false
					for d in CityMap.DIRS:
						if m.is_fire(p + d):
							next_to_fire = true
					check(next_to_fire and m.get_tile(p) == CityMap.Tile.ROAD, "round %d seed %d: smolder at %s not on road next to fire" % [r, s, p])
					check(not window.has(p), "round %d seed %d: smolder at %s inside a fairness window" % [r, s, p])
				if not hz.fire_lethal:
					for g in groups:
						if g.is_active():
							check(m.has_path(g.stop_tile()) and not m.is_fire(g.tile), "round %d seed %d: training fire traps group %s" % [r, s, g.label])
				time += DT
			if time >= LIMIT:
				unresolved += 1
			round_secs += time
			for g in groups:
				if g.state == SurvivorGroup.State.DELIVERED:
					delivered += 1
	print("  %s\n    rounds: %d (avg %.0fs), spot fires: %d, ignitions: %d, STOPs: %d, detours: %d, groups delivered: %d, burned: %d, lost to smoke: %d, stranded: %d, unresolved after %.0fs: %d" % [
		label, rounds, round_secs / rounds, spot_count, ignitions, stops, detours, delivered, burned, smoked, stranded, LIMIT, unresolved])
	check(ignitions > 0 and stops > 0 and detours > 0, "%s: spreading fire, STOPs and detours should actually occur" % label)
	check(unresolved * 10 <= rounds, "%s: most rounds should resolve within %.0fs (%d unresolved)" % [label, LIMIT, unresolved])
	check(spots == (spot_count > 0), "%s: spot fires should occur only when enabled (%d)" % [label, spot_count])


## True if fire or a smoldering tile lies within the next `tiles` steps of
## a moving group's remaining route.
func _fire_just_ahead(m: CityMap, g: SurvivorGroup, tiles: int) -> bool:
	for i in range(g.index + 1, mini(g.index + 1 + tiles, g.path.size())):
		if m.is_fire(g.path[i]) or m.is_smoldering(g.path[i]):
			return true
	return false


func test_map_view_alignment() -> void:
	print("\n[map view] tile <-> screen round trip on generated maps")
	var mv := MapView.new()
	var bad := 0
	for r in [2, 5, 9]:
		for view in [Vector2(940, 690), Vector2(500, 900), Vector2(1600, 700)]:
			var m := MapGenerator.build_from_seed(r, 4242 + r)
			mv.map = m
			mv.size = view
			mv._update_layout()
			var frame := Rect2(Vector2.ZERO, view)
			for y in m.height:
				for x in m.width:
					var p := Vector2i(x, y)
					if mv.screen_to_tile(mv.tile_center(p)) != p or not frame.encloses(mv.tile_rect(p)):
						bad += 1
	mv.free()
	print("  misaligned tiles: %d" % bad)
	check(bad == 0, "every tile must map to itself and fit the view")


## Runs the real main scene and plays the start of several procedural rounds.
func test_game_integration() -> void:
	print("\n[game integration] main scene, rounds 1-5")
	var game: Control = load("res://scenes/main.tscn").instantiate()
	game.best_score_path = TEST_BEST_PATH
	root.add_child(game)
	game.rng.seed = 555  # after _ready(), which randomizes it
	for i in 5:
		await process_frame
	for r in range(1, 6):
		game.round_num = r
		game._start_round()
		for i in 10:
			await process_frame
		var m: CityMap = game.map
		check(game.map_view.map == m, "round %d: map view not showing the current map" % r)
		check(game.groups.size() == m.survivor_starts.size(), "round %d: group count mismatch" % r)
		check(not game.round_over, "round %d: round ended immediately" % r)
		validate_map(m, r, "game round %d" % r)
		# Plan and dispatch the first group through the real operator code path.
		game._select_group(game.groups[0])
		for p in m.find_path(game.groups[0].tile).slice(1):
			game._try_extend(p)
		game._dispatch()
		check(game.groups[0].state == SurvivorGroup.State.MOVING, "round %d: dispatch through game controller failed" % r)
		for i in 30:
			await process_frame
		print("  round %d: %s %dx%d, %d groups, log: %s" % [r, m.gen_info.get("source"), m.width, m.height, game.groups.size(), game.log_lines[-1]])
	game.queue_free()
	await process_frame


## Plays round 1 to the end through the game controller (simulated time, live
## hazards, detours), banks the score and advances; then fails round 2, which
## ends the run: GAME OVER shows the banked score, the people saved this run
## and a new best, and TRY AGAIN starts a fresh run from round 1. The best
## score lives in a scratch file that is removed afterwards.
func test_round_flow() -> void:
	print("\n[round flow] play, bank, next round, game over, new run")
	_remove_user_file(TEST_BEST_PATH)
	var game: Control = load("res://scenes/main.tscn").instantiate()
	game.best_score_path = TEST_BEST_PATH
	root.add_child(game)
	await process_frame
	check(game.best_score == 0 and game.best_round == 0, "no best-score file: the best should start at 0")
	game.rng.seed = 777
	game.round_num = 1
	game._start_round()
	var t := 0.0
	while not game.round_over and t < 120.0:
		for g in game.groups:
			if g.can_plan():
				game._select_group(g)
				for p in game.map.find_path(g.tile).slice(1):
					game._try_extend(p)
				game._dispatch()
		game._process(0.05)
		t += 0.05
	check(game.round_over and game.last_round_success, "round 1 should end in success (t=%.1f)" % t)
	check(game.result_panel.visible, "result panel should show")
	var banked: int = game.banked_score
	check(banked == game.scorer.total() and banked > 0, "round score %d should be banked (banked %d)" % [game.scorer.total(), banked])
	var saved_r1: int = game.scorer.delivered
	check(game.run_saved == saved_r1 and saved_r1 > 0, "run_saved should count round 1's survivors (%d vs %d)" % [game.run_saved, saved_r1])
	check(game.lbl_result_title.text == "ROUND COMPLETE" and game.lbl_result_total_title.text == "ROUND SCORE" and game.btn_next.text.begins_with("NEXT ROUND"),
			"a passed round should keep its usual panel")
	game._on_next_pressed()
	check(game.round_num == 2 and not game.round_over and not game.result_panel.visible, "Next Round should start round 2")

	# Fail round 2 by making the remaining group casualties outnumber the
	# survivors still alive, which is the current game-over rule.
	var first: SurvivorGroup = game.groups[0]
	first.survivors = 1
	first.state = SurvivorGroup.State.DELIVERED
	game._on_group_event(first, {"type": "delivered", "tile": first.tile})
	# The other members of the delivered group were not saved, so they also
	# count as casualties under the current deaths-vs-survivors rule.
	var first_lost_count: int = first.initial_survivors - first.survivors
	for j in first_lost_count:
		game.scorer.record_casualty()
	for i in range(1, game.groups.size()):
		var doomed: SurvivorGroup = game.groups[i]
		var failed_lost_count: int = doomed.survivors
		doomed.survivors = 0
		doomed.state = SurvivorGroup.State.LOST
		for j in failed_lost_count:
			game.scorer.record_casualty()
	game._process(0.05)
	check(game.round_over and not game.last_round_success, "one survivor out of round 2 should fail it")
	check(game.banked_score == banked, "a failed round must not bank points")
	check(game.lbl_result_title.text == "GAME OVER", "a failed round should show GAME OVER, got %s" % game.lbl_result_title.text)
	check(game.lbl_result_total_title.text == "FINAL SCORE" and game.lbl_result_total.text == str(banked),
			"GAME OVER should show the banked %d as the final score, got %s" % [banked, game.lbl_result_total.text])
	check(game.run_saved == saved_r1 + 1 and game.lbl_result_saved.text == str(saved_r1 + 1),
			"people saved should include the failed round's survivor (%d, shown %s)" % [game.run_saved, game.lbl_result_saved.text])
	check(game.lbl_result_sub.text.begins_with("REACHED ROUND 2"), "GAME OVER should show the round reached, got %s" % game.lbl_result_sub.text)
	check(game.btn_next.text.begins_with("TRY AGAIN"), "GAME OVER should offer Try Again")
	check(game.new_best and game.best_score == banked and game.best_round == 2 and game.lbl_result_note.text.contains("NEW BEST!"),
			"the first game over should set a new best (%d, round %d)" % [game.best_score, game.best_round])
	game.best_score = 0
	game._load_best_score()
	check(game.best_score == banked and game.best_round == 2, "the best score should survive a reload (%d)" % game.best_score)

	# TRY AGAIN starts a new run.
	game._on_next_pressed()
	check(game.round_num == 1 and game.banked_score == 0 and game.run_saved == 0 and not game.new_best,
			"Try Again should start a new run at round 1 with nothing carried over")
	check(not game.round_over and not game.result_panel.visible and game.lbl_score.text == "0", "the new run should be in play with score 0")

	# Tying the best is not enough; it has to be beaten.
	game.banked_score = banked
	for g in game.groups:
		var retry_lost_count: int = g.survivors
		g.survivors = 0
		g.state = SurvivorGroup.State.LOST
		for j in retry_lost_count:
			game.scorer.record_casualty()
	game._process(0.05)
	check(game.round_over and not game.new_best and game.best_score == banked and not game.lbl_result_note.text.contains("NEW BEST"),
			"a tied score must not count as a new best")
	game._on_next_pressed()
	game.banked_score = banked + 10
	for g in game.groups:
		var best_lost_count: int = g.survivors
		g.survivors = 0
		g.state = SurvivorGroup.State.LOST
		for j in best_lost_count:
			game.scorer.record_casualty()
	game._process(0.05)
	check(game.new_best and game.best_score == banked + 10 and game.best_round == 1, "a higher score should become the new best")
	game.best_score = 0
	game._load_best_score()
	check(game.best_score == banked + 10, "the higher best should be stored (%d)" % game.best_score)
	print("  round 1 cleared in %.1fs of game time, banked %d; round 2 failed -> game over (saved %d, best %d); new runs checked" % [
		t, banked, saved_r1 + 1, banked])
	game.queue_free()
	await process_frame
	_remove_user_file(TEST_BEST_PATH)


## A missing, unreadable or malformed best-score file counts as no best, and a
## failed save is logged; none of them stop the game.
func test_best_score_file() -> void:
	print("\n[best score] missing, broken and unwritable files")
	_remove_user_file(TEST_BEST_PATH)
	var game: Control = load("res://scenes/main.tscn").instantiate()
	game.best_score_path = TEST_BEST_PATH
	root.add_child(game)
	await process_frame
	game._start_round()
	check(game.best_score == 0 and game.best_round == 0, "missing file: the best should be 0")
	var f := FileAccess.open(TEST_BEST_PATH, FileAccess.WRITE)
	f.store_string("[best]\nscore = \"unterminated\nround = {{{\n")
	f.close()
	game.best_score = 123
	game._load_best_score()  # expect one engine parse error in the output
	check(game.best_score == 0 and game.best_round == 0, "unreadable file: the best should be 0")
	var cfg := ConfigFile.new()
	cfg.set_value("best", "score", "lots")
	cfg.set_value("best", "round", 3)
	cfg.save(TEST_BEST_PATH)
	game._load_best_score()
	check(game.best_score == 0 and game.best_round == 0, "malformed values: the best should be 0")
	# A path that can't be written: logged, and play goes on. (Expect one warning.)
	game.best_score_path = "user://no_such_dir/nested/best_score.cfg"
	game.best_score = 50
	game.best_round = 2
	game._save_best_score()
	check(game.log_lines[-1].contains("Could not save the best score"), "a failed save should be logged")
	game.banked_score = 80
	for g in game.groups:
		var lost_count: int = g.survivors
		g.survivors = 0
		g.state = SurvivorGroup.State.LOST
		for j in lost_count:
			game.scorer.record_casualty()
	game._process(0.05)
	check(game.round_over and game.lbl_result_title.text == "GAME OVER" and game.best_score == 80,
			"the game should still end the run and keep the new best in memory")
	game._on_next_pressed()
	check(game.round_num == 1 and not game.round_over, "and a new run should still start")
	print("  missing, unreadable, malformed and unwritable files handled")
	game.queue_free()
	await process_frame
	_remove_user_file(TEST_BEST_PATH)


## A no-route ending must count waiting/blocked groups as lost before deciding
## whether the saved count is high enough to continue.
func test_no_safe_route_flow() -> void:
	print("\n[no safe route] trapped groups and strict saved-vs-lost result")
	var game: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_setup_no_route_case(game, 2, 2)
	game._check_round_end()
	check(game.round_over and not game.last_round_success and game.scorer.lost == 2,
			"equal saved/lost after trapping a group should be game over")
	check(game.lbl_result_title.text == "GAME OVER", "equal no-route result should show GAME OVER")
	_setup_no_route_case(game, 3, 2)
	game._check_round_end()
	check(game.round_over and game.last_round_success and game.scorer.lost == 2,
			"more saved than trapped should continue after a no-safe-route ending")
	check(game.lbl_result_title.text == "NO SAFE ROUTE" and game.btn_next.text.begins_with("NEXT ROUND"),
			"successful no-route result should offer NEXT ROUND")
	print("  equal saved/lost fails; saved > trapped continues")
	game.queue_free()
	await process_frame


func _setup_no_route_case(game: Control, saved: int, trapped: int) -> void:
	var m := CityMap.new()
	m.setup(3, 1, CityMap.Tile.BUILDING)
	m.set_tile(Vector2i(0, 0), CityMap.Tile.ROAD)
	m.set_tile(Vector2i(1, 0), CityMap.Tile.ROAD)
	m.set_tile(Vector2i(2, 0), CityMap.Tile.SAFE)
	m.add_fire(Vector2i(1, 0))
	game.map = m
	game.map_view.map = m
	var delivered := SurvivorGroup.new(0, "A", Vector2i(2, 0), saved)
	delivered.state = SurvivorGroup.State.DELIVERED
	var trapped_group := SurvivorGroup.new(1, "B", Vector2i(0, 0), trapped)
	var test_groups: Array[SurvivorGroup] = [delivered, trapped_group]
	game.groups = test_groups
	game._build_group_rows()
	game.scorer = ScoreKeeper.new()
	game.scorer.delivered = saved
	game.round_over = false
	game.last_round_success = false
	game.result_panel.visible = false


## The main menu draws its own dimmed backdrop city without starting a round.
## START replaces it with a fresh round 1 and fades the menu out; settings keeps
## END GAME and BACK tied to where it was opened; MAIN MENU brings the menu back.
func test_main_menu() -> void:
	print("\n[main menu] backdrop, start, settings, return")
	_remove_user_file(TEST_BEST_PATH)
	var game: Control = load("res://scenes/main.tscn").instantiate()
	game.best_score_path = TEST_BEST_PATH
	root.add_child(game)
	await process_frame
	var backdrop: CityMap = game.map_view.map
	check(game.main_menu_overlay.visible and game.main_menu_card.visible, "the main menu should show at start-up")
	check(game.map == null and backdrop != null and not backdrop.fires.is_empty(),
			"the menu should draw a burning backdrop city without starting a round")
	check(game.lbl_menu_best.text == "----", "no best score should read ---- (%s)" % game.lbl_menu_best.text)
	game._show_settings_from_menu()
	check(game.settings_panel.visible and not game.btn_end_game.visible, "END GAME must stay hidden in menu settings")
	game._on_settings_back_pressed()
	check(game.main_menu_card.visible and not game.settings_panel.visible and game.map_view.map == backdrop,
			"BACK from menu settings should return to the same menu")
	game._on_start_game_pressed()
	check(game.game_started and game.round_num == 1 and game.map != null and game.map != backdrop,
			"START should build a fresh round 1 map")
	await process_frame
	check(game.map_view.map == game.map and not game.round_over, "the round map should replace the backdrop")
	await create_timer(0.5).timeout
	check(not game.main_menu_overlay.visible, "the menu should fade out into the round")
	game._show_settings_from_game()
	check(game.main_menu_overlay.visible and game.main_menu_overlay.modulate.a == 1.0 and game.btn_end_game.visible
			and not game.btn_end_game.disabled, "in-game settings should show an active END GAME")
	game._on_settings_back_pressed()
	check(not game.main_menu_overlay.visible and not game.round_over, "BACK from in-game settings should resume the round")
	game._show_settings_from_game()
	game._on_settings_end_game_pressed()
	check(game.round_over and game.lbl_result_title.text == "GAME OVER", "END GAME should open the game-over panel")
	game.best_score = 120
	game.best_round = 3
	game._on_main_menu_pressed()
	await process_frame
	check(game.main_menu_card.visible and game.map_view.map != game.map and game.map_view.map != null,
			"MAIN MENU should show the menu over a new backdrop")
	check(game.lbl_menu_best.text == "120" and game.lbl_menu_best_round.text == "ROUND 3",
			"the menu LCD should show the best score (%s)" % game.lbl_menu_best.text)
	print("  backdrop kept apart from the round; settings and menu routes intact")
	game.queue_free()
	await process_frame
	_remove_user_file(TEST_BEST_PATH)


func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
