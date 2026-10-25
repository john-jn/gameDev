extends Node
## Scripted gameplay demo for the Evac Grid tutorial video.
##
## Open demo/demo_render.tscn, turn on Movie Maker mode (film icon, top right
## of the editor) and press "Run Current Scene" (F6). The director plays the
## real game through the demo script, shows captions and a pointer, then quits,
## which finalizes the video file named in the scene root's `movie_file`
## metadata. Normal play (scenes/main.tscn) is not affected by any of this.
##
## Gameplay is driven through the same methods the mouse and buttons call, so
## everything on screen is the real game reacting. One beat plants a fire
## warning ahead of Group B on purpose, so the "route blocked -> detour" part
## of the script happens on cue instead of by luck.

const FONT_BOLD := preload("res://assets/fonts/Rajdhani-Bold.ttf")
const FONT_MEDIUM := preload("res://assets/fonts/Rajdhani-Medium.ttf")
const LOGO := preload("res://assets/art/logo_evac_grid.png")

const DEMO_SEED := 20261025
const WORDS_PER_SECOND := 2.6   ## caption pace, roughly a relaxed speaking voice
const MINT := Color("96f2d8")
const ACCENT := Color("3cffd0")
const WARN := Color("ffc24d")
const PANEL_BG := Color(0.02, 0.09, 0.10, 0.88)

# --- Overlay pieces -------------------------------------------------------------

class Pointer extends Node2D:
	var pressed := false

	func _draw() -> void:
		var pts := PackedVector2Array([
			Vector2(0, 0), Vector2(0, 27), Vector2(7, 21), Vector2(12, 32),
			Vector2(17, 30), Vector2(12, 19), Vector2(21, 19)])
		draw_colored_polygon(pts, Color(1, 1, 1) if not pressed else Color("c8fff0"))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0.02, 0.08, 0.09), 2.0, true)


class Ripple extends Node2D:
	var age := 0.0
	var color := Color("3cffd0")

	func _process(delta: float) -> void:
		age += delta
		if age >= 0.45:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := age / 0.45
		draw_arc(Vector2.ZERO, 6.0 + 22.0 * k, 0.0, TAU, 32, Color(color, 1.0 - k), 3.0, true)


var game                       ## the Main node (scripts/game.gd), left untyped on purpose
var _clock := 0.0
var _caption_until := 0.0

var _layer: CanvasLayer
var _blocker: Control
var _caption_box: PanelContainer
var _caption_chapter: Label
var _caption_text: Label
var _highlight: Panel
var _highlight_tween: Tween
var _toast: PanelContainer
var _toast_label: Label
var _pointer: Pointer
var _ghost: Line2D
var _fade: ColorRect
var _end_card: VBoxContainer
var _end_line: Label


# --- Setup ----------------------------------------------------------------------

func _ready() -> void:
	game = get_node("Main")
	game.rng.seed = DEMO_SEED
	game.tutorial.seen = true          # skip the first-launch tutorial offer
	game.set_process_unhandled_input(false)
	_build_overlay()
	_run.call_deferred()


