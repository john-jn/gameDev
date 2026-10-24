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
@export var map_bg := UiPalette.BG_DARK
@export var map_frame := Color(UiPalette.MINT, 0.35)
## Surface of city blocks around and between building footprints.
@export var block_ground := UiPalette.PANEL

@export_group("Roads")
@export var road := UiPalette.BG_DARK
@export var avenue := UiPalette.TEAL
## Flat style only: road tiles where three or more streets meet.
@export var intersection := UiPalette.TEAL
@export var road_edge := UiPalette.TEAL_MID
@export var road_edge_width := 1.0
@export var road_marking := Color(UiPalette.MINT, 0.4)
@export var road_marking_ratio := 0.035
## Roads closed by rubble during generation (impassable).
@export var closed_road := UiPalette.TEAL
@export var closed_hatch := Color(UiPalette.TEAL_MID, 0.28)
@export var closed_barrier := Color(UiPalette.MINT, 0.85)

@export_group("Buildings")
## Fill per variant (wraps around).
@export var building_fills: Array[Color] = [UiPalette.TEAL, UiPalette.PANEL, UiPalette.TEAL_MID]
@export var building_outline := Color(UiPalette.MINT, 0.82)
@export var building_outline_width := 1.2
@export var building_glow := Color(UiPalette.MINT, 0.07)
@export var building_glow_width := 4.0
@export var building_detail := Color(UiPalette.MINT, 0.34)
@export var building_detail_width := 1.0
## Flat style only: the inner roof square.
@export var building_roof := UiPalette.TEAL_MID
## Clear space between a footprint and a road (tile fraction).
@export var building_road_setback := 0.13
## Clear space between two neighbouring footprints (tile fraction).
@export var building_gap := 0.1
@export var park_fill := UiPalette.PANEL
@export var park_edge := Color(UiPalette.GREEN, 0.45)
@export var park_detail := Color(UiPalette.MINT, 0.5)
@export var park_tree := UiPalette.TEAL
## Outlines lots and marks their entrances on top of the city (debugging aid).
@export var show_lot_debug := false
@export var lot_debug := Color(UiPalette.CYAN, 0.75)

@export_group("Safe zone")
## Purely visual: safe zones work the same with the highlight off.
@export var safe_highlight_enabled := true
@export var safe_label_text := "SAFE"
@export var safe_outline := UiPalette.GREEN
@export var safe_outline_width := 2.5
@export var safe_fill := Color(UiPalette.GREEN, 0.16)
@export var safe_glow := Color(UiPalette.GREEN, 0.22)
@export var safe_glow_width := 9.0
## Flat style only: colour of SAFE tiles.
@export var safe_tile := UiPalette.TEAL_MID
@export var safe_label := UiPalette.WHITE

@export_group("Hazards")
@export var fire := UiPalette.ALERT
@export var fire_core := UiPalette.MINT
@export var fire_glow := Color(UiPalette.ALERT, 0.32)
@export var smoke := Color(UiPalette.WARNING, 0.4)
@export var smoke_line := Color(UiPalette.WARNING, 0.85)
## Smoldering tiles (about to ignite): pulsing ember overlay.
@export var ember := Color(UiPalette.DANGER, 0.55)
@export var ember_core := UiPalette.WARNING
@export var alert := UiPalette.ALERT
## Ring around a group losing people to smoke while it stands still.
@export var smoke_drain_ring := UiPalette.WARNING

@export_group("Survivors")
@export var survivor := UiPalette.GREEN
@export var survivor_blocked := UiPalette.ALERT
@export var survivor_radius_ratio := 0.36
@export var select_ring := UiPalette.MINT
@export var waiting_ring := Color(UiPalette.WHITE, 0.45)
@export var badge_text := UiPalette.WHITE

