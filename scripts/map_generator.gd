class_name MapGenerator
extends RefCounted
## Builds the city for each round.
## Round 1 is a fixed, hand-authored training map. Later rounds grow their road
## network with a Physarum (slime mould) simulation started from a randomized
## colony center (see PhysarumSim), then organize the result into a top-down
## city plan: orthogonal avenues, side streets, building blocks and cross-links.
## If that fails validation a bounded number of times, the older street lattice
## (which always has alternate routes) is tried, and finally the hand-authored
## map, so a round can always be played.
## After the roads exist, both generators share the same steps: survivors are
## placed, road segments are closed and fires pre-placed one at a time, and any
## change that would strand a group or remove its detours is reverted.
## Only a map that passed validation gets a city plan (CityLayout: building
## lots, safe-zone building, road classes). The plan never changes a tile, and
## it draws from the RNG last, so the same seed still yields the same tiles.
##
## Seeds: build_round() draws one map seed from the caller's RNG. Every attempt
## then uses its own RandomNumberGenerator derived from (map seed, round,
## attempt), so build_from_seed() with the same arguments rebuilds the same map.

## Legend: '.' road, '#' building, 'P' park, 'S' safe zone,
## 'A'..'Z' survivor group start (on a road tile).
const HANDMADE_LAYOUT := [
	"..B......###.........",
	".###.###.###.###.###.",
	".###.###.....###.###.",
	".###.###.###.###.###.",
	".....................",
	".###.###.#######.SSS.",
	".###.###.#######.SSS.",
	".###.###.#######.SSS.",
	".............###.....",
	".#######.###.PPP.###.",
	"A#######.###.PPP.###.",
	".#######.###.PPP.###.",
	".....................",
]
const HANDMADE_SIZES := [5, 4]

const PHYSARUM_ATTEMPTS := 12
const LATTICE_ATTEMPTS := 40
## Attempt budgets (default to the constants above). Tests lower them to
## exercise the fallback chain; the lattice seeds stay offset by the constant.
static var physarum_attempts := PHYSARUM_ATTEMPTS
static var lattice_attempts := LATTICE_ATTEMPTS
const SAFE_SIZE := Vector2i(3, 3)
## Tiles kept clear between the colony's spawn disc and the map edge.
const CENTER_MARGIN := 2.0
## Preferred minimum distance (tiles) from the colony center to the safe zone.
const CENTER_SAFE_DIST := 4.0
## Minimum mean trail along a loop-forming link for it to become a road.
const LINK_SUPPORT := 0.15
## Road-carving costs per tile entered. Strong trail is as cheap as existing
## road; untouched ground costs up to ROAD_COST + TRAIL_COST_SPAN. Ground next
## to an existing road costs extra so new roads don't hug old ones.
const ROAD_COST := 2
const TRAIL_COST_SPAN := 10
const BESIDE_ROAD_COST := 4
const MAX_REINFORCEMENTS := 40
const BYPASS_CLEARANCE := 2
## Cut-off pieces smaller than this (in street tiles) are not bypassed.
const MIN_BYPASS_SIDE := 4
## Longest stretch of organic road that may be closed as rubble.
const MAX_CLOSURE_LENGTH := 4
## Map area (tiles) per food source.
const AREA_PER_FOOD := 24.0
## City blocks are deliberately small enough to produce several alternate
## routes, while still leaving building clusters between streets.
const CITY_MIN_BLOCK_WIDTH := 2
const CITY_AVENUE_WIDTH := 2


static func build_round(round_num: int, rng: RandomNumberGenerator) -> CityMap:
	return build_from_seed(round_num, rng.randi())


static func build_from_seed(round_num: int, map_seed: int) -> CityMap:
	if round_num <= 1:
		var hm := build_handmade()
		hm.gen_info = {"source": "handmade", "seed": map_seed, "attempt": 0}
		return hm
	for attempt in physarum_attempts:
		var m := _try_physarum(round_num, attempt_rng(map_seed, round_num, attempt))
		if m != null:
			m.gen_info.merge({"source": "physarum", "seed": map_seed, "attempt": attempt}, true)
			return m
	push_warning("Physarum generation failed %d times (seed %d); using the street lattice." % [physarum_attempts, map_seed])
	for attempt in lattice_attempts:
		var m := _try_lattice(round_num, attempt_rng(map_seed, round_num, PHYSARUM_ATTEMPTS + attempt))
		if m != null:
			m.gen_info = {"source": "lattice", "seed": map_seed, "attempt": PHYSARUM_ATTEMPTS + attempt}
			return m
	push_warning("Procedural generation failed (seed %d); using the hand-authored map." % map_seed)
	var fallback := build_handmade()
	fallback.gen_info = {"source": "handmade", "seed": map_seed, "attempt": -1}
	return fallback


