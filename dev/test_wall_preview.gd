extends "res://dev/test_case.gd"

# Dev-only headless test for the WALL PLACEMENT GHOST shaping (the hover-drop preview). obstacles
# .preview_wall_configs(cell) must return the SAME piece shape build_world would give the cell, so the
# ghost shows the real horizontal / vertical / corner / T / cross look. Also checks the FloorManager ghost
# pool exists. Text-only (the shaping is pure geometry; rendering is verified by eye).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_wall_preview.tscn

func _has_full(cfgs: Array) -> bool:
	for c in cfgs:
		if c["width"] == 0.0:
			return true
	return false

func _has_thin(cfgs: Array, cap: float) -> bool:
	for c in cfgs:
		if c["width"] == cap:
			return true
	return false

func _ready() -> void:
	var main: Node = await boot_main()
	var obs = main.get_node("World/Obstacles")
	var fm = main.get_node("World/FloorManager")
	var cap: float = obs.CAP_HEIGHT

	# ghost pool present on FloorManager (2 reusable preview wall_segments)
	_check("FloorManager has a 2-node wall ghost pool", fm._wall_ghost.size() == 2)
	_check("ghost nodes are in preview mode", fm._wall_ghost[0].preview and fm._wall_ghost[1].preview)

	obs.apply_map([], [], []) # clear all walls
	await get_tree().process_frame
	var c := Vector2i(20, 20) # the hovered (empty) cell

	# lone: one thin post
	var cfgs: Array = obs.preview_wall_configs(c)
	_check("lone cell: 1 piece", cfgs.size() == 1)
	_check("lone cell: it is a thin post", cfgs[0]["width"] == cap)

	# horizontal: one full-width piece (a left neighbour, nothing vertical)
	obs.add_wall(Vector2i(19, 20))
	cfgs = obs.preview_wall_configs(c)
	_check("horizontal: 1 full-width piece", cfgs.size() == 1 and _has_full(cfgs))

	# corner: add an above neighbour -> a trimmed L-arm + a thin vertical rail (2 pieces, no full width)
	obs.add_wall(Vector2i(20, 19))
	cfgs = obs.preview_wall_configs(c)
	_check("corner: 2 pieces", cfgs.size() == 2)
	_check("corner: an L-arm + a thin rail (no full-width piece)", not _has_full(cfgs) and _has_thin(cfgs, cap))

	# cross: add right + below too -> a full-width horizontal piece + a thin vertical rail
	obs.add_wall(Vector2i(21, 20))
	obs.add_wall(Vector2i(20, 21))
	cfgs = obs.preview_wall_configs(c)
	_check("cross: 2 pieces", cfgs.size() == 2)
	_check("cross: full-width horizontal + thin rail", _has_full(cfgs) and _has_thin(cfgs, cap))

	# vertical: only above/below neighbours -> a single thin rail
	obs.apply_map([], [], [])
	await get_tree().process_frame
	obs.add_wall(Vector2i(20, 19))
	obs.add_wall(Vector2i(20, 21))
	cfgs = obs.preview_wall_configs(c)
	_check("vertical: 1 thin rail piece", cfgs.size() == 1 and cfgs[0]["width"] == cap)

	finish()
