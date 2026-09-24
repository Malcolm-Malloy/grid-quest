extends "res://dev/test_case.gd"

# Dev-only headless test for where things may stand: FloorManager.is_walkable (the terrain rule the
# player and zone spawning share) case by case, then the REAL player stepping in PLAY: blocked by a wall
# and by a hole, free into open ground.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_walkable.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var w := main.get_node("World")
	var fm: FloorManager = w.get_node("FloorManager")
	var obs: Obstacles = w.get_node("Obstacles")
	var gb: GridBackground = w.get_node("GridBackground")
	var player = w.get_node("Player")
	var here := Vector2i(30, 20)
	var wall := here + Vector2i.RIGHT
	var hole := here + Vector2i.LEFT
	var water := here + Vector2i.DOWN
	obs.add_wall(wall)
	MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
	gb.set_absent_cells({hole: true})
	for q in Grid.quads_of(water):
		fm._quad_mat[q] = "water"
	_check("open ground is walkable", fm.is_walkable(here))
	_check("a wall is not", not fm.is_walkable(wall))
	_check("a hole is not", not fm.is_walkable(hole))
	_check("off the map is not", not fm.is_walkable(Vector2i(-1, 0)))
	_check("water is not", not fm.is_walkable(water))
	obs.add_bridge(water, "vertical")
	_check("bridged water is", fm.is_walkable(water))
	obs.remove_bridge(water)

	EditorMode.set_mode(EditorMode.Mode.PLAY)
	player.position = Grid.cell_center(here)
	player.target_position = player.position
	player.is_moving = false
	for dir in [["ui_right", "into a wall", here], ["ui_left", "into a hole", here], ["ui_up", "into open ground", here + Vector2i.UP]]:
		player.position = Grid.cell_center(here)
		player.target_position = player.position
		Input.action_press(dir[0])
		for i in 3:
			await get_tree().physics_frame
		Input.action_release(dir[0])
		for i in 40:
			await get_tree().physics_frame
		_check("stepping %s ends on %s" % [dir[1], dir[2]], Grid.cell_of(player.position) == dir[2])
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	finish()
