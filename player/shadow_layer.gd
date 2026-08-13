extends Node2D

var points: PackedVector2Array = []
# fully opaque: transparency is applied once at the group level (see ShadowGroup
# in main.tscn) after overlapping shadows are merged, not per-shape here, or
# overlapping shadows would still double-blend inside the group's own buffer
var shadow_color := Color(0.05, 0.08, 0.05, 1.0)

func setup(new_points: PackedVector2Array, register_as_wall_shadow: bool = true) -> void:
	points = new_points
	if register_as_wall_shadow:
		add_to_group("wall_shadows")
	queue_redraw()

func _draw() -> void:
	if points.size() > 0:
		draw_colored_polygon(points, shadow_color)

func get_world_points() -> PackedVector2Array:
	# to_global applies this node's full transform (including the World's y-scale),
	# so the polygon lines up with the player's global position for the in-shadow test
	var world_points := PackedVector2Array()
	for p in points:
		world_points.append(to_global(p))
	return world_points
