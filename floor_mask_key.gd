extends Node2D

# PROTOTYPE: draws the hovered room's floor shape in a solid magenta key colour, tagged onto
# the mask visibility layer only. The mask viewport renders this plus the real occluders, so
# the magenta that survives = the floor the player can actually see.

const CELL := 32
const KEY := Color(1.0, 0.0, 1.0, 1.0)

var cells: Dictionary = {}
var quads: Array = []

func set_shape(c: Dictionary, q: Array) -> void:
	cells = c
	quads = q
	queue_redraw()

func _draw() -> void:
	for c in cells:
		var cell: Vector2i = c
		draw_rect(Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL), KEY)
	for q in quads:
		draw_rect(q, KEY)
