class_name MapView
extends Control
## Draws the city straight down (bird's-eye) and turns pointer input into
## tile events. It holds no game rules: the game controller pushes state into
## the public fields each frame and reacts to the signals.
## This script decides what is drawn where. How each object looks comes from
## `visual_theme` (VisualTheme) through the painters in MapPainter.
## The city itself (ground, roads, lots) is on a layer that is only redrawn
## when the map, theme or size changes. Hazards, routes and survivors are
## redrawn every frame on a layer above it. Neither layer takes input.
## Touch works through Godot's default "emulate mouse from touch" setting.

signal tile_pressed(tile: Vector2i)
signal tile_dragged(tile: Vector2i)

const POPUP_LIFETIME := 1.6


## A full-size, input-transparent canvas that paints through a view callback.
class Layer extends Control:
	var paint: Callable

	func _init(p_paint: Callable) -> void:
		paint = p_paint
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		paint.call(self)


var map: CityMap:
	set(value):
		if value != map:
			map = value
			_city_dirty = true
var visual_theme: VisualTheme = VisualTheme.dispatch_style():
	set(value):
		visual_theme = value if value != null else VisualTheme.dispatch_style()
		refresh()
var groups: Array[SurvivorGroup] = []
var selected: SurvivorGroup = null
var route: Array[Vector2i] = []
var route_bad_index := -1
var route_complete := false
## Fire tiles that cut a route; drawn with a pulsing alert ring.
var alert_tiles: Array[Vector2i] = []
## Full smolder warning time, so embers pulse faster as ignition nears.
var smolder_time := 2.0

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
var _city_layer: Layer
var _overlay_layer: Layer
var _city_dirty := true
var _drawn_version := -1
var _shapes: Array[MapPainter.LotShape] = []  ## per building id, in tile units
var _shapes_key := []                         ## [map, layout_version, theme] of _shapes


func _init() -> void:
	_city_layer = Layer.new(_draw_city)
	_overlay_layer = Layer.new(_draw_overlay)
	add_child(_city_layer)
	add_child(_overlay_layer)


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
	if map != null and map.layout_version != _drawn_version:
		_city_dirty = true
	if _city_dirty:
		_city_dirty = false
		queue_redraw()
		_city_layer.queue_redraw()
	_overlay_layer.queue_redraw()


## Redraws the city layer and rebuilds cached lot geometry. Call after editing
## the current theme's properties in place.
func refresh() -> void:
	_shapes_key = []
	_city_dirty = true


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


## Tile units (one unit per tile, origin at the map's top-left) to screen.
func tile_transform() -> Transform2D:
	return Transform2D(Vector2(_ts, 0), Vector2(0, _ts), _origin)


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
	elif what == NOTIFICATION_RESIZED:
		_city_dirty = true


# --- City layer -------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), visual_theme.map_bg)


func _draw_city(ci: CanvasItem) -> void:
	if map == null:
		return
	_update_layout()
	_drawn_version = map.layout_version
	# A map without a city plan (built by hand, outside MapGenerator) still
	# shows every tile in the flat style.
	if visual_theme.style == VisualTheme.Style.DEBUG_SHAPES or map.building_ids.size() != map.tiles.size():
		_draw_city_flat(ci)
	else:
		_draw_city_dispatch(ci)


## One flat shape per tile: light roads, dark building squares, green safe tiles.
func _draw_city_flat(ci: CanvasItem) -> void:
	var th := visual_theme
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var r := tile_rect(p)
			match map.get_tile(p):
				CityMap.Tile.ROAD:
					MapPainter.draw_road_flat(ci, th, r, _street_marking(p), map.is_intersection(p))
				CityMap.Tile.BUILDING:
					MapPainter.draw_building_flat(ci, th, r, (x * 7 + y * 13) % 3)
				CityMap.Tile.PARK:
					MapPainter.draw_park_flat(ci, th, r)
				CityMap.Tile.SAFE:
					ci.draw_rect(r, th.safe_tile)
	if th.show_lot_debug and not map.buildings.is_empty():
		_ensure_shapes()
		var xf := tile_transform()
		for b in map.buildings:
			MapPainter.draw_lot_debug(ci, th, _shapes[b.id], xf)