func _process(delta: float) -> void:
	_clock += delta


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)

	# Swallows real mouse input so a stray mouse move can't change the take.
	_blocker = Control.new()
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_blocker)

	_highlight = Panel.new()
	var hs := StyleBoxFlat.new()
	hs.draw_center = false
	hs.border_color = MINT
	hs.set_border_width_all(3)
	hs.set_corner_radius_all(8)
	hs.shadow_color = Color(ACCENT, 0.35)
	hs.shadow_size = 10
	_highlight.add_theme_stylebox_override("panel", hs)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false
	_layer.add_child(_highlight)

	_ghost = Line2D.new()
	_ghost.width = 7.0
	_ghost.default_color = Color(WARN, 0.85)
	_ghost.joint_mode = Line2D.LINE_JOINT_ROUND
	_ghost.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_ghost.end_cap_mode = Line2D.LINE_CAP_ROUND
	_layer.add_child(_ghost)

	_caption_box = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = PANEL_BG
	cs.border_color = Color(MINT, 0.55)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(10)
	cs.content_margin_left = 22
	cs.content_margin_right = 22
	cs.content_margin_top = 10
	cs.content_margin_bottom = 12
	_caption_box.add_theme_stylebox_override("panel", cs)
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.anchor_left = 0.5
	_caption_box.anchor_right = 0.5
	_caption_box.anchor_top = 1.0
	_caption_box.anchor_bottom = 1.0
	_caption_box.offset_left = -470
	_caption_box.offset_right = 470
	_caption_box.offset_top = -150
	_caption_box.offset_bottom = -40
	_caption_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption_box.modulate.a = 0.0
	_layer.add_child(_caption_box)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	cv.alignment = BoxContainer.ALIGNMENT_END
	_caption_box.add_child(cv)
	_caption_chapter = _make_label(FONT_BOLD, 14, ACCENT)
	cv.add_child(_caption_chapter)
	_caption_text = _make_label(FONT_MEDIUM, 25, Color("e6fff8"))
	_caption_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_text.custom_minimum_size.x = 896
	cv.add_child(_caption_text)

	_toast = PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.02, 0.09, 0.10, 0.92)
	ts.border_color = WARN
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(8)
	ts.content_margin_left = 14
	ts.content_margin_right = 14
	ts.content_margin_top = 4
	ts.content_margin_bottom = 6
	_toast.add_theme_stylebox_override("panel", ts)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_layer.add_child(_toast)
	_toast_label = _make_label(FONT_BOLD, 22, WARN)
	_toast.add_child(_toast_label)

	_fade = ColorRect.new()
	_fade.color = Color(0.01, 0.05, 0.06, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)

	_end_card = VBoxContainer.new()
	_end_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_card.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_card.add_theme_constant_override("separation", 22)
	_end_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_card.modulate.a = 0.0
	_layer.add_child(_end_card)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 220)
	_end_card.add_child(logo)
	_end_line = _make_label(FONT_BOLD, 30, Color("e6fff8"))
	_end_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_card.add_child(_end_line)

	_pointer = Pointer.new()
	_pointer.position = Vector2(1180, 760)
	_layer.add_child(_pointer)


