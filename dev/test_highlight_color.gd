extends Node

# Dev-only headless test for the coloured-highlight palette (ROADMAP "Coloured highlight system").
# Verifies the per-ACTION colour actually reaches the outline shader (show_floor -> orange ground,
# show_walls -> purple walls) and that the square paint cursor's three roles map to the right colours
# (GROUND orange, ADD green, ERASE red). Text-only, no pixel readback.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_highlight_color.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame # let the mask's deferred keys enter the tree
	var mask = main.get_node("World/FloorHighlightMask")
	var fm = main.get_node("World/FloorManager")

	# --- mask outline colour follows the action ---
	mask.show_floor({}, [])
	await get_tree().process_frame
	_check("show_floor tints the outline ORANGE (ground)",
		mask._mat.get_shader_parameter("hl_color") == mask.GROUND)
	mask.show_walls([])
	await get_tree().process_frame
	_check("show_walls tints the outline PURPLE (walls)",
		mask._mat.get_shader_parameter("hl_color") == mask.WALLS)
	# an explicit override wins (e.g. doors would pass blue)
	mask.show_walls([], mask.DOORS)
	await get_tree().process_frame
	_check("show_walls override tints the outline BLUE (doors)",
		mask._mat.get_shader_parameter("hl_color") == mask.DOORS)

	# --- square paint cursor roles map to the palette ---
	var cur = fm._cursor
	cur.set_role(PaintCursor.Role.GROUND)
	_check("cursor GROUND role is orange", cur._line == PaintCursor.GROUND_LINE)
	cur.set_role(PaintCursor.Role.ADD)
	_check("cursor ADD role is green", cur._line == PaintCursor.ADD_LINE)
	cur.set_role(PaintCursor.Role.ERASE)
	_check("cursor ERASE role is red", cur._line == PaintCursor.ERASE_LINE)

	# --- the mask default (unset) is still red, so erase/untinted paths read as destructive ---
	_check("shader default hl_color is red",
		mask.GROUND != Color(0.95, 0.13, 0.13) and mask.WALLS != Color(0.95, 0.13, 0.13))

	print("RESULT: " + ("OK" if _fails == 0 else str(_fails) + " FAILURES"))
	get_tree().quit(_fails)
