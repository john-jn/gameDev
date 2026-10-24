class_name CityLayout
extends RefCounted
## Turns a finished CityMap into a city plan: building lots inside the blocks
## between roads, park lots, the safe-zone building and the road hierarchy.
## It runs after the generator has fixed every tile, reads the tiles and never
## changes them, so routes, fires and the generation guarantees are untouched.
##
## Blocks are the connected groups of BUILDING (or PARK) tiles. Each block is
## cut into rectangular lots of varied size, and some small lots are merged
## into a neighbour to form L-shaped footprints. Every connected group of SAFE
## tiles becomes one building designated SAFE_ZONE. Road closures are not lots;
## they stay part of the road network on screen.

## Lot sizes tried at each free corner, with relative weights.
const BUILDING_SIZES := [Vector2i(3, 3), Vector2i(3, 2), Vector2i(2, 3), Vector2i(2, 2),
		Vector2i(3, 1), Vector2i(1, 3), Vector2i(2, 1), Vector2i(1, 2), Vector2i(1, 1)]
const BUILDING_WEIGHTS := [1, 3, 3, 5, 1, 1, 3, 3, 1]
const PARK_SIZES := [Vector2i(3, 3), Vector2i(3, 2), Vector2i(2, 3), Vector2i(2, 2),
		Vector2i(2, 1), Vector2i(1, 2), Vector2i(1, 1)]
const PARK_WEIGHTS := [4, 2, 2, 2, 1, 1, 1]
## Chance that a one- or two-tile lot joins a neighbour to form an L.
const L_MERGE_CHANCE := 0.45
const MAX_LOT_CELLS := 7


static func build(m: CityMap, rng: RandomNumberGenerator) -> void:
	var n := m.tiles.size()
	m.buildings.clear()
	m.building_ids.resize(n)
	m.building_ids.fill(-1)
	_classify_roads(m)
	for comp in _components(m, CityMap.Tile.SAFE):
		var b := _add_lot(m, comp, CityBuilding.Kind.BUILDING, rng)
		b.designation = CityBuilding.Designation.SAFE_ZONE
	for comp in _components(m, CityMap.Tile.BUILDING):
		for lot in _partition(m, comp, BUILDING_SIZES, BUILDING_WEIGHTS, rng):
			_add_lot(m, lot, CityBuilding.Kind.BUILDING, rng)
	for comp in _components(m, CityMap.Tile.PARK):
		for lot in _partition(m, comp, PARK_SIZES, PARK_WEIGHTS, rng):
			_add_lot(m, lot, CityBuilding.Kind.PARK, rng)
	m.layout_version += 1


## Everything the layout promises, as human-readable problems (empty = valid).
## Tests run it over hundreds of generated maps.
static func find_problems(m: CityMap) -> PackedStringArray:
	var out := PackedStringArray()
	if m.building_ids.size() != m.tiles.size() or m.road_class.size() != m.tiles.size():
		out.append("no city layout")
		return out
	var owner := PackedInt32Array()
	owner.resize(m.tiles.size())
	owner.fill(-1)
	for i in m.buildings.size():
		var b := m.buildings[i]
		if b.id != i:
			out.append("lot %d has id %d" % [i, b.id])
		if b.cells.is_empty():
			out.append("lot %d is empty" % i)
			continue
		if not Rect2i(0, 0, m.width, m.height).encloses(b.bounds):
			out.append("lot %d leaves the map: %s" % [i, b.bounds])
			continue
		var want: int = CityMap.Tile.SAFE if b.is_safe_zone() else (
				CityMap.Tile.PARK if b.kind == CityBuilding.Kind.PARK else CityMap.Tile.BUILDING)
		for c in b.cells:
			var idx := c.y * m.width + c.x
			if owner[idx] != -1:
				out.append("tile %s is in lots %d and %d" % [c, owner[idx], i])
			owner[idx] = i
			if m.tiles[idx] != want:
				out.append("lot %d covers tile %s of type %d, expected %d" % [i, c, m.tiles[idx], want])
			if m.is_road_closure(c):
				out.append("lot %d covers closed road %s" % [i, c])
			if m.survivor_starts.has(c):
				out.append("lot %d covers survivor start %s" % [i, c])
		if not b.is_safe_zone() and not _is_rect_or_l(b):
			out.append("lot %d is neither a rectangle nor an L: %s" % [i, b.cells])
		for e in b.entrances:
			if m.get_tile(e) != CityMap.Tile.ROAD or not _touches(b, e):
				out.append("lot %d has a bad entrance %s" % [i, e])
		if b.entrance != CityMap.NO_TILE and not b.entrances.has(b.entrance):
			out.append("lot %d main entrance %s is not one of its entrances" % [i, b.entrance])
		if b.is_safe_zone() and b.entrances.is_empty():
			out.append("safe zone %d has no road entrance" % i)
	for idx in m.tiles.size():
		var t := m.tiles[idx]
		@warning_ignore("integer_division")
		var p := Vector2i(idx % m.width, idx / m.width)
		if owner[idx] != m.building_ids[idx]:
			out.append("building_ids disagrees with lot cells at %s" % p)
		var needs_lot := t != CityMap.Tile.ROAD and not m.is_road_closure(p)
		if needs_lot != (owner[idx] != -1):
			out.append("tile %s (type %d) %s" % [p, t, "has no lot" if needs_lot else "should not be in a lot"])
		if (m.road_class[idx] != CityMap.RoadClass.NONE) != (t == CityMap.Tile.ROAD):
			out.append("road class %d on tile %s of type %d" % [m.road_class[idx], p, t])
	return out


