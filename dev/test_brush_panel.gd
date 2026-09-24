extends "res://dev/test_case.gd"

# Dev-only test for the persistent Brush panel (ROADMAP "Photoshop-style persistent LEFT panel"): the
# left tool strip shows the armed floor material + colour as clickable swatches, live-synced to
# FloorManager via brush_changed. Checks the panel builds, clicking arms the brush, and menu arming
# syncs the panel highlight back. Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_brush_panel.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var ts = get_tree().get_first_node_in_group("tool_strip")
	var fm = main.get_node("World/FloorManager")

	_check("Brush section exists", ts._sections.has("Brush"))
	_check("material buttons == floor MENU", ts._mat_buttons.size() == FloorMaterials.MATERIAL_NAMES.size()) # Grass+Wood+Concrete+Tile+Carpet+Water
	_check("8 colour swatches", ts._col_swatches.size() == 8) # 9 presets minus the culled Grey

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
	_check("panel colour keeps combined floor brush", fm.active_tool_kind() == EditorState.Brush.FLOOR and fm.active_floor_color().is_equal_approx(FloorMaterials.COLORS[1][1]))
	_check("panel colour keeps the armed material (carpet)", fm.armed_material() == "carpet" and ts._mat_buttons["carpet"].button_pressed)

	# and a paint with the combined brush writes BOTH the material and the tint into the same quarter
	var q := Vector2i(3, 3)
	fm.write_quad(q, "wood")
	fm.arm_floor_material("tile")
	fm.arm_floor_color(FloorMaterials.COLORS[4][1]) # Green
	fm.paint(Vector2(q.x * 16 + 4, q.y * 16 + 4)) # Fine grain lands in quarter q (HALF = 16)
	_check("combined paint writes material", fm.material_at(q) == "tile")
	_check("combined paint writes tint", fm.floor_tint_at_quad(q).is_equal_approx(FloorMaterials.COLORS[4][1]))

	# the preview swatch shows the armed texture tinted by the armed colour
	fm.arm_floor_material("tile")
	fm.arm_floor_color(FloorMaterials.COLORS[1][1]) # Red
	_check("preview swatch shows the armed texture", ts._brush_preview.texture == fm.armed_brush_texture())
	_check("preview swatch tinted by the armed colour", ts._brush_preview.modulate.is_equal_approx(FloorMaterials.COLORS[1][1]))

	# --- the MATERIAL-AWARE swatch row (ROADMAP "Colour palette: 16 swatches, half material-aware").
	# The fun row above is constant; this one must SWAP with the armed material, which is the feature.
	fm.arm_floor_material("wood")
	_check("the material-aware row is shown", ts._mat_col_grid.visible and ts._mat_col_label.visible)
	_check("...headed for the armed material", ts._mat_col_label.text == "For Wood")
	_check("...with eight realistic tints", ts._mat_col_swatches.size() == 8)
	var wood_first: Color = ts._mat_col_swatches[0]["color"]
	fm.arm_floor_material("snow")
	_check("arming another material SWAPS the row", ts._mat_col_label.text == "For Snow")
	_check("...to that material's own tints", not (ts._mat_col_swatches[0]["color"] as Color).is_equal_approx(wood_first))
	_check("...which are the table's", (ts._mat_col_swatches[0]["color"] as Color).is_equal_approx(FloorMaterials.MATERIAL_COLORS["snow"][0][1]))
	_check("every floor material has a table", func_all_have_tables(fm))
	# picking one arms it, exactly like the fun row
	ts._mat_col_swatches[2]["button"].pressed.emit()
	_check("clicking a material-aware swatch arms that colour",
		fm.active_floor_color().is_equal_approx(FloorMaterials.MATERIAL_COLORS["snow"][2][1]))
	# the fun row is unaffected by any of it
	_check("the constant row still has its eight", ts._col_swatches.size() == FloorMaterials.COLORS.size())

	finish()

# every material the Material grid offers must have a realistic table, or picking it would silently
# drop the row -- the one way this feature can be half-built as the roster grows
func func_all_have_tables(fm) -> bool:
	for entry in FloorMaterials.MATERIAL_NAMES:
		if FloorMaterials.material_colors(entry[1]).size() != 8:
			return false
	return true
