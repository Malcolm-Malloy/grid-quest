extends Node

# MapClipboard (autoload): the editor's copy/paste clipboard for a REGION of the map.
#
# A "clip" is a self-contained, ORIGIN-RELATIVE slice of the same layers MapIO.serialize()
# stores (walls, doors, bridges, wall colours/materials, floor quarters/tints/patterns/bank
# flags), plus the footprint of CELLS it covers. Because it is just data in the serialized
# shape, pasting is a pure transform on a map dict re-applied through MapIO -- the same path
# load, resize and undo already use -- so a paste rebuilds everything derived and lands as
# one undo entry (see MapEdit.stamp_clip / move_clip).
#
# GRAIN (settled at build, ROADMAP "Copy, paste, and duplicate" -> "also settle at build"):
# - The footprint is a set of CELLS. A floor selection contributes every cell that owns one of
#   its selected quarters, so magic-wand-selecting a room (interior + wall ring) and copying it
#   takes the room's floor AND its walls/doors -- the "build a room once, reuse it" case.
# - Paste OVERWRITES within the footprint: every target cell is stripped first, so a stamp never
#   half-merges with what was there.
# - Paste CLIPS at the map edge: target cells outside the grid (or on an absent-cell hole) are
#   dropped, the rest still land. Nothing auto-extends the map.
#
# CROSS-MAP + RESTART: the clip lives here (an autoload), so it survives loading another map,
# and it is mirrored to user://clipboard.json so it survives a restart too.
#
# ROTATE / FLIP: clips transform as DATA, not as rotated images. Cell and quarter coordinates
# remap within the bounding box, and every directional record is remapped through the
# orientation table below (a horizontal door becomes a vertical one, its swing side following
# the rotation), per ROADMAP "Directional assets must re-orient correctly, not spin naively".
# Walls carry no orientation of their own (their shape is derived from their neighbours), and
# floor quarters/materials/patterns are non-directional, so today every clip can rotate.

const FILE := "user://clipboard.json"

signal changed # a new clip was copied (or the clipboard was cleared), for UI affordances

var _clip: Dictionary = {}

func _ready() -> void:
	_load_from_disk()

# --- public state ---

func has_clip() -> bool:
	return not _clip.is_empty()

# the stored clip (a copy, so callers can transform it freely without touching the clipboard)
func clip() -> Dictionary:
	return _clip.duplicate(true)

func set_clip(c: Dictionary) -> void:
	_clip = c
	_save_to_disk()
	changed.emit()

func clear() -> void:
	_clip = {}
	changed.emit()

# how many cells the stored clip covers (0 = empty), for status text
func clip_cell_count() -> int:
	return _clip.get("cells", []).size()

# --- build a clip: the slice of `d` (a MapIO.serialize() dict) covered by the cell set `cells` ---

func build_clip(d: Dictionary, cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {}
	var minc := Vector2i(1 << 30, 1 << 30)
	var maxc := Vector2i(-(1 << 30), -(1 << 30))
	for c in cells:
		minc.x = mini(minc.x, c.x); minc.y = mini(minc.y, c.y)
		maxc.x = maxi(maxc.x, c.x); maxc.y = maxi(maxc.y, c.y)
	var out := {
		"w": maxc.x - minc.x + 1,
		"h": maxc.y - minc.y + 1,
		"origin": [minc.x, minc.y], # where it was copied FROM (a move stamps back relative to this)
		"cells": [],
		"walls": [], "wall_colors": [], "wall_materials": [],
		"doors": [], "bridges": [], "pickups": [],
		"quads": [], "floor_tints": [], "floor_patterns": [], "floor_no_bank": [],
	}
	for c in cells:
		out["cells"].append([c.x - minc.x, c.y - minc.y])
	# [cx, cy, ...] rows: keep the row if its cell is in the footprint, rebased to the origin
	for key in ["walls", "wall_colors", "wall_materials"]:
		for a in d.get(key, []):
			var cell := Vector2i(int(a[0]), int(a[1]))
			if not cells.has(cell):
				continue
			var row: Array = a.duplicate()
			row[0] = cell.x - minc.x
			row[1] = cell.y - minc.y
			out[key].append(row)
	# {cell: [cx, cy], ...} records (doors, bridges, placed items)
	for key in ["doors", "bridges", "pickups"]:
		for r in d.get(key, []):
			var cell := Vector2i(int(r["cell"][0]), int(r["cell"][1]))
			if not cells.has(cell):
				continue
			var rec: Dictionary = r.duplicate(true)
			rec["cell"] = [cell.x - minc.x, cell.y - minc.y]
			out[key].append(rec)
	# [qx, qy, ...] quarter rows: keyed by the CELL that owns the quarter, rebased in quarter units
	for key in ["quads", "floor_tints", "floor_patterns", "floor_no_bank"]:
		for a in d.get(key, []):
			var q := Vector2i(int(a[0]), int(a[1]))
			if not cells.has(Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))):
				continue
			var row: Array = a.duplicate()
			row[0] = q.x - minc.x * 2
			row[1] = q.y - minc.y * 2
			out[key].append(row)
	return out

# --- transforms (each returns a NEW clip; the stored clipboard is never mutated in place) ---

