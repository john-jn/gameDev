extends RefCounted
## Drawing helpers shared by make_building_sheet.gd: building and road autotile pieces.

const PALETTE := preload("res://scripts/ui_palette.gd")
const FILL := PALETTE.TEAL
const RIM := Color(PALETTE.MINT, 0.9)
const ROAD := PALETTE.BG_DARK
const DASH := Color(PALETTE.TEAL_MID, 0.8)
const TICK := PALETTE.MINT
const N := 1
const E := 2
const S := 4
const W := 8


static func piece(ci: CanvasItem, r: Rect2, mask: int, notch: int, ticks: bool) -> void:
	var k := r.size.x / 128.0
	var m := 14.0 * k
	var rim := 8.0 * k
	var x0 := r.position.x + (0.0 if mask & W else m)
	var x1 := r.end.x - (0.0 if mask & E else m)
	var y0 := r.position.y + (0.0 if mask & N else m)
	var y1 := r.end.y - (0.0 if mask & S else m)
	var pts := PackedVector2Array()
	if notch & 1:
		pts.append_array([Vector2(x0, y0 + m), Vector2(x0 + m, y0 + m), Vector2(x0 + m, y0)])
	else:
		pts.append(Vector2(x0, y0))
	if notch & 2:
		pts.append_array([Vector2(x1 - m, y0), Vector2(x1 - m, y0 + m), Vector2(x1, y0 + m)])
	else:
		pts.append(Vector2(x1, y0))
	if notch & 4:
		pts.append_array([Vector2(x1, y1 - m), Vector2(x1 - m, y1 - m), Vector2(x1 - m, y1)])
	else:
		pts.append(Vector2(x1, y1))
	if notch & 8:
		pts.append_array([Vector2(x0 + m, y1), Vector2(x0 + m, y1 - m), Vector2(x0, y1 - m)])
	else:
		pts.append(Vector2(x0, y1))
	ci.draw_colored_polygon(pts, FILL)
	var rim_c := Color(RIM, 0.28)
	if not mask & N:
		ci.draw_rect(Rect2(x0, y0, x1 - x0, rim), rim_c)
		ci.draw_line(Vector2(x0, y0), Vector2(x1, y0), RIM, 2.0 * k)
	if not mask & S:
		ci.draw_rect(Rect2(x0, y1 - rim, x1 - x0, rim), rim_c)
		ci.draw_line(Vector2(x0, y1), Vector2(x1, y1), RIM, 2.0 * k)
	if not mask & W:
		ci.draw_rect(Rect2(x0, y0, rim, y1 - y0), rim_c)
		ci.draw_line(Vector2(x0, y0), Vector2(x0, y1), RIM, 2.0 * k)
	if not mask & E:
		ci.draw_rect(Rect2(x1 - rim, y0, rim, y1 - y0), rim_c)
		ci.draw_line(Vector2(x1, y0), Vector2(x1, y1), RIM, 2.0 * k)
	var corners: Array[Vector2] = [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	for i in 4:
		if notch & (1 << i):
			var a := corners[i]
			var sx := 1.0 if i == 0 or i == 3 else -1.0
			var sy := 1.0 if i == 0 or i == 1 else -1.0
			ci.draw_polyline(PackedVector2Array([a + Vector2(0, sy * m), a + Vector2(sx * m, sy * m), a + Vector2(sx * m, 0)]), RIM, 2.0 * k)
	if ticks:
		var c := r.get_center()
		var t := 18.0 * k
		if mask & N:
			ci.draw_line(Vector2(c.x - t, r.position.y), Vector2(c.x + t, r.position.y), TICK, 4.0 * k)
		if mask & S:
			ci.draw_line(Vector2(c.x - t, r.end.y), Vector2(c.x + t, r.end.y), TICK, 4.0 * k)
		if mask & W:
			ci.draw_line(Vector2(r.position.x, c.y - t), Vector2(r.position.x, c.y + t), TICK, 4.0 * k)
		if mask & E:
			ci.draw_line(Vector2(r.end.x, c.y - t), Vector2(r.end.x, c.y + t), TICK, 4.0 * k)


static func road_piece(ci: CanvasItem, r: Rect2, mask: int) -> void:
	var k := r.size.x / 128.0
	ci.draw_rect(r, ROAD)
	var edge := Color(RIM, 0.55)
	if not mask & N:
		ci.draw_line(r.position, Vector2(r.end.x, r.position.y), edge, 4.0 * k)
	if not mask & S:
		ci.draw_line(Vector2(r.position.x, r.end.y), r.end, edge, 4.0 * k)
	if not mask & W:
		ci.draw_line(r.position, Vector2(r.position.x, r.end.y), edge, 4.0 * k)
	if not mask & E:
		ci.draw_line(Vector2(r.end.x, r.position.y), r.end, edge, 4.0 * k)
	var c := r.get_center()
	var dirs := {N: Vector2(0, -1), E: Vector2(1, 0), S: Vector2(0, 1), W: Vector2(-1, 0)}
	for b in dirs:
		if mask & b:
			ci.draw_line(c, c + dirs[b] * r.size.x * 0.5, DASH, 4.0 * k)
	if mask == 0:
		ci.draw_circle(c, 6.0 * k, DASH)


## Draws a lot built from cells, picking each cell's piece from its neighbours.
static func lot(ci: CanvasItem, cells: Array, origin: Vector2, ts: float, ticks: bool, f: Font) -> void:
	var has := {}
	for c in cells:
		has[c] = true
	for c: Vector2i in cells:
		var mask := 0
		mask |= N if has.has(c + Vector2i(0, -1)) else 0
		mask |= E if has.has(c + Vector2i(1, 0)) else 0
		mask |= S if has.has(c + Vector2i(0, 1)) else 0
		mask |= W if has.has(c + Vector2i(-1, 0)) else 0
		var notch := 0
		if mask & N and mask & W and not has.has(c + Vector2i(-1, -1)):
			notch |= 1
		if mask & N and mask & E and not has.has(c + Vector2i(1, -1)):
			notch |= 2
		if mask & S and mask & E and not has.has(c + Vector2i(1, 1)):
			notch |= 4
		if mask & S and mask & W and not has.has(c + Vector2i(-1, 1)):
			notch |= 8
		var r := Rect2(origin + Vector2(c) * ts, Vector2(ts, ts))
		piece(ci, r, mask, notch, ticks)
		var lbl := str(mask) + ("+IC" if notch != 0 else "")
		ci.draw_string(f, r.position + Vector2(5, 15), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(PALETTE.WHITE, 0.85))