## Independent, reproducible RNG per generation attempt. Plain integer mixing
## (not hash()) keeps seeds stable across engine versions.
static func attempt_rng(map_seed: int, round_num: int, attempt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = map_seed * 1000003 + round_num * 7919 + attempt * 104729
	return r


static func build_handmade() -> CityMap:
	var m := CityMap.new()
	var w: int = HANDMADE_LAYOUT[0].length()
	m.setup(w, HANDMADE_LAYOUT.size(), CityMap.Tile.BUILDING)
	var starts := {}
	for y in HANDMADE_LAYOUT.size():
		var row: String = HANDMADE_LAYOUT[y]
		if row.length() != w:
			push_error("HANDMADE_LAYOUT row %d has length %d, expected %d" % [y, row.length(), w])
		for x in row.length():
			var c := row[x]
			var p := Vector2i(x, y)
			match c:
				".":
					m.set_tile(p, CityMap.Tile.ROAD)
				"S":
					m.set_tile(p, CityMap.Tile.SAFE)
				"P":
					m.set_tile(p, CityMap.Tile.PARK)
				"#":
					m.set_tile(p, CityMap.Tile.BUILDING)
				_:
					m.set_tile(p, CityMap.Tile.ROAD)
					starts[c] = p
	var keys := starts.keys()
	keys.sort()
	for i in keys.size():
		m.survivor_starts.append(starts[keys[i]])
		m.survivor_sizes.append(HANDMADE_SIZES[i % HANDMADE_SIZES.size()])
	# Fixed seed: the training map always has the same buildings.
	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = 1
	CityLayout.build(m, layout_rng)
	return m


## Difficulty knobs, all growing slowly with the round number.
static func group_count_for(round_num: int) -> int:
	return mini(2 + floori((round_num - 1) / 2.0), 5)


static func pre_fire_count_for(round_num: int) -> int:
	return mini(round_num - 1, 6)


static func closure_count_for(round_num: int) -> int:
	return mini(2 + round_num, 10)


## Map size in tiles; matches the footprint of the lattice at the same round.
static func map_size_for(round_num: int, rng: RandomNumberGenerator) -> Vector2i:
	var w := 1 + roundi(3.5 * mini(4 + round_num, 9)) + rng.randi_range(-1, 1)
	var h := 1 + roundi(3.5 * mini(3 + floori(round_num / 2.0), 6)) + rng.randi_range(-1, 1)
	return Vector2i(w, h)


# --- Physarum generator ---------------------------------------------------------

## `forced_center` (tile coordinates) bypasses the random center; tests use it
## to probe centers on the edge of the allowed region.
static func _try_physarum(round_num: int, rng: RandomNumberGenerator, forced_center := Vector2(-1, -1)) -> CityMap:
	var size := map_size_for(round_num, rng)
	var m := CityMap.new()
	m.setup(size.x, size.y, CityMap.Tile.BUILDING)

	# 1. Safe zone: a plaza one tile in from a random edge, ringed by road so it
	#    can be entered from several sides.
	var safe := _place_safe_zone(m, rng)

	# 2. Colony center, randomized per attempt and kept inside the margins.
	var radius := clampf(minf(size.x, size.y) * 0.12, 1.5, 3.0)
	var center := forced_center
	if center.x < 0.0:
		center = PhysarumSim.pick_center(size.x, size.y, radius, CENTER_MARGIN, rng, safe, CENTER_SAFE_DIST)
	var center_tile := Vector2i(clampi(floori(center.x), 0, size.x - 1), clampi(floori(center.y), 0, size.y - 1))

	# 3. Food sources scattered over the whole map (not around its middle), plus
	#    a strong one at the safe zone so the network always reaches it.
	var safe_entry := _safe_entry(m, safe, center)
	var foods := _scatter_foods(m, rng, safe)
	var food_tiles: Array[Vector2i] = [safe_entry]
	var weights: Array[float] = [3.0]
	for f in foods:
		food_tiles.append(f)
		weights.append(1.0)

	# 4. Grow the slime mould.
	var sim := PhysarumSim.new()
	sim.setup(size.x, size.y, center, radius, food_tiles, weights)
	sim.run(rng)
	var trail := sim.tile_trail()

	# 5. Establish a street plan first. The Physarum field decides which of the
	#    planned streets become wider avenues, while the regular orthogonal plan
	#    gives the map the multiple routes and block structure of a city.
	var city_info := _lay_city_grid(m, round_num, trail, rng)

	# 6. Roads follow the veins: link the colony center, the food and the
	#    junctions the colony formed by its own accord. Existing city streets are
	#    cheap, so these connectors generally reuse the grid and create extra
	#    district-to-district routes instead of isolated organic branches.
	var nodes: Array[Vector2i] = [safe_entry, center_tile]
	for f in foods:
		if not nodes.has(f):
			nodes.append(f)
	for j in _trail_junctions(m, trail, nodes, maxi(2, foods.size() >> 1)):
		nodes.append(j)
	_carve_links(m, trail, nodes)

	# 7. Clean up: keep only roads joined to the safe zone, thin 2x2 road
	#    blobs, add bypasses around single points of failure until every road
	#    tile has a detour (or the budget runs out), thin again, then drop
	#    whatever dead ends are left.
	_keep_safe_component(m)
	_thin_blobs(m)
	_reinforce(m, trail)
	_thin_blobs(m)
	_prune_dead_ends(m)
	_sprinkle_parks(m, rng)
	m.gen_info = {"center": center, "spawn_radius": radius, "steps": sim.steps_run, "nodes": nodes.size(), "city": city_info}

	# 8. Shared gameplay steps.
	if not _place_survivors(m, round_num, rng):
		return null
	_close_segments(m, _road_segments(m), closure_count_for(round_num), rng)
	_place_pre_fires(m, pre_fire_count_for(round_num), rng)
	return _finish(m, rng)


static func _place_safe_zone(m: CityMap, rng: RandomNumberGenerator) -> Rect2i:
	var edge := rng.randi() % 4
	var pos := Vector2i.ZERO
	if edge == 0 or edge == 1:  # top / bottom
		pos.x = rng.randi_range(1, m.width - 1 - SAFE_SIZE.x)
		pos.y = 1 if edge == 0 else m.height - 1 - SAFE_SIZE.y
	else:  # left / right
		pos.y = rng.randi_range(1, m.height - 1 - SAFE_SIZE.y)
		pos.x = 1 if edge == 2 else m.width - 1 - SAFE_SIZE.x
	var safe := Rect2i(pos, SAFE_SIZE)
	var ring := safe.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var p := Vector2i(x, y)
			m.set_tile(p, CityMap.Tile.SAFE if safe.has_point(p) else CityMap.Tile.ROAD)
	return safe


## The ring-road tile nearest the colony; the network's anchor at the safe zone.
static func _safe_entry(m: CityMap, safe: Rect2i, center: Vector2) -> Vector2i:
	var ring := safe.grow(1)
	var best := ring.position
	var best_d := INF
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var p := Vector2i(x, y)
			if m.get_tile(p) != CityMap.Tile.ROAD:
				continue
			var d := center.distance_squared_to(Vector2(p) + Vector2(0.5, 0.5))
			if d < best_d:
				best_d = d
				best = p
	return best


## Roughly evenly spaced food tiles over the map (bounded dart throwing).
static func _scatter_foods(m: CityMap, rng: RandomNumberGenerator, safe: Rect2i) -> Array[Vector2i]:
	var count := clampi(roundi(m.width * m.height / AREA_PER_FOOD), 6, 24)
	var min_sep := sqrt(m.width * m.height / float(count)) * 0.75
	var keep_out := safe.grow(2)
	var out: Array[Vector2i] = []
	for i in count * 30:
		if out.size() >= count:
			break
		var p := Vector2i(rng.randi_range(1, m.width - 2), rng.randi_range(1, m.height - 2))
		if keep_out.has_point(p):
			continue
		var ok := true
		for q in out:
			if Vector2(p).distance_to(Vector2(q)) < min_sep:
				ok = false
				break
		if ok:
			out.append(p)
	return out


## Strong local trail maxima away from existing nodes: the junctions the
## colony formed on its own (its Steiner points).
static func _trail_junctions(m: CityMap, trail: PackedFloat32Array, nodes: Array[Vector2i], limit: int) -> Array[Vector2i]:
	var peaks: Array[Vector2i] = []
	for y in range(1, m.height - 1):
		for x in range(1, m.width - 1):
			var v := trail[y * m.width + x]
			if v < 0.6 or m.get_tile(Vector2i(x, y)) != CityMap.Tile.BUILDING:
				continue
			var is_peak := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var q := Vector2i(x + dx, y + dy)
					if m.in_bounds(q) and trail[q.y * m.width + q.x] > v:
						is_peak = false
			if is_peak:
				peaks.append(Vector2i(x, y))
	# Strongest first; ties broken by position so the order is deterministic.
	peaks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ta := trail[a.y * m.width + a.x]
		var tb := trail[b.y * m.width + b.x]
		return ta > tb or (ta == tb and (a.y * m.width + a.x) < (b.y * m.width + b.x)))
	var out: Array[Vector2i] = []
	for p in peaks:
		if out.size() >= limit:
			break
		var ok := true
		for q in nodes + out:
			if absi(p.x - q.x) + absi(p.y - q.y) < 4:
				ok = false
				break
		if ok:
			out.append(p)
	return out


