extends Control
## Evac Grid - main controller.
## Owns round state and wires the pieces together:
##   MapGenerator -> CityMap      layout, hazards, BFS pathfinding
##   MapView                      drawing + pointer input -> route editing here
##   RouteValidator               route legality checks
##   SurvivorGroup                tile-by-tile movement
##   HazardManager                fire that spreads along the roads
##   ScoreKeeper                  transparent scoring
## The tablet UI is built in code so the scene file stays minimal.
## The map's look is one VisualTheme, picked here (see `visual_style`) and
## handed to MapView and the legend; nothing else depends on it.

const COL_BG := Color("0a0f1a")
const COL_BEZEL := Color("12161d")
const COL_BEZEL_EDGE := Color("6a7588")
const COL_PANEL := Color("141c2b")
const COL_PANEL_EDGE := Color("3a475c")
const COL_MODULE := Color("1a2230")
const COL_MODULE_EDGE := Color("46546b")
const COL_TEXT := Color("d7e1f0")
const COL_DIM := Color("7f8ea8")
const COL_ACCENT := Color("38c6f4")
const COL_ALERT := Color("ff4d3d")
const COL_OK := Color("39d98a")
const COL_WARN := Color("ffb020")
const LOG_LINES := 6
const LOG_SHOWN := 3
const MAX_STRIKES := 6
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
## A run lasts until a round is failed (game over); TRY AGAIN starts a new
## run from round 1.
var run_saved := 0       ## survivors delivered this run, the failed round included
var best_score := 0      ## best final score on this device, loaded at start-up
var best_round := 0      ## round reached on that best run
var new_best := false    ## the run that just ended beat the stored best
## Where the best score is kept; tests point it at a scratch file.
var best_score_path := "user://best_score.cfg"

var map: CityMap
var groups: Array[SurvivorGroup] = []
var hazards := HazardManager.new()
var scorer := ScoreKeeper.new()
var selected: SurvivorGroup = null
var stop_target: SurvivorGroup = null  ## moving group the STOP button halts (last dispatched or tapped)
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
var lbl_log: Label
var group_box: VBoxContainer
var group_leds: Array[UiWidgets.Led] = []
var group_btns: Array[Button] = []
var route_led: UiWidgets.Led
var strike_leds: Array[UiWidgets.Led] = []
var help_box: VBoxContainer
var alert_led: UiWidgets.Led
var btn_dispatch: Button
var btn_undo: Button
var btn_clear: Button
var alert_panel: PanelContainer
var lbl_alert: Label
var result_panel: PanelContainer
var lbl_result_title: Label
var lbl_result_sub: Label
var lbl_result_saved: Label
var lbl_result_saved_title: Label
var lbl_result_total: Label
var lbl_result_total_title: Label
var result_banner: PanelContainer
var result_led: UiWidgets.Led
var result_stars: Array[UiWidgets.Led] = []
var result_pips: HFlowContainer
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
	_load_best_score()
	_start_round()


# --- Round flow -----------------------------------------------------------------

func _start_round() -> void:
	map = MapGenerator.build_round(round_num, rng)
	groups.clear()
	for i in map.survivor_starts.size():
		groups.append(SurvivorGroup.new(i, char(65 + i), map.survivor_starts[i], map.survivor_sizes[i]))
	hazards = HazardManager.new()
	hazards.setup(round_num, rng)
	for g in groups:
		g.fire_lethal = hazards.fire_lethal
		g.smoke_drain = hazards.smoke_drain
	hazards.place_starting_fires(map, groups)
	scorer = ScoreKeeper.new()
	selected = null
	stop_target = null
	route.clear()
	round_time = 0.0
	plan_clock_start = 0.0
	round_over = false
	log_lines.clear()
	map_view.reset_effects()
	_build_group_rows()
	result_panel.visible = false
	alert_panel.visible = false
	_log("Round %d (%s): %d groups, %d fire(s) burning, spreading in %ds, %d more reported during the round%s." % [
		round_num, _difficulty_name(), groups.size(), map.fires.size(), roundi(hazards.grace), hazards.spot_fires,
		"" if hazards.fire_lethal else " (training: groups stop before fire)"])
	if round_num == 1 and best_score > 0:
		_log("New run. Best score to beat: %d (round %d)." % [best_score, best_round])
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
		for fire in hazards.update(delta, map, groups):
			_on_hazard(fire)
		for spot in hazards.spotted:
			map_view.popup(spot, "FIRE REPORTED", COL_WARN)
			_log("FIRE REPORTED at (%d, %d) - it ignites in %.0fs." % [spot.x, spot.y, hazards.spot_warning])
		_check_round_end()
	_update_ui()


