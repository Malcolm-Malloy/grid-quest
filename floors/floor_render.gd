class_name FloorRender
extends RefCounted

# Derives what the floor LOOKS like from FloorManager's per-quarter stores: one fill per painted/tinted
# quarter, plus the derived edges -- liquid shorelines, the river-bank ring, and natural terrains
# feathering over lower ones. Nothing here is stored or saved; build() recomputes it from the stores.
# A fill is [dst_rect, texture, tint, (src_rect override), (animate)] (see grid_background._draw).

# the stores are FloorManager's own Dictionaries, shared by reference (it only ever clears them)
var _mat: Dictionary     # quarter -> material
var _tint: Dictionary    # quarter -> Color
var _pattern: Dictionary # quarter -> pattern index
var _no_bank: Dictionary # liquid quarter -> true when laid with the bank switch off
var _grid_bg: GridBackground

func _init(mat: Dictionary, tint: Dictionary, pattern: Dictionary, no_bank: Dictionary, grid_bg: GridBackground) -> void:
	_mat = mat
	_tint = tint
	_pattern = pattern
	_no_bank = no_bank
	_grid_bg = grid_bg

# neighbour offsets on the quarter grid. _N4 is N, E, S, W: side i is edge-mask bit 1 << i (N=1 E=2 S=4 W=8)
const _N4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const _N8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

# is quarter `q` on an existing cell? The same answer as FloorManager._in_bounds(Grid.cell_of_quad(q)), inlined for the
# neighbour tests in build' hot loops (up to 12 per liquid quarter), where that call chain dominated
func quad_in_map(q: Vector2i) -> bool:
	if _grid_bg == null:
		return true
	var cx := q.x >> 1 # arithmetic shift = floor division by 2, negatives included
	var cy := q.y >> 1
	return cx >= 0 and cy >= 0 and cx < _grid_bg.grid_width and cy < _grid_bg.grid_height \
		and (_grid_bg.absent_cells.is_empty() or not _grid_bg.absent_cells.has(Vector2i(cx, cy)))

# _mat is the whole floor (interior + under-wall quarters written by room fills), so the render is a
# straight one-rect-per-quarter pass: laying a tile changes only that quarter and never disturbs the
# under-wall ground already stored.
func build() -> Array:
	var extent := _extent_now()
	if extent != _extent:
		_extent = extent
		_rebuild_all() # the map's size or holes changed: every bank / edge test may answer differently
	else:
		_rebuild_changed()
	var fills: Array = []
	for q in _fills_by_q:
		fills.append_array(_fills_by_q[q])
	return fills

# --- incremental bookkeeping: a quarter's fills depend only on its own inputs and its 8 neighbours',
# so a change re-derives just the changed quarters and their neighbours. Changes are found by DIFFING
# the stores against copies from the last build, so any writer (or a test poking the stores) is covered.

var _fills_by_q := {} # quarter -> its fills: main (or tinted grass), then the river bank on top
var _snap: Array = [{}, {}, {}, {}] # copies of [_mat, _tint, _pattern, _no_bank] as of the last build
var _extent := []     # [width, height, holes] as of the last build

func _extent_now() -> Array:
	if _grid_bg == null:
		return []
	return [_grid_bg.grid_width, _grid_bg.grid_height, _grid_bg.absent_cells.hash()]

func _take_snapshot() -> void:
	_snap = [_mat.duplicate(), _tint.duplicate(), _pattern.duplicate(), _no_bank.duplicate()]

func _rebuild_all() -> void:
	_fills_by_q.clear()
	var bank := bank_quads() # the ring as a set, once, rather than a neighbour test per quarter
	var todo := bank.duplicate()
	for q in _mat:
		todo[q] = true
	for q in _tint:
		todo[q] = true
	for q in todo:
		_refresh(q, bank.has(q))
	_take_snapshot()

func _rebuild_changed() -> void:
	var changed := {}
	var stores := [_mat, _tint, _pattern, _no_bank]
	for i in stores.size():
		var cur: Dictionary = stores[i]
		var old: Dictionary = _snap[i]
		for q in cur:
			if not old.has(q) or old[q] != cur[q]:
				changed[q] = true
		for q in old:
			if not cur.has(q):
				changed[q] = true
	if changed.is_empty():
		return
	var redo := {}
	for q in changed:
		redo[q] = true
		for d in _N8:
			redo[q + d] = true
	for q in redo:
		_refresh(q, _is_bank(q))
	_take_snapshot()

