extends "res://demo/demo_director.gd"
## Clean gameplay footage for the promo trailer, with an in-engine camera:
## the whole game view is scaled and panned (crisp, since it renders at the
## new scale) to track teams, snap to hazards and dolly across big cities.
## No captions; text, music and cuts are added in the edit. Shot times are
## written to demo_output/promo_marks.json for the editor.

const PROMO_SEED := 7031
const VIEW := Vector2(1280, 800)

var _cam_z := 1.0
var _cam_focus := Vector2(640, 400)     ## game-local point at the screen centre
var _cam_target_z := 1.0
var _cam_target_focus := Vector2(640, 400)
var _cam_follow = null                   ## SurvivorGroup to track, or null
var _cam_speed := 4.0
var _marks: Array = []


func _ready() -> void:
	super._ready()
	game.rng.seed = PROMO_SEED


func _process(delta: float) -> void:
	super._process(delta)
	if game == null:
		return
	if _cam_follow != null and _cam_follow.is_active():
		_cam_target_focus = _group_local(_cam_follow)
	var k := 1.0 - exp(-_cam_speed * delta)
	_cam_z = lerpf(_cam_z, _cam_target_z, k)
	_cam_focus = _cam_focus.lerp(_cam_target_focus, k)
	var pos := VIEW * 0.5 - _cam_focus * _cam_z
	pos.x = clampf(pos.x, VIEW.x - VIEW.x * _cam_z, 0.0)
	pos.y = clampf(pos.y, VIEW.y - VIEW.y * _cam_z, 0.0)
	game.scale = Vector2(_cam_z, _cam_z)
	game.position = pos
	# The pointer only shows on wide shots; zoomed shots are pure camera.
	_pointer.visible = _cam_z < 1.08


func _click_at(pos: Vector2) -> void:
	if _cam_z >= 1.08:
		_pointer.position = pos
		await _wait(0.12)
		return
	await super._click_at(pos)


func _group_local(g) -> Vector2:
	var mv = game.map_view
	var p: Vector2 = mv.grid_to_screen(g.draw_position())
	return game.get_global_transform().affine_inverse() * (mv.get_global_transform() * p)


func _tile_local(p: Vector2i) -> Vector2:
	var mv = game.map_view
	return game.get_global_transform().affine_inverse() * (mv.get_global_transform() * mv.tile_center(p))


func _map_center_local() -> Vector2:
	var r: Rect2 = game.map_frame.get_global_rect()
	return game.get_global_transform().affine_inverse() * r.get_center()


func _cam_wide(speed: float = 3.0) -> void:
	_cam_follow = null
	_cam_target_z = 1.0
	_cam_target_focus = VIEW * 0.5
	_cam_speed = speed


func _cam_track(g, z: float, speed: float) -> void:
	_cam_follow = g
	_cam_target_z = z
	_cam_speed = speed


func _cam_at(local_point: Vector2, z: float, speed: float) -> void:
	_cam_follow = null
	_cam_target_focus = local_point
	_cam_target_z = z
	_cam_speed = speed


func _mark(name: String) -> void:
	_marks.append({"name": name, "t": snappedf(_clock, 0.01)})


func _save_marks() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://demo_output/promo_marks.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_marks, " "))
		f.close()


## A slow dolly across the map at zoom `z`, from `from_frac` to `to_frac`
## (fractions of the map frame), over `seconds`. Runs alongside play.
func _dolly(z: float, from_frac: Vector2, to_frac: Vector2, seconds: float) -> void:
	var r: Rect2 = game.map_frame.get_global_rect()
	var inv: Transform2D = game.get_global_transform().affine_inverse()
	var a: Vector2 = inv * (r.position + r.size * from_frac)
	var b: Vector2 = inv * (r.position + r.size * to_frac)
	_cam_follow = null
	_cam_target_z = z
	_cam_speed = 2.2
	var t := 0.0
	while t < seconds and _cam_follow == null:
		_cam_target_focus = a.lerp(b, smoothstep(0.0, 1.0, t / seconds))
		await get_tree().process_frame
		t += get_process_delta_time()