func _on_group_event(g: SurvivorGroup, ev: Dictionary) -> void:
	var tile: Vector2i = ev["tile"]
	match ev["type"]:
		"halted":
			if ev.get("manual", false):
				_log("Group %s stopped at (%d, %d)." % [g.label, tile.x, tile.y])
			else:
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
			if ev.get("cause", "") == "fire":
				var count: int = ev.get("count", 0)
				var pts := 0
				for i in count:
					pts += scorer.record_casualty()
				map_view.popup(tile, "-%d survivors (%d)" % [count, pts], COL_ALERT)
				_log("Group %s was caught by the fire: %d lost (%d)." % [g.label, count, pts])
			else:
				_log("Group %s was lost in the smoke." % g.label)


func _on_hazard(fire: Vector2i) -> void:
	map_view.alert_tiles.append(fire)
	map_view.popup(fire, "FIRE!", COL_ALERT)
	var hit: Array[String] = []
	for g in groups:
		if g.remaining_contains(fire):
			# Training round only: the group stops by itself before the fire.
			# From round 2 the operator has to press STOP.
			if not hazards.fire_lethal:
				g.request_halt(fire, round_time)
			hit.append(g.label)
	if hit.is_empty():
		_log("Fire reported at (%d, %d)." % [fire.x, fire.y])
	elif hazards.fire_lethal:
		_log("ALERT: fire at (%d, %d) is on the route of Group %s - STOP it!" % [fire.x, fire.y, ", ".join(PackedStringArray(hit))])
		_notify("Fire ahead of Group %s! Press STOP before it walks in." % hit[0], COL_ALERT)
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
	run_saved += scorer.delivered
	if last_round_success:
		banked_score += scorer.total()
	else:
		# Game over. The final score is what the run banked before this round.
		new_best = banked_score > best_score
		if new_best:
			best_score = banked_score
			best_round = round_num
			_save_best_score()
	selected = null
	route.clear()
	_show_results(total_survivors)


func _on_next_pressed() -> void:
	if last_round_success:
		round_num += 1
	else:
		# TRY AGAIN after a game over: a new run from round 1, on a new random map.
		round_num = 1
		banked_score = 0
		run_saved = 0
		new_best = false
	_start_round()


## Loads the best score. A missing, unreadable or malformed file counts as
## no best yet; it never stops the game.
func _load_best_score() -> void:
	best_score = 0
	best_round = 0
	var cfg := ConfigFile.new()
	if cfg.load(best_score_path) != OK:
		return
	var s: Variant = cfg.get_value("best", "score", 0)
	var r: Variant = cfg.get_value("best", "round", 0)
	if typeof(s) == TYPE_INT and typeof(r) == TYPE_INT:
		best_score = maxi(s, 0)
		best_round = maxi(r, 0)


## Stores the best score. A failed write is logged and play goes on.
func _save_best_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "score", best_score)
	cfg.set_value("best", "round", best_round)
	var err := cfg.save(best_score_path)
	if err != OK:
		push_warning("Could not save the best score to %s (error %d)." % [best_score_path, err])
		_log("Could not save the best score (error %d)." % err)


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
			stop_target = mover
			_notify("Group %s is en route. Press STOP to halt it." % mover.label, COL_DIM)
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
	elif map.is_smoldering(p):
		_notify("Warning: that road is smoldering and will catch fire soon.", COL_WARN)
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
	stop_target = selected
	plan_clock_start = round_time
	selected = null
	route.clear()
	var next := _first_group_in_state(SurvivorGroup.State.BLOCKED)
	if next != null:
		_select_group(next)
	else:
		_notify("Dispatched. Select the next group, and watch for hazard alerts.", COL_OK)


## UNDO while a route is being planned; STOP for a moving group otherwise.
func _undo() -> void:
	if selected == null:
		var g := _stop_candidate()
		if g != null:
			g.stop(round_time)
			_log("STOP: Group %s halting." % g.label)
			_notify("Group %s stopping. Draw a detour from where it halts, then DISPATCH." % g.label, COL_WARN)
		return
	if route.size() > 1:
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


