extends Node

# Dev-only headless test for LAVA + the river-bank switch. Lava is a second impassable "liquid" that works
# like water (shoreline, shimmer, bank) but is its OWN material, so wooden bridges cannot be built over it.
# The river bank is now a per-body switch set before laying a liquid. Checks: registration/impassable/
# shoreline for lava; bridges refuse lava but allow water; the bank switch suppresses the bank and
# round-trips through MapIO v9. Text-only.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_lava.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _fill(fm, cell: Vector2i, mat: String) -> void:
	for dx in 2:
		for dy in 2:
			fm._write_quad(Vector2i(cell.x * 2 + dx, cell.y * 2 + dy), mat)

func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _bank_count(fm) -> int:
	var n := 0
	for f in fm.base_fills():
		if f[1] == fm.RIVER_BANK:
			n += 1
	return n

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	EditHistory.reset()

	# --- registration ---
	_check("lava is a floor material", fm.textures.has("lava"))
	var in_menu := false
	for e in fm.MENU:
		if e[1] == "lava":
			in_menu = true
	_check("lava is in the MENU", in_menu)
	_check("lava is IMPASSABLE", fm.IMPASSABLE.has("lava"))
	_check("lava grows a bank (BANK_AROUND)", fm.BANK_AROUND.has("lava"))
	_check("lava has a shore atlas (LIQUID_SHORE)", fm.LIQUID_SHORE.has("lava"))
	_check("lava is top-rank terrain (never auto-matched over)", fm.TERRAIN_RANK.get("lava", 0) == 99)

	# --- lava blocks + shorelines like water ---
	fm._quad_mat = {}
	fm._quad_no_bank = {}
	_fill(fm, Vector2i(30, 10), "lava")
	fm._rebuild()
	_check("a full lava cell is impassable", fm.is_cell_impassable(Vector2i(30, 10)))
	# a lava quarter touching land feathers (edge mask != 0) and renders the lava shore atlas
	var qedge := Vector2i(60, 20)
	_check("lava edge quarter feathers toward land", fm._liquid_edge_mask(qedge, "lava") != 0)
	var lava_shore := false
	for f in fm.base_fills():
		if f[1] == fm.LIQUID_SHORE["lava"]:
			lava_shore = true
	_check("base_fills carries a lava shore tile", lava_shore)

	# --- bridges: refuse lava, allow water ---
	fm._quad_mat = {}
	_fill(fm, Vector2i(30, 10), "lava")
	_fill(fm, Vector2i(25, 10), "water")
	fm._rebuild()
	_check("_cell_liquid reads lava", fm._cell_liquid(Vector2i(30, 10)) == "lava")
	_check("_cell_liquid reads water", fm._cell_liquid(Vector2i(25, 10)) == "water")
	fm.set_mode(8) # Mode.BRIDGE
	fm._place_bridge_at(_center(Vector2i(30, 10)))
	_check("no bridge is built over lava", not obs.is_bridge(Vector2i(30, 10)))
	fm._place_bridge_at(_center(Vector2i(25, 10)))
	_check("a bridge IS built over water", obs.is_bridge(Vector2i(25, 10)))
	# lava is not counted as a river for bridge orientation
	fm._quad_mat = {}
	_fill(fm, Vector2i(41, 10), "lava")
	_fill(fm, Vector2i(43, 10), "lava") # lava left+right of (42,10)
	fm._rebuild()
	_check("lava does not orient a bridge (treated as no river)", fm._bridge_river_orientation(Vector2i(42, 10)) == "")

	# --- river-bank switch: OFF suppresses the bank, ON keeps it ---
	fm._quad_mat = {}
	fm._quad_no_bank = {}
	fm.set_bank_on(false)
	_fill(fm, Vector2i(35, 10), "water") # water laid with the switch OFF
	fm._rebuild()
	_check("bank-off water records _quad_no_bank", fm._quad_no_bank.size() == 4)
	_check("bank-off water draws NO river bank", _bank_count(fm) == 0)

	fm._quad_mat = {}
	fm._quad_no_bank = {}
	fm.set_bank_on(true)
	_fill(fm, Vector2i(35, 10), "water") # water laid with the switch ON
	fm._rebuild()
	_check("bank-on water records no suppression", fm._quad_no_bank.is_empty())
	_check("bank-on water draws a river bank ring", _bank_count(fm) > 0)

	# --- MapIO v9 round-trips the no-bank flags ---
	fm.set_bank_on(false)
	_fill(fm, Vector2i(38, 12), "lava")
	fm._rebuild()
	var data: Dictionary = MapIO.serialize()
	# the save VERSION has moved on since lava landed (v10 = sparse absent_cells); lava only needs
	# it to be at least the version that introduced the river-bank flags it writes
	_check("serialize writes at least VERSION 9 (lava's river-bank flags)", int(data["version"]) >= 9)
	_check("serialize writes floor_no_bank", data.has("floor_no_bank") and data["floor_no_bank"].size() == 4)
	fm._quad_no_bank = {}
	MapIO.apply_serialized(data, true)
	await get_tree().process_frame
	_check("apply restores the no-bank flags", fm._quad_no_bank.size() == 4)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
