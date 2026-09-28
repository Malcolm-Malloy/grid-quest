extends "res://dev/test_case.gd"

# Dev-only headless test for the in-place Wall <-> Door convert (ROADMAP "Editor fixes + build-menu
# UX" -> convert wall to door and vice versa). The properties inspector gains a "Convert to Door"
# button on a wall and a "Convert to Wall" button on a door; each swaps the structure in place through
# the MapIO rebuild and re-inspects the same cell. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_wall_door_convert.tscn

func _is_door(obs, cell: Vector2i) -> bool:
	return not obs.door_at(cell).is_empty()

func _find(box, text: String) -> Button:
	for c in box.get_children():
		if c is Button and c.text == text:
			return c
	return null

func _ready() -> void:
	var main: Node = await boot_main()
	var obs = main.get_node("World/Obstacles")
	var insp = get_tree().get_first_node_in_group("inspector")
	EditHistory.reset()

	var cell := Vector2i(8, 3) # a cell on the top wall run
	_check("start: cell is a wall (blocked, no door)", obs.is_blocked(cell) and not _is_door(obs, cell))

	# inspect the wall, press Convert to Door
	insp.inspect_wall(cell)
	var to_door := _find(insp._box, "Convert to Door")
	_check("wall inspector has a 'Convert to Door' button", to_door != null)
	to_door.pressed.emit()
	_check("wall -> door: now a door, not blocked", _is_door(obs, cell) and not obs.is_blocked(cell))
	_check("wall -> door: door follows the run orientation (horizontal)", obs.door_at(cell).get("orientation", "") == Grid.Orient.HORIZONTAL)

	# the panel re-inspected as a door; press Convert to Wall
	var to_wall := _find(insp._box, "Convert to Wall")
	_check("door inspector has a 'Convert to Wall' button", to_wall != null)
	to_wall.pressed.emit()
	_check("door -> wall: now a wall (blocked, no door)", obs.is_blocked(cell) and not _is_door(obs, cell))

	# undo the round-trip should be possible (two structural edits committed)
	_check("two convert edits were committed", EditHistory.can_undo())

	finish()
