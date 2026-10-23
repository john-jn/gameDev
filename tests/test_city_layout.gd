extends SceneTree
## Headless tests for the city plan (CityLayout, CityBuilding) and the visual
## layer built on it (VisualTheme, MapPainter, MapView). Run from the project
## folder:
##   godot --headless --path . --script res://tests/test_city_layout.gd
## Optional user args (after `--`): --seeds=N (default 12 per round).
## Exits with code 0 when every check passes, 1 otherwise.
## Headless rendering draws nothing, so these tests check geometry, state and
## input; tests/capture_screenshots.gd is for looking at the result.

const UI_COLORS = preload("res://scripts/ui_colors.gd")

var failures := 0
var checks := 0
var seeds_per_round := 12

## Scripts that make up the game rules. None of them may depend on how the
## map is drawn.
const GAMEPLAY_SCRIPTS := ["city_map.gd", "city_building.gd", "city_layout.gd", "map_generator.gd",
		"physarum_sim.gd", "route_validator.gd", "survivor_group.gd", "hazard_manager.gd", "score_keeper.gd"]
const VISUAL_NAMES := ["VisualTheme", "MapPainter", "MapView", "CanvasItem", "Color(", "Color.", "Texture", "queue_redraw"]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds_per_round = arg.substr(8).to_int()
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	test_layout_invariants()
	test_layout_reads_but_never_writes_tiles()
	test_footprint_geometry()
	test_safe_zone_designation()
	test_gameplay_has_no_visual_dependencies()
	await test_render_styles()
	await test_pointer_input()
	print("\n==== %d checks, %d failures, %.1fs ====" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> bool:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)
	return cond


## Physarum maps for rounds 2-9, lattice maps and the hand-authored map.
func sample_maps(per_round: int) -> Array[CityMap]:
	var maps: Array[CityMap] = [MapGenerator.build_handmade()]
	for r in range(2, 10):
		for s in per_round:
			maps.append(MapGenerator.build_from_seed(r, 7000 + 31 * r + s))
		for attempt in MapGenerator.LATTICE_ATTEMPTS:
			var lat := MapGenerator._try_lattice(r, MapGenerator.attempt_rng(r, r, attempt))
			if lat != null:
				maps.append(lat)
				break
	return maps


# --- City plan ---------------------------------------------------------------------

func test_layout_invariants() -> void:
	print("\n[layout] city plan on generated maps, %d seeds per round" % seeds_per_round)
	var maps := sample_maps(seeds_per_round)
	var bad := 0
	var buildings := 0
	var l_shapes := 0
	var no_entrance := 0
	var parks := 0
	var variants := {}
	var avenue_maps := 0
	var closures := 0
	for m in maps:
		var problems := CityLayout.find_problems(m)
		if not check(problems.is_empty(), "%s map: %s" % [m.gen_info.get("source", "?"), problems.slice(0, 3)]):
			bad += 1
		check(m.safe_zones().size() >= 1, "map has no safe-zone building")
		for z in m.safe_zones():
			check(not z.entrances.is_empty(), "safe zone %d has no open entrance" % z.id)
		var has_avenue := false
		for c in m.road_class:
			if c == CityMap.RoadClass.AVENUE:
				has_avenue = true
		if has_avenue:
			avenue_maps += 1
		closures += m.road_closures.size()
		for b in m.buildings:
			if b.kind == CityBuilding.Kind.PARK:
				parks += 1
				continue
			buildings += 1
			variants[b.variant] = true
			if not b.is_rect():
				l_shapes += 1
			if b.entrances.is_empty():
				no_entrance += 1
			# Every cell of a part is in the footprint and the parts cover it.
			var covered := 0
			for part in b.parts():
				covered += part.get_area()
				for y in range(part.position.y, part.end.y):
					for x in range(part.position.x, part.end.x):
						check(b.cells.has(Vector2i(x, y)), "lot %d part %s leaves its footprint" % [b.id, part])
			check(covered == b.cells.size(), "lot %d parts cover %d of %d tiles" % [b.id, covered, b.cells.size()])
	print("  maps: %d, invalid: %d, buildings: %d (L-shaped %d, no road frontage %d), parks: %d, variants used: %d" % [
		maps.size(), bad, buildings, l_shapes, no_entrance, parks, variants.size()])
	print("  maps with two-lane avenues: %d, closed road tiles: %d" % [avenue_maps, closures])
	check(variants.size() == CityBuilding.VARIANT_COUNT, "every visual variant should be used")
	check(l_shapes > buildings * 0.05, "some footprints should be L-shaped")
	check(no_entrance < buildings * 0.05, "almost every building should face a road")
	check(avenue_maps > 0 and closures > 0, "avenues and closures should be recorded")


