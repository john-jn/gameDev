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
var fire_lethal := false           ## a burning tile kills the group, and there is no auto-halt
var smoke_drain := 0.0             ## seconds per survivor lost while standing in smoke (0 = off)
var smoke_timer := 0.0             ## time stood in smoke since the last loss
var _manual_stop := false          ## the pending halt came from the operator's STOP
var _backing_off := false          ## STOP between tiles: walking back to the last tile reached


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


## Marks a waiting or blocked group as lost when no route to safety remains.
## Returns the number of survivors trapped in the group.
func mark_trapped() -> int:
	if state != State.WAITING and state != State.BLOCKED:
		return 0
	var count := survivors
	casualties += count
	survivors = 0
	state = State.LOST
	return count


func dispatch(route: Array[Vector2i]) -> void:
	path = route.duplicate()
	index = 0
	t = 0.0
	halt_requested = false
	blocking_tile = CityMap.NO_TILE
	smoke_timer = 0.0
	_manual_stop = false
	_backing_off = false
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


## The operator's STOP. It takes effect at once: a group standing on a tile
## halts there, and a group between tiles walks back to the tile it last
## reached instead of finishing the step. So STOP never carries a group onto
## a tile it had not reached yet, such as one about to ignite. Either way the
## group ends up BLOCKED, ready for a detour.
func stop(now: float) -> void:
	if state != State.MOVING or _backing_off:
		return
	blocked_since = now
	blocking_tile = next_tile()
	halt_requested = true
	_manual_stop = true
	if t > 0.0:
		var back: Array[Vector2i] = [next_tile(), tile]
		path = back
		index = 0
		tile = back[0]
		t = 1.0 - t
		_backing_off = true


## True while the group stands still in smoke and is losing people to it.
func is_draining(map: CityMap) -> bool:
	return smoke_drain > 0.0 and (state == State.WAITING or state == State.BLOCKED) and map.is_smoke(tile)


## Position in (fractional) tile coordinates, for smooth drawing.
func draw_position() -> Vector2:
	if state == State.MOVING and t > 0.0:
		return Vector2(tile).lerp(Vector2(next_tile()), t)
	return Vector2(tile)


## Advances the group by `delta` seconds. Returns events for the game:
## {"type": "halted" | "casualty" | "delivered" | "lost", "tile": Vector2i}
## "halted" also has "manual" (true after STOP); "lost" has "cause"
## ("smoke" | "fire") and, for fire, "count" (survivors lost with it).
func step(delta: float, map: CityMap) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state == State.WAITING or state == State.BLOCKED:
		_check_fire(map, events)
		if is_active():
			_drain_smoke(delta, map, events)
		return events
	if state != State.MOVING:
		return events
	smoke_timer = 0.0
	if t == 0.0:
		# At a tile boundary: stop when asked to, at the end of the path, or
		# (only while fire is not lethal) before a burning tile.
		if halt_requested or (not fire_lethal and map.is_fire(next_tile())) or index >= path.size() - 1:
			if blocking_tile == CityMap.NO_TILE:
				blocking_tile = next_tile()
			state = State.BLOCKED
			halt_requested = false
			events.append({"type": "halted", "tile": tile, "manual": _manual_stop})
			_manual_stop = false
			_backing_off = false
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
		# Backing off after STOP re-enters a tile the group already paid for.
		if map.is_smoke(tile) and not _backing_off:
			_lose_survivor(events)
			if state == State.LOST:
				return events
	_check_fire(map, events)
	return events


## Lethal fire: a group on a burning tile is lost with everyone in it. A group
## between tiles is on whichever tile it is closer to.
func _check_fire(map: CityMap, events: Array[Dictionary]) -> void:
	if not fire_lethal:
		return
	var at := tile if t < 0.5 else next_tile()
	if not map.is_fire(at):
		return
	var count := survivors
	casualties += count
	survivors = 0
	state = State.LOST
	events.append({"type": "lost", "tile": at, "cause": "fire", "count": count})


## Standing still in smoke costs one survivor every `smoke_drain` seconds. The
## first loss comes after one full interval; leaving the smoke resets it.
func _drain_smoke(delta: float, map: CityMap, events: Array[Dictionary]) -> void:
	if not is_draining(map):
		smoke_timer = 0.0
		return
	smoke_timer += delta
	if smoke_timer >= smoke_drain:
		smoke_timer -= smoke_drain
		_lose_survivor(events)


func _lose_survivor(events: Array[Dictionary]) -> void:
	survivors -= 1
	casualties += 1
	events.append({"type": "casualty", "tile": tile})
	if survivors <= 0:
		state = State.LOST
		events.append({"type": "lost", "tile": tile, "cause": "smoke"})
