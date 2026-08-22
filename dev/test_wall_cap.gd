extends Node

# Dev-only guard for wall faces (ROADMAP "Wall cap rebuild"): EVERY wall cell keeps its front face (its
# 3D body) - a straight wall, a corner, AND a +/T through-junction. (An earlier pass dropped the face at
# junctions/corners to make the cap connect; that removed the walls' body, so it was reverted. The
# greyscale textures keep the cap from reading as a separate "T".) Checked via piece_rects returning both
# a cap slice and a face rect (2 rects) on the default map's junction (10,7), corner (6,3), and an exposed
# top-wall cell (7,3).
# Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_wall_cap.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

# the full-width horizontal piece (run_length == 1) covering `cell` (not the thin vertical rail)
func _horizontal_piece(cell: Vector2i):
	for w in get_tree().get_nodes_in_group("walls"):
		if w.run_length == 1 and w.covers_cell(cell):
			return w
	return null

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame # walls spawn deferred; let them land

	var obs = main.get_node("World/Obstacles")
	var junction := Vector2i(10, 7) # + intersection: walls on all 4 sides
	var corner := Vector2i(6, 3)    # top-left corner: south (6,4) is a wall
	var exposed := Vector2i(7, 3)   # straight top wall: south (7,4) is open

	_check("setup: (10,7) is a + junction (wall to the south)", obs.is_blocked(Vector2i(10, 8)))
	_check("setup: (6,3) is a corner (wall to the south)", obs.is_blocked(Vector2i(6, 4)))
	_check("setup: (7,3) is a straight wall (open to the south)", not obs.has_structure(Vector2i(7, 4)))

	var jseg = _horizontal_piece(junction)
	var cseg = _horizontal_piece(corner)
	var eseg = _horizontal_piece(exposed)
	_check("found the junction piece", jseg != null)
	_check("found the corner piece", cseg != null)
	_check("found the exposed piece", eseg != null)

	# every wall cell keeps its front face: piece_rects returns a cap slice + a face rect (2 rects)
	_check("junction keeps its face (cap + face)", jseg != null and jseg.piece_rects(junction).size() == 2)
	_check("corner keeps its face (cap + face)", cseg != null and cseg.piece_rects(corner).size() == 2)
	_check("exposed keeps its face (cap + face)", eseg != null and eseg.piece_rects(exposed).size() == 2)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