func test_layout_reads_but_never_writes_tiles() -> void:
	print("\n[layout] read-only and reproducible")
	var same := 0
	for r in [2, 5, 9]:
		var m := MapGenerator.build_from_seed(r, 99 + r)
		var tiles := m.tiles.duplicate()
		var starts := m.survivor_starts.duplicate()
		var fires := m.fires.keys()
		var ids := m.building_ids.duplicate()
		var before := m.layout_version
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		CityLayout.build(m, rng)
		check(m.tiles == tiles and m.survivor_starts == starts and m.fires.keys() == fires,
				"round %d: building the layout changed gameplay data" % r)
		check(m.layout_version == before + 1, "round %d: layout_version should bump" % r)
		var again := RandomNumberGenerator.new()
		again.seed = 5
		var ids_first := m.building_ids.duplicate()
		CityLayout.build(m, again)
		if check(m.building_ids == ids_first, "round %d: same RNG seed should rebuild the same lots" % r):
			same += 1
		check(ids.size() == m.building_ids.size(), "round %d: layout size" % r)
	var hm := MapGenerator.build_handmade()
	check(hm.building_ids == MapGenerator.build_handmade().building_ids, "hand-authored map layout should be fixed")
	print("  identical rebuilds: %d/3" % same)


## Footprint outlines (both styles' setbacks) stay inside their own tiles, off
## every road tile, and clear of each other.
func test_footprint_geometry() -> void:
	print("\n[geometry] footprint outlines vs roads and neighbours")
	var lots := 0
	var on_road := 0
	var overlaps := 0
	var degenerate := 0
	var outside := 0
	for theme in [VisualTheme.dispatch_style(), VisualTheme.debug_shapes()]:
		for m in sample_maps(2):
			var shapes := []
			for b in m.buildings:
				shapes.append(MapPainter.lot_shape(m, b, theme))
			for b in m.buildings:
				lots += 1
				var s: MapPainter.LotShape = shapes[b.id]
				if s.outline.size() < 4 or Geometry2D.triangulate_polygon(s.outline).is_empty():
					degenerate += 1
					continue
				var area := Rect2(b.bounds).grow(0.0001)
				for v in s.outline:
					if not area.has_point(v):
						outside += 1
				var seen := {}
				for c in b.cells:
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
						var q: Vector2i = c + d
						if seen.has(q) or b.cells.has(q) or not m.in_bounds(q):
							continue
						seen[q] = true
						var other := m.building_at(q)
						var tile_poly := MapPainter._rect_poly(Rect2(Vector2(q), Vector2.ONE))
						if other == null:
							if not Geometry2D.intersect_polygons(s.outline, tile_poly).is_empty():
								on_road += 1
						elif other.id > b.id:
							var o: MapPainter.LotShape = shapes[other.id]
							if not Geometry2D.intersect_polygons(s.outline, o.outline).is_empty():
								overlaps += 1
				for door in s.doors:
					var mid := (door[0] + door[1] + door[2] + door[3]) * 0.25
					check(b.cells.has(Vector2i(mid.floor())) or b.entrances.has(Vector2i(mid.floor())),
							"lot %d entrance strip is not between the lot and its road" % b.id)
	print("  outlines checked: %d, on road tiles: %d, overlapping: %d, degenerate: %d, vertices outside footprint: %d" % [
		lots, on_road, overlaps, degenerate, outside])
	check(on_road == 0, "no footprint may cover a road or closed-road tile")
	check(overlaps == 0, "footprints must not overlap")
	check(degenerate == 0, "every footprint outline must be a fillable polygon")
	check(outside == 0, "outlines must stay inside their footprint")


