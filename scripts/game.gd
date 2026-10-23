extends Control
## Evac Grid - main controller.
## Owns round state and wires the pieces together:
##   MapGenerator -> CityMap      layout, hazards, BFS pathfinding
##   MapView                      drawing + pointer input -> route editing here
##   RouteValidator               route legality checks
##   SurvivorGroup                tile-by-tile movement
##   HazardManager                fires that cut active routes
##   ScoreKeeper                  transparent scoring
## The tablet UI is built in code so the scene file stays minimal.
## The map's look is one VisualTheme, picked here (see `visual_style`) and
## handed to MapView and the legend; nothing else depends on it.

const UI_COLORS = preload("res://scripts/ui_colors.gd")

var COL_PANEL := UI_COLORS.BG_PANEL
var COL_PANEL_EDGE := UI_COLORS.TEAL
var COL_MODULE := UI_COLORS.BG_PANEL
var COL_MODULE_EDGE := UI_COLORS.TEAL
var COL_TEXT := UI_COLORS.TEXT_PRIMARY
var COL_DIM := UI_COLORS.TEXT_SECONDARY
var COL_ACCENT := UI_COLORS.ACCENT_TEAL
var COL_ALERT := UI_COLORS.DANGER
var COL_OK := UI_COLORS.SUCCESS
var COL_WARN := UI_COLORS.WARNING
const LOG_LINES := 6
const LOG_SHOWN := 3
const MAX_STRIKES := 6
const DIFFICULTY_NAMES := ["Training", "Easy", "Moderate", "Hard", "Severe", "Extreme"]
const BUTTONS_SHEET := preload("res://assets/art/buttons_sheet.png")
const LOGO_TEXTURE := preload("res://ui/logo_header_1x.png")
const STAR_SHEET := preload("res://assets/art/star_icons_sheet.png")
const ALERT_TEXTURE := preload("res://assets/art/alert_icon.png")
const TABLET_FRAME_TEXTURE := preload("res://ui/tablet_frame_slim.png")
const GROUP_A_TEXTURE := preload("res://ui/group_a_light.png")
const GROUP_B_TEXTURE := preload("res://ui/group_b_light.png")
const PEOPLE_LOST_EMPTY_TEXTURE := preload("res://ui/people_lost_empty.png")
const PEOPLE_LOST_FILLED_TEXTURE := preload("res://ui/people_lost_filled.png")
const UI_THEME := preload("res://ui_theme.tres")
const SCANLINE_SHADER := preload("res://ui/scanline_overlay.gdshader")
const ALERT_FLASH_SHADER := preload("res://ui/alert_flash.gdshader")


## Small legend icon that reuses the map's own symbol painters.
class Swatch extends Control:
	const LEGEND_SHEET := preload("res://assets/art/legend_icons_sheet.png")

	var kind := ""
	var visual_theme: VisualTheme

	func _init(p_kind: String, p_theme: VisualTheme) -> void:
		kind = p_kind
		visual_theme = p_theme
		custom_minimum_size = Vector2(32, 32)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sprite_index: int = {"fire": 0, "smoke": 1, "road": 2, "survivor": 3}.get(kind, -1)
		if sprite_index >= 0:
			draw_texture_rect_region(LEGEND_SHEET, Rect2(Vector2.ZERO, size),
					Rect2(sprite_index * 32, 0, 32, 32), UiPalette.CYAN)
			return
		MapPainter.draw_legend_symbol(self, visual_theme, kind, Rect2(Vector2.ZERO, size), get_theme_default_font())


## Map look at start-up; V switches between the two in game, and
## `godot -- --visual=debug` (or `dispatch`) overrides it from the command line.
@export var visual_style: VisualTheme.Style = VisualTheme.Style.DISPATCH_STYLE
## Optional theme resource (.tres) used instead of the built-in preset whose
## style it matches, e.g. one with art in its asset slots.
@export var visual_theme_override: VisualTheme

var rng := RandomNumberGenerator.new()
var round_num := 1
var banked_score := 0
var last_round_success := false

var map: CityMap
var groups: Array[SurvivorGroup] = []
var hazards := HazardManager.new()
var scorer := ScoreKeeper.new()
var selected: SurvivorGroup = null
var route: Array[Vector2i] = []
var validation: Dictionary = {}
var round_time := 0.0
var plan_clock_start := 0.0  ## planning time is measured from round start / last dispatch
var round_over := false
var log_lines: Array[String] = []
var visual_theme: VisualTheme

var map_view: MapView
var map_frame: PanelContainer
var legend: GridContainer
var lbl_round: Label
var lbl_time: Label
var lbl_plan: Label
var lbl_score: Label
var lbl_route: Label
var lbl_hint: Label
var lbl_log: RichTextLabel
var group_box: VBoxContainer
var group_icons: Array[TextureRect] = []
var group_btns: Array[Button] = []
var route_led: UiWidgets.Led
var strike_icons: Array[TextureRect] = []
var help_box: VBoxContainer
var alert_led: TextureRect
var btn_dispatch: Button
var btn_undo: Button
var btn_clear: Button
var alert_panel: PanelContainer
var lbl_alert: Label
var hint_panel: PanelContainer
var _juice_flash: ColorRect
var result_panel: PanelContainer
var lbl_result_title: Label
var lbl_result_sub: Label
var lbl_result_saved: Label
var lbl_result_total: Label
var result_banner: PanelContainer
var result_led: UiWidgets.Led
var result_stars: Array[TextureRect] = []
var result_pips: HFlowContainer
var result_grid: GridContainer
var lbl_result_note: Label
var btn_next: Button
var first_successful_dispatch := false
var _styled_selected: SurvivorGroup
var lbl_score_popup: Label
var _score_target := 0
var _animated_score := 0.0
var _score_tween: Tween


func _ready() -> void:
	# `godot -- --seed=N` replays a whole session (maps and hazards) for debugging.
	rng.randomize()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed=") and arg.substr(7).is_valid_int():
			rng.seed = arg.substr(7).to_int()
		elif arg == "--visual=debug":
			visual_style = VisualTheme.Style.DEBUG_SHAPES
		elif arg == "--visual=dispatch":
			visual_style = VisualTheme.Style.DISPATCH_STYLE
	_build_ui()
	set_visual_style(visual_style)
	_start_round()


