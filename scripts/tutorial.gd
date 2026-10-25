class_name Tutorial
extends RefCounted
## Guided first lesson on the hand-authored training map. A coach card at the
## top of the side panel tells the player what to do next and waits for them to
## do it: select a team, draw a route, dispatch, watch it arrive, repeat for the
## second team. Fires are switched off, nothing is scored or banked.
## The game owns one Tutorial and calls tick() every frame while it is active;
## the tutorial only reads game state and drives MapView.guide_tiles.

const UI_COLORS = preload("res://scripts/ui_colors.gd")
const STATE_PATH := "user://tutorial.cfg"

enum Step { INTRO, SELECT, DRAW, DISPATCH, WATCH, SECOND, DONE }
const STEP_COUNT := 6  ## numbered steps shown to the player (DONE is the wrap-up)
const CARD_WIDTH := 440.0
enum Place { CENTER, TOP, BOTTOM }

var active := false
var step := Step.INTRO
var seen := false       ## the first-launch offer was answered
var completed := false  ## the lesson was finished at least once

var _game: Control
var _card: PanelContainer
var _lbl_step: Label
var _lbl_title: Label
var _lbl_body: RichTextLabel
var _btn_next: Button
var _btn_exit: Button
var _done_box: VBoxContainer
var _offer: ColorRect
var _pulse_buttons: Array[Button] = []
var _time := 0.0
var _place := -1
var _fade: Tween


func setup(game: Control, parent: Control) -> void:
	_game = game
	_load()
	_build_card(parent)
	_build_offer()


# --- Entry points --------------------------------------------------------------

## True for a player who has never been offered the lesson and has no history.
func should_offer() -> bool:
	return not seen and _game.best_score <= 0


func show_offer() -> void:
	_offer.visible = true


func begin() -> void:
	active = true
	_offer.visible = false
	_card.visible = true
	_place = -1
	_done_box.visible = false
	_enter(Step.INTRO)


func finish_exit() -> void:
	active = false
	_card.visible = false
	_game.map_view.guide_tiles.clear()
	_clear_pulse()


# --- Per-frame -----------------------------------------------------------------

func tick(delta: float) -> void:
	if not active:
		return
	_time += delta
	var a: SurvivorGroup = _group(0)
	var b: SurvivorGroup = _group(1)
	match step:
		Step.INTRO:
			_guide(_safe_tiles())
		Step.SELECT:
			if _game.selected == a:
				_enter(Step.DRAW)
			else:
				_guide([a.tile])
		Step.DRAW:
			if _game.selected != a:
				_enter(Step.SELECT)
			elif _route_complete():
				_enter(Step.DISPATCH)
			else:
				_guide(_next_tile())
				_lbl_body.text = "Click or drag along the roads, one tile after another, until the route reaches the green SAFE zone.\n[color=#7fe8d2]Route so far: %d tiles. Mistakes are fine: UNDO or CLEAR.[/color]" % (_game.route.size() - 1)
		Step.DISPATCH:
			if a.state == SurvivorGroup.State.MOVING or a.state == SurvivorGroup.State.DELIVERED:
				_enter(Step.WATCH)
			elif _game.selected != a or not _route_complete():
				_enter(Step.DRAW if _game.selected == a else Step.SELECT)
			else:
				_guide([])
				_pulse([_game.btn_team_dispatch])
		Step.WATCH:
			if a.state == SurvivorGroup.State.DELIVERED:
				_enter(Step.SECOND)
			else:
				_guide([])
		Step.SECOND:
			if b.state == SurvivorGroup.State.DELIVERED:
				_complete()
			else:
				_second_team(b)
	_card.reset_size()
	_apply_place()
	if step != Step.DONE:
		_avoid_guide()


func _second_team(b: SurvivorGroup) -> void:
	_clear_pulse()
	if b.state == SurvivorGroup.State.MOVING:
		_guide([])
		_lbl_body.text = "Group B is on its way. Wait for it to reach the SAFE zone."
	elif _game.selected != b:
		_guide([b.tile])
		_lbl_body.text = "Group A is safe! Now rescue Group B: click its marker, draw a route, then DISPATCH."
	elif _route_complete():
		_guide([])
		_pulse([_game.btn_team_dispatch])
		_lbl_body.text = "Route ready. Press DISPATCH (or Enter)."
	else:
		_guide(_next_tile())
		_lbl_body.text = "Draw Group B's route to the SAFE zone. Shorter routes score higher."


# --- Steps ---------------------------------------------------------------------