## STREET for every road tile, AVENUE where it is part of a 2x2 block of road
## (the two-lane avenues the Physarum city grid lays down).
static func _classify_roads(m: CityMap) -> void:
	m.road_class.resize(m.tiles.size())
	m.road_class.fill(CityMap.RoadClass.NONE)
	for i in m.tiles.size():
		if m.tiles[i] == CityMap.Tile.ROAD:
			m.road_class[i] = CityMap.RoadClass.STREET
	for y in m.height - 1:
		for x in m.width - 1:
			var quad := [y * m.width + x, y * m.width + x + 1, (y + 1) * m.width + x, (y + 1) * m.width + x + 1]
			var all_road := true
			for i in quad:
				if m.tiles[i] != CityMap.Tile.ROAD:
					all_road = false
			if all_road:
				for i in quad:
					m.road_class[i] = CityMap.RoadClass.AVENUE


## 4-connected groups of `tile_type` tiles (closures excluded), each a
## row-major list of flat indices, in row-major order of their first tile.
static func _components(m: CityMap, tile_type: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(m.tiles.size())
	var out := []
	for start in m.tiles.size():
		if seen[start] == 1 or not _lot_tile(m, start, tile_type):
			continue
		var comp: Array[int] = [start]
		seen[start] = 1
		var head := 0
		while head < comp.size():
			var cur := comp[head]
			head += 1
			var x := cur % m.width
			for k in 4:
				if (k == 0 and x == m.width - 1) or (k == 1 and x == 0):
					continue
				var nb := cur + 1 if k == 0 else (cur - 1 if k == 1 else (cur + m.width if k == 2 else cur - m.width))
				if nb >= 0 and nb < m.tiles.size() and seen[nb] == 0 and _lot_tile(m, nb, tile_type):
					seen[nb] = 1
					comp.append(nb)
		comp.sort()
		out.append(comp)
	return out


static func _lot_tile(m: CityMap, idx: int, tile_type: int) -> bool:
	if m.tiles[idx] != tile_type:
		return false
	@warning_ignore("integer_division")
	return not m.road_closures.has(Vector2i(idx % m.width, idx / m.width))


## Cuts one block into lots: at each free tile (row-major), the first size in a
## weighted random order that fits on free block tiles is taken, then small
## lots may merge with a neighbour into an L. Returns lists of flat indices.
static func _partition(m: CityMap, comp: Array, sizes: Array, weights: Array, rng: RandomNumberGenerator) -> Array:
	var lot_of := {}  # flat index -> lot number, for tiles of this block
	for idx in comp:
		lot_of[idx] = -1
	var lots := []
	for idx in comp:
		if lot_of[idx] != -1:
			continue
		var x0: int = idx % m.width
		@warning_ignore("integer_division")
		var y0: int = idx / m.width
		for size in _weighted_order(sizes, weights, rng):
			var cells: Array[int] = []
			for dy in size.y:
				for dx in size.x:
					var q: int = (y0 + dy) * m.width + x0 + dx
					if x0 + dx < m.width and y0 + dy < m.height and lot_of.get(q, 0) == -1:
						cells.append(q)
			if cells.size() == size.x * size.y:
				for q in cells:
					lot_of[q] = lots.size()
				lots.append(cells)
				break
	# L shapes: a small lot joins a neighbouring lot when the union is an L.
	for i in lots.size():
		var lot: Array = lots[i]
		if lot.is_empty() or lot.size() > 2 or rng.randf() >= L_MERGE_CHANCE:
			continue
		var options: Array[int] = []
		for q in lot:
			var x: int = q % m.width
			for k in 4:
				if (k == 0 and x == m.width - 1) or (k == 1 and x == 0):
					continue
				var nb: int = q + 1 if k == 0 else (q - 1 if k == 1 else (q + m.width if k == 2 else q - m.width))
				var j: int = lot_of.get(nb, -1)
				if j >= 0 and j != i and not options.has(j) and lots[j].size() + lot.size() <= MAX_LOT_CELLS \
						and _cells_form_l(m, lots[j] + lot):
					options.append(j)
		if options.is_empty():
			continue
		options.sort()
		var j := options[rng.randi() % options.size()]
		for q in lot:
			lot_of[q] = j
		lots[j] = lots[j] + lot
		lots[i] = []
	var out := []
	for lot in lots:
		if not lot.is_empty():
			lot.sort()
			out.append(lot)
	return out


static func _weighted_order(items: Array, weights: Array, rng: RandomNumberGenerator) -> Array:
	var pool := items.duplicate()
	var w := weights.duplicate()
	var out := []
	while not pool.is_empty():
		var total := 0
		for v in w:
			total += v
		var pick := rng.randi_range(0, total - 1)
		var k := 0
		while pick >= w[k]:
			pick -= w[k]
			k += 1
		out.append(pool[k])
		pool.remove_at(k)
		w.remove_at(k)
	return out


static func _add_lot(m: CityMap, comp: Array, kind: CityBuilding.Kind, rng: RandomNumberGenerator) -> CityBuilding:
	var b := CityBuilding.new()
	b.id = m.buildings.size()
	b.kind = kind
	b.variant = rng.randi() % CityBuilding.VARIANT_COUNT
	var lo := Vector2i(m.width, m.height)
	var hi := Vector2i(-1, -1)
	for idx in comp:
		@warning_ignore("integer_division")
		var c := Vector2i(idx % m.width, idx / m.width)
		b.cells.append(c)
		m.building_ids[idx] = b.id
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	b.bounds = Rect2i(lo, hi - lo + Vector2i.ONE)
	var seen := {}
	for c in b.cells:
		for d in CityMap.DIRS:
			var e: Vector2i = c + d
			if not seen.has(e) and m.get_tile(e) == CityMap.Tile.ROAD:
				seen[e] = true
				b.entrances.append(e)
	b.entrances.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.y < q.y or (p.y == q.y and p.x < q.x))
	if b.entrances.is_empty():
		b.rotation = rng.randi() % 4
	else:
		b.entrance = b.entrances[rng.randi() % b.entrances.size()]
		b.rotation = _facing(b, b.entrance)
	m.buildings.append(b)
	return b