## The moving group STOP would halt: the last one dispatched or tapped, else
## any moving group that is not already stopping.
func _stop_candidate() -> SurvivorGroup:
	if stop_target != null and stop_target.state == SurvivorGroup.State.MOVING and not stop_target.halt_requested:
		return stop_target
	for g in groups:
		if g.state == SurvivorGroup.State.MOVING and not g.halt_requested:
			return g
	return null


## Lethal rounds: a moving group with fire (or a smoldering tile) still ahead
## on its route, which walks into it unless the operator presses STOP.
func _group_heading_into_fire() -> SurvivorGroup:
	if not hazards.fire_lethal:
		return null
	for g in groups:
		if g.state != SurvivorGroup.State.MOVING or g.halt_requested:
			continue
		for i in range(g.index + 1, g.path.size()):
			if map.is_fire(g.path[i]) or map.is_smoldering(g.path[i]):
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


func _group_led_color(g: SurvivorGroup) -> Color:
	if g == selected:
		return COL_ACCENT
	match g.state:
		SurvivorGroup.State.WAITING:
			return COL_WARN
		SurvivorGroup.State.MOVING:
			return Color("5b8cff")
		SurvivorGroup.State.BLOCKED:
			return COL_ALERT
		SurvivorGroup.State.DELIVERED:
			return COL_OK
	return COL_DIM


## One LED + select button per group; rebuilt each round (the group count changes).
func _build_group_rows() -> void:
	for c in group_box.get_children():
		group_box.remove_child(c)
		c.queue_free()
	group_leds.clear()
	group_btns.clear()
	for g in groups:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var led := UiWidgets.Led.new(18.0)
		led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(led)
		var b := _button("", Color("232d40"), _on_group_row_pressed.bind(g))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		row.add_child(b)
		group_box.add_child(row)
		group_leds.append(led)
		group_btns.append(b)