func _enter(s: Step) -> void:
	step = s
	_clear_pulse()
	_btn_next.visible = s == Step.INTRO
	_lbl_step.text = "TUTORIAL  %d / %d" % [mini(int(s) + 1, STEP_COUNT), STEP_COUNT]
	match s:
		Step.INTRO:
			_lbl_title.text = "WELCOME, OPERATOR"
			_lbl_body.text = "People are trapped in the city. You plan routes; survivor teams follow them to the green SAFE zone (highlighted on the map).\nYou have two teams to rescue."
		Step.SELECT:
			_lbl_title.text = "1. PICK A TEAM"
			_lbl_body.text = "Click the pulsing marker on the map: that is Group A. You can also click its row under YOUR TEAMS."
		Step.DRAW:
			_lbl_title.text = "2. DRAW A ROUTE"
		Step.DISPATCH:
			_lbl_title.text = "3. DISPATCH"
			_lbl_body.text = "The route reaches the SAFE zone. Press the pulsing DISPATCH button (or Enter) to send the team."
		Step.WATCH:
			_lbl_title.text = "4. WATCH IT GO"
			_lbl_body.text = "Group A is walking your route tile by tile. Wait for it to reach the SAFE zone."
		Step.SECOND:
			_lbl_title.text = "5. YOUR TURN"
			_lbl_body.text = ""
		Step.DONE:
			pass
	_game.map_view.guide_tiles.clear()
	_set_place(Place.CENTER if s == Step.INTRO else (Place.TOP if _place == Place.CENTER or _place < 0 else _place))
	_refit()


func _complete() -> void:
	step = Step.DONE
	completed = true
	seen = true
	_save()
	_clear_pulse()
	_game.map_view.guide_tiles.clear()
	_lbl_step.text = "TUTORIAL COMPLETE"
	_lbl_title.text = "WELL DONE, OPERATOR"
	_lbl_body.text = "You know the core loop: [b]select, draw, dispatch[/b].\nIn real rounds a fire starts and spreads along the roads. A team that is stopped by fire needs a detour, and the STOP button halts a moving team. Faster, shorter routes score more."
	_btn_next.visible = false
	_btn_exit.visible = false
	_done_box.visible = true
	_set_place(Place.CENTER)
	_refit()


# --- Helpers -------------------------------------------------------------------

func _group(i: int) -> SurvivorGroup:
	return _game.groups[mini(i, _game.groups.size() - 1)]


func _route_complete() -> bool:
	return _game.selected != null and _game.validation.get("complete", false)


func _next_tile() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _game.route.is_empty():
		return out
	var path: Array[Vector2i] = _game.map.find_path(_game.route[-1])
	if path.size() > 1:
		out.append(path[1])
	return out


func _safe_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in _game.map.height:
		for x in _game.map.width:
			if _game.map.is_safe(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func _guide(tiles: Array) -> void:
	_game.map_view.guide_tiles.clear()
	for t in tiles:
		_game.map_view.guide_tiles.append(t)


func _pulse(buttons: Array) -> void:
	_pulse_buttons.clear()
	for b in buttons:
		_pulse_buttons.append(b)
	var k := 0.5 + 0.5 * sin(_time * 7.0)
	for b in _pulse_buttons:
		b.self_modulate = Color.WHITE.lerp(Color(1.6, 1.6, 1.6), k)


func _clear_pulse() -> void:
	for b in _pulse_buttons:
		if is_instance_valid(b):
			b.self_modulate = Color.WHITE
	_pulse_buttons.clear()


func _on_next() -> void:
	_enter(Step.SELECT)


func _on_exit() -> void:
	_game._exit_tutorial()


func _on_play() -> void:
	finish_exit()
	_game._on_start_game_pressed()


func _on_replay() -> void:
	_game._start_tutorial()


func _on_menu() -> void:
	_game._exit_tutorial()


func _on_offer_yes() -> void:
	seen = true
	_save()
	_game._start_tutorial()


func _on_offer_no() -> void:
	seen = true
	_save()
	_offer.visible = false
	_game._on_start_game_pressed()


# --- Persistence ---------------------------------------------------------------

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) == OK:
		seen = bool(cfg.get_value("tutorial", "seen", false))
		completed = bool(cfg.get_value("tutorial", "completed", false))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tutorial", "seen", seen)
	cfg.set_value("tutorial", "completed", completed)
	cfg.save(STATE_PATH)


# --- UI ------------------------------------------------------------------------

