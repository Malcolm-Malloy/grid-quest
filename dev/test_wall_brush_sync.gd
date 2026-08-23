extends Node

# Dev-only headless test for the WALL side of the two-way Brush-panel binding (ROADMAP "Coloured
# highlight system"): a Magic Wand wall selection reflects its dominant material + colour into the
# panel (armed_wall_material / active_wall_color), and picking a wall material/colour in the panel then
# edits the selection in place (re-material / re-tint), keeping the selection and the other axis. Text.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_wall_brush_sync.tscn

var _fails := 0
func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond: _fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	EditHistory.reset()

	var wallCenter := Vector2(8 * 32 + 16, 3 * 32 + 16) # a cell on the top wall run
	_check("setup: it is a wall cell", obs.is_blocked(Vector2i(8, 3)))

	# select the wall run, then paint the whole run wood + red directly, then re-select to reflect it
	fm.set_mode(0) # Mode.WAND
	fm._wand_click(wallCenter)
	_check("wand select: a wall selection exists", fm.has_wall_selection())
	var wcell: Vector2i = fm._sel_cells.keys()[0]
	obs._material_cells(fm._sel_cells, "wood")
	obs._color_cells(fm._sel_cells, Color.RED)
	fm._clear_selection()
	fm._wand_click(wallCenter) # re-select the now wood+red run -> reflect into the panel
	_check("panel reflects wall material (wood)", fm.armed_wall_material() == "wood")
	_check("panel reflects wall colour (red)", fm.active_wall_color().is_equal_approx(Color.RED))

	# pick a colour in the panel -> re-tints the wall SELECTION in place, material + selection kept
	fm.arm_wall_color(Color.GREEN)
	_check("panel colour re-tints the wall selection", obs.get_wall_color(wcell).is_equal_approx(Color.GREEN))
	_check("re-tint keeps the wall material", obs.get_wall_material(wcell) == "wood")
	_check("re-tint keeps the wall selection", fm.has_wall_selection())

	# pick a material in the panel -> re-materials the SELECTION in place, colour + selection kept
	fm.arm_wall_material("slate")
	_check("panel material re-materials the wall selection", obs.get_wall_material(wcell) == "slate")
	_check("re-material keeps the wall colour", obs.get_wall_color(wcell).is_equal_approx(Color.GREEN))
	_check("re-material keeps the wall selection", fm.has_wall_selection())

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
