extends Node2D
class_name PaintCursor

# A plain grid-cell / quarter cursor for the Cell and Quarter paint scopes. Unlike the room
# highlight (FloorHighlightMask, which traces the visible floor and is occluded by walls and the
# player), this just outlines the exact square the next paint will write, so the scope reads at a
# glance. Drawn in World space (a child of FloorManager) so it lines up with the grid, at a high
# z_index so it sits above the walls and player like an editor cursor should.

# role colours, matching the editor coloured-highlight palette (ROADMAP "Coloured highlight system"):
#   GROUND (orange) = terrain / floor paint, ADD (green) = additive placement (walls, doors, objects),
#   ERASE (red) = destructive removal. Terrain paint reads as a ground edit (orange), NOT "adding"
#   (green), which is reserved for placing structures/objects. Kept in sync with FloorHighlightMask.
enum Role { GROUND, ADD, ERASE }
const GROUND_FILL := Color(0.95, 0.55, 0.15, 0.22)
const GROUND_LINE := Color(0.95, 0.55, 0.15, 0.95)
const ADD_FILL := Color(0.25, 0.85, 0.35, 0.22)
const ADD_LINE := Color(0.25, 0.85, 0.35, 0.95)
const ERASE_FILL := Color(0.95, 0.15, 0.15, 0.22)
const ERASE_LINE := Color(0.95, 0.15, 0.15, 0.95)

var _rect := Rect2() # zero size = hidden
var _fill := GROUND_FILL
var _line := GROUND_LINE

func show_rect(r: Rect2) -> void:
	if r == _rect:
		return
	_rect = r
	queue_redraw()

# set the cursor's action colour: orange for terrain paint (GROUND), green for placement (ADD),
# red for erase (ERASE). See the Role palette above.
func set_role(role: Role) -> void:
	var f: Color
	var l: Color
	match role:
		Role.ERASE:
			f = ERASE_FILL; l = ERASE_LINE
		Role.ADD:
			f = ADD_FILL; l = ADD_LINE
		_:
			f = GROUND_FILL; l = GROUND_LINE
	if f == _fill:
		return
	_fill = f
	_line = l
	queue_redraw()

func hide_cursor() -> void:
	if _rect == Rect2():
		return
	_rect = Rect2()
	queue_redraw()

func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return
	draw_rect(_rect, _fill, true)
	draw_rect(_rect, _line, false, 2.0)
