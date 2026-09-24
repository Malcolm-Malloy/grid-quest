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
	}
	for c in cells:
		out["cells"].append([c.x - minc.x, c.y - minc.y])
	# every layer's records inside the footprint, rebased to the origin (a quarter goes with the cell that
	# owns it). Spawn zones are regions, so "in the selection" means CONTAINED, not "touches": a zone
	# clipped in half by a copy would paste a different rule from the one that was copied.
	out.merge(MapLayers.transform(d,
		func(c: Vector2i) -> Vector2i: return c - minc if cells.has(c) else Grid.INVALID_CELL,
		Callable(),
		func(r: Rect2i) -> Rect2i: return Rect2i(r.position - minc, r.size) if _rect_inside(r, cells) else Rect2i()))
	return out

# is every cell of `r` in the set `cells`?
func _rect_inside(r: Rect2i, cells: Dictionary) -> bool:
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			if not cells.has(Vector2i(x, y)):
				return false
	return true

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
	var out := {"w": nw, "h": nh, "origin": c.get("origin", [0, 0]).duplicate(), "cells": []}
	for a in c.get("cells", []):
		var p: Vector2i = cell_fn.call(Vector2i(int(a[0]), int(a[1])))
		out["cells"].append([p.x, p.y])
	# a zone is a rect, so it is remapped by its two opposite CORNERS and rebuilt from them -- a rotate
	# turns a wide zone into a tall one, which mapping the corners gets right for free. Directional
	# records (doors, bridges) re-face through the orientation table.
	out.merge(MapLayers.transform(c, cell_fn, quad_fn,
		func(r: Rect2i) -> Rect2i:
			var p0: Vector2i = cell_fn.call(r.position)
			var p1: Vector2i = cell_fn.call(r.end - Vector2i.ONE)
			return Rect2i(p0.min(p1), (p0.max(p1) - p0.min(p1)) + Vector2i.ONE),
		func(rec: Dictionary, _key: String) -> void: _reorient(rec, kind)))
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
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("cells"):
		_clip = parsed
