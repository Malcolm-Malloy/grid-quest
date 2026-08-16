extends Node

# MapEdit (autoload): editor geometry operations on the live map.
#
# Growing or shrinking the map at an edge is expressed as a pure transform on the
# MapIO.serialize() dict, which is then re-applied through MapIO's normal load path.
# One code path already moves every coordinate store in lockstep (walls, doors, wall
# colours, per-16px-quarter floors, the player spawn, and the grid size), so a resize
# can never leave one store behind, and the before/after dicts drop straight into the
# undo history later.
#
# Adding at the TOP or LEFT shifts the origin: every existing cell moves +1 along that
# axis so the new row/column can take index 0. Adding at the BOTTOM or RIGHT just
# extends the grid; nothing moves. A freshly added row/column copies the terrain of the
# neighbouring edge cells (terrain only, not walls or objects), so extending a grass
# field stays grass and a stone path stays stone (ROADMAP "New cell terrain: copy the
# adjacent edge cell"). Removing a row/column deletes whatever sat on it (paint, walls,
# doors) in the same single action (ROADMAP "delete its contents with it").
#
# SCOPE (2026-08-16): this is the ROW / COLUMN grain only. The single-cell grain in the
# roadmap needs a per-cell existence model first: the map is currently a solid rectangle
# (grid_width x grid_height, every cell present), so a lone jagged cell is not yet
# representable. Logged in ROADMAP under "Map extent and edge editing".
#
# INTERIM CONTROL: the real UX is the left tool strip plus the green add-highlight
# (roadmap, not built yet). Until then this answers to IJKL keys (Shift = grow that
# edge, Ctrl/Cmd = shrink that edge) so levels can be sized now, and to the capture
# harness GQ_RESIZE hook for headless verification.

const CELL := 32
const MIN_W := 1
const MIN_H := 1
const EDGES := ["top", "bottom", "left", "right"]

# --- public API ---

# grow the map by one row (top/bottom) or column (left/right); returns success
func grow(edge: String) -> bool:
	if not EDGES.has(edge):
		push_warning("MapEdit.grow: unknown edge '%s'" % edge)
		return false
	var d := MapIO.serialize()
	var w := int(d["grid"]["width"])
	var h := int(d["grid"]["height"])
	var dx := 0
	var dy := 0
	var nw := w
	var nh := h
	match edge:
		"top": dy = 1; nh = h + 1
		"bottom": nh = h + 1
		"left": dx = 1; nw = w + 1
		"right": nw = w + 1
	d = _shift(d, dx, dy, nw, nh)
	_copy_edge_terrain(d, edge)
	MapIO.apply_serialized(d)
	EditHistory.commit("grow %s" % edge) # one edge resize = one undo step
	print("MapEdit: grew %s -> %dx%d" % [edge, nw, nh])
	return true

# shrink the map by one edge row/column, deleting whatever sat on it; returns success
func shrink(edge: String) -> bool:
	if not EDGES.has(edge):
		push_warning("MapEdit.shrink: unknown edge '%s'" % edge)
		return false
	var d := MapIO.serialize()
	var w := int(d["grid"]["width"])
	var h := int(d["grid"]["height"])
	var horizontal := edge == "left" or edge == "right"
	if horizontal and w <= MIN_W:
		push_warning("MapEdit.shrink: map already at minimum width")
		return false
	if not horizontal and h <= MIN_H:
		push_warning("MapEdit.shrink: map already at minimum height")
		return false
	var dx := 0
	var dy := 0
	var nw := w
	var nh := h
	match edge:
		"top": dy = -1; nh = h - 1
		"bottom": nh = h - 1
		"left": dx = -1; nw = w - 1
		"right": nw = w - 1
	# _shift clips every store to the new bounds, so the removed band (and everything on
	# it) is dropped in the same pass that moves the survivors.
	d = _shift(d, dx, dy, nw, nh)
	MapIO.apply_serialized(d)
	EditHistory.commit("shrink %s" % edge) # one edge resize = one undo step
	print("MapEdit: shrank %s -> %dx%d" % [edge, nw, nh])
	return true

# --- transform: shift every store by (dx, dy) cells, resize to (nw, nh), clip out-of-range ---

