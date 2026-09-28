extends "res://dev/test_case.gd"

# Dev-only headless test for MapEdit grow/shrink (the _shift transform). Seeds EVERY map layer near the
# left edge, then checks a grow moves each record by exactly one cell with all its fields intact, and that
# shrinking past it drops cell records and clips the spawn zone. Asserts on the serialized shape only, so
# it stays valid however _shift is implemented. Also covers MapSizeTool.edge_at (pure geometry).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_resize.tscn
# (For an eyeball check of arbitrary resizes, dev/capture.gd still takes GQ_RESIZE="grow:left;...".)

const CELL_LAYERS := ["walls", "wall_colors", "wall_materials", "absent_cells"]
const QUAD_LAYERS := ["quads", "floor_tints", "floor_patterns", "floor_no_bank"]
const REC_LAYERS := ["doors", "bridges", "pickups", "creatures"]

func _ready() -> void:
	var main: Node = await boot_main()
	var d := MapIO.serialize()
	d["walls"] = [[1, 2], [1, 3]]
	d["wall_colors"] = [[1, 2, 0.85, 0.3, 0.28]]
	d["wall_materials"] = [[1, 3, "wood"]]
	d["absent_cells"] = [[1, 20]]
	d["doors"] = [{"cell": [1, 4], "orientation": "vertical", "open": true, "swing": true, "id": "door0001",
		"lock": "unique", "lock_color": "red", "lock_name": "Vault"}]
	d["bridges"] = [{"cell": [1, 8], "orientation": "horizontal"}]
	d["quads"] = [[2, 12, "wood"], [3, 12, "wood"], [2, 16, "water"], [3, 16, "water"]]
	d["floor_tints"] = [[2, 12, 0.5, 0.25, 1.0]]
	d["floor_patterns"] = [[3, 12, 1]]
	d["floor_no_bank"] = [[2, 16]]
	d["pickups"] = [{"cell": [1, 10], "item": "key", "id": "pick0001", "data": {"door_id": "door0001", "name": "Vault"}}]
	d["creatures"] = [{"cell": [1, 11], "creature": "frost_frog", "kind": Bestiary.INSTANCE, "id": "crea0001", "blocks": false}]
	d["creature_zones"] = [{"rect": [1, 14, 4, 3], "creature": "frost_frog", "rate": 7.5, "cap": 5, "id": "zone0001"}]
	d["spawn"] = {"x": 5 * 32 + 16.0, "y": 5 * 32 + 16.0}
	MapIO.apply_serialized(d)
	var s0 := MapIO.serialize()
	for layer in CELL_LAYERS + QUAD_LAYERS + REC_LAYERS + ["creature_zones"]:
		_check("seeded %s round-trips" % layer, (s0[layer] as Array).size() == (d[layer] as Array).size())

	# --- grow left: everything moves one cell right, every field intact ---
	var w0 := int(s0["grid"]["width"])
	MapEdit.grow("left")
	var s1 := MapIO.serialize()
	_check("grow left widens by one", int(s1["grid"]["width"]) == w0 + 1)
	for layer in CELL_LAYERS:
		_check("grow shifts %s" % layer, _canon(s1[layer]) == _canon(_shift_rows(s0[layer], 1)))
	for layer in QUAD_LAYERS:
		_check("grow shifts %s" % layer, _canon(s1[layer]) == _canon(_shift_rows(s0[layer], 2)))
	for layer in REC_LAYERS:
		_check("grow shifts %s (all fields kept)" % layer, _canon(s1[layer]) == _canon(_shift_recs(s0[layer], 1)))
	_check("grow shifts creature_zones", _canon(s1["creature_zones"]) == _canon(_shift_zones(s0["creature_zones"], 1)))
	_check("grow shifts the spawn", is_equal_approx(float(s1["spawn"]["x"]), float(s0["spawn"]["x"]) + 32.0))

	# --- shrink left x3: the seeded column (now x=2) falls off; the zone (x 2..5) clips to x 0..2 ---
	for i in 3:
		MapEdit.shrink("left")
	var s2 := MapIO.serialize()
	_check("shrink x3 narrows by three", int(s2["grid"]["width"]) == w0 - 2)
	for layer in CELL_LAYERS + QUAD_LAYERS + REC_LAYERS:
		_check("shrink drops %s off the edge" % layer, (s2[layer] as Array).is_empty())
	var zs: Array = s2["creature_zones"]
	_check("shrink clips the zone", zs.size() == 1 and _ints(zs[0]["rect"]) == [0, 14, 3, 3])
	_check("clipped zone keeps its rule", zs.size() == 1 and is_equal_approx(float(zs[0]["rate"]), 7.5) \
		and int(zs[0]["cap"]) == 5 and zs[0]["id"] == "zone0001")

	# --- MapSizeTool.edge_at on a 48x32 grid (BAND = 32px into the void) ---
	var t = load("res://world/map_size_tool.gd").new()
	_check("edge_at above the map = top", t.edge_at(Vector2(100, -16), 48, 32) == "top")
	_check("edge_at inside the map = none", t.edge_at(Vector2(100, 16), 48, 32) == "")
	_check("edge_at left of the map = left", t.edge_at(Vector2(-16, 100), 48, 32) == "left")
	_check("edge_at right of the map = right", t.edge_at(Vector2(1550, 100), 48, 32) == "right")
	_check("edge_at a diagonal corner = none", t.edge_at(Vector2(-16, -16), 48, 32) == "")
	t.free()
	finish()

# --- expected-value builders: shift by n (cells) along x, in each layer's own shape ---

func _shift_rows(rows: Array, n: int) -> Array:
	var out: Array = []
	for a in rows:
		var r: Array = a.duplicate()
		r[0] = int(r[0]) + n
		out.append(r)
	return out

func _shift_recs(recs: Array, n: int) -> Array:
	var out: Array = []
	for r in recs:
		var c: Dictionary = r.duplicate(true)
		c["cell"] = [int(r["cell"][0]) + n, int(r["cell"][1])]
		out.append(c)
	return out

func _shift_zones(zones: Array, n: int) -> Array:
	var out: Array = []
	for z in zones:
		var c: Dictionary = z.duplicate(true)
		var a := _ints(z["rect"])
		c["rect"] = [a[0] + n, a[1], a[2], a[3]]
		out.append(c)
	return out

func _ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out

# order-free comparison: each record rendered to canonical JSON (ints normalised), sorted
func _canon(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(JSON.stringify(_norm(r), "", true))
	out.sort()
	return out

func _norm(v):
	if v is float and v == floorf(v):
		return int(v)
	if v is Array:
		var a: Array = []
		for e in v:
			a.append(_norm(e))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _norm(v[k])
		return d
	return v
