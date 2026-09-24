extends "res://dev/test_case.gd"

# Dev-only headless test for EditHistory (undo/redo). Builds the real world, performs a
# paint and a resize (each of which commits one undo step), then walks undo/redo and checks
# the live map returns to the right state at every step. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_undo.tscn

func _w(main: Node) -> int:
	return int(main.get_node("World/GridBackground").grid_width)

func _has_quad(main: Node, q: Vector2i) -> bool:
	return main.get_node("World/FloorManager")._quad_mat.has(q)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")

	# start from a clean baseline: the default freshly-built world, empty history
	EditHistory.reset()
	var w0 := _w(main)
	_check("baseline: no undo/redo available", not EditHistory.can_undo() and not EditHistory.can_redo())
	_check("baseline: quad (0,0) empty", not _has_quad(main, Vector2i(0, 0)))

	# action 1: paint one quarter wood, then commit (one step)
	fm._quad_mat[Vector2i(0, 0)] = "wood"
	fm._rebuild()
	EditHistory.commit("paint")
	_check("after paint: quad (0,0) present", _has_quad(main, Vector2i(0, 0)))
	_check("after paint: can undo", EditHistory.can_undo())

	# action 2: grow the left edge (auto-commits). Left-grow shifts every quad +2 in x, so the
	# wood quad moves (0,0) -> (2,0) and width goes up by one.
	MapEdit.grow("left")
	_check("after grow: width +1", _w(main) == w0 + 1)
	_check("after grow: quad shifted to (2,0)", _has_quad(main, Vector2i(2, 0)))

	# no-op commit must NOT create a phantom step (state unchanged since the grow)
	var undo_depth_before := EditHistory._undo.size()
	EditHistory.commit("noop")
	_check("no-op commit adds no step", EditHistory._undo.size() == undo_depth_before)

	# undo the grow
	EditHistory.undo()
	_check("undo grow: width back to w0", _w(main) == w0)
	_check("undo grow: quad back at (0,0)", _has_quad(main, Vector2i(0, 0)) and not _has_quad(main, Vector2i(2, 0)))

	# undo the paint
	EditHistory.undo()
	_check("undo paint: quad (0,0) gone", not _has_quad(main, Vector2i(0, 0)))
	_check("undo paint: nothing left to undo", not EditHistory.can_undo())
	_check("undo paint: redo available", EditHistory.can_redo())

	# redo the paint
	EditHistory.redo()
	_check("redo paint: quad (0,0) back", _has_quad(main, Vector2i(0, 0)))

	# redo the grow
	EditHistory.redo()
	_check("redo grow: width +1 again", _w(main) == w0 + 1)
	_check("redo grow: quad at (2,0) again", _has_quad(main, Vector2i(2, 0)))
	_check("redo grow: nothing left to redo", not EditHistory.can_redo())

	# a fresh edit after undo must clear the redo trail
	EditHistory.undo() # back before the grow
	fm._quad_mat[Vector2i(5, 5)] = "wood"
	fm._rebuild()
	EditHistory.commit("paint")
	_check("fresh edit clears redo", not EditHistory.can_redo())

	# player is exempt from history: moving the player then undoing must NOT teleport them
	var player = main.get_node("World/Player")
	player.position = Vector2(123, 456)
	player.target_position = player.position
	EditHistory.undo()
	_check("undo leaves the player where they stand", player.position == Vector2(123, 456))

	finish()
