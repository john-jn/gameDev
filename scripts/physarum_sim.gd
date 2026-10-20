class_name PhysarumSim
extends RefCounted
## Agent-based Physarum polycephalum (slime mould) simulation, after Jones (2010).
## A colony of agents spawns in a disc around a randomized center, senses the
## chemical trail ahead of it, turns toward the strongest signal, moves and
## deposits more trail. The trail diffuses and evaporates every step, and food
## sources (attractors) keep emitting, so the colony settles into a network of
## veins linking the food. MapGenerator turns those veins into roads.
##
## The simulation grid is `sub` cells per map tile on each axis. All randomness
## comes from the RandomNumberGenerator passed to run(), so a seed reproduces
## the same trail field.

## Simulation cells per map tile (per axis).
var sub := 2
## Agents per simulation cell (Jones uses roughly 3-15% occupancy).
var agent_density := 0.12
var sensor_angle := deg_to_rad(45.0)
var rotate_angle := deg_to_rad(45.0)
## Sensor distance ahead of the agent, in cells.
var sensor_offset := 3.0
## Distance moved per step, in cells.
var step_size := 1.0
var deposit := 1.0
## Fraction of trail that evaporates each step (after diffusion).
var decay := 0.1
## Trail emitted per step by each food tile, before its weight.
var food_strength := 3.0
## Steps always run, plus the time needed to cross from the center to the
## farthest map corner, so off-center colonies still reach the far side.
var base_steps := 90
var max_steps := 320

## Read-only results.
var tile_w := 0
var tile_h := 0
var center := Vector2.ZERO        ## colony center, in tile coordinates
var spawn_radius := 0.0           ## in tiles
var steps_run := 0

var _w := 0                       ## grid size in cells
var _h := 0
var _trail := PackedFloat32Array()
var _tmp := PackedFloat32Array()
var _ax := PackedFloat32Array()
var _ay := PackedFloat32Array()
var _ah := PackedFloat32Array()
var _food_cells := PackedInt32Array()
var _food_amount := PackedFloat32Array()


## Picks a colony center so the whole spawn disc stays at least `margin` tiles
## from every map edge, and at least `avoid_dist` tiles from `avoid` (the safe
## zone) when possible. Tile coordinates are continuous: the map spans
## [0, w) x [0, h). On maps too small for the margins, the axis midpoint is used.
static func pick_center(w: int, h: int, radius: float, margin: float, rng: RandomNumberGenerator,
		avoid: Rect2i = Rect2i(), avoid_dist: float = 0.0) -> Vector2:
	var lo := Vector2(margin + radius, margin + radius)
	var hi := Vector2(w - margin - radius, h - margin - radius)
	if lo.x > hi.x:
		lo.x = w * 0.5
		hi.x = lo.x
	if lo.y > hi.y:
		lo.y = h * 0.5
		hi.y = lo.y
	var best := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
	if avoid.size == Vector2i.ZERO:
		return best
	# Rejection sampling, bounded; keeps the sample farthest from `avoid` if
	# none clears it (only possible on very small maps).
	var best_d := _dist_to_rect(best, avoid)
	for i in 24:
		if best_d >= avoid_dist:
			break
		var c := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		var d := _dist_to_rect(c, avoid)
		if d > best_d:
			best = c
			best_d = d
	return best


static func _dist_to_rect(p: Vector2, r: Rect2i) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()


## `foods` are attractor tiles; `weights` scales each one's emission.
func setup(w_tiles: int, h_tiles: int, colony_center: Vector2, radius_tiles: float,
		foods: Array[Vector2i], weights: Array[float]) -> void:
	tile_w = w_tiles
	tile_h = h_tiles
	center = colony_center
	spawn_radius = radius_tiles
	_w = w_tiles * sub
	_h = h_tiles * sub
	_trail.resize(_w * _h)
	_trail.fill(0.0)
	_tmp.resize(_w * _h)
	_food_cells.clear()
	_food_amount.clear()
	for i in foods.size():
		var f := foods[i]
		for dy in sub:
			for dx in sub:
				_food_cells.append((f.y * sub + dy) * _w + f.x * sub + dx)
				_food_amount.append(food_strength * weights[i])


