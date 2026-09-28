class_name MapLayers
extends RefCounted

# The positioned layers of a MapIO.serialize() dict, grouped by how each stores its position, and ONE
# transform that moves them all. Resize (MapEdit._shift), cell removal (_strip_cell), paste (_apply_clip),
# copy (MapClipboard.build_clip) and rotate/flip (_remap) are all "move or drop every positioned thing",
# so they share this instead of each listing every layer: a new layer is added HERE, once.

const CELL_ROWS := ["walls", "wall_colors", "wall_materials"]          # [cx, cy, ...]
const CELL_RECS := ["doors", "bridges", "pickups", "creatures"]         # {"cell": [cx, cy], ...}
const QUAD_ROWS := ["quads", "floor_tints", "floor_patterns", "floor_no_bank"] # [qx, qy, ...]
const RECT_RECS := ["creature_zones"]                                   # {"rect": [x, y, w, h], ...}
# every layer an edit region carries (the map's own extent, absent_cells, is a CELL_ROWS-shaped extra
# that only a resize moves; pass it explicitly there)
const LAYERS := ["walls", "wall_colors", "wall_materials", "doors", "bridges", "pickups", "creatures",
	"quads", "floor_tints", "floor_patterns", "floor_no_bank", "creature_zones"]

# Map every layer in `keys` of `d` to a new list, returned as {key: Array}. Nothing in `d` is mutated;
# records are deep-copied, so every field rides along and only the position is rewritten.
#   cell_fn(Vector2i) -> Vector2i : a cell's new position, or Grid.INVALID_CELL to drop it
#   quad_fn(Vector2i) -> Vector2i : a quarter's new position (or INVALID). Omit it and each quarter
#                                   follows its cell, keeping its place within it (right for any
#                                   translate / filter; a rotate or flip must pass its own)
#   rect_fn(Rect2i) -> Rect2i     : a rect layer's new rect; an empty result drops it. Omit it to keep
#                                   rects unchanged
#   rec_hook(rec, key)            : called on each copied record (doors, zones, ...) to adjust it
static func transform(d: Dictionary, cell_fn: Callable, quad_fn := Callable(), rect_fn := Callable(),
		rec_hook := Callable(), keys: Array = LAYERS) -> Dictionary:
	var out := {}
	for key in keys:
		var dst: Array = []
		for item in d.get(key, []):
			if QUAD_ROWS.has(key):
				var q := Vector2i(int(item[0]), int(item[1]))
				var nq: Vector2i = quad_fn.call(q) if quad_fn.is_valid() else _follow_cell(q, cell_fn)
				if nq != Grid.INVALID_CELL:
					dst.append(_moved_row(item, nq))
			elif CELL_RECS.has(key):
				var p: Vector2i = cell_fn.call(Vector2i(int(item["cell"][0]), int(item["cell"][1])))
				if p != Grid.INVALID_CELL:
					var rec: Dictionary = item.duplicate(true)
					rec["cell"] = [p.x, p.y]
					if rec_hook.is_valid():
						rec_hook.call(rec, key)
					dst.append(rec)
			elif RECT_RECS.has(key):
				var a: Array = item["rect"]
				var r := Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
				if rect_fn.is_valid():
					r = rect_fn.call(r)
				if r.size.x > 0 and r.size.y > 0:
					var zrec: Dictionary = item.duplicate(true)
					zrec["rect"] = [r.position.x, r.position.y, r.size.x, r.size.y]
					if rec_hook.is_valid():
						rec_hook.call(zrec, key)
					dst.append(zrec)
			else: # CELL_ROWS, and absent_cells
				var c: Vector2i = cell_fn.call(Vector2i(int(item[0]), int(item[1])))
				if c != Grid.INVALID_CELL:
					dst.append(_moved_row(item, c))
		out[key] = dst
	return out

# a quarter moved with its owning cell, keeping its offset (0/1, 0/1) inside the cell
static func _follow_cell(q: Vector2i, cell_fn: Callable) -> Vector2i:
	var c := Grid.cell_of_quad(q)
	var nc: Vector2i = cell_fn.call(c)
	if nc == Grid.INVALID_CELL:
		return Grid.INVALID_CELL
	return nc * 2 + (q - c * 2)

static func _moved_row(row: Array, p: Vector2i) -> Array:
	var out: Array = row.duplicate()
	out[0] = p.x
	out[1] = p.y
	return out
