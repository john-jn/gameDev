class_name VisualTheme
extends Resource
## Every colour, line width and proportion the map renderer uses, plus
## optional art slots, in one inspector-editable resource. Gameplay never reads
## it: editing or swapping a theme can only change how the map looks.
##
## Two presets ship, both pure primitive shapes:
##   dispatch_style()  dark emergency-dispatch city map (the defaults below)
##   debug_shapes()    the flat prototype look, plus lot outlines and entrances
## To tune one in the editor: create a new VisualTheme resource (it starts as
## DISPATCH_STYLE) or save a preset with ResourceSaver, then assign the .tres
## to Main's `visual_theme_override` in scenes/main.tscn.
##
## Ratios are fractions of one tile; widths are pixels.

enum Style { DEBUG_SHAPES, DISPATCH_STYLE }

## DEBUG_SHAPES draws one flat shape per tile; DISPATCH_STYLE draws merged
## blocks, curbed roads and outlined building footprints.
@export var style := Style.DISPATCH_STYLE

@export_group("Ground")
@export var map_bg := Color("040a0c")
@export var map_frame := Color(0.31, 0.85, 0.78, 0.35)
## Surface of city blocks around and between building footprints.
@export var block_ground := Color("15383c")

@export_group("Roads")
@export var road := Color("071316")
@export var avenue := Color("0a1a1e")
## Flat style only: road tiles where three or more streets meet.
@export var intersection := Color("0a1a1e")
@export var road_edge := Color("3d8582")
@export var road_edge_width := 1.0
@export var road_marking := Color(0.5, 0.8, 0.76, 0.4)
@export var road_marking_ratio := 0.035
## Roads closed by rubble during generation (impassable).
@export var closed_road := Color("0c1416")
@export var closed_hatch := Color(0.72, 0.78, 0.76, 0.28)
@export var closed_barrier := Color(0.86, 0.9, 0.88, 0.85)

@export_group("Buildings")
## Fill per variant (wraps around).
@export var building_fills: Array[Color] = [Color("1a4146"), Color("1c464b"), Color("1f4b50")]
@export var building_outline := Color(0.38, 0.9, 0.82, 0.82)
@export var building_outline_width := 1.2
@export var building_glow := Color(0.31, 0.85, 0.78, 0.07)
@export var building_glow_width := 4.0
@export var building_detail := Color(0.38, 0.9, 0.82, 0.34)
@export var building_detail_width := 1.0
## Flat style only: the inner roof square.
@export var building_roof := Color("364258")
## Clear space between a footprint and a road (tile fraction).
@export var building_road_setback := 0.13
## Clear space between two neighbouring footprints (tile fraction).
@export var building_gap := 0.1
@export var park_fill := Color("0d2c26")
@export var park_edge := Color(0.36, 0.78, 0.58, 0.45)
@export var park_detail := Color(0.32, 0.66, 0.5, 0.5)
@export var park_tree := Color("1f4a3b")
## Outlines lots and marks their entrances on top of the city (debugging aid).
@export var show_lot_debug := false
@export var lot_debug := Color(0.85, 0.6, 1.0, 0.75)

@export_group("Safe zone")
## Purely visual: safe zones work the same with the highlight off.
@export var safe_highlight_enabled := true
@export var safe_label_text := "SAFE"
@export var safe_outline := Color("5dff9d")
@export var safe_outline_width := 2.5
@export var safe_fill := Color(0.36, 1.0, 0.62, 0.16)
@export var safe_glow := Color(0.36, 1.0, 0.62, 0.22)
@export var safe_glow_width := 9.0
## Flat style only: colour of SAFE tiles.
@export var safe_tile := Color("1d8f5c")
@export var safe_label := Color.WHITE

@export_group("Hazards")
@export var fire := Color("ff4a2a")
@export var fire_core := Color("ffd23f")
@export var fire_glow := Color(1.0, 0.36, 0.12, 0.32)
@export var smoke := Color(1.0, 0.62, 0.1, 0.4)
@export var smoke_line := Color(0.78, 0.45, 0.05, 0.85)
@export var alert := Color("ff4d3d")

@export_group("Survivors")
@export var survivor := Color("ffe066")
@export var survivor_blocked := Color("ff9f43")
@export var survivor_radius_ratio := 0.36
@export var select_ring := Color("7fe7ff")
@export var waiting_ring := Color(1, 1, 1, 0.45)
@export var badge_text := Color.WHITE

@export_group("Routes and feedback")
@export var route := Color("3cc4ff")
@export var route_bad := Color("ff3b5c")
@export var route_width_ratio := 0.26
## Groups already walking a route (dashed line).
@export var en_route := Color(1.0, 0.878, 0.4, 0.85)
@export var next_step_smoke := Color("ffb020")
@export var hover := Color(1, 1, 1, 0.6)
## Dark casing under routes and markers, and text outlines.
@export var outline := Color("02080b")

@export_group("Asset slots")
## Optional art. Leave a slot empty to draw primitive shapes. Textures are
## loaded once with the theme, never per frame. See MapPainter for where each
## slot is drawn.
## Building art per CityBuilding.variant (wraps around), stretched over the
## footprint's bounds and clipped to its outline; rotated by its rotation.
@export var building_textures: Array[Texture2D] = []
@export var park_texture: Texture2D
@export var survivor_texture: Texture2D
@export var fire_texture: Texture2D


static func dispatch_style() -> VisualTheme:
	return VisualTheme.new()


## The original prototype palette (flat light roads, per-tile buildings).
static func debug_shapes() -> VisualTheme:
	var t := VisualTheme.new()
	t.style = Style.DEBUG_SHAPES
	t.map_bg = Color("0a1019")
	t.map_frame = Color(0.153, 0.769, 0.961, 0.3)
	t.block_ground = Color("0a1019")
	t.road = Color("b9c4d2")
	t.avenue = Color("b9c4d2")
	t.intersection = Color("cdd6e2")
	t.road_marking = Color("7d8a9c")
	t.road_marking_ratio = 0.06
	t.building_fills = [Color("27303e"), Color("2b3545"), Color("2f394a")]
	t.building_road_setback = 0.08
	t.building_gap = 0.08
	t.park_fill = Color("1f3a2b")
	t.park_tree = Color("2f5e40")
	t.show_lot_debug = true
	t.safe_outline = Color("5ff2ad")
	t.safe_tile = Color("1d8f5c")
	t.fire = Color("e2412a")
	t.fire_glow = Color(0, 0, 0, 0)
	t.smoke = Color(1.0, 0.62, 0.1, 0.5)
	t.smoke_line = Color("8a4a00")
	t.select_ring = Color("27c4f5")
	t.route = Color("1fb8f0")
	t.hover = Color(1, 1, 1, 0.55)
	t.outline = Color("08101c")
	return t


static func for_style(s: Style) -> VisualTheme:
	return debug_shapes() if s == Style.DEBUG_SHAPES else dispatch_style()


func building_fill(variant: int) -> Color:
	if building_fills.is_empty():
		return Color.DIM_GRAY
	return building_fills[posmod(variant, building_fills.size())]


func building_texture(variant: int) -> Texture2D:
	if building_textures.is_empty():
		return null
	return building_textures[posmod(variant, building_textures.size())]
