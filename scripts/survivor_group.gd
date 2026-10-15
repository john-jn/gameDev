class_name SurvivorGroup
extends RefCounted
## One survivor group: its position, dispatched path and tile-by-tile movement.
## Groups never move on their own; they only follow a dispatched route.

enum State { WAITING, MOVING, BLOCKED, DELIVERED, LOST }

const SPEED := 2.5  ## tiles per second

var id := 0
var label := "A"
var tile := Vector2i.ZERO          ## tile the group currently stands on
var survivors := 0
var initial_survivors := 0
var state := State.WAITING
var path: Array[Vector2i] = []
var index := 0                     ## index of `tile` inside `path`
var t := 0.0                       ## 0..1 progress from path[index] to path[index + 1]
var halt_requested := false
var blocked_since := 0.0           ## round time when a hazard cut the route
var blocking_tile := CityMap.NO_TILE
var route_tiles_total := 0         ## sum of dispatched route lengths (for efficiency)
var shortest_tiles_total := 0      ## sum of shortest available lengths at each dispatch
var casualties := 0


func _init(p_id: int, p_label: String, p_tile: Vector2i, p_size: int) -> void:
	id = p_id
	label = p_label
	tile = p_tile
	survivors = p_size
	initial_survivors = p_size


func is_active() -> bool:
	return state == State.WAITING or state == State.MOVING or state == State.BLOCKED


func can_plan() -> bool:
	return state == State.WAITING or state == State.BLOCKED


func dispatch(route: Array[Vector2i]) -> void:
	path = route.duplicate()
	index = 0
	t = 0.0
	halt_requested = false
	blocking_tile = CityMap.NO_TILE
	state = State.MOVING


func next_tile() -> Vector2i:
	if state == State.MOVING and index + 1 < path.size():
		return path[index + 1]
	return tile


## The tile the group will be standing on once it stops (it never stops mid-step).
func stop_tile() -> Vector2i:
	if state == State.MOVING and t > 0.0:
		return next_tile()
	return tile


## True if `p` lies on the part of the route the group has not walked yet.
func remaining_contains(p: Vector2i) -> bool:
	if state != State.MOVING:
		return false
	for i in range(index + 1, path.size()):
		if path[i] == p:
			return true
	return false


func request_halt(fire_tile: Vector2i, now: float) -> void:
	halt_requested = true
	blocking_tile = fire_tile
	blocked_since = now


## Position in (fractional) tile coordinates, for smooth drawing.
func draw_position() -> Vector2:
	if state == State.MOVING and t > 0.0:
		return Vector2(tile).lerp(Vector2(next_tile()), t)
	return Vector2(tile)


## Advances movement by `delta` seconds. Returns events for the game:
## {"type": "halted" | "casualty" | "delivered" | "lost", "tile": Vector2i}
func step(delta: float, map: CityMap) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state != State.MOVING:
		return events
	if t == 0.0:
		# At a tile boundary: only continue if the next tile is still safe to enter.
		if halt_requested or map.is_fire(next_tile()) or index >= path.size() - 1:
			if blocking_tile == CityMap.NO_TILE:
				blocking_tile = next_tile()
			state = State.BLOCKED
			halt_requested = false
			events.append({"type": "halted", "tile": tile})
			return events
	t += delta * SPEED
	if t >= 1.0:
		t = 0.0
		index += 1
		tile = path[index]
		if map.is_safe(tile):
			state = State.DELIVERED
			events.append({"type": "delivered", "tile": tile})
			return events
		if map.is_smoke(tile):
			survivors -= 1
			casualties += 1
			events.append({"type": "casualty", "tile": tile})
			if survivors <= 0:
				state = State.LOST
				events.append({"type": "lost", "tile": tile})
	return events