func _build_card(parent: Control) -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _popup_style())
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_card.z_index = 60
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	parent.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_lbl_step = _game._label("TUTORIAL  1 / %d" % STEP_COUNT, 12, UI_COLORS.ACCENT_TEAL)
	_lbl_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_lbl_step)
	_btn_exit = _game._button("EXIT", _on_exit)
	_btn_exit.custom_minimum_size = Vector2(60, 26)
	_game._set_secondary_button_styles(_btn_exit)
	head.add_child(_btn_exit)
	_lbl_title = _game._label("", 20, UI_COLORS.TEXT_PRIMARY)
	box.add_child(_lbl_title)
	_lbl_body = RichTextLabel.new()
	_lbl_body.bbcode_enabled = true
	_lbl_body.fit_content = true
	_lbl_body.scroll_active = false
	_lbl_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_body.add_theme_font_size_override("normal_font_size", 14)
	_lbl_body.add_theme_color_override("default_color", UI_COLORS.TEXT_PRIMARY)
	box.add_child(_lbl_body)
	_btn_next = _game._button("NEXT  >>", _on_next)
	_btn_next.custom_minimum_size.y = 40
	_game._set_dispatch_button_styles(_btn_next)
	box.add_child(_btn_next)
	_done_box = VBoxContainer.new()
	_done_box.add_theme_constant_override("separation", 6)
	_done_box.visible = false
	box.add_child(_done_box)
	var play: Button = _game._button("START GAME", _on_play)
	play.custom_minimum_size.y = 44
	_game._set_dispatch_button_styles(play)
	_done_box.add_child(play)
	var replay: Button = _game._button("REPLAY TUTORIAL", _on_replay)
	_game._set_secondary_button_styles(replay)
	_done_box.add_child(replay)
	var menu: Button = _game._button("MAIN MENU", _on_menu)
	_game._set_secondary_button_styles(menu)
	_done_box.add_child(menu)


func _build_offer() -> void:
	_offer = ColorRect.new()
	_offer.color = Color(UI_COLORS.BG_DARK, 0.9)
	_offer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_offer.mouse_filter = Control.MOUSE_FILTER_STOP
	_offer.z_index = 220
	_offer.visible = false
	_game.add_child(_offer)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(460, 0)
	card.add_theme_stylebox_override("panel", _game._style(UI_COLORS.BG_PANEL, UI_COLORS.ACCENT_TEAL, 14, 2, 24))
	_offer.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var title: Label = _game._label("NEW HERE?", 28, UI_COLORS.ACCENT_TEAL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text: Label = _game._wrap_label(15, UI_COLORS.TEXT_PRIMARY)
	text.text = "Try a quick guided practice round (about 2 minutes). No fire, no score: just learn how to send teams to safety."
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	var yes: Button = _game._button("PLAY TUTORIAL", _on_offer_yes)
	yes.custom_minimum_size.y = 54
	_game._set_dispatch_button_styles(yes)
	box.add_child(yes)
	var no: Button = _game._button("SKIP, START GAME", _on_offer_no)
	no.custom_minimum_size.y = 44
	_game._set_secondary_button_styles(no)
	box.add_child(no)


# --- Pop-up placement ------------------------------------------------------------

func _popup_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = _game._style(UI_COLORS.BG_PANEL, UI_COLORS.ACCENT_TEAL, 10, 2, 14)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 14
	return sb


## Puts the pop-up at the top, bottom or centre of the map area.
func _set_place(mode: int) -> void:
	if mode == _place:
		return
	_place = mode
	_apply_place()


## Anchors the pop-up to its edge. Re-applied every frame because its height
## changes with the text and only settles after the first layout pass.
func _apply_place() -> void:
	match _place:
		Place.CENTER:
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
			_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_card.grow_vertical = Control.GROW_DIRECTION_BOTH
		Place.TOP:
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 14)
			_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_card.grow_vertical = Control.GROW_DIRECTION_END
		Place.BOTTOM:
			_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
			_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_card.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Moves the pop-up to the other edge when it would cover a highlighted tile.
func _avoid_guide() -> void:
	if _place == Place.CENTER or _game.map_view.guide_tiles.is_empty():
		return
	var covered := _card.get_rect().grow(20.0)
	for t in _game.map_view.guide_tiles:
		if covered.has_point(_game.map_view.tile_center(t)):
			_set_place(Place.BOTTOM if _place == Place.TOP else Place.TOP)
			return


func _refit() -> void:
	_card.reset_size()
	if _fade != null and _fade.is_running():
		_fade.kill()
	_card.modulate.a = 0.0
	_fade = _card.create_tween()
	_fade.tween_property(_card, "modulate:a", 1.0, 0.2)
