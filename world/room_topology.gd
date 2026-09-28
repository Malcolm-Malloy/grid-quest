class_name RoomTopology
extends Node

# Which cells are walls, doors, open exterior, or enclosed room floor, and which floor cells make up
# each room. Rooms are discovered by flood fill from the actual wall/door layout, with no hardcoded
# room shapes, so the editor can place arbitrary walls and doors and this keeps working. Layout only:
# a door's OPEN state never changes a room (that is lighting's concern, see RoomLight).
#
# Consumers: RoomLight (the lit flood), ShadowManager (room interiors), FloorManager and SelectionTool
# (room fills, the hover mask, the Magic Wand), the player (indoor shadow size).
#
# Cell model, all derived from Obstacles:
#   wall  - in Obstacles.blocked_cells; a solid barrier.
#   door  - a gate cell; always a room boundary here, whatever its open state.
#   floor - anything else. "exterior" floor is reachable from the map edge without
#           crossing a wall or door; every other floor cell is enclosed room floor.
#
# The layout is built lazily on the first query and again after rebuild(). A map with no walls has
# no layout: every cell reads as exterior and there are no rooms.

signal rebuilt # after rebuild(): the layout changed, so anything derived from rooms is stale

const CELL := Grid.CELL

@onready var _obstacles: Obstacles = get_node("../Obstacles")

var _built := false
var _walls: Dictionary = {}     # Vector2i -> true
var _doorcells: Dictionary = {} # Vector2i -> true (positions, independent of open state)
var _exterior: Dictionary = {}  # Vector2i -> true (floor reachable from the map edge, inside _box)
var _box: Rect2i                # bounding box the exterior flood covers

# throw away the layout and rebuild it from Obstacles' current cells. Called by MapIO after a map load
# or a structure edit (Obstacles' arrays already updated).
func rebuild() -> void:
	_built = false
	_walls = {}
	_doorcells = {}
	_exterior = {}
	_ensure_built()
	rebuilt.emit()

func _ensure_built() -> void:
	if _built or _obstacles == null:
		return
	_walls = {}
	for c in _obstacles.blocked_cells:
		_walls[c] = true
	if _walls.is_empty():
		return # Obstacles not populated yet; retry on the next call
	_doorcells = {}
	for gd in _obstacles.gate_cells:
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
		for n in neighbours(c):
			if not in_box(n) or _exterior.has(n) or _walls.has(n) or _doorcells.has(n):
				continue
			_exterior[n] = true
			q.append(n)

func _seed(c: Vector2i, q: Array) -> void:
	if _exterior.has(c) or _walls.has(c) or _doorcells.has(c):
		return
	_exterior[c] = true
	q.append(c)

# --- cell queries ---

# true once there is a layout to query (builds it on first call). False on a map with no walls.
func has_layout() -> bool:
	_ensure_built()
	return _built

static func neighbours(c: Vector2i) -> Array:
	return [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]

func is_wall(c: Vector2i) -> bool:
	return _walls.has(c)

func is_door(c: Vector2i) -> bool:
	return _doorcells.has(c)

# inside the box the exterior flood enumerates. Everything beyond it is exterior implicitly.
func in_box(c: Vector2i) -> bool:
	return _box.has_point(c)

func is_exterior(c: Vector2i) -> bool:
	if not in_box(c):
		return true
	return _exterior.has(c)

# the exterior cells inside the box (the unbounded rest is never enumerated). Shared, not a copy:
# read it, never mutate it.
func exterior_cells() -> Dictionary:
	_ensure_built()
	return _exterior

func is_enclosed_floor(c: Vector2i) -> bool:
	_ensure_built()
	if not _built:
		return false
	return not _walls.has(c) and not _doorcells.has(c) and not is_exterior(c)

# true when a cell is indoors: enclosed room floor OR a doorway (not a wall, not the
# open exterior). Used to shrink the player's shadow once it steps into a doorway.
func is_indoor(c: Vector2i) -> bool:
	_ensure_built()
	if not _built:
		return false
	return not _walls.has(c) and not is_exterior(c)

# --- room queries ---

# every enclosed room-floor cell (no walls, doors or exterior), across all rooms.
func enclosed_floor_cells() -> Array:
	_ensure_built()
	var out: Array = []
	if not _built:
		return out
	for x in range(_box.position.x, _box.end.x):
		for y in range(_box.position.y, _box.end.y):
			var c := Vector2i(x, y)
			if not _walls.has(c) and not _doorcells.has(c) and not _exterior.has(c):
				out.append(c)
	return out

# floor cells of the single room containing `seed`, treating EVERY door as a barrier, so it stops at
# this room's walls and doors: one room only, never the ones joined through open doors. Empty when
# `seed` is not enclosed floor.
func room_floor_cells(seed: Vector2i) -> Dictionary:
	var out := {}
	if not is_enclosed_floor(seed):
		return out
	out[seed] = true
	var q: Array = [seed]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for n in neighbours(c):
			if out.has(n) or _walls.has(n) or _doorcells.has(n) or is_exterior(n):
				continue
			out[n] = true
			q.append(n)
	return out

# Half-cell rects (World space) for the room-facing quadrants of the wall, corner AND
# door tiles bordering the given floor set. A quadrant is included when it faces a floor
# cell (2 orthogonal + 1 diagonal neighbour), so the outward sides are left out. This is
# how a floor (or a shadow-clean) reaches right up to the walls with no border showing.
func wall_ring_quads(floor: Dictionary) -> Array:
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