## Dispatch map: block ground, curbed roads, then outlined lots on top.
func _draw_city_dispatch(ci: CanvasItem) -> void:
	var th := visual_theme
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var r := tile_rect(p)
			if map.get_tile(p) == CityMap.Tile.ROAD:
				var cls := map.get_road_class(p)
				var marking: int = _street_marking(p) if cls == CityMap.RoadClass.STREET and not map.is_intersection(p) else MapPainter.Marking.NONE
				var seams := 0
				if _lane_seam(p, Vector2i(1, 0)):
					seams |= MapPainter.SEAM_RIGHT
				if _lane_seam(p, Vector2i(0, 1)):
					seams |= MapPainter.SEAM_DOWN
				MapPainter.draw_road(ci, th, r, cls, _curb_sides(p), marking, seams)
			elif map.is_road_closure(p):
				MapPainter.draw_closed_road(ci, th, r, _sides_where(p, func(q: Vector2i) -> bool: return map.get_tile(q) == CityMap.Tile.ROAD), _curb_sides(p))
			else:
				ci.draw_rect(r, th.block_ground)
	_ensure_shapes()
	var xf := tile_transform()
	for b in map.buildings:
		MapPainter.draw_lot(ci, th, b, _shapes[b.id], xf, _ts)


## Rebuilds lot geometry when the map, its layout or the theme changed.
func _ensure_shapes() -> void:
	var key := [map, map.layout_version, visual_theme]
	if key == _shapes_key:
		return
	_shapes_key = key
	_shapes.clear()
	for b in map.buildings:
		_shapes.append(MapPainter.lot_shape(map, b, visual_theme))


## Side mask (MapPainter.SIDES order) of the neighbours of `p` passing `test`.
func _sides_where(p: Vector2i, test: Callable) -> int:
	var mask := 0
	for k in 4:
		if test.call(p + MapPainter.SIDES[k]):
			mask |= 1 << k
	return mask


## Sides of a road tile that border ground (lots or the map edge) rather than
## more road; closed roads count as road so curbs stay continuous.
func _curb_sides(p: Vector2i) -> int:
	return _sides_where(p, func(q: Vector2i) -> bool:
		return map.get_tile(q) != CityMap.Tile.ROAD and not map.is_road_closure(q))


## Centre-dash direction of a one-lane street tile.
func _street_marking(p: Vector2i) -> int:
	var h := map.is_street(p + Vector2i(1, 0)) or map.is_street(p + Vector2i(-1, 0))
	var v := map.is_street(p + Vector2i(0, 1)) or map.is_street(p + Vector2i(0, -1))
	if h and not v:
		return MapPainter.Marking.ALONG_X
	if v and not h:
		return MapPainter.Marking.ALONG_Y
	return MapPainter.Marking.NONE


## True where avenue tiles p and p + d are its two lanes: the pair continues
## as road on both sides (or runs off the map), and neither is a crossing.
func _lane_seam(p: Vector2i, d: Vector2i) -> bool:
	var q := p + d
	if map.get_road_class(p) != CityMap.RoadClass.AVENUE or map.get_road_class(q) != CityMap.RoadClass.AVENUE:
		return false
	var side := Vector2i(d.y, d.x)
	for s in [side, -side]:
		if map.in_bounds(p + s) and not (map.get_tile(p + s) == CityMap.Tile.ROAD and map.get_tile(q + s) == CityMap.Tile.ROAD):
			return false
	return _road_neighbors(p) < 4 and _road_neighbors(q) < 4


func _road_neighbors(p: Vector2i) -> int:
	var n := 0
	for d in CityMap.DIRS:
		if map.get_tile(p + d) == CityMap.Tile.ROAD:
			n += 1
	return n


# --- Overlay layer ----------------------------------------------------------------

