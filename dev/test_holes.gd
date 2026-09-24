extends "res://dev/test_case.gd"

# Dev-only headless test: a hole (GridBackground.absent_cells) is off-map for every floor tool. Painting
# into one stores nothing (the fill would otherwise draw over the void), a river bank never grows into
# one, a liquid does not feather toward one, and a wall cannot be placed in one.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_holes.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	var gb = main.get_node("World/GridBackground")
	var obs = main.get_node("World/Obstacles")
	var hole := Vector2i(20, 20)
	gb.set_absent_cells({hole: true})
	_check("a hole is not in bounds", not fm.in_bounds(hole))
	_check("its neighbour is", fm.in_bounds(hole + Vector2i.LEFT))

	fm.set_mode(EditorState.Mode.CELL)
	fm.arm_floor_material("wood")
	fm.paint(Grid.cell_center(hole), true)
	var stored := false
	for q in Grid.quads_of(hole):
		stored = stored or (fm.material_at(q) != "")
	_check("painting a hole stores no floor", not stored)

	# a water cell right beside the hole: no bank quarter may land in the hole, and the edge facing the
	# hole must read as a map edge (no feather), exactly like the outer border
	var wet := hole + Vector2i.LEFT
	for q in Grid.quads_of(wet):
		fm.write_quad(q, "water")
	fm.rebuild()
	var banked := false
	for q in fm.render.bank_quads():
		banked = banked or Grid.cell_of_quad(q) == hole
	_check("no river bank grows into a hole", not banked)
	_check("water does not feather toward a hole", fm.render.liquid_edge_mask(Vector2i(wet.x * 2 + 1, wet.y * 2), "water") & 2 == 0)

	fm.set_mode(EditorState.Mode.WALL)
	fm.place_wall_at(Grid.cell_center(hole))
	_check("a wall cannot be placed in a hole", not obs.is_blocked(hole))
	finish()