## Builds a compact top-down street plan with unevenly spaced city blocks.
## The base plan is a connected grid, so every district has several ways to
## reach the safe zone. Physarum's trail field chooses the two main avenues;
## making those streets wider gives the organic simulation a visible effect
## without allowing it to collapse the whole map into one long corridor.
static func _lay_city_grid(m: CityMap, round_num: int, trail: PackedFloat32Array, rng: RandomNumberGenerator) -> Dictionary:
	var blocks_x := mini(4 + round_num, 9)
	var blocks_y := mini(3 + floori(round_num / 2.0), 6)
	var xs := _city_line_positions(m.width, blocks_x, rng)
	var ys := _city_line_positions(m.height, blocks_y, rng)
	for x in xs:
		for y in m.height:
			if not m.is_safe(Vector2i(x, y)):
				m.set_tile(Vector2i(x, y), CityMap.Tile.ROAD)
	for y in ys:
		for x in m.width:
			if not m.is_safe(Vector2i(x, y)):
				m.set_tile(Vector2i(x, y), CityMap.Tile.ROAD)

	var avenue_x := _strongest_city_line(trail, m.width, m.height, xs, true)
	var avenue_y := _strongest_city_line(trail, m.width, m.height, ys, false)
	# Two-tile avenues are selected from the simulated trail, so different map
	# seeds produce different district hierarchies while keeping the grid legible.
	for offset in CITY_AVENUE_WIDTH:
		var x := avenue_x + offset
		if x < 0 or x >= m.width:
			continue
		for y in m.height:
			if not m.is_safe(Vector2i(x, y)):
				m.set_tile(Vector2i(x, y), CityMap.Tile.ROAD)
	for offset in CITY_AVENUE_WIDTH:
		var y := avenue_y + offset
		if y < 0 or y >= m.height:
			continue
		for x in m.width:
			if not m.is_safe(Vector2i(x, y)):
				m.set_tile(Vector2i(x, y), CityMap.Tile.ROAD)
	return {"blocks_x": blocks_x, "blocks_y": blocks_y, "avenue_x": avenue_x, "avenue_y": avenue_y}


