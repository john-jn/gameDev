class_name MapPainter
extends RefCounted
## How each map object looks. Static painters draw one logical object (a road
## tile, a lot, a fire, a survivor marker...) onto any CanvasItem, using the
## colours, sizes and optional art of a VisualTheme. MapView decides what is
## drawn where; the legend reuses the same painters.
## Replacing a primitive with art means filling the theme's asset slot, or
## changing the one painter here. Map generation, pathfinding and the game
## controller do not change.
##
## Lot geometry (footprint outlines, rooftop details, entrances) is built once
## per map in tile units by lot_shape(); painters scale it with a Transform2D.

## Tile sides in order top, right, bottom, left. Bit k of a side mask is SIDES[k].
const SIDES := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Corner where side k starts, walking each tile clockwise on screen (y down).
const CORNERS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
const INWARD := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
## Direction a lot's front faces, per CityBuilding.rotation.
const FRONTS := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
const SEAM_RIGHT := 1
const SEAM_DOWN := 2

enum Marking { NONE, ALONG_X, ALONG_Y }


## Screen-independent geometry for one lot, in tile units.
class LotShape:
	var outline := PackedVector2Array()  ## footprint, pulled in from roads and neighbours
	var uvs := PackedVector2Array()      ## texture coordinates for `outline`
	var lines := PackedVector2Array()    ## rooftop detail segments, as point pairs
	var solids: Array[PackedVector2Array] = []  ## small filled rooftop shapes
	var holes: Array[PackedVector2Array] = []   ## courtyards, open to the ground
	var dots := PackedVector2Array()     ## park stipple
	var trees := PackedVector2Array()    ## park tree centres
	var doors: Array[PackedVector2Array] = []   ## per entrance: strip from footprint to road


# --- Lot geometry ------------------------------------------------------------------

static func lot_shape(m: CityMap, b: CityBuilding, th: VisualTheme) -> LotShape:
	var s := LotShape.new()
	var road_in := th.building_road_setback
	var lot_in := th.building_gap * 0.5
	s.outline = footprint_outline(m, b.cells, road_in, lot_in)
	var bounds := Rect2(b.bounds)
	for v in s.outline:
		s.uvs.append(_uv(v, bounds, b.rotation))
	if b.kind == CityBuilding.Kind.PARK:
		_park_details(s, b)
	else:
		_roof_details(s, b, Rect2(b.parts()[0]).grow(-maxf(road_in, lot_in)))
	for e in b.entrances:
		for c in b.cells:
			var d := e - c
			if absi(d.x) + absi(d.y) != 1:
				continue
			var dv := Vector2(d)
			var mid := (Vector2(c) + Vector2(e)) * 0.5 + Vector2(0.5, 0.5)
			var w := Vector2(-dv.y, dv.x) * 0.11
			var inner := mid - dv * road_in
			var outer := mid + dv * 0.06
			s.doors.append(PackedVector2Array([inner - w, inner + w, outer + w, outer - w]))
			break
	return s


