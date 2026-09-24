extends "res://dev/test_case.gd"

# Dev-only headless test: switching to PLAY drops every piece of editor state. The map tools stand
# down in PLAY, so anything left on screen would sit frozen over the running game, and a selection you
# cannot change is not a selection. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_play_clears.tscn

func _mid(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	var mst = main.get_node("World/MapSizeTool")
	var gb = main.get_node("World/GridBackground")
	var inspector = get_tree().get_first_node_in_group("inspector")
	EditHistory.reset()

	# --- set the editor up with as much live state as it can hold ---
	fm.set_mode(EditorState.Mode.WAND)
	fm._wand_click(_mid(Vector2i(8, 9))) # a floor selection (the seeded wooden room)
	_check("setup: there is a selection", fm._selection.has_selection() and fm.has_floor_selection())
	fm._copy_selection()
	fm._arm_paste(MapClipboard.clip())
	_check("setup: a paste is armed", EditorState.pending_kind == EditorState.Pending.PASTE)
	fm.arm_floor_material("sand")
	_check("setup: a brush is armed", fm.is_armed())
	inspector.inspect_wall(Vector2i(8, 3))
	_check("setup: the inspector holds a target", inspector._kind == "wall")

	# --- switch to PLAY ---
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	await get_tree().process_frame

	_check("the selection is cleared", not fm._selection.has_selection())
	_check("...and its model with it", EditorState.sel_kind == EditorState.SelKind.NONE and EditorState.sel_quads.is_empty() and EditorState.sel_cells.is_empty())
	_check("the armed paste is dropped", EditorState.pending_clip.is_empty() and EditorState.pending_kind == EditorState.Pending.NONE)
	_check("the terrain brush is disarmed (no stray drop on the first click back)", not fm.is_armed())
	_check("the inspector lets go of its target", inspector._kind == "")
	_check("the inspector panel is hidden", not inspector._panel.visible)
	_check("the clipboard itself is NOT cleared (it is cross-map by design)", MapClipboard.has_clip())

	# --- the map tools really are inert in PLAY ---
	var w_before: int = gb.grid_width
	mst.active = true
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	mst._input(ev)
	_check("the Map Size tool cannot resize the map while playing", gb.grid_width == w_before)
	mst._process(0.016)
	_check("...and shows no add-band", mst._edge == "" and mst._cell == mst._NO_CELL)
	mst.active = false

	# --- back to EDIT: a clean slate, not a restored selection ---
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	await get_tree().process_frame
	_check("returning to EDIT does not resurrect the old selection", not fm._selection.has_selection())
	_check("the editor is usable again (a fresh selection works)",
		fm._wand_click(_mid(Vector2i(8, 9))) == null and fm._selection.has_selection())

	finish()
