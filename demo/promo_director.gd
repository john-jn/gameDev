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



## Draws the city being generated, on the same tile grid as the map view:
## the Physarum trail and agents, then roads appearing stage by stage.
class BuildView extends Control:
	const BG := Color("0a1f23")
	const GRIDC := Color(0.16, 0.36, 0.36, 0.35)
	const ROAD := Color("2a8f78")
	const AVENUE := Color("96f2d8")
	const VEIN := Color("ffc24d")
	const PARK := Color("2f6b45")
	var mv
	var sub := 2
	var sim_w := 0
	var sim_h := 0
	var trail := PackedFloat32Array()
	var trail_ref := 1.0
	var trail_alpha := 1.0
	var agents := PackedVector2Array()
	var foods: Array = []
	var safe := Rect2i()
	var roads := {}      ## Vector2i -> [appear time, color]
	var removed := {}    ## Vector2i -> fade-out start
	var parks := {}      ## Vector2i -> appear time
	var t := 0.0
	var _tex: ImageTexture   ## kept alive until the frame is drawn

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BG)
		if mv == null or mv.map == null:
			return
		var ts: float = mv._ts
		var org: Vector2 = mv._origin
		var mw: int = mv.map.width
		var mh: int = mv.map.height
		for x in mw + 1:
			draw_line(org + Vector2(x * ts, 0), org + Vector2(x * ts, mh * ts), GRIDC, 1.0)
		for y in mh + 1:
			draw_line(org + Vector2(0, y * ts), org + Vector2(mw * ts, y * ts), GRIDC, 1.0)
		if trail_alpha > 0.01 and trail.size() > 0:
			var img := Image.create(sim_w, sim_h, false, Image.FORMAT_RGBA8)
			for cy in sim_h:
				for cx in sim_w:
					var v := sqrt(clampf(trail[cy * sim_w + cx] / trail_ref, 0.0, 1.0))
					var c := Color("1c8270").lerp(Color("c8fff0"), v)
					c.a = clampf(v * 1.2, 0.0, 1.0) * trail_alpha
					img.set_pixel(cx, cy, c)
			if _tex == null or _tex.get_width() != sim_w:
				_tex = ImageTexture.create_from_image(img)
			else:
				_tex.update(img)
			draw_texture_rect(_tex, Rect2(org, Vector2(mw, mh) * ts), false)
			for a in agents:
				draw_rect(Rect2(org + a * ts - Vector2(1, 1), Vector2(2, 2)), Color(0.85, 1.0, 0.95, 0.55 * trail_alpha))
			for f in foods:
				draw_circle(org + (Vector2(f) + Vector2(0.5, 0.5)) * ts, ts * 0.22, Color(VEIN, trail_alpha))
		for p in parks:
			var a := clampf((t - parks[p]) / 0.3, 0.0, 1.0)
			if a > 0.0:
				draw_rect(mv.tile_rect(p).grow(-1.0), Color(PARK, a))
		for p in roads:
			var info: Array = roads[p]
			var a := clampf((t - info[0]) / 0.22, 0.0, 1.0)
			if removed.has(p):
				a *= 1.0 - clampf((t - removed[p]) / 0.35, 0.0, 1.0)
			if a <= 0.0:
				continue
			var c: Color = info[1]
			draw_rect(mv.tile_rect(p).grow(-1.0), Color(c, a))
		var sr := Rect2(org + Vector2(safe.position) * ts, Vector2(safe.size) * ts)
		draw_rect(sr, Color("5cff9d", 0.18))
		draw_rect(sr, Color("5cff9d"), false, 3.0)
		var cc := sr.get_center()
		draw_line(cc - Vector2(ts * 0.6, 0), cc + Vector2(ts * 0.6, 0), Color("5cff9d"), 4.0)
		draw_line(cc - Vector2(0, ts * 0.6), cc + Vector2(0, ts * 0.6), Color("5cff9d"), 4.0)


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



