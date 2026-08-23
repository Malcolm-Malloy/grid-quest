extends Node

# Dev-only headless test for GRASS PATTERNS (ROADMAP item 7): grass is now a real, patternable floor
# material ("grass") with variants Plain/Wild/Tuft. Plain draws NOTHING so the base ground shows through
# (no patch seam); Wild/Tuft are alpha blade overlays over the base. Rides the existing _quad_mat /
# _quad_pattern save (no MapIO bump). Checks registration, the render branch, and that grass stays a
# passable base terrain. Text-only.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_grass_pattern.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _rect(q: Vector2i) -> Rect2:
	return Rect2(q.x * 16, q.y * 16, 16, 16)

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")

	# --- registration ---
	_check("grass is a material with 3 variants", fm.textures.has("grass") and fm.textures["grass"].size() == 3)
	_check("grass pattern names are Plain/Wild/Tuft", fm.PATTERN_NAMES.get("grass", []) == ["Plain", "Wild", "Tuft"])
	var grass_val := ""
	for e in fm.MENU:
		if e[0] == "Grass":
			grass_val = e[1]
	_check("the Grass menu entry now arms the 'grass' material", grass_val == "grass")
	_check("grass is a passable base terrain (rank 0, not impassable)",
		fm.TERRAIN_RANK.get("grass", -1) == 0 and not fm.IMPASSABLE.has("grass"))
	_check("grass does NOT auto-match (no edge atlas; it is the base)", not fm.EDGE_ATLAS.has("grass"))

	# --- render branch: Plain untinted = nothing; Plain tinted = tinted base; Wild = overlay ---
	fm._quad_mat = {}
	fm._quad_tint = {}
	fm._quad_pattern = {}
	var q_plain := Vector2i(40, 40)
	var q_tint := Vector2i(42, 40)
	var q_wild := Vector2i(44, 40)
	fm._quad_mat[q_plain] = "grass"                       # Plain, untinted
	fm._quad_mat[q_tint] = "grass"; fm._quad_tint[q_tint] = Color(0.5, 0.8, 0.4)  # Plain, tinted
	fm._quad_mat[q_wild] = "grass"; fm._quad_pattern[q_wild] = 1                   # Wild overlay
	fm._rebuild()

	var plain_drawn := false
	var tint_ok := false
	var wild_ok := false
	var wild_tex = fm._mat_tex("grass", 1)
	for f in fm.base_fills():
		if f[0] == _rect(q_plain):
			plain_drawn = true
		if f[0] == _rect(q_tint) and f[1] == fm.GRASS and f[2] == Color(0.5, 0.8, 0.4):
			tint_ok = true
		if f[0] == _rect(q_wild) and f[1] == wild_tex and f.size() > 3:
			wild_ok = true
	_check("Plain untinted grass emits NO fill (base ground shows through)", not plain_drawn)
	_check("Plain tinted grass draws the tinted base grass", tint_ok)
	_check("Wild grass draws the blade overlay (with a tiled src override)", wild_ok)

	# grass painted anywhere is walkable (base terrain)
	fm._quad_mat = {}
	for dx in 2:
		for dy in 2:
			fm._quad_mat[Vector2i(20 * 2 + dx, 20 * 2 + dy)] = "grass"
	_check("a grass cell is passable", not fm.is_cell_impassable(Vector2i(20, 20)))

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