# --- Round flow -----------------------------------------------------------------

func _start_round() -> void:
	map = MapGenerator.build_round(round_num, rng)
	groups.clear()
	for i in map.survivor_starts.size():
		groups.append(SurvivorGroup.new(i, char(65 + i), map.survivor_starts[i], map.survivor_sizes[i]))
	hazards = HazardManager.new()
	hazards.setup(round_num, rng)
	scorer = ScoreKeeper.new()
	selected = null
	route.clear()
	round_time = 0.0
	plan_clock_start = 0.0
	round_over = false
	log_lines.clear()
	map_view.reset_effects()
	_build_group_rows()
	result_panel.visible = false
	alert_panel.visible = false
	_log("Round %d (%s): %d groups, %d fire(s) on map, %d timed alert(s) incoming." % [
		round_num, _difficulty_name(), groups.size(), map.fires.size(), hazards.events_remaining])
	# MapGenerator.build_from_seed(round, seed) rebuilds this exact map.
	print("Evac Grid round %d map: %s" % [round_num, map.gen_info])
	_notify("Tap a green survivor marker to start planning. The plan clock is running!", COL_ACCENT)
	_update_ui()


func _process(delta: float) -> void:
	if map == null:
		return
	if not round_over:
		round_time += delta
		for g in groups:
			for ev in g.step(delta, map):
				_on_group_event(g, ev)
		var fire := hazards.update(delta, map, groups)
		if fire != CityMap.NO_TILE:
			_on_hazard(fire)
		_check_round_end()
	_update_ui()


func _on_group_event(g: SurvivorGroup, ev: Dictionary) -> void:
	var tile: Vector2i = ev["tile"]
	match ev["type"]:
		"halted":
			_log("Group %s stopped at (%d, %d) before the fire." % [g.label, tile.x, tile.y])
			# Auto-select the stranded group unless the operator is mid-plan elsewhere.
			if selected == null or route.size() <= 1:
				_select_group(g)
				_notify("Group %s halted. Draw a detour from its position, then DISPATCH." % g.label, COL_ALERT)
		"casualty":
			var pts := scorer.record_casualty()
			map_view.popup(tile, "-1 survivor (%d)" % pts, COL_ALERT)
			_show_score_popup(pts)
			_play_loss_feedback(scorer.lost - 1)
			_log("Group %s lost a survivor in smoke (%d)." % [g.label, pts])
		"delivered":
			var res := scorer.record_delivery(g)
			var points: int = int(res["rescue"]) + int(res["efficiency"])
			map_view.popup(tile, "+%d" % points, COL_OK)
			map_view.play_safe_burst(tile, UI_COLORS.SUCCESS)
			_show_score_popup(points)
			_log("Group %s SAFE: %d survivors (+%d), efficiency %d%% (+%d)." % [
				g.label, g.survivors, res["rescue"], roundi(res["ratio"] * 100.0), res["efficiency"]])
		"lost":
			_log("Group %s was lost in the smoke." % g.label)


func _on_hazard(fire: Vector2i) -> void:
	map_view.popup(fire, "FIRE!", COL_ALERT)
	_trigger_juice_alert()
	var hit: Array[String] = []
	for g in groups:
		if g.remaining_contains(fire):
			g.request_halt(fire, round_time)
			hit.append(g.label)
	if hit.is_empty():
		_log("Fire reported at (%d, %d)." % [fire.x, fire.y])
	else:
		_log("ALERT: fire at (%d, %d) cuts the route of Group %s!" % [fire.x, fire.y, ", ".join(PackedStringArray(hit))])


func _check_round_end() -> void:
	for g in groups:
		if g.is_active():
			return
	round_over = true
	var total_survivors := 0
	for g in groups:
		total_survivors += g.initial_survivors
	# A round succeeds when at least half of all survivors reach safety.
	last_round_success = scorer.delivered * 2 >= total_survivors
	scorer.finish_round(last_round_success, round_num)
	if last_round_success:
		banked_score += scorer.total()
	selected = null
	route.clear()
	_show_results(total_survivors)


func _on_next_pressed() -> void:
	if last_round_success:
		round_num += 1
	_start_round()


# --- Operator actions ---------------------------------------------------------

func _on_tile_pressed(p: Vector2i) -> void:
	if round_over:
		return
	var g := _plannable_group_at(p)
	if g != null and g != selected:
		# Switch groups, unless the tap is simply the next step of the current
		# route (routes may pass through tiles where other groups wait).
		var is_next_step := selected != null and route.size() > 1 and not route.has(p) \
				and map.is_adjacent(route[-1], p) and not map.is_safe(route[-1])
		if not is_next_step:
			_select_group(g)
			return
	if selected == null:
		var mover := _moving_group_at(p)
		if mover != null:
			_notify("Group %s is already en route." % mover.label, COL_DIM)
		else:
			map_view.flash_invalid(p)
			_notify("Select a survivor group first (green markers).", COL_WARN)
		return
	var idx := route.find(p)
	if idx != -1:
		# Tapping an earlier route tile cuts the route back to it.
		route.resize(idx + 1)
		return
	_try_extend(p)


func _on_tile_dragged(p: Vector2i) -> void:
	if round_over or selected == null or route.is_empty():
		return
	if route.size() >= 2 and p == route[-2]:
		route.pop_back()  # dragging backwards erases
		return
	if route.has(p):
		return
	var last := route[-1]
	if not map.is_adjacent(last, p) and absi(last.x - p.x) == 1 and absi(last.y - p.y) == 1:
		# Diagonal hop from a fast drag: insert the passable corner tile.
		for corner in [Vector2i(p.x, last.y), Vector2i(last.x, p.y)]:
			if map.is_passable(corner) and not route.has(corner) and not map.is_safe(corner):
				route.append(corner)
				break
	_try_extend(p)


