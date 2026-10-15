class_name MapView
extends Control
## Draws the city grid straight down (bird's-eye) and turns pointer input into
## tile events. It holds no game rules: the game controller pushes state into
## the public fields each frame and reacts to the signals.
## Touch works through Godot's default "emulate mouse from touch" setting.

signal tile_pressed(tile: Vector2i)
signal tile_dragged(tile: Vector2i)

const COL_MAP_BG := Color("0a1019")
const COL_ROAD := Color("b9c4d2")
const COL_ROAD_X := Color("cdd6e2")
const COL_ROAD_MARK := Color("7d8a9c")
const COL_BUILDING := [Color("27303e"), Color("2b3545"), Color("2f394a")]
const COL_BUILDING_ROOF := Color("364258")
const COL_PARK := Color("1f3a2b")
const COL_PARK_TREE := Color("2f5e40")
const COL_SAFE := Color("1d8f5c")
const COL_SAFE_EDGE := Color("5ff2ad")
const COL_FIRE := Color("e2412a")
const COL_FIRE_CORE := Color("ffd23f")
const COL_SMOKE := Color(1.0, 0.62, 0.1, 0.5)
const COL_SMOKE_LINE := Color("8a4a00")
const COL_ROUTE := Color("1fb8f0")
const COL_ROUTE_BAD := Color("ff3b5c")
const COL_OUTLINE := Color("08101c")
const COL_SURVIVOR := Color("ffe066")
const COL_SELECT := Color("27c4f5")
const COL_ALERT := Color("ff4d3d")
const POPUP_LIFETIME := 1.6

var map: CityMap
var groups: Array[SurvivorGroup] = []
var selected: SurvivorGroup = null
var route: Array[Vector2i] = []
var route_bad_index := -1
var route_complete := false
## Fire tiles that cut a route; drawn with a pulsing alert ring.
var alert_tiles: Array[Vector2i] = []

var _time := 0.0
var _hover := CityMap.NO_TILE
var _flash_tile := CityMap.NO_TILE
var _flash_left := 0.0
var _dragging := false
var _last_drag_pos := Vector2.ZERO
var _last_drag_tile := CityMap.NO_TILE
var _popups: Array[Dictionary] = []
var _ts := 32.0
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	_time += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i]["age"] += delta
		if _popups[i]["age"] > POPUP_LIFETIME:
			_popups.remove_at(i)
	queue_redraw()


## Red X feedback on a tile the operator cannot use.
func flash_invalid(tile: Vector2i) -> void:
	_flash_tile = tile
	_flash_left = 0.7


## Drops transient effects when a new round starts.
func reset_effects() -> void:
	_popups.clear()
	alert_tiles.clear()
	_flash_left = 0.0


## Floating text (points, casualties, alerts) rising from a tile.
func popup(tile: Vector2i, text: String, color: Color) -> void:
	_popups.append({"tile": tile, "text": text, "color": color, "age": 0.0})


# --- Layout helpers -----------------------------------------------------------

func _update_layout() -> void:
	if map == null:
		return
	_ts = floorf(minf((size.x - 16.0) / map.width, (size.y - 16.0) / map.height))
	_ts = maxf(_ts, 6.0)
	_origin = ((size - Vector2(map.width, map.height) * _ts) * 0.5).floor()


func tile_rect(p: Vector2i) -> Rect2:
	return Rect2(_origin + Vector2(p) * _ts, Vector2(_ts, _ts))


func tile_center(p: Vector2i) -> Vector2:
	return _origin + (Vector2(p) + Vector2(0.5, 0.5)) * _ts


func grid_to_screen(v: Vector2) -> Vector2:
	return _origin + (v + Vector2(0.5, 0.5)) * _ts


func screen_to_tile(pos: Vector2) -> Vector2i:
	var v := (pos - _origin) / _ts
	return Vector2i(floori(v.x), floori(v.y))


# --- Input ----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	_update_layout()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var t := screen_to_tile(event.position)
			_dragging = true
			_last_drag_pos = event.position
			_last_drag_tile = t
			if map.in_bounds(t):
				tile_pressed.emit(t)
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		_hover = screen_to_tile(event.position)
		if _dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_drag_to(event.position)
		else:
			_dragging = false


