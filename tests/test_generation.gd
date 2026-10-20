extends SceneTree
## Headless integration tests for procedural map generation and the systems
## that consume generated maps. Run from the project folder:
##   godot --headless --path . --script res://tests/test_generation.gd
## Optional user args (after `--`): --seeds=N (default 20 per round).
## Exits with code 0 when every check passes, 1 otherwise.

var failures := 0
var checks := 0
var seeds_per_round := 20


func _initialize() -> void:
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
	test_gameplay_simulation()
	test_map_view_alignment()
	await test_game_integration()
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
	ok = check(m.fires.size() <= MapGenerator.pre_fire_count_for(round_num), "%s: too many pre-fires" % tag) and ok
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
	return ok


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
					and a.gen_info == b.gen_info and a.width == b.width
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


## Plays rounds automatically: dispatches every group along its shortest path,
## lets HazardManager drop fires, and re-routes halted groups. No group may
## ever be left without a path to safety.
func test_gameplay_simulation() -> void:
	print("\n[gameplay simulation] rounds 2-9 x 6 seeds, auto-dispatch with live hazards")
	var rounds := 0
	var fires_total := 0
	var detours := 0
	var delivered := 0
	var lost := 0
	var stranded := 0
	var timeouts := 0
	for r in range(2, 10):
		for s in 6:
			var m := MapGenerator.build_from_seed(r, 9000 + 10 * r + s)
			var rng := RandomNumberGenerator.new()
			rng.seed = 31337 + s
			var groups: Array[SurvivorGroup] = []
			for i in m.survivor_starts.size():
				groups.append(SurvivorGroup.new(i, char(65 + i), m.survivor_starts[i], m.survivor_sizes[i]))
			var hz := HazardManager.new()
			hz.setup(r, rng)
			var scorer := ScoreKeeper.new()
			var time := 0.0
			rounds += 1
			while time < 240.0:
				var active := false
				for g in groups:
					if g.is_active():
						active = true
					if g.can_plan():
						var path := m.find_path(g.tile)
						if path.is_empty():
							stranded += 1
							check(false, "round %d seed %d: group %s stranded at %s" % [r, s, g.label, g.tile])
							g.state = SurvivorGroup.State.LOST
							continue
						var v := RouteValidator.validate(m, path, g.tile)
						check(v["valid"] and v["complete"], "round %d: auto route invalid: %s" % [r, v["reason"]])
						if g.state == SurvivorGroup.State.BLOCKED:
							detours += 1
						scorer.record_dispatch(g, 1.0, g.state == SurvivorGroup.State.BLOCKED, path.size() - 1, m.shortest_length(g.tile))
						g.dispatch(path)
						hz.on_dispatch()
				if not active:
					break
				for g in groups:
					for ev in g.step(0.05, m):
						if ev["type"] == "delivered":
							scorer.record_delivery(g)
				var fire := hz.update(0.05, m, groups)
				if fire != CityMap.NO_TILE:
					fires_total += 1
					for g in groups:
						if g.remaining_contains(fire):
							g.request_halt(fire, time)
					for g in groups:
						if g.is_active():
							check(m.has_path(g.stop_tile()), "round %d: fire at %s strands group %s" % [r, fire, g.label])
				time += 0.05
			if time >= 240.0:
				timeouts += 1
				check(false, "round %d seed %d: simulation timed out" % [r, s])
			for g in groups:
				if g.state == SurvivorGroup.State.DELIVERED:
					delivered += 1
				elif g.state == SurvivorGroup.State.LOST:
					lost += 1
			check(scorer.total() > 0, "round %d seed %d: scoring produced %d" % [r, s, scorer.total()])
	print("  rounds: %d, live fires: %d, detours: %d, groups delivered: %d, lost to smoke: %d, stranded: %d, timeouts: %d" % [
		rounds, fires_total, detours, delivered, lost, stranded, timeouts])
	check(fires_total > 0 and detours > 0, "hazards and detours should actually occur")


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