func _draw_overlay(ci: CanvasItem) -> void:
	if map == null:
		return
	_update_layout()
	var th := visual_theme
	var font := get_theme_default_font()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)

	# 1. Safe-zone highlight on every designated building.
	if th.safe_highlight_enabled:
		_draw_safe_zones(ci, font, pulse)

	# 2. Hazards: smoke (hatched amber), smoldering embers, then fire (red with X and flame).
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if map.is_smoke(p):
				MapPainter.draw_smoke(ci, th, tile_rect(p))
	for s in map.smolders:
		var urgency := 1.0 - clampf(map.smolders[s] / maxf(smolder_time, 0.01), 0.0, 1.0)
		MapPainter.draw_smolder(ci, th, tile_rect(s), _time, urgency)
	for f in map.fires:
		MapPainter.draw_fire(ci, th, tile_rect(f), _time)
	for a in alert_tiles:
		if map.is_fire(a):
			ci.draw_arc(tile_center(a), _ts * (0.75 + 0.25 * pulse), 0, TAU, 28, Color(th.alert, 0.9), 3.0, true)

	# 3. Paths of groups already en route (dashed), and blocked segments (red).
	for g in groups:
		if g.state == SurvivorGroup.State.MOVING:
			var from := grid_to_screen(g.draw_position())
			for i in range(g.index + 1, g.path.size()):
				var to := tile_center(g.path[i])
				var col := th.alert if g.halt_requested else th.en_route
				ci.draw_dashed_line(from, to, col, maxf(2.0, _ts * 0.09), _ts * 0.22, true)
				from = to
		elif g.state == SurvivorGroup.State.BLOCKED and g.blocking_tile != CityMap.NO_TILE:
			_draw_blocked_segment(ci, g, pulse)

	# 4. The operator's planned route.
	if selected != null and not route.is_empty():
		_draw_planned_route(ci, pulse)

	# 5. Hover and invalid-tap feedback. Hovering a building outlines all of it.
	if map.in_bounds(_hover):
		var hb: CityBuilding = map.building_at(_hover) if th.style == VisualTheme.Style.DISPATCH_STYLE else null
		if hb != null:
			_ensure_shapes()
			MapPainter.draw_lot_hover(ci, th, tile_transform() * _shapes[hb.id].outline)
		else:
			ci.draw_rect(tile_rect(_hover).grow(-1.0), th.hover, false, 2.0)
	if _flash_left > 0.0 and map.in_bounds(_flash_tile):
		var fr := tile_rect(_flash_tile).grow(-_ts * 0.12)
		var fc := Color(th.route_bad, clampf(_flash_left / 0.4, 0.0, 1.0))
		ci.draw_rect(tile_rect(_flash_tile), fc, false, 3.0)
		ci.draw_line(fr.position, fr.end, fc, 3.0, true)
		ci.draw_line(Vector2(fr.end.x, fr.position.y), Vector2(fr.position.x, fr.end.y), fc, 3.0, true)

	# 6. Survivor groups.
	for g in groups:
		if not g.is_active():
			continue
		var c := grid_to_screen(g.draw_position())
		var rad := _ts * th.survivor_radius_ratio
		if g == selected:
			ci.draw_arc(c, rad + 5.0 + 3.0 * pulse, 0, TAU, 32, th.select_ring, 3.0, true)
		elif g.state == SurvivorGroup.State.BLOCKED:
			ci.draw_arc(c, rad + 5.0 + 4.0 * pulse, 0, TAU, 32, th.alert, 3.0, true)
		elif g.state == SurvivorGroup.State.WAITING:
			ci.draw_arc(c, rad + 3.0 + 2.0 * pulse, 0, TAU, 32, th.waiting_ring, 1.5, true)
		if g.is_draining(map):
			# Countdown ring that fills toward the next smoke loss, flashing amber.
			var ring := rad + 9.0
			var k := clampf(g.smoke_timer / g.smoke_drain, 0.0, 1.0)
			ci.draw_arc(c, ring, 0, TAU, 32, Color(th.smoke_drain_ring, 0.25), 3.0, true)
			ci.draw_arc(c, ring, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(th.smoke_drain_ring, 0.55 + 0.45 * pulse), 4.0, true)
		var fill := th.survivor_blocked if g.state == SurvivorGroup.State.BLOCKED else th.survivor
		MapPainter.draw_survivor(ci, th, font, c, rad, g.label, g.survivors, fill)

	# 7. Floating popups.
	for pp in _popups:
		var age: float = pp["age"]
		var alpha := clampf(1.0 - age / POPUP_LIFETIME, 0.0, 1.0)
		var pos := tile_center(pp["tile"]) + Vector2(0, -_ts * 0.6 - age * 24.0)
		var col: Color = pp["color"]
		var fs := int(clampf(_ts * 0.55, 12, 20))
		var w := font.get_string_size(pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string_outline(font, pos - Vector2(w * 0.5, 0), pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(th.outline, alpha))
		ci.draw_string(font, pos - Vector2(w * 0.5, 0), pp["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, alpha))

	# 8. Map frame.
	ci.draw_rect(Rect2(_origin, Vector2(map.width, map.height) * _ts), th.map_frame, false, 1.0)


## Highlights every building designated SAFE_ZONE. It brightens while a route
## is being planned, and most when the route already ends inside it.
func _draw_safe_zones(ci: CanvasItem, font: Font, pulse: float) -> void:
	var th := visual_theme
	var zones := map.safe_zones()
	if zones.is_empty():
		# No city plan: frame the SAFE tiles, as the flat prototype did.
		var lo := Vector2i(map.width, map.height)
		var hi := Vector2i(-1, -1)
		for y in map.height:
			for x in map.width:
				if map.is_safe(Vector2i(x, y)):
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		if hi.x >= 0:
			var none: Array[PackedVector2Array] = []
			MapPainter.draw_safe_zone(ci, th, font, PackedVector2Array(), none,
					Rect2(tile_rect(lo).position, Vector2(hi - lo + Vector2i.ONE) * _ts), _ts, pulse, 0.0)
		return
	_ensure_shapes()
	var xf := tile_transform()
	var goal: Vector2i = route[-1] if selected != null and route_complete and not route.is_empty() else CityMap.NO_TILE
	for b in zones:
		var s := _shapes[b.id]
		var doors: Array[PackedVector2Array] = []
		for d in s.doors:
			doors.append(xf * d)
		var emphasis := 1.0 if b.cells.has(goal) else (0.5 if selected != null else 0.0)
		var bounds := Rect2(tile_rect(b.bounds.position).position, Vector2(b.bounds.size) * _ts)
		MapPainter.draw_safe_zone(ci, th, font, xf * s.outline, doors, bounds, _ts, pulse, emphasis)


func _draw_blocked_segment(ci: CanvasItem, g: SurvivorGroup, pulse: float) -> void:
	var from := tile_center(g.tile)
	var started := false
	for i in range(0, g.path.size()):
		if g.path[i] == g.tile:
			started = true
			continue
		if not started:
			continue
		var to := tile_center(g.path[i])
		ci.draw_line(from, to, Color(visual_theme.alert, 0.5 + 0.5 * pulse), maxf(3.0, _ts * 0.16), true)
		from = to
		if g.path[i] == g.blocking_tile:
			break


func _draw_planned_route(ci: CanvasItem, pulse: float) -> void:
	var th := visual_theme
	var pts := PackedVector2Array()
	for p in route:
		pts.append(tile_center(p))
	var width := maxf(3.0, _ts * th.route_width_ratio)
	var good := route.size() if route_bad_index < 0 else route_bad_index
	if pts.size() >= 2:
		ci.draw_polyline(pts, th.outline, width + 4.0, true)
		if good >= 2:
			ci.draw_polyline(pts.slice(0, good), th.route, width, true)
		if route_bad_index >= 0:
			ci.draw_polyline(pts.slice(maxi(good - 1, 0)), th.route_bad, width, true)
	for i in range(1, pts.size()):
		ci.draw_circle(pts[i], width * 0.32, th.outline)
	if route_bad_index >= 0 and route_bad_index < route.size():
		var br := tile_rect(route[route_bad_index]).grow(-_ts * 0.15)
		ci.draw_line(br.position, br.end, th.route_bad, 3.0, true)
		ci.draw_line(Vector2(br.end.x, br.position.y), Vector2(br.position.x, br.end.y), th.route_bad, 3.0, true)
		return
	var last := route[-1]
	if route_complete:
		var c := tile_center(last)
		ci.draw_circle(c, _ts * 0.3, th.outline)
		ci.draw_circle(c, _ts * 0.24, th.safe_outline)
		ci.draw_polyline(PackedVector2Array([c + Vector2(-_ts * 0.11, 0), c + Vector2(-_ts * 0.02, _ts * 0.09), c + Vector2(_ts * 0.13, -_ts * 0.09)]), th.outline, 2.5, true)
		return
	# Route still open: outline the tiles it can extend into next.
	for d in CityMap.DIRS:
		var n: Vector2i = last + d
		if map.is_passable(n) and not route.has(n):
			var col := Color(th.route, 0.45 + 0.45 * pulse)
			if map.is_smoke(n):
				col = Color(th.next_step_smoke, 0.45 + 0.45 * pulse)
			ci.draw_rect(tile_rect(n).grow(-2.0), col, false, 2.0)
	ci.draw_arc(tile_center(last), _ts * 0.3, 0, TAU, 24, th.route, 2.5, true)
