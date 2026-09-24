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

const CELL := Grid.CELL
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

# --- single-cell edge editing (jagged / non-square maps, the cell-existence model) ---
# These enable NON-SQUARE maps: instead of whole-row/column grow/shrink, add or remove ONE perimeter
# cell. The map stays a bounding box (grid_width x grid_height) minus a sparse `absent_cells` set of
# holes (see GridBackground). Both ops are pure transforms on the serialized dict re-applied through
# MapIO, so they undo/redo and persist like every other edit.

# add one cell at the map edge; returns success. A single add is ITS OWN undo entry. For a DRAG that
# lays several cells, the tool calls add_cell_applied() per cell and commits once (see below).
func add_cell(cell: Vector2i) -> bool:
	if add_cell_applied(cell):
		EditHistory.commit("add cell")
		return true
	return false

# add one cell and apply it to the live map, but do NOT commit an undo entry (so a drag can add many
# cells and commit ONCE on release, matching the paint-stroke "one gesture = one undo entry" rule).
# Returns whether the map actually changed. Two cases:
#  - a HOLE inside the box (an absent cell): fill it back in.
#  - a cell one step BEYOND exactly one edge: grow the box to include it, leaving the REST of the new
#    row/column absent, so only this one cell is added (a spur). This is what makes maps non-square.
# The new cell copies the terrain of its inward neighbour, matching the row/column grow behaviour.
func add_cell_applied(cell: Vector2i) -> bool:
	var d := MapIO.serialize()
	var w := int(d["grid"]["width"])
	var h := int(d["grid"]["height"])
	# case 1: an existing hole inside the box -> just un-absent it
	if cell.x >= 0 and cell.x < w and cell.y >= 0 and cell.y < h:
		var absent_in := _absent_set(d)
		if not absent_in.has(cell):
			return false # already present, nothing to add
		absent_in.erase(cell)
		d["absent_cells"] = _absent_list(absent_in)
		var src := _copy_source(absent_in, cell, w, h)
		if src != _NONE:
			_copy_cell_terrain(d, cell, src)
		MapIO.apply_serialized(d)
		return true
	# case 2: one step beyond exactly one edge -> grow the box, keep only this cell present
	var edge := _beyond_edge(cell, w, h)
	if edge == "":
		return false # not an addable perimeter cell (too far out, or a diagonal corner)
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
	var target := Vector2i(cell.x + dx, cell.y + dy) # target in the new (possibly shifted) coords
	var absent_out := _absent_set(d)
	# mark the whole fresh row/column absent, then carve out the one added cell
	if edge == "left" or edge == "right":
		var col := 0 if edge == "left" else nw - 1
		for j in range(nh):
			absent_out[Vector2i(col, j)] = true
	else:
		var row := 0 if edge == "top" else nh - 1
		for i in range(nw):
			absent_out[Vector2i(i, row)] = true
	absent_out.erase(target)
	d["absent_cells"] = _absent_list(absent_out)
	var src2 := _copy_source(absent_out, target, nw, nh)
	if src2 != _NONE:
		_copy_cell_terrain(d, target, src2)
	MapIO.apply_serialized(d)
	return true

# remove one present cell, deleting whatever sat on it (paint, walls, doors, objects) in the same
# action, so Ctrl+Z restores the cell and its contents together. Marks the cell absent (a hole);
# returns success. Never removes the last remaining cell.
func remove_cell(cell: Vector2i) -> bool:
	var d := MapIO.serialize()
	var w := int(d["grid"]["width"])
	var h := int(d["grid"]["height"])
	var absent := _absent_set(d)
	var in_box := cell.x >= 0 and cell.x < w and cell.y >= 0 and cell.y < h
	if not in_box or absent.has(cell):
		return false # not a present cell
	if (w * h) - absent.size() <= 1:
		return false # would empty the map
	absent[cell] = true
	d["absent_cells"] = _absent_list(absent)
	_strip_cells(d, {cell: true}) # delete walls/doors/floors/objects sitting on the removed cell
	_relocate_spawn_if_on(d, cell, absent, w, h) # keep the player off the new hole
	MapIO.apply_serialized(d)
	EditHistory.commit("remove cell")
	print("MapEdit: removed cell %s (hole)" % cell)
	return true

# --- clip stamping: paste and move a copied REGION (ROADMAP "Copy, paste, and duplicate", "Move tool") ---
# Both are pure transforms on the serialized dict, re-applied through MapIO exactly like every other
# edit here, so a stamp rebuilds walls/lighting/shadows/floors together and lands as ONE undo entry.
# See MapClipboard for the clip format and the rotate/flip orientation remap.

