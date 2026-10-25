extends "res://demo/demo_director.gd"
## Clean gameplay footage for the promo trailer: no captions or highlights,
## just the pointer playing round 1 through round 4. Text, music and
## the cutting are added in the edit. Same Movie Maker workflow as the tutorial
## (demo/README.md); this scene writes its own file.

const PROMO_SEED := 7031


func _ready() -> void:
	super._ready()
	game.rng.seed = PROMO_SEED


## Plays groups home automatically, pressing STOP whenever a team is about to
## walk into fire (lethal from round 2) and rerouting it.
func _autopilot(seconds: float, step_seconds: float) -> void:
	var until := _clock + seconds
	while _clock < until and not game.round_over:
		var danger = game._group_heading_into_fire()
		if danger != null:
			game.selected = null
			game.route.clear()
			game.stop_target = danger
			await _click_button(game.btn_team_stop)
			game._on_team_stop_pressed()
			await _wait(0.3)
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
	await _wait(3.5)                       # menu backdrop
	await _click_button(game.btn_menu_start)
	game._on_start_game_pressed()
	await _wait(1.2)

	# Round 1: a clean plan, a dispatch, a fire that cuts a route, a detour.
	var a = _group("A")
	var b = _group("B")
	await _select_by_marker(a)
	await _draw_route_for(a, 0.11)
	await _press_dispatch()
	await _wait(0.6)
	var b_sent: bool = await _send(b, true, 0.08)
	if b_sent:
		await _wait(0.3)
		_plant_fire_ahead(b)
	await _wait_for(func() -> bool: return b.state == SurvivorGroup.State.BLOCKED or not b.is_active(), 9.0)
	await _wait(0.8)
	if b.can_plan():
		await _send(b, false, 0.09)
	await _bring_everyone_home(30.0)
	await _wait_for(func() -> bool: return game.round_over, 30.0)
	await _wait(3.5)

	# Rounds 2-4: bigger cities, lethal fire, more teams.
	for r in 3:
		if not game.last_round_success:
			break
		await _click_button(game.btn_next)
		game._on_next_pressed()
		await _wait(1.6)
		await _autopilot(50.0, 0.06)
		await _wait_for(func() -> bool: return game.round_over, 10.0)
		await _wait(3.5)

	var out := create_tween()
	out.tween_property(_fade, "color:a", 1.0, 0.6)
	await out.finished
	get_tree().quit()