## Samples the pointer path finely so fast drags still visit every tile.
func _drag_to(pos: Vector2) -> void:
	var steps := maxi(1, ceili(_last_drag_pos.distance_to(pos) / (_ts * 0.25)))
	for i in range(1, steps + 1):
		var t := screen_to_tile(_last_drag_pos.lerp(pos, float(i) / steps))
		if t != _last_drag_tile:
			_last_drag_tile = t
			if map.in_bounds(t):
				tile_dragged.emit(t)
	_last_drag_pos = pos


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = CityMap.NO_TILE


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_MAP_BG)
	if map == null:
		return
	_update_layout()
	var font := get_theme_default_font()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)

	# 1. Ground: roads, buildings, parks, safe zone.
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var r := tile_rect(p)
			match map.get_tile(p):
				CityMap.Tile.ROAD:
					_draw_road(p, r)
				CityMap.Tile.BUILDING:
					draw_building(self, r, (x * 7 + y * 13) % 3)
				CityMap.Tile.PARK:
					draw_park(self, r)
				CityMap.Tile.SAFE:
					draw_rect(r, COL_SAFE)
	_draw_safe_zone_frame(font)

	# 2. Hazards: smoke (hatched amber) then fire (red with X and flame).
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if map.is_smoke(p):
				draw_smoke(self, tile_rect(p))
	for f in map.fires:
		draw_fire(self, tile_rect(f), _time)
	for a in alert_tiles:
		if map.is_fire(a):
			draw_arc(tile_center(a), _ts * (0.75 + 0.25 * pulse), 0, TAU, 28, Color(COL_ALERT, 0.9), 3.0, true)

	# 3. Paths of groups already en route (dashed), and blocked segments (red).
	for g in groups:
		if g.state == SurvivorGroup.State.MOVING:
			var from := grid_to_screen(g.draw_position())
			for i in range(g.index + 1, g.path.size()):
				var to := tile_center(g.path[i])
				var col := COL_ALERT if g.halt_requested else Color(COL_SURVIVOR, 0.85)
				draw_dashed_line(from, to, col, maxf(2.0, _ts * 0.09), _ts * 0.22, true)
				from = to
		elif g.state == SurvivorGroup.State.BLOCKED and g.blocking_tile != CityMap.NO_TILE:
			_draw_blocked_segment(g, pulse)

	# 4. The operator's planned route.
	if selected != null and not route.is_empty():
		_draw_planned_route(pulse)

	# 5. Hover and invalid-tap feedback.
	if map.in_bounds(_hover):
		draw_rect(tile_rect(_hover).grow(-1.0), Color(1, 1, 1, 0.55), false, 2.0)
	if _flash_left > 0.0 and map.in_bounds(_flash_tile):
		var fr := tile_rect(_flash_tile).grow(-_ts * 0.12)
		var fc := Color(COL_ROUTE_BAD, clampf(_flash_left / 0.4, 0.0, 1.0))
		draw_rect(tile_rect(_flash_tile), fc, false, 3.0)
		draw_line(fr.position, fr.end, fc, 3.0, true)
		draw_line(Vector2(fr.end.x, fr.position.y), Vector2(fr.position.x, fr.end.y), fc, 3.0, true)

	# 6. Survivor groups.
	for g in groups:
		if not g.is_active():
			continue
		var c := grid_to_screen(g.draw_position())
		var rad := _ts * 0.36
		if g == selected:
			draw_arc(c, rad + 5.0 + 3.0 * pulse, 0, TAU, 32, COL_SELECT, 3.0, true)
		elif g.state == SurvivorGroup.State.BLOCKED:
			draw_arc(c, rad + 5.0 + 4.0 * pulse, 0, TAU, 32, COL_ALERT, 3.0, true)
		elif g.state == SurvivorGroup.State.WAITING:
			draw_arc(c, rad + 3.0 + 2.0 * pulse, 0, TAU, 32, Color(1, 1, 1, 0.45), 1.5, true)
		var fill := COL_SURVIVOR
		if g.state == SurvivorGroup.State.BLOCKED:
			fill = Color("ff9f43")
		draw_survivor(self, font, c, rad, g.label, g.survivors, fill)

	# 7. Floating popups.
	for pp in _popups:
		var age: float = pp["age"]
		var alpha := clampf(1.0 - age / POPUP_LIFETIME, 0.0, 1.0)
		var pos := tile_center(pp["tile"]) + Vector2(0, -_ts * 0.6 - age * 24.0)
		var col: Color = pp["color"]
		var fs := int(clampf(_ts * 0.55, 12, 20))
		var w := font.get_string_size(pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, pos - Vector2(w * 0.5, 0), pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, alpha))
		draw_string(font, pos - Vector2(w * 0.5, 0), pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, alpha))

	# 8. Map frame.
	draw_rect(Rect2(_origin, Vector2(map.width, map.height) * _ts), Color(COL_SELECT, 0.3), false, 1.0)


