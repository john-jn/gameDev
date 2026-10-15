class_name RouteValidator
extends RefCounted
## Checks an operator-drawn route against the current map state.
## The route is valid while every step so far is legal; it is "complete" once
## it ends on a SAFE tile. Hazards can appear after a route was drawn, so the
## game re-validates every frame and highlights the first bad tile.


static func validate(map: CityMap, route: Array[Vector2i], start: Vector2i) -> Dictionary:
	var result := {
		"valid": true,
		"complete": false,
		"bad_index": -1,
		"reason": "",
		"smoke": 0,
		"length": maxi(route.size() - 1, 0),
	}
	if route.is_empty() or route[0] != start:
		return _fail(result, 0, "Route must start at the selected group.")
	var seen := {}
	for i in route.size():
		var p := route[i]
		if seen.has(p):
			return _fail(result, i, "Route loops back on itself.")
		seen[p] = true
		if i > 0 and not map.is_adjacent(route[i - 1], p):
			return _fail(result, i, "Route has a gap - each step must touch the previous tile.")
		if map.is_fire(p):
			return _fail(result, i, "Route crosses a fire-blocked tile.")
		if not map.is_street(p):
			return _fail(result, i, "Route leaves the road network.")
		if map.is_safe(p) and i < route.size() - 1:
			return _fail(result, i + 1, "Route continues past the safe zone.")
		if i > 0 and map.is_smoke(p):
			result["smoke"] += 1
	result["complete"] = route.size() > 1 and map.is_safe(route[-1])
	if not result["complete"]:
		result["reason"] = "Incomplete - extend it to the SAFE zone."
	return result


static func _fail(result: Dictionary, index: int, reason: String) -> Dictionary:
	result["valid"] = false
	result["bad_index"] = index
	result["reason"] = reason
	return result