# paste `clip` with its bounding box's top-left at `origin`. Target cells off the map (or on an
# absent-cell hole) are CLIPPED; the rest still land. Returns the cells actually stamped ({} = nothing
# landed, e.g. the whole clip fell outside the map, in which case nothing is committed).
func stamp_clip(clip: Dictionary, origin: Vector2i, label := "paste") -> Dictionary:
	if clip.is_empty():
		return {}
	var d := MapIO.serialize()
	var stamped := _apply_clip(d, clip, origin, true) # a PASTE is a new instance: mint fresh ids
	if stamped.is_empty():
		return {}
	MapIO.apply_serialized(d, true) # keep_player: a paste must never teleport the character
	EditHistory.commit(label)
	return stamped

# move a region: clear `src_cells`, then stamp `clip` (built from those cells, optionally rotated or
# flipped) at `origin`. One dict, one re-apply, ONE undo entry, so the region never flickers through a
# half-moved state. Each record is carried across verbatim, so a moved door keeps its authored state
# (and, once objects carry durable ids, its id) -- the "move keeps identity" contract that separates
# a move from delete-then-place. Returns the cells actually stamped.
func move_clip(src_cells: Dictionary, clip: Dictionary, origin: Vector2i, label := "move") -> Dictionary:
	if clip.is_empty() or src_cells.is_empty():
		return {}
	var d := MapIO.serialize()
	_strip_cells(d, src_cells)
	# a MOVE KEEPS every durable id -- that is the whole contract (ROADMAP "Move tool": moving a locked
	# door keeps its door_id, so its Unique key still resolves)
	var stamped := _apply_clip(d, clip, origin, false)
	if stamped.is_empty():
		return {} # nothing landed: leave the map untouched rather than deleting the source
	MapIO.apply_serialized(d, true)
	EditHistory.commit(label)
	return stamped

# write `clip` into the dict `d` at `origin` (no apply, no undo). Every target cell is STRIPPED first,
# so a paste overwrites within its footprint instead of half-merging with what was there.
func _apply_clip(d: Dictionary, clip: Dictionary, origin: Vector2i, fresh_ids := false) -> Dictionary:
	var w := int(d["grid"]["width"])
	var h := int(d["grid"]["height"])
	var absent := _absent_set(d)
	var target := {}
	for a in clip.get("cells", []):
		var cell := origin + Vector2i(int(a[0]), int(a[1]))
		if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h or absent.has(cell):
			continue # clipped at the map edge / on a hole
		target[cell] = true
	if target.is_empty():
		return {}
	_strip_cells(d, target)
	# the clip's records land rebased to `origin`, dropping any whose cell was clipped off. A PASTE mints
	# fresh ids for everything that carries one (doors, pickups, creatures, zones -- a pasted locked door is
	# a new door, so the original's Unique key does not open it); a bridge has no id. Zones land whole at
	# the origin, clipped to the map.
	var map_rect := Rect2i(0, 0, w, h)
	var placed := MapLayers.transform(clip,
		func(c: Vector2i) -> Vector2i: return origin + c if target.has(origin + c) else Grid.INVALID_CELL,
		Callable(),
		func(r: Rect2i) -> Rect2i: return Rect2i(r.position + origin, r.size).intersection(map_rect),
		func(rec: Dictionary, _key: String) -> void:
			if fresh_ids and rec.has("id"):
				rec["id"] = Items.new_id())
	for key in placed:
		if not d.has(key):
			d[key] = []
		d[key].append_array(placed[key])
	return target

# true if add_cell(cell) would succeed, without mutating (drives the hover highlight). A cell is
# addable when it is a hole inside the box with a present neighbour, or one step beyond exactly one edge.
func can_add_cell(cell: Vector2i) -> bool:
	var gb = _grid_bg()
	if gb == null:
		return false
	var w: int = gb.grid_width
	var h: int = gb.grid_height
	if cell.x >= 0 and cell.x < w and cell.y >= 0 and cell.y < h:
		if gb.cell_present(cell.x, cell.y):
			return false # already there
		return _copy_source(_absent_from_grid(gb), cell, w, h) != _NONE # a hole with a present neighbour
	return _beyond_edge(cell, w, h) != ""

# true if remove_cell(cell) would succeed, without mutating.
func can_remove_cell(cell: Vector2i) -> bool:
	var gb = _grid_bg()
	if gb == null:
		return false
	var w: int = gb.grid_width
	var h: int = gb.grid_height
	if not gb.cell_present(cell.x, cell.y):
		return false
	return (w * h) - gb.absent_cells.size() > 1 # never the last present cell

