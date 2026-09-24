class_name Grid
extends RefCounted

# The map's coordinate system, in one place. Three grids share one origin (World-local pixels):
#   pixel   Vector2 in World space
#   cell    Vector2i, the 32px movement/structure grid
#   quarter Vector2i, the 16px floor grid; a cell is 2x2 quarters
# Every script converts between them through these helpers instead of re-deriving floori(x / 32).

const CELL := 32
const HALF := 16 # one floor quarter
const INVALID_CELL := Vector2i(-9999, -9999) # "no cell" sentinel for dedupe trackers

# the cell containing World-space point `p`
static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

# the quarter containing World-space point `p`
static func quad_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / HALF), floori(p.y / HALF))

# the cell a quarter belongs to (floor division, so negative quarters map correctly too)
static func cell_of_quad(q: Vector2i) -> Vector2i:
	return Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))

# the four quarters of a cell: TL, TR, BL, BR
static func quads_of(c: Vector2i) -> Array[Vector2i]:
	return [Vector2i(c.x * 2, c.y * 2), Vector2i(c.x * 2 + 1, c.y * 2),
			Vector2i(c.x * 2, c.y * 2 + 1), Vector2i(c.x * 2 + 1, c.y * 2 + 1)]

# a cell's centre / rect in World pixels
static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)

static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * CELL, c.y * CELL, CELL, CELL)

static func quad_rect(q: Vector2i) -> Rect2:
	return Rect2(q.x * HALF, q.y * HALF, HALF, HALF)

# the axis a door or bridge lies along. NONE is only an answer ("no wall run here"), never stored. A save
# file spells it "horizontal" / "vertical" (orient_name / orient_from convert at that boundary).
enum Orient { NONE, HORIZONTAL, VERTICAL }

static func orient_name(o: Orient) -> String:
	return "vertical" if o == Orient.VERTICAL else ("horizontal" if o == Orient.HORIZONTAL else "")

# anything but "vertical" reads as horizontal, as the renderers always treated it
static func orient_from(name: String) -> Orient:
	return Orient.VERTICAL if name == "vertical" else Orient.HORIZONTAL

static func flip(o: Orient) -> Orient:
	return Orient.HORIZONTAL if o == Orient.VERTICAL else Orient.VERTICAL
