extends "res://dev/test_case.gd"

# Dev-only headless test for the contextual right-click menu (ROADMAP "Right-click menu overhaul",
# "Editor UX revisions", "Optimise the right menu"). After the 2026-09-05 merge the menu is ONE submenu
# per target plus actions: a WALL shows Wall + Floor + Erase, a DOOR shows Door + Floor + Erase, a bare
# FLOOR shows Floor + Erase. Floor shows on EVERY cell (the ground under a structure is editable), and
# each submenu groups its axes inside with separator headings instead of taking a top-level slot each.
# BUILDING left the menu entirely: the Place tool drops walls/doors and can drag a wall line.
# The Grid toggle stays regardless. Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_context_menu.tscn

# index of the top-level menu item whose text == label, or -1 if absent (contextual = present or not)
func _idx_of(menu: PopupMenu, label: String) -> int:
	for i in menu.item_count:
		if menu.get_item_text(i) == label:
			return i
	return -1

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	var menu: PopupMenu = fm.menu.popup

	# --- floor cell: Terrain + Build Wall/Door + Erase; no Wall Colour/Door ---
	var floor_cell := Vector2i(8, 4) # inside room A, no wall or door
	_check("setup: (8,4) has no structure", not obs.has_structure(floor_cell))
	fm.menu.apply_context(floor_cell)
	_check("floor cell: 'Floor' section present", _idx_of(menu, "Floor") != -1)
	_check("floor cell: 'Wall' section absent", _idx_of(menu, "Wall") == -1)
	_check("floor cell: 'Door' section absent", _idx_of(menu, "Door") == -1)
	_check("floor cell: building left the menu (Place tool owns it)",
		_idx_of(menu, "Build Wall") == -1 and _idx_of(menu, "Build Door") == -1)
	_check("floor cell: 'Erase' present", _idx_of(menu, "Erase") != -1)
	_check("floor cell: Grid item present", menu.get_item_index(ContextMenu.GRID_ID) != -1)
	# the whole point of the merge: a short top level. Floor + Erase + separator + Grid.
	_check("floor cell: at most 4 top-level entries", menu.item_count <= 4)
	# ...with the axes still all reachable, one level deep, inside the Floor submenu
	var fsub: PopupMenu = menu.get_node("floor_sub")
	_check("Floor submenu groups Texture / Colour", _idx_of(fsub, "Texture") != -1 and _idx_of(fsub, "Colour") != -1)
	_check("Floor submenu keeps the custom colour picker", _idx_of(fsub, "Custom...") != -1)
	_check("Floor submenu lists the materials", _idx_of(fsub, "Wood") != -1)

	# --- wall cell: Wall Colour/Material + Terrain + Erase; no Build Wall (already a structure) ---
	var wall := Vector2i(6, 3) # part of the default top wall
	_check("setup: (6,3) is a wall", obs.is_blocked(wall))
	fm.menu.apply_context(wall)
	_check("wall cell: 'Wall' section present", _idx_of(menu, "Wall") != -1)
	_check("wall cell: 'Floor' (terrain) present", _idx_of(menu, "Floor") != -1)
	_check("wall cell: 'Erase' present", _idx_of(menu, "Erase") != -1)
	_check("wall cell: Grid item present", menu.get_item_index(ContextMenu.GRID_ID) != -1)
	_check("wall cell: at most 5 top-level entries", menu.item_count <= 5)
	var wsub: PopupMenu = menu.get_node("wall_sub")
	_check("Wall submenu groups Colour / Material",
		_idx_of(wsub, "Colour") != -1 and _idx_of(wsub, "Material") != -1)
	_check("Wall submenu lists the materials", _idx_of(wsub, "Slate") != -1)

	# --- door cell: Door + Terrain + Erase; NO Wall Colour ---
	var door := Vector2i(10, 5) # the A<->B vertical door
	_check("setup: (10,5) is a structure (door), not a wall", obs.has_structure(door) and not obs.is_blocked(door))
	fm.menu.apply_context(door)
	_check("door cell: 'Door' section present", _idx_of(menu, "Door") != -1)
	_check("door cell: 'Wall' section absent", _idx_of(menu, "Wall") == -1)
	_check("door cell: 'Floor' (terrain) present", _idx_of(menu, "Floor") != -1)
	_check("door cell: 'Erase' present", _idx_of(menu, "Erase") != -1)

	# --- Grid check reflects the current toggle state after a rebuild ---
	EditorState.grid_on = true
	fm.menu.apply_context(floor_cell)
	_check("Grid check mirrors _grid_on after rebuild", menu.is_item_checked(menu.get_item_index(ContextMenu.GRID_ID)))

	finish()
