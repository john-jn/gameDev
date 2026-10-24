extends SceneTree
## Runs the real game in a window and saves PNG snapshots of several rounds in
## both visual styles, plus one with stand-in art in the theme's asset slots,
## for checking the look by eye. Not a pass/fail test, and it needs a display
## (do not pass --headless):
##   godot --path . --script res://tests/capture_screenshots.gd -- --out=C:/shots
## Without --out, images go to user://screenshots.

var out_dir := "user://screenshots"
var rounds: Array[int] = [1, 3, 6, 9]


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var game: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(5)
	for style in [VisualTheme.Style.DISPATCH_STYLE, VisualTheme.Style.DEBUG_SHAPES]:
		game.set_visual_style(style)
		var tag := "dispatch" if style == VisualTheme.Style.DISPATCH_STYLE else "debug"
		for r in rounds:
			await _stage_round(game, r)
			_save("%s_round_%d.png" % [tag, r])
	# Asset slots filled with art generated in memory: no files involved.
	var themed := VisualTheme.dispatch_style()
	themed.building_textures.append(_stripes(Color("2b5d8a"), Color("16324d")))
	themed.building_textures.append(_stripes(Color("6a4a8c"), Color("2e1f45")))
	themed.survivor_texture = _disc(Color("ffe066"), Color("b8860b"))
	themed.fire_texture = _stripes(Color("ff7a1a"), Color("c0200a"))
	game.visual_theme_override = themed
	game.set_visual_style(VisualTheme.Style.DISPATCH_STYLE)
	await _stage_round(game, 3)
	_save("asset_slots_round_3.png")
	quit(0)


## Starts round `r` on a fixed seed, plans half a route for group A, sends the
## next group on its way and hovers a building, so every overlay is on screen.
func _stage_round(game: Control, r: int) -> void:
	game.rng.seed = 4000 + r
	game.round_num = r
	game._start_round()
	var m: CityMap = game.map
	if game.groups.size() > 1:
		var b: SurvivorGroup = game.groups[1]
		game._select_group(b)
		for p in m.find_path(b.tile).slice(1):
			game._try_extend(p)
		game._dispatch()
	var a: SurvivorGroup = game.groups[0]
	game._select_group(a)
	var path := m.find_path(a.tile)
	for p in path.slice(1, maxi(2, path.size() >> 1)):
		game._try_extend(p)
	for bld in m.buildings:
		if bld.kind == CityBuilding.Kind.BUILDING and not bld.is_safe_zone() and bld.cells.size() >= 3:
			game.map_view._hover = bld.cells[0]
			break
	await _frames(40)


func _save(file: String) -> void:
	var path := out_dir.path_join(file)
	root.get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _stripes(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, a if ((x + y) >> 2) % 2 == 0 else b)
	return ImageTexture.create_from_image(img)


func _disc(fill: Color, edge: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length()
			img.set_pixel(x, y, fill if d < 12.0 else (edge if d < 15.5 else Color(0, 0, 0, 0)))
	return ImageTexture.create_from_image(img)