## Outline of a set of tiles (tile units), clockwise on screen. Each unit edge
## is pulled inward by `road_inset` where it faces a road, a closed road or the
## map edge, and by `lot_inset` where it faces another lot, so footprints keep
## clear of the street and of each other. Handles any hole-free footprint
## (rectangles and Ls); concave corners stay square.
static func footprint_outline(m: CityMap, cells: Array[Vector2i], road_inset: float, lot_inset: float) -> PackedVector2Array:
	var inside := {}
	for c in cells:
		inside[c] = true
	var by_start := {}  # start corner -> [start, end, side, inset]
	var first := Vector2i(1 << 30, 1 << 30)
	for c in cells:
		for k in 4:
			var q: Vector2i = c + SIDES[k]
			if inside.has(q):
				continue
			var a: Vector2i = c + CORNERS[k]
			by_start[a] = [a, c + CORNERS[(k + 1) % 4], k, lot_inset if m.building_at(q) != null else road_inset]
			if a.y < first.y or (a.y == first.y and a.x < first.x):
				first = a
	var edges := []
	var cur: Array = by_start.get(first, [])
	while not cur.is_empty() and edges.size() < by_start.size():
		edges.append(cur)
		cur = by_start.get(cur[1], [])
		if not cur.is_empty() and cur[0] == first:
			break
	if edges.is_empty() or edges.size() != by_start.size():
		push_warning("Footprint %s is not a simple outline; drawing its bounds." % [cells])
		return _rect_poly(_cell_bounds(cells).grow(-road_inset))
	# Merge straight runs with the same inset, wrapping around the start.
	var runs := []
	for e in edges:
		if not runs.is_empty() and runs[-1][2] == e[2] and runs[-1][3] == e[3]:
			runs[-1][1] = e[1]
		else:
			runs.append(e.duplicate())
	if runs.size() > 1 and runs[0][2] == runs[-1][2] and runs[0][3] == runs[-1][3]:
		runs[0][0] = runs[-1][0]
		runs.pop_back()
	# Each corner moves in along both edge normals; a change of inset along a
	# straight side becomes a small step.
	var out := PackedVector2Array()
	for i in runs.size():
		var r1: Array = runs[i]
		var r2: Array = runs[(i + 1) % runs.size()]
		var p := Vector2(r1[1])
		var n1: Vector2 = INWARD[r1[2]] * float(r1[3])
		var n2: Vector2 = INWARD[r2[2]] * float(r2[3])
		if r1[2] == r2[2]:
			out.append(p + n1)
			out.append(p + n2)
		else:
			out.append(p + n1 + n2)
	return out


## Rooftop details for one of the CityBuilding.VARIANT_COUNT variants, inside
## the footprint's main rectangle `r`. Rotation picks which wall is the back.
static func _roof_details(s: LotShape, b: CityBuilding, r: Rect2) -> void:
	var square := absf(r.size.x - r.size.y) <= 0.01
	var along_x := r.size.x > r.size.y or (square and b.rotation % 2 == 1)
	var long := maxf(r.size.x, r.size.y)
	var short := minf(r.size.x, r.size.y)
	match posmod(b.variant, CityBuilding.VARIANT_COUNT):
		0:  # parapet
			_rect_lines(s.lines, r.grow(-0.09))
		1:  # ribbed roof, split across its long axis
			var n := clampi(roundi(long / 0.45), 2, 6)
			for i in range(1, n):
				var t := float(i) / n
				if along_x:
					var x := lerpf(r.position.x, r.end.x, t)
					s.lines.append_array([Vector2(x, r.position.y + 0.07), Vector2(x, r.end.y - 0.07)])
				else:
					var y := lerpf(r.position.y, r.end.y, t)
					s.lines.append_array([Vector2(r.position.x + 0.07, y), Vector2(r.end.x - 0.07, y)])
		2:  # parapet and plant units along the back wall
			_rect_lines(s.lines, r.grow(-0.09))
			var back: Vector2 = -FRONTS[posmod(b.rotation, 4)]
			var row_x := absf(back.y) > 0.5
			var u := minf(0.2, short * 0.26)
			var inner := r.grow(-0.17)
			var count := clampi(floori((inner.size.x if row_x else inner.size.y) / 0.42), 1, 4)
			for i in count:
				var t := (i + 0.5) / count
				var c := Vector2.ZERO
				if row_x:
					c = Vector2(lerpf(inner.position.x, inner.end.x, t), inner.position.y + u * 0.5 if back.y < 0.0 else inner.end.y - u * 0.5)
				else:
					c = Vector2(inner.position.x + u * 0.5 if back.x < 0.0 else inner.end.x - u * 0.5, lerpf(inner.position.y, inner.end.y, t))
				s.solids.append(_rect_poly(Rect2(c - Vector2(u, u) * 0.5, Vector2(u, u))))
		3:  # courtyard block, or a ridge line on narrow roofs
			if short >= 1.2:
				var yard := r.grow(-0.3)
				s.holes.append(_rect_poly(yard))
				_rect_lines(s.lines, r.grow(-0.09))
			elif along_x:
				s.lines.append_array([Vector2(r.position.x + 0.1, r.get_center().y), Vector2(r.end.x - 0.1, r.get_center().y)])
			else:
				s.lines.append_array([Vector2(r.get_center().x, r.position.y + 0.1), Vector2(r.get_center().x, r.end.y - 0.1)])
		4:  # stepped tower
			_rect_lines(s.lines, r.grow(-0.09))
			_rect_lines(s.lines, r.grow(-short * 0.3))
			if short >= 1.2:
				s.solids.append(_rect_poly(Rect2(r.get_center() - Vector2(0.1, 0.1), Vector2(0.2, 0.2))))


