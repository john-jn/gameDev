extends SceneTree
## Plays the guided tutorial through the real game scene and checks every step.
## godot --headless --path . --script res://tests/test_tutorial.gd

var checks := 0
var failures := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL: ", msg)


## Frames in which the game node has processed (process_frame fires before _process).
func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	var t: Tutorial = game.tutorial
	t.seen = false
	t.completed = false
	game.best_score = 0

	print("[tutorial] first-launch offer")
	check(t.should_offer(), "new player should be offered the tutorial")
	game._on_start_game_pressed()
	check(not game.game_started, "START GAME waits for the offer to be answered")
	game.best_score = 50
	check(not t.should_offer(), "a player with a best score is not offered the tutorial")
	game.best_score = 0

	print("[tutorial] play-through")
	game._start_tutorial()
	check(t.active and game.game_started and game.round_num == 1, "tutorial starts on round 1")
	check(game.map.fires.is_empty(), "no fire in the tutorial map")
	check(game.groups.size() == 2, "training map has two teams")
	check(t.step == Tutorial.Step.INTRO, "starts at the intro")
	await process_frame
	t._on_next()
	check(t.step == Tutorial.Step.SELECT, "NEXT moves to SELECT")
	await process_frame
	check(game.map_view.guide_tiles.size() == 1 and game.map_view.guide_tiles[0] == game.groups[0].tile, "SELECT points at Group A")

	game._select_group(game.groups[0])
	await process_frame
	check(t.step == Tutorial.Step.DRAW, "selecting A moves to DRAW")
	var path: Array[Vector2i] = game.map.find_path(game.groups[0].tile)
	for i in range(1, path.size()):
		game._try_extend(path[i])
		await process_frame
	await _frames(3)
	check(t.step == Tutorial.Step.DISPATCH, "a complete route moves to DISPATCH")
	game._dispatch()
	await process_frame
	await _frames(3)
	check(t.step == Tutorial.Step.WATCH, "dispatching moves to WATCH")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		if t.step != Tutorial.Step.WATCH:
			break
	check(t.step == Tutorial.Step.SECOND, "Group A arriving moves to the second team")
	check(game.groups[0].state == SurvivorGroup.State.DELIVERED, "Group A was delivered")

	game._select_group(game.groups[1])
	var path_b: Array[Vector2i] = game.map.find_path(game.groups[1].tile)
	for i in range(1, path_b.size()):
		game._try_extend(path_b[i])
	await process_frame
	game._dispatch()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		if t.step == Tutorial.Step.DONE:
			break
	check(t.step == Tutorial.Step.DONE, "Group B arriving completes the tutorial")
	check(t.completed and t.seen, "completion is remembered")
	check(not game.round_over and game.banked_score == 0, "nothing is scored or banked")

	print("[tutorial] exit")
	game._exit_tutorial()
	check(not t.active and not game.game_started, "exit returns to the menu")
	check(game.map_view.guide_tiles.is_empty(), "guide highlights are cleared on exit")
	check(not t.should_offer(), "the offer is not shown again after completion")

	# Do not leave test state in the player's save file.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Tutorial.STATE_PATH))
	print("==== %d checks, %d failures ====" % [checks, failures])
	quit(1 if failures > 0 else 0)