func _road_set(m: CityMap) -> Dictionary:
	var out := {}
	for y in m.height:
		for x in m.width:
			if m.get_tile(Vector2i(x, y)) == CityMap.Tile.ROAD:
				out[Vector2i(x, y)] = true
	return out


## Replays the round's own map generation (same seed, same attempt, same RNG
## order as MapGenerator._try_physarum) and animates each stage over the map,
## then fades away to reveal the identical, real map the round is played on.
func _build_city_sequence() -> void:
	var info: Dictionary = game.map.gen_info
	if str(info.get("source", "")) != "physarum":
		_mark("build_skipped_not_physarum")
		return
	var round_num: int = game.round_num
	var rng2 := MapGenerator.attempt_rng(int(info["seed"]), round_num, int(info["attempt"]))
	var size := MapGenerator.map_size_for(round_num, rng2)
	var m := CityMap.new()
	m.setup(size.x, size.y, CityMap.Tile.BUILDING)
	var safe := MapGenerator._place_safe_zone(m, rng2)
	var radius := clampf(minf(size.x, size.y) * 0.12, 1.5, 3.0)
	var center := PhysarumSim.pick_center(size.x, size.y, radius, MapGenerator.CENTER_MARGIN, rng2, safe, MapGenerator.CENTER_SAFE_DIST)
	var center_tile := Vector2i(clampi(floori(center.x), 0, size.x - 1), clampi(floori(center.y), 0, size.y - 1))
	var safe_entry := MapGenerator._safe_entry(m, safe, center)
	var foods := MapGenerator._scatter_foods(m, rng2, safe)
	var food_tiles: Array[Vector2i] = [safe_entry]
	var weights: Array[float] = [3.0]
	for f in foods:
		food_tiles.append(f)
		weights.append(1.0)
	var sim := PhysarumSim.new()
	sim.setup(size.x, size.y, center, radius, food_tiles, weights)

	var view := BuildView.new()
	view.mv = game.map_view
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 200
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.sub = sim.sub
	view.sim_w = size.x * sim.sub
	view.sim_h = size.y * sim.sub
	view.safe = safe
	view.foods = foods
	game.map_view.get_parent().add_child(view)
	game.map_view._update_layout()
	var s0 := _road_set(m)
	for p in s0:
		view.roads[p] = [0.0, Color("2a8f78")]

	# 1. The slime mould grows: exactly PhysarumSim.run(), one step per frame.
	_mark("build_sim")
	sim._spawn(rng2)
	var reach := 0.0
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), Vector2(size.x, size.y)]:
		reach = maxf(reach, center.distance_to(corner))
	sim.steps_run = clampi(sim.base_steps + ceili(reach * sim.sub / sim.step_size), sim.base_steps, sim.max_steps)
	for step in sim.steps_run:
		sim._emit_food()
		sim._move_agents(rng2)
		sim._diffuse()
		var tr: PackedFloat32Array = sim._trail
		var sorted := tr.duplicate()
		sorted.sort()
		view.trail = tr
		view.trail_ref = maxf(sorted[int(sorted.size() * 0.97)], 0.001)
		view.agents = sim.agent_positions()
		view.queue_redraw()
		await get_tree().process_frame
	var trail := sim.tile_trail()

	# 2. The street plan; Physarum picks the avenues.
	_mark("build_grid")
	var city_info := MapGenerator._lay_city_grid(m, round_num, trail, rng2)
	var s2 := _road_set(m)
	var add2: Array = []
	for p in s2:
		if not view.roads.has(p):
			add2.append(p)
	add2.sort_custom(func(a, b) -> bool: return Vector2(a).distance_to(Vector2(center_tile)) < Vector2(b).distance_to(Vector2(center_tile)))
	var ax: int = city_info["avenue_x"]
	var ay: int = city_info["avenue_y"]
	for i in add2.size():
		var p: Vector2i = add2[i]
		var is_avenue := (p.x >= ax and p.x < ax + MapGenerator.CITY_AVENUE_WIDTH) or (p.y >= ay and p.y < ay + MapGenerator.CITY_AVENUE_WIDTH)
		view.roads[p] = [view.t + 1.5 * i / maxf(add2.size(), 1.0), Color("96f2d8") if is_avenue else Color("2a8f78")]
	await _animate_view(view, 1.9, 1.0, 0.45)

	# 3. Roads follow the veins.
	_mark("build_carve")
	var nodes: Array[Vector2i] = [safe_entry, center_tile]
	for f in foods:
		if not nodes.has(f):
			nodes.append(f)
	for j in MapGenerator._trail_junctions(m, trail, nodes, maxi(2, foods.size() >> 1)):
		nodes.append(j)
	MapGenerator._carve_links(m, trail, nodes)
	var s3 := _road_set(m)
	var add3: Array = []
	for p in s3:
		if not view.roads.has(p):
			add3.append(p)
	add3.sort_custom(func(a, b) -> bool: return trail[a.y * size.x + a.x] > trail[b.y * size.x + b.x])
	for i in add3.size():
		view.roads[add3[i]] = [view.t + 1.0 * i / maxf(add3.size(), 1.0), Color("ffc24d")]
	await _animate_view(view, 1.4, 0.45, 0.3)

	# 4. Clean-up: detours added, blobs thinned, dead ends pruned, parks.
	_mark("build_clean")
	MapGenerator._keep_safe_component(m)
	MapGenerator._thin_blobs(m)
	MapGenerator._reinforce(m, trail)
	MapGenerator._thin_blobs(m)
	MapGenerator._prune_dead_ends(m)
	MapGenerator._sprinkle_parks(m, rng2)
	var s4 := _road_set(m)
	for p in view.roads.keys():
		if not s4.has(p):
			view.removed[p] = view.t + 0.2
	for p in s4:
		if not view.roads.has(p):
			view.roads[p] = [view.t, Color("2a8f78")]
	for y in m.height:
		for x in m.width:
			if m.get_tile(Vector2i(x, y)) == CityMap.Tile.PARK:
				view.parks[Vector2i(x, y)] = view.t + 0.2
	await _animate_view(view, 1.1, 0.3, 0.0)

	# Check the replay against the real map before revealing it.
	var mismatch := 0
	for y in m.height:
		for x in m.width:
			var p := Vector2i(x, y)
			var real: int = game.map.get_tile(p)
			if game.map.is_road_closure(p):
				real = CityMap.Tile.ROAD
			if real != m.get_tile(p):
				mismatch += 1
	_marks.append({"name": "build_mismatch_tiles", "t": mismatch, "size": [size.x, size.y]})

	# 5. Reveal the real city underneath.
	_mark("build_reveal")
	var fade := create_tween()
	fade.tween_property(view, "modulate:a", 0.0, 0.9)
	await fade.finished
	view.queue_free()


func _animate_view(view, seconds: float, trail_from: float, trail_to: float) -> void:
	var t0: float = view.t
	while view.t < t0 + seconds:
		await get_tree().process_frame
		view.t += get_process_delta_time()
		view.trail_alpha = lerpf(trail_from, trail_to, clampf((view.t - t0) / seconds, 0.0, 1.0))
		view.queue_redraw()


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
		if r == 0:
			# Hold the round while its own city is generated on screen.
			game.process_mode = Node.PROCESS_MODE_DISABLED
			game.map_view.process_mode = Node.PROCESS_MODE_ALWAYS   # keep drawing the new city underneath
			_cam_at(_map_center_local(), 1.12, 3.0)
			_mark("r2_build")
			await _build_city_sequence()
			game.process_mode = Node.PROCESS_MODE_INHERIT
			game.map_view.process_mode = Node.PROCESS_MODE_INHERIT
			_cam_wide(1.5)
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