func _refresh(q: Vector2i, bank: bool) -> void:
	var fills := _quarter_fills(q, bank)
	if fills.is_empty():
		_fills_by_q.erase(q)
	else:
		_fills_by_q[q] = fills

# everything drawn on quarter `q`: its material's fill(s), or a tinted patch of grass, then the brown
# river bank on top if `q` borders a banked liquid. A 5th `true` flags a shimmering (liquid) fill.
func _quarter_fills(q: Vector2i, bank: bool) -> Array:
	var fills := _material_fills(q) if _mat.has(q) else []
	# a quarter carrying a tint but NO material is a tinted patch of grass: draw the grass base under the
	# tint so the recolour shows
	if not _mat.has(q) and _tint.has(q):
		fills.append([Grid.quad_rect(q), FloorMaterials.GRASS, _tint[q]])
	# River-bank auto-edge: a non-liquid quarter touching a banked liquid draws the brown bank on TOP of
	# whatever is there, untinted. Derived only, so it is neither saved nor blocking.
	if bank:
		fills.append([Grid.quad_rect(q), FloorMaterials.RIVER_BANK, Color.WHITE])
	return fills

# the fill(s) for a quarter that carries a material
func _material_fills(q: Vector2i) -> Array:
	var fills: Array = []
	var rect := Grid.quad_rect(q)
	var mat: String = _mat[q]
	var tint: Color = _tint.get(q, Color.WHITE)
	if FloorMaterials.LIQUID_SHORE.has(mat):
		# Liquids (water/lava): a feathered shore where they meet a different material, over a bank
		# underlay UNLESS the bank switch was off for this quarter (then the feather reveals grass).
		# Fills carry a 5th `true` so grid_background shimmers them; the bank underlay stays static.
		# mask 0 (open liquid) draws the flat, seamless, world-tiled tile, also animated.
		var mask := liquid_edge_mask(q, mat)
		if mask != 0:
			if not _no_bank.has(q):
				fills.append([rect, FloorMaterials.RIVER_BANK, Color.WHITE]) # bank the feather reveals
			fills.append([rect, FloorMaterials.LIQUID_SHORE[mat], tint, shore_src(mask), true]) # feathered liquid
		else:
			fills.append([rect, FloorMaterials.texture(mat, 0), tint, GridBackground.tiled_src(rect), true])
		return fills
	elif FloorMaterials.EDGE_ATLAS.has(mat):
		# Auto-match: a natural terrain feathers over its lower-precedence orthogonal neighbours.
		var mask := terrain_edge_mask(q, mat)
		if mask != 0:
			var under: String = edge_underlay_mat(q, mat)
			if under != "": # reveal a non-base lower terrain (e.g. sand under snow) through the feather
				fills.append([rect, FloorMaterials.texture(under, 0), Color.WHITE])
			fills.append([rect, FloorMaterials.EDGE_ATLAS[mat], tint, shore_src(mask)])
			return fills
		# mask 0 (bordered only by same/higher terrain): fall through to the flat, seamless tile
	elif mat == "grass":
		# grass is the base: Plain (pattern 0) draws NOTHING so the ground grass shows through with no
		# patch seam (a tint still shows, matching the tint-only branch); Wild/Tuft draw an alpha blade
		# overlay over the base. Never falls through to the opaque generic tile.
		var gp: int = _pattern.get(q, 0)
		if gp != 0:
			fills.append([rect, FloorMaterials.texture("grass", gp), tint, GridBackground.tiled_src(rect)])
		elif tint != Color.WHITE:
			fills.append([rect, FloorMaterials.GRASS, tint])
		return fills
	fills.append([rect, FloorMaterials.texture(mat, _pattern.get(q, 0)), tint])
	return fills

