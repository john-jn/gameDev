extends SceneTree
## Renders art_and_sound_pack/asset_sheet.png: every art and UI asset the team needs, with the
## current code-drawn placeholder shown where one exists.
## godot --path . --script res://tools/make_asset_sheet.gd   (needs a window, so not --headless)

const BG := Color("0a0f1a")
const CARD := Color("141c2b")
const EDGE := Color("3a475c")
const TXT := Color("d7e1f0")
const DIM := Color("7f8ea8")
const ACCENT := Color("38c6f4")
const NEED := Color("ffb020")
const OK := Color("39d98a")

# [group, title, size, status, preview kind or "", note]
const ITEMS := [
	["MAP", "Buildings: 5 styles", "20 pieces each, 512x640", "TEMP", "building", "connecting autotile, see spec"],
	["MAP", "Park", "256x256", "TEMP", "park", "grass, trees, path"],
	["MAP", "Survivor marker", "128x128", "TEMP", "survivor", "people / yellow pin"],
	["MAP", "Fire", "128x128 or 4-6 frames", "TEMP", "fire", "flickering flames"],
	["MAP", "Smoke", "128x128", "TEMP", "smoke", "soft grey overlay"],
	["MAP", "Roads: street + avenue", "16 pieces each, 512x512", "TEMP", "road", "connecting autotile, see spec"],
	["MAP", "Closed road", "128x128", "TEMP", "closed", "barrier / rubble"],
	["MAP", "Safe zone", "384x384 (3x3)", "TEMP", "safe", "shelter, green cross"],
	["MAP", "Route arrow", "64x64", "TEMP", "route", "optional"],
	["UI", "Tablet frame", "1280x800", "TEMP", "", "9-slice, optional"],
	["UI", "Logo EVAC GRID", "512x128", "NEW", "", "title + top bar"],
	["UI", "App icon", "256x256", "TEMP", "", "still Godot default"],
	["UI", "Buttons x4 states", "9-slice", "TEMP", "", "normal/hover/press/off"],
	["UI", "Status lights", "32x32 x5", "TEMP", "", "on/off, 5 colours"],
	["UI", "Star icons", "64x64 x2", "TEMP", "", "results rating"],
	["UI", "Legend icons", "32x32", "TEMP", "", "fire, smoke, road, team"],
	["UI", "Title background", "1280x800", "NEW", "", "no title screen yet"],
	["UI", "Alert icon", "64x64", "NEW", "", "warning triangle"],
]

var th: VisualTheme
var font: Font
var frames := 0
var viewport: SubViewport


class Preview extends Control:
	var kind := ""
	var th: VisualTheme
	var font: Font
	func _init(p_kind: String, p_th: VisualTheme, p_font: Font) -> void:
		kind = p_kind
		th = p_th
		font = p_font
		custom_minimum_size = Vector2(300, 110)
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), th.map_bg)
		var s := 86.0
		var r := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
		if kind == "":
			var c := Color("56627a")
			draw_rect(r, Color(c, 0.12))
			for i in 4:
				var a := r.position + Vector2(0 if i % 2 == 0 else s, 0 if i < 2 else s)
				draw_line(a, a + Vector2(14 if i % 2 == 0 else -14, 0), c, 2)
				draw_line(a, a + Vector2(0, 14 if i < 2 else -14), c, 2)
			draw_string(font, r.position + Vector2(0, s * 0.58), "NO ART YET", HORIZONTAL_ALIGNMENT_CENTER, s, 12, Color("ffb020"))
			return
		MapPainter.draw_legend_symbol(self, th, kind, r, font)


func _initialize() -> void:
	var sz := Vector2i(1800, 1250)
	th = VisualTheme.dispatch_style()
	font = load("res://assets/fonts/Rajdhani-Bold.ttf") as Font
	var medium := load("res://assets/fonts/Rajdhani-Medium.ttf") as Font
	var ui := Theme.new()
	ui.default_font = medium
	ui.default_font_size = 16
	var root_ctl := Control.new()
	root_ctl.theme = ui
	root_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var svp := SubViewport.new()
	svp.size = sz
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)
	viewport = svp
	svp.add_child(root_ctl)
	root_ctl.size = Vector2(sz)
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(sz)
	root_ctl.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 28)
	root_ctl.add_child(margin)
	margin.size = Vector2(sz)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(_lbl("EVAC GRID  -  ASSET SHEET", 34, ACCENT, true))
	var intro := _lbl("Previews show today's placeholders. Replace each with PNG art (transparent, top-down, dark teal/cyan style). Slots in visual_theme.gd: building_textures, park_texture, survivor_texture, fire_texture. The rest need new slots.   TEMP = code-drawn placeholder, needs real art.   NEW = does not exist yet.", 14, DIM)
	v.add_child(intro)

	for group in ["MAP", "UI"]:
		v.add_child(_lbl("MAP ART" if group == "MAP" else "INTERFACE ART", 20, TXT, true))
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		v.add_child(grid)
		for it in ITEMS:
			if it[0] != group:
				continue
			grid.add_child(_card(it))

	v.add_child(_lbl("Fonts: Rajdhani UI font = DONE.   Digital/7-segment font for clock and score = TEMP.   Sound: see SOUND_GUIDE.md.", 15, OK))


func _card(it: Array) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(330, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 4)
	p.add_child(b)
	b.add_child(Preview.new(it[4], th, font))
	var row := HBoxContainer.new()
	b.add_child(row)
	var t := _lbl(it[1], 17, TXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var tag := _lbl(it[3], 13, NEED if it[3] == "TEMP" else Color("ff6b5c"), true)
	row.add_child(tag)
	b.add_child(_lbl(it[2], 14, ACCENT))
	b.add_child(_lbl(it[5], 13, DIM))
	return p


func _lbl(text: String, size: int, col: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _process(_d: float) -> bool:
	frames += 1
	if frames == 10:
		viewport.get_texture().get_image().save_png("res://art_and_sound_pack/asset_sheet.png")
	if frames > 12:
		quit()
	return false