static func _park_details(s: LotShape, b: CityBuilding) -> void:
	for c in b.cells:
		for j in 3:
			for i in 3:
				var p := Vector2(c) + Vector2(0.2 + 0.28 * i + (0.1 if j == 1 else 0.0), 0.22 + 0.28 * j)
				if Geometry2D.is_point_in_polygon(p, s.outline):
					s.dots.append(p)
		if posmod(c.x + c.y + b.variant, 2) == 0:
			var t := Vector2(c) + Vector2(0.5, 0.5)
			if Geometry2D.is_point_in_polygon(t, s.outline):
				s.trees.append(t)


## Texture coordinate of `v` within `bounds`, turned `quarter_turns` clockwise,
## so the bottom edge of the art ends up on the lot's front.
static func _uv(v: Vector2, bounds: Rect2, quarter_turns: int) -> Vector2:
	var uv := (v - bounds.position) / bounds.size
	for i in posmod(quarter_turns, 4):
		uv = Vector2(uv.y, 1.0 - uv.x)
	return uv


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _rect_lines(out: PackedVector2Array, r: Rect2) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	out.append_array([a, b, b, c, c, d, d, a])


static func _cell_bounds(cells: Array[Vector2i]) -> Rect2:
	var r := Rect2(Vector2(cells[0]), Vector2.ONE)
	for c in cells:
		r = r.merge(Rect2(Vector2(c), Vector2.ONE))
	return r


# --- City layer: DISPATCH_STYLE -------------------------------------------------

## One road tile. `curbs` is a side mask of edges facing non-road ground;
## `marking` the centre dash of a one-lane street; `seams` (SEAM_*) the lane
## divider on the right or bottom edge of an avenue tile.
static func draw_road(ci: CanvasItem, th: VisualTheme, r: Rect2, road_class: int, curbs: int, marking: int, seams: int) -> void:
	ci.draw_rect(r, th.avenue if road_class == CityMap.RoadClass.AVENUE else th.road)
	var mw := maxf(1.0, r.size.x * th.road_marking_ratio)
	var c := r.get_center()
	if marking == Marking.ALONG_X:
		ci.draw_line(c - Vector2(r.size.x * 0.2, 0), c + Vector2(r.size.x * 0.2, 0), th.road_marking, mw)
	elif marking == Marking.ALONG_Y:
		ci.draw_line(c - Vector2(0, r.size.y * 0.2), c + Vector2(0, r.size.y * 0.2), th.road_marking, mw)
	if seams & SEAM_RIGHT:
		ci.draw_line(Vector2(r.end.x - mw * 0.5, r.position.y), Vector2(r.end.x - mw * 0.5, r.end.y), th.road_marking, mw)
	if seams & SEAM_DOWN:
		ci.draw_line(Vector2(r.position.x, r.end.y - mw * 0.5), Vector2(r.end.x, r.end.y - mw * 0.5), th.road_marking, mw)
	_draw_sides(ci, r, curbs, th.road_edge, th.road_edge_width)


