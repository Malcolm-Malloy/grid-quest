extends Node

# Dev-only guard for the "shadow shows but the wall doesn't build" bug (ROADMAP "Investigate lag" area /
# wall building): a wall cell with no wall-LINE neighbour was skipped by BOTH build passes (horizontal
# needs a left/right neighbour, vertical an up/down one), yet spawn_shadows still cast a shadow for it, so
# a lone wall (or a wall whose only neighbour is a PERPENDICULAR door, after the orientation-aware fix)
# rendered as a floating shadow with no node. build_world now spawns a standalone thin rail for such cells.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_isolated_wall.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _covered(cell: Vector2i) -> bool:
	for w in get_tree().get_nodes_in_group("walls"):
		if w.covers_cell(cell):
			return true
	return false

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var obs = main.get_node("World/Obstacles")

	# a single isolated wall must spawn a node
	obs.apply_map([Vector2i(20, 20)], [])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("isolated wall (20,20) is in blocked_cells", obs.is_blocked(Vector2i(20, 20)))
	_check("isolated wall (20,20) spawns a wall node", _covered(Vector2i(20, 20)))

	# a wall whose ONLY neighbour is a perpendicular door must also spawn a node (a vertical wall above a
	# HORIZONTAL door: the door does not continue the vertical line, so the wall is otherwise orphaned)
	obs.apply_map([Vector2i(25, 25)], [{"cell": Vector2i(25, 26), "orientation": "horizontal", "open": false, "swing": false}])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("wall with only a perpendicular door spawns a node", _covered(Vector2i(25, 25)))

	# a normal connected wall still spawns (regression)
	obs.apply_map([Vector2i(30, 30), Vector2i(31, 30), Vector2i(32, 30)], [])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("normal horizontal wall still spawns nodes", _covered(Vector2i(30, 30)) and _covered(Vector2i(31, 30)) and _covered(Vector2i(32, 30)))

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
