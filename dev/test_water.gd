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

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