## A road closed by rubble: hatched tarmac with a barrier toward open road.
static func draw_closed_road(ci: CanvasItem, th: VisualTheme, r: Rect2, barriers: int, curbs: int) -> void:
	ci.draw_rect(r, th.closed_road)
	_hatch(ci, r, th.closed_hatch, maxf(1.0, r.size.x * 0.05))
	_draw_sides(ci, r, curbs, th.road_edge, th.road_edge_width)
	var bw := maxf(2.0, r.size.x * 0.12)
	for k in 4:
		if barriers & (1 << k):
			var a := r.position + Vector2(CORNERS[k]) * r.size
			var b := r.position + Vector2(CORNERS[(k + 1) % 4]) * r.size
			var inward: Vector2 = INWARD[k] * (bw * 0.5 + 1.0)
			var trim := (b - a).normalized() * r.size.x * 0.12
			ci.draw_line(a + inward + trim, b + inward - trim, th.closed_barrier, bw)


## A building or park lot from its cached shape. Uses the theme's art for the
## lot's variant when one is assigned, otherwise flat fill plus rooftop lines.
static func draw_lot(ci: CanvasItem, th: VisualTheme, b: CityBuilding, s: LotShape, xf: Transform2D, ts: float) -> void:
	var poly := xf * s.outline
	if b.kind == CityBuilding.Kind.PARK:
		_fill(ci, poly, th.park_fill, s.uvs, th.park_texture)
		if th.park_texture == null:
			var d := maxf(1.0, ts * 0.045)
			for p in s.dots:
				ci.draw_rect(Rect2(xf * p - Vector2(d, d) * 0.5, Vector2(d, d)), th.park_detail)
			for p in s.trees:
				ci.draw_circle(xf * p, ts * 0.17, th.park_tree)
				ci.draw_arc(xf * p, ts * 0.17, 0, TAU, 16, th.park_detail, 1.0, true)
		_closed_line(ci, poly, th.park_edge, 1.0)
		return
	var tex := th.building_texture(b.variant)
	_fill(ci, poly, th.building_fill(b.variant), s.uvs, tex)
	if tex == null:
		for h in s.holes:
			var hp := xf * h
			ci.draw_colored_polygon(hp, th.block_ground)
			_closed_line(ci, hp, th.building_detail, th.building_detail_width)
		for so in s.solids:
			ci.draw_colored_polygon(xf * so, th.building_detail)
		if not s.lines.is_empty():
			ci.draw_multiline(xf * s.lines, th.building_detail, th.building_detail_width)
	if th.building_glow.a > 0.0:
		_closed_line(ci, poly, th.building_glow, th.building_glow_width)
	_closed_line(ci, poly, th.building_outline, th.building_outline_width)


## Debug aid: a lot's outline and its entrance strips.
static func draw_lot_debug(ci: CanvasItem, th: VisualTheme, s: LotShape, xf: Transform2D) -> void:
	_closed_line(ci, xf * s.outline, th.lot_debug, 1.0)
	for d in s.doors:
		ci.draw_colored_polygon(xf * d, th.lot_debug)


static func draw_lot_hover(ci: CanvasItem, th: VisualTheme, outline: PackedVector2Array) -> void:
	_closed_line(ci, outline, th.hover, 2.0)


# --- City layer: DEBUG_SHAPES ---------------------------------------------------

static func draw_road_flat(ci: CanvasItem, th: VisualTheme, r: Rect2, marking: int, crossing: bool) -> void:
	if crossing:
		ci.draw_rect(r, th.intersection)
		return
	ci.draw_rect(r, th.road)
	var c := r.get_center()
	var w := maxf(1.0, r.size.x * th.road_marking_ratio)
	if marking == Marking.ALONG_X:
		ci.draw_line(c - Vector2(r.size.x * 0.22, 0), c + Vector2(r.size.x * 0.22, 0), th.road_marking, w)
	elif marking == Marking.ALONG_Y:
		ci.draw_line(c - Vector2(0, r.size.y * 0.22), c + Vector2(0, r.size.y * 0.22), th.road_marking, w)


