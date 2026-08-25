extends Node

# Dev-only headless test for the DOOR-mode hover GHOST: FloorManager shows a translucent gate.gd preview
# auto-oriented to the wall run under the cursor (horizontal between L/R walls, vertical between up/down
# walls, else the R-flippable default), mirroring _place_door_at. Text-only (rendering is verified by eye).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_door_preview.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var obs = main.get_node("World/Obstacles")
	var fm = main.get_node("World/FloorManager")

	_check("FloorManager has a door preview node", fm._door_preview != null)
	_check("the door preview is in preview mode", fm._door_preview.preview)

	obs.apply_map([], [], []) # clear all walls
	await get_tree().process_frame
	var c := Vector2i(20, 20)

	# horizontal run (walls left + right) -> a horizontal door
	obs.add_wall(Vector2i(19, 20))
	obs.add_wall(Vector2i(21, 20))
	fm._show_door_ghost(c, obs)
	_check("door between L/R walls is horizontal", fm._door_preview.orientation == "horizontal")
	_check("door ghost is visible", fm._door_preview.visible)

	# vertical run (walls above + below) -> a vertical door
	obs.apply_map([], [], [])
	await get_tree().process_frame
	obs.add_wall(Vector2i(20, 19))
	obs.add_wall(Vector2i(20, 21))
	fm._show_door_ghost(c, obs)
	_check("door between up/down walls is vertical", fm._door_preview.orientation == "vertical")

	# open space (no adjacent structure) -> the R-flippable default (_door_orient)
	obs.apply_map([], [], [])
	await get_tree().process_frame
	fm._door_orient = "vertical"
	fm._show_door_ghost(c, obs)
	_check("door in open space uses the default orientation", fm._door_preview.orientation == "vertical")

	# hiding clears it
	fm._hide_door_ghost()
	_check("hide clears the door ghost", not fm._door_preview.visible)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
