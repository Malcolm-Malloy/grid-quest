extends Node

# Dev-only headless test for BRIDGES, slice 1 (crossable deck over water). Builds the real world and
# checks: bridges are a placed-object store on Obstacles; the BRIDGE tool auto-orients to the water
# run it spans (horizontal river -> vertical bridge, and vice-versa); a bridge re-enables crossing on
# a water cell (passable-over-impassable); the deck node spawns; and MapIO round-trips bridges at v8.
# Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_bridge.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _quads(cell: Vector2i) -> Array:
	return [
		Vector2i(cell.x * 2, cell.y * 2), Vector2i(cell.x * 2 + 1, cell.y * 2),
		Vector2i(cell.x * 2, cell.y * 2 + 1), Vector2i(cell.x * 2 + 1, cell.y * 2 + 1),
	]

func _fill_water(fm, cell: Vector2i) -> void:
	for q in _quads(cell):
		fm._quad_mat[q] = "water"

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	var player = main.get_node("World/Player")

	# --- store + API present ---
	_check("Obstacles has a bridge_cells store", obs.bridge_cells is Array)
	fm.set_mode(8) # Mode.BRIDGE is the last enum value; set_mode takes the raw index from the tool strip
	_check("BRIDGE is mode index 8", fm.mode() == 8)

	# --- add / query ---
	_check("add_bridge places a bridge", obs.add_bridge(Vector2i(5, 5), "horizontal"))
	_check("is_bridge finds it", obs.is_bridge(Vector2i(5, 5)))
	_check("bridge_orientation reads back", obs.bridge_orientation(Vector2i(5, 5)) == "horizontal")
	_check("add_bridge is a no-op on an occupied cell", not obs.add_bridge(Vector2i(5, 5), "vertical"))
	_check("remove_bridge clears it", obs.remove_bridge(Vector2i(5, 5)) and not obs.is_bridge(Vector2i(5, 5)))

	# --- auto-orient to the water run (a horizontal river gets a north-south bridge) ---
	fm._quad_mat = {}
	_fill_water(fm, Vector2i(24, 15))
	_fill_water(fm, Vector2i(26, 15)) # water left+right of (25,15) => horizontal river
	fm._rebuild()
	fm.set_mode(8) # Mode.BRIDGE
	fm._place_bridge_at(Vector2(25 * 32 + 16, 15 * 32 + 16))
	_check("horizontal river -> vertical bridge", obs.bridge_orientation(Vector2i(25, 15)) == "vertical")

	fm._quad_mat = {}
	_fill_water(fm, Vector2i(25, 19))
	_fill_water(fm, Vector2i(25, 21)) # water above+below (25,20) => vertical river
	fm._rebuild()
	fm._place_bridge_at(Vector2(25 * 32 + 16, 20 * 32 + 16))
	_check("vertical river -> horizontal bridge", obs.bridge_orientation(Vector2i(25, 20)) == "horizontal")

	# --- passable-over-impassable: a bridge re-enables crossing on a water cell ---
	fm._quad_mat = {}
	var wcell := Vector2i(30, 15)
	_fill_water(fm, wcell)
	fm._rebuild()
	_check("full water cell is impassable", fm.is_cell_impassable(wcell))
	# the exact rule player.gd applies: a water cell blocks UNLESS a bridge covers it
	var blocks_before: bool = fm.is_cell_impassable(wcell) and not obs.is_bridge(wcell)
	_check("un-bridged water blocks the player", blocks_before)
	obs.add_bridge(wcell, "vertical")
	var blocks_after: bool = fm.is_cell_impassable(wcell) and not obs.is_bridge(wcell)
	_check("bridged water no longer blocks the player", not blocks_after)
	_check("player.floor_manager + obstacles wired", player.floor_manager == fm and player.obstacles == obs)

	# --- the deck node spawns (grouped "bridges") after a rebuild ---
	obs.apply_map([], [], []) # clean slate: free every prior bridge node
	await get_tree().process_frame
	await get_tree().process_frame # queue_free + the deferred add both need a frame to settle
	obs.apply_map([], [], [{"cell": Vector2i(30, 15), "orientation": "vertical"}])
	await get_tree().process_frame
	await get_tree().process_frame
	var node_count := get_tree().get_nodes_in_group("bridges").size()
	_check("a bridge deck node spawns in group 'bridges'", node_count == 1)

	# --- MapIO round-trips bridges (bridge_cells is now [30,15] from apply_map above) ---
	var data: Dictionary = MapIO.serialize()
	_check("serialize writes the current VERSION", int(data["version"]) == MapIO.VERSION)
	_check("serialize writes the bridges section", data.has("bridges") and data["bridges"].size() == 1)
	_check("serialized bridge keeps cell + orientation",
		data["bridges"][0]["cell"] == [30, 15] and data["bridges"][0]["orientation"] == "vertical")
	obs.bridge_cells.clear() # wipe (typed-array safe), then reload from the serialized dict
	MapIO.apply_serialized(data, true)
	await get_tree().process_frame
	_check("apply restores the bridge", obs.is_bridge(Vector2i(30, 15)))

	# --- erase removes a bridge (Erase tool path) before the water beneath it ---
	fm._quad_mat = {}
	var ecell := Vector2i(28, 12)
	_fill_water(fm, ecell) # bridge sits over water; erasing the bridge must leave the water intact
	fm._rebuild()
	obs.add_bridge(ecell, "vertical")
	fm.set_mode(4) # Mode.ERASE
	var erased: bool = fm._erase_structure_at(Vector2(ecell.x * 32 + 16, ecell.y * 32 + 16))
	_check("Erase tool removes the bridge", erased and not obs.is_bridge(ecell))
	_check("erasing the bridge leaves the water floor", fm.is_cell_impassable(ecell))
	_check("Erase over an empty (bridgeless) cell reports nothing", not fm._erase_structure_at(Vector2(2 * 32 + 16, 2 * 32 + 16)))

	# --- right-click Erase (single target) also removes a bridge ---
	obs.add_bridge(ecell, "vertical")
	fm._erase_single(ecell)
	await get_tree().process_frame
	_check("right-click Erase removes the bridge", not obs.is_bridge(ecell))

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