## Appends `p` to the route if it is a legal next step; otherwise gives feedback.
func _try_extend(p: Vector2i) -> void:
	var last := route[-1]
	var reason := ""
	if map.is_safe(last):
		reason = "Route already reaches the SAFE zone. Dispatch it, or Undo."
	elif map.is_fire(p):
		reason = "Blocked: that road is on fire."
	elif map.is_road_closure(p):
		reason = "Road closed by rubble - take another street."
	elif not map.is_street(p):
		reason = "Buildings are impassable - stay on the roads."
	elif not map.is_adjacent(last, p):
		reason = "Not connected: pick a road tile next to the end of the route."
	if reason != "":
		map_view.flash_invalid(p)
		_notify(reason, COL_ALERT)
		return
	route.append(p)
	if map.is_safe(p):
		_notify("Route reaches the SAFE zone. Press DISPATCH (Enter).", COL_OK)
	elif map.is_smoke(p):
		_notify("Warning: smoke tile - each one crossed costs a survivor.", COL_WARN)
	else:
		_notify("Extend the route along the highlighted roads.", COL_DIM)


func _select_group(g: SurvivorGroup) -> void:
	if g == null or not g.can_plan():
		return
	selected = g
	route.clear()
	route.append(g.tile)
	_notify("Group %s selected. Tap or drag along adjacent roads to the SAFE zone." % g.label, COL_ACCENT)


func _dispatch() -> void:
	if round_over:
		return
	if selected == null:
		_notify("No group selected.", COL_WARN)
		return
	var v := RouteValidator.validate(map, route, selected.tile)
	if not v["valid"] or not v["complete"]:
		_notify("Cannot dispatch: " + str(v["reason"]), COL_ALERT)
		if v["bad_index"] >= 0 and v["bad_index"] < route.size():
			map_view.flash_invalid(route[v["bad_index"]])
		return
	var is_reroute := selected.state == SurvivorGroup.State.BLOCKED
	var secs := round_time - (selected.blocked_since if is_reroute else plan_clock_start)
	var shortest := map.shortest_length(selected.tile)
	var pts := scorer.record_dispatch(selected, secs, is_reroute, route.size() - 1, shortest)
	_show_score_popup(pts)
	var kind := "Detour" if is_reroute else "Route"
	_log("%s for Group %s: %d tiles (shortest %d), %.1fs -> +%d %s." % [
		kind, selected.label, route.size() - 1, shortest, secs, pts, "response" if is_reroute else "planning"])
	map_view.popup(selected.tile, "+%d" % pts, COL_ACCENT)
	selected.dispatch(route)
	first_successful_dispatch = true
	hint_panel.visible = false
	plan_clock_start = round_time
	selected = null
	route.clear()
	var next := _first_group_in_state(SurvivorGroup.State.BLOCKED)
	if next != null:
		_select_group(next)
	else:
		_notify("Dispatched. Select the next group, and watch for hazard alerts.", COL_OK)


func _undo() -> void:
	if selected != null and route.size() > 1:
		route.pop_back()


func _clear_route() -> void:
	if selected != null:
		route.clear()
		route.append(selected.tile)


func _cycle_selection() -> void:
	var plannable: Array[SurvivorGroup] = []
	for g in groups:
		if g.can_plan():
			plannable.append(g)
	if plannable.is_empty():
		return
	var i := plannable.find(selected)
	_select_group(plannable[(i + 1) % plannable.size()])


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if round_over:
				_on_next_pressed()
			else:
				_dispatch()
		KEY_BACKSPACE, KEY_Z:
			_undo()
		KEY_C:
			_clear_route()
		KEY_ESCAPE:
			selected = null
			route.clear()
		KEY_TAB:
			_cycle_selection()
		KEY_V:
			var other: VisualTheme.Style = VisualTheme.Style.DEBUG_SHAPES if visual_style == VisualTheme.Style.DISPATCH_STYLE else VisualTheme.Style.DISPATCH_STYLE
			set_visual_style(other)
		_:
			return
	get_viewport().set_input_as_handled()


# --- Queries ----------------------------------------------------------------------

func _plannable_group_at(p: Vector2i) -> SurvivorGroup:
	for g in groups:
		if g.can_plan() and g.tile == p:
			return g
	return null


func _moving_group_at(p: Vector2i) -> SurvivorGroup:
	for g in groups:
		if g.state == SurvivorGroup.State.MOVING and (g.tile == p or g.next_tile() == p):
			return g
	return null


func _first_group_in_state(s: int) -> SurvivorGroup:
	for g in groups:
		if g.state == s:
			return g
	return null


func _difficulty_name() -> String:
	return DIFFICULTY_NAMES[mini(round_num - 1, DIFFICULTY_NAMES.size() - 1)]


func _state_text(g: SurvivorGroup) -> String:
	match g.state:
		SurvivorGroup.State.WAITING:
			return "needs a route"
		SurvivorGroup.State.MOVING:
			if g.halt_requested:
				return "stopping..."
			return "on the way"
		SurvivorGroup.State.BLOCKED:
			return "FIRE! needs detour"
		SurvivorGroup.State.DELIVERED:
			return "safe"
		SurvivorGroup.State.LOST:
			return "lost"
	return ""


## One team icon + select button per group; rebuilt each round.
func _build_group_rows() -> void:
	for c in group_box.get_children():
		group_box.remove_child(c)
		c.queue_free()
	group_icons.clear()
	group_btns.clear()
	for g in groups:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.texture = GROUP_A_TEXTURE if g.label == "A" else GROUP_B_TEXTURE
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var b := _button("", _on_group_row_pressed.bind(g))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		row.add_child(b)
		group_box.add_child(row)
		group_icons.append(icon)
		group_btns.append(b)
	_apply_team_button_styles()


func _on_group_row_pressed(g: SurvivorGroup) -> void:
	if not round_over:
		_select_group(g)


func _log(text: String) -> void:
	log_lines.append("[%s] %s" % [_fmt_time(round_time), text])
	while log_lines.size() > LOG_LINES:
		log_lines.remove_at(0)
	_refresh_ops_log()