func _make_label(font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Timing helpers ---------------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits until `cond` returns true, or `timeout` seconds pass. Returns cond's result.
func _wait_for(cond: Callable, timeout: float) -> bool:
	var until := _clock + timeout
	while _clock < until:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


## Shows a caption for as long as it takes to read it aloud.
func _say(chapter: String, text: String) -> void:
	if chapter != "":
		_caption_chapter.text = chapter.to_upper()
	_caption_text.text = text
	var words := text.split(" ", false).size()
	var secs := maxf(2.4, float(words) / WORDS_PER_SECOND + 0.7)
	_caption_until = _clock + secs
	if _caption_box.modulate.a < 1.0:
		create_tween().tween_property(_caption_box, "modulate:a", 1.0, 0.25)


## Waits until the current caption has been on screen for its full read time.
func _finish_say() -> void:
	while _clock < _caption_until:
		await get_tree().process_frame


func _hide_caption() -> void:
	create_tween().tween_property(_caption_box, "modulate:a", 0.0, 0.3)


# --- Pointer, highlights, toasts ------------------------------------------------------

func _move_to(pos: Vector2, seconds: float = 0.45) -> void:
	var tw := create_tween()
	tw.tween_property(_pointer, "position", pos, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _click_at(pos: Vector2) -> void:
	await _move_to(pos)
	_pointer.pressed = true
	_pointer.queue_redraw()
	var r := Ripple.new()
	r.position = pos
	_layer.add_child(r)
	_layer.move_child(_pointer, -1)
	await _wait(0.12)
	_pointer.pressed = false
	_pointer.queue_redraw()


func _center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _tile_pos(p: Vector2i) -> Vector2:
	game.map_view._update_layout()
	return game.map_view.get_global_transform() * game.map_view.tile_center(p)


func _tile_rect(p: Vector2i) -> Rect2:
	game.map_view._update_layout()
	var r: Rect2 = game.map_view.tile_rect(p)
	return Rect2(game.map_view.get_global_transform() * r.position, r.size)


func _show_highlight(rect: Rect2, pad: float = 6.0) -> void:
	var target := rect.grow(pad)
	if _highlight_tween != null and _highlight_tween.is_running():
		_highlight_tween.kill()
	if not _highlight.visible:
		_highlight.position = target.position
		_highlight.size = target.size
		_highlight.modulate.a = 0.0
		_highlight.visible = true
	_highlight_tween = create_tween().set_parallel(true)
	_highlight_tween.tween_property(_highlight, "position", target.position, 0.35).set_trans(Tween.TRANS_SINE)
	_highlight_tween.tween_property(_highlight, "size", target.size, 0.35).set_trans(Tween.TRANS_SINE)
	_highlight_tween.tween_property(_highlight, "modulate:a", 1.0, 0.25)


func _hide_highlight() -> void:
	if not _highlight.visible:
		return
	if _highlight_tween != null and _highlight_tween.is_running():
		_highlight_tween.kill()
	_highlight_tween = create_tween()
	_highlight_tween.tween_property(_highlight, "modulate:a", 0.0, 0.25)
	_highlight_tween.tween_callback(func() -> void: _highlight.visible = false)


func _show_toast(text: String, near: Vector2) -> void:
	_toast_label.text = text
	_toast.reset_size()
	_toast.position = near + Vector2(26, -46)
	_toast.modulate.a = 1.0
	_toast.visible = true
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: _toast.visible = false)


# --- Game actions (the same calls the mouse and buttons make) --------------------------

func _group(label: String):
	for g in game.groups:
		if g.label == label:
			return g
	return null


func _row_button(g) -> Button:
	return game.group_btns[game.groups.find(g)]


func _click_button(b: Button) -> void:
	await _click_at(_center_of(b))


func _select_by_row(g) -> void:
	await _click_button(_row_button(g))
	game._on_group_row_pressed(g)


func _select_by_marker(g) -> void:
	var pos := _tile_pos(g.tile)
	await _click_at(pos)
	game.map_view._ripple_tile = g.tile
	game.map_view._ripple_age = 0.0
	game._on_tile_pressed(g.tile)


## Cheapest route to the nearest SAFE tile: fire is impassable, smoldering
## and smoky roads cost extra, so the demo picks the sensible route.
func _plan_path(from: Vector2i) -> Array[Vector2i]:
	var m = game.map
	var dist := {from: 0.0}
	var prev := {}
	var open: Array[Vector2i] = [from]
	var goal := CityMap.NO_TILE
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if m.is_safe(cur):
			goal = cur
			break
		for d in CityMap.DIRS:
			var n: Vector2i = cur + d
			if not m.in_bounds(n) or not m.is_passable(n):
				continue
			var cost := 1.0
			if m.is_smoldering(n):
				cost += 40.0
			if m.is_smoke(n):
				cost += 8.0
			var nd: float = dist[cur] + cost
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				prev[n] = cur
				if not open.has(n):
					open.append(n)
	var path: Array[Vector2i] = []
	if goal == CityMap.NO_TILE:
		return path
	var at := goal
	while at != from:
		path.push_front(at)
		at = prev[at]
	path.push_front(from)
	return path


## Drags the pointer along `path` (path[0] is the group's own tile).
func _drag_route(path: Array[Vector2i], step_seconds: float) -> void:
	_pointer.pressed = true
	_pointer.queue_redraw()
	for i in range(1, path.size()):
		var p := path[i]
		await _move_to(_tile_pos(p), step_seconds)
		game.map_view._hover = p
		game._on_tile_dragged(p)
	_pointer.pressed = false
	_pointer.queue_redraw()


func _route_ready(g) -> bool:
	if game.selected != g:
		return false
	var v: Dictionary = RouteValidator.validate(game.map, game.route, g.tile)
	return v["valid"] and v["complete"]


## Draws a fresh route for the selected group `g` (redrawing if the fire moved
## while drawing) but does not dispatch.
func _draw_route_for(g, step_seconds: float) -> bool:
	for attempt in 3:
		if game.selected != g:
			game._select_group(g)
		if game.route.size() > 1:
			game._clear_route()
		var path := _plan_path(g.tile)
		if path.size() < 2:
			return false
		await _drag_route(path, step_seconds if attempt == 0 else 0.06)
		if _route_ready(g):
			return true
	return _route_ready(g)


func _press_dispatch() -> void:
	await _click_button(game.btn_team_dispatch)
	game._on_team_dispatch_pressed()


## Select (if needed), draw and dispatch. Returns true if the group set off.
func _send(g, by_row: bool, step_seconds: float) -> bool:
	if g == null or not g.can_plan() or game.round_over:
		return false
	if game.selected != g:
		if by_row:
			await _select_by_row(g)
		else:
			await _select_by_marker(g)
	var drawn: bool = await _draw_route_for(g, step_seconds)
	if not drawn:
		return false
	await _press_dispatch()
	return g.state == SurvivorGroup.State.MOVING


## Sends every group that is waiting or stuck, until the round ends.
func _bring_everyone_home(timeout: float) -> void:
	var until := _clock + timeout
	while _clock < until and not game.round_over:
		for g in game.groups:
			if game.round_over:
				break
			if g.can_plan():
				await _send(g, false, 0.07)
		await _wait(0.2)


## Plants a fire warning on `g`'s route far enough ahead that it ignites
## before the group gets there. Uses only tiles that leave everyone a way out.
func _plant_fire_ahead(g) -> Vector2i:
	var m = game.map
	for off in [12, 11, 13, 10, 14, 9]:
		var i: int = g.index + off
		if i >= g.path.size() - 2:
			continue
		var p: Vector2i = g.path[i]
		if m.is_safe(p) or m.is_fire(p) or m.is_smoldering(p) or not m.can_burn(p):
			continue
		m.add_fire(p)
		var ok := true
		for other in game.groups:
			if other.is_active() and not m.has_path(other.stop_tile()):
				ok = false
		m.remove_fire(p)
		if ok:
			m.add_smolder(p, 3.2)
			game.map_view.popup(p, "FIRE WARNING", WARN)
			return p
	return CityMap.NO_TILE


func _first_in_state(s: int):
	for g in game.groups:
		if g.state == s:
			return g
	return null


# --- The video ---------------------------------------------------------------------

func _run() -> void:
	await _wait(1.0)

	# [0:00] Hook + intro, over the live main menu.
	_say("Evac Grid  |  gameplay tutorial", "Imagine the city is on fire, the roads are falling apart, and a few dozen people are counting on you to get them home. No pressure.")
	await _finish_say()
	_say("", "Welcome to Evac Grid, a top-down disaster-evacuation puzzle game.")
	await _finish_say()
	_say("", "You're not a firefighter or a superhero. You're the remote evacuation operator: the calm voice in the chaos.")
	await _finish_say()
	_say("", "Your job: guide survivors to the green SAFE zone before the city decides otherwise.")
	await _wait(1.6)
	await _click_button(game.btn_menu_start)
	game._on_start_game_pressed()
	await _finish_say()

	# [0:20] Quick tour.
	_say("The interface", "Here's mission control. On the left is the city grid.")
	await _wait(0.4)
	_show_highlight(game.map_frame.get_global_rect(), 2.0)
	await _finish_say()
	var teams_rect: Rect2 = game.group_box.get_global_rect().merge(game.btn_team_clear.get_global_rect())
	_say("", "On the right are your survivor teams, with the round, your score and the clock up top.")
	_show_highlight(teams_rect)
	await _wait(2.2)
	_show_highlight(game.lbl_round.get_global_rect().merge(game.lbl_score.get_global_rect()))
	await _finish_say()
	var a = _group("A")
	var b = _group("B")
	_say("", "These markers are your survivor groups. Green is safety. Roads are the only way through.")
	_show_highlight(_tile_rect(a.tile), 8.0)
	await _wait(1.6)
	_show_highlight(_tile_rect(b.tile), 8.0)
	await _wait(1.4)
	var safe_rect := Rect2()
	var first := true
	for y in game.map.height:
		for x in game.map.width:
			var p := Vector2i(x, y)
			if game.map.is_safe(p):
				safe_rect = _tile_rect(p) if first else safe_rect.merge(_tile_rect(p))
				first = false
	_show_highlight(safe_rect, 6.0)
	await _finish_say()
	_say("", "Survivors are brave, but they won't cut through buildings.")
	await _finish_say()
	_hide_highlight()
	_say("", "Click a team, in the panel or right on the map, and you're ready to plan its route.")
	await _select_by_row(a)
	await _finish_say()

	# [0:45] Plan and dispatch.
	var a_path := _plan_path(a.tile)
	var half := maxi(2, int(a_path.size() / 2.0))
	_say("Plan and dispatch", "Let's get Group A out. Click or drag across connected roads toward SAFE.")
	await _drag_route(a_path.slice(0, half + 1), 0.16)
	await _finish_say()
	_say("", "Quick rule: the shortest route isn't always the smartest. That shortcut past the fire? It's short because you might not finish it.")
	await _drag_route(a_path.slice(half), 0.16)
	await _finish_say()
	_say("", "Made a mistake? Undo a step, clear the route, or click an earlier tile to trim it.")
	for i in 2:
		_show_toast("UNDO  (Z)", _pointer.position)
		game._undo()
		await _wait(0.7)
	_show_highlight(game.btn_team_clear.get_global_rect(), 4.0)
	await _wait(0.9)
	_hide_highlight()
	var trim_index := maxi(1, game.route.size() - 4)
	var trim_tile: Vector2i = game.route[trim_index]
	await _click_at(_tile_pos(trim_tile))
	game._on_tile_pressed(trim_tile)
	await _wait(0.6)
	var rest: Array[Vector2i] = _plan_path(trim_tile)
	await _drag_route(rest, 0.13)
	if not _route_ready(a):
		await _draw_route_for(a, 0.08)
	await _finish_say()
	_say("", "And... DISPATCH! Group A is on the move, one tile at a time.")
	await _press_dispatch()
	await _finish_say()

	# [1:20] The city fights back.
	_say("The city fights back", "Here's the twist: the disaster doesn't wait for you. Fire spreads to nearby roads, and smoke hurts anyone who walks through it.")
	var b_sent := await _send(b, true, 0.09)
	var warn_tile := CityMap.NO_TILE
	if b_sent:
		await _wait(0.3)
		warn_tile = _plant_fire_ahead(b)
	await _finish_say()
	if warn_tile != CityMap.NO_TILE:
		_say("", "See that warning? That's your heads-up: a few seconds to react.")
		_show_highlight(_tile_rect(warn_tile), 10.0)
	await _wait_for(func() -> bool: return b.state == SurvivorGroup.State.BLOCKED or not b.is_active(), 9.0)
	await _finish_say()
	_hide_highlight()
	_say("", "If a route gets blocked, the team stops at the last safe tile and waits for new orders.")
	if b.state == SurvivorGroup.State.BLOCKED:
		_show_highlight(_tile_rect(b.tile), 8.0)
	await _finish_say()
	_hide_highlight()
	_say("", "Planning once and sitting back is not a strategy here.")
	await _finish_say()

	# [1:55] Detours and STOP.
	var stuck = _first_in_state(SurvivorGroup.State.BLOCKED)
	_say("Detours and scoring", "Team stuck? Select them again and draw a detour from where they're standing.")
	if stuck != null:
		await _select_by_marker(stuck)
		await _draw_route_for(stuck, 0.12)
		await _press_dispatch()
	await _finish_say()
	var mover = stuck if stuck != null and stuck.state == SurvivorGroup.State.MOVING else _first_in_state(SurvivorGroup.State.MOVING)
	_say("", "Need them to freeze right now? Hit STOP.")
	if mover != null:
		await _wait(0.6)
		await _click_button(game.btn_team_stop)
		game._on_team_stop_pressed()
	await _finish_say()
	_say("", "Then send them on their way again.")
	if mover != null:
		await _wait_for(func() -> bool: return mover.can_plan() or not mover.is_active(), 3.0)
		await _send(mover, false, 0.09)
	await _finish_say()
	await _bring_everyone_home(40.0)
	await _wait_for(func() -> bool: return game.round_over, 40.0)
	await _wait(0.8)
	_say("", "At the end of the round you're scored on survivors rescued, route efficiency, planning speed, hazard response time and casualties.")
	_show_highlight(game.result_grid.get_global_rect(), 10.0)
	await _finish_say()
	_say("", "Fast is good. Careful is better.")
	_show_highlight(game.lbl_result_total.get_global_rect(), 10.0)
	await _finish_say()
	_hide_highlight()

	# [2:20] Under the hood.
	_say("Under the hood", "Quick peek behind the curtain. From round 2, the city is procedurally generated with the Physarum algorithm.")
	await _wait(1.2)
	await _click_button(game.btn_next)
	game._on_next_pressed()
	await _finish_say()
	_say("", "It's inspired by slime mould. Yes, actual slime mould. It's surprisingly good at growing connected road networks with multiple routes.")
	await _finish_say()
	var a2 = _group("A")
	_say("", "Then Dijkstra's algorithm finds the shortest path, so the game can compare your route against the best possible one.")
	if a2 != null:
		var best: Array[Vector2i] = game.map.find_path(a2.tile)
		for p in best:
			_ghost.add_point(_tile_pos(p))
			await _wait(0.05)
	await _finish_say()
	_say("", "Every round, the maps get bigger, more teams appear, and the hazards get faster.")
	var ghost_fade := create_tween()
	ghost_fade.tween_property(_ghost, "modulate:a", 0.0, 0.6)
	ghost_fade.tween_callback(_ghost.clear_points)
	if a2 != null:
		await _send(a2, true, 0.08)
	await _finish_say()

	# [2:40] What's next + outro, over the end card. The round is frozen
	# first so the card covers a calm board.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	_layer.move_child(_caption_box, -1)  # captions sit above the end-card fade
	_layer.move_child(_pointer, -1)
	create_tween().tween_property(_pointer, "modulate:a", 0.0, 0.4)
	var to_card := create_tween().set_parallel(true)
	to_card.tween_property(_fade, "color:a", 0.9, 0.8)
	to_card.tween_property(_end_card, "modulate:a", 1.0, 0.8)
	_say("What's next", "And we're just getting started: earthquakes, floods and nonstop fires, plus new maps inspired by Philippine landmarks.")
	await _finish_say()
	_say("", "Also coming: character designs, collectible skills, local and global leaderboards, and a Co-op Duel mode where you and a friend compete for the best evacuation score.")
	await _finish_say()
	_hide_caption()
	_end_line.text = "Stay calm. Think fast. Get everyone home."
	await _wait(3.4)
	_end_line.text = "Thanks for watching. Now go save some people."
	await _wait(3.2)
	var out := create_tween()
	out.tween_property(_fade, "color:a", 1.0, 0.8)
	out.parallel().tween_property(_end_card, "modulate:a", 0.0, 0.8)
	await out.finished
	await _wait(0.4)
	get_tree().quit()
