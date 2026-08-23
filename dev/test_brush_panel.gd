extends Node

# Dev-only test for the persistent Brush panel (ROADMAP "Photoshop-style persistent LEFT panel"): the
# left tool strip shows the armed floor material + colour as clickable swatches, live-synced to
# FloorManager via brush_changed. Checks the panel builds, clicking arms the brush, and menu arming
# syncs the panel highlight back. Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_brush_panel.tscn

var _fails := 0
func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond: _fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var ts = get_tree().get_first_node_in_group("tool_strip")
	var fm = main.get_node("World/FloorManager")

	_check("Brush section exists", ts._sections.has("Brush"))
	_check("5 material buttons", ts._mat_buttons.size() == 5)
	_check("9 colour swatches", ts._col_swatches.size() == 9)

	# clicking a material button in the panel arms it
	fm.set_mode(1) # Mode.CELL
	ts._mat_buttons["tile"].pressed.emit()
	_check("panel material click arms the brush", fm.armed_material() == "tile" and fm.is_armed())

	# arming from FloorManager (as the right-click menu does) syncs the panel highlight back
	fm.arm_floor_material("carpet")
	_check("panel highlight syncs to fm arming (carpet pressed)", ts._mat_buttons["carpet"].button_pressed)

	# the panel is a COMBINED brush: picking a colour sets the tint but KEEPS the armed material, so a
	# paint lays both. carpet was armed above; clicking Red must leave the material carpet and the tool
	# "floor" (not switch to the tint-only "floor_color" tool), with both lit in the panel.
	ts._col_swatches[1]["button"].pressed.emit() # index 1 = Red
	_check("panel colour keeps combined floor brush", fm.active_tool_kind() == "floor" and fm.active_floor_color().is_equal_approx(fm.FLOOR_COLORS[1][1]))
	_check("panel colour keeps the armed material (carpet)", fm.armed_material() == "carpet" and ts._mat_buttons["carpet"].button_pressed)

	# and a paint with the combined brush writes BOTH the material and the tint into the same quarter
	var q := Vector2i(3, 3)
	fm._write_quad(q, "wood")
	fm.arm_floor_material("tile")
	fm.arm_floor_color(fm.FLOOR_COLORS[4][1]) # Green
	fm._paint(Vector2(q.x * 16 + 4, q.y * 16 + 4)) # Fine grain lands in quarter q (HALF = 16)
	_check("combined paint writes material", fm._quad_mat.get(q, "") == "tile")
	_check("combined paint writes tint", fm._quad_tint.get(q, Color.WHITE).is_equal_approx(fm.FLOOR_COLORS[4][1]))

	# the preview swatch shows the armed texture tinted by the armed colour
	fm.arm_floor_material("tile")
	fm.arm_floor_color(fm.FLOOR_COLORS[1][1]) # Red
	_check("preview swatch shows the armed texture", ts._brush_preview.texture == fm.armed_brush_texture())
	_check("preview swatch tinted by the armed colour", ts._brush_preview.modulate.is_equal_approx(fm.FLOOR_COLORS[1][1]))

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
