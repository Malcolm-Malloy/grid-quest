extends Node2D

# Lights the room the player is in (plus any room reachable through an OPEN door) and
# dims the rest. Rooms are discovered by flood fill from the actual wall/door layout,
# with no hardcoded room shapes, so a level editor can place arbitrary walls and doors
# and this keeps working. Sits just above the floor (below shadows and walls) so only
# the floor dims.
#
# Cell model, all derived from Obstacles:
#   wall  - in Obstacles.blocked_cells; a solid barrier.
#   door  - a gate cell; a barrier while closed, passable + lit while open.
#   floor - anything else. "exterior" floor is reachable from the map edge without
#           crossing a wall or door; every other floor cell is enclosed room floor.

const CELL := 32
const DARK := Color(0.0, 0.0, 0.05, 0.55) # overlay colour for unlit floor
const VIEW := 15 # cells around the player the dim overlay covers (past the camera edge)

@onready var player = get_node("../Player")
@onready var obstacles = get_node("../Obstacles")

var last_key := "?"
var _built := false
var _walls: Dictionary = {}     # Vector2i -> true
var _doorcells: Dictionary = {} # Vector2i -> true (positions, independent of open state)
var _exterior: Dictionary = {}  # Vector2i -> true (floor reachable from the map edge)
var _box: Rect2i                # bounding box the exterior flood covers
var _lit_cache: Dictionary = {} # memoised lit_cells for the current key
var _lit_key := "?"
var _lit_ext := false           # does the current lit region include the outdoor

func _process(_delta: float) -> void:
	var key := _key()
	if key != last_key:
		last_key = key
		queue_redraw()
		# the shadow manager reads the same layout, so it has to redraw in step
		var shadows := get_parent().get_node_or_null("ShadowGroup")
		if shadows:
			shadows.refresh()

# --- layout, built once from Obstacles (rebuildable later for an editor) ---

func _ensure_built() -> void:
	if _built or obstacles == null:
		return
	_walls = {}
	for c in obstacles.blocked_cells:
		_walls[c] = true
	if _walls.is_empty():
		return # Obstacles not populated yet; retry on the next call
	_doorcells = {}
	for gd in obstacles.gate_cells:
		_doorcells[gd["cell"]] = true
	_built = true
	_build_exterior()

# floods the exterior: floor reachable from the border of a box around the walls,
# treating walls AND doors as barriers so every room stays enclosed regardless of door
# state. Anything outside the box counts as exterior too.
func _build_exterior() -> void:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in _walls:
		lo.x = min(lo.x, c.x)
		lo.y = min(lo.y, c.y)
		hi.x = max(hi.x, c.x)
		hi.y = max(hi.y, c.y)
	lo -= Vector2i(2, 2)
	hi += Vector2i(2, 2)
	_box = Rect2i(lo, hi - lo + Vector2i(1, 1))
	_exterior = {}
	var q: Array = []
	for x in range(lo.x, hi.x + 1):
		_seed(Vector2i(x, lo.y), q)
		_seed(Vector2i(x, hi.y), q)
	for y in range(lo.y, hi.y + 1):
		_seed(Vector2i(lo.x, y), q)
		_seed(Vector2i(hi.x, y), q)
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for n in _neighbours(c):
			if not _in_box(n) or _exterior.has(n) or _walls.has(n) or _doorcells.has(n):
				continue
			_exterior[n] = true
			q.append(n)

func _seed(c: Vector2i, q: Array) -> void:
	if _exterior.has(c) or _walls.has(c) or _doorcells.has(c):
		return
	_exterior[c] = true
	q.append(c)

func _neighbours(c: Vector2i) -> Array:
	return [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]

func _in_box(c: Vector2i) -> bool:
	return c.x >= _box.position.x and c.y >= _box.position.y \
			and c.x < _box.position.x + _box.size.x and c.y < _box.position.y + _box.size.y

func _is_exterior(c: Vector2i) -> bool:
	if not _in_box(c):
		return true
	return _exterior.has(c)

func _player_cell() -> Vector2i:
	return Vector2i(floori(player.position.x / CELL), floori(player.position.y / CELL))

# --- queries used by the shadow manager ---