func _shift(d: Dictionary, dx: int, dy: int, nw: int, nh: int) -> Dictionary:
	var out := {}
	out["version"] = d.get("version", 3)
	out["grid"] = {"width": nw, "height": nh}

	# spawn is in world pixels: shift with the world, then clamp into the new walkable
	# range so a player standing on a removed band lands on a valid cell instead of the void
	var sx := float(d["spawn"]["x"]) + dx * CELL
	var sy := float(d["spawn"]["y"]) + dy * CELL
	sx = clampf(sx, CELL / 2.0, (nw - 1) * CELL + CELL / 2.0)
	sy = clampf(sy, CELL / 2.0, (nh - 1) * CELL + CELL / 2.0)
	out["spawn"] = {"x": sx, "y": sy}

	var walls: Array = []
	for a in d.get("walls", []):
		var x := int(a[0]) + dx
		var y := int(a[1]) + dy
		if _in_cells(x, y, nw, nh):
			walls.append([x, y])
	out["walls"] = walls

	var doors: Array = []
	for dr in d.get("doors", []):
		var x := int(dr["cell"][0]) + dx
		var y := int(dr["cell"][1]) + dy
		if _in_cells(x, y, nw, nh):
			doors.append({"cell": [x, y], "orientation": dr["orientation"]})
	out["doors"] = doors

	# floors are on the 16px quarter grid, so a cell shift is a two-quarter shift
	var quads: Array = []
	for a in d.get("quads", []):
		var qx := int(a[0]) + dx * 2
		var qy := int(a[1]) + dy * 2
		if qx >= 0 and qy >= 0 and qx < nw * 2 and qy < nh * 2:
			quads.append([qx, qy, a[2]])
	out["quads"] = quads

	var wcols: Array = []
	for a in d.get("wall_colors", []):
		var x := int(a[0]) + dx
		var y := int(a[1]) + dy
		if _in_cells(x, y, nw, nh):
			wcols.append([x, y, a[2], a[3], a[4]])
	out["wall_colors"] = wcols

	return out

func _in_cells(x: int, y: int, nw: int, nh: int) -> bool:
	return x >= 0 and y >= 0 and x < nw and y < nh

# --- copy-neighbour terrain into a freshly grown row/column (quarter grid) ---

# The new band has no floor quarters yet (it was just created). For each quarter in the
# band, copy the material of the corresponding quarter one cell inward (delta is +/-2 on
# the quarter grid = one cell). Unpainted neighbours (grass base) copy nothing, which is
# correct: grass is the absence of a quarter, so the new band simply stays grass.
func _copy_edge_terrain(d: Dictionary, edge: String) -> void:
	var nw := int(d["grid"]["width"])
	var nh := int(d["grid"]["height"])
	var have := {}
	for a in d["quads"]:
		have[Vector2i(int(a[0]), int(a[1]))] = a[2]
	var added: Array = []
	match edge:
		"top":
			for qx in range(nw * 2):
				for qy in [0, 1]:
					_copy_quad(have, added, Vector2i(qx, qy), Vector2i(0, 2))
		"bottom":
			var base := (nh - 1) * 2
			for qx in range(nw * 2):
				for qy in [base, base + 1]:
					_copy_quad(have, added, Vector2i(qx, qy), Vector2i(0, -2))
		"left":
			for qy in range(nh * 2):
				for qx in [0, 1]:
					_copy_quad(have, added, Vector2i(qx, qy), Vector2i(2, 0))
		"right":
			var base2 := (nw - 1) * 2
			for qy in range(nh * 2):
				for qx in [base2, base2 + 1]:
					_copy_quad(have, added, Vector2i(qx, qy), Vector2i(-2, 0))
	for q in added:
		d["quads"].append(q)

func _copy_quad(have: Dictionary, added: Array, pos: Vector2i, delta: Vector2i) -> void:
	var src: Vector2i = pos + delta
	if have.has(src):
		added.append([pos.x, pos.y, have[src]])

# --- interim keyboard control (scaffolding until the tool strip lands) ---

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var edge := ""
	match event.keycode:
		KEY_I: edge = "top"
		KEY_K: edge = "bottom"
		KEY_J: edge = "left"
		KEY_L: edge = "right"
		_: return
	if event.shift_pressed:
		grow(edge)
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed or event.meta_pressed:
		shrink(edge)
		get_viewport().set_input_as_handled()
