extends Node

# Dev-only headless logic test for MapEdit (grid resize). Builds the real world, runs the
# GQ_RESIZE ops, and prints the serialized map so coordinates can be checked by text with
# no rendering (fast under --headless, unlike capture.tscn which awaits a drawn frame).
#   GQ_RESIZE="grow:left;shrink:left" /Applications/Godot.app/Contents/MacOS/Godot \
#     --headless --path . res://dev/test_resize.tscn

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var load_name := OS.get_environment("GQ_LOAD")
	if load_name != "":
		MapIO.load_map(load_name)

	# GQ_PAINTEDGE paints the outermost row/column wood so grow's copy-neighbour can be checked
	var pe := OS.get_environment("GQ_PAINTEDGE")
	if pe != "":
		var fm = main.get_node("World/FloorManager")
		var gb = main.get_node("World/GridBackground")
		var cells: Array = []
		match pe:
			"left": for y in range(gb.grid_height): cells.append(Vector2i(0, y))
			"right": for y in range(gb.grid_height): cells.append(Vector2i(gb.grid_width - 1, y))
			"top": for x in range(gb.grid_width): cells.append(Vector2i(x, 0))
			"bottom": for x in range(gb.grid_width): cells.append(Vector2i(x, gb.grid_height - 1))
		for c in cells:
			for q in fm._cell_quads(c):
				fm._quad_mat[q] = "wood"
		fm._rebuild()

	print("BEFORE: ", JSON.stringify(MapIO.serialize()))
	var resize := OS.get_environment("GQ_RESIZE")
	if resize != "":
		for op in resize.split(";", false):
			var parts := op.split(":")
			if parts.size() == 2:
				if parts[0] == "grow":
					MapEdit.grow(parts[1])
				elif parts[0] == "shrink":
					MapEdit.shrink(parts[1])
	print("AFTER: ", JSON.stringify(MapIO.serialize()))

	# GQ_TEST_EDGEAT unit-tests MapSizeTool.edge_at (pure geometry) on a 48x32 grid
	if OS.get_environment("GQ_TEST_EDGEAT") == "1":
		var t = load("res://world/map_size_tool.gd").new()
		var pts := [Vector2(100, -16), Vector2(100, 16), Vector2(-16, 100), Vector2(1550, 100), Vector2(-16, -16)]
		for pt in pts:
			print("EDGEAT ", pt, " -> ", t.edge_at(pt, 48, 32))
		t.free()

	get_tree().quit()
