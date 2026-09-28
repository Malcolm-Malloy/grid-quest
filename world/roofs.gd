class_name Roofs
extends Node2D

# Roofs over buildings (ROADMAP "Future terrain and world objects" -> Roofs). One roof per BUILDING: the
# rooms RoomTopology finds, joined wherever they share a wall or door, plus that wall/door ring. The roof
# covers the whole footprint and hides (a quick fade) while the player stands inside the building, so the
# interior shows; every other building keeps its roof.
#
# Top/front perspective (see the asset perspective model): the roof sits at wall-cap height, so each
# footprint cell's roof is lifted by WallSegment.WALL_HEIGHT, and a cell on the building's SOUTH edge stops
# at the bottom of the wall cap, then drops a shaded eave. The south walls' front faces (and their doors)
# stay visible below the eave, the way a house reads from the front.
#
# A room ringed by any see-through fence is a pen or paddock, not a building, and gets no roof.
#
# Visibility: always shown in PLAY. In EDIT the roofs would hide the interiors being built, so they show
# only while show_in_edit is on (the tool strip's Show Roofs switch, O).
#
# Derived only: nothing is saved. Rebuilt from RoomTopology.rebuilt and Obstacles.materials_changed.

const CELL := Grid.CELL
const LIFT := WallSegment.WALL_HEIGHT       # the roof sits on the wall caps, this far above the cell
const CAP_BOTTOM := 4.0                     # a wall cap ends this far below its cell's top (WallSegment)
const EAVE := 5.0                           # depth of the shaded eave hanging below a south-edge cap
const FADE := 0.2                           # seconds for a roof to fade fully in or out
const ROW := 6                              # shingle row height (px, World space)
const SHINGLE := 10                         # shingle width
const STAGGER := 5                          # alternate rows shift their seams by this (half a shingle)

const SLATE := Color(0.37, 0.41, 0.49)
const SLATE_LIT := Color(0.45, 0.50, 0.58)  # the top lip of each shingle row catches the light
const SLATE_SEAM := Color(0.27, 0.30, 0.37) # the shadowed bottom of a row and the gaps between shingles
const EDGE := Color(0.20, 0.22, 0.28)       # outline where the roof ends (north / east / west)
const EAVE_FACE := Color(0.23, 0.25, 0.31)
const EAVE_DRIP := Color(0.15, 0.16, 0.20)

signal show_in_edit_changed(on: bool)

var show_in_edit := false:
	set(v):
		if v == show_in_edit:
			return
		show_in_edit = v
		show_in_edit_changed.emit(v)

@onready var _topo: RoomTopology = get_node("../RoomTopology")
@onready var _obstacles: Obstacles = get_node("../Obstacles")
@onready var _player: Player = get_node("../Player")

var _pieces: Array[RoofPiece] = []
var _piece_at := {} # Vector2i floor/door cell -> the RoofPiece over it (walls aren't stood on)

func _ready() -> void:
	z_index = 800 # above everything in the world (walls, gates, the player), below the editor overlays
	_topo.rebuilt.connect(rebuild)
	_obstacles.materials_changed.connect(rebuild)
	rebuild()

# the buildings, as sets of footprint cells (floor + their wall/door rings)
func buildings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _pieces:
		out.append(p.cells)
	return out

# the roof piece over `c`, or null (walls and exterior cells answer null)
func piece_at(c: Vector2i) -> RoofPiece:
	return _piece_at.get(c)

func rebuild() -> void:
	for p in _pieces:
		p.queue_free()
	_pieces.clear()
	_piece_at.clear()
	if not _topo.has_layout():
		return
	# rooms (doors are barriers, so each is one room) and the wall/door ring around each
	var rooms: Array[Dictionary] = []
	var rings: Array[Dictionary] = []
	var seen := {}
	for c: Vector2i in _topo.enclosed_floor_cells():
		if seen.has(c):
			continue
		var room := _topo.room_floor_cells(c)
		for f in room:
			seen[f] = true
		var ring := _ring(room)
		if ring.keys().any(func(w: Vector2i) -> bool: return _is_fence(w)):
			continue # a pen, not a building
		rooms.append(room)
		rings.append(ring)
	# rooms sharing any wall or door cell are one building (union-find over room indexes)
	var parent := range(rooms.size())
	var owner_of := {} # ring cell -> first room that claimed it
	for i in rooms.size():
		for w in rings[i]:
			if owner_of.has(w):
				_union(parent, i, owner_of[w])
			else:
				owner_of[w] = i
	var groups := {} # root -> footprint set
	for i in rooms.size():
		var root := _find(parent, i)
		var cells: Dictionary = groups.get(root, {})
		cells.merge(rooms[i])
		cells.merge(rings[i])
		groups[root] = cells
	for cells: Dictionary in groups.values():
		var p := RoofPiece.new()
		p.cells = cells
		p.alpha = _target_shown()
		add_child(p)
		_pieces.append(p)
		for c: Vector2i in cells:
			if not _topo.is_wall(c):
				_piece_at[c] = p
	_process(0.0) # settle visibility now, not a frame late

