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

const COL_BG := Color("0a0f1a")
const COL_BEZEL := Color("05080f")
const COL_BEZEL_EDGE := Color("223047")
const COL_PANEL := Color("111a2b")
const COL_PANEL_EDGE := Color("24324a")
const COL_TEXT := Color("d7e1f0")
const COL_DIM := Color("7f8ea8")
const COL_ACCENT := Color("38c6f4")
const COL_ALERT := Color("ff4d3d")
const COL_OK := Color("39d98a")
const COL_WARN := Color("ffb020")
const LOG_LINES := 6
const DIFFICULTY_NAMES := ["Training", "Easy", "Moderate", "Hard", "Severe", "Extreme"]


## Small legend icon that reuses the map's own symbol painters.
class Swatch extends Control:
	var kind := ""
	var visual_theme: VisualTheme

	func _init(p_kind: String, p_theme: VisualTheme) -> void:
		kind = p_kind
		visual_theme = p_theme
		custom_minimum_size = Vector2(20, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
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
var lbl_group: Label
var lbl_route: Label
var lbl_hint: Label
var lbl_groups: Label
var lbl_log: Label
var btn_dispatch: Button
var btn_undo: Button
var btn_clear: Button
var alert_panel: PanelContainer
var lbl_alert: Label
var result_panel: PanelContainer
var lbl_result_title: Label
var result_grid: GridContainer
var lbl_result_note: Label
var btn_next: Button


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
	result_panel.visible = false
	alert_panel.visible = false
	_log("Round %d (%s): %d groups, %d fire(s) on map, %d timed alert(s) incoming." % [
		round_num, _difficulty_name(), groups.size(), map.fires.size(), hazards.events_remaining])
	# MapGenerator.build_from_seed(round, seed) rebuilds this exact map.
	print("Evac Grid round %d map: %s" % [round_num, map.gen_info])
	_notify("Tap a yellow survivor group to start planning. The plan clock is running!", COL_ACCENT)
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
			_log("Group %s lost a survivor in smoke (%d)." % [g.label, pts])
		"delivered":
			var res := scorer.record_delivery(g)
			map_view.popup(tile, "+%d" % (res["rescue"] + res["efficiency"]), COL_OK)
			_log("Group %s SAFE: %d survivors (+%d), efficiency %d%% (+%d)." % [
				g.label, g.survivors, res["rescue"], roundi(res["ratio"] * 100.0), res["efficiency"]])
		"lost":
			_log("Group %s was lost in the smoke." % g.label)


func _on_hazard(fire: Vector2i) -> void:
	map_view.alert_tiles.append(fire)
	map_view.popup(fire, "FIRE!", COL_ALERT)
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
			_notify("Select a survivor group first (yellow circles).", COL_WARN)
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
	var kind := "Detour" if is_reroute else "Route"
	_log("%s for Group %s: %d tiles (shortest %d), %.1fs -> +%d %s." % [
		kind, selected.label, route.size() - 1, shortest, secs, pts, "response" if is_reroute else "planning"])
	map_view.popup(selected.tile, "+%d" % pts, COL_ACCENT)
	selected.dispatch(route)
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
			return "waiting for route"
		SurvivorGroup.State.MOVING:
			if g.halt_requested:
				return "HALTING"
			return "en route %d/%d" % [g.index, g.path.size() - 1]
		SurvivorGroup.State.BLOCKED:
			return "BLOCKED - needs detour"
		SurvivorGroup.State.DELIVERED:
			return "SAFE"
		SurvivorGroup.State.LOST:
			return "LOST"
	return ""


func _log(text: String) -> void:
	log_lines.append("[%s] %s" % [_fmt_time(round_time), text])
	while log_lines.size() > LOG_LINES:
		log_lines.remove_at(0)


func _notify(text: String, color: Color) -> void:
	lbl_hint.text = text
	lbl_hint.add_theme_color_override("font_color", color)


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
	map_frame.add_theme_stylebox_override("panel", _style(visual_theme.map_bg, COL_PANEL_EDGE, 8, 1, 4))
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

	# Top bar
	lbl_round.text = "ROUND %d  |  %s" % [round_num, _difficulty_name().to_upper()]
	lbl_time.text = "TIME %s" % _fmt_time(round_time)
	lbl_score.text = "SCORE %d" % (banked_score + (0 if round_over else scorer.total()))
	if not round_over and _first_group_in_state(SurvivorGroup.State.WAITING) != null:
		var s := round_time - plan_clock_start
		var b := ScoreKeeper.planning_bonus(s)
		lbl_plan.text = "PLAN CLOCK %.1fs  (+%d)" % [s, b]
		lbl_plan.add_theme_color_override("font_color", COL_OK if b > 40 else (COL_WARN if b > 0 else COL_ALERT))
	else:
		lbl_plan.text = "PLAN CLOCK  --"
		lbl_plan.add_theme_color_override("font_color", COL_DIM)

	# Selected group
	if selected == null:
		lbl_group.text = "None selected.\nTap a yellow circle on the map\n(or press Tab)."
	else:
		var shortest := map.shortest_length(selected.tile)
		var status := "Waiting" if selected.state == SurvivorGroup.State.WAITING else "HALTED - needs a detour"
		lbl_group.text = "Group %s  -  %d survivors\n%s at (%d, %d)\nShortest route available: %d tiles" % [
			selected.label, selected.survivors, status, selected.tile.x, selected.tile.y, shortest]

	# Route status
	var can_dispatch := false
	if selected == null:
		lbl_route.text = "No route."
	else:
		var lines: Array[String] = []
		var length: int = validation["length"]
		lines.append("Length: %d tile(s)" % length)
		if not validation["valid"]:
			lines.append("INVALID: " + str(validation["reason"]))
		elif validation["complete"]:
			var shortest := map.shortest_length(selected.tile)
			var eff := float(shortest) / float(maxi(length, 1))
			lines.append("READY - reaches SAFE zone")
			lines.append("Efficiency: %d%% of shortest" % roundi(eff * 100.0))
			can_dispatch = true
		else:
			lines.append(str(validation["reason"]))
		if validation["smoke"] > 0:
			lines.append("Smoke tiles: %d  (= %d casualties)" % [validation["smoke"], validation["smoke"]])
		if selected.state == SurvivorGroup.State.BLOCKED:
			var rs := round_time - selected.blocked_since
			lines.append("Response bonus if sent now: +%d" % ScoreKeeper.response_bonus(rs))
		else:
			lines.append("Planning bonus if sent now: +%d" % ScoreKeeper.planning_bonus(round_time - plan_clock_start))
		lbl_route.text = "\n".join(PackedStringArray(lines))
	btn_dispatch.disabled = not can_dispatch
	if selected != null and selected.state == SurvivorGroup.State.BLOCKED:
		btn_dispatch.text = "DISPATCH DETOUR  (Enter)"
	elif selected != null:
		btn_dispatch.text = "DISPATCH GROUP %s  (Enter)" % selected.label
	else:
		btn_dispatch.text = "DISPATCH  (Enter)"
	btn_undo.disabled = selected == null or route.size() <= 1
	btn_clear.disabled = btn_undo.disabled

	# Group roster and log
	var roster: Array[String] = []
	for g in groups:
		roster.append("%s   %d/%d   %s" % [g.label, g.survivors, g.initial_survivors, _state_text(g)])
	lbl_groups.text = "\n".join(PackedStringArray(roster))
	lbl_log.text = "\n".join(PackedStringArray(log_lines))

	# Hazard alert banner
	var blocked: SurvivorGroup = null
	for g in groups:
		if g.state == SurvivorGroup.State.BLOCKED or (g.state == SurvivorGroup.State.MOVING and g.halt_requested):
			blocked = g
			break
	alert_panel.visible = blocked != null and not round_over
	if blocked != null:
		var rs := round_time - blocked.blocked_since
		var action := "Group halting..." if blocked.state == SurvivorGroup.State.MOVING else "Draw a detour from its position."
		lbl_alert.text = "!! ROUTE BLOCKED - fire at (%d, %d) cuts Group %s's route. %s   Response %.1fs (+%d)" % [
			blocked.blocking_tile.x, blocked.blocking_tile.y, blocked.label, action, rs, ScoreKeeper.response_bonus(rs)]
		alert_panel.modulate.a = 0.8 + 0.2 * sin(round_time * 8.0)


func _show_results(total_survivors: int) -> void:
	lbl_result_title.text = "EVACUATION COMPLETE" if last_round_success else "EVACUATION FAILED"
	lbl_result_title.add_theme_color_override("font_color", COL_OK if last_round_success else COL_ALERT)
	for c in result_grid.get_children():
		c.queue_free()
	for row in scorer.breakdown():
		_add_result_row(row[0], row[1], row[2], false)
	_add_result_row("ROUND TOTAL", "%d / %d survivors saved" % [scorer.delivered, total_survivors], scorer.total(), true)
	if last_round_success:
		lbl_result_note.text = "Round score banked. Total score: %d\nNext round: bigger city, more groups and hazards." % banked_score
		btn_next.text = "NEXT ROUND  >>"
	else:
		lbl_result_note.text = "Fewer than half the survivors reached safety.\nRound points are not banked. Total score: %d" % banked_score
		btn_next.text = "RETRY ROUND"
	result_panel.visible = true


func _add_result_row(title: String, detail: String, pts: int, bold: bool) -> void:
	var fs := 16 if bold else 14
	result_grid.add_child(_label(title, fs, COL_TEXT))
	result_grid.add_child(_label(detail, 12, COL_DIM))
	var col := COL_OK if pts > 0 else (COL_ALERT if pts < 0 else COL_DIM)
	var l := _label("%+d" % pts, fs, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size.x = 70
	result_grid.add_child(l)


# --- UI construction ------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Tablet bezel
	var bezel := PanelContainer.new()
	bezel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bezel.offset_left = 10
	bezel.offset_top = 10
	bezel.offset_right = -10
	bezel.offset_bottom = -10
	bezel.add_theme_stylebox_override("panel", _style(COL_BEZEL, COL_BEZEL_EDGE, 22, 3, 14))
	add_child(bezel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	bezel.add_child(vbox)

	# Top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 8, 1, 10))
	vbox.add_child(top)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 28)
	top.add_child(top_h)
	top_h.add_child(_label("EVAC GRID", 22, COL_ACCENT))
	top_h.add_child(_label("RESCUE OPERATIONS", 12, COL_DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(spacer)
	lbl_round = _label("ROUND 1", 16, COL_TEXT)
	lbl_plan = _label("PLAN CLOCK", 16, COL_OK)
	lbl_time = _label("TIME", 16, COL_TEXT)
	lbl_score = _label("SCORE 0", 18, COL_WARN)
	for l in [lbl_round, lbl_plan, lbl_time, lbl_score]:
		top_h.add_child(l)

	# Body: map + side panel
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	vbox.add_child(body)

	map_frame = PanelContainer.new()  # styled by set_visual_style()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map_frame)
	var map_area := Control.new()
	map_area.clip_contents = true
	map_frame.add_child(map_area)
	map_view = MapView.new()
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
	alert_panel.add_theme_stylebox_override("panel", _style(Color("5c0d12"), COL_ALERT, 6, 2, 10))
	lbl_alert = _label("", 15, Color.WHITE)
	lbl_alert.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_panel.add_child(lbl_alert)
	alert_panel.visible = false
	map_area.add_child(alert_panel)

	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.custom_minimum_size = Vector2(500, 0)
	result_panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.07, 0.12, 0.97), COL_ACCENT, 10, 2, 20))
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	result_panel.add_child(rv)
	lbl_result_title = _label("EVACUATION COMPLETE", 24, COL_OK)
	lbl_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(lbl_result_title)
	result_grid = GridContainer.new()
	result_grid.columns = 3
	result_grid.add_theme_constant_override("h_separation", 18)
	result_grid.add_theme_constant_override("v_separation", 6)
	rv.add_child(result_grid)
	lbl_result_note = _label("", 13, COL_DIM)
	lbl_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(lbl_result_note)
	btn_next = _button("NEXT ROUND  >>", Color("1c7c54"), _on_next_pressed)
	btn_next.custom_minimum_size.y = 46
	rv.add_child(btn_next)
	result_panel.visible = false
	map_area.add_child(result_panel)

	# Side panel
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(310, 0)
	side.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 8, 1, 12))
	body.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 6)
	scroll.add_child(sv)

	sv.add_child(_label("SELECTED GROUP", 12, COL_ACCENT))
	lbl_group = _wrap_label(13, COL_TEXT)
	sv.add_child(lbl_group)
	sv.add_child(HSeparator.new())
	sv.add_child(_label("ROUTE", 12, COL_ACCENT))
	lbl_route = _wrap_label(13, COL_TEXT)
	sv.add_child(lbl_route)
	lbl_hint = _wrap_label(13, COL_ACCENT)
	lbl_hint.custom_minimum_size.y = 36
	sv.add_child(lbl_hint)

	btn_dispatch = _button("DISPATCH", Color("1c7c54"), _dispatch)
	btn_dispatch.custom_minimum_size.y = 48
	btn_dispatch.add_theme_font_size_override("font_size", 16)
	sv.add_child(btn_dispatch)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	btn_undo = _button("UNDO (Z)", Color("2c3c58"), _undo)
	btn_clear = _button("CLEAR (C)", Color("2c3c58"), _clear_route)
	for b in [btn_undo, btn_clear]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	sv.add_child(row)

	sv.add_child(HSeparator.new())
	sv.add_child(_label("GROUPS", 12, COL_ACCENT))
	lbl_groups = _wrap_label(13, COL_TEXT)
	sv.add_child(lbl_groups)

	sv.add_child(HSeparator.new())
	sv.add_child(_label("LEGEND", 12, COL_ACCENT))
	legend = GridContainer.new()  # filled by set_visual_style()
	legend.columns = 4
	legend.add_theme_constant_override("h_separation", 6)
	legend.add_theme_constant_override("v_separation", 4)
	sv.add_child(legend)

	sv.add_child(HSeparator.new())
	sv.add_child(_label("OPS LOG", 12, COL_ACCENT))
	lbl_log = _wrap_label(11, COL_DIM)
	sv.add_child(lbl_log)
	var keys := _wrap_label(11, COL_DIM)
	sv.add_child(keys)
	keys.text = "Keys: Enter dispatch, Z/Backspace undo, C clear, Tab next group, Esc deselect, V map style. Tap an earlier route tile to cut back to it."


func _style(bg_color: Color, edge: Color, radius: int, border: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = edge
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _wrap_label(font_size: int, color: Color) -> Label:
	var l := _label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


func _button(text: String, color: Color, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 38
	b.add_theme_stylebox_override("normal", _style(color, color.lightened(0.25), 6, 1, 6))
	b.add_theme_stylebox_override("hover", _style(color.lightened(0.12), color.lightened(0.4), 6, 1, 6))
	b.add_theme_stylebox_override("pressed", _style(color.darkened(0.2), color.lightened(0.25), 6, 1, 6))
	b.add_theme_stylebox_override("disabled", _style(Color("19212e"), Color("273246"), 6, 1, 6))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", COL_DIM)
	b.pressed.connect(callback)
	return b
