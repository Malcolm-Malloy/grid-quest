class_name RoomLight
extends Node2D

# Lights the room the player is in (plus any room reachable through an OPEN door) and
# dims the rest. Which cells are walls, doors, exterior or room floor comes from RoomTopology;
# this node only floods the LIT region over that layout (crossing open doors) and paints the dim.
# Sits just above the floor (below shadows and walls) so only the floor dims.

const CELL := Grid.CELL
const DARK := Color(0.0, 0.0, 0.05, 0.55) # overlay colour for unlit floor
const VIEW := 15 # cells around the player the dim overlay covers (past the camera edge)

@onready var player: Player = get_node("../Player")
@onready var _topo: RoomTopology = get_node("../RoomTopology")
@onready var _shadows: ShadowManager = get_node_or_null("../ShadowGroup")
@onready var _fm: FloorManager = get_node_or_null("../FloorManager")

var last_key := "?"
var _lit_cache: Dictionary = {} # memoised lit_cells for the current key
var _lit_key := "?"
var _lit_ext := false           # does the current lit region include the outdoor

func _ready() -> void:
	_topo.rebuilt.connect(_on_topology_rebuilt)

func _process(_delta: float) -> void:
	var key := _key()
	if key != last_key:
		last_key = key
		queue_redraw()
		# the shadow manager reads the same layout, so it has to redraw in step
		if _shadows:
			_shadows.refresh()

# the walls/doors changed (map load or structure edit): the memoised lit region is stale
func _on_topology_rebuilt() -> void:
	_lit_cache = {}
	_lit_key = "?"
	last_key = "?"
	queue_redraw()
	if _shadows:
		_shadows.refresh()

func _player_cell() -> Vector2i:
	return Grid.cell_of(player.position)

# --- queries used by the shadow manager ---

# true when the lit region includes the outdoor: the player is outside, OR is indoors
# with an open door onto the exterior. Then the room(s) AND the outdoor both light up,
# the same way two rooms both light through the open door between them.
func exterior_lit() -> bool:
	lit_cells() # refreshes the cache and the _lit_ext flag
	return _lit_ext

# room-facing wall/door quadrants of every LIT room. The shadow manager stamps these clean
# in outdoor mode so a lit room's whole enclosing ring reads clean like indoors.
func lit_wall_stamps() -> Array:
	if not _topo.has_layout():
		return []
	var lit := lit_cells()
	var floor := {}
	for c in lit:
		if _topo.is_enclosed_floor(c):
			floor[c] = true
	return _topo.wall_ring_quads(floor)

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
	_lit_ext = false
	var lit := {}
	if not _topo.has_layout():
		return lit
	var open := _open_doors()
	var q: Array = []
	var pc := _player_cell()
	if _topo.is_exterior(pc):
		# player outside: the whole exterior is one lit region, and every room with an
		# open outdoor door joins in
		_lit_ext = true
		for c in _topo.exterior_cells():
			lit[c] = true
			q.append(c)
	else:
		lit[pc] = true
		q.append(pc)
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for n in RoomTopology.neighbours(c):
			if lit.has(n) or _topo.is_wall(n):
				continue
			if _topo.is_door(n):
				if not open.has(n):
					continue # closed door: a barrier
			elif _topo.is_exterior(n):
				if not _topo.in_box(n):
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
	# an active floor selection reads LIT so the colour being edited shows its true (lit) value: a room
	# the player is not standing in is otherwise dimmed, which distorts the picked colour. Copy the cache
	# (never mutate it) and fold the selected cells in, so their wall neighbours light on that side too.
	if _fm != null:
		var sel: Dictionary = _fm.selection.lit_cells()
		if not sel.is_empty():
			lit = lit.duplicate()
			for c in sel:
				lit[c] = true
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
