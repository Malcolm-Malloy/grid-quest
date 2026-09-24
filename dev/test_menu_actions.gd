extends "res://dev/test_case.gd"

# Dev-only headless test for the right-click-menu ACTIONS (ROADMAP "Editor UX revisions"): Erase (single
# structure, single floor cell, floor selection, wall selection), the Delete key (erases the selection),
# and the Door edits (flip / open / swing). Drives ContextMenu.on_id with the menu target set, and a
# synthesized Delete key through _unhandled_key_input. Walls/doors are laid through the Place tool path.
# Checks the data model (blocked_cells / gate_cells / _quad_mat).
# Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_menu_actions.tscn

func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _click(fm, cell: Vector2i, id: int) -> void:
	fm.menu.target = _center(cell)
	fm.menu.on_id(id)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	EditHistory.reset()

	# --- lay a wall and a door on empty cells (the Place tool path) ---
	var wcell := Vector2i(20, 20)
	_check("setup: (20,20) is empty", not obs.has_structure(wcell))
	fm.place_wall_at(_center(wcell))
	fm._process(0.0) # flush the coalesced wall rebuild
	_check("setup: the cell is now a wall", obs.is_blocked(wcell))
	var dcell := Vector2i(22, 20)
	fm.place_door_at(_center(dcell))
	_check("setup: the cell now holds a door", not obs.door_at(dcell).is_empty())

	# --- Erase a single structure (no selection) ---
	_click(fm, wcell, ContextMenu.ERASE_ID)
	_check("Erase (structure): the wall is gone", not obs.has_structure(wcell))

	# --- Erase a single floor cell (no selection) -> grass ---
	var fcell := Vector2i(9, 9) # wood room A
	var fq: Vector2i = Grid.quads_of(fcell)[0]
	_check("setup: (9,9) has a floor material", (fm.material_at(fq) != ""))
	_click(fm, fcell, ContextMenu.ERASE_ID)
	_check("Erase (floor cell): the ground is cleared to grass", not (fm.material_at(fq) != ""))

	# --- Door edits on the A<->B door (10,5): flip / open / swing ---
	var door := Vector2i(10, 5)
	var orient0: Grid.Orient = obs.door_at(door)["orientation"]
	_click(fm, door, ContextMenu.DOOR_FLIP_ID)
	_check("Door flip: orientation changed", obs.door_at(door)["orientation"] != orient0)
	_check("Door open default false initially", not bool(obs.door_at(door).get("open", false)))
	_click(fm, door, ContextMenu.DOOR_OPEN_ID)
	_check("Door open: toggled on", bool(obs.door_at(door).get("open", false)))
	_click(fm, door, ContextMenu.DOOR_SWING_ID)
	_check("Door swing: toggled on", bool(obs.door_at(door).get("swing", false)))

	# --- Erase a FLOOR selection (Wand), then it clears ---
	fm.set_mode(0) # WAND
	fm.selection.wand_click(_center(Vector2i(12, 9)))
	_check("setup: a floor selection exists", fm.selection.overlay.has_selection() and EditorState.sel_kind == EditorState.SelKind.FLOOR)
	var sel_q = EditorState.sel_quads.keys()[0]
	_click(fm, Vector2i(12, 9), ContextMenu.ERASE_ID)
	_check("Erase (floor selection): a selected quarter is cleared", not (fm.material_at(sel_q) != ""))
	_check("Erase (floor selection): selection cleared afterwards", not fm.selection.overlay.has_selection())

	# --- Delete key erases the selection ---
	fm.selection.wand_click(_center(Vector2i(7, 4)))
	_check("setup: a floor selection exists for Delete", fm.selection.overlay.has_selection())
	var del_q = EditorState.sel_quads.keys()[0]
	var ev := InputEventKey.new()
	ev.keycode = KEY_DELETE
	ev.pressed = true
	fm._unhandled_key_input(ev)
	_check("Delete key: the selected quarter is cleared", not (fm.material_at(del_q) != ""))
	_check("Delete key: selection cleared afterwards", not fm.selection.overlay.has_selection())

	# --- Erase a WALL selection (Wand on a wall), then it clears ---
	fm.selection.wand_click(_center(Vector2i(6, 3)))
	_check("setup: a wall selection exists", fm.selection.overlay.has_selection() and EditorState.sel_kind == EditorState.SelKind.WALL)
	var sel_wall = EditorState.sel_cells.keys()[0]
	_click(fm, Vector2i(6, 3), ContextMenu.ERASE_ID)
	_check("Erase (wall selection): a selected wall is removed", not obs.is_blocked(sel_wall))
	_check("Erase (wall selection): selection cleared afterwards", not fm.selection.overlay.has_selection())

	# --- Wall submenu: Wand colours the whole building, Cell/Fine a single segment, a door is untouched ---
	var red: Color = WallSegment.COLORS[1][1]
	var green: Color = WallSegment.COLORS[2][1]
	fm.selection.clear()
	fm.set_mode(EditorState.Mode.WAND)
	_check("setup: (14,5) and (12,11) are walls of one building", obs.is_blocked(Vector2i(14, 5)) and obs.building_cells(Vector2i(14, 5)).has(Vector2i(12, 11)))
	_click(fm, Vector2i(14, 5), ContextMenu.WALL_BASE_ID + 1)
	_check("wall colour (Wand): the clicked wall is red", obs.get_wall_color(Vector2i(14, 5)) == red)
	_check("wall colour (Wand): the rest of the building is red too", obs.get_wall_color(Vector2i(12, 11)) == red)
	fm.set_mode(EditorState.Mode.CELL)
	_click(fm, Vector2i(14, 5), ContextMenu.WALL_BASE_ID + 2)
	_check("wall colour (Cell): only the clicked wall turns green",
		obs.get_wall_color(Vector2i(14, 5)) == green and obs.get_wall_color(Vector2i(14, 6)) == red)
	_check("wall colour arms the wall-colour brush", EditorState.tool_kind == EditorState.Brush.WALL_COLOR)
	var gate_cell: Vector2i = obs.gate_cells[0]["cell"]
	_click(fm, gate_cell, ContextMenu.WALL_BASE_ID + 2)
	_check("wall colour on a door is a no-op", obs.get_wall_color(gate_cell) == Color.WHITE)
	# a wall SELECTION takes the material, whatever the mode
	fm.selection.wand_click(_center(Vector2i(14, 5)))
	var run: Array = EditorState.sel_cells.keys()
	_click(fm, Vector2i(14, 5), ContextMenu.WALL_MAT_BASE_ID + 2)
	var all_slate := true
	for c in run:
		all_slate = all_slate and obs.get_wall_material(c) == WallSegment.MATERIAL_NAMES[2][1]
	_check("wall material fills the whole wall selection", run.size() > 1 and all_slate)
	fm.selection.clear()

	# --- Floor submenu: pattern and colour on a clicked cell (Cell grain) ---
	var pcell := Vector2i(30, 25)
	for q in Grid.quads_of(pcell):
		fm.write_quad(q, "wood")
	_click(fm, pcell, ContextMenu.PATTERN_BASE_ID + 1)
	var patterned := true
	for q in Grid.quads_of(pcell):
		patterned = patterned and fm.floor_pattern_at_quad(q) == 1
	_check("pattern applies to all four quarters of the clicked cell", patterned)
	_click(fm, pcell, ContextMenu.FLOOR_COLOR_BASE_ID + 1)
	_check("colour swatch tints the clicked cell",
		fm.floor_tint_at_quad(Grid.quads_of(pcell)[3]) == FloorMaterials.COLORS[1][1])
	_check("colour swatch arms the floor-colour brush", EditorState.tool_kind == EditorState.Brush.FLOOR_COLOR)

	# --- UNIFIED brush: arming a wall colour/material from the LEFT PANEL also builds with it (no wall
	# selection, so arm_wall_* just set the brush), matching the floor flow ---
	fm.selection.clear()
	fm.arm_wall_color(WallSegment.COLORS[1][1])       # Red, via the panel path
	fm.arm_wall_material(WallSegment.MATERIAL_NAMES[2][1]) # Slate, via the panel path
	var pw := Vector2i(26, 20)
	fm.place_wall_at(_center(pw))
	_check("panel brush: a wall built after a panel pick carries that colour", obs.get_wall_color(pw) == WallSegment.COLORS[1][1])
	_check("panel brush: a wall built after a panel pick carries that material", obs.get_wall_material(pw) == WallSegment.MATERIAL_NAMES[2][1])

	finish()
