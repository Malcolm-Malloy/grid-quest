extends "res://dev/test_case.gd"

# Dev-only headless test for the Erase tool's structure removal (ROADMAP "Erase mode"). Builds
# the real world and checks that a click on a wall or door removes it topmost-first, that terrain
# is left for a follow-up click, and that each removal is one undo step that fully restores the
# level through the MapIO rebuild path. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_erase.tscn

# world-space centre of a cell, as _erase_structure_at expects (it floors local/CELL back to a cell)
func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	fm.set_mode(3) # Mode.ERASE

	EditHistory.reset()

	# --- wall removal ---
	var wall := Vector2i(6, 3) # part of the default top wall (see obstacles.blocked_cells)
	_check("setup: (6,3) is a wall", obs.is_blocked(wall))
	var removed_wall: bool = fm.erase_structure_at(_center(wall))
	_check("erase wall: reports a removal", removed_wall)
	_check("erase wall: (6,3) no longer blocked", not obs.is_blocked(wall))
	_check("erase wall: one undo step available", EditHistory.can_undo())

	# a second erase on the same cell finds no structure, so terrain would be erased instead
	# (topmost-first: structure first, terrain only once nothing is stacked on it)
	_check("erase wall again: nothing left to remove", not fm.erase_structure_at(_center(wall)))

	EditHistory.undo()
	_check("undo wall erase: (6,3) is a wall again", obs.is_blocked(wall))
	EditHistory.redo()
	_check("redo wall erase: (6,3) blocked cleared again", not obs.is_blocked(wall))
	EditHistory.undo() # leave the wall in place for the rest of the run

	# --- door removal ---
	var door := Vector2i(10, 5) # the A<->B vertical door (see obstacles.gate_cells)
	_check("setup: (10,5) is a structure (door)", obs.has_structure(door))
	_check("setup: (10,5) is not a wall", not obs.is_blocked(door))
	var doors_before: int = obs.gate_cells.size()
	var removed_door: bool = fm.erase_structure_at(_center(door))
	_check("erase door: reports a removal", removed_door)
	_check("erase door: (10,5) no longer a structure", not obs.has_structure(door))
	_check("erase door: one fewer door", obs.gate_cells.size() == doors_before - 1)

	EditHistory.undo()
	_check("undo door erase: door count restored", obs.gate_cells.size() == doors_before)
	_check("undo door erase: (10,5) a structure again", obs.has_structure(door))

	# --- nothing on a plain interior floor cell ---
	var floor_cell := Vector2i(8, 4) # inside room A, no wall or door
	_check("interior floor: no structure to erase", not fm.erase_structure_at(_center(floor_cell)))

	# --- remove_structure return values ---
	_check("remove_structure on wall returns 'wall'", obs.remove_structure(Vector2i(7, 3)) == "wall")
	_check("remove_structure on door returns 'door'", obs.remove_structure(Vector2i(10, 9)) == "door")
	_check("remove_structure on empty returns ''", obs.remove_structure(Vector2i(8, 4)) == "")

	# --- use-after-free guard: fading a wall then erasing it must not leave a freed ref that
	# _restore_faded later touches (the "previously freed" crash when deleting a hovered wall) ---
	EditHistory.reset()
	var hover_wall := Vector2i(9, 3) # still a wall in the default map
	_check("guard setup: (9,3) is a wall", obs.is_blocked(hover_wall))
	fm.fade_obstacles_at(hover_wall) # simulate the hover dim over the wall about to be erased
	fm.erase_structure_at(_center(hover_wall)) # frees the old wall nodes (deferred)
	# a hover on the same spot before the freed nodes clear must skip the dying node, not fade it
	fm.fade_obstacles_at(hover_wall)
	await get_tree().process_frame # let queue_free actually reap the old nodes
	await get_tree().process_frame
	fm.restore_faded() # would throw "previously freed" without the is_instance_valid guard
	_check("guard: survived fade+erase+restore without a freed-node error", true)
	_check("guard: (9,3) wall stayed erased", not obs.is_blocked(hover_wall))

	finish()
