extends "res://dev/test_case.gd"

# Dev-only headless test for Coloured floors slice 1 (ROADMAP "Coloured floors" -> "First-slice
# build plan"): floor TINTS stored per 16px quarter, parallel to floor materials. Checks that a
# tint applies at cell / quarter / room grain, round-trips through MapIO serialize/deserialize
# (v5), that Natural resets it, and that a tint is one undo step restored via the rebuild path.
# Text-only, no rendering (renders hang headless on this machine).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_floor_color.tscn

func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	EditHistory.reset()

	var red := Color(0.85, 0.3, 0.28)

	# --- cell-grain tint: all four quarters of the cell carry it ---
	var cell := Vector2i(8, 9) # inside the seeded wooden room A
	var changed: bool = fm._tint_cell(cell, red)
	_check("tint cell: reports a change", changed)
	var quads: Array = Grid.quads_of(cell)
	var all_red := true
	for q in quads:
		if fm.floor_tint_at_quad(q) != red:
			all_red = false
	_check("tint cell: all four quarters are red", all_red)
	_check("tint cell: re-tinting the same colour is a no-op", not fm._tint_cell(cell, red))

	# --- Natural (white) erases the tint entry ---
	fm._tint_cell(cell, Color.WHITE)
	_check("Natural resets: quarter reads white again", fm.floor_tint_at_quad(quads[0]) == Color.WHITE)
	_check("Natural resets: no _quad_tint entry left", not fm._quad_tint.has(quads[0]))

	# --- quarter-grain tint: exactly one quarter ---
	var q: Vector2i = quads[0]
	fm._write_tint(q, red)
	_check("tint quarter: the target quarter is red", fm.floor_tint_at_quad(q) == red)
	_check("tint quarter: a sibling quarter is untinted", fm.floor_tint_at_quad(quads[1]) == Color.WHITE)
	fm._quad_tint.clear()

	# --- room-grain tint: reaches every interior quarter AND the wall-ring (under the walls) ---
	var tinted_room: bool = fm._tint_room(cell, red)
	_check("tint room: reports a change", tinted_room)
	var room_cells: Dictionary = fm.room_light.room_floor_cells(cell)
	_check("tint room: found a room to fill", not room_cells.is_empty())
	var interior_ok := true
	for c in room_cells:
		for cq in Grid.quads_of(c):
			if fm.floor_tint_at_quad(cq) != red:
				interior_ok = false
	_check("tint room: every interior quarter is red", interior_ok)
	var ring_ok := true
	for rect in fm.room_light.wall_ring_quads(room_cells):
		var rq := Vector2i(floori(rect.position.x / 16), floori(rect.position.y / 16))
		if fm.floor_tint_at_quad(rq) != red:
			ring_ok = false
	_check("tint room: the wall-ring quarters are red (under the walls)", ring_ok)
	_check("tint room outside any room is a no-op", not fm._tint_room(Vector2i(0, 0), red))

	# --- base_fills carry the tint (what the renderer reads) ---
	fm._rebuild()
	var found_tinted_fill := false
	for f in fm.base_fills():
		if f.size() >= 3 and f[2] == red:
			found_tinted_fill = true
	_check("base_fills: at least one fill carries the red tint", found_tinted_fill)

	# --- a tint on a grass (unpainted) quarter still produces a fill (tinted grass patch) ---
	fm._quad_tint.clear()
	fm._quad_mat.clear()
	fm._write_tint(Vector2i(2, 2), red) # a quarter with no material
	fm._rebuild()
	var grass_fill := false
	for f in fm.base_fills():
		if f.size() >= 3 and f[2] == red and f[1] == FloorMaterials.GRASS:
			grass_fill = true
	_check("tinted grass: an unpainted tinted quarter draws a tinted grass fill", grass_fill)

	# --- MapIO round-trip (v5): tints serialize and restore identically ---
	fm._quad_tint.clear()
	fm._quad_mat.clear()
	fm._tint_room(cell, red)
	var before: Dictionary = MapIO.serialize()
	_check("serialize: version is current", int(before["version"]) == MapIO.VERSION)
	_check("serialize: floor_tints is non-empty", before["floor_tints"].size() > 0)
	var tint_count: int = fm._quad_tint.size()
	MapIO.apply_serialized(before, true)
	_check("round-trip: same number of tinted quarters", fm._quad_tint.size() == tint_count)
	var after: Dictionary = MapIO.serialize()
	_check("round-trip: floor_tints list is identical", str(after["floor_tints"]) == str(before["floor_tints"]))

	# --- undo restores the tint state (snapshot via serialize, per EditHistory) ---
	# clear + rebuild FIRST, then reset so the baseline snapshot is the tint-free state.
	fm._quad_tint.clear()
	fm._rebuild()
	EditHistory.reset()
	_check("undo setup: no tints", fm._quad_tint.is_empty())
	fm._tint_cell(cell, red)
	fm._rebuild()
	EditHistory.commit("floor colour")
	_check("undo setup: a tint was committed", not fm._quad_tint.is_empty() and EditHistory.can_undo())
	EditHistory.undo()
	_check("undo: the tint is gone again", fm._quad_tint.is_empty())
	EditHistory.redo()
	_check("redo: the tint is back", not fm._quad_tint.is_empty())

	# --- a pre-v5 map (no floor_tints key) loads with tints cleared, no error ---
	var legacy := before.duplicate(true)
	legacy.erase("floor_tints")
	legacy["version"] = 4
	MapIO.apply_serialized(legacy, true)
	_check("back-compat: a v4 dict clears tints without error", fm._quad_tint.is_empty())

	# --- slice 2: the shared _apply_floor_tint helper (used by swatches AND the picker) ---
	fm._quad_tint.clear(); fm._rebuild()
	fm._mode = 1 # Mode.CELL
	fm._pending = Vector2(cell.x * 32 + 16, cell.y * 32 + 16)
	fm._sel_kind = "" # no active selection
	var applied: bool = fm._apply_floor_tint(red)
	_check("apply-helper (Cell): reports a change", applied)
	var cell_all_red := true
	for q2 in Grid.quads_of(cell):
		if fm.floor_tint_at_quad(q2) != red:
			cell_all_red = false
	_check("apply-helper (Cell): tints the clicked cell's 4 quarters", cell_all_red)

	# --- slice 2: the colour picker live-preview + guarded start colour ---
	fm._quad_tint.clear(); fm._rebuild()
	var blue := Color(0.2, 0.4, 0.9)
	fm._suppress_picker = true
	fm._on_floor_picker_changed(blue) # while suppressed: must NOT apply (setting the start colour)
	_check("picker: suppressed change does not tint", fm._quad_tint.is_empty())
	fm._suppress_picker = false
	fm._picker_applied = false
	fm._on_floor_picker_changed(blue) # a real drag: applies live and flags for commit-on-close
	_check("picker: live change tints the target", fm.floor_tint_at_quad(Grid.quads_of(cell)[0]) == blue)
	_check("picker: flags applied for commit-on-close", fm._picker_applied)

	finish()