## Any building with a road entrance can become a safe zone, and pathfinding,
## validation and the generator's own rules accept it.
func test_safe_zone_designation() -> void:
	print("\n[safe zones] designating ordinary buildings")
	var designated := 0
	var refused := 0
	for r in range(2, 10):
		var m := MapGenerator.build_from_seed(r, 4400 + r)
		var rng := RandomNumberGenerator.new()
		rng.seed = r
		var picks: Array[CityBuilding] = []
		for b in m.buildings:
			if b.kind == CityBuilding.Kind.PARK or b.entrances.is_empty():
				check(not m.can_be_safe_zone(b), "round %d: lot %d should not be eligible" % [r, b.id])
				var tiles := m.tiles.duplicate()
				if not m.designate_safe_zone(b):
					refused += 1
				check(m.tiles == tiles and not b.is_safe_zone(), "round %d: refused designation changed the map" % r)
			elif not b.is_safe_zone():
				picks.append(b)
		var pick: CityBuilding = picks[rng.randi() % picks.size()]
		var version := m.layout_version
		check(m.designate_safe_zone(pick), "round %d: eligible lot %d refused" % [r, pick.id])
		designated += 1
		check(pick.is_safe_zone() and m.safe_zones().has(pick) and m.layout_version == version + 1,
				"round %d: designation not recorded" % r)
		for c in pick.cells:
			check(m.is_safe(c), "round %d: designated tile %s is not SAFE" % [r, c])
		# From its entrance, safety is one step away (BFS may pick another zone
		# that is equally close), and a route into the new zone is accepted.
		check(m.shortest_length(pick.entrance) == 1, "round %d: entrance %s is not next to safety" % [r, pick.entrance])
		var door := CityMap.NO_TILE
		for c in pick.cells:
			if m.is_adjacent(c, pick.entrance):
				door = c
		var route: Array[Vector2i] = [pick.entrance, door]
		var v := RouteValidator.validate(m, route, pick.entrance)
		check(v["valid"] and v["complete"], "round %d: route into the new zone rejected: %s" % [r, v["reason"]])
		for s in m.survivor_starts:
			check(m.has_path(s) and m.is_robust(s), "round %d: group at %s lost its route" % [r, s])
		check(MapGenerator._layout_ok(m), "round %d: generator rules broken by the new zone" % r)
		check(CityLayout.find_problems(m).is_empty(), "round %d: layout invalid after designation: %s" % [r, CityLayout.find_problems(m).slice(0, 2)])
	print("  designated: %d, ineligible lots refused: %d" % [designated, refused])
	check(refused > 0, "parks and buried lots should be refused")


## Static check: no gameplay script names a visual class, colour or draw call,
## so swapping art can never change the rules.
func test_gameplay_has_no_visual_dependencies() -> void:
	print("\n[separation] gameplay scripts vs visual code")
	var hits: Array[String] = []
	for file in GAMEPLAY_SCRIPTS:
		var src := FileAccess.get_file_as_string("res://scripts/" + file)
		check(not src.is_empty(), "could not read %s" % file)
		for line in src.split("\n"):
			var code := line.split("#")[0]
			for name in VISUAL_NAMES:
				if code.contains(name):
					hits.append("%s: %s" % [file, line.strip_edges()])
	print("  gameplay scripts scanned: %d, visual references: %d" % [GAMEPLAY_SCRIPTS.size(), hits.size()])
	check(hits.is_empty(), "gameplay code references visuals: %s" % [hits])


