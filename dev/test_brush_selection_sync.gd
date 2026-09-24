extends "res://dev/test_case.gd"

# Dev-only headless test for the two-way Brush-panel <-> floor-selection binding (ROADMAP "Coloured
# highlight system"): a Magic Wand floor selection REFLECTS its material + colour into the panel
# (armed_material/active_floor_color), and picking a material/colour in the panel then EDITS the
# selection in place (re-texture / re-tint), keeping the selection and the other axis. Text-only.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_brush_selection_sync.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	EditHistory.reset()

	var roomCell := Vector2i(8, 9) # inside the bottom-left room
	var center := Vector2(roomCell.x * 32 + 16, roomCell.y * 32 + 16)
	var q0: Vector2i = Grid.quads_of(roomCell)[0] # an interior quarter of that cell

	# make the room "red tiles"
	fm.set_room_style(roomCell, "tile")
	fm._tint_room(roomCell, Color.RED)
	fm._rebuild()
	_check("setup: room is tile", fm._quad_mat.get(q0, "") == "tile")
	_check("setup: room is red", fm._quad_tint.get(q0, Color.WHITE).is_equal_approx(Color.RED))

	# wand-select the room: the panel must reflect Tile + Red
	fm.set_mode(0) # Mode.WAND
	fm._wand_click(center)
	_check("wand select: a floor selection exists", fm.has_floor_selection())
	_check("panel reflects material (tile)", fm.armed_material() == "tile")
	_check("panel reflects colour (red)", fm.active_floor_color().is_equal_approx(Color.RED))

	# pick a colour in the panel -> re-tints the SELECTION in place, texture + selection kept
	fm.arm_floor_color(Color.GREEN)
	_check("panel colour re-tints the selection", fm._quad_tint.get(q0, Color.WHITE).is_equal_approx(Color.GREEN))
	_check("re-tint keeps the material", fm._quad_mat.get(q0, "") == "tile")
	_check("re-tint keeps the selection", fm.has_floor_selection())

	# pick a material in the panel -> re-textures the SELECTION in place, colour + selection kept
	fm.arm_floor_material("wood")
	_check("panel material re-textures the selection", fm._quad_mat.get(q0, "") == "wood")
	_check("re-texture keeps the colour", fm._quad_tint.get(q0, Color.WHITE).is_equal_approx(Color.GREEN))
	_check("re-texture keeps the selection", fm.has_floor_selection())

	finish()
