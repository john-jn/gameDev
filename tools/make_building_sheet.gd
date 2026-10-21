extends SceneTree
## Renders the modular building and road templates plus the spec sheet that
## explains them:
##   art_and_sound_pack/templates/building_autotile_template.png   512x640, transparent
##   art_and_sound_pack/templates/road_autotile_template.png       512x512
##   art_and_sound_pack/building_sheet_spec.png                    spec for the art team
## godot --path . --script res://tools/make_building_sheet.gd   (needs a window)

const D := preload("res://tools/sheet_draw.gd")
const BG := Color("0a0f1a")
const CARD := Color("141c2b")
const EDGE := Color("3a475c")
const TXT := Color("d7e1f0")
const DIM := Color("7f8ea8")
const ACCENT := Color("38c6f4")
const GOOD := Color("39d98a")

const MASK_NAMES := ["0 single", "1 N", "2 E", "3 N+E", "4 S", "5 N+S", "6 E+S", "7 N+E+S",
		"8 W", "9 N+W", "10 E+W", "11 N+E+W", "12 S+W", "13 N+S+W", "14 E+S+W", "15 interior"]
const NOTCH_NAMES := ["IC top-left", "IC top-right", "IC bottom-right", "IC bottom-left"]

var font: Font
var frames := 0
var views: Array = []  ## [SubViewport, path]


