class_name PlacementGhosts
extends Node2D

# The lifted, translucent previews of what a placement click would build, shown on hover in the WALL,
# DOOR and BRIDGE modes: the REAL wall shape (horizontal / vertical / corner / T / cross, in the armed
# colour + material), the closed door auto-oriented to the wall run it would bridge, and the bridge
# deck oriented across the water. FloorManager decides WHEN (hover, mode, bounds); this owns the nodes
# and how each is configured. Each preview dedupes, so a still cursor costs nothing.

const BRIDGE_LIFT := 6.0 # px the bridge deck floats above its cell

var walls: Array[WallSegment] = [] # 2 reused wall segments: a cell gets at most a horizontal piece + a rail
var door: Gate                     # gate.gd in preview mode
var bridge: Node2D                 # bridge.gd in preview mode
var _obs: Obstacles
var _wall_key := ""                # dedupe: cell + colour + material + piece-count
var _door_key := ""                # dedupe: cell + orientation

func setup(obs: Obstacles) -> void:
	_obs = obs
	for _i in 2:
		var wp := WallSegment.new()
		wp.preview = true
		wp.visible = false
		add_child(wp)
		walls.append(wp)
	door = Gate.new()
	door.preview = true
	door.visible = false
	add_child(door)
	bridge = Node2D.new()
	bridge.set_script(load("res://world/bridge.gd"))
	bridge.preview = true
	bridge.visible = false
	add_child(bridge)

func hide_all() -> void:
	hide_wall()
	hide_door()
	hide_bridge()

# the wall a click on `cell` would place: Obstacles computes the piece config(s) the cell would get (same
# shaping as build_world), applied to the reused segments with the armed wall colour + material
func show_wall(cell: Vector2i) -> void:
	if _obs == null:
		return
	var configs: Array = _obs.preview_wall_configs(cell)
	var key := "%s|%s|%s|%d" % [cell, EditorState.wall_color, EditorState.wall_mat, configs.size()]
	if key == _wall_key:
		return # same cell + brush + shape: leave the ghost as-is
	_wall_key = key
	var center := Grid.cell_center(cell)
	for i in walls.size():
		var wp := walls[i]
		if i < configs.size():
			var cfg: Dictionary = configs[i]
			wp.run_length = int(cfg["run_length"])
			wp.align_offset_x = float(cfg["align"])
			wp.seg_x_start = float(cfg["x_start"])
			wp.seg_width = float(cfg["width"])
			wp.cell_colors = [EditorState.wall_color]
			wp.cell_materials = [EditorState.wall_mat]
			wp.position = center
			wp.visible = true
			wp.queue_redraw()
		else:
			wp.visible = false

func hide_wall() -> void:
	if _wall_key == "":
		return
	_wall_key = ""
	for wp in walls:
		wp.visible = false

# the door a click on `cell` would place, auto-oriented exactly like FloorManager._place_door_at (the wall
# run it bridges, else the R-flippable default), drawn closed at the cell centre
func show_door(cell: Vector2i) -> void:
	if _obs == null:
		return
	var orient: String = _obs.wall_run_orientation(cell)
	if orient == "":
		orient = EditorState.door_orient
	var key := "%s|%s" % [cell, orient]
	if key == _door_key and door.visible:
		return
	_door_key = key
	door.set_preview_orientation(orient)
	door.position = Grid.cell_center(cell)
	door.visible = true

func hide_door() -> void:
	if not door.visible:
		return
	_door_key = ""
	door.visible = false

# the bridge deck a click on `cell` would place, oriented `orient`, lifted a few px over the cell
func show_bridge(cell: Vector2i, orient: String) -> void:
	bridge.orientation = orient
	bridge.position = Grid.cell_center(cell) - Vector2(0, BRIDGE_LIFT)
	bridge.visible = true
	bridge.queue_redraw()

func hide_bridge() -> void:
	bridge.visible = false
