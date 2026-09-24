extends "res://dev/test_case.gd"

# Dev-only headless test for the Selection UX fixes (ROADMAP "Editor UX revisions"): (1) Cell/Fine
# must NOT start with a material armed to drop (the user picks one first), and (2) a Wand selection
# can be deselected by clicking off it / off the map (tested here via the decision helpers the input
# handlers use: _click_in_selection + _in_bounds + _clear_selection).
# Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_selection_ux.tscn

const TILE_ID := 3 # MENU index of "tile"

func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	EditHistory.reset()

	var cellA := Vector2i(8, 9)  # inside the wood room A
	var cellB := Vector2i(9, 9)  # another cell in the same room
	var qA0: Vector2i = Grid.quads_of(cellA)[0]
	var qB0: Vector2i = Grid.quads_of(cellB)[0]

	# --- (2) armed state: entering Cell/Fine disarms ---
	fm.set_mode(1) # Mode.CELL
	_check("enter Cell: no material armed", not EditorState.armed)

	# arming via the menu (Cell mode, no selection -> arm-only, nothing placed yet)
	fm._pending = _center(cellA)
	EditorState.sel_kind = EditorState.SelKind.NONE
	fm._on_menu_id(TILE_ID)
	_check("pick material: now armed", EditorState.armed and EditorState.brush == "tile")
	_check("pick material (Cell, no sel): nothing placed yet", fm._quad_mat.get(qA0, "") == "wood")

	# armed paint drops the material
	fm._paint(_center(cellA), true)
	_check("armed Cell paint: the material is placed", fm._quad_mat.get(qA0, "") == "tile")

	# re-entering Fine disarms again, so a paint places nothing (even though _brush is still "tile")
	fm.set_mode(2) # Mode.FINE
	_check("enter Fine: disarmed again", not EditorState.armed)
	var beforeB: String = fm._quad_mat.get(qB0, "")
	fm._paint(_center(cellB), true)
	_check("un-armed Fine paint: no-op (cell unchanged)", fm._quad_mat.get(qB0, "") == beforeB)

	# re-arming re-enables placement (Fine mode paints the quarter under the cursor)
	fm._pending = _center(cellB)
	fm._on_menu_id(TILE_ID)
	fm._paint(_center(cellB), true)
	var paintedQ := Vector2i(floori(_center(cellB).x / 16), floori(_center(cellB).y / 16))
	_check("re-armed paint: places again", fm._quad_mat.get(paintedQ, "") == "tile")

	# --- right-click while armed in Cell/Fine disarms the brush (removes the hover graphic), no menu ---
	fm.set_mode(1) # Mode.CELL
	fm._pending = _center(cellA)
	EditorState.sel_kind = EditorState.SelKind.NONE
	fm._on_menu_id(TILE_ID) # arm
	_check("armed before right-click", EditorState.armed)
	var rc := InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	fm._unhandled_input(rc)
	_check("right-click while armed: disarms the brush", not EditorState.armed)

	# --- custom-shape drop: a Wand-selection fill animates the whole shape dropping in ---
	fm.set_mode(0) # Mode.WAND
	fm.selection.wand_click(_center(cellA)) # makes a floor selection
	var drop_rects: Array = fm._selection_drop_rects()
	_check("shape-drop rects: >0 and <= selected quarters (excludes under-wall ring)",
		drop_rects.size() > 0 and drop_rects.size() <= EditorState.sel_quads.size())
	fm._pending = _center(cellA)
	fm._on_menu_id(TILE_ID) # selection-fill path -> fills + plays the shape drop
	_check("shape-drop: preview holds the shape rects after a selection fill", fm._preview._shape_rects.size() > 0)

	# --- (1) deselect helpers: a Wand selection, then the off-selection / off-map decisions ---
	fm.set_mode(0) # Mode.WAND
	fm.selection.wand_click(_center(cellA))
	_check("wand: a selection exists", fm.selection.overlay.has_selection())
	_check("click-in-selection: a point inside the selection is 'inside'", fm.selection.contains(_center(cellA)))
	_check("click-in-selection: a far point is 'outside'", not fm.selection.contains(_center(Vector2i(2, 2))))
	_check("off-map: an out-of-bounds cell is not in bounds", not fm._in_bounds(Vector2i(-1, -1)))

	# the right-click handler's deselect decision = has_selection AND (off-map OR off-selection)
	var deselect_far: bool = fm.selection.overlay.has_selection() and (not fm._in_bounds(Vector2i(2, 2)) or not fm.selection.contains(_center(Vector2i(2, 2))))
	_check("decision: right-click on a far cell would deselect", deselect_far)
	var keep_inside: bool = fm.selection.overlay.has_selection() and (not fm._in_bounds(cellA) or not fm.selection.contains(_center(cellA)))
	_check("decision: right-click inside the selection would NOT deselect (menu opens)", not keep_inside)

	fm.selection.clear()
	_check("clear_selection: the selection is gone", not fm.selection.overlay.has_selection())

	finish()