func _refresh_ops_log() -> void:
	if lbl_log == null:
		return
	lbl_log.clear()
	var shown := log_lines.slice(maxi(0, log_lines.size() - LOG_SHOWN))
	for i in shown.size():
		var line: String = shown[i]
		var color := UI_COLORS.TEXT_SECONDARY
		if line.contains("ALERT") or line.contains("lost") or line.contains("FIRE"):
			color = UI_COLORS.DANGER
		elif line.contains("halted") or line.contains("smoke") or line.contains("blocked"):
			color = UI_COLORS.WARNING
		var age := float(i + 1) / float(maxi(shown.size(), 1))
		var color_code := Color(color, lerpf(0.42, 1.0, age)).to_html(true)
		var escaped_line := line.replace("[", "[lb]").replace("]", "[rb]")
		lbl_log.append_text("[color=#%s]%s[/color]\n" % [color_code, escaped_line])


func _play_loss_feedback(index: int) -> void:
	if index < 0 or index >= strike_icons.size():
		return
	var icon := strike_icons[index]
	icon.pivot_offset = icon.size * 0.5
	var tween := create_tween()
	tween.tween_property(icon, "rotation", -0.12, 0.06)
	tween.tween_property(icon, "rotation", 0.12, 0.06)
	tween.tween_property(icon, "rotation", -0.08, 0.05)
	tween.tween_property(icon, "rotation", 0.0, 0.06)
	_trigger_juice_alert()


func _trigger_juice_alert() -> void:
	if not UI_COLORS.JUICE_ENABLED or _juice_flash == null:
		return
	_juice_flash.visible = true
	var material := _juice_flash.material as ShaderMaterial
	material.set_shader_parameter("intensity", 0.16)
	var flash_tween := create_tween()
	flash_tween.tween_method(
			func(value: float) -> void: material.set_shader_parameter("intensity", value),
			0.16, 0.0, 0.3)
	flash_tween.finished.connect(func() -> void: _juice_flash.visible = false)
	var rest := map_view.position
	var shake := create_tween()
	shake.tween_property(map_view, "position", rest + Vector2(3.0, 0.0), 0.025)
	shake.tween_property(map_view, "position", rest - Vector2(3.0, 0.0), 0.04)
	shake.tween_property(map_view, "position", rest, 0.05)


func _set_animated_score(value: float) -> void:
	_animated_score = value
	lbl_score.text = "%d" % roundi(value)


func _show_score_popup(points: int) -> void:
	if points == 0 or lbl_score_popup == null:
		return
	lbl_score_popup.text = "%+d" % points
	lbl_score_popup.add_theme_color_override("font_color",
			UI_COLORS.SUCCESS if points > 0 else UI_COLORS.DANGER)
	lbl_score_popup.modulate.a = 1.0
	lbl_score_popup.scale = Vector2.ONE * 0.8
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl_score_popup, "scale", Vector2.ONE, 0.18)
	tween.tween_property(lbl_score_popup, "modulate:a", 0.0, 0.8).set_delay(0.25)


func _team_color_for_group(group: SurvivorGroup) -> Color:
	return UI_COLORS.TEAM_A_COLOR if group.label == "A" else UI_COLORS.TEAM_B_COLOR


func _apply_team_button_styles() -> void:
	for i in group_btns.size():
		var button := group_btns[i]
		var group := groups[i]
		var color := UI_COLORS.TEAM_A_COLOR if group.label == "A" else UI_COLORS.TEAM_B_COLOR
		var is_selected := group == selected
		button.modulate = Color.WHITE if is_selected else Color(UI_COLORS.WHITE, 0.72)
		group_icons[i].modulate = Color(color, 1.0 if is_selected else 0.72)
		var normal := _flat_button_style(
				Color(color, 0.16) if is_selected else UI_COLORS.BG_PANEL,
				color if is_selected else UI_COLORS.TEAL_MID,
				2 if is_selected else 1)
		var hover := _flat_button_style(Color(color, 0.25), color, 2)
		var pressed := _flat_button_style(Color(color, 0.32), color, 2)
		var disabled := _flat_button_style(UI_COLORS.BG_PANEL, UI_COLORS.TEAL, 1)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("disabled", disabled)
	_styled_selected = selected


func _notify(text: String, color: Color) -> void:
	lbl_hint.text = text
	lbl_hint.add_theme_color_override("font_color", color)
	hint_panel.visible = not first_successful_dispatch


func _fmt_time(s: float) -> String:
	return "%02d:%04.1f" % [floori(s / 60.0), fmod(s, 60.0)]


# --- UI refresh -------------------------------------------------------------------