## Plays groups home automatically. A team about to walk into fire gets the
## camera snapped onto it, a STOP, and a reroute.
func _autopilot(seconds: float, step_seconds: float, round_label: String) -> void:
	var until := _clock + seconds
	var stops := 0
	while _clock < until and not game.round_over:
		var danger = game._group_heading_into_fire()
		if danger != null:
			stops += 1
			_mark("%s_stop%d" % [round_label, stops])
			_cam_track(danger, 2.3, 10.0)
			game.selected = null
			game.route.clear()
			game.stop_target = danger
			await _wait(0.35)
			await _click_button(game.btn_team_stop)
			game._on_team_stop_pressed()
			await _wait(0.5)
			if danger.can_plan():
				await _send(danger, false, step_seconds)
			await _wait(1.2)
			_cam_wide(3.0)
			continue
		var acted := false
		for g in game.groups:
			if game.round_over:
				break
			if g.can_plan():
				var sent: bool = await _send(g, false, step_seconds)
				if sent:
					acted = true
					break
		if not acted:
			await _wait(0.25)


func _run() -> void:
	_caption_box.visible = false
	_mark("menu")
	await _wait(3.5)
	await _click_button(game.btn_menu_start)
	game._on_start_game_pressed()
	await _wait(1.2)

	# Round 1. Wide while drawing; on DISPATCH the camera swoops in and tracks A.
	var a = _group("A")
	var b = _group("B")
	_mark("r1_draw_a")
	await _select_by_marker(a)
	await _draw_route_for(a, 0.11)
	await _press_dispatch()
	_mark("r1_dispatch_a")
	_cam_track(a, 2.4, 3.2)
	await _wait_for(func() -> bool: return not a.is_active(), 14.0)
	_mark("r1_a_safe")
	await _wait(1.0)
	_cam_wide(3.5)
	await _wait(0.8)

	# B sets off; the camera finds the fire warning, then snaps to B when it halts.
	_mark("r1_send_b")
	var b_sent: bool = await _send(b, true, 0.08)
	var warn := CityMap.NO_TILE
	if b_sent:
		await _wait(0.3)
		warn = _plant_fire_ahead(b)
	if warn != CityMap.NO_TILE:
		_mark("r1_fire_warning")
		_cam_at(_tile_local(warn), 2.0, 4.0)
	await _wait_for(func() -> bool: return b.state == SurvivorGroup.State.BLOCKED or not b.is_active(), 9.0)
	_mark("r1_b_blocked")
	_cam_track(b, 2.8, 14.0)
	await _wait(1.6)
	_cam_wide(4.0)
	await _wait(1.1)
	_mark("r1_detour")
	if b.can_plan():
		await _send(b, false, 0.09)
		_cam_track(b, 1.7, 3.0)
	await _bring_everyone_home(30.0)
	await _wait_for(func() -> bool: return game.round_over, 30.0)
	_cam_wide(4.0)
	_mark("r1_complete")
	await _wait(3.5)

	# Rounds 2-4: dollies across the growing cities while the autopilot plays.
	var dollies := [
		[1.5, Vector2(0.25, 0.3), Vector2(0.75, 0.7), 6.0],
		[1.7, Vector2(0.2, 0.75), Vector2(0.8, 0.25), 7.0],
		[1.6, Vector2(0.8, 0.3), Vector2(0.2, 0.7), 7.0],
	]
	for r in 3:
		if not game.last_round_success:
			break
		await _click_button(game.btn_next)
		game._on_next_pressed()
		var label := "r%d" % (r + 2)
		_mark(label + "_start")
		await _wait(1.2)
		var d: Array = dollies[r]
		_mark(label + "_dolly")
		_dolly(d[0], d[1], d[2], d[3])
		await _autopilot(50.0, 0.06, label)
		await _wait_for(func() -> bool: return game.round_over, 10.0)
		_cam_wide(4.0)
		_mark(label + "_complete")
		await _wait(3.5)

	_mark("end")
	_save_marks()
	var out := create_tween()
	out.tween_property(_fade, "color:a", 1.0, 0.6)
	await out.finished
	get_tree().quit()