func _draw_road(p: Vector2i, r: Rect2) -> void:
	var h := map.is_street(p + Vector2i(1, 0)) or map.is_street(p + Vector2i(-1, 0))
	var v := map.is_street(p + Vector2i(0, 1)) or map.is_street(p + Vector2i(0, -1))
	if map.is_intersection(p):
		draw_rect(r, COL_ROAD_X)
		return
	draw_rect(r, COL_ROAD)
	var c := r.get_center()
	var w := maxf(1.0, _ts * 0.06)
	if h and not v:
		draw_line(c - Vector2(_ts * 0.22, 0), c + Vector2(_ts * 0.22, 0), COL_ROAD_MARK, w)
	elif v and not h:
		draw_line(c - Vector2(0, _ts * 0.22), c + Vector2(0, _ts * 0.22), COL_ROAD_MARK, w)


func _draw_safe_zone_frame(font: Font) -> void:
	var min_p := Vector2i(map.width, map.height)
	var max_p := Vector2i(-1, -1)
	for y in map.height:
		for x in map.width:
			if map.is_safe(Vector2i(x, y)):
				min_p = Vector2i(mini(min_p.x, x), mini(min_p.y, y))
				max_p = Vector2i(maxi(max_p.x, x), maxi(max_p.y, y))
	if max_p.x < 0:
		return
	var r := Rect2(tile_rect(min_p).position, Vector2(max_p - min_p + Vector2i.ONE) * _ts)
	draw_rect(r.grow(-2.0), COL_SAFE_EDGE, false, 3.0)
	var c := r.get_center()
	var arm := minf(r.size.x, r.size.y) * 0.18
	var th := maxf(3.0, arm * 0.45)
	draw_rect(Rect2(c.x - arm, c.y - th * 0.5 - arm * 0.35, arm * 2.0, th), Color.WHITE)
	draw_rect(Rect2(c.x - th * 0.5, c.y - arm - arm * 0.35, th, arm * 2.0), Color.WHITE)
	draw_text_centered(self, font, c + Vector2(0, arm * 1.15), "SAFE", int(clampf(_ts * 0.5, 10, 18)), Color.WHITE)


func _draw_blocked_segment(g: SurvivorGroup, pulse: float) -> void:
	var from := tile_center(g.tile)
	var started := false
	for i in range(0, g.path.size()):
		if g.path[i] == g.tile:
			started = true
			continue
		if not started:
			continue
		var to := tile_center(g.path[i])
		draw_line(from, to, Color(COL_ALERT, 0.5 + 0.5 * pulse), maxf(3.0, _ts * 0.16), true)
		from = to
		if g.path[i] == g.blocking_tile:
			break


func _draw_planned_route(pulse: float) -> void:
	var pts := PackedVector2Array()
	for p in route:
		pts.append(tile_center(p))
	var width := maxf(3.0, _ts * 0.26)
	var good := route.size() if route_bad_index < 0 else route_bad_index
	if pts.size() >= 2:
		draw_polyline(pts, COL_OUTLINE, width + 4.0, true)
		if good >= 2:
			draw_polyline(pts.slice(0, good), COL_ROUTE, width, true)
		if route_bad_index >= 0:
			draw_polyline(pts.slice(maxi(good - 1, 0)), COL_ROUTE_BAD, width, true)
	for i in range(1, pts.size()):
		draw_circle(pts[i], width * 0.32, COL_OUTLINE)
	if route_bad_index >= 0 and route_bad_index < route.size():
		var br := tile_rect(route[route_bad_index]).grow(-_ts * 0.15)
		draw_line(br.position, br.end, COL_ROUTE_BAD, 3.0, true)
		draw_line(Vector2(br.end.x, br.position.y), Vector2(br.position.x, br.end.y), COL_ROUTE_BAD, 3.0, true)
		return
	var last := route[-1]
	if route_complete:
		var c := tile_center(last)
		draw_circle(c, _ts * 0.3, COL_OUTLINE)
		draw_circle(c, _ts * 0.24, COL_SAFE_EDGE)
		draw_polyline(PackedVector2Array([c + Vector2(-_ts * 0.11, 0), c + Vector2(-_ts * 0.02, _ts * 0.09), c + Vector2(_ts * 0.13, -_ts * 0.09)]), COL_OUTLINE, 2.5, true)
		return
	# Route still open: outline the tiles it can extend into next.
	for d in CityMap.DIRS:
		var n: Vector2i = last + d
		if map.is_passable(n) and not route.has(n):
			var col := Color(COL_ROUTE, 0.45 + 0.45 * pulse)
			if map.is_smoke(n):
				col = Color("ffb020", 0.45 + 0.45 * pulse)
			draw_rect(tile_rect(n).grow(-2.0), col, false, 2.0)
	draw_arc(tile_center(last), _ts * 0.3, 0, TAU, 24, COL_ROUTE, 2.5, true)