func _on_group_row_pressed(g: SurvivorGroup) -> void:
	if round_over:
		return
	if g.state == SurvivorGroup.State.MOVING:
		# A moving group can't be planned for; picking it aims the STOP button.
		selected = null
		route.clear()
		stop_target = g
		_notify("Group %s is en route. Press STOP to halt it." % g.label, COL_DIM)
		return
	_select_group(g)


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
			["survivor", "Survivors"], ["route", "Your route"], ["fire", "Fire"], ["smolder", "Catching fire"],
			["smoke", "Smoke (-1 ppl)"]]
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
	map_view.smolder_time = hazards.smolder_time

	# Top bar
	lbl_round.text = "ROUND %d  |  %s" % [round_num, _difficulty_name().to_upper()]
	lbl_time.text = _fmt_time(round_time)
	lbl_score.text = "%d" % (banked_score + (0 if round_over else scorer.total()))
	if not round_over and _first_group_in_state(SurvivorGroup.State.WAITING) != null:
		var s := round_time - plan_clock_start
		var b := ScoreKeeper.planning_bonus(s)
		lbl_plan.text = "%.1fs  +%d" % [s, b]
		lbl_plan.add_theme_color_override("font_color", COL_OK if b > 40 else (COL_WARN if b > 0 else COL_ALERT))
	else:
		lbl_plan.text = "--"
		lbl_plan.add_theme_color_override("font_color", COL_DIM)

	# Group module: one LED row per group
	for i in groups.size():
		var g := groups[i]
		var blink_off := g.state == SurvivorGroup.State.BLOCKED and fmod(round_time, 0.6) > 0.3
		group_leds[i].set_state(_group_led_color(g), g.state != SurvivorGroup.State.LOST and not blink_off)
		var smoke_note := "   SMOKE -1 in %.1fs" % (g.smoke_drain - g.smoke_timer) if g.is_draining(map) else ""
		group_btns[i].text = "%sGroup %s   %d/%d people   %s%s" % [
			"> " if g == selected else "", g.label, g.survivors, g.initial_survivors, _state_text(g), smoke_note]
		group_btns[i].disabled = not (g.can_plan() or g.state == SurvivorGroup.State.MOVING)
	for i in strike_leds.size():
		strike_leds[i].set_state(COL_ALERT, i < scorer.lost)

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
	route_led.set_state(route_color, route_lit)
	btn_dispatch.disabled = not can_dispatch
	btn_dispatch.modulate = Color.WHITE.lerp(Color(1.3, 1.3, 1.3), 0.5 + 0.5 * sin(round_time * 6.0)) if can_dispatch else Color.WHITE
	if selected != null and selected.state == SurvivorGroup.State.BLOCKED:
		btn_dispatch.text = "DISPATCH DETOUR"
	elif selected != null:
		btn_dispatch.text = "DISPATCH GROUP %s" % selected.label
	else:
		btn_dispatch.text = "DISPATCH"
	# UNDO while planning a route; STOP while a group is moving and none is selected.
	var stopper := _stop_candidate() if selected == null and not round_over else null
	if stopper != null:
		btn_undo.text = "STOP GROUP %s" % stopper.label
		btn_undo.disabled = false
		btn_undo.modulate = Color(1.45, 0.7, 0.65)
	else:
		btn_undo.text = "UNDO"
		btn_undo.disabled = selected == null or route.size() <= 1
		btn_undo.modulate = Color.WHITE
	btn_clear.disabled = selected == null or route.size() <= 1

	# Ops log (latest lines only)
	lbl_log.text = "\n".join(PackedStringArray(log_lines.slice(maxi(0, log_lines.size() - LOG_SHOWN))))

	# Hazard alert banner: fire ahead of a moving group first, then halted groups.
	var danger := _group_heading_into_fire()
	var blocked: SurvivorGroup = null
	for g in groups:
		if g.state == SurvivorGroup.State.BLOCKED or (g.state == SurvivorGroup.State.MOVING and g.halt_requested):
			blocked = g
			break
	alert_panel.visible = (danger != null or blocked != null) and not round_over
	if danger != null:
		lbl_alert.text = "FIRE AHEAD  -  Group %s: press STOP (Z) or it walks into the fire" % danger.label
		alert_led.set_state(COL_ALERT, fmod(round_time, 0.3) < 0.15)
		alert_panel.modulate.a = 0.85 + 0.15 * sin(round_time * 12.0)
	elif blocked != null:
		var rs := round_time - blocked.blocked_since
		var action := "halting..." if blocked.state == SurvivorGroup.State.MOVING else "draw a detour"
		lbl_alert.text = "ROUTE BLOCKED  -  Group %s: %s   (%.1fs, +%d)" % [
			blocked.label, action, rs, ScoreKeeper.response_bonus(rs)]
		alert_led.set_state(COL_ALERT, fmod(round_time, 0.5) < 0.25)
		alert_panel.modulate.a = 0.85 + 0.15 * sin(round_time * 8.0)


