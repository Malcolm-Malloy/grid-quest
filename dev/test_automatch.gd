extends "res://dev/test_case.gd"

# Dev-only headless test for the generalised AUTO-MATCHING terrain edge system (item 8): outdoor natural
# terrains (grass/sand/snow) feather into lower-precedence neighbours via the shared edge autotile the
# water shoreline pioneered. Checks: sand/snow are registered PASSABLE materials; the precedence table
# and edge mask pick the right feather sides (over lower naturals, never toward water / peers / the void /
# indoor floors); the underlay reveals a non-base lower terrain (sand under snow); and _rebuild emits a
# shore tile per edge quarter over the correct underlay while interior quarters stay flat. Text-only.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_automatch.tscn

func _quads(cell: Vector2i) -> Array:
	return [
		Vector2i(cell.x * 2, cell.y * 2), Vector2i(cell.x * 2 + 1, cell.y * 2),
		Vector2i(cell.x * 2, cell.y * 2 + 1), Vector2i(cell.x * 2 + 1, cell.y * 2 + 1),
	]

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")

	# --- registration (sand + snow are passable outdoor naturals) ---
	_check("sand registered (textures)", fm.textures.has("sand"))
	_check("snow registered (textures)", fm.textures.has("snow"))
	var menu_has := {"sand": false, "snow": false}
	for entry in fm.MENU:
		if menu_has.has(entry[1]):
			menu_has[entry[1]] = true
	_check("sand + snow in the floor MENU", menu_has["sand"] and menu_has["snow"])
	_check("sand is NOT impassable", not fm.IMPASSABLE.has("sand"))
	_check("snow is NOT impassable", not fm.IMPASSABLE.has("snow"))
	_check("sand + snow have an edge atlas", fm.EDGE_ATLAS.has("sand") and fm.EDGE_ATLAS.has("snow"))

	# --- precedence table (grass 0 < sand 1 < snow 2 < water 99) ---
	_check("precedence grass < sand < snow < water",
		fm.TERRAIN_RANK[""] < fm.TERRAIN_RANK["sand"]
		and fm.TERRAIN_RANK["sand"] < fm.TERRAIN_RANK["snow"]
		and fm.TERRAIN_RANK["snow"] < fm.TERRAIN_RANK["water"])
	_check("indoor materials are NOT in the precedence table",
		not fm.TERRAIN_RANK.has("wood") and not fm.TERRAIN_RANK.has("tile"))

	# --- edge mask: a 2x2-cell sand block on grass = 4x4 quarters (60..63, 20..23) ---
	fm._quad_mat = {}
	for cy in [10, 11]:
		for cx in [30, 31]:
			for qq in _quads(Vector2i(cx, cy)):
				fm._quad_mat[qq] = "sand"
	fm._rebuild()
	_check("sand NW-corner quarter feathers N|W (mask 9)", fm._terrain_edge_mask(Vector2i(60, 20), "sand") == 9)
	_check("sand interior quarter feathers nothing (mask 0)", fm._terrain_edge_mask(Vector2i(61, 21), "sand") == 0)
	_check("sand over grass needs no underlay (grass is the base)", fm._edge_underlay_mat(Vector2i(60, 20), "sand") == "")
	_check("sand cell is passable", not fm.is_cell_impassable(Vector2i(30, 10)))
	# _rebuild emits a shore tile for each of the 12 edge quarters; the 4 interior quarters stay flat
	var sand_shore := 0
	var interior_flat := false
	var flat_sand = fm._mat_tex("sand", 0)
	for f in fm.base_fills():
		if f[1] == fm.EDGE_ATLAS["sand"]:
			sand_shore += 1
		if f[0] == Rect2(61 * 16, 21 * 16, 16, 16) and f[1] == flat_sand and f.size() == 3:
			interior_flat = true
	_check("12 sand edge quarters draw a shore tile", sand_shore == 12)
	_check("interior sand quarter stays flat (no autotile)", interior_flat)

	# --- sand never feathers toward WATER (water outranks it) ---
	fm._quad_mat = {}
	fm._quad_mat[Vector2i(60, 20)] = "sand"
	fm._quad_mat[Vector2i(61, 20)] = "water" # east neighbour is water
	fm._rebuild()
	var sm = fm._terrain_edge_mask(Vector2i(60, 20), "sand")
	_check("sand feathers over grass N/S/W but NOT toward water (E bit clear)", (sm & 2) == 0 and (sm & 1) != 0)

	# --- snow feathers over sand and reveals it via an underlay ---
	fm._quad_mat = {}
	fm._quad_mat[Vector2i(60, 20)] = "snow"
	fm._quad_mat[Vector2i(61, 20)] = "sand" # east neighbour is lower (sand); the rest are grass base
	fm._rebuild()
	_check("snow feathers on every side over sand+grass (mask 15)", fm._terrain_edge_mask(Vector2i(60, 20), "snow") == 15)
	_check("snow-over-sand underlay is sand (reveals it, not grass)", fm._edge_underlay_mat(Vector2i(60, 20), "snow") == "sand")
	# a snow quarter bordered only by grass needs no underlay
	fm._quad_mat = {}
	fm._quad_mat[Vector2i(60, 20)] = "snow"
	fm._rebuild()
	_check("snow over grass only needs no underlay", fm._edge_underlay_mat(Vector2i(60, 20), "snow") == "")
	# sand does NOT feather over snow (snow outranks sand): reverse of the pair above
	fm._quad_mat = {}
	fm._quad_mat[Vector2i(60, 20)] = "sand"
	fm._quad_mat[Vector2i(61, 20)] = "snow"
	_check("sand does not feather toward higher snow (E bit clear)", (fm._terrain_edge_mask(Vector2i(60, 20), "sand") & 2) == 0)

	# --- the snow-over-sand emission lays a sand underlay BEFORE the snow shore tile at that quarter ---
	fm._quad_mat = {}
	fm._quad_mat[Vector2i(60, 20)] = "snow"
	fm._quad_mat[Vector2i(61, 20)] = "sand"
	fm._rebuild()
	var rect := Rect2(60 * 16, 20 * 16, 16, 16)
	var under_idx := -1
	var snow_idx := -1
	var fills: Array = fm.base_fills()
	for i in fills.size():
		var f = fills[i]
		if f[0] == rect and f[1] == flat_sand and under_idx == -1:
			under_idx = i
		if f[0] == rect and f[1] == fm.EDGE_ATLAS["snow"]:
			snow_idx = i
	_check("snow edge lays a sand underlay then the snow shore tile (underlay first)",
		under_idx != -1 and snow_idx != -1 and under_idx < snow_idx)

	finish()
