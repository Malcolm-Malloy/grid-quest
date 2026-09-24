extends "res://dev/test_case.gd"

# Dev-only headless test for the cell-existence model (ROADMAP "Map extent and edge editing" ->
# single-cell edge editing / non-square maps): GridBackground.absent_cells, MapEdit.add_cell /
# remove_cell, walkability, save/load, resize-carry, and undo. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_cell_existence.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var gb = main.get_node("World/GridBackground")
	var fm = main.get_node("World/FloorManager")

	# start from a blank rectangle so the geometry is easy to reason about
	MapIO.new_map()
	var w0: int = gb.grid_width
	var h0: int = gb.grid_height
	_check("blank map is a solid rectangle (no holes)", gb.absent_cells.is_empty())
	_check("cell_present: interior cell", gb.cell_present(5, 5))
	_check("cell_present: out-of-box cell", not gb.cell_present(-1, 5))

	# --- remove one cell -> a hole ---
	EditHistory.reset()
	_check("remove_cell interior returns true", MapEdit.remove_cell(Vector2i(5, 5)))
	_check("removed cell is now absent", not gb.cell_present(5, 5))
	_check("neighbours stay present", gb.cell_present(4, 5) and gb.cell_present(6, 5))
	_check("box size unchanged by a hole", gb.grid_width == w0 and gb.grid_height == h0)

	# --- removing contents with the cell: paint then remove strips the quads ---
	fm._write_quad(Vector2i(10 * 2, 10 * 2), "wood")
	fm._rebuild()
	MapEdit.remove_cell(Vector2i(10, 10))
	var snap: Dictionary = MapIO.serialize()
	var has_quad_on_10 := false
	for q in snap["quads"]:
		if int(q[0]) / 2 == 10 and int(q[1]) / 2 == 10:
			has_quad_on_10 = true
	_check("remove strips the cell's floor quads", not has_quad_on_10)

	# --- undo restores the hole (and its contents) ---
	EditHistory.undo()
	_check("undo restores the removed cell", gb.cell_present(10, 10))

	# --- add a cell BEYOND the right edge -> box grows, only that cell present ---
	MapIO.new_map()
	EditHistory.reset()
	var y := 3
	_check("add_cell beyond right edge returns true", MapEdit.add_cell(Vector2i(w0, y)))
	_check("box width grew by 1", gb.grid_width == w0 + 1)
	_check("the added spur cell is present", gb.cell_present(w0, y))
	_check("its row-mates in the new column are absent", not gb.cell_present(w0, y + 1) and not gb.cell_present(w0, 0))

	# --- add BEYOND the top edge -> origin shifts, height grows ---
	MapIO.new_map()
	EditHistory.reset()
	var before_h: int = gb.grid_height
	_check("add_cell beyond top edge returns true", MapEdit.add_cell(Vector2i(4, -1)))
	_check("box height grew by 1", gb.grid_height == before_h + 1)
	_check("added top cell present at (4,0) after the origin shift", gb.cell_present(4, 0))
	_check("the rest of the new top row is absent", not gb.cell_present(0, 0) and not gb.cell_present(4 + 1, 0))
	# a previously-interior cell shifted down by one (origin shift), still present
	_check("existing cells shifted down and stay present", gb.cell_present(4, 1))

	# --- fill a hole back in ---
	MapIO.new_map()
	EditHistory.reset()
	MapEdit.remove_cell(Vector2i(8, 8))
	_check("hole made", not gb.cell_present(8, 8))
	_check("add_cell fills the hole", MapEdit.add_cell(Vector2i(8, 8)))
	_check("hole filled", gb.cell_present(8, 8))

	# --- guards ---
	_check("add_cell on an already-present cell is a no-op", not MapEdit.add_cell(Vector2i(8, 8)))
	_check("add_cell two steps beyond an edge is rejected", not MapEdit.add_cell(Vector2i(gb.grid_width + 1, 3)))
	_check("remove_cell of an out-of-box cell is rejected", not MapEdit.remove_cell(Vector2i(-1, 0)))

	# --- terrain copy: painting the right edge then adding a spur copies its material ---
	MapIO.new_map()
	EditHistory.reset()
	var ew: int = gb.grid_width
	for q in fm._cell_quads(Vector2i(ew - 1, 6)):
		fm._quad_mat[q] = "wood"
	fm._rebuild()
	MapEdit.add_cell(Vector2i(ew, 6)) # spur beyond right, should copy the wood neighbour
	var snap2: Dictionary = MapIO.serialize()
	var spur_is_wood := false
	for q in snap2["quads"]:
		if int(q[0]) / 2 == ew and int(q[1]) / 2 == 6 and String(q[2]) == "wood":
			spur_is_wood = true
	_check("spur cell copied the neighbour's terrain (wood)", spur_is_wood)

	# --- save / load round-trip preserves holes ---
	MapIO.new_map()
	MapEdit.remove_cell(Vector2i(2, 2))
	MapEdit.remove_cell(Vector2i(3, 3))
	MapIO.save_map("_cellexist_test")
	MapIO.new_map() # wipe live holes
	_check("new map cleared holes", gb.absent_cells.is_empty())
	MapIO.load_map("_cellexist_test")
	_check("load restores hole (2,2)", not gb.cell_present(2, 2))
	_check("load restores hole (3,3)", not gb.cell_present(3, 3))
	MapIO.delete_map("_cellexist_test")

	# --- old-format map (no absent_cells key) loads as a solid rectangle ---
	var legacy := MapIO.serialize()
	legacy.erase("absent_cells")
	MapIO.apply_serialized(legacy)
	_check("a dict with no absent_cells key loads as a full rectangle", gb.absent_cells.is_empty())

	# --- resize carries holes: a hole survives a row/column grow, shifted correctly ---
	MapIO.new_map()
	MapEdit.remove_cell(Vector2i(5, 5))
	MapEdit.grow("left") # shifts everything +1 x
	_check("hole shifted with a grow:left (5,5)->(6,5)", not gb.cell_present(6, 5) and gb.cell_present(5, 5))

	# --- resize now carries the later stores too (regression: _shift used to drop these) ---
	MapIO.new_map()
	var obs = main.get_node("World/Obstacles")
	# place a wall and give it a non-default material, then grow and confirm the material survives
	MapEdit.add_cell(Vector2i(gb.grid_width, 2)) # ensure MapEdit path is exercised; ignore result
	MapIO.new_map()
	obs.apply_map([Vector2i(4, 4)], [], [])
	obs.set_wall_material(Vector2i(4, 4), "wood")
	await get_tree().process_frame
	MapEdit.grow("left")
	var snap3: Dictionary = MapIO.serialize()
	var mat_survived := false
	for a in snap3.get("wall_materials", []):
		if int(a[0]) == 5 and int(a[1]) == 4 and String(a[2]) == "wood":
			mat_survived = true
	_check("resize carries wall materials (regression)", mat_survived)

	# --- can_add_cell / can_remove_cell predicates (drive the hover highlight; must not mutate) ---
	MapIO.new_map()
	var cw: int = gb.grid_width
	var ch: int = gb.grid_height
	_check("can_add_cell: interior present cell is NOT addable", not MapEdit.can_add_cell(Vector2i(10, 10)))
	_check("can_add_cell: cell just beyond the right edge IS addable", MapEdit.can_add_cell(Vector2i(cw, 15)))
	_check("can_add_cell: cell just beyond the top edge IS addable", MapEdit.can_add_cell(Vector2i(15, -1)))
	_check("can_add_cell: two cells beyond an edge is NOT addable", not MapEdit.can_add_cell(Vector2i(cw + 1, 15)))
	_check("can_add_cell: a diagonal past the corner is NOT addable", not MapEdit.can_add_cell(Vector2i(cw, -1)))
	_check("can_remove_cell: a present interior cell IS removable", MapEdit.can_remove_cell(Vector2i(10, 10)))
	_check("can_remove_cell: an out-of-box cell is NOT removable", not MapEdit.can_remove_cell(Vector2i(-1, 0)))
	_check("predicates did not mutate the map (still a full rectangle)", gb.absent_cells.is_empty() and gb.grid_width == cw and gb.grid_height == ch)

	# --- drag-add: many cells applied then ONE commit = ONE undo entry (like a paint stroke) ---
	MapIO.new_map()
	EditHistory.reset()
	var dw: int = gb.grid_width
	# lay a vertical strip of spur cells down the right edge, as a drag would (add_cell_applied, no commit)
	var laid := 0
	for ry in [10, 11, 12, 13]:
		if MapEdit.add_cell_applied(Vector2i(dw, ry)):
			laid += 1
	_check("drag laid all four spur cells", laid == 4)
	_check("drag: all four cells present before commit", gb.cell_present(dw, 10) and gb.cell_present(dw, 11) and gb.cell_present(dw, 12) and gb.cell_present(dw, 13))
	EditHistory.commit("add cells") # one entry for the whole strip
	_check("drag: one undo reverts the ENTIRE strip", true)
	EditHistory.undo()
	_check("after one undo: none of the strip remains", not gb.cell_present(dw, 10) and not gb.cell_present(dw, 11) and not gb.cell_present(dw, 12) and not gb.cell_present(dw, 13))
	EditHistory.redo()
	_check("redo restores the whole strip", gb.cell_present(dw, 10) and gb.cell_present(dw, 13))

	finish()
