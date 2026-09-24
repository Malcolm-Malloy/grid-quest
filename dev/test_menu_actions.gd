extends "res://dev/test_case.gd"

# Dev-only headless test for the right-click-menu ACTIONS (ROADMAP "Editor UX revisions"): Build Wall /
# Build Door, Erase (single structure, single floor cell, floor selection, wall selection), the Delete
# key (erases the selection), and the Door edits (flip / open / swing). Drives the handlers through
# _on_menu_id with _pending set, and a synthesized Delete key through _unhandled_key_input. Checks the
# data model (blocked_cells / gate_cells / _quad_mat), which apply_serialized updates synchronously.
# Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_menu_actions.tscn

func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _click(fm, cell: Vector2i, id: int) -> void:
	fm._pending = _center(cell)
	fm._on_menu_id(id)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	EditHistory.reset()

	# --- Build Wall on an empty cell ---
	var wcell := Vector2i(20, 20)
	_check("setup: (20,20) is empty", not obs.has_structure(wcell))
	_click(fm, wcell, fm.BUILD_WALL_ID)
	_check("Build Wall: the cell is now a wall", obs.is_blocked(wcell))

	# --- Build Door on an empty cell ---
	var dcell := Vector2i(22, 20)
	_click(fm, dcell, fm.BUILD_DOOR_ID)
	_check("Build Door: the cell now holds a door", not obs.door_at(dcell).is_empty())

	# --- Erase a single structure (no selection) ---
	_click(fm, wcell, fm.ERASE_ID)
	_check("Erase (structure): the wall is gone", not obs.has_structure(wcell))

	# --- Erase a single floor cell (no selection) -> grass ---
	var fcell := Vector2i(9, 9) # wood room A
	var fq: Vector2i = Grid.quads_of(fcell)[0]
	_check("setup: (9,9) has a floor material", fm._quad_mat.has(fq))
	_click(fm, fcell, fm.ERASE_ID)
	_check("Erase (floor cell): the ground is cleared to grass", not fm._quad_mat.has(fq))

	# --- Door edits on the A<->B door (10,5): flip / open / swing ---
	var door := Vector2i(10, 5)
	var orient0: String = obs.door_at(door)["orientation"]
	_click(fm, door, fm.DOOR_FLIP_ID)
	_check("Door flip: orientation changed", obs.door_at(door)["orientation"] != orient0)
	_check("Door open default false initially", not bool(obs.door_at(door).get("open", false)))
	_click(fm, door, fm.DOOR_OPEN_ID)
	_check("Door open: toggled on", bool(obs.door_at(door).get("open", false)))
	_click(fm, door, fm.DOOR_SWING_ID)
	_check("Door swing: toggled on", bool(obs.door_at(door).get("swing", false)))

	# --- Erase a FLOOR selection (Wand), then it clears ---
	fm.set_mode(0) # WAND
	fm._wand_click(_center(Vector2i(12, 9)))
	_check("setup: a floor selection exists", fm._selection.has_selection() and fm._sel_kind == "floor")
	var sel_q = fm._sel_quads.keys()[0]
	_click(fm, Vector2i(12, 9), fm.ERASE_ID)
	_check("Erase (floor selection): a selected quarter is cleared", not fm._quad_mat.has(sel_q))
	_check("Erase (floor selection): selection cleared afterwards", not fm._selection.has_selection())

	# --- Delete key erases the selection ---
	fm._wand_click(_center(Vector2i(7, 4)))
	_check("setup: a floor selection exists for Delete", fm._selection.has_selection())
	var del_q = fm._sel_quads.keys()[0]
	var ev := InputEventKey.new()
	ev.keycode = KEY_DELETE
	ev.pressed = true
	fm._unhandled_key_input(ev)
	_check("Delete key: the selected quarter is cleared", not fm._quad_mat.has(del_q))
	_check("Delete key: selection cleared afterwards", not fm._selection.has_selection())

	# --- Erase a WALL selection (Wand on a wall), then it clears ---
	fm._wand_click(_center(Vector2i(6, 3)))
	_check("setup: a wall selection exists", fm._selection.has_selection() and fm._sel_kind == "wall")
	var sel_wall = fm._sel_cells.keys()[0]
	_click(fm, Vector2i(6, 3), fm.ERASE_ID)
	_check("Erase (wall selection): a selected wall is removed", not obs.is_blocked(sel_wall))
	_check("Erase (wall selection): selection cleared afterwards", not fm._selection.has_selection())

	# --- Build Wall configurator: pick colour + material, Start arms Wall mode, placed walls carry them ---
	fm._on_build_wall_id(2)   # WALL_COLORS[2] = Green
	_check("build-wall: colour armed", fm._wall_color == WallSegment.COLORS[2][1])
	fm._on_build_wall_id(101) # WALL_MATERIALS[1] = Wood
	_check("build-wall: material armed", fm._wall_mat == WallSegment.MATERIAL_NAMES[1][1])
	fm._on_build_wall_id(999) # Start Building -> Wall mode
	_check("build-wall: Start arms Wall mode", fm._mode == 4) # Mode.WALL
	var bw := Vector2i(24, 20)
	fm._place_wall_at(_center(bw))
	_check("build-wall: placed wall is blocked", obs.is_blocked(bw))
	_check("build-wall: placed wall carries the brush colour", obs.get_wall_color(bw) == WallSegment.COLORS[2][1])
	_check("build-wall: placed wall carries the brush material", obs.get_wall_material(bw) == WallSegment.MATERIAL_NAMES[1][1])

	# --- UNIFIED brush: arming a wall colour/material from the LEFT PANEL also builds with it (no wall
	# selection, so arm_wall_* just set the brush), matching the floor flow ---
	fm._clear_selection()
	fm.arm_wall_color(WallSegment.COLORS[1][1])       # Red, via the panel path
	fm.arm_wall_material(WallSegment.MATERIAL_NAMES[2][1]) # Slate, via the panel path
	var pw := Vector2i(26, 20)
	fm._place_wall_at(_center(pw))
	_check("panel brush: a wall built after a panel pick carries that colour", obs.get_wall_color(pw) == WallSegment.COLORS[1][1])
	_check("panel brush: a wall built after a panel pick carries that material", obs.get_wall_material(pw) == WallSegment.MATERIAL_NAMES[2][1])

	finish()