@export_group("Routes and feedback")
@export var route := UiPalette.CYAN
@export var route_bad := UiPalette.ALERT
@export var route_width_ratio := 0.26
## Groups already walking a route (dashed line).
@export var en_route := Color(UiPalette.MINT, 0.85)
@export var next_step_smoke := UiPalette.CYAN
@export var hover := Color(UiPalette.WHITE, 0.6)
## Dark casing under routes and markers, and text outlines.
@export var outline := UiPalette.BG_DARK

@export_group("Asset slots")
## Optional art. Leave a slot empty to draw primitive shapes. Textures are
## loaded once with the theme, never per frame. See MapPainter for where each
## slot is drawn.
## Building art per CityBuilding.variant (wraps around), stretched over the
## footprint's bounds and clipped to its outline; rotated by its rotation.
@export var building_textures: Array[Texture2D] = []
## Optional 4x5 autotile sheets (128 px cells), one per building variant.
## When assigned, pieces are drawn per occupied tile instead of stretching
## the texture over the whole lot.
@export var building_autotile_textures: Array[Texture2D] = []
## Optional 4x4 road autotile sheets (128 px cells), indexed by N/E/S/W mask.
@export var street_texture: Texture2D
@export var avenue_texture: Texture2D
@export var closed_road_texture: Texture2D
@export var park_texture: Texture2D
@export var park_grass_texture: Texture2D
@export var survivor_texture: Texture2D
@export var survivor_group_a_texture: Texture2D
@export var survivor_group_b_texture: Texture2D
@export var fire_texture: Texture2D
@export var fire_sheet_texture: Texture2D
@export var smoke_texture: Texture2D
@export var smoke_sheet_texture: Texture2D
@export var safe_zone_texture: Texture2D
@export var pulse_ring_texture: Texture2D
@export var select_brackets_texture: Texture2D
@export var route_start_texture: Texture2D
@export var route_straight_texture: Texture2D
@export var route_corner_texture: Texture2D
@export var route_end_texture: Texture2D


static func dispatch_style() -> VisualTheme:
	return VisualTheme.new()


## The original prototype palette (flat light roads, per-tile buildings).
static func debug_shapes() -> VisualTheme:
	var t := VisualTheme.new()
	t.style = Style.DEBUG_SHAPES
	t.map_bg = UiPalette.BG_DARK
	t.map_frame = Color(UiPalette.MINT, 0.3)
	t.block_ground = UiPalette.BG_DARK
	t.road = UiPalette.TEAL_MID
	t.avenue = UiPalette.TEAL_MID
	t.intersection = UiPalette.MINT
	t.road_marking = UiPalette.TEAL
	t.road_marking_ratio = 0.06
	t.building_fills = [UiPalette.PANEL, UiPalette.TEAL, UiPalette.TEAL_MID]
	t.building_road_setback = 0.08
	t.building_gap = 0.08
	t.park_fill = UiPalette.PANEL
	t.park_tree = UiPalette.TEAL
	t.show_lot_debug = true
	t.safe_outline = UiPalette.GREEN
	t.safe_tile = UiPalette.TEAL_MID
	t.fire = UiPalette.ALERT
	t.smoke = Color(UiPalette.TEAL_MID, 0.5)
	t.smoke_line = UiPalette.MINT
	t.select_ring = UiPalette.MINT
	t.route = UiPalette.CYAN
	t.hover = Color(UiPalette.WHITE, 0.55)
	t.outline = UiPalette.BG_DARK
	return t


static func for_style(s: Style) -> VisualTheme:
	return debug_shapes() if s == Style.DEBUG_SHAPES else dispatch_style()


func building_fill(variant: int) -> Color:
	if building_fills.is_empty():
		return UiPalette.TEAL
	return building_fills[posmod(variant, building_fills.size())]


func building_texture(variant: int) -> Texture2D:
	if building_textures.is_empty():
		return null
	return building_textures[posmod(variant, building_textures.size())]


func building_autotile_texture(variant: int) -> Texture2D:
	if building_autotile_textures.is_empty():
		return null
	return building_autotile_textures[posmod(variant, building_autotile_textures.size())]