# --- single-cell helpers ---

const _NONE := Vector2i(-2147483648, -2147483648) # "no cell" sentinel for _copy_source

# the live GridBackground (via the obstacles group, like MapIO finds the world), or null.
func _grid_bg():
	var obs = get_tree().get_first_node_in_group("obstacles")
	var w = obs.get_parent() if obs else null
	return w.get_node_or_null("GridBackground") if w else null

func _absent_from_grid(gb) -> Dictionary:
	return gb.absent_cells

func _absent_set(d: Dictionary) -> Dictionary:
	var s := {}
	for a in d.get("absent_cells", []):
		s[Vector2i(int(a[0]), int(a[1]))] = true
	return s

func _absent_list(s: Dictionary) -> Array:
	var out: Array = []
	for c in s:
		out.append([c.x, c.y])
	return out

# the edge a cell lies just beyond (one step out, in-range on the other axis), or "" if it is not a
# valid single perimeter add (inside the box, too far out, or a diagonal past a corner).
func _beyond_edge(cell: Vector2i, w: int, h: int) -> String:
	if cell.x == -1 and cell.y >= 0 and cell.y < h:
		return "left"
	if cell.x == w and cell.y >= 0 and cell.y < h:
		return "right"
	if cell.y == -1 and cell.x >= 0 and cell.x < w:
		return "top"
	if cell.y == h and cell.x >= 0 and cell.x < w:
		return "bottom"
	return ""

# a present orthogonal neighbour to copy terrain from (prefers the interior), or _NONE if isolated.
func _copy_source(absent: Dictionary, cell: Vector2i, w: int, h: int) -> Vector2i:
	for n in [Vector2i(cell.x - 1, cell.y), Vector2i(cell.x + 1, cell.y),
			Vector2i(cell.x, cell.y - 1), Vector2i(cell.x, cell.y + 1)]:
		if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h and not absent.has(n):
			return n
	return _NONE

# copy the four floor quarters of `src` onto `dst` (terrain only, like _copy_edge_terrain does for a
# whole grown row/column). Only quarters that actually carry a material are copied; grass copies nothing.
func _copy_cell_terrain(d: Dictionary, dst: Vector2i, src: Vector2i) -> void:
	var have := {}
	for a in d["quads"]:
		have[Vector2i(int(a[0]), int(a[1]))] = a[2]
	for oy in [0, 1]:
		for ox in [0, 1]:
			var sq := Vector2i(src.x * 2 + ox, src.y * 2 + oy)
			if have.has(sq):
				d["quads"].append([dst.x * 2 + ox, dst.y * 2 + oy, have[sq]])

# strip everything sitting on any of `cells` (a set) from the dict, in one pass per layer. Zones are
# regions, not occupants, so they stay. The removal is part of the caller's single undo entry.
func _strip_cells(d: Dictionary, cells: Dictionary) -> void:
	d.merge(MapLayers.transform(d,
		func(c: Vector2i) -> Vector2i: return Grid.INVALID_CELL if cells.has(c) else c), true)

# if the player's spawn sits on the just-removed cell, move it to a present cell so a reload/undo
# never lands the player on the void.
func _relocate_spawn_if_on(d: Dictionary, cell: Vector2i, absent: Dictionary, w: int, h: int) -> void:
	var sx := float(d["spawn"]["x"])
	var sy := float(d["spawn"]["y"])
	var scell := Grid.cell_of(Vector2(sx, sy))
	if scell != cell:
		return
	for y in range(h):
		for x in range(w):
			var c := Vector2i(x, y)
			if not absent.has(c):
				d["spawn"] = {"x": Grid.cell_center(c).x, "y": Grid.cell_center(c).y}
				return

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

	# every positioned layer, plus the map's own holes, moves by (dx, dy) and is clipped to the new
	# bounds; a zone half-off the edge keeps the half that survives
	var delta := Vector2i(dx, dy)
	var bounds := Rect2i(0, 0, nw, nh)
	out.merge(MapLayers.transform(d,
		func(c: Vector2i) -> Vector2i: return c + delta if bounds.has_point(c + delta) else Grid.INVALID_CELL,
		Callable(),
		func(r: Rect2i) -> Rect2i: return Rect2i(r.position + delta, r.size).intersection(bounds),
		Callable(), MapLayers.LAYERS + ["absent_cells"]))
	return out

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
