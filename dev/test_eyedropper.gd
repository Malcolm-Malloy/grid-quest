extends "res://dev/test_case.gd"

# Dev-only headless test for the Eyedropper (ROADMAP "Eyedropper"): picking an existing cell's
# material + colour into the active brush, from the tool AND from Alt+click while a paint brush is
# active. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_eyedropper.tscn

func _mid(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	EditHistory.reset()

	# lay a known floor: sand tinted red at cell (20,10), plain wood at (21,10)
	var sand := Vector2i(20, 10)
	var wood := Vector2i(21, 10)
	for q in Grid.quads_of(sand):
		fm._write_quad(q, "sand")
		fm._write_tint(q, Color(0.8, 0.2, 0.2))
	for q in Grid.quads_of(wood):
		fm._write_quad(q, "wood")
	fm._rebuild()
	await get_tree().process_frame

	# --- 1. the tool picks material AND colour, and never edits the map ---
	var before := JSON.stringify(MapIO.serialize())
	fm.set_mode(EditorState.Mode.EYEDROP)
	_check("picked a floor", fm._eyedrop_at(_mid(sand)))
	_check("picked the material", fm.armed_material() == "sand")
	_check("picked the colour", fm.active_floor_color().is_equal_approx(Color(0.8, 0.2, 0.2)))
	_check("the pick armed the brush (next click paints it)", fm.is_armed())
	_check("the pick is a floor-brush pick", fm.active_tool_kind() == EditorState.Brush.FLOOR)
	_check("picking edited nothing", JSON.stringify(MapIO.serialize()) == before)
	_check("picking committed no undo entry", not EditHistory.can_undo())

	# --- 2. picking a different cell replaces the whole brush, tint included ---
	fm._eyedrop_at(_mid(wood))
	_check("picked the second material", fm.armed_material() == "wood")
	_check("an untinted cell picks Natural (white)", fm.active_floor_color().is_equal_approx(Color.WHITE))

	# --- 3. bare grass is a real answer (it arms the grass eraser) ---
	fm._eyedrop_at(_mid(Vector2i(30, 20)))
	_check("bare ground picks the grass brush", fm.armed_material() == "")

	# --- 4. the same pick from a PAINT mode replaces the armed brush without painting. (This is what
	# Alt+click runs; the routing itself reads the OS cursor, which a headless run cannot place, so the
	# branch that calls this is covered by inspection, not here.) ---
	fm.set_mode(EditorState.Mode.CELL)
	fm.arm_floor_material("snow")
	_check("armed snow to paint with", fm.armed_material() == "snow")
	fm._eyedrop_at(_mid(sand))
	_check("picking in Cell mode loaded the sampled material over the armed one", fm.armed_material() == "sand")
	_check("picking kept the mode on Cell (you keep painting)", fm.mode() == EditorState.Mode.CELL)
	_check("picking in a paint mode painted nothing", JSON.stringify(MapIO.serialize()) == before)

	# --- 5. a WALL picks the wall brush (material + colour) ---
	var wall := Vector2i(8, 3) # a cell on the seeded room's top wall run
	_check("setup: that cell is a wall", obs.is_blocked(wall))
	obs.set_wall_material(wall, "slate")
	obs.set_wall_color(wall, Color(0.2, 0.4, 0.9))
	await get_tree().process_frame
	fm.set_mode(EditorState.Mode.EYEDROP)
	fm._eyedrop_at(_mid(wall))
	_check("picked the wall material", fm.armed_wall_material() == "slate")
	_check("picked the wall colour", fm.active_wall_color().is_equal_approx(Color(0.2, 0.4, 0.9)))
	_check("the pick is a wall-brush pick", fm.active_tool_kind() == EditorState.Brush.WALL_MATERIAL)

	# --- 6. off-map picks nothing ---
	_check("a pick off the map does nothing", not fm._eyedrop_at(Vector2(-40, -40)))

	finish()