## Shows the map and legend in style `s`. Purely cosmetic: the round, routes
## and score are untouched.
func set_visual_style(s: VisualTheme.Style) -> void:
	visual_style = s
	if visual_theme_override != null and visual_theme_override.style == s:
		visual_theme = visual_theme_override
	else:
		visual_theme = VisualTheme.for_style(s)
	map_view.visual_theme = visual_theme
	map_frame.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 8, 1, 4))
	for c in legend.get_children():
		legend.remove_child(c)
		c.queue_free()
	var items := [["road", "Road"], ["building", "Building"], ["park", "Park"], ["safe", "Safe zone"],
			["survivor", "Survivors"], ["route", "Your route"], ["fire", "Fire (blocked)"], ["smoke", "Smoke (-1 ppl)"]]
	if s == VisualTheme.Style.DISPATCH_STYLE:
		items.append(["closed", "Closed road"])
	for item in items:
		legend.add_child(Swatch.new(item[0], visual_theme))
		var l := _label(item[1], 12, COL_TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		legend.add_child(l)


func _update_ui() -> void:
	validation = {}
	if selected != null:
		validation = RouteValidator.validate(map, route, selected.tile)
	map_view.map = map
	map_view.groups = groups
	map_view.selected = selected
	map_view.route = route
	map_view.route_bad_index = validation.get("bad_index", -1)
	map_view.route_complete = validation.get("complete", false)
	map_view.alert_countdown = hazards.seconds_to_next_event if not round_over else 0.0
	map_view.alert_progress = hazards.next_event_progress if not round_over else 0.0

	# Top bar
	lbl_round.text = "ROUND %d  ·  %s" % [round_num, _difficulty_name().to_upper()]
	lbl_time.text = _fmt_time(round_time)
	var new_score := banked_score + (0 if round_over else scorer.total())
	if new_score != _score_target:
		_score_target = new_score
		if _score_tween != null and _score_tween.is_running():
			_score_tween.kill()
		_score_tween = create_tween()
		_score_tween.tween_method(_set_animated_score, _animated_score, float(_score_target), 0.45)
	if not round_over and _first_group_in_state(SurvivorGroup.State.WAITING) != null:
		var s := round_time - plan_clock_start
		var b := ScoreKeeper.planning_bonus(s)
		lbl_plan.text = "%.1fs  +%d" % [s, b]
		lbl_plan.add_theme_color_override("font_color", COL_OK if b > 40 else (COL_WARN if b > 0 else COL_ALERT))
	else:
		lbl_plan.text = "--"
		lbl_plan.add_theme_color_override("font_color", COL_DIM)

	# Group module: one team icon row per group
	for i in groups.size():
		var g := groups[i]
		var blink_off := g.state == SurvivorGroup.State.BLOCKED and fmod(round_time, 0.6) > 0.3
		var icon_color := UI_COLORS.TEAM_A_COLOR if g.label == "A" else UI_COLORS.TEAM_B_COLOR
		var opacity := 0.25 if g.state == SurvivorGroup.State.LOST or blink_off else (1.0 if g == selected else 0.72)
		group_icons[i].modulate = Color(icon_color, opacity)
		group_btns[i].text = "%sGroup %s   %d/%d people   %s" % [
			"> " if g == selected else "", g.label, g.survivors, g.initial_survivors, _state_text(g)]
		group_btns[i].disabled = not g.can_plan()
	for i in strike_icons.size():
		strike_icons[i].texture = PEOPLE_LOST_FILLED_TEXTURE if i < scorer.lost else PEOPLE_LOST_EMPTY_TEXTURE
		strike_icons[i].modulate = UI_COLORS.DANGER if i < scorer.lost else UI_COLORS.TEXT_SECONDARY
	if selected != _styled_selected:
		_apply_team_button_styles()

	# Route module: one LED, one short line
	var can_dispatch := false
	var route_color := COL_DIM
	var route_lit := false
	if selected == null:
		lbl_route.text = "No team selected"
	else:
		var length: int = validation["length"]
		var shortest := map.shortest_length(selected.tile)
		route_lit = true
		if not validation["valid"]:
			route_color = COL_ALERT
			lbl_route.text = "Route not valid"
		elif validation["complete"]:
			route_color = COL_OK
			lbl_route.text = "Route ready!  %d tiles, %d%% direct" % [length, roundi(100.0 * shortest / maxi(length, 1))]
			can_dispatch = true
		else:
			route_color = COL_WARN
			lbl_route.text = "Keep going to the SAFE zone  (%d tiles)" % length
		if validation["smoke"] > 0:
			lbl_route.text += "\nSmoke x%d = -%d people" % [validation["smoke"], validation["smoke"]]
	route_led.set_state(_team_color_for_group(selected) if selected != null else route_color, route_lit)
	btn_dispatch.disabled = not can_dispatch
	btn_dispatch.modulate = UiPalette.MINT.lerp(UiPalette.WHITE, 0.5 + 0.5 * sin(round_time * 6.0)) if can_dispatch else UiPalette.WHITE
	if selected != null and selected.state == SurvivorGroup.State.BLOCKED:
		btn_dispatch.text = "DISPATCH DETOUR"
	elif selected != null:
		btn_dispatch.text = "DISPATCH GROUP %s" % selected.label
	else:
		btn_dispatch.text = "DISPATCH"
	btn_undo.disabled = selected == null or route.size() <= 1
	btn_clear.disabled = btn_undo.disabled
	btn_undo.modulate = Color(UI_COLORS.WHITE, 0.55) if btn_undo.disabled else UI_COLORS.WHITE
	btn_clear.modulate = Color(UI_COLORS.WHITE, 0.55) if btn_clear.disabled else UI_COLORS.WHITE

	map_view.route_eta_seconds = 0.0
	if selected != null:
		var plan_start := selected.blocked_since if selected.state == SurvivorGroup.State.BLOCKED else plan_clock_start
		map_view.route_eta_seconds = maxf(0.0, round_time - plan_start)

	# Hazard alert banner
	var blocked: SurvivorGroup = null
	for g in groups:
		if g.state == SurvivorGroup.State.BLOCKED or (g.state == SurvivorGroup.State.MOVING and g.halt_requested):
			blocked = g
			break
	alert_panel.visible = blocked != null and not round_over
	if blocked != null:
		var rs := round_time - blocked.blocked_since
		var action := "halting..." if blocked.state == SurvivorGroup.State.MOVING else "draw a detour"
		lbl_alert.text = "ROUTE BLOCKED  -  Group %s: %s   (%.1fs, +%d)" % [
			blocked.label, action, rs, ScoreKeeper.response_bonus(rs)]
		alert_led.modulate.a = 0.65 + 0.35 * float(fmod(round_time, 0.5) < 0.25)
		alert_panel.modulate.a = 0.85 + 0.15 * sin(round_time * 8.0)


func _show_results(total_survivors: int) -> void:
	var ok := last_round_success
	var tone := COL_OK if ok else COL_ALERT
	lbl_result_title.text = "ROUND COMPLETE" if ok else "ROUND FAILED"
	lbl_result_title.add_theme_color_override("font_color", tone)
	lbl_result_sub.text = "ROUND %d  |  %s" % [round_num, _difficulty_name().to_upper()]
	result_led.set_state(tone, true)
	result_panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 14, 2, 0))
	var banner := _style(COL_PANEL, UiPalette.MINT, 10, 1, 14)
	banner.corner_radius_bottom_left = 0
	banner.corner_radius_bottom_right = 0
	result_banner.add_theme_stylebox_override("panel", banner)

	lbl_result_saved.text = "%d / %d" % [scorer.delivered, total_survivors]
	lbl_result_saved.add_theme_color_override("font_color", tone)
	# Star rating: 3 = everyone saved, 2 = three quarters or more, 1 = cleared, 0 = failed.
	var ratio := float(scorer.delivered) / float(maxi(total_survivors, 1))
	var stars := 0 if not ok else (3 if ratio >= 1.0 else (2 if ratio >= 0.75 else 1))
	for i in result_stars.size():
		result_stars[i].texture = _star_texture(i < stars)
	for c in result_pips.get_children():
		c.queue_free()
	for i in total_survivors:
		var pip := UiWidgets.Led.new(12.0)
		pip.set_state(COL_OK if i < scorer.delivered else COL_ALERT, true)
		result_pips.add_child(pip)

	for c in result_grid.get_children():
		c.queue_free()
	for row in scorer.breakdown():
		_add_result_row(row[0], row[1], row[2])
	lbl_result_total.text = "%+d" % scorer.total()
	lbl_result_total.add_theme_color_override("font_color", COL_WARN if scorer.total() >= 0 else COL_ALERT)
	if ok:
		lbl_result_note.text = "Total score: %d  -  the next round has a bigger city and more fires." % banked_score
		btn_next.text = "NEXT ROUND  >>"
	else:
		lbl_result_note.text = "Save at least half the people to pass. This round's points don't count."
		btn_next.text = "TRY AGAIN"
	result_panel.visible = true
	result_panel.modulate.a = 0.0
	create_tween().tween_property(result_panel, "modulate:a", 1.0, 0.3)


