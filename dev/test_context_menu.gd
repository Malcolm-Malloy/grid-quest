extends Node

# Dev-only headless test for the contextual right-click menu (ROADMAP "Right-click menu overhaul",
# item 4). The popup must show ONLY the section for the clicked target: Floor Textures on a floor
# cell, Wall Colour on a wall/door (structure) cell. The Grid toggle stays available regardless, and
# the floor submenu is titled "Floor Textures" (descriptive, not bare "Floor"). Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_context_menu.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

# index of the top-level menu item whose text == label, or -1 if absent (contextual = present or not)
func _idx_of(menu: PopupMenu, label: String) -> int:
	for i in menu.item_count:
		if menu.get_item_text(i) == label:
			return i
	return -1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	var menu: PopupMenu = fm._menu

	# --- floor cell: Floor Textures present (descriptive heading), Wall Colour absent ---
	var floor_cell := Vector2i(8, 4) # inside room A, no wall or door
	_check("setup: (8,4) has no structure", not obs.has_structure(floor_cell))
	fm._apply_menu_context(floor_cell)
	_check("floor cell: 'Floor Textures' section present", _idx_of(menu, "Floor Textures") != -1)
	_check("floor cell: 'Wall Colour' section absent", _idx_of(menu, "Wall Colour") == -1)
	_check("floor cell: Grid item present", menu.get_item_index(fm.GRID_ID) != -1)

	# --- wall cell: Wall Colour present, Floor Textures absent ---
	var wall := Vector2i(6, 3) # part of the default top wall
	_check("setup: (6,3) is a wall", obs.is_blocked(wall))
	fm._apply_menu_context(wall)
	_check("wall cell: 'Wall Colour' section present", _idx_of(menu, "Wall Colour") != -1)
	_check("wall cell: 'Floor Textures' section absent", _idx_of(menu, "Floor Textures") == -1)
	_check("wall cell: Grid item present", menu.get_item_index(fm.GRID_ID) != -1)

	# --- door cell: treated as structure, so Wall Colour present, Floor Textures absent ---
	var door := Vector2i(10, 5) # the A<->B vertical door
	_check("setup: (10,5) is a structure (door), not a wall", obs.has_structure(door) and not obs.is_blocked(door))
	fm._apply_menu_context(door)
	_check("door cell: 'Wall Colour' section present", _idx_of(menu, "Wall Colour") != -1)
	_check("door cell: 'Floor Textures' section absent", _idx_of(menu, "Floor Textures") == -1)

	# --- Grid check reflects the current toggle state after a rebuild ---
	fm._grid_on = true
	fm._apply_menu_context(floor_cell)
	_check("Grid check mirrors _grid_on after rebuild", menu.is_item_checked(menu.get_item_index(fm.GRID_ID)))

	print("RESULT: " + ("OK" if _fails == 0 else str(_fails) + " FAILURES"))
	get_tree().quit(_fails)
