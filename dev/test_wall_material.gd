extends Node

# Dev-only headless test for Wall materials (ROADMAP item 7 -> "Terrain patterns and material
# variants" -> wall materials): a per-cell face/cap texture pair (Stone/Wood/Slate) stored parallel
# to and independent of the wall colour tint. Checks set/reset at cell + building grain, that the
# wall_segment picks the right texture pair, MapIO round-trip (v6), pre-v6 back-compat, and undo/redo.
# Text-only, no rendering (renders hang headless on this machine).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_wall_material.tscn

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
	var obs = main.get_node("World/Obstacles")
	EditHistory.reset()

	var wall := Vector2i(6, 3) # part of the default top wall (same cell the context-menu test uses)
	_check("setup: (6,3) is a wall", obs.is_blocked(wall))
	_check("default material is stone", obs.get_wall_material(wall) == "stone")
	_check("default: nothing stored for a stone cell", not obs.wall_materials.has(wall))

	# --- cell-grain set + reset ---
	obs.set_wall_material(wall, "wood")
	_check("set wood: reads back wood", obs.get_wall_material(wall) == "wood")
	_check("set wood: stored in wall_materials", obs.wall_materials.get(wall, "") == "wood")
	obs.set_wall_material(wall, "stone")
	_check("reset stone: reads back stone", obs.get_wall_material(wall) == "stone")
	_check("reset stone: entry erased", not obs.wall_materials.has(wall))

	# --- the spawned wall_segment picks the right texture pair for its cell ---
	obs.set_wall_material(wall, "slate")
	await get_tree().process_frame # let _apply_wall_materials push onto the segments
	var seg_ok := false
	var pair_ok := false
	for w in get_tree().get_nodes_in_group("walls"):
		var idx: int = w.cells().find(wall)
		if idx != -1:
			seg_ok = true
			pair_ok = w._cell_material(idx) == "slate" and w._cell_textures(idx)[0] == w.MATERIALS["slate"][0]
	_check("segment: found the wall segment covering (6,3)", seg_ok)
	_check("segment: it reports slate and the slate face texture", pair_ok)
	obs.set_wall_material(wall, "stone")

	# --- new materials Brick + Hedge are registered and render through the same path ---
	var fm = main.get_node("World/FloorManager")
	var menu_mats := {}
	for e in fm.WALL_MATERIALS:
		menu_mats[e[1]] = true
	_check("Brick + Hedge in the wall-material menu", menu_mats.has("brick") and menu_mats.has("hedge"))
	_check("Brick + Hedge have a cap texture (Brush panel)", fm.WALL_TEX.has("brick") and fm.WALL_TEX.has("hedge"))
	for m in ["brick", "hedge"]:
		obs.set_wall_material(wall, m)
		await get_tree().process_frame
		var ok := false
		for w in get_tree().get_nodes_in_group("walls"):
			var idx: int = w.cells().find(wall)
			if idx != -1 and w._cell_material(idx) == m and w._cell_textures(idx)[0] == w.MATERIALS[m][0]:
				ok = true
		_check("segment renders %s with its own face texture" % m, ok)
	obs.set_wall_material(wall, "stone")

	# --- building-grain: material every wall of the building at once ---
	var bcells: Dictionary = obs.building_cells(wall)
	_check("building: (6,3) belongs to a multi-cell building", bcells.size() > 1)
	obs.material_building(wall, "wood")
	var all_wood := true
	for c in bcells:
		if obs.get_wall_material(c) != "wood":
			all_wood = false
	_check("building: every wall of the building is wood", all_wood)
	obs.material_building(wall, "stone")
	_check("building: reset back to stone clears the store", obs.wall_materials.is_empty())

	# --- MapIO round-trip (v6): materials serialize and restore identically ---
	obs.set_wall_material(wall, "wood")
	obs.set_wall_material(Vector2i(7, 3), "slate")
	var before: Dictionary = MapIO.serialize()
	_check("serialize: version is current", int(before["version"]) == MapIO.VERSION)
	_check("serialize: wall_materials is non-empty", before["wall_materials"].size() > 0)
	var mat_count: int = obs.wall_materials.size()
	MapIO.apply_serialized(before, true)
	_check("round-trip: same number of materialled cells", obs.wall_materials.size() == mat_count)
	var after: Dictionary = MapIO.serialize()
	_check("round-trip: wall_materials list is identical", str(after["wall_materials"]) == str(before["wall_materials"]))

	# --- pre-v6 map (no wall_materials key) loads with materials cleared, no error ---
	var legacy := before.duplicate(true)
	legacy.erase("wall_materials")
	legacy["version"] = 5
	MapIO.apply_serialized(legacy, true)
	_check("back-compat: a v5 dict clears materials without error", obs.wall_materials.is_empty())

	# --- undo restores the material state (snapshot via serialize, per EditHistory) ---
	MapIO.apply_serialized(_stone_state(before), true) # baseline: no materials
	EditHistory.reset()
	_check("undo setup: no materials", obs.wall_materials.is_empty())
	obs.set_wall_material(wall, "wood")
	EditHistory.commit("wall material")
	_check("undo setup: a material was committed", not obs.wall_materials.is_empty() and EditHistory.can_undo())
	EditHistory.undo()
	_check("undo: the material is gone again", obs.wall_materials.is_empty())
	EditHistory.redo()
	_check("redo: the material is back", obs.get_wall_material(wall) == "wood")

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)

# a copy of `data` with no wall materials, for a clean undo baseline
func _stone_state(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	d["wall_materials"] = []
	return d
