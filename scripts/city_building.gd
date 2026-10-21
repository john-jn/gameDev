class_name CityBuilding
extends RefCounted
## One lot inside a city block: a building footprint or an open park.
## Pure map data. It records what stands where, never how it looks: renderers
## turn `kind` and `variant` into shapes, textures or scenes of their own, and
## gameplay only ever reads the tiles underneath (see CityMap).
## Lots are built by CityLayout after the roads are final, so they never sit on
## a road tile or a survivor start.

enum Kind { BUILDING, PARK }
## Gameplay role. Any BUILDING lot can carry SAFE_ZONE (CityMap.designate_safe_zone);
## the renderer highlights it whatever its variant.
enum Designation { NONE, SAFE_ZONE }

## Visual variants the layout picks from. Renderers wrap (variant % their own
## count), so adding or removing art never invalidates map data.
const VARIANT_COUNT := 5

var id := -1                        ## index in CityMap.buildings
var kind := Kind.BUILDING
var designation := Designation.NONE
var variant := 0
## Quarter turns clockwise of the lot's "front", 0 = facing south (down).
## Set from the entrance side, so a future sprite faces its street.
var rotation := 0
var cells: Array[Vector2i] = []     ## occupied tiles, row-major
var bounds := Rect2i()              ## smallest rectangle containing `cells`
## Open road tiles touching the footprint, row-major. Empty for lots buried
## inside a block.
var entrances: Array[Vector2i] = []
## The main entrance (one of `entrances`), or (-1, -1) (CityMap.NO_TILE).
var entrance := Vector2i(-1, -1)


func is_safe_zone() -> bool:
	return designation == Designation.SAFE_ZONE


func is_rect() -> bool:
	return cells.size() == bounds.get_area()


## The footprint as row bands of equal span: one rectangle for a rectangular
## lot, two for an L. Largest first.
func parts() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var spans := {}
	for c in cells:
		var s: Vector2i = spans.get(c.y, Vector2i(c.x, c.x))
		spans[c.y] = Vector2i(mini(s.x, c.x), maxi(s.y, c.x))
	for y in range(bounds.position.y, bounds.end.y):
		var s: Vector2i = spans[y]
		if not out.is_empty() and out[-1].end.y == y and out[-1].position.x == s.x and out[-1].end.x == s.y + 1:
			out[-1].size.y += 1
		else:
			out.append(Rect2i(s.x, y, s.y - s.x + 1, 1))
	out.sort_custom(func(a: Rect2i, b: Rect2i) -> bool:
		return a.get_area() > b.get_area() or (a.get_area() == b.get_area() and a.position.y < b.position.y))
	return out
