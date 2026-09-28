extends "res://dev/test_case.gd"

# Dev-only headless test for Terrain patterns (ROADMAP item 7 -> "Terrain patterns and material
# variants"): a per-16px-quarter PATTERN index into the material's texture-variant array, stored
# parallel to and independent of the material + colour tint. Checks that a pattern applies at
# cell / quarter / room grain, is a no-op over grass (no material), that the renderer picks the right
# variant (and clamps a stale index), round-trips through MapIO (v7), and is one undo step.
# Text-only, no rendering (renders hang headless on this machine).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_floor_pattern.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	EditHistory.reset()

	var cell := Vector2i(8, 9) # inside the seeded wooden room A (material "wood", 2 variants)
	var quads: Array = Grid.quads_of(cell)
	_check("setup: the cell is wood (has a material)", fm.material_at(quads[0]) == "wood")
	_check("setup: default pattern is 0", fm.floor_pattern_at_quad(quads[0]) == 0)

	# --- cell-grain: all four quarters take the pattern ---
	var changed: bool = fm.pattern_cell(cell, 1)
	_check("pattern cell: reports a change", changed)
	var all_one := true
	for q in quads:
		if fm.floor_pattern_at_quad(q) != 1:
			all_one = false
	_check("pattern cell: all four quarters are pattern 1", all_one)
	_check("pattern cell: re-applying the same index is a no-op", not fm.pattern_cell(cell, 1))
	_check("pattern cell: index 0 erases the entry", fm.pattern_cell(cell, 0) and not (fm.floor_pattern_at_quad(quads[0]) != 0))

	# --- pattern is a no-op over a quarter with no material (grass) ---
	var grass_q := Vector2i(2, 2)
	_check("setup: (2,2) quarter has no material", not (fm.material_at(grass_q) != ""))
	_check("pattern on grass: no-op", not fm.write_pattern(grass_q, 1) and not (fm.floor_pattern_at_quad(grass_q) != 0))

	# --- the renderer picks the right variant, and clamps a stale index ---
	fm.write_pattern(quads[0], 1)
	fm.rebuild()
	var tex1 = fm.floor_tex_at_quad(quads[0])
	_check("render: quarter draws the wood variant-1 texture", tex1 == FloorMaterials.TEXTURES["wood"][1])
	# a stale over-range index (e.g. left over from a many-variant material) clamps, never crashes
	fm.write_pattern(quads[0], 9)
	var texc = fm.floor_tex_at_quad(quads[0])
	_check("render: an out-of-range index clamps to the last variant", texc == FloorMaterials.TEXTURES["wood"][FloorMaterials.TEXTURES["wood"].size() - 1])
	fm.apply_patterns([]); fm.rebuild()

	# --- room-grain: interior + wall-ring quarters ---
	var tinted_room: bool = fm.pattern_room(cell, 1)
	_check("pattern room: reports a change", tinted_room)
	var room_cells: Dictionary = fm.topology.room_floor_cells(cell)
	var interior_ok := true
	for c in room_cells:
		for cq in Grid.quads_of(c):
			if (fm.material_at(cq) != "") and fm.floor_pattern_at_quad(cq) != 1:
				interior_ok = false
	_check("pattern room: every materialled interior quarter is pattern 1", interior_ok)

	# --- MapIO round-trip (v7): patterns serialize and restore identically ---
	var before: Dictionary = MapIO.serialize()
	_check("serialize: version is current", int(before["version"]) == MapIO.VERSION)
	_check("serialize: floor_patterns is non-empty", before["floor_patterns"].size() > 0)
	var pat_count: int = fm.quad_patterns().size()
	MapIO.apply_serialized(before, true)
	_check("round-trip: same number of patterned quarters", fm.quad_patterns().size() == pat_count)
	var after: Dictionary = MapIO.serialize()
	_check("round-trip: floor_patterns list is identical", str(after["floor_patterns"]) == str(before["floor_patterns"]))

	# --- pre-v7 map (no floor_patterns key) loads with patterns cleared, no error ---
	var legacy := before.duplicate(true)
	legacy.erase("floor_patterns")
	legacy["version"] = 6
	MapIO.apply_serialized(legacy, true)
	_check("back-compat: a v6 dict clears patterns without error", fm.quad_patterns().is_empty())

	# --- painting grass over a patterned quarter drops its pattern (no orphan) ---
	fm.write_pattern(quads[0], 1)
	fm.write_quad(quads[0], "") # erase to grass
	_check("erase to grass: pattern entry dropped", not (fm.floor_pattern_at_quad(quads[0]) != 0))

	# --- undo restores the pattern state (snapshot via serialize, per EditHistory) ---
	fm.apply_patterns([]); fm.rebuild()
	EditHistory.reset()
	_check("undo setup: no patterns", fm.quad_patterns().is_empty())
	fm.pattern_cell(cell, 1)
	fm.rebuild()
	EditHistory.commit("floor pattern")
	_check("undo setup: a pattern was committed", not fm.quad_patterns().is_empty() and EditHistory.can_undo())
	EditHistory.undo()
	_check("undo: the pattern is gone again", fm.quad_patterns().is_empty())
	EditHistory.redo()
	_check("redo: the pattern is back", not fm.quad_patterns().is_empty())

	finish()