# rotate 90 degrees clockwise: (x, y) -> (h - 1 - y, x), and the bounding box's w/h swap.
func rotate_cw(c: Dictionary) -> Dictionary:
	if c.is_empty():
		return c
	var h := int(c["h"]) # a disk-loaded clip comes back with JSON floats, so read every dim through int()
	return _remap(c, int(c["h"]), int(c["w"]),
		func(p: Vector2i) -> Vector2i: return Vector2i(h - 1 - p.y, p.x),
		func(q: Vector2i) -> Vector2i: return Vector2i(h * 2 - 1 - q.y, q.x),
		"rotate")

# mirror left-to-right: (x, y) -> (w - 1 - x, y)
func flip_h(c: Dictionary) -> Dictionary:
	if c.is_empty():
		return c
	var w := int(c["w"])
	return _remap(c, int(c["w"]), int(c["h"]),
		func(p: Vector2i) -> Vector2i: return Vector2i(w - 1 - p.x, p.y),
		func(q: Vector2i) -> Vector2i: return Vector2i(w * 2 - 1 - q.x, q.y),
		"flip_h")

# mirror top-to-bottom: (x, y) -> (x, h - 1 - y)
func flip_v(c: Dictionary) -> Dictionary:
	if c.is_empty():
		return c
	var h := int(c["h"])
	return _remap(c, int(c["w"]), int(c["h"]),
		func(p: Vector2i) -> Vector2i: return Vector2i(p.x, h - 1 - p.y),
		func(q: Vector2i) -> Vector2i: return Vector2i(q.x, h * 2 - 1 - q.y),
		"flip_v")

# one generic coordinate remap. `cell_fn` moves a cell, `quad_fn` a quarter (the quarter grid is
# twice as fine, so it needs its own mapping), and `kind` picks the orientation remap for the
# directional records.
func _remap(c: Dictionary, nw: int, nh: int, cell_fn: Callable, quad_fn: Callable, kind: String) -> Dictionary:
	var out := {"w": nw, "h": nh, "origin": c.get("origin", [0, 0]).duplicate(),
		"cells": [], "walls": [], "wall_colors": [], "wall_materials": [],
		"doors": [], "bridges": [], "pickups": [], "quads": [], "floor_tints": [], "floor_patterns": [],
		"floor_no_bank": []}
	for a in c.get("cells", []):
		var p: Vector2i = cell_fn.call(Vector2i(int(a[0]), int(a[1])))
		out["cells"].append([p.x, p.y])
	for key in ["walls", "wall_colors", "wall_materials"]:
		for a in c.get(key, []):
			var row: Array = a.duplicate()
			var p: Vector2i = cell_fn.call(Vector2i(int(a[0]), int(a[1])))
			row[0] = p.x
			row[1] = p.y
			out[key].append(row)
	for key in ["doors", "bridges", "pickups"]:
		for r in c.get(key, []):
			var rec: Dictionary = r.duplicate(true)
			var p: Vector2i = cell_fn.call(Vector2i(int(r["cell"][0]), int(r["cell"][1])))
			rec["cell"] = [p.x, p.y]
			_reorient(rec, kind)
			out[key].append(rec)
	for key in ["quads", "floor_tints", "floor_patterns", "floor_no_bank"]:
		for a in c.get(key, []):
			var row: Array = a.duplicate()
			var q: Vector2i = quad_fn.call(Vector2i(int(a[0]), int(a[1])))
			row[0] = q.x
			row[1] = q.y
			out[key].append(row)
	return out

# THE ORIENTATION REMAP TABLE (ROADMAP: "the single source for orientation X rotated/flipped -> Y",
# reused by rotate, flip and, later, the R-key placement override).
#
# A door's `swing` is one bool read per orientation: vertical -> swings EAST when true, horizontal ->
# swings NORTH when true (gate.gd swing_right / swing_up). So the side it opens to must follow the
# transform, not just the orientation:
#   rotate CW: north -> east (horizontal true -> vertical true), east -> south (vertical true ->
#              horizontal false). So only a VERTICAL source inverts.
#   flip_h (mirror x): east <-> west, so a VERTICAL door inverts; a horizontal one is untouched.
#   flip_v (mirror y): north <-> south, so a HORIZONTAL door inverts; a vertical one is untouched.
# Bridges are orientation-only (no swing side).
func _reorient(rec: Dictionary, kind: String) -> void:
	if not rec.has("orientation"):
		return # a non-directional record (a placed item): position moves, nothing to re-face
	var vertical: bool = String(rec["orientation"]) == "vertical"
	match kind:
		"rotate":
			rec["orientation"] = "horizontal" if vertical else "vertical"
			if rec.has("swing") and vertical:
				rec["swing"] = not bool(rec["swing"])
		"flip_h":
			if rec.has("swing") and vertical:
				rec["swing"] = not bool(rec["swing"])
		"flip_v":
			if rec.has("swing") and not vertical:
				rec["swing"] = not bool(rec["swing"])

# --- disk mirror, so the clipboard survives a restart (ROADMAP: "optionally persists to disk") ---

func _save_to_disk() -> void:
	if _clip.is_empty():
		if FileAccess.file_exists(FILE):
			DirAccess.remove_absolute(FILE)
		return
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f == null:
		return # a clipboard that cannot persist is not worth an error; it still works in-session
	f.store_string(JSON.stringify(_clip))
	f.close()

func _load_from_disk() -> void:
	if not FileAccess.file_exists(FILE):
		return
	var f := FileAccess.open(FILE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("cells"):
		_clip = parsed