func _add_result_row(title: String, detail: String, pts: int) -> void:
	result_grid.add_child(_label(title, 15, COL_TEXT))
	var d := _label(detail, 12, COL_DIM)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_grid.add_child(d)
	var col := COL_OK if pts > 0 else (COL_ALERT if pts < 0 else COL_DIM)
	var l := _label("%+d" % pts, 15, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size.x = 60
	result_grid.add_child(l)


# --- UI construction ------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Rajdhani (SIL OFL): a squared, technical face for the whole tablet UI.
	var ui_theme := UI_THEME.duplicate() as Theme
	var font_medium := load("res://assets/fonts/Rajdhani-Medium.ttf") as Font
	var font_bold := load("res://assets/fonts/Rajdhani-Bold.ttf") as Font
	if font_medium != null:
		ui_theme.default_font = font_medium
		ui_theme.default_font_size = 16
		if font_bold != null:
			ui_theme.set_font("font", "Button", font_bold)
			ui_theme.set_font_size("font_size", "Button", 18)
	theme = ui_theme
	var bg := ColorRect.new()
	bg.color = UiPalette.BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Keep the slim bezel clear while allowing its 9-slice edges to stay intact.
	var content := MarginContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 20)
	content.add_theme_constant_override("margin_top", 20)
	content.add_theme_constant_override("margin_right", 20)
	content.add_theme_constant_override("margin_bottom", 20)
	add_child(content)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 8, 1, 8))
	screen.clip_contents = true
	content.add_child(screen)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	screen.add_child(vbox)

	# Top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 6, 1, 8))
	vbox.add_child(top)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 14)
	top.add_child(top_h)
	var logo := TextureRect.new()
	logo.texture = LOGO_TEXTURE
	logo.custom_minimum_size = Vector2(112, 34)
	logo.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_h.add_child(logo)
	top_h.add_child(_label("RESCUE OPS", 12, COL_DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(spacer)
	lbl_round = UiWidgets.Lcd.new("ROUND 1", 18, COL_TEXT)
	lbl_plan = UiWidgets.Lcd.new("PLAN --", 18, COL_OK)
	lbl_time = UiWidgets.Lcd.new("00:00.0", 28, COL_ACCENT)
	lbl_score = UiWidgets.Lcd.new("0", 22, COL_WARN)
	lbl_plan.custom_minimum_size.x = 200
	lbl_time.custom_minimum_size.x = 130
	lbl_score.custom_minimum_size.x = 120
	lbl_round.custom_minimum_size.x = 170
	for pair in [["PLAN", lbl_plan], ["TIME", lbl_time], ["SCORE", lbl_score], ["", lbl_round]]:
		if pair[0] != "":
			top_h.add_child(_label(pair[0], 11, COL_DIM))
		top_h.add_child(pair[1])
	lbl_score_popup = _label("", 12, COL_OK)
	top_h.add_child(lbl_score_popup)

	# Body: map + side panel
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	vbox.add_child(body)

	map_frame = PanelContainer.new()  # styled by set_visual_style()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map_frame)
	var map_area := Control.new()
	map_area.clip_contents = true
	map_frame.add_child(map_area)
	map_view = MapView.new()
	map_view.alert_icon_texture = ALERT_TEXTURE
	map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_view.tile_pressed.connect(_on_tile_pressed)
	map_view.tile_dragged.connect(_on_tile_dragged)
	map_area.add_child(map_view)

	alert_panel = PanelContainer.new()
	alert_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	alert_panel.offset_left = 12
	alert_panel.offset_right = -12
	alert_panel.offset_top = 10
	alert_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 6, 1, 10))
	var alert_h := HBoxContainer.new()
	alert_h.add_theme_constant_override("separation", 12)
	alert_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_panel.add_child(alert_h)
	alert_led = TextureRect.new()
	alert_led.texture = ALERT_TEXTURE
	alert_led.modulate = COL_ALERT
	alert_led.custom_minimum_size = Vector2(64, 64)
	alert_led.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	alert_led.stretch_mode = TextureRect.STRETCH_KEEP
	alert_led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alert_h.add_child(alert_led)
	lbl_alert = _label("", 17, UiPalette.WHITE)
	lbl_alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_alert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_h.add_child(lbl_alert)
	alert_panel.visible = false
	map_area.add_child(alert_panel)

	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.z_index = 10
	result_panel.custom_minimum_size = Vector2(560, 0)
	result_panel.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 14, 2, 0))
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 0)
	result_panel.add_child(rv)

	# Banner: status light, verdict and round name
	result_banner = PanelContainer.new()
	rv.add_child(result_banner)
	var banner_h := HBoxContainer.new()
	banner_h.add_theme_constant_override("separation", 12)
	result_banner.add_child(banner_h)
	result_led = UiWidgets.Led.new(22.0)
	result_led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_h.add_child(result_led)
	lbl_result_title = _label("ROUND COMPLETE", 28, COL_OK)
	lbl_result_title.add_theme_font_override("font", load("res://assets/fonts/Rajdhani-Bold.ttf") as Font)
	banner_h.add_child(lbl_result_title)
	var banner_gap := Control.new()
	banner_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_h.add_child(banner_gap)
	lbl_result_sub = _label("", 13, COL_DIM)
	banner_h.add_child(lbl_result_sub)

	var body_box := VBoxContainer.new()
	body_box.add_theme_constant_override("separation", 12)
	var body_margin := MarginContainer.new()
	for side_name in ["left", "right", "top", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side_name, 18)
	body_margin.add_child(body_box)
	rv.add_child(body_margin)

	# Hero: people saved readout and star rating
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 16)
	body_box.add_child(hero)
	var saved_box := VBoxContainer.new()
	saved_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_child(saved_box)
	saved_box.add_child(_label("PEOPLE SAVED", 11, COL_DIM))
	lbl_result_saved = UiWidgets.Lcd.new("0 / 0", 34, COL_OK)
	saved_box.add_child(lbl_result_saved)
	var rating_box := VBoxContainer.new()
	hero.add_child(rating_box)
	rating_box.add_child(_label("RATING", 11, COL_DIM))
	var stars_h := HBoxContainer.new()
	stars_h.add_theme_constant_override("separation", 8)
	stars_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stars_h.alignment = BoxContainer.ALIGNMENT_CENTER
	rating_box.add_child(stars_h)
	for i in 3:
		var star := TextureRect.new()
		star.texture = _star_texture(false)
		star.custom_minimum_size = Vector2(64, 64)
		star.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars_h.add_child(star)
		result_stars.append(star)
	result_pips = HFlowContainer.new()
	result_pips.add_theme_constant_override("h_separation", 4)
	result_pips.add_theme_constant_override("v_separation", 4)
	body_box.add_child(result_pips)

	# Score lines
	var rows_frame := PanelContainer.new()
	rows_frame.add_theme_stylebox_override("panel", _style(COL_MODULE, COL_MODULE_EDGE, 6, 2, 12))
	body_box.add_child(rows_frame)
	result_grid = GridContainer.new()
	result_grid.columns = 3
	result_grid.add_theme_constant_override("h_separation", 16)
	result_grid.add_theme_constant_override("v_separation", 4)
	rows_frame.add_child(result_grid)

	# Round score readout
	var total_h := HBoxContainer.new()
	total_h.add_theme_constant_override("separation", 12)
	body_box.add_child(total_h)
	total_h.add_child(_label("ROUND SCORE", 16, COL_TEXT))
	var total_gap := Control.new()
	total_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_h.add_child(total_gap)
	lbl_result_total = UiWidgets.Lcd.new("+0", 30, COL_WARN)
	lbl_result_total.custom_minimum_size.x = 170
	total_h.add_child(lbl_result_total)

	lbl_result_note = _label("", 13, COL_DIM)
	lbl_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_box.add_child(lbl_result_note)
	btn_next = _button("NEXT ROUND  >>", _on_next_pressed)
	btn_next.custom_minimum_size.y = 52
	_set_button_art(btn_next)
	body_box.add_child(btn_next)
	result_panel.visible = false
	map_area.add_child(result_panel)

	# Side panel: stacked control-unit modules
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	side.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 6, 1, 8))
	body.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 12)
	scroll.add_child(sv)

	var mg := _add_module(sv, "YOUR TEAMS")
	group_box = VBoxContainer.new()
	group_box.add_theme_constant_override("separation", 4)
	mg.add_child(group_box)

	# Route module
	var mr := _add_module(sv, "PLAN THE ROUTE")
	var route_row := HBoxContainer.new()
	route_row.add_theme_constant_override("separation", 8)
	mr.add_child(route_row)
	route_led = UiWidgets.Led.new(20.0)
	route_led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	route_row.add_child(route_led)
	lbl_route = _wrap_label(14, COL_TEXT)
	route_row.add_child(lbl_route)
	hint_panel = PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel",
			_style(Color(UI_COLORS.ACCENT_TEAL, 0.08), UI_COLORS.TEAL_MID, 6, 1, 8))
	lbl_hint = _wrap_label(12, COL_ACCENT)
	lbl_hint.custom_minimum_size.y = 34
	hint_panel.add_child(lbl_hint)
	mr.add_child(hint_panel)

	btn_dispatch = _button("DISPATCH", _dispatch)
	btn_dispatch.custom_minimum_size.y = 64
	btn_dispatch.add_theme_font_size_override("font_size", 20)
	_set_dispatch_button_styles(btn_dispatch)
	btn_dispatch.button_down.connect(_animate_dispatch_press.bind(true))
	btn_dispatch.button_up.connect(_animate_dispatch_press.bind(false))
	mr.add_child(btn_dispatch)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	btn_undo = _button("UNDO", _undo)
	btn_clear = _button("CLEAR", _clear_route)
	for b in [btn_undo, btn_clear]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_set_secondary_button_styles(b)
		row.add_child(b)
	mr.add_child(row)

	# Losses module: one sprite slot per possible survivor loss
	var ml := _add_module(sv, "PEOPLE LOST")
	var strikes := HBoxContainer.new()
	strikes.add_theme_constant_override("separation", 10)
	ml.add_child(strikes)
	for i in MAX_STRIKES:
		var icon := TextureRect.new()
		icon.texture = PEOPLE_LOST_EMPTY_TEXTURE
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strikes.add_child(icon)
		strike_icons.append(icon)

	# Ops log module
	var mo := _add_module(sv, "OPS LOG")
	lbl_log = RichTextLabel.new()
	lbl_log.custom_minimum_size.y = 100
	lbl_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_log.bbcode_enabled = true
	lbl_log.scroll_following = true
	lbl_log.selection_enabled = false
	lbl_log.fit_content = false
	lbl_log.add_theme_font_size_override("normal_font_size", 14)
	lbl_log.add_theme_color_override("default_color", UI_COLORS.TEXT_SECONDARY)
	mo.add_child(lbl_log)
	_refresh_ops_log()

	# Help (legend + keys), hidden until asked for
	var btn_help := _button("? LEGEND / KEYS", func() -> void: help_box.visible = not help_box.visible)
	sv.add_child(btn_help)
	help_box = VBoxContainer.new()
	help_box.add_theme_constant_override("separation", 6)
	help_box.visible = false
	sv.add_child(help_box)
	legend = GridContainer.new()  # filled by set_visual_style()
	legend.columns = 4
	legend.add_theme_constant_override("h_separation", 6)
	legend.add_theme_constant_override("v_separation", 4)
	help_box.add_child(legend)
	var keys := _wrap_label(11, COL_DIM)
	keys.text = "Keys: Enter dispatch, Z/Backspace undo, C clear, Tab next group, Esc deselect, V map style. Tap an earlier route tile to cut back to it."
	help_box.add_child(keys)

	var tablet_frame := NinePatchRect.new()
	tablet_frame.texture = TABLET_FRAME_TEXTURE
	tablet_frame.patch_margin_left = 32
	tablet_frame.patch_margin_top = 32
	tablet_frame.patch_margin_right = 32
	tablet_frame.patch_margin_bottom = 32
	tablet_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	tablet_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tablet_frame.z_index = 100
	add_child(tablet_frame)
	var scanline_overlay := ColorRect.new()
	scanline_overlay.name = "ScanlineOverlay"
	scanline_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	scanline_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scanline_overlay.z_index = 90
	var scanline_material := ShaderMaterial.new()
	scanline_material.shader = SCANLINE_SHADER
	scanline_material.set_shader_parameter("intensity", 0.018)
	scanline_overlay.material = scanline_material
	add_child(scanline_overlay)
	_juice_flash = ColorRect.new()
	_juice_flash.name = "AlertFlashOverlay"
	_juice_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_juice_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flash_material := ShaderMaterial.new()
	flash_material.shader = ALERT_FLASH_SHADER
	flash_material.set_shader_parameter("flash_color", UI_COLORS.DANGER)
	flash_material.set_shader_parameter("intensity", 0.0)
	_juice_flash.material = flash_material
	_juice_flash.visible = false
	_juice_flash.z_index = 95
	add_child(_juice_flash)


