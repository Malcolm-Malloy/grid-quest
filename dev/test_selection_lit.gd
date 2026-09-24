extends "res://dev/test_case.gd"

# Dev-only headless test for "a floor selection reads LIT and un-tinted while its colour is edited"
# (ROADMAP "Coloured highlight system"): the marching-ants selection must NOT wash the floor with the
# blue fill (it distorted the colour), and RoomLight must treat the selected cells as lit so a room the
# player is not standing in shows its true (lit) colour. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_selection_lit.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")

	# a FLOOR selection: the overlay draws ants only (no wash), so the true colour shows through
	fm._selection.set_floor({Vector2i(16, 18): true}, [])
	_check("floor selection: wash off (ants only)", not fm._selection._wash)

	# selection_lit_cells maps the selected quarters to their owning 32px cells for RoomLight
	fm._sel_kind = "floor"
	fm._sel_quads = {Vector2i(16, 18): true, Vector2i(17, 18): true}
	var lit: Dictionary = fm.selection_lit_cells()
	_check("selection_lit_cells: quarter (16,18) -> cell (8,9)", lit.has(Vector2i(8, 9)))
	_check("selection_lit_cells: no stray cells", lit.size() == 1)

	# a WALL selection keeps the wash (the 3D silhouette reads better than a bare outline)
	fm._selection.set_wall({Vector2i(8, 8): true}, [Rect2(256, 256, 32, 18)])
	_check("wall selection: wash on", fm._selection._wash)

	# no floor selection -> nothing extra lit
	fm._sel_kind = ""
	fm._sel_quads = {}
	_check("no floor selection: selection_lit_cells empty", fm.selection_lit_cells().is_empty())

	finish()
