extends Node

# Dev-only headless test for WATER terrain. Builds the real world and checks: water is registered as a
# floor material; FloorManager.is_cell_impassable uses cell-level MAJORITY-of-4-quarters granularity; a
# fully-watered cell blocks the player's movement while grass does not; the river-bank auto-edge rings
# every body; and the SHORELINE AUTOTILE picks a feathered variant per 4-neighbour land mask (edge
# quarters draw a shore tile over a bank underlay, interior stays flat) without affecting collision.
# Text-only, no rendering.
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

	# --- shoreline autotile (feathered beach): a 2x2-cell water block = 4x4 quarters (60..63, 20..23) ---
	_check("shore atlas registered (WATER_SHORE)", fm.WATER_SHORE != null)
	fm._quad_mat = {}
	for cy in [10, 11]:
		for cx in [30, 31]:
			for qq in _quads(Vector2i(cx, cy)):
				fm._quad_mat[qq] = "water"
	fm._rebuild()
	# neighbour LAND mask (N=1 E=2 S=4 W=8): the NW-corner quarter faces land N+W; a top-edge quarter
	# faces land only N; a fully-surrounded interior quarter faces no land (mask 0 -> flat tiled tile).
	_check("NW-corner water quarter mask = N|W (9)", fm._water_land_mask(Vector2i(60, 20)) == 9)
	_check("top-edge water quarter mask = N (1)", fm._water_land_mask(Vector2i(61, 20)) == 1)
	_check("interior water quarter mask = 0 (open water)", fm._water_land_mask(Vector2i(61, 21)) == 0)
	# atlas src rect for a mask indexes the 4x4 grid of 32px cells (m%4 across, m/4 down)
	_check("shore src for mask 9 = cell (1,2)", fm._shore_src(9) == Rect2(32, 64, 32, 32))
	# _rebuild emits, for the 12 edge quarters, a feathered shore tile (atlas src override) over a bank
	# underlay; the 4 interior quarters keep the flat, seamless, world-tiled water tile (no shore).
	var shore_fills := 0
	var interior_flat := false
	var corner_has_shore := false
	var corner_has_underlay := false
	var flat = fm._mat_tex("water", 0)
	var corner_rect := Rect2(60 * 16, 20 * 16, 16, 16)
	var interior_rect := Rect2(61 * 16, 21 * 16, 16, 16)
	for f in fm.base_fills():
		if f[1] == fm.WATER_SHORE:
			shore_fills += 1
			if f[0] == corner_rect:
				corner_has_shore = true
		if f[0] == corner_rect and f[1] == fm.RIVER_BANK:
			corner_has_underlay = true
		# interior uses the flat still tile, not the shore atlas (it now also carries a tiled-src + animate
		# flag for the shimmer, so it is no longer a bare 3-element fill).
		if f[0] == interior_rect and f[1] == flat:
			interior_flat = true
	_check("12 edge quarters draw a shore tile", shore_fills == 12)
	_check("interior quarter keeps the flat water tile", interior_flat)
	_check("corner quarter draws a shore tile", corner_has_shore)
	_check("corner shore has a bank underlay beneath it", corner_has_underlay)
	# shoreline is purely visual: the fully-watered edge cell still blocks the player
	_check("shored water cell is still impassable", fm.is_cell_impassable(Vector2i(30, 10)))

	# --- water shimmer plumbing (grid_background animates flagged water fills; dry maps cost nothing) ---
	fm._quad_mat = {}
	fm._rebuild()
	_check("dry map reports no animated water", not fm.has_animated_water())
	# a full-water cell plus a wood cell: water fills carry the animate flag (5th element), wood does not
	for qq in _quads(Vector2i(30, 10)):
		fm._quad_mat[qq] = "water"
	for qq in _quads(Vector2i(33, 10)):
		fm._quad_mat[qq] = "wood"
	fm._rebuild()
	_check("map with water reports animated water", fm.has_animated_water())
	var water_animated := false
	var wood_animated := false
	var wood_tex = fm._mat_tex("wood", 0)
	for f in fm.base_fills():
		var is_anim: bool = f.size() > 4 and f[4]
		if is_anim and (f[1] == fm.WATER_SHORE or f[1] == fm._mat_tex("water", 0)):
			water_animated = true
		if f[1] == wood_tex and is_anim:
			wood_animated = true
	_check("water fills are flagged animated", water_animated)
	_check("non-water (wood) fills are NOT animated", not wood_animated)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
