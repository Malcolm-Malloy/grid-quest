extends Node

# Dev-only headless test for the editor STATUS BAR (ROADMAP "Editor layout" -> "A thin status bar",
# the last open item of Phase A group 4). Checks the bar exists, is EDIT-only chrome, reports the
# hovered cell / active tool / selection size / map dimensions / zoom, and that the tool strip leaves
# room for it. Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_status_bar.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var sb = get_tree().get_first_node_in_group("status_bar")
	_check("status bar exists (grouped)", sb != null)
	var fm = main.get_node("World/FloorManager")
	var gb = main.get_node("World/GridBackground")
	var cam = main.get_node("Camera2D") as Camera2D

	# --- editor-only chrome, exactly like the tool strip ---
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	_check("visible in EDIT", sb.visible)
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	_check("hidden in PLAY", not sb.visible)
	EditorMode.set_mode(EditorMode.Mode.EDIT)

	# --- hovered cell. Headless has no real pointer, so drive FloorManager's own accessor: it must
	# report nothing while the cursor is away or the mode is PLAY, which is when the highlights are
	# also standing down.
	_check("hovered_cell reports nothing with the cursor off the window",
		fm.hovered_cell() == fm.INVALID_CELL)
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	_check("hovered_cell reports nothing in PLAY", fm.hovered_cell() == fm.INVALID_CELL)
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	_check("the readout says 'Cell --' when there is no cell", "Cell --" in sb._compose_left())

	# --- active tool: the bar must name the MERGED tool the user picked, not the internal mode ---
	fm.set_mode(fm.Mode.CELL)
	_check("Cell mode reads as Paint", "Paint" in sb._compose_left())
	fm.set_mode(fm.Mode.FINE)
	_check("Fine mode names the grain", "Paint (Fine)" in sb._compose_left())
	fm.set_mode(fm.Mode.DOOR)
	_check("Door mode reads as Place: Door", "Place: Door" in sb._compose_left())
	fm.set_mode(fm.Mode.BOX)
	_check("Box mode reads as Select (all three select modes are one tool)",
		"Select" in sb._compose_left())
	_check("every mode has a name", sb.TOOL_NAMES.size() == fm.Mode.size())

	# --- selection size, in the unit the selection was made in ---
	_check("no selection field with nothing selected", not ("Sel " in sb._compose_left()))
	_check("selection_summary is empty with nothing selected", fm.selection_summary() == "")
	# a floor selection is quarter-grained: whole cells report cells, a partial cell reports quads
	# Each change goes through _refresh_selection_overlay, the real path that emits selection_changed --
	# the bar CACHES the selection off that signal (recounting every selected quarter each frame would
	# be the one expensive thing on a per-frame readout), so the signal is part of what is under test.
	fm._sel_kind = "floor"
	fm._sel_quads = {Vector2i(4, 4): true, Vector2i(5, 4): true, Vector2i(4, 5): true, Vector2i(5, 5): true}
	fm._refresh_selection_overlay()
	_check("four quarters of one cell report 1 cell", fm.selection_summary() == "1 cell")
	_check("the bar shows the selection", "Sel 1 cell" in sb._compose_left())
	fm._sel_quads.erase(Vector2i(5, 5))
	fm._refresh_selection_overlay()
	_check("a partial cell reports quads, not a rounded-up cell", fm.selection_summary() == "3 quads")
	_check("the bar followed the change without being told twice", "Sel 3 quads" in sb._compose_left())
	fm._clear_selection()
	fm._refresh_selection_overlay()
	# a wall selection counts walls
	fm._sel_kind = "wall"
	fm._sel_cells = {Vector2i(1, 1): true, Vector2i(2, 1): true}
	fm._refresh_selection_overlay()
	_check("a wall selection counts walls", fm.selection_summary() == "2 walls")
	_check("the bar shows walls too", "Sel 2 walls" in sb._compose_left())
	fm._clear_selection()
	fm._refresh_selection_overlay()
	_check("clearing the selection drops the field", fm.selection_summary() == "")
	_check("...and the bar drops it too", not ("Sel " in sb._compose_left()))

	# --- map dimensions + zoom (the right half) ---
	gb.set_grid_size(48, 32)
	gb.set_absent_cells({})
	cam.zoom = Vector2(2, 2)
	var right: String = sb._compose_right()
	_check("dimensions read as the grid size", "48 × 32" in right)
	_check("zoom reads as a percentage", "200%" in right)
	cam.zoom = Vector2(0.5, 0.5)
	_check("zoom follows the camera", "50%" in sb._compose_right())
	# a jagged map's bounding box overstates it, so the true cell count is appended -- but only then
	_check("a full rectangle shows no cell count", not ("cells" in right))
	gb.set_absent_cells({Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(2, 0): true})
	_check("a map with holes appends the real cell count", "(1533 cells)" in sb._compose_right())
	gb.set_absent_cells({})

	# --- the two pieces of EDIT-only chrome on the left/bottom do not overlap ---
	var ts = get_tree().get_first_node_in_group("tool_strip")
	ts._relayout()
	var vp: float = ts.get_viewport().get_visible_rect().size.y
	_check("the tool strip reserves the bar's REAL height, not a guess",
		ts._scroll.custom_minimum_size.y <= vp - sb.height())
	# the theme decides how tall one line of text in a PanelContainer is, so the bar measures itself
	# rather than trusting the constant; the constant is only the floor.
	_check("the bar reports at least its declared floor", sb.height() >= sb.HEIGHT)
	_check("the reported height is the panel's own minimum",
		sb.height() == max(sb._panel.get_combined_minimum_size().y, sb.HEIGHT))
	_check("a taller-than-declared bar grows UP, staying flush with the bottom edge",
		sb._panel.grow_vertical == Control.GROW_DIRECTION_BEGIN)

	# --- the readout is inert: it must never eat the hover the map tools need ---
	_check("the bar ignores the mouse", sb._panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