static func draw_building_flat(ci: CanvasItem, th: VisualTheme, r: Rect2, variant: int) -> void:
	var body := r.grow(-maxf(1.0, r.size.x * 0.06))
	ci.draw_rect(body, th.building_fill(variant))
	ci.draw_rect(body.grow(-r.size.x * 0.2), th.building_roof)


static func draw_park_flat(ci: CanvasItem, th: VisualTheme, r: Rect2) -> void:
	ci.draw_rect(r.grow(-maxf(1.0, r.size.x * 0.06)), th.park_fill)
	ci.draw_circle(r.get_center(), r.size.x * 0.26, th.park_tree)


# --- Overlays (both styles) ------------------------------------------------------

## Highlight for a building designated SAFE_ZONE. `outline` and `doors` are in
## screen space (empty `outline`: frame `bounds` instead, as the flat style
## does). `emphasis` 0..1 strengthens the pulse while a route is being planned
## (0.5) or already ends inside this building (1).
static func draw_safe_zone(ci: CanvasItem, th: VisualTheme, font: Font, outline: PackedVector2Array,
		doors: Array[PackedVector2Array], bounds: Rect2, ts: float, pulse: float, emphasis: float) -> void:
	if th.style == VisualTheme.Style.DEBUG_SHAPES or outline.is_empty():
		ci.draw_rect(bounds.grow(-2.0), th.safe_outline, false, 3.0)
		_safe_badge(ci, th, font, bounds, ts, false)
		return
	var lift := emphasis * pulse
	_closed_line(ci, outline, Color(th.safe_glow, th.safe_glow.a * (0.6 + 0.8 * lift)), th.safe_glow_width * (1.0 + 0.4 * lift))
	ci.draw_colored_polygon(outline, Color(th.safe_fill, th.safe_fill.a * (1.0 + lift)))
	for d in doors:
		ci.draw_colored_polygon(d, th.safe_outline)
	_closed_line(ci, outline, th.safe_outline, th.safe_outline_width)
	_safe_badge(ci, th, font, bounds, ts, true)


## Cross and label in the middle of a safe zone. `outlined` rims them in the
## dark outline colour so they read over rooftop detail without hiding it.
static func _safe_badge(ci: CanvasItem, th: VisualTheme, font: Font, r: Rect2, ts: float, outlined: bool) -> void:
	var c := r.get_center()
	var arm := minf(r.size.x, r.size.y) * (0.15 if outlined else 0.18)
	var thick := maxf(3.0, arm * 0.45)
	var fs := int(clampf(ts * 0.5, 10, 18))
	var bar_h := Rect2(c.x - arm, c.y - thick * 0.5 - arm * 0.35, arm * 2.0, thick)
	var bar_v := Rect2(c.x - thick * 0.5, c.y - arm - arm * 0.35, thick, arm * 2.0)
	var text_c := c + Vector2(0, arm * 1.15 + (2.0 if outlined else 0.0))
	if outlined:
		ci.draw_rect(bar_h.grow(1.5), th.outline)
		ci.draw_rect(bar_v.grow(1.5), th.outline)
		var w := font.get_string_size(th.safe_label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := Vector2(text_c.x - w * 0.5, text_c.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
		ci.draw_string_outline(font, base, th.safe_label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, th.outline)
	ci.draw_rect(bar_h, th.safe_label)
	ci.draw_rect(bar_v, th.safe_label)
	draw_text_centered(ci, font, text_c, th.safe_label_text, fs, th.safe_label)


static func draw_smoke(ci: CanvasItem, th: VisualTheme, r: Rect2) -> void:
	ci.draw_rect(r, th.smoke)
	_hatch(ci, r, th.smoke_line, maxf(1.0, r.size.x * 0.06))


static func draw_fire(ci: CanvasItem, th: VisualTheme, r: Rect2, time: float) -> void:
	var c := r.get_center()
	if th.fire_glow.a > 0.0:
		var g := 0.5 + 0.5 * sin(time * 6.0 + r.position.x * 0.1)
		ci.draw_circle(c, r.size.x * (0.74 + 0.08 * g), Color(th.fire_glow, th.fire_glow.a * 0.45))
		ci.draw_circle(c, r.size.x * 0.6, th.fire_glow)
	var body := r.grow(-1.0)
	if th.fire_texture != null:
		ci.draw_texture_rect(th.fire_texture, body, false)
	else:
		ci.draw_rect(body, th.fire)
	var x := body.grow(-r.size.x * 0.12)
	var w := maxf(2.0, r.size.x * 0.08)
	ci.draw_line(x.position, x.end, th.outline, w, true)
	ci.draw_line(Vector2(x.end.x, x.position.y), Vector2(x.position.x, x.end.y), th.outline, w, true)
	if th.fire_texture == null:
		var flick := 1.0 + 0.12 * sin(time * 13.0 + r.position.x)
		var s := r.size.x * 0.24 * flick
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.2), c + Vector2(s * 0.8, s * 0.7), c + Vector2(-s * 0.8, s * 0.7)]), th.fire_core)


