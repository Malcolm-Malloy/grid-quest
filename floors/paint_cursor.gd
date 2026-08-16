extends Node2D

# A plain grid-cell / quarter cursor for the Cell and Quarter paint scopes. Unlike the room
# highlight (FloorHighlightMask, which traces the visible floor and is occluded by walls and the
# player), this just outlines the exact square the next paint will write, so the scope reads at a
# glance. Drawn in World space (a child of FloorManager) so it lines up with the grid, at a high
# z_index so it sits above the walls and player like an editor cursor should.

# role colours, matching the editor coloured-highlight palette: green = adding terrain,
# red = erasing (destructive). Cell/Fine placement uses ADD, the Erase tool uses ERASE.
const ADD_FILL := Color(0.25, 0.85, 0.35, 0.22)
const ADD_LINE := Color(0.25, 0.85, 0.35, 0.95)
const ERASE_FILL := Color(0.95, 0.15, 0.15, 0.22)
const ERASE_LINE := Color(0.95, 0.15, 0.15, 0.95)

var _rect := Rect2() # zero size = hidden
var _fill := ADD_FILL
var _line := ADD_LINE

func show_rect(r: Rect2) -> void:
	if r == _rect:
		return
	_rect = r
	queue_redraw()

# green while placing terrain (adding), red while erasing (destructive)
func set_erasing(erasing: bool) -> void:
	var f: Color = ERASE_FILL if erasing else ADD_FILL
	if f == _fill:
		return
	_fill = f
	_line = ERASE_LINE if erasing else ADD_LINE
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
