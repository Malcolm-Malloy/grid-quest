extends "res://dev/test_case.gd"

# Dev-only headless test for GRASS PATTERNS (ROADMAP item 7): grass is now a real, patternable floor
# material ("grass") with variants Plain/Wild/Tuft. Plain draws NOTHING so the base ground shows through
# (no patch seam); Wild/Tuft are alpha blade overlays over the base. Rides the existing _quad_mat /
# _quad_pattern save (no MapIO bump). Checks registration, the render branch, and that grass stays a
# passable base terrain. Text-only.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_grass_pattern.tscn

func _rect(q: Vector2i) -> Rect2:
	return Rect2(q.x * 16, q.y * 16, 16, 16)

func _ready() -> void:
	var main: Node = await boot_main()
	var fm = main.get_node("World/FloorManager")

	# --- registration ---
	_check("grass is a material with 3 variants", FloorMaterials.TEXTURES.has("grass") and FloorMaterials.TEXTURES["grass"].size() == 3)
	_check("grass pattern names are Plain/Wild/Tuft", FloorMaterials.PATTERN_NAMES.get("grass", []) == ["Plain", "Wild", "Tuft"])
	var grass_val := ""
	for e in FloorMaterials.MATERIAL_NAMES:
		if e[0] == "Grass":
			grass_val = e[1]
	_check("the Grass menu entry now arms the 'grass' material", grass_val == "grass")
	_check("grass is a passable base terrain (rank 0, not impassable)",
		FloorMaterials.TERRAIN_RANK.get("grass", -1) == 0 and not FloorMaterials.IMPASSABLE.has("grass"))
	_check("grass does NOT auto-match (no edge atlas; it is the base)", not FloorMaterials.EDGE_ATLAS.has("grass"))

	# --- render branch: Plain untinted = nothing; Plain tinted = tinted base; Wild = overlay ---
	fm.clear_floor()
	var q_plain := Vector2i(40, 40)
	var q_tint := Vector2i(42, 40)
	var q_wild := Vector2i(44, 40)
	fm.write_quad(q_plain, "grass")                       # Plain, untinted
	fm.write_quad(q_tint, "grass"); fm.write_tint(q_tint, Color(0.5, 0.8, 0.4))  # Plain, tinted
	fm.write_quad(q_wild, "grass"); fm.write_pattern(q_wild, 1)                   # Wild overlay
	fm.rebuild()

	var plain_drawn := false
	var tint_ok := false
	var wild_ok := false
	var wild_tex = FloorMaterials.texture("grass", 1)
	for f in fm.base_fills():
		if f[0] == _rect(q_plain):
			plain_drawn = true
		if f[0] == _rect(q_tint) and f[1] == FloorMaterials.GRASS and f[2] == Color(0.5, 0.8, 0.4):
			tint_ok = true
		if f[0] == _rect(q_wild) and f[1] == wild_tex and f.size() > 3:
			wild_ok = true
	_check("Plain untinted grass emits NO fill (base ground shows through)", not plain_drawn)
	_check("Plain tinted grass draws the tinted base grass", tint_ok)
	_check("Wild grass draws the blade overlay (with a tiled src override)", wild_ok)

	# grass painted anywhere is walkable (base terrain)
	fm.clear_floor()
	for dx in 2:
		for dy in 2:
			fm.write_quad(Vector2i(20 * 2 + dx, 20 * 2 + dy), "grass")
	_check("a grass cell is passable", not fm.is_cell_impassable(Vector2i(20, 20)))

	finish()
