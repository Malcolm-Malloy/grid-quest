extends Node2D

# A plain grid-cell / quarter cursor for the Cell and Quarter paint scopes. Unlike the room
# highlight (FloorHighlightMask, which traces the visible floor and is occluded by walls and the
# player), this just outlines the exact square the next paint will write, so the scope reads at a
# glance. Drawn in World space (a child of FloorManager) so it lines up with the grid, at a high
# z_index so it sits above the walls and player like an editor cursor should.

const FILL := Color(0.95, 0.15, 0.15, 0.22)
const LINE := Color(0.95, 0.15, 0.15, 0.95)

var _rect := Rect2() # zero size = hidden

func show_rect(r: Rect2) -> void:
	if r == _rect:
		return
	_rect = r
	queue_redraw()

func hide_cursor() -> void:
	if _rect == Rect2():
		return
	_rect = Rect2()
	queue_redraw()

func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return
	draw_rect(_rect, FILL, true)
	draw_rect(_rect, LINE, false, 2.0)