## Uneven but bounded line positions: the blocks read as planned city parcels,
## while a small seed-dependent offset prevents every round from looking alike.
static func _city_line_positions(extent: int, block_count: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = [0]
	for i in range(1, block_count):
		var ideal := roundi(float(extent - 1) * float(i) / float(block_count))
		var min_pos := out[-1] + CITY_MIN_BLOCK_WIDTH
		var max_pos := (extent - 1) - CITY_MIN_BLOCK_WIDTH * (block_count - i)
		out.append(clampi(ideal + rng.randi_range(-1, 1), min_pos, max_pos))
	out.append(extent - 1)
	return out


static func _strongest_city_line(trail: PackedFloat32Array, width: int, height: int,
		lines: Array[int], vertical: bool) -> int:
	var best_line := lines[0]
	var best_score := -1.0
	for line in lines:
		var score := 0.0
		var count := 0
		if vertical:
			for y in height:
				score += trail[y * width + line]
				count += 1
		else:
			for x in width:
				score += trail[line * width + x]
				count += 1
		score /= float(maxi(count, 1))
		if score > best_score:
			best_score = score
			best_line = line
	return best_line


## Chooses which nodes to link. Candidates are the Gabriel graph of the nodes
## (a proximity graph that Physarum networks are known to approximate). Its
## minimum spanning tree, weighted toward strong trail, is always kept so every
## node is connected; the remaining loop-forming links are kept only where the
## colony actually grew a vein between the two nodes.
static func _link_pairs(trail: PackedFloat32Array, width: int, nodes: Array[Vector2i]) -> Array:
	var n := nodes.size()
	var cands := []  # [weight, i, j, support]
	for i in n:
		for j in range(i + 1, n):
			var a := Vector2(nodes[i])
			var b := Vector2(nodes[j])
			var mid := (a + b) * 0.5
			var r2 := a.distance_squared_to(mid)
			var gabriel := true
			for k in n:
				if k != i and k != j and Vector2(nodes[k]).distance_squared_to(mid) < r2:
					gabriel = false
					break
			if not gabriel:
				continue
			var support := _line_support(trail, width, nodes[i], nodes[j])
			cands.append([a.distance_to(b) * (1.5 - support), i, j, support])
	cands.sort_custom(func(x: Array, y: Array) -> bool:
		return x[0] < y[0] or (x[0] == y[0] and (x[1] < y[1] or (x[1] == y[1] and x[2] < y[2]))))
	var root: Array[int] = []
	for i in n:
		root.append(i)
	var out := []
	for c in cands:
		var ri := _find_root(root, c[1])
		var rj := _find_root(root, c[2])
		if ri != rj:
			root[ri] = rj
			out.append(Vector2i(c[1], c[2]))
		elif c[3] >= LINK_SUPPORT:
			out.append(Vector2i(c[1], c[2]))
	return out


static func _find_root(root: Array[int], i: int) -> int:
	while root[i] != i:
		root[i] = root[root[i]]
		i = root[i]
	return i


## Mean normalized trail sampled along the straight line between two tiles.
static func _line_support(trail: PackedFloat32Array, width: int, a: Vector2i, b: Vector2i) -> float:
	var samples := maxi(2, ceili(Vector2(a).distance_to(Vector2(b)) * 2.0))
	var s := 0.0
	for i in samples + 1:
		var p := (Vector2(a) + Vector2(0.5, 0.5)).lerp(Vector2(b) + Vector2(0.5, 0.5), float(i) / samples)
		s += trail[int(p.y) * width + int(p.x)]
	return s / (samples + 1)


## Carves the chosen links as cheapest paths over the trail field, shortest
## links first so later links can reuse earlier roads.
static func _carve_links(m: CityMap, trail: PackedFloat32Array, nodes: Array[Vector2i]) -> void:
	var pairs := _link_pairs(trail, m.width, nodes)
	pairs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var la := absi(nodes[a.x].x - nodes[a.y].x) + absi(nodes[a.x].y - nodes[a.y].y)
		var lb := absi(nodes[b.x].x - nodes[b.y].x) + absi(nodes[b.x].y - nodes[b.y].y)
		return la < lb or (la == lb and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	for pair in pairs:
		var a: Vector2i = nodes[pair.x]
		var b: Vector2i = nodes[pair.y]
		var target := PackedByteArray()
		target.resize(m.width * m.height)
		target[b.y * m.width + b.x] = 1
		_carve(m, _cheapest_path(m, trail, PackedInt32Array([a.y * m.width + a.x]), target, PackedByteArray()))
		if m.get_tile(a) != CityMap.Tile.SAFE:
			m.set_tile(a, CityMap.Tile.ROAD)


static func _carve(m: CityMap, path: PackedInt32Array) -> void:
	for idx in path:
		if m.tiles[idx] != CityMap.Tile.SAFE:
			m.tiles[idx] = CityMap.Tile.ROAD


## Dijkstra from any of `sources` to the nearest tile flagged in `target`
## (flat indices). Safe-zone tiles can only be entered as a target, and tiles
## flagged in `blocked` (may be empty) never. Returns the path, or empty.
static func _cheapest_path(m: CityMap, trail: PackedFloat32Array, sources: PackedInt32Array,
		target: PackedByteArray, blocked: PackedByteArray) -> PackedInt32Array:
	var n := m.width * m.height
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var heap := MinHeap.new()
	for s in sources:
		dist[s] = 0
		parent[s] = s
		heap.push(0, s)
	var goal := -1
	while not heap.is_empty():
		var top := heap.pop()
		var cur: int = top & (MinHeap.KEY_SCALE - 1)
		var d: int = top >> MinHeap.KEY_SHIFT
		if d > dist[cur]:
			continue
		if target[cur] == 1:
			goal = cur
			break
		var x := cur % m.width
		for k in 4:
			if (k == 0 and x == m.width - 1) or (k == 1 and x == 0):
				continue
			var nb := cur + 1 if k == 0 else (cur - 1 if k == 1 else (cur + m.width if k == 2 else cur - m.width))
			if nb < 0 or nb >= n or (not blocked.is_empty() and blocked[nb] == 1):
				continue
			var step := _step_cost(m, trail, nb, target[nb] == 1)
			if step < 0:
				continue
			var nd := d + step
			if dist[nb] == -1 or nd < dist[nb]:
				dist[nb] = nd
				parent[nb] = cur
				heap.push(nd, nb)
	var path := PackedInt32Array()
	if goal == -1:
		return path
	var c := goal
	while parent[c] != c:
		path.append(c)
		c = parent[c]
	path.append(c)
	path.reverse()
	return path


static func _step_cost(m: CityMap, trail: PackedFloat32Array, idx: int, is_target: bool) -> int:
	if is_target:
		return ROAD_COST
	var t := m.tiles[idx]
	if t == CityMap.Tile.SAFE:
		return -1
	if t == CityMap.Tile.ROAD:
		return ROAD_COST
	var weak := 1.0 - trail[idx]
	var cost := ROAD_COST + roundi(weak * weak * TRAIL_COST_SPAN)
	@warning_ignore("integer_division")
	if m.street_neighbor_count(Vector2i(idx % m.width, idx / m.width)) > 0:
		cost += BESIDE_ROAD_COST
	return cost


## Roads that cannot reach the safe zone are turned back into buildings.
static func _keep_safe_component(m: CityMap) -> void:
	var reach := m.distance_field()
	for i in m.tiles.size():
		if m.tiles[i] == CityMap.Tile.ROAD and reach[i] == -1:
			m.tiles[i] = CityMap.Tile.BUILDING


## Removes one corner of any 2x2 block of road when that corner has no road
## outside the block, so the remaining three tiles stay connected.
static func _thin_blobs(m: CityMap) -> void:
	for y in m.height - 1:
		for x in m.width - 1:
			var quad: Array[Vector2i] = [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]
			var all_road := true
			for q in quad:
				if m.get_tile(q) != CityMap.Tile.ROAD:
					all_road = false
			if not all_road:
				continue
			for q in quad:
				var outside := 0
				for d in CityMap.DIRS:
					var nb: Vector2i = q + d
					if not quad.has(nb) and m.is_street(nb):
						outside += 1
				if outside == 0:
					m.set_tile(q, CityMap.Tile.BUILDING)
					break


static func _prune_dead_ends(m: CityMap) -> void:
	var changed := true
	while changed:
		changed = false
		for y in m.height:
			for x in m.width:
				var p := Vector2i(x, y)
				if m.get_tile(p) == CityMap.Tile.ROAD and m.street_neighbor_count(p) <= 1:
					m.set_tile(p, CityMap.Tile.BUILDING)
					changed = true


## Repeatedly finds a road tile whose loss would cut part of the network off
## from the safe zone (an articulation point), starting with the one nearest
## the safe zone, and carves the cheapest bypass from the cut-off side back to
## the rest. The bypass keeps BYPASS_CLEARANCE tiles away from the weak point
## so it forms a real block instead of a one-tile bump. Small cut-off pieces
## are left alone (dead ends are pruned afterwards). Bounded by
## MAX_REINFORCEMENTS.
static func _reinforce(m: CityMap, trail: PackedFloat32Array) -> void:
	var skip := {}
	for i in MAX_REINFORCEMENTS:
		var aps := articulation_points(m)
		var dist := m.distance_field()
		var best := -1
		for idx in aps:
			if m.tiles[idx] != CityMap.Tile.ROAD or skip.has(idx):
				continue
			if best == -1 or dist[idx] < dist[best] or (dist[idx] == dist[best] and idx < best):
				best = idx
		if best == -1:
			return
		var reach := _reach_from_safe(m, best)
		var fixed := false
		for clearance in range(BYPASS_CLEARANCE, 0, -1):
			var block := _diamond_mask(m, best, clearance)
			var target := reach.duplicate()
			var sources := PackedInt32Array()
			for idx in m.tiles.size():
				if block[idx] == 1:
					target[idx] = 0
					continue
				var t := m.tiles[idx]
				if reach[idx] == 0 and (t == CityMap.Tile.ROAD or t == CityMap.Tile.SAFE):
					sources.append(idx)
			if sources.size() < MIN_BYPASS_SIDE:
				continue
			var path := _cheapest_path(m, trail, sources, target, block)
			if not path.is_empty():
				_carve(m, path)
				fixed = true
				break
		if not fixed:
			skip[best] = true


## Flags every tile within Manhattan distance `r` of flat index `center`.
static func _diamond_mask(m: CityMap, center: int, r: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(m.tiles.size())
	var cx := center % m.width
	@warning_ignore("integer_division")
	var cy := center / m.width
	for dy in range(-r, r + 1):
		for dx in range(-(r - absi(dy)), r - absi(dy) + 1):
			var q := Vector2i(cx + dx, cy + dy)
			if m.in_bounds(q):
				mask[q.y * m.width + q.x] = 1
	return mask


## Flags (1) every street tile reachable from the safe zone without `blocked`.
static func _reach_from_safe(m: CityMap, blocked: int) -> PackedByteArray:
	var reach := PackedByteArray()
	reach.resize(m.tiles.size())
	var queue: Array[int] = []
	for i in m.tiles.size():
		if m.tiles[i] == CityMap.Tile.SAFE:
			reach[i] = 1
			queue.append(i)
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		@warning_ignore("integer_division")
		var p := Vector2i(cur % m.width, cur / m.width)
		for d in CityMap.DIRS:
			var q: Vector2i = p + d
			var qi := q.y * m.width + q.x
			if m.in_bounds(q) and qi != blocked and reach[qi] == 0 and m.is_street(q):
				reach[qi] = 1
				queue.append(qi)
	return reach


## Street tiles (flat indices) whose removal disconnects the street graph.
## Iterative Tarjan, so deep road chains cannot overflow the call stack.
static func articulation_points(m: CityMap) -> PackedInt32Array:
	var n := m.tiles.size()
	var disc := PackedInt32Array()
	disc.resize(n)
	disc.fill(-1)
	var low := PackedInt32Array()
	low.resize(n)
	var par := PackedInt32Array()
	par.resize(n)
	par.fill(-1)
	var is_ap := PackedByteArray()
	is_ap.resize(n)
	var timer := 0
	var stack_node := PackedInt32Array()
	var stack_dir := PackedInt32Array()
	for s in n:
		if disc[s] != -1 or (m.tiles[s] != CityMap.Tile.ROAD and m.tiles[s] != CityMap.Tile.SAFE):
			continue
		disc[s] = timer
		low[s] = timer
		timer += 1
		var root_children := 0
		stack_node.append(s)
		stack_dir.append(0)
		while not stack_node.is_empty():
			var top := stack_node.size() - 1
			var u := stack_node[top]
			var k := stack_dir[top]
			if k < 4:
				stack_dir[top] = k + 1
				var x := u % m.width
				if (k == 0 and x == m.width - 1) or (k == 1 and x == 0):
					continue
				var v := u + 1 if k == 0 else (u - 1 if k == 1 else (u + m.width if k == 2 else u - m.width))
				if v < 0 or v >= n or (m.tiles[v] != CityMap.Tile.ROAD and m.tiles[v] != CityMap.Tile.SAFE):
					continue
				if disc[v] == -1:
					par[v] = u
					disc[v] = timer
					low[v] = timer
					timer += 1
					stack_node.append(v)
					stack_dir.append(0)
					if u == s:
						root_children += 1
				elif v != par[u]:
					low[u] = mini(low[u], disc[v])
			else:
				stack_node.resize(top)
				stack_dir.resize(top)
				var p := par[u]
				if p != -1:
					low[p] = mini(low[p], low[u])
					if par[p] != -1 and low[u] >= disc[p]:
						is_ap[p] = 1
		if root_children > 1:
			is_ap[s] = 1
	var out := PackedInt32Array()
	for i in n:
		if is_ap[i] == 1:
			out.append(i)
	return out


## Small enclosed building clusters occasionally become parks (cosmetic).
static func _sprinkle_parks(m: CityMap, rng: RandomNumberGenerator) -> void:
	var seen := PackedByteArray()
	seen.resize(m.tiles.size())
	for start in m.tiles.size():
		if seen[start] == 1 or m.tiles[start] != CityMap.Tile.BUILDING:
			continue
		var comp: Array[int] = [start]
		seen[start] = 1
		var head := 0
		while head < comp.size():
			var cur := comp[head]
			head += 1
			@warning_ignore("integer_division")
			var p := Vector2i(cur % m.width, cur / m.width)
			for d in CityMap.DIRS:
				var q: Vector2i = p + d
				var qi := q.y * m.width + q.x
				if m.in_bounds(q) and seen[qi] == 0 and m.tiles[qi] == CityMap.Tile.BUILDING:
					seen[qi] = 1
					comp.append(qi)
		if comp.size() >= 2 and comp.size() <= 10 and rng.randf() < 0.15:
			for idx in comp:
				m.tiles[idx] = CityMap.Tile.PARK


## Maximal runs of non-intersection road tiles: the stretches between
## junctions. Only short ones (like a lattice block side) are closable as
## rubble; closing a long organic street would erase a whole route.
static func _road_segments(m: CityMap) -> Array:
	var seen := {}
	var segs := []
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			if seen.has(p) or m.get_tile(p) != CityMap.Tile.ROAD or m.is_intersection(p):
				continue
			var seg: Array[Vector2i] = [p]
			seen[p] = true
			var head := 0
			while head < seg.size():
				var cur := seg[head]
				head += 1
				for d in CityMap.DIRS:
					var q: Vector2i = cur + d
					if not seen.has(q) and m.get_tile(q) == CityMap.Tile.ROAD and not m.is_intersection(q):
						seen[q] = true
						seg.append(q)
			if seg.size() <= MAX_CLOSURE_LENGTH:
				segs.append(seg)
	return segs


# --- Street lattice generator (fallback) ----------------------------------------

static func _try_lattice(round_num: int, rng: RandomNumberGenerator) -> CityMap:
	var blocks_x := mini(4 + round_num, 9)
	var blocks_y := mini(3 + floori(round_num / 2.0), 6)

	# 1. Street lattice: roads every 3-4 tiles, building blocks in between.
	var xs := _line_positions(blocks_x, rng)
	var ys := _line_positions(blocks_y, rng)
	var m := CityMap.new()
	m.setup(xs[-1] + 1, ys[-1] + 1, CityMap.Tile.BUILDING)
	for x in xs:
		for y in m.height:
			m.set_tile(Vector2i(x, y), CityMap.Tile.ROAD)
	for y in ys:
		for x in m.width:
			m.set_tile(Vector2i(x, y), CityMap.Tile.ROAD)

	# 2. Safe zone: one block on the edge of the city becomes an evacuation plaza.
	var edge_blocks: Array[Vector2i] = []
	for bx in blocks_x:
		for by in blocks_y:
			if bx == 0 or by == 0 or bx == blocks_x - 1 or by == blocks_y - 1:
				edge_blocks.append(Vector2i(bx, by))
	var safe_block := edge_blocks[rng.randi() % edge_blocks.size()]
	_fill_block(m, xs, ys, safe_block, CityMap.Tile.SAFE)
	for bx in blocks_x:
		for by in blocks_y:
			if Vector2i(bx, by) != safe_block and rng.randf() < 0.12:
				_fill_block(m, xs, ys, Vector2i(bx, by), CityMap.Tile.PARK)

	# 3-5. Shared gameplay steps.
	if not _place_survivors(m, round_num, rng):
		return null
	_close_segments(m, _segments(xs, ys), closure_count_for(round_num), rng)
	_place_pre_fires(m, pre_fire_count_for(round_num), rng)
	return _finish(m, rng)


static func _line_positions(blocks: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = [0]
	for i in blocks:
		out.append(out[-1] + rng.randi_range(3, 4))
	return out


static func _fill_block(m: CityMap, xs: Array[int], ys: Array[int], b: Vector2i, t: int) -> void:
	for x in range(xs[b.x] + 1, xs[b.x + 1]):
		for y in range(ys[b.y] + 1, ys[b.y + 1]):
			m.set_tile(Vector2i(x, y), t)


## Road tiles strictly between two neighbouring intersections of the lattice.
static func _segments(xs: Array[int], ys: Array[int]) -> Array:
	var segs := []
	for x in xs:
		for j in ys.size() - 1:
			var seg: Array[Vector2i] = []
			for y in range(ys[j] + 1, ys[j + 1]):
				seg.append(Vector2i(x, y))
			segs.append(seg)
	for y in ys:
		for i in xs.size() - 1:
			var seg: Array[Vector2i] = []
			for x in range(xs[i] + 1, xs[i + 1]):
				seg.append(Vector2i(x, y))
			segs.append(seg)
	return segs


# --- Shared gameplay steps -------------------------------------------------------

## Survivors on road tiles far from the safe zone, spread apart, each with a
## robust route. Returns false if not enough spots were found.
static func _place_survivors(m: CityMap, round_num: int, rng: RandomNumberGenerator) -> bool:
	var group_count := group_count_for(round_num)
	var dist := m.distance_field()
	var max_d := 0
	for v in dist:
		max_d = maxi(max_d, v)
	var robust := m.robust_mask()
	var candidates: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			var i := y * m.width + x
			if m.get_tile(p) == CityMap.Tile.ROAD and not m.is_intersection(p) and dist[i] >= max_d * 0.45 and robust[i] == 1:
				candidates.append(p)
	shuffle(candidates, rng)
	for min_sep in [5, 3]:
		for p in candidates:
			if m.survivor_starts.size() >= group_count:
				break
			if m.survivor_starts.has(p):
				continue
			var ok := true
			for s in m.survivor_starts:
				if absi(s.x - p.x) + absi(s.y - p.y) < min_sep:
					ok = false
					break
			if ok:
				m.survivor_starts.append(p)
	if m.survivor_starts.size() < group_count:
		return false
	for i in m.survivor_starts.size():
		m.survivor_sizes.append(rng.randi_range(3, mini(4 + floori(round_num / 2.0), 8)))
	return _layout_ok(m)


## Closes up to `count` road segments (rubble) to make route choice more
## interesting, reverting any closure that breaks the layout rules.
static func _close_segments(m: CityMap, segments: Array, count: int, rng: RandomNumberGenerator) -> void:
	shuffle(segments, rng)
	var closed := 0
	for seg in segments:
		if closed >= count:
			break
		var touches_start := false
		for p in seg:
			if m.survivor_starts.has(p):
				touches_start = true
		if touches_start:
			continue
		for p in seg:
			m.set_tile(p, CityMap.Tile.BUILDING)
		if _layout_ok(m):
			closed += 1
			for p in seg:
				m.road_closures[p] = true
		else:
			for p in seg:
				m.set_tile(p, CityMap.Tile.ROAD)


## Pre-existing fires from round 2 on (with their smoke) as standing hazards.
static func _place_pre_fires(m: CityMap, count: int, rng: RandomNumberGenerator) -> void:
	var fire_spots: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			if m.get_tile(p) != CityMap.Tile.ROAD or m.is_intersection(p):
				continue
			var near_start := false
			for s in m.survivor_starts:
				if absi(s.x - p.x) + absi(s.y - p.y) < 3:
					near_start = true
			if not near_start:
				fire_spots.append(p)
	shuffle(fire_spots, rng)
	var placed := 0
	for p in fire_spots:
		if placed >= count:
			break
		m.add_fire(p)
		if _layout_ok(m):
			placed += 1
		else:
			m.remove_fire(p)


## Final validation of a generated map; a valid map then gets its city plan.
## The plan reads the tiles and changes none of them.
static func _finish(m: CityMap, rng: RandomNumberGenerator) -> CityMap:
	if not _layout_ok(m):
		return null
	CityLayout.build(m, rng)
	return m


## Every group must have a robust route (a detour for any single blocked tile),
## and every walkable road tile must stay connected to the safe zone.
## (robust_mask() is the single-pass equivalent of calling is_robust per group.)
static func _layout_ok(m: CityMap) -> bool:
	var reach := m.distance_field()
	for y in m.height:
		for x in m.width:
			if reach[y * m.width + x] == -1 and m.is_passable(Vector2i(x, y)):
				return false
	var robust := m.robust_mask()
	for s in m.survivor_starts:
		if robust[s.y * m.width + s.x] == 0:
			return false
	return true


## Fisher-Yates shuffle driven by an explicit RNG (never the global one), so
## seeded generation and hazards stay reproducible.
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Binary min-heap of ints packed as priority * KEY_SCALE + index.
class MinHeap:
	const KEY_SHIFT := 20
	const KEY_SCALE := 1 << KEY_SHIFT
	var _a: Array[int] = []

	func is_empty() -> bool:
		return _a.is_empty()

	func push(priority: int, index: int) -> void:
		_a.append(priority * KEY_SCALE + index)
		var i := _a.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if _a[p] <= _a[i]:
				break
			var t := _a[p]
			_a[p] = _a[i]
			_a[i] = t
			i = p

	func pop() -> int:
		var top := _a[0]
		var last: int = _a.pop_back()
		if not _a.is_empty():
			_a[0] = last
			var i := 0
			var n := _a.size()
			while true:
				var l := 2 * i + 1
				var r := l + 1
				var s := i
				if l < n and _a[l] < _a[s]:
					s = l
				if r < n and _a[r] < _a[s]:
					s = r
				if s == i:
					break
				var t := _a[s]
				_a[s] = _a[i]
				_a[i] = t
				i = s
		return top