# true when the lit region includes the outdoor: the player is outside, OR is indoors
# with an open door onto the exterior. Then the room(s) AND the outdoor both light up,
# the same way two rooms both light through the open door between them.
func exterior_lit() -> bool:
	lit_cells() # refreshes the cache and the _lit_ext flag
	return _lit_ext

# every enclosed room-floor cell (no walls, doors or exterior). The shadow manager
# shades these while the player is outside so the rooms read dark.
func enclosed_floor_cells() -> Array:
	_ensure_built()
	var out: Array = []
	if not _built:
		return out
	for x in range(_box.position.x, _box.position.x + _box.size.x):
		for y in range(_box.position.y, _box.position.y + _box.size.y):
			var c := Vector2i(x, y)
			if not _walls.has(c) and not _doorcells.has(c) and not _exterior.has(c):
				out.append(c)
	return out

func _is_lit_floor(lit: Dictionary, c: Vector2i) -> bool:
	# a lit room-FLOOR cell: enclosed floor that the lit flood reached (not exterior)
	return lit.has(c) and not _walls.has(c) and not _doorcells.has(c) and not _is_exterior(c)

# Half-cell rects (World space) for the room-facing quadrants of the wall, corner AND
# door tiles bordering the given floor set. A quadrant is included when it faces a floor
# cell (2 orthogonal + 1 diagonal neighbour), so the outward sides are left out. This is
# how a floor (or a shadow-clean) reaches right up to the walls with no border showing.
func _wall_ring_quads(floor: Dictionary) -> Array:
	var half := CELL / 2.0
	var walls := {}
	for c in floor:
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n: Vector2i = c + Vector2i(dx, dy)
				if _walls.has(n) or _doorcells.has(n):
					walls[n] = true
	var out: Array = []
	for w in walls:
		var x: int = w.x
		var y: int = w.y
		if floor.has(Vector2i(x - 1, y)) or floor.has(Vector2i(x, y - 1)) or floor.has(Vector2i(x - 1, y - 1)):
			out.append(Rect2(x * CELL, y * CELL, half, half))
		if floor.has(Vector2i(x + 1, y)) or floor.has(Vector2i(x, y - 1)) or floor.has(Vector2i(x + 1, y - 1)):
			out.append(Rect2(x * CELL + half, y * CELL, half, half))
		if floor.has(Vector2i(x - 1, y)) or floor.has(Vector2i(x, y + 1)) or floor.has(Vector2i(x - 1, y + 1)):
			out.append(Rect2(x * CELL, y * CELL + half, half, half))
		if floor.has(Vector2i(x + 1, y)) or floor.has(Vector2i(x, y + 1)) or floor.has(Vector2i(x + 1, y + 1)):
			out.append(Rect2(x * CELL + half, y * CELL + half, half, half))
	return out

# room-facing wall/door quadrants of every LIT room. The shadow manager stamps these clean
# in outdoor mode so a lit room's whole enclosing ring reads clean like indoors.
func lit_wall_stamps() -> Array:
	_ensure_built()
	if not _built:
		return []
	var lit := lit_cells()
	var floor := {}
	for c in lit:
		if _is_lit_floor(lit, c):
			floor[c] = true
	return _wall_ring_quads(floor)

func is_enclosed_floor(c: Vector2i) -> bool:
	_ensure_built()
	if not _built:
		return false
	return not _walls.has(c) and not _doorcells.has(c) and not _is_exterior(c)

# true when a cell is indoors: enclosed room floor OR a doorway (not a wall, not the
# open exterior). Used to shrink the player's shadow once it steps into a doorway.
func is_indoor(c: Vector2i) -> bool:
	_ensure_built()
	if not _built:
		return false
	return not _walls.has(c) and not _is_exterior(c)

# floor cells of the single room containing `seed`, found the same way as the shadow
# system's enclosed floor but treating EVERY door as a barrier, so it stops at this
# room's walls and doors: one room only, never the ones joined through open doors.
func room_floor_cells(seed: Vector2i) -> Dictionary:
	_ensure_built()
	var out := {}
	if not _built or not is_enclosed_floor(seed):
		return out
	out[seed] = true
	var q: Array = [seed]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for n in _neighbours(c):
			if out.has(n) or _walls.has(n) or _doorcells.has(n) or _is_exterior(n):
				continue
			out[n] = true
			q.append(n)
	return out