# --- Rendering ---------------------------------------------------------------------

func _generated_texture(color: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Draws a busy map (fires, smoke, closures, groups en route, a planned route)
## in every theme, plus a map with no city plan, and checks the view's state.
func test_render_styles() -> void:
	print("\n[render] MapView in each theme")
	var art := VisualTheme.dispatch_style()
	art.building_textures.append(_generated_texture(Color.STEEL_BLUE))
	art.park_texture = _generated_texture(Color.DARK_GREEN)
	art.survivor_texture = _generated_texture(Color.YELLOW)
	art.fire_texture = _generated_texture(Color.ORANGE_RED)
	var autotiled := VisualTheme.dispatch_style()
	var sheet_image := Image.create(512, 640, false, Image.FORMAT_RGBA8)
	sheet_image.fill(Color.AQUA)
	autotiled.building_autotile_textures.append(ImageTexture.create_from_image(sheet_image))
	var road_image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	road_image.fill(Color.DARK_SLATE_GRAY)
	autotiled.street_texture = ImageTexture.create_from_image(road_image)
	autotiled.avenue_texture = ImageTexture.create_from_image(road_image)
	autotiled.closed_road_texture = _generated_texture(Color("303030"))
	var park_image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	park_image.fill(Color.DARK_GREEN)
	autotiled.park_texture = ImageTexture.create_from_image(park_image)
	autotiled.park_grass_texture = _generated_texture(Color.DARK_GREEN)
	autotiled.survivor_texture = _generated_texture(Color.YELLOW)
	autotiled.survivor_group_a_texture = _generated_texture(Color.CYAN)
	autotiled.survivor_group_b_texture = _generated_texture(Color.GREEN)
	var safe_image := Image.create(384, 384, false, Image.FORMAT_RGBA8)
	safe_image.fill(Color.GREEN)
	autotiled.safe_zone_texture = ImageTexture.create_from_image(safe_image)
	var fire_image := Image.create(1024, 128, false, Image.FORMAT_RGBA8)
	fire_image.fill(Color.ORANGE_RED)
	autotiled.fire_sheet_texture = ImageTexture.create_from_image(fire_image)
	autotiled.smoke_texture = _generated_texture(Color.GRAY)
	var smoke_sheet_image := Image.create(512, 128, false, Image.FORMAT_RGBA8)
	smoke_sheet_image.fill(Color.GRAY)
	autotiled.smoke_sheet_texture = ImageTexture.create_from_image(smoke_sheet_image)
	var pulse_ring_image := Image.create(576, 96, false, Image.FORMAT_RGBA8)
	pulse_ring_image.fill(Color.WHITE)
	autotiled.pulse_ring_texture = ImageTexture.create_from_image(pulse_ring_image)
	autotiled.select_brackets_texture = _generated_texture(Color.WHITE)
	autotiled.route_start_texture = _generated_texture(Color.WHITE)
	autotiled.route_straight_texture = _generated_texture(Color.WHITE)
	autotiled.route_corner_texture = _generated_texture(Color.WHITE)
	autotiled.route_end_texture = _generated_texture(Color.WHITE)
	var no_highlight := VisualTheme.dispatch_style()
	no_highlight.safe_highlight_enabled = false
	var themes := {"dispatch": VisualTheme.dispatch_style(), "debug": VisualTheme.debug_shapes(),
			"asset slots": art, "autotile sheet": autotiled, "no highlight": no_highlight}
	check(art.building_texture(3) != null and VisualTheme.dispatch_style().building_texture(0) == null,
			"building texture slots should resolve by variant")
	check(autotiled.building_autotile_texture(0) != null,
			"building autotile texture slots should resolve by variant")
	check(autotiled.street_texture != null and autotiled.avenue_texture != null,
			"road autotile texture slots should be available")
	check(autotiled.closed_road_texture != null and autotiled.park_texture != null
			and autotiled.survivor_texture != null and autotiled.safe_zone_texture != null
			and autotiled.park_grass_texture != null and autotiled.survivor_group_a_texture != null
			and autotiled.survivor_group_b_texture != null and autotiled.pulse_ring_texture != null
			and autotiled.select_brackets_texture != null and autotiled.fire_sheet_texture != null
			and autotiled.smoke_sheet_texture != null
			and autotiled.route_start_texture != null and autotiled.route_straight_texture != null
			and autotiled.route_corner_texture != null and autotiled.route_end_texture != null,
			"map sprite slots should be available")
	var connected_theme := load("res://assets/art/dispatch_theme.tres") as VisualTheme
	check(connected_theme != null and connected_theme.street_texture != null
			and connected_theme.avenue_texture != null and connected_theme.fire_sheet_texture != null
			and connected_theme.safe_zone_texture != null and connected_theme.park_texture != null
			and connected_theme.park_grass_texture != null and connected_theme.pulse_ring_texture != null
			and connected_theme.select_brackets_texture != null
			and connected_theme.survivor_group_a_texture != null
			and connected_theme.survivor_group_b_texture != null
			and connected_theme.smoke_sheet_texture != null and connected_theme.route_start_texture != null
			and connected_theme.route_straight_texture != null and connected_theme.route_corner_texture != null
			and connected_theme.route_end_texture != null, "connected art theme should load its textures")
	var m := MapGenerator.build_from_seed(7, 321)
	var groups: Array[SurvivorGroup] = []
	for i in m.survivor_starts.size():
		groups.append(SurvivorGroup.new(i, char(65 + i), m.survivor_starts[i], m.survivor_sizes[i]))
	groups[0].dispatch(m.find_path(groups[0].tile))
	var mv := MapView.new()
	mv.size = Vector2(900, 640)
	root.add_child(mv)
	mv.map = m
	mv.groups = groups
	mv.selected = groups[1]
	mv.route = m.find_path(groups[1].tile)
	mv.route_complete = true
	check(not m.fires.is_empty() and not m.road_closures.is_empty(), "test map should have fires and closures to draw")
	# Spreading fire: a smoldering tile next to a fire, and a group losing
	# people to smoke (countdown ring).
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			if m.can_burn(p) and not m.is_fire(p):
				m.add_smolder(p, 1.0)
				break
		if not m.smolders.is_empty():
			break
	var drainer: SurvivorGroup
	for candidate in groups:
		for d in CityMap.DIRS:
			var fire_tile: Vector2i = candidate.tile + d
			if m.can_burn(fire_tile) and not m.is_fire(fire_tile):
				m.add_fire(fire_tile)
				if m.is_smoke(candidate.tile):
					drainer = candidate
					break
		if drainer != null:
			break
	if drainer != null:
		drainer.smoke_drain = 2.0
		drainer.smoke_timer = 1.2
	check(not m.smolders.is_empty() and drainer != null and drainer.is_draining(m),
			"test map should have embers and a draining group to draw")
	for name in themes:
		mv.visual_theme = themes[name]
		mv._hover = m.buildings[0].cells[0]
		for i in 3:
			await process_frame
		check(mv._shapes.size() == m.buildings.size() and mv._shapes_key[2] == themes[name],
				"%s: lot shapes not built for this theme" % name)
		check(mv._drawn_version == m.layout_version, "%s: city layer not drawn" % name)
	for layer in [mv._city_layer, mv._park_layer, mv._building_layer,
			mv._smoke_layer, mv._overlay_layer]:
		check(layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "draw layers must not take input")
	check(mv._city_layer.z_index < mv._park_layer.z_index
			and mv._park_layer.z_index < mv._building_layer.z_index
			and mv._building_layer.z_index < mv._smoke_layer.z_index
			and mv._smoke_layer.z_index < mv._route_line.z_index
			and mv._route_line.z_index < mv._overlay_layer.z_index,
			"buildings, smoke, route and overlays should render in order")
	check(mv._building_layer.modulate == UI_COLORS.BUILDING_DIM,
			"only the building layer should use the dim tint")
	check(mv._route_line.width == 7.0, "planned route line should stay within the requested width")
	# Designating a new zone redraws the city with fresh geometry.
	var extra: CityBuilding = null
	for b in m.buildings:
		if m.can_be_safe_zone(b) and not b.is_safe_zone():
			extra = b
			break
	m.designate_safe_zone(extra)
	await process_frame
	await process_frame
	check(mv._drawn_version == m.layout_version and mv._shapes_key[1] == m.layout_version, "designation should trigger a redraw")
	# A hand-made map without a city plan falls back to flat shapes.
	var bare := CityMap.new()
	bare.setup(6, 5, CityMap.Tile.ROAD)
	bare.set_tile(Vector2i(2, 2), CityMap.Tile.BUILDING)
	bare.set_tile(Vector2i(5, 4), CityMap.Tile.SAFE)
	mv.visual_theme = VisualTheme.dispatch_style()
	mv.map = bare
	mv.groups = []
	mv.selected = null
	await process_frame
	await process_frame
	check(mv._drawn_version == bare.layout_version, "map without a city plan should still draw")
	mv.queue_free()
	await process_frame
	print("  themes drawn: %s, plus a designated zone and a map without a plan" % [themes.keys()])


## Drives the real game with pointer events at the drawn tile centres: select
## a group, drag its route, dispatch. Then switches style and checks that only
## the look changed.
func test_pointer_input() -> void:
	print("\n[input] pointer events through the main scene")
	var game: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.rng.seed = 2024
	for i in 3:
		await process_frame
	for style in [VisualTheme.Style.DISPATCH_STYLE, VisualTheme.Style.DEBUG_SHAPES]:
		game.set_visual_style(style)
		game.round_num = 4
		game._start_round()
		await process_frame
		var mv: MapView = game.map_view
		var m: CityMap = game.map
		mv.size = Vector2(1000, 700)
		mv._update_layout()
		var g: SurvivorGroup = game.groups[0]
		var path := m.find_path(g.tile)
		_press(mv, mv.tile_center(g.tile), true)
		check(game.selected == g, "style %d: tapping the group's drawn position should select it" % style)
		for p in path.slice(1):
			_drag(mv, mv.tile_center(p))
		_press(mv, mv.tile_center(path[-1]), false)
		check(game.route == path, "style %d: dragging along drawn tiles should build the route (%d of %d tiles)" % [
				style, game.route.size(), path.size()])
		# Tapping a building is refused and leaves the route alone.
		var bld := m.buildings[0]
		for b in m.buildings:
			if b.kind == CityBuilding.Kind.BUILDING and not b.is_safe_zone():
				bld = b
				break
		var before: Array[Vector2i] = game.route.duplicate()
		_press(mv, mv.tile_center(bld.cells[0]), true)
		_press(mv, mv.tile_center(bld.cells[0]), false)
		check(game.route == before, "style %d: tapping a building changed the route" % style)
		var score: int = game.scorer.total()
		var other: VisualTheme.Style = VisualTheme.Style.DEBUG_SHAPES if style == VisualTheme.Style.DISPATCH_STYLE else VisualTheme.Style.DISPATCH_STYLE
		game.set_visual_style(other)
		await process_frame
		check(game.map == m and game.route == before and game.selected == g and game.scorer.total() == score,
				"style %d: switching style changed game state" % style)
		check(game.legend.get_child_count() > 0 and mv.visual_theme == game.visual_theme, "style switch did not reach the view/legend")
		game.set_visual_style(style)
		game._dispatch()
		check(g.state == SurvivorGroup.State.MOVING, "style %d: dispatch after pointer planning failed" % style)
	game.queue_free()
	await process_frame
	print("  pointer-planned routes dispatched in both styles")


func _press(mv: MapView, pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	mv._gui_input(ev)


func _drag(mv: MapView, pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	mv._gui_input(ev)