## Round result panel. A failed round ends the run, so the same panel then
## shows GAME OVER with the run's final score, people saved and best score,
## above the failed round's own breakdown.
func _show_results(total_survivors: int) -> void:
	var ok := last_round_success
	var tone := COL_OK if ok else COL_ALERT
	lbl_result_title.text = "ROUND COMPLETE" if ok else "GAME OVER"
	lbl_result_title.add_theme_color_override("font_color", tone)
	lbl_result_sub.text = ("ROUND %d  |  %s" if ok else "REACHED ROUND %d  |  %s") % [round_num, _difficulty_name().to_upper()]
	result_led.set_state(tone, true)
	result_panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.07, 0.12, 0.97), tone, 14, 4, 0))
	var banner := _style(Color("0f2c1f") if ok else Color("33100f"), tone, 10, 0, 14)
	banner.corner_radius_bottom_left = 0
	banner.corner_radius_bottom_right = 0
	result_banner.add_theme_stylebox_override("panel", banner)

	lbl_result_saved_title.text = "PEOPLE SAVED" if ok else "PEOPLE SAVED THIS RUN"
	lbl_result_saved.text = "%d / %d" % [scorer.delivered, total_survivors] if ok else "%d" % run_saved
	lbl_result_saved.add_theme_color_override("font_color", tone)
	# Star rating: 3 = everyone saved, 2 = three quarters or more, 1 = cleared, 0 = failed.
	var ratio := float(scorer.delivered) / float(maxi(total_survivors, 1))
	var stars := 0 if not ok else (3 if ratio >= 1.0 else (2 if ratio >= 0.75 else 1))
	for i in result_stars.size():
		result_stars[i].set_state(COL_WARN, i < stars)
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
	if ok:
		lbl_result_total_title.text = "ROUND SCORE"
		lbl_result_total.text = "%+d" % scorer.total()
		lbl_result_total.add_theme_color_override("font_color", COL_WARN if scorer.total() >= 0 else COL_ALERT)
		lbl_result_note.text = "Total score: %d  -  the next round has a bigger city and more fires." % banked_score
		lbl_result_note.add_theme_color_override("font_color", COL_DIM)
		btn_next.text = "NEXT ROUND  >>"
	else:
		lbl_result_total_title.text = "FINAL SCORE"
		lbl_result_total.text = "%d" % banked_score
		lbl_result_total.add_theme_color_override("font_color", COL_WARN)
		var best := "NEW BEST!  Best score: %d (round %d)" % [best_score, best_round] if new_best \
				else ("Best score: %d (round %d)" % [best_score, best_round] if best_score > 0 else "No best score yet")
		lbl_result_note.text = "%s\nFewer than half got out. This round's %+d doesn't count. Try again from round 1." % [best, scorer.total()]
		lbl_result_note.add_theme_color_override("font_color", COL_WARN if new_best else COL_DIM)
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
	var ui_theme := Theme.new()
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
	bg.color = Color("06080c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Tablet bezel
	var bezel := PanelContainer.new()
	bezel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bezel.offset_left = 8
	bezel.offset_top = 8
	bezel.offset_right = -8
	bezel.offset_bottom = -8
	# Thick rounded tablet frame: extra room at the top and bottom for the camera and home bar.
	var frame_style := _style(COL_BEZEL, COL_BEZEL_EDGE, 36, 3, 16)
	frame_style.content_margin_top = 30
	frame_style.content_margin_bottom = 30
	bezel.add_theme_stylebox_override("panel", frame_style)
	add_child(bezel)
	# Front camera and home bar, drawn on the frame but ignoring input.
	var hw := Control.new()
	hw.set_anchors_preset(Control.PRESET_FULL_RECT)
	hw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hw)
	var cam := UiWidgets.Led.new(9.0)
	cam.set_state(Color("3a6a9a"), false)
	hw.add_child(cam)
	cam.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 0)
	cam.offset_top = 16
	cam.offset_bottom = 25
	var home := PanelContainer.new()
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.custom_minimum_size = Vector2(140, 5)
	home.add_theme_stylebox_override("panel", _style(Color("56627a"), Color("56627a"), 3, 0, 0))
	hw.add_child(home)
	home.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 0)
	home.offset_top = -24
	home.offset_bottom = -19
	# The screen itself, inset in the frame.
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _style(COL_BG, Color("0b0f17"), 14, 2, 10))
	screen.clip_contents = true
	bezel.add_child(screen)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	screen.add_child(vbox)

	# Top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 6, 3, 8))
	vbox.add_child(top)
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 14)
	top.add_child(top_h)
	top_h.add_child(_label("EVAC GRID", 22, COL_ACCENT))
	top_h.add_child(_label("RESCUE OPS", 12, COL_DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(spacer)
	lbl_round = UiWidgets.Lcd.new("ROUND 1", 16, COL_TEXT)
	lbl_plan = UiWidgets.Lcd.new("PLAN --", 18, COL_OK)
	lbl_time = UiWidgets.Lcd.new("00:00.0", 24, COL_ALERT)
	lbl_score = UiWidgets.Lcd.new("0", 20, COL_WARN)
	lbl_plan.custom_minimum_size.x = 200
	lbl_time.custom_minimum_size.x = 130
	lbl_score.custom_minimum_size.x = 120
	lbl_round.custom_minimum_size.x = 170
	for pair in [["PLAN", lbl_plan], ["TIME", lbl_time], ["SCORE", lbl_score], ["", lbl_round]]:
		if pair[0] != "":
			top_h.add_child(_label(pair[0], 11, COL_DIM))
		top_h.add_child(pair[1])

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
	alert_panel.add_theme_stylebox_override("panel", _style(Color("5c0d12"), COL_ALERT, 6, 3, 10))
	var alert_h := HBoxContainer.new()
	alert_h.add_theme_constant_override("separation", 12)
	alert_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alert_panel.add_child(alert_h)
	alert_led = UiWidgets.Led.new(22.0)
	alert_led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alert_h.add_child(alert_led)
	lbl_alert = _label("", 17, Color.WHITE)
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
	result_panel.custom_minimum_size = Vector2(560, 0)
	result_panel.add_theme_stylebox_override("panel", _style(Color(0.04, 0.07, 0.12, 0.97), COL_ACCENT, 14, 4, 0))
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
	lbl_result_saved_title = _label("PEOPLE SAVED", 11, COL_DIM)
	saved_box.add_child(lbl_result_saved_title)
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
		var star := UiWidgets.Led.new(28.0)
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
	lbl_result_total_title = _label("ROUND SCORE", 16, COL_TEXT)
	total_h.add_child(lbl_result_total_title)
	var total_gap := Control.new()
	total_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_h.add_child(total_gap)
	lbl_result_total = UiWidgets.Lcd.new("+0", 30, COL_WARN)
	lbl_result_total.custom_minimum_size.x = 170
	total_h.add_child(lbl_result_total)

	lbl_result_note = _label("", 13, COL_DIM)
	lbl_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_box.add_child(lbl_result_note)
	btn_next = _button("NEXT ROUND  >>", Color("1c7c54"), _on_next_pressed)
	btn_next.custom_minimum_size.y = 52
	btn_next.add_theme_stylebox_override("normal", _style(Color("1c7c54"), Color("5be3a0"), 8, 3, 8))
	btn_next.add_theme_stylebox_override("hover", _style(Color("23956a"), Color("8cf0bf"), 8, 3, 8))
	btn_next.add_theme_stylebox_override("pressed", _style(Color("14583c"), Color("5be3a0"), 8, 3, 8))
	body_box.add_child(btn_next)
	result_panel.visible = false
	map_area.add_child(result_panel)

	# Side panel: stacked control-unit modules
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	side.add_theme_stylebox_override("panel", _style(COL_PANEL, COL_PANEL_EDGE, 6, 3, 8))
	body.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 8)
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
	lbl_hint = _wrap_label(12, COL_ACCENT)
	lbl_hint.custom_minimum_size.y = 34
	mr.add_child(lbl_hint)

	btn_dispatch = _button("DISPATCH", Color("1c7c54"), _dispatch)
	btn_dispatch.custom_minimum_size.y = 64
	btn_dispatch.add_theme_font_size_override("font_size", 20)
	btn_dispatch.add_theme_stylebox_override("normal", _style(Color("1c7c54"), Color("5be3a0"), 8, 4, 8))
	btn_dispatch.add_theme_stylebox_override("hover", _style(Color("23956a"), Color("8cf0bf"), 8, 4, 8))
	btn_dispatch.add_theme_stylebox_override("pressed", _style(Color("14583c"), Color("5be3a0"), 8, 4, 8))
	btn_dispatch.add_theme_stylebox_override("disabled", _style(Color("19212e"), Color("2c384c"), 8, 4, 8))
	mr.add_child(btn_dispatch)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	btn_undo = _button("UNDO", Color("2c3c58"), _undo)
	btn_clear = _button("CLEAR", Color("2c3c58"), _clear_route)
	for b in [btn_undo, btn_clear]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	mr.add_child(row)

	# Losses module: one red light per survivor lost this round
	var ml := _add_module(sv, "PEOPLE LOST")
	var strikes := HBoxContainer.new()
	strikes.add_theme_constant_override("separation", 10)
	ml.add_child(strikes)
	for i in MAX_STRIKES:
		var led := UiWidgets.Led.new(18.0)
		strikes.add_child(led)
		strike_leds.append(led)

	# Ops log module
	var mo := _add_module(sv, "OPS LOG")
	lbl_log = _wrap_label(11, COL_DIM)
	mo.add_child(lbl_log)

	# Help (legend + keys), hidden until asked for
	var btn_help := _button("? LEGEND / KEYS", Color("2c3c58"), func() -> void: help_box.visible = not help_box.visible)
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
	keys.text = "Keys: Enter dispatch, Z/Backspace undo (STOP while a group moves), C clear, Tab next group, Esc deselect, V map style. Tap an earlier route tile to cut back to it."
	help_box.add_child(keys)


## A framed control-unit module with a title; returns the box to fill.
func _add_module(parent: Control, title: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _style(COL_MODULE, COL_MODULE_EDGE, 4, 2, 8))
	parent.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	box.add_child(_label(title, 11, COL_ACCENT))
	return box


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
	l.add_theme_font_size_override("font_size", font_size + 2)
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