# is `q` part of the river-bank ring: in the map, not itself a liquid, and 8-neighbour-adjacent to a
# liquid quarter that was laid with the bank switch on? (bank_quads() is the same rule, as a set)
func _is_bank(q: Vector2i) -> bool:
	if FloorMaterials.BANK_AROUND.has(_mat.get(q, "")) or not quad_in_map(q):
		return false
	for d in _N8:
		var n: Vector2i = q + d
		if FloorMaterials.BANK_AROUND.has(_mat.get(n, "")) and not _no_bank.has(n):
			return true
	return false

# the set of 16px quarter coords that render as river bank: any in-bounds quarter that is NOT a
# FloorMaterials.BANK_AROUND material but is 8-neighbour-adjacent to one. Returned as a dict (used as a set) so a
# quarter shared by several water quarters is emitted once. Purely derived from _mat.
func bank_quads() -> Dictionary:
	var bank := {}
	for q in _mat:
		if not FloorMaterials.BANK_AROUND.has(_mat[q]):
			continue
		if _no_bank.has(q):
			continue # this liquid quarter was laid with the bank switch OFF
		for d in _N8:
			var n: Vector2i = q + d
			if bank.has(n) or FloorMaterials.BANK_AROUND.has(_mat.get(n, "")):
				continue # already banked, or a neighbouring water quarter (not bank)
			if quad_in_map(n): # keep bank inside the map grid, not out in the void
				bank[n] = true
	return bank

# the 4-bit LAND mask for a water quarter's ORTHOGONAL neighbours (N=1 E=2 S=4 W=8), used to pick the
# shoreline autotile variant. A side is "land" when its neighbour quarter is in-bounds and not water;
# out-of-map neighbours are NOT land, so water never feathers toward the map edge (it just clips there).
# A side feathers when its neighbour is in-bounds and a DIFFERENT material (land, or the other liquid);
# out-of-map neighbours are not, so a liquid clips at the map edge instead of feathering.
func liquid_edge_mask(q: Vector2i, mat: String) -> int:
	var m := 0
	for i in 4:
		var nq: Vector2i = q + _N4[i]
		if _mat.get(nq, "") != mat and quad_in_map(nq):
			m |= 1 << i
	return m

# the 4-bit edge mask for an auto-matching terrain quarter `mat` at `q` (N=1 E=2 S=4 W=8): a side is set
# when its orthogonal neighbour is an IN-BOUNDS natural terrain of STRICTLY LOWER precedence (so `mat`
# feathers over it). Out-of-map, same-rank, higher-rank (incl. water), and non-natural (indoor) neighbours
# never set a bit, so terrain never feathers toward the void, a peer, water, or a constructed floor.
func terrain_edge_mask(q: Vector2i, mat: String) -> int:
	var r: int = FloorMaterials.TERRAIN_RANK.get(mat, 0)
	var m := 0
	for i in 4:
		var nq: Vector2i = q + _N4[i]
		var nmat: String = _mat.get(nq, "")
		if FloorMaterials.TERRAIN_RANK.has(nmat) and FloorMaterials.TERRAIN_RANK[nmat] < r and quad_in_map(nq):
			m |= 1 << i
	return m

# the material to lay UNDER a feathered edge quarter so the feather reveals the right lower terrain: the
# HIGHEST-ranked lower natural among the orthogonal neighbours. Returns "" (no underlay) when that is the
# grass base (rank 0), since the whole map already draws grass beneath every quarter.
func edge_underlay_mat(q: Vector2i, mat: String) -> String:
	var r: int = FloorMaterials.TERRAIN_RANK.get(mat, 0)
	var best := ""
	var best_rank := 0
	for d in _N4:
		var nq: Vector2i = q + d
		var nmat: String = _mat.get(nq, "")
		if FloorMaterials.TERRAIN_RANK.has(nmat) and FloorMaterials.TERRAIN_RANK[nmat] < r and FloorMaterials.TERRAIN_RANK[nmat] > best_rank and quad_in_map(nq):
			best_rank = FloorMaterials.TERRAIN_RANK[nmat]
			best = nmat
	return best

# the atlas source rect for shoreline mask `m`: the 4x4 grid of 32px cells, indexed m%4 across, m/4 down.
func shore_src(m: int) -> Rect2:
	return Rect2((m % 4) * FloorMaterials.SHORE_TILE, (m / 4) * FloorMaterials.SHORE_TILE, FloorMaterials.SHORE_TILE, FloorMaterials.SHORE_TILE)