## Quarter turns that point the lot's front (south at rotation 0) at road tile `e`.
static func _facing(b: CityBuilding, e: Vector2i) -> int:
	const FRONTS := [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]
	for c in b.cells:
		var k := FRONTS.find(e - c)
		if k != -1:
			return k
	return 0


static func _touches(b: CityBuilding, p: Vector2i) -> bool:
	for c in b.cells:
		if absi(c.x - p.x) + absi(c.y - p.y) == 1:
			return true
	return false


static func _is_rect_or_l(b: CityBuilding) -> bool:
	return b.is_rect() or _rect_minus_corner(b.cells, b.bounds)


## True when `cells` (flat indices) form an L: their bounding rectangle minus
## one rectangular corner.
static func _cells_form_l(m: CityMap, flat: Array) -> bool:
	var cells: Array[Vector2i] = []
	var lo := Vector2i(m.width, m.height)
	var hi := Vector2i(-1, -1)
	for idx in flat:
		@warning_ignore("integer_division")
		var c := Vector2i(idx % m.width, idx / m.width)
		cells.append(c)
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return _rect_minus_corner(cells, Rect2i(lo, hi - lo + Vector2i.ONE))


static func _rect_minus_corner(cells: Array[Vector2i], bounds: Rect2i) -> bool:
	var inside := {}
	for c in cells:
		inside[c] = true
	var lo := bounds.end
	var hi := bounds.position - Vector2i.ONE
	var missing := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if not inside.has(Vector2i(x, y)):
				missing += 1
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if missing == 0 or inside.size() != cells.size():
		return false
	var hole := Rect2i(lo, hi - lo + Vector2i.ONE)
	var at_x_edge := hole.position.x == bounds.position.x or hole.end.x == bounds.end.x
	var at_y_edge := hole.position.y == bounds.position.y or hole.end.y == bounds.end.y
	return missing == hole.get_area() and at_x_edge and at_y_edge