static func draw_survivor(ci: CanvasItem, th: VisualTheme, font: Font, c: Vector2, rad: float, label: String, count: int, fill: Color) -> void:
	ci.draw_circle(c, rad + 2.0, th.outline)
	if th.survivor_texture != null:
		var tint := Color.WHITE if fill == th.survivor else fill.lightened(0.3)
		ci.draw_texture_rect(th.survivor_texture, Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false, tint)
	else:
		ci.draw_circle(c, rad, fill)
	draw_text_centered(ci, font, c, label, int(maxf(9.0, rad * 1.1)), th.outline)
	if count >= 0:
		var bc := c + Vector2(rad * 0.9, -rad * 0.9)
		var br := maxf(6.0, rad * 0.5)
		ci.draw_circle(bc, br, th.outline)
		draw_text_centered(ci, font, bc, str(count), int(maxf(8.0, br * 1.3)), th.badge_text)


static func draw_text_centered(ci: CanvasItem, font: Font, center: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var asc := font.get_ascent(font_size)
	var desc := font.get_descent(font_size)
	ci.draw_string(font, Vector2(center.x - w * 0.5, center.y + (asc - desc) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# --- Legend ---------------------------------------------------------------------

## Legend icon for `kind`, drawn with the same painters as the map.
static func draw_legend_symbol(ci: CanvasItem, th: VisualTheme, kind: String, r: Rect2, font: Font) -> void:
	var flat := th.style == VisualTheme.Style.DEBUG_SHAPES
	var xf := Transform2D(Vector2(r.size.x, 0), Vector2(0, r.size.y), r.position)
	match kind:
		"road":
			_legend_road(ci, th, r)
		"building", "park", "safe":
			var b := CityBuilding.new()
			b.kind = CityBuilding.Kind.PARK if kind == "park" else CityBuilding.Kind.BUILDING
			b.cells.append(Vector2i.ZERO)
			b.bounds = Rect2i(0, 0, 1, 1)
			if flat:
				if kind == "park":
					draw_park_flat(ci, th, r)
				elif kind == "building":
					draw_building_flat(ci, th, r, 1)
				else:
					ci.draw_rect(r, th.safe_tile)
					ci.draw_rect(r.grow(-1.0), th.safe_outline, false, 2.0)
					draw_text_centered(ci, font, r.get_center(), "+", int(r.size.y * 0.8), th.safe_label)
				return
			var s := LotShape.new()
			s.outline = _rect_poly(Rect2(0.12, 0.12, 0.76, 0.76))
			if b.kind == CityBuilding.Kind.PARK:
				_park_details(s, b)
			else:
				_roof_details(s, b, Rect2(0.12, 0.12, 0.76, 0.76))
			ci.draw_rect(r, th.block_ground)
			draw_lot(ci, th, b, s, xf, r.size.x)
			if kind == "safe":
				var poly := xf * s.outline
				_closed_line(ci, poly, th.safe_glow, 4.0)
				ci.draw_colored_polygon(poly, th.safe_fill)
				_closed_line(ci, poly, th.safe_outline, 2.0)
		"closed":
			if flat:
				draw_building_flat(ci, th, r, 0)
			else:
				draw_closed_road(ci, th, r, 2 | 8, 1 | 4)
		"survivor":
			draw_survivor(ci, th, font, r.get_center(), r.size.x * 0.38, "A", -1, th.survivor)
		"route":
			_legend_road(ci, th, r)
			ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), th.outline, 7.0)
			ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), th.route, 5.0)
		"bad":
			_legend_road(ci, th, r)
			ci.draw_line(Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y), th.route_bad, 5.0)
			var x := r.grow(-r.size.x * 0.2)
			ci.draw_line(x.position, x.end, th.route_bad, 2.0, true)
			ci.draw_line(Vector2(x.end.x, x.position.y), Vector2(x.position.x, x.end.y), th.route_bad, 2.0, true)
		"fire":
			draw_fire(ci, th, r, 0.0)
		"smoke":
			_legend_road(ci, th, r)
			draw_smoke(ci, th, r)