func run(rng: RandomNumberGenerator) -> void:
	_spawn(rng)
	# Farthest corner from the colony decides how long the network needs to grow.
	var reach := 0.0
	for corner in [Vector2.ZERO, Vector2(tile_w, 0), Vector2(0, tile_h), Vector2(tile_w, tile_h)]:
		reach = maxf(reach, center.distance_to(corner))
	steps_run = clampi(base_steps + ceili(reach * sub / step_size), base_steps, max_steps)
	for s in steps_run:
		_emit_food()
		_move_agents(rng)
		_diffuse()


## Agents start uniformly inside the spawn disc, heading outward so the colony
## expands from its center the way a plasmodium does.
func _spawn(rng: RandomNumberGenerator) -> void:
	var n := maxi(32, roundi(_w * _h * agent_density))
	_ax.resize(n)
	_ay.resize(n)
	_ah.resize(n)
	var c := center * sub
	var r := spawn_radius * sub
	for i in n:
		var a := rng.randf() * TAU
		var d := r * sqrt(rng.randf())
		# Clamp guards the degenerate small-map case where the disc may touch an edge.
		_ax[i] = clampf(c.x + cos(a) * d, 0.0, _w - 0.001)
		_ay[i] = clampf(c.y + sin(a) * d, 0.0, _h - 0.001)
		_ah[i] = a + rng.randf_range(-0.5, 0.5)
		_trail[int(_ay[i]) * _w + int(_ax[i])] += deposit


func _emit_food() -> void:
	for i in _food_cells.size():
		_trail[_food_cells[i]] += _food_amount[i]


## Sense -> rotate -> move -> deposit for every agent (Jones' update rule).
## Sensors outside the map read -1, so agents steer away from the boundary;
## an agent whose move would leave the map picks a new random heading instead.
func _move_agents(rng: RandomNumberGenerator) -> void:
	var so := sensor_offset
	var sa := sensor_angle
	var ra := rotate_angle
	for i in _ax.size():
		var x := _ax[i]
		var y := _ay[i]
		var h := _ah[i]
		var f := _sample(x + cos(h) * so, y + sin(h) * so)
		var fl := _sample(x + cos(h - sa) * so, y + sin(h - sa) * so)
		var fr := _sample(x + cos(h + sa) * so, y + sin(h + sa) * so)
		if f > fl and f > fr:
			pass
		elif f < fl and f < fr:
			h += ra if rng.randf() < 0.5 else -ra
		elif fl > fr:
			h -= ra
		elif fr > fl:
			h += ra
		var nx := x + cos(h) * step_size
		var ny := y + sin(h) * step_size
		if nx < 0.0 or ny < 0.0 or nx >= _w or ny >= _h:
			_ah[i] = rng.randf() * TAU
			continue
		_ax[i] = nx
		_ay[i] = ny
		_ah[i] = h
		_trail[int(ny) * _w + int(nx)] += deposit


func _sample(x: float, y: float) -> float:
	if x < 0.0 or y < 0.0 or x >= _w or y >= _h:
		return -1.0
	return _trail[int(y) * _w + int(x)]


## 3x3 mean filter (as two separable passes) followed by evaporation.
func _diffuse() -> void:
	var w := _w
	for y in _h:
		var row := y * w
		for x in w:
			var l := x - 1 if x > 0 else 0
			var r := x + 1 if x < w - 1 else x
			_tmp[row + x] = _trail[row + l] + _trail[row + x] + _trail[row + r]
	var k := (1.0 - decay) / 9.0
	for y in _h:
		var row := y * w
		var up := (y - 1) * w if y > 0 else row
		var dn := (y + 1) * w if y < _h - 1 else row
		for x in w:
			_trail[row + x] = (_tmp[up + x] + _tmp[row + x] + _tmp[dn + x]) * k


## Mean trail per map tile, normalized so the 90th percentile maps to 1.0
## (values above it are clamped). Indexed by y * tile_w + x.
func tile_trail() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(tile_w * tile_h)
	var inv := 1.0 / float(sub * sub)
	for ty in tile_h:
		for tx in tile_w:
			var s := 0.0
			for dy in sub:
				var row := (ty * sub + dy) * _w + tx * sub
				for dx in sub:
					s += _trail[row + dx]
			out[ty * tile_w + tx] = s * inv
	var sorted := out.duplicate()
	sorted.sort()
	var ref := sorted[int(sorted.size() * 0.9)]
	if ref <= 0.0:
		return out
	for i in out.size():
		out[i] = minf(out[i] / ref, 1.0)
	return out


## Agent positions in tile coordinates (for tests and debugging).
func agent_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(_ax.size())
	for i in _ax.size():
		out[i] = Vector2(_ax[i], _ay[i]) / sub
	return out
