class_name FloorRender
extends RefCounted

# Derives what the floor LOOKS like from FloorManager's per-quarter stores: one fill per painted/tinted
# quarter, plus the derived edges -- liquid shorelines, the river-bank ring, and natural terrains
# feathering over lower ones. Nothing here is stored or saved; build() recomputes it from the stores.
# A fill is [dst_rect, texture, tint, (src_rect override), (animate)] (see grid_background._draw).

var has_water := false # the last build() emitted an animated liquid fill (grid_background shimmers)

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
	var fills: Array = []
	has_water = false
	for q in _mat:
		var rect := Grid.quad_rect(q)
		var mat: String = _mat[q]
		var tint: Color = _tint.get(q, Color.WHITE)
		if FloorMaterials.LIQUID_SHORE.has(mat):
			# Liquids (water/lava): a feathered shore where they meet a different material, over a bank
			# underlay UNLESS the bank switch was off for this quarter (then the feather reveals grass).
			# Fills carry a 5th `true` so grid_background shimmers them; the bank underlay stays static.
			# mask 0 (open liquid) draws the flat, seamless, world-tiled tile, also animated.
			has_water = true
			var mask := liquid_edge_mask(q, mat)
			if mask != 0:
				if not _no_bank.has(q):
					fills.append([rect, FloorMaterials.RIVER_BANK, Color.WHITE]) # bank the feather reveals
				fills.append([rect, FloorMaterials.LIQUID_SHORE[mat], tint, shore_src(mask), true]) # feathered liquid
			else:
				fills.append([rect, FloorMaterials.texture(mat, 0), tint, GridBackground.tiled_src(rect), true])
			continue
		elif FloorMaterials.EDGE_ATLAS.has(mat):
			# Auto-match: a natural terrain feathers over its lower-precedence orthogonal neighbours.
			var mask := terrain_edge_mask(q, mat)
			if mask != 0:
				var under: String = edge_underlay_mat(q, mat)
				if under != "": # reveal a non-base lower terrain (e.g. sand under snow) through the feather
					fills.append([rect, FloorMaterials.texture(under, 0), Color.WHITE])
				fills.append([rect, FloorMaterials.EDGE_ATLAS[mat], tint, shore_src(mask)])
				continue
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
			continue
		fills.append([rect, FloorMaterials.texture(mat, _pattern.get(q, 0)), tint])
	# a quarter carrying a tint but NO material is a tinted patch of grass: draw the grass base
	# under the tint so the recolour shows (an unpainted quarter isn't in _mat above).
	for q in _tint:
		if _mat.has(q):
			continue
		fills.append([Grid.quad_rect(q), FloorMaterials.GRASS, _tint[q]])
	# River-bank auto-edge: every non-water quarter touching water (8-neighbour, in-bounds) draws the
	# brown bank on TOP of whatever is there. Appended last so it renders over the underlying fill;
	# untinted (native brown). Derived only, so it is neither saved nor blocking (see FloorMaterials.RIVER_BANK).
	for bq in bank_quads():
		fills.append([Grid.quad_rect(bq), FloorMaterials.RIVER_BANK, Color.WHITE])
	return fills

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
