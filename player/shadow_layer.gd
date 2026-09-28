extends Node2D

var points: PackedVector2Array = []
# fully opaque: transparency is applied once at the group level (see ShadowGroup
# in main.tscn) after overlapping shadows are merged, not per-shape here, or
# overlapping shadows would still double-blend inside the group's own buffer
var shadow_color := Color(0.05, 0.08, 0.05, 1.0)

func setup(new_points: PackedVector2Array) -> void:
	points = new_points
	queue_redraw()

func _draw() -> void:
	if points.size() > 0:
		draw_colored_polygon(points, shadow_color)
