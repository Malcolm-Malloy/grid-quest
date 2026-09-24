extends "res://dev/test_case.gd"

# Dev-only test for orientation-aware wall/door connection (ROADMAP "Wall connects to a perpendicular
# door" fix): a wall's corner logic treats a neighbouring DOOR as part of its wall line only if the door's
# orientation matches the direction. A "horizontal" door continues a HORIZONTAL line; a "vertical" door a
# VERTICAL line. So a wall no longer connects to a perpendicular door (e.g. a closet's side wall vs its
# front door). Checked via obstacles._in_wall_line on the default map's real doors.
# Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_door_orient.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	await get_tree().process_frame # let build_world (and _gate_orient) settle
	var obs = main.get_node("World/Obstacles")

	var v_door := Vector2i(10, 5) # default map: a VERTICAL door
	var h_door := Vector2i(8, 7)  # default map: a HORIZONTAL door
	var wall := Vector2i(6, 3)    # a wall
	var empty := Vector2i(2, 2)   # open ground

	_check("setup: (10,5) is a vertical door", obs.door_at(v_door).get("orientation", "") == "vertical")
	_check("setup: (8,7) is a horizontal door", obs.door_at(h_door).get("orientation", "") == "horizontal")

	# a VERTICAL door continues a vertical line, NOT a horizontal one
	_check("vertical door: in a VERTICAL line", obs._in_wall_line(v_door, false))
	_check("vertical door: NOT in a horizontal line", not obs._in_wall_line(v_door, true))

	# a HORIZONTAL door continues a horizontal line, NOT a vertical one
	_check("horizontal door: in a HORIZONTAL line", obs._in_wall_line(h_door, true))
	_check("horizontal door: NOT in a vertical line", not obs._in_wall_line(h_door, false))

	# a wall is part of a line in BOTH directions
	_check("wall: in a horizontal line", obs._in_wall_line(wall, true))
	_check("wall: in a vertical line", obs._in_wall_line(wall, false))

	# open ground is in neither
	_check("empty cell: in neither direction", not obs._in_wall_line(empty, true) and not obs._in_wall_line(empty, false))

	finish()