# the room-facing wall/door quadrants around a floor set, so a styled floor (or a
# shadow-clean) runs right up to the walls with no grass border. Public for FloorManager.
func wall_ring_quads(floor: Dictionary) -> Array:
	return _wall_ring_quads(floor)

# --- lighting ---

func _open_doors() -> Dictionary:
	var out := {}
	for g in get_tree().get_nodes_in_group("gates"):
		if g.is_open:
			out[g.cell] = true
	return out

# flood of lit cells: from the player across floor and, once reached through an open
# door, the exterior, crossing open doors and stopping at walls and closed doors. This
# is the whole lit region: the current space plus everything joined to it by open doors,
# indoors or out. Memoised per key since several callers ask for it each redraw.
func lit_cells() -> Dictionary:
	var k := _key()
	if _lit_key == k:
		return _lit_cache
	_lit_key = k
	_lit_cache = _compute_lit()
	return _lit_cache

func _compute_lit() -> Dictionary:
	_ensure_built()
	_lit_ext = false
	var lit := {}
	if not _built:
		return lit
	var open := _open_doors()
	var q: Array = []
	var pc := _player_cell()
	if _is_exterior(pc):
		# player outside: the whole exterior is one lit region, and every room with an
		# open outdoor door joins in
		_lit_ext = true
		for x in range(_box.position.x, _box.position.x + _box.size.x):
			for y in range(_box.position.y, _box.position.y + _box.size.y):
				var c := Vector2i(x, y)
				if _exterior.has(c):
					lit[c] = true
					q.append(c)
	else:
		lit[pc] = true
		q.append(pc)
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for n in _neighbours(c):
			if lit.has(n) or _walls.has(n):
				continue
			if _doorcells.has(n):
				if not open.has(n):
					continue # closed door: a barrier
			elif _is_exterior(n):
				if not _in_box(n):
					continue # unbounded outer exterior: lit implicitly, don't enumerate
				_lit_ext = true # reached the outdoor through an open door
			lit[n] = true
			q.append(n)
	return lit

func _key() -> String:
	var k := str(_player_cell())
	for g in get_tree().get_nodes_in_group("gates"):
		if g.is_open:
			k += "|o" + str(g.cell)
	return k

func _draw() -> void:
	if exterior_lit():
		return # outdoor mode: the shadow manager owns the darkness (unlit rooms shaded,
		# wall shadows on the outdoor). RoomLight only dims for the pure-indoor case.
	var lit := lit_cells()
	if lit.is_empty():
		return
	var half := CELL / 2.0
	var pc := _player_cell()
	for x in range(pc.x - VIEW, pc.x + VIEW + 1):
		for y in range(pc.y - VIEW, pc.y + VIEW + 1):
			var c := Vector2i(x, y)
			if lit.has(c):
				continue # fully lit floor / open doorway
			# A non-lit cell (wall, closed door, exterior) is lit on each quadrant that
			# faces the lit region: a quadrant is lit if any of its two orthogonal or one
			# diagonal neighbour is lit. So wall grass beside a room lights up, a wall
			# between two lit rooms lights on both sides, and corners fill in, while the
			# far side stays dark so no light leaks past the wall.
			var tl: bool = lit.has(Vector2i(x - 1, y)) or lit.has(Vector2i(x, y - 1)) or lit.has(Vector2i(x - 1, y - 1))
			var tr: bool = lit.has(Vector2i(x + 1, y)) or lit.has(Vector2i(x, y - 1)) or lit.has(Vector2i(x + 1, y - 1))
			var bl: bool = lit.has(Vector2i(x - 1, y)) or lit.has(Vector2i(x, y + 1)) or lit.has(Vector2i(x - 1, y + 1))
			var br: bool = lit.has(Vector2i(x + 1, y)) or lit.has(Vector2i(x, y + 1)) or lit.has(Vector2i(x + 1, y + 1))
			var ox := x * CELL
			var oy := y * CELL
			if not (tl or tr or bl or br):
				draw_rect(Rect2(ox, oy, CELL, CELL), DARK)
			else:
				if not tl:
					draw_rect(Rect2(ox, oy, half, half), DARK)
				if not tr:
					draw_rect(Rect2(ox + half, oy, half, half), DARK)
				if not bl:
					draw_rect(Rect2(ox, oy + half, half, half), DARK)
				if not br:
					draw_rect(Rect2(ox + half, oy + half, half, half), DARK)