static func _legend_road(ci: CanvasItem, th: VisualTheme, r: Rect2) -> void:
	if th.style == VisualTheme.Style.DEBUG_SHAPES:
		draw_road_flat(ci, th, r, Marking.ALONG_X, false)
	else:
		draw_road(ci, th, r, CityMap.RoadClass.STREET, 1 | 4, Marking.ALONG_X, 0)


# --- Helpers --------------------------------------------------------------------

static func _fill(ci: CanvasItem, poly: PackedVector2Array, color: Color, uvs: PackedVector2Array, tex: Texture2D) -> void:
	if tex != null:
		ci.draw_colored_polygon(poly, Color.WHITE, uvs, tex)
	else:
		ci.draw_colored_polygon(poly, color)


## Closed outline. It starts and ends halfway along the first edge so thick
## lines have no notch at a corner.
static func _closed_line(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var mid := (pts[0] + pts[1]) * 0.5
	var loop := PackedVector2Array([mid])
	loop.append_array(pts.slice(1))
	loop.append(pts[0])
	loop.append(mid)
	ci.draw_polyline(loop, color, width, true)


## Lines along the tile sides in `mask`, kept just inside the tile.
static func _draw_sides(ci: CanvasItem, r: Rect2, mask: int, color: Color, width: float) -> void:
	if mask == 0:
		return
	for k in 4:
		if mask & (1 << k):
			var inward: Vector2 = INWARD[k] * (width * 0.5)
			ci.draw_line(r.position + Vector2(CORNERS[k]) * r.size + inward,
					r.position + Vector2(CORNERS[(k + 1) % 4]) * r.size + inward, color, width)


## Diagonal hatching from the bottom-left to the top-right of `r`.
static func _hatch(ci: CanvasItem, r: Rect2, color: Color, width: float) -> void:
	for k in [0.33, 0.66, 1.0]:
		ci.draw_line(r.position + Vector2(0, r.size.y * k), r.position + Vector2(r.size.x * k, 0), color, width, true)
	for k in [0.33, 0.66]:
		ci.draw_line(r.position + Vector2(r.size.x * k, r.size.y), r.position + Vector2(r.size.x, r.size.y * k), color, width, true)