# --- Shared symbol painters (also used by the legend) -------------------------

static func draw_building(ci: CanvasItem, r: Rect2, variant: int) -> void:
	var inset := maxf(1.0, r.size.x * 0.06)
	var body := r.grow(-inset)
	ci.draw_rect(body, COL_BUILDING[variant % COL_BUILDING.size()])
	ci.draw_rect(body.grow(-r.size.x * 0.2), COL_BUILDING_ROOF)


static func draw_park(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r.grow(-maxf(1.0, r.size.x * 0.06)), COL_PARK)
	ci.draw_circle(r.get_center(), r.size.x * 0.26, COL_PARK_TREE)


static func draw_smoke(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, COL_SMOKE)
	var w := maxf(1.0, r.size.x * 0.06)
	for k in [0.33, 0.66, 1.0]:
		ci.draw_line(r.position + Vector2(0, r.size.y * k), r.position + Vector2(r.size.x * k, 0), COL_SMOKE_LINE, w, true)
	for k in [0.33, 0.66]:
		ci.draw_line(r.position + Vector2(r.size.x * k, r.size.y), r.position + Vector2(r.size.x, r.size.y * k), COL_SMOKE_LINE, w, true)


static func draw_fire(ci: CanvasItem, r: Rect2, time: float) -> void:
	var body := r.grow(-1.0)
	ci.draw_rect(body, COL_FIRE)
	var x := body.grow(-r.size.x * 0.12)
	var w := maxf(2.0, r.size.x * 0.08)
	ci.draw_line(x.position, x.end, COL_OUTLINE, w, true)
	ci.draw_line(Vector2(x.end.x, x.position.y), Vector2(x.position.x, x.end.y), COL_OUTLINE, w, true)
	var c := r.get_center()
	var flick := 1.0 + 0.12 * sin(time * 13.0 + r.position.x)
	var s := r.size.x * 0.24 * flick
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.2), c + Vector2(s * 0.8, s * 0.7), c + Vector2(-s * 0.8, s * 0.7)]), COL_FIRE_CORE)


static func draw_survivor(ci: CanvasItem, font: Font, c: Vector2, rad: float, label: String, count: int, fill: Color) -> void:
	ci.draw_circle(c, rad + 2.0, COL_OUTLINE)
	ci.draw_circle(c, rad, fill)
	draw_text_centered(ci, font, c, label, int(maxf(9.0, rad * 1.1)), COL_OUTLINE)
	if count >= 0:
		var bc := c + Vector2(rad * 0.9, -rad * 0.9)
		var br := maxf(6.0, rad * 0.5)
		ci.draw_circle(bc, br, COL_OUTLINE)
		draw_text_centered(ci, font, bc, str(count), int(maxf(8.0, br * 1.3)), Color.WHITE)


static func draw_text_centered(ci: CanvasItem, font: Font, center: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var asc := font.get_ascent(font_size)
	var desc := font.get_descent(font_size)
	ci.draw_string(font, Vector2(center.x - w * 0.5, center.y + (asc - desc) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func draw_legend_symbol(ci: CanvasItem, kind: String, r: Rect2, font: Font) -> void:
	match kind:
		"road":
			ci.draw_rect(r, COL_ROAD)
			ci.draw_line(r.get_center() - Vector2(r.size.x * 0.22, 0), r.get_center() + Vector2(r.size.x * 0.22, 0), COL_ROAD_MARK, 1.5)
		"building":
			draw_building(ci, r, 1)
		"park":
			draw_park(ci, r)
		"safe":
			ci.draw_rect(r, COL_SAFE)
			ci.draw_rect(r.grow(-1.0), COL_SAFE_EDGE, false, 2.0)
			draw_text_centered(ci, font, r.get_center(), "+", int(r.size.y * 0.8), Color.WHITE)
		"survivor":
			draw_survivor(ci, font, r.get_center(), r.size.x * 0.38, "A", -1, COL_SURVIVOR)
		"route":
			ci.draw_rect(r, COL_ROAD)
			ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), COL_OUTLINE, 7.0)
			ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), COL_ROUTE, 5.0)
		"bad":
			ci.draw_rect(r, COL_ROAD)
			ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), COL_ROUTE_BAD, 5.0)
			var x := r.grow(-r.size.x * 0.2)
			ci.draw_line(x.position, x.end, COL_ROUTE_BAD, 2.0, true)
			ci.draw_line(Vector2(x.end.x, x.position.y), Vector2(x.position.x, x.end.y), COL_ROUTE_BAD, 2.0, true)
		"fire":
			draw_fire(ci, r, 0.0)
		"smoke":
			ci.draw_rect(r, COL_ROAD)
			draw_smoke(ci, r)
