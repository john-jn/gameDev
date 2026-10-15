class_name CityMap
extends RefCounted
## Grid model of the city: tile types, active hazards and BFS pathfinding.
## Coordinates are Vector2i(x, y) with (0, 0) at the top-left corner.
## Movement is 4-directional (no diagonals) along ROAD and SAFE tiles.
## BFS runs on flat packed arrays because map generation calls it thousands
## of times while validating layouts.

enum Tile { ROAD, BUILDING, PARK, SAFE }

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const NO_TILE := Vector2i(-1, -1)

var width := 0
var height := 0
var tiles := PackedInt32Array()
## Tiles currently on fire (Vector2i -> true). Fire tiles are impassable.
## Road tiles orthogonally next to a fire are "smoke": passable but deadly.
var fires: Dictionary = {}
var survivor_starts: Array[Vector2i] = []
var survivor_sizes: Array[int] = []
var _fire_mask := PackedByteArray()  ## 1 where a fire burns, mirrors `fires`


func setup(w: int, h: int, fill: int) -> void:
	width = w
	height = h
	tiles.resize(w * h)
	tiles.fill(fill)
	_fire_mask.resize(w * h)
	_fire_mask.fill(0)
	fires.clear()
	survivor_starts.clear()
	survivor_sizes.clear()


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func get_tile(p: Vector2i) -> int:
	if not in_bounds(p):
		return Tile.BUILDING
	return tiles[p.y * width + p.x]


func set_tile(p: Vector2i, t: int) -> void:
	if in_bounds(p):
		tiles[p.y * width + p.x] = t


## Walkable ground (road or safe zone), ignoring hazards.
func is_street(p: Vector2i) -> bool:
	var t := get_tile(p)
	return t == Tile.ROAD or t == Tile.SAFE


func is_safe(p: Vector2i) -> bool:
	return get_tile(p) == Tile.SAFE


func is_fire(p: Vector2i) -> bool:
	return fires.has(p)


func is_passable(p: Vector2i) -> bool:
	return is_street(p) and not fires.has(p)


func is_smoke(p: Vector2i) -> bool:
	if get_tile(p) != Tile.ROAD or fires.has(p):
		return false
	for d in DIRS:
		if fires.has(p + d):
			return true
	return false


func street_neighbor_count(p: Vector2i) -> int:
	var n := 0
	for d in DIRS:
		if is_street(p + d):
			n += 1
	return n


func is_intersection(p: Vector2i) -> bool:
	return get_tile(p) == Tile.ROAD and street_neighbor_count(p) >= 3


func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func add_fire(p: Vector2i) -> void:
	if in_bounds(p):
		fires[p] = true
		_fire_mask[p.y * width + p.x] = 1


func remove_fire(p: Vector2i) -> void:
	if in_bounds(p):
		fires.erase(p)
		_fire_mask[p.y * width + p.x] = 0


## Breadth-first search from `start` to the nearest SAFE tile.
## `blocked` lets callers test "what if this tile were blocked too?".
## Returns the full path including `start`, or an empty array if none exists.
func find_path(start: Vector2i, blocked: Vector2i = NO_TILE) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_passable(start) or start == blocked:
		return result
	var s := start.y * width + start.x
	var b := blocked.y * width + blocked.x if in_bounds(blocked) else -1
	var parent := _bfs([s], b, true)
	var goal := -1
	for i in parent.size():
		if parent[i] != -1 and tiles[i] == Tile.SAFE:
			goal = i
			break
	if goal == -1:
		return result
	# _bfs stops at the first SAFE tile reached, so only one SAFE tile has a parent.
	var cur := goal
	while cur != s:
		@warning_ignore("integer_division")
		result.push_front(Vector2i(cur % width, cur / width))
		cur = parent[cur]
	result.push_front(start)
	return result


func has_path(start: Vector2i, blocked: Vector2i = NO_TILE) -> bool:
	return not find_path(start, blocked).is_empty()


## Number of moves on the shortest route to safety, or -1 if unreachable.
func shortest_length(start: Vector2i) -> int:
	return find_path(start).size() - 1


## True when the start can reach safety AND still could if any single tile of
## its shortest route were blocked, i.e. a detour exists for every possible
## single obstruction on that route.
func is_robust(start: Vector2i) -> bool:
	var path := find_path(start)
	if path.is_empty():
		return false
	for i in range(1, path.size()):
		var p := path[i]
		if is_safe(p):
			break
		if not has_path(start, p):
			return false
	return true


## BFS distance (in moves) from the safe zone to every tile; -1 if unreachable.
## Indexed by y * width + x.
func distance_field() -> PackedInt32Array:
	var sources: Array[int] = []
	for i in tiles.size():
		if tiles[i] == Tile.SAFE and _fire_mask[i] == 0:
			sources.append(i)
	var dist := PackedInt32Array()
	dist.resize(tiles.size())
	dist.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(tiles.size())
	var head := 0
	var tail := 0
	for i in sources:
		dist[i] = 0
		queue[tail] = i
		tail += 1
	var n := tiles.size()
	while head < tail:
		var cur := queue[head]
		head += 1
		var x := cur % width
		for k in 4:
			var nb := cur + 1 if k == 0 else (cur - 1 if k == 1 else (cur + width if k == 2 else cur - width))
			if (k == 0 and x == width - 1) or (k == 1 and x == 0) or nb < 0 or nb >= n:
				continue
			if dist[nb] != -1 or _fire_mask[nb] == 1:
				continue
			var t := tiles[nb]
			if t != Tile.ROAD and t != Tile.SAFE:
				continue
			dist[nb] = dist[cur] + 1
			queue[tail] = nb
			tail += 1
	return dist


## Core BFS over flat indices. Returns a parent array (-1 = not reached).
## When `stop_at_safe` is true the search ends at the first SAFE tile.
func _bfs(sources: Array, blocked: int, stop_at_safe: bool) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(tiles.size())
	parent.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(tiles.size())
	var n := tiles.size()
	var head := 0
	var tail := 0
	for s in sources:
		parent[s] = s
		queue[tail] = s
		tail += 1
	while head < tail:
		var cur := queue[head]
		head += 1
		if stop_at_safe and tiles[cur] == Tile.SAFE:
			# Clear any other SAFE tiles already queued so find_path sees one goal.
			for i in range(head, tail):
				if tiles[queue[i]] == Tile.SAFE:
					parent[queue[i]] = -1
			break
		var x := cur % width
		for k in 4:
			var nb := cur + 1 if k == 0 else (cur - 1 if k == 1 else (cur + width if k == 2 else cur - width))
			if (k == 0 and x == width - 1) or (k == 1 and x == 0) or nb < 0 or nb >= n:
				continue
			if parent[nb] != -1 or nb == blocked or _fire_mask[nb] == 1:
				continue
			var t := tiles[nb]
			if t != Tile.ROAD and t != Tile.SAFE:
				continue
			parent[nb] = cur
			queue[tail] = nb
			tail += 1
	return parent
