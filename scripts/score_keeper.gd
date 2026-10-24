class_name ScoreKeeper
extends RefCounted
## Transparent per-round scoring. Each point source has its own bucket so the
## result screen can show exactly where every point came from.
##
##   Rescue      +50 per survivor delivered
##   Efficiency  up to +100 per delivered group = 100 * shortest / drawn length
##               (summed over each dispatch, shortest measured at dispatch time)
##   Planning    +80 per first dispatch, -4 per second of planning (min 0)
##   Response    +80 per detour after a hazard, -6 per second of response (min 0)
##   Casualties  -60 per survivor lost in smoke
##   Clear bonus +50 x round number when the round is not a loss

const RESCUE_PER_SURVIVOR := 50
const CASUALTY_PENALTY := 60
const EFFICIENCY_MAX := 100
const PLANNING_MAX := 80
const PLANNING_DECAY := 4.0
const RESPONSE_MAX := 80
const RESPONSE_DECAY := 6.0
const CLEAR_BONUS_PER_ROUND := 50

var rescue := 0
var efficiency := 0
var planning := 0
var response := 0
var casualty := 0
var clear_bonus := 0
var delivered := 0
var lost := 0
var groups_delivered := 0
var plan_times: Array[float] = []
var response_times: Array[float] = []


static func planning_bonus(seconds: float) -> int:
	return maxi(0, roundi(PLANNING_MAX - PLANNING_DECAY * seconds))


static func response_bonus(seconds: float) -> int:
	return maxi(0, roundi(RESPONSE_MAX - RESPONSE_DECAY * seconds))


## Records a dispatch and returns the time bonus it earned.
func record_dispatch(group: SurvivorGroup, seconds: float, is_reroute: bool, route_len: int, shortest_len: int) -> int:
	group.route_tiles_total += route_len
	group.shortest_tiles_total += shortest_len
	if is_reroute:
		var pts := response_bonus(seconds)
		response += pts
		response_times.append(seconds)
		return pts
	var pts := planning_bonus(seconds)
	planning += pts
	plan_times.append(seconds)
	return pts


func record_casualty() -> int:
	casualty -= CASUALTY_PENALTY
	lost += 1
	return -CASUALTY_PENALTY


## Returns {"rescue": int, "efficiency": int, "ratio": float}.
func record_delivery(group: SurvivorGroup) -> Dictionary:
	var r := group.survivors * RESCUE_PER_SURVIVOR
	var ratio := float(group.shortest_tiles_total) / float(maxi(group.route_tiles_total, 1))
	var e := roundi(EFFICIENCY_MAX * clampf(ratio, 0.0, 1.0))
	rescue += r
	efficiency += e
	delivered += group.survivors
	groups_delivered += 1
	return {"rescue": r, "efficiency": e, "ratio": ratio}


func finish_round(success: bool, round_num: int) -> void:
	clear_bonus = CLEAR_BONUS_PER_ROUND * round_num if success else 0


func total() -> int:
	return rescue + efficiency + planning + response + casualty + clear_bonus


## Rows of [label, detail, points] for the result screen.
func breakdown() -> Array:
	return [
		["People saved", "%d" % delivered, rescue],
		["Short routes", "direct paths", efficiency],
		["Fast planning", "sent quickly", planning],
		["Quick detours", "after a fire", response],
		["People lost", "%d" % lost, casualty],
		["Round bonus", "for clearing it" if clear_bonus > 0 else "round lost", clear_bonus],
	]


func _times_text(times: Array[float], noun: String) -> String:
	if times.is_empty():
		return "no %ss" % noun
	var sum := 0.0
	for s in times:
		sum += s
	return "%d %s(s), avg %.1fs" % [times.size(), noun, sum / times.size()]