# the wall/door cells touching `room` (8-way, so the corners are part of it)
func _ring(room: Dictionary) -> Dictionary:
	var out := {}
	for c: Vector2i in room:
		for dx: int in [-1, 0, 1]:
			for dy: int in [-1, 0, 1]:
				var n := c + Vector2i(dx, dy)
				if _topo.is_wall(n) or _topo.is_door(n):
					out[n] = true
	return out

func _is_fence(c: Vector2i) -> bool:
	return _topo.is_wall(c) and WallSegment.FENCE.has(_obstacles.get_wall_material(c))

static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

static func _union(parent: Array, a: int, b: int) -> void:
	parent[_find(parent, a)] = _find(parent, b)

# one shingle repeat: two rows (the second staggered by half a shingle), each with a lit top lip, a
# shadowed bottom seam and a gap on the left of every shingle. Built once, shared by every roof.
static var _tile: ImageTexture

static func shingle_tile() -> ImageTexture:
	if _tile != null:
		return _tile
	var img := Image.create(SHINGLE, ROW * 2, false, Image.FORMAT_RGBA8)
	img.fill(SLATE)
	for row in 2:
		var y0 := row * ROW
		for x in SHINGLE:
			img.set_pixel(x, y0, SLATE_LIT)
			img.set_pixel(x, y0 + ROW - 1, SLATE_SEAM)
		for y in range(y0 + 1, y0 + ROW - 1):
			img.set_pixel((STAGGER * row) % SHINGLE, y, SLATE_SEAM)
	_tile = ImageTexture.create_from_image(img)
	return _tile

func _target_shown() -> float:
	return 1.0 if EditorMode.is_play() or show_in_edit else 0.0

func _process(delta: float) -> void:
	var shown := _target_shown()
	var inside := piece_at(Grid.cell_of(_player.position))
	var step := delta / FADE if delta > 0.0 else 1.0
	for p in _pieces:
		var target := 0.0 if p == inside else shown
		p.fade_toward(target, step)


# One building's roof: drawn once from its footprint, faded with modulate.
class RoofPiece extends Node2D:
	var cells: Dictionary = {}
	var alpha := 1.0

	func _ready() -> void:
		texture_filter = TEXTURE_FILTER_NEAREST
		texture_repeat = TEXTURE_REPEAT_ENABLED
		_apply_alpha()

	func fade_toward(target: float, step: float) -> void:
		if is_equal_approx(alpha, target):
			return
		alpha = move_toward(alpha, target, step)
		_apply_alpha()

	func _apply_alpha() -> void:
		modulate.a = alpha
		visible = alpha > 0.0
		# a solid roof hides the floor under it, so it occludes the floor-highlight mask like a wall; a
		# fading one doesn't (it would smear the mask's colour key)
		if alpha >= 1.0:
			visibility_layer |= FloorHighlightMask.MASK_BIT
		else:
			visibility_layer &= ~FloorHighlightMask.MASK_BIT

	func _draw() -> void:
		for c: Vector2i in cells:
			var x := float(c.x * CELL)
			var top := float(c.y * CELL)
			var south_edge := not cells.has(c + Vector2i.DOWN)
			var y0 := top - LIFT
			var y1 := top + CAP_BOTTOM if south_edge else top + CELL - LIFT
			_shingles(Rect2(x, y0, CELL, y1 - y0))
			if not cells.has(c + Vector2i.UP):
				draw_rect(Rect2(x, y0, CELL, 1), EDGE)
			if not cells.has(c + Vector2i.LEFT):
				draw_rect(Rect2(x, y0, 1, y1 - y0), EDGE)
			if not cells.has(c + Vector2i.RIGHT):
				draw_rect(Rect2(x + CELL - 1, y0, 1, y1 - y0), EDGE)
			if south_edge:
				draw_rect(Rect2(x, y1, CELL, EAVE - 1), EAVE_FACE)
				draw_rect(Rect2(x, y1 + EAVE - 1, CELL, 1), EAVE_DRIP)

	# slate shingles over `r`, sampled from a tile anchored at the World origin so neighbouring cells join
	# seamlessly (WallSegment._stamp's trick): one draw per cell instead of one per shingle
	func _shingles(r: Rect2) -> void:
		var src := Rect2(fposmod(r.position.x, SHINGLE), fposmod(r.position.y, ROW * 2), r.size.x, r.size.y)
		draw_texture_rect_region(Roofs.shingle_tile(), r, src)
