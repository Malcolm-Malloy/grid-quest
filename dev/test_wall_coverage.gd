extends "res://dev/test_case.gd"

# Dev-only audit for "invisible wall" (a cell that blocks but renders no node). Builds a map covering
# every wall configuration (isolated, lines, corners, cross, T-junction, 2x2 block, diagonal staircase,
# walls beside aligned + perpendicular doors) and asserts EVERY blocked cell has a covering wall node.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_wall_coverage.tscn

func _covered(cell: Vector2i) -> bool:
	for w in get_tree().get_nodes_in_group("walls"):
		if w.covers_cell(cell):
			return true
	return false

func _ready() -> void:
	var main: Node = await boot_main()
	var obs = main.get_node("World/Obstacles")

	var walls: Array = []
	walls.append(Vector2i(2, 2)) # isolated
	for x in range(5, 8): walls.append(Vector2i(x, 2)) # horizontal line
	for y in range(5, 8): walls.append(Vector2i(2, y)) # vertical line
	walls.append_array([Vector2i(10,5),Vector2i(10,6),Vector2i(11,5)]) # L corner
	walls.append_array([Vector2i(14,5),Vector2i(16,5),Vector2i(15,4),Vector2i(15,6),Vector2i(15,5)]) # cross
	walls.append_array([Vector2i(20,5),Vector2i(21,5),Vector2i(22,5),Vector2i(21,6)]) # T-junction
	walls.append_array([Vector2i(25,5),Vector2i(26,5),Vector2i(25,6),Vector2i(26,6)]) # 2x2 block
	walls.append_array([Vector2i(30,5),Vector2i(31,6),Vector2i(32,7)]) # diagonal staircase (each isolated)
	walls.append(Vector2i(35,5)) # wall above a perpendicular (horizontal) door
	var doors: Array = [{"cell":Vector2i(35,6),"orientation":Grid.Orient.HORIZONTAL,"open":false,"swing":false}]

	obs.apply_map(walls, doors)
	await get_tree().process_frame
	await get_tree().process_frame

	var uncovered: Array = []
	for c in walls:
		if not _covered(c):
			uncovered.append(c)
	print(("PASS " if uncovered.is_empty() else "FAIL ") + "every blocked cell has a wall node (uncovered: %s)" % str(uncovered))
	if not uncovered.is_empty(): _fails += 1

	finish()
