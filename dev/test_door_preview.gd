extends "res://dev/test_case.gd"

# Dev-only headless test for the DOOR-mode hover GHOST: FloorManager shows a translucent gate.gd preview
# auto-oriented to the wall run under the cursor (horizontal between L/R walls, vertical between up/down
# walls, else the R-flippable default), mirroring _place_door_at. Text-only (rendering is verified by eye).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_door_preview.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var obs = main.get_node("World/Obstacles")
	var fm = main.get_node("World/FloorManager")

	_check("FloorManager has a door preview node", fm.ghosts.door != null)
	_check("the door preview is in preview mode", fm.ghosts.door.preview)

	obs.apply_map([], [], []) # clear all walls
	await get_tree().process_frame
	var c := Vector2i(20, 20)

	# horizontal run (walls left + right) -> a horizontal door
	obs.add_wall(Vector2i(19, 20))
	obs.add_wall(Vector2i(21, 20))
	fm.ghosts.show_door(c)
	_check("door between L/R walls is horizontal", fm.ghosts.door.orientation == Grid.Orient.HORIZONTAL)
	_check("door ghost is visible", fm.ghosts.door.visible)

	# vertical run (walls above + below) -> a vertical door
	obs.apply_map([], [], [])
	await get_tree().process_frame
	obs.add_wall(Vector2i(20, 19))
	obs.add_wall(Vector2i(20, 21))
	fm.ghosts.show_door(c)
	_check("door between up/down walls is vertical", fm.ghosts.door.orientation == Grid.Orient.VERTICAL)

	# open space (no adjacent structure) -> the R-flippable default (_door_orient)
	obs.apply_map([], [], [])
	await get_tree().process_frame
	EditorState.door_orient = Grid.Orient.VERTICAL
	fm.ghosts.show_door(c)
	_check("door in open space uses the default orientation", fm.ghosts.door.orientation == Grid.Orient.VERTICAL)

	# hiding clears it
	fm.ghosts.hide_door()
	_check("hide clears the door ghost", not fm.ghosts.door.visible)

	finish()
