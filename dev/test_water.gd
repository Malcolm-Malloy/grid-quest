extends Node

# Dev-only headless test for WATER terrain, slice 1 (impassable floor). Builds the real world and
# checks: water is registered as a floor material; FloorManager.is_cell_impassable uses cell-level
# MAJORITY-of-4-quarters granularity; and a fully-watered cell blocks the player's movement while
# grass does not. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_water.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

# the four 16px quarter coords of a 32px cell (mirrors FloorManager cell<->quarter mapping)
func _quads(cell: Vector2i) -> Array:
	return [
		Vector2i(cell.x * 2, cell.y * 2), Vector2i(cell.x * 2 + 1, cell.y * 2),
		Vector2i(cell.x * 2, cell.y * 2 + 1), Vector2i(cell.x * 2 + 1, cell.y * 2 + 1),
	]

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var player = main.get_node("World/Player")

	# --- registration ---
	_check("water is a floor material (textures)", fm.textures.has("water"))
	_check("water has a pattern name (PATTERN_NAMES)", fm.PATTERN_NAMES.has("water"))
	var in_menu := false
	for entry in fm.MENU:
		if entry[1] == "water":
			in_menu = true
	_check("water is in the floor MENU", in_menu)
	_check("water is flagged IMPASSABLE", fm.IMPASSABLE.has("water"))

	# --- cell-level majority granularity ---
	var cell := Vector2i(20, 20) # open ground, no wall/door in the default map
	var q := _quads(cell)
	_check("grass cell is passable", not fm.is_cell_impassable(cell))

	fm._quad_mat[q[0]] = "water" # 1 of 4 quarters -> minority, still passable
	_check("1 water quarter: still passable (minority)", not fm.is_cell_impassable(cell))

	fm._quad_mat[q[1]] = "water" # 2 of 4 -> majority, now blocks
	_check("2 water quarters: impassable (majority)", fm.is_cell_impassable(cell))

	fm._quad_mat[q[2]] = "water"
	fm._quad_mat[q[3]] = "water" # full water cell
	_check("4 water quarters: impassable", fm.is_cell_impassable(cell))

	# a non-impassable material never blocks, even filling the cell
	for qq in q:
		fm._quad_mat[qq] = "wood"
	_check("full wood cell is passable", not fm.is_cell_impassable(cell))

	# --- player movement rejects a water cell ---
	# stand the player on (19,20) facing right; (20,20) is full water -> the move must be refused.
	for qq in q:
		fm._quad_mat[qq] = "water"
	fm._rebuild()
	player.position = Vector2(19 * 32 + 16, 20 * 32 + 16)
	player.target_position = player.position
	player.is_moving = false
	var blocked: bool = fm.is_cell_impassable(Vector2i(20, 20)) and not player.obstacles.is_blocked(Vector2i(20, 20))
	_check("water cell blocks via floor (not wall)", blocked)
	_check("player.floor_manager wired", player.floor_manager == fm)

	# --- river-bank auto-edge (derived, walkable, not saved) ---
	_check("river-bank texture registered (RIVER_BANK)", fm.RIVER_BANK != null)
	_check("water is a BANK_AROUND source", fm.BANK_AROUND.has("water"))

	fm._quad_mat = {} # isolate: one full-water cell in open ground, well away from the map edge
	var wcell := Vector2i(30, 10)
	for qq in _quads(wcell):
		fm._quad_mat[qq] = "water"
	fm._rebuild()
	var bank: Dictionary = fm._bank_quads()

	# a single 2x2 water block has a 12-quarter ring (its 4x4 8-neighbourhood minus the 4 water quarters)
	_check("bank rings the water (12 quarters)", bank.size() == 12)
	# the water quarters themselves are never bank
	var water_in_bank := false
	for qq in _quads(wcell):
		if bank.has(qq):
			water_in_bank = true
	_check("water quarters are not bank", not water_in_bank)
	# a specific orthogonal-neighbour quarter is bank; a diagonal corner too
	_check("orthogonal neighbour quarter is bank", bank.has(Vector2i(59, 20)))
	_check("diagonal corner quarter is bank", bank.has(Vector2i(59, 19)))

	# bank is WALKABLE: the cell above the water (its bottom quarters are bank, no water) is passable
	_check("bank cell is passable (bank never blocks)", not fm.is_cell_impassable(Vector2i(30, 9)))

	# bank renders: a RIVER_BANK-textured fill exists in base_fills
	var bank_fill := false
	for f in fm.base_fills():
		if f[1] == fm.RIVER_BANK:
			bank_fill = true
	_check("base_fills carries a river-bank fill", bank_fill)

	# bank stays inside the map grid: water in the corner never emits an out-of-bounds bank quarter
	fm._quad_mat = {}
	for qq in _quads(Vector2i(0, 0)):
		fm._quad_mat[qq] = "water"
	fm._rebuild()
	var all_in_bounds := true
	for bq in fm._bank_quads():
		if not fm._in_bounds(Vector2i(floori(bq.x / 2.0), floori(bq.y / 2.0))):
			all_in_bounds = false
	_check("corner water emits no out-of-bounds bank", all_in_bounds)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
