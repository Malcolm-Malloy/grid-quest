extends Node

# Dev-only headless test for Box-select + additive/subtractive selection (ROADMAP "Box-select" +
# "Additive / subtractive selection"). Box-select drags a rectangle selecting every quarter inside it,
# regardless of material/room; Shift adds, Alt subtracts, for both box and the Magic Wand. Drives the
# selection logic directly (input handlers read the real mouse; the compositing helpers do not).
# Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_box_select.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var gb = main.get_node("World/GridBackground")

	# --- box-select replace: a 3x3-cell box selects 36 quarters ---
	fm.set_mode(7) # Mode.BOX
	fm._box_start = Vector2i(5, 5)
	fm._box_op = "replace"
	fm._box_base = {}
	fm._update_box(Vector2i(7, 7)) # cells (5..7)x(5..7) = 9 cells x 4 quarters
	_check("box replace: 3x3 box selects 36 quarters", fm._sel_quads.size() == 36)
	_check("box replace: selection kind is floor", fm._sel_kind == "floor")
	var probe: Vector2i = fm._cell_quads(Vector2i(6, 6))[0]
	_check("box replace: an interior quarter is selected", fm._sel_quads.has(probe))

	# --- box add: a second box UNIONs onto the first ---
	fm._box_base = fm._sel_quads.duplicate()
	fm._box_op = "add"
	fm._box_start = Vector2i(8, 5)
	fm._update_box(Vector2i(8, 7)) # adds cells (8,5),(8,6),(8,7) = 3 cells x 4 = 12 quarters
	_check("box add: union grows the selection to 48", fm._sel_quads.size() == 48)
	_check("box add: kept the original region", fm._sel_quads.has(probe))
	_check("box add: added the new region", fm._sel_quads.has(fm._cell_quads(Vector2i(8, 6))[0]))

	# --- box subtract: a box removes an overlapping region ---
	fm._box_base = fm._sel_quads.duplicate()
	fm._box_op = "subtract"
	fm._box_start = Vector2i(5, 5)
	fm._update_box(Vector2i(5, 7)) # removes cells (5,5),(5,6),(5,7) = 12 quarters
	_check("box subtract: removed 12 quarters (48 -> 36)", fm._sel_quads.size() == 36)
	_check("box subtract: the removed column is gone", not fm._sel_quads.has(fm._cell_quads(Vector2i(5, 6))[0]))
	_check("box subtract: untouched region remains", fm._sel_quads.has(fm._cell_quads(Vector2i(8, 6))[0]))

	# --- _clamp_cell keeps a box inside the map ---
	_check("_clamp_cell clamps off-map to the edge", fm._clamp_cell(Vector2i(-5, 999)) == Vector2i(0, gb.grid_height - 1))

	# --- _sel_op reads the modifier ---
	var e := InputEventMouseButton.new()
	e.shift_pressed = true
	_check("_sel_op: Shift = add", fm._sel_op(e) == "add")
	e.shift_pressed = false
	e.alt_pressed = true
	_check("_sel_op: Alt = subtract", fm._sel_op(e) == "subtract")
	e.alt_pressed = false
	_check("_sel_op: plain = replace", fm._sel_op(e) == "replace")

	# --- Magic Wand add / subtract (outdoor cells have single-cell patches, 4 quarters each) ---
	fm.set_mode(0) # Mode.WAND
	fm._clear_selection()
	fm._wand_click(_center(Vector2i(2, 2)), "replace")
	var s0: int = fm._sel_quads.size()
	_check("wand replace: a single outdoor cell selects its quarters", s0 == 4 and fm._sel_kind == "floor")
	fm._wand_click(_center(Vector2i(4, 2)), "add")
	_check("wand add: a second cell unions in", fm._sel_quads.size() == 8)
	_check("wand add: both cells present", fm._sel_quads.has(fm._cell_quads(Vector2i(2, 2))[0]) and fm._sel_quads.has(fm._cell_quads(Vector2i(4, 2))[0]))
	fm._wand_click(_center(Vector2i(2, 2)), "subtract")
	_check("wand subtract: the first cell is removed", not fm._sel_quads.has(fm._cell_quads(Vector2i(2, 2))[0]))
	_check("wand subtract: selection still floor with the other cell", fm._sel_kind == "floor" and fm._sel_quads.size() == 4)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
