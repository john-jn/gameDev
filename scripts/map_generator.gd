class_name MapGenerator
extends RefCounted
## Builds the city for each round.
## Round 1 is a fixed, hand-authored training map. Later rounds are generated
## from a street lattice (which always has alternate routes), then roads are
## closed and fires pre-placed one at a time; any change that would strand a
## group or remove its detours is reverted. If generation ever fails, the
## hand-authored map is used, so a round can always be played.

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


static func build_round(round_num: int, rng: RandomNumberGenerator) -> CityMap:
	if round_num <= 1:
		return build_handmade()
	for attempt in 40:
		var m := _try_procedural(round_num, rng)
		if m != null:
			return m
	push_warning("Procedural generation failed; using the hand-authored map.")
	return build_handmade()


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
	return m


## Difficulty knobs, all growing slowly with the round number.
static func group_count_for(round_num: int) -> int:
	return mini(2 + floori((round_num - 1) / 2.0), 6)


static func pre_fire_count_for(round_num: int) -> int:
	return mini(round_num - 1, 6)


static func _try_procedural(round_num: int, rng: RandomNumberGenerator) -> CityMap:
	var blocks_x := mini(4 + round_num, 9)
	var blocks_y := mini(3 + floori(round_num / 2.0), 6)
	var group_count := group_count_for(round_num)
	var closures := mini(2 + round_num, 10)
	var pre_fires := pre_fire_count_for(round_num)

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

	# 3. Survivors on road tiles far from the safe zone, spread apart.
	var dist := m.distance_field()
	var max_d := 0
	for v in dist:
		max_d = maxi(max_d, v)
	var candidates: Array[Vector2i] = []
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			if m.get_tile(p) == CityMap.Tile.ROAD and not m.is_intersection(p) and dist[y * m.width + x] >= max_d * 0.45:
				candidates.append(p)
	_shuffle(candidates, rng)
	for min_sep in [5, 3]:
		for p in candidates:
			if m.survivor_starts.size() >= group_count:
				break
			var ok := true
			for s in m.survivor_starts:
				if absi(s.x - p.x) + absi(s.y - p.y) < min_sep:
					ok = false
					break
			if ok:
				m.survivor_starts.append(p)
	if m.survivor_starts.size() < group_count:
		return null
	for i in m.survivor_starts.size():
		m.survivor_sizes.append(rng.randi_range(3, mini(4 + floori(round_num / 2.0), 8)))
	if not _layout_ok(m):
		return null

	# 4. Close some road segments (rubble) to make route choice more interesting.
	var segments := _segments(xs, ys)
	_shuffle(segments, rng)
	var closed := 0
	for seg in segments:
		if closed >= closures:
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
		else:
			for p in seg:
				m.set_tile(p, CityMap.Tile.ROAD)

	# 5. Pre-existing fires from round 2 on (with their smoke) as standing hazards.
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
	_shuffle(fire_spots, rng)
	var placed := 0
	for p in fire_spots:
		if placed >= pre_fires:
			break
		m.add_fire(p)
		if _layout_ok(m):
			placed += 1
		else:
			m.remove_fire(p)
	return m


## Every group must have a robust route (a detour for any single blocked tile),
## and every walkable road tile must stay connected to the safe zone.
static func _layout_ok(m: CityMap) -> bool:
	for s in m.survivor_starts:
		if not m.is_robust(s):
			return false
	var reach := m.distance_field()
	for y in m.height:
		for x in m.width:
			if reach[y * m.width + x] == -1 and m.is_passable(Vector2i(x, y)):
				return false
	return true


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


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