## A framed control-unit module with a title; returns the box to fill.
func _add_module(parent: Control, title: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _style(COL_MODULE, COL_MODULE_EDGE, 4, 2, 8))
	parent.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	box.add_child(_label(title, 14, COL_ACCENT))
	return box


func _style(bg_color: Color, edge: Color, radius: int, border: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = edge
	sb.set_border_width_all(clampi(border, 1, 2))
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(14, font_size + 2))
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _wrap_label(font_size: int, color: Color) -> Label:
	var l := _label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 38
	_set_button_art(b)
	b.add_theme_color_override("font_color", UiPalette.MINT)
	b.add_theme_color_override("font_hover_color", UiPalette.WHITE)
	b.add_theme_color_override("font_pressed_color", UiPalette.MINT)
	b.add_theme_color_override("font_disabled_color", UiPalette.TEAL_MID)
	b.pressed.connect(callback)
	return b


func _button_art(state: int) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = BUTTONS_SHEET
	atlas.region = Rect2(state * 192, 0, 192, 64)
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.texture_margin_left = 20
	style.texture_margin_top = 20
	style.texture_margin_right = 20
	style.texture_margin_bottom = 20
	style.set_content_margin_all(12)
	return style


func _set_button_art(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_art(0))
	button.add_theme_stylebox_override("hover", _button_art(1))
	button.add_theme_stylebox_override("pressed", _button_art(2))
	button.add_theme_stylebox_override("disabled", _button_art(3))