class Template extends Control:
	var kind := "building"
	var f: Font

	func _init(p_kind: String, p_font: Font, sz: Vector2) -> void:
		kind = p_kind
		f = p_font
		size = sz

	func _draw() -> void:
		if kind == "road":
			for m in 16:
				var r := Rect2(Vector2(m % 4, m / 4) * 128.0, Vector2(128, 128))
				D.road_piece(self, r, m)
				draw_string(f, r.position + Vector2(6, 18), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
			return
		for m in 16:
			var r := Rect2(Vector2(m % 4, m / 4) * 128.0, Vector2(128, 128))
			D.piece(self, r, m, 0, false)
			draw_string(f, r.position + Vector2(6, 18), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
		for i in 4:
			var r := Rect2(Vector2(i, 4) * 128.0, Vector2(128, 128))
			D.piece(self, r, 15, 1 << i, false)
			draw_string(f, r.position + Vector2(6, 18), "IC%d" % i, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))


class Spec extends Control:
	var f: Font
	var fm: Font

	func _init(p_f: Font, p_fm: Font, sz: Vector2) -> void:
		f = p_f
		fm = p_fm
		size = sz

	func _t(pos: Vector2, text: String, fs: int, col: Color, bold := false) -> void:
		draw_string(f if bold else fm, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _head(pos: Vector2, num: String, text: String) -> void:
		draw_rect(Rect2(pos + Vector2(0, -22), Vector2(30, 30)), ACCENT)
		_t(pos + Vector2(9, 1), num, 20, BG, true)
		_t(pos + Vector2(40, 1), text, 22, TXT, true)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		_t(Vector2(30, 52), "EVAC GRID  -  BUILDING & ROAD SPRITE SHEET SPEC", 36, ACCENT, true)
		_t(Vector2(30, 82), "Buildings are built from connecting 128 px cells, so ONE set of 20 pieces covers every lot shape in the game (1x1 up to 3x3, plus L shapes).", 16, DIM)

		# 1. Building autotile sheet
		_head(Vector2(30, 140), "1", "BUILDING SHEET  (one PNG per style, 512 x 640 px)")
		var o := Vector2(30, 165)
		var ts := 128.0
		for m in 16:
			var r := Rect2(o + Vector2(m % 4, m / 4) * (ts + 10), Vector2(ts, ts))
			D.piece(self, r, m, 0, true)
			_t(r.position + Vector2(6, 18), MASK_NAMES[m], 14, Color.WHITE)
		for i in 4:
			var r2 := Rect2(o + Vector2(i, 4) * (ts + 10), Vector2(ts, ts))
			D.piece(self, r2, 15, 1 << i, true)
			_t(r2.position + Vector2(6, 18), NOTCH_NAMES[i], 14, Color.WHITE)
		_t(o + Vector2(0, 5 * (ts + 10) + 6), "Orange ticks = seamless connection point. Rim = outer wall.", 13, DIM)
		_t(o + Vector2(0, 5 * (ts + 10) + 24), "Order: left to right, top to bottom, mask 0-15, then 4 inner corners.", 13, DIM)

		# 2. How pieces assemble
		var ax := 650.0
		_head(Vector2(ax, 140), "2", "HOW PIECES BUILD A LOT  (the numbers are the piece used)")
		var shapes := [
			["1x1  (mask 0)", [Vector2i(0, 0)]],
			["2x1", [Vector2i(0, 0), Vector2i(1, 0)]],
			["1x3", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]],
			["2x2", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]],
			["3x2", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]],
			["3x3  (centre = 15)", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]],
			["L shape  (IC piece)", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]],
			["L shape, 5 cells", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]],
		]
		var pos := [Vector2(ax, 200), Vector2(ax + 120, 200), Vector2(ax + 290, 200), Vector2(ax + 400, 200),
				Vector2(ax, 400), Vector2(ax + 290, 400), Vector2(ax, 690), Vector2(ax + 200, 690)]
		var cs := 64.0
		for i in 8:
			var sh: Array = shapes[i][1]
			D.lot(self, sh, pos[i], cs, false, fm)
			_t(pos[i] + Vector2(0, -8), shapes[i][0], 14, TXT, true)
		_t(Vector2(ax, 845), "Any footprint: look at each cell's 4 neighbours and add N=1 E=2 S=4 W=8 for the sides that belong to the same lot.", 13, DIM)
		_t(Vector2(ax, 863), "If a diagonal cell is missing but both side neighbours exist, also draw the inner-corner (IC) overlay in that corner.", 13, DIM)

		# 3. Rules
		var rx := 1260.0
		_head(Vector2(rx, 140), "3", "RULES FOR THE ARTISTS")
		var rules := "- Cell = 128 x 128 px. Top-down, flat, no perspective. Light from top-left.\n" \
				+ "- mask = N(1) + E(2) + S(4) + W(8), where a side counts only if the next cell is the SAME lot.\n" \
				+ "- Connected sides: paint right to the cell edge, NO rim and NO shadow, so cells join invisibly. Test by tiling a piece against itself.\n" \
				+ "- Outer sides: leave a 14 px transparent margin (setback from the road), then an 8 px wall / parapet rim.\n" \
				+ "- Inner-corner pieces (IC) are the interior piece with one 14 px notch cut from that corner.\n" \
				+ "- Interior pieces (15) must tile in any combination, so no big unique details. Use roof props instead.\n" \
				+ "- Rotation: the game turns lots so the front faces its street, so bake lighting flat.\n" \
				+ "- PNG, transparent background, sRGB. Keep the dark teal / cyan palette of the reference map.\n" \
				+ "- File names: building_style0.png to building_style4.png, plus the extra sprites below."
		draw_multiline_string(fm, Vector2(rx, 175), rules, HORIZONTAL_ALIGNMENT_LEFT, 700, 15, -1, TXT)

		# 4. Styles
		var sy := 560.0
		_head(Vector2(rx, sy), "4", "5 BUILDING STYLES  (matches the game's 5 variants)")
		var styles := ["style0   Flat roof with parapet", "style1   Ribbed / corrugated roof", "style2   Roof with plant units along the back wall",
				"style3   Courtyard block (big lots look open in the middle)", "style4   Stepped tower"]
		for i in styles.size():
			_t(Vector2(rx, sy + 38 + i * 26), styles[i], 16, TXT)
		_t(Vector2(rx, sy + 180), "Each style = 1 sheet of 20 pieces.  5 styles = 100 pieces.", 15, GOOD, true)

		# 5. Extra sprites
		var ey := 930.0
		_head(Vector2(30, ey), "5", "EXTRA SPRITES  (separate transparent PNGs)")
		var extras := [
			["Door overlay", "128 x 32", "front of lot, faces south"],
			["Roof props x6", "64 x 64 each", "vent, AC unit, tank, skylight, antenna, solar"],
			["Safe zone set", "512 x 640 sheet", "same layout, green cross + helipad overlay 384 x 384"],
			["Park set", "512 x 640 sheet", "same layout, grass + paths"],
			["Trees x3", "64 x 64 each", "round, pine, bush, scattered on parks"],
			["Smoke", "128 x 128", "soft overlay, 2 to 3 variants"],
			["Fire", "128 x 128, 4 frames", "flicker loop"],
			["Closed road barrier", "128 x 128", "rubble or striped barrier"],
		]
		for i in extras.size():
			var r3 := Rect2(Vector2(30 + (i % 4) * 300, ey + 20 + (i / 4) * 92), Vector2(285, 80))
			draw_rect(r3, CARD)
			draw_rect(r3, EDGE, false, 2.0)
			_t(r3.position + Vector2(10, 24), extras[i][0], 17, TXT, true)
			_t(r3.position + Vector2(10, 44), extras[i][1], 14, ACCENT)
			draw_multiline_string(fm, r3.position + Vector2(10, 62), extras[i][2], HORIZONTAL_ALIGNMENT_LEFT, 268, 12, 2, DIM)

		# 6. Road sheet
		_head(Vector2(rx, 880), "6", "ROAD SHEET  (512 x 512, mask = road neighbours)")
		for m in 16:
			var r4 := Rect2(Vector2(rx, 905) + Vector2(m % 4, m / 4) * 78.0, Vector2(72, 72))
			D.road_piece(self, r4, m)
			_t(r4.position + Vector2(4, 14), str(m), 11, Color.WHITE)
		draw_multiline_string(fm, Vector2(rx + 340, 925), "2 sheets of 16 pieces: street and avenue (2-lane).\nA side with no road next to it gets a curb line.\nCentre dashes lead toward the connected sides.\nNames: road_street.png, road_avenue.png", HORIZONTAL_ALIGNMENT_LEFT, 380, 14, -1, TXT)

		_t(Vector2(30, 1190), "Developers: the game currently stretches ONE texture over a whole lot (building_textures in visual_theme.gd). Per-cell pieces need a small change in MapPainter.draw_lot.", 14, Color("ffb020"))
		_t(Vector2(30, 1214), "Paint-over templates: art_and_sound_pack/templates/building_autotile_template.png and road_autotile_template.png.", 14, DIM)


func _initialize() -> void:
	font = load("res://assets/fonts/Rajdhani-Bold.ttf") as Font
	var med := load("res://assets/fonts/Rajdhani-Medium.ttf") as Font
	_add_view(Template.new("building", med, Vector2(512, 640)), Vector2i(512, 640), "res://art_and_sound_pack/templates/building_autotile_template.png", true)
	_add_view(Template.new("road", med, Vector2(512, 512)), Vector2i(512, 512), "res://art_and_sound_pack/templates/road_autotile_template.png", false)
	_add_view(Spec.new(font, med, Vector2(2000, 1240)), Vector2i(2000, 1240), "res://art_and_sound_pack/building_sheet_spec.png", false)


func _add_view(ctl: Control, sz: Vector2i, path: String, transparent: bool) -> void:
	var svp := SubViewport.new()
	svp.size = sz
	svp.transparent_bg = transparent
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)
	svp.add_child(ctl)
	views.append([svp, path])


func _process(_d: float) -> bool:
	frames += 1
	if frames == 10:
		for v in views:
			(v[0] as SubViewport).get_texture().get_image().save_png(v[1])
	if frames > 12:
		quit()
	return false