func _set_dispatch_button_styles(button: Button) -> void:
	var normal := _flat_button_style(UI_COLORS.BG_PANEL, UI_COLORS.ACCENT_TEAL, 2)
	normal.shadow_color = Color(UI_COLORS.ACCENT_TEAL, 0.24)
	normal.shadow_size = 5
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover",
			_flat_button_style(Color(UI_COLORS.ACCENT_TEAL, 0.16), UI_COLORS.WHITE, 2))
	button.add_theme_stylebox_override("pressed",
			_flat_button_style(Color(UI_COLORS.ACCENT_TEAL, 0.3), UI_COLORS.ACCENT_TEAL, 2))
	button.add_theme_stylebox_override("disabled",
			_flat_button_style(UI_COLORS.BG_PANEL, UI_COLORS.TEAL, 1))
	button.add_theme_color_override("font_color", UI_COLORS.ACCENT_TEAL)
	button.add_theme_color_override("font_hover_color", UI_COLORS.WHITE)
	button.add_theme_color_override("font_pressed_color", UI_COLORS.BG_DARK)
	button.add_theme_color_override("font_disabled_color", UI_COLORS.TEAL_MID)


func _set_secondary_button_styles(button: Button) -> void:
	button.add_theme_stylebox_override("normal",
			_flat_button_style(UI_COLORS.BG_PANEL, UI_COLORS.TEAL_MID, 1))
	button.add_theme_stylebox_override("hover",
			_flat_button_style(Color(UI_COLORS.TEAL, 0.5), UI_COLORS.TEXT_SECONDARY, 1))
	button.add_theme_stylebox_override("pressed",
			_flat_button_style(Color(UI_COLORS.TEAL, 0.75), UI_COLORS.ACCENT_TEAL, 1))
	button.add_theme_stylebox_override("disabled",
			_flat_button_style(UI_COLORS.BG_PANEL, UI_COLORS.TEAL, 1))


func _flat_button_style(background: Color, edge: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _animate_dispatch_press(is_pressed: bool) -> void:
	btn_dispatch.pivot_offset = btn_dispatch.size * 0.5
	var target_scale := Vector2.ONE * (0.95 if is_pressed else 1.0)
	create_tween().tween_property(btn_dispatch, "scale", target_scale, 0.08)


func _star_texture(lit: bool) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = STAR_SHEET
	atlas.region = Rect2(0 if lit else 64, 0, 64, 64)
	return atlas
