class_name Roofs
extends Node2D

# Roofs over buildings (ROADMAP "Future terrain and world objects" -> Roofs). One roof per BUILDING: the
# rooms RoomTopology finds, joined wherever they share a wall or door, plus that wall/door ring. The roof
# covers the whole footprint and hides (a quick fade) while the player stands inside the building, so the
# interior shows; every other building keeps its roof.
#
# THE SHAPE: a GABLE with its ridge running NORTH-SOUTH, so the point faces the camera (decided with the
# user 2026-09-29). Drawn in the top/front perspective (see the asset perspective model):
#   - The eaves sit at wall-cap height: each footprint cell's roof is lifted by WallSegment.WALL_HEIGHT, and
#     on the building's SOUTH edge the roof stops at the bottom of the wall cap, so the front walls' faces
#     (and their doors) stay visible below it.
#   - Each ROW of the footprint rises from its west and east ends to a ridge down its middle: height grows
#     by PITCH per pixel inward, and height is drawn as an upward shift, like a wall's cap sits above its
#     cell. So the roof's north edge pokes up in a "^" and the ridge runs down the centre.
#   - The two slopes are TOP faces seen from above: the west slope catches the light (the world is lit from
#     the upper left, which is why shadows fall to the lower right) and the east slope is shaded.
#   - The GABLE END is a south-facing FRONT face: the triangle between the roof's south edge and the eave
#     line, filled with that building's own wall texture and colour at the walls' FACE_SHADE, trimmed with
#     a dark barge board. Rows are drawn north to south, so a nearer section overlaps a farther one, and
#     wherever a row stands taller than the row in front of it (an L or a U), its gable face shows too.
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
const PITCH := 0.25                         # roof rise per pixel of run (drawn as an upward shift)
const FADE := 0.2                           # seconds for a roof to fade fully in or out
const ROW := 6                              # shingle row height (px, World space)
const SHINGLE := 10                         # shingle width
const STAGGER := 5                          # alternate rows shift their seams by this (half a shingle)

const SLATE := Color(0.37, 0.41, 0.49)
const SLATE_LIT := Color(0.45, 0.50, 0.58)  # the top lip of each shingle row catches the light
const SLATE_SEAM := Color(0.27, 0.30, 0.37) # the shadowed bottom of a row and the gaps between shingles
const EDGE := Color(0.20, 0.22, 0.28)       # outline where the roof ends (north / east / west)
const RIDGE := Color(0.52, 0.57, 0.65)      # the ridge cap, lit along its top
const BARGE := Color(0.14, 0.15, 0.19)      # the trim along a gable end's sloping edges
const SLOPE_LIT := Color(1, 1, 1)           # west slope, facing the light
const SLOPE_SHADE := Color(0.72, 0.72, 0.76) # east slope, turned away from it

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
		p.faces = _gable_faces(cells)
		p.face_clip = _face_clip(cells)
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

# the [texture, colour] a gable face above each footprint cell is made of: the building's own wall. A wall
# cell uses itself; a floor or door cell borrows the nearest wall along its row (west first).
func _gable_faces(cells: Dictionary) -> Dictionary:
	var out := {}
	for c: Vector2i in cells:
		var w := c
		for step in [0, -1, 1, -2, 2, -3, 3, -4, 4, -6, 6, -8, 8, -12, 12]:
			var n := c + Vector2i(step, 0)
			if cells.has(n) and _topo.is_wall(n):
				w = n
				break
		var mat := _obstacles.get_wall_material(w) if _topo.is_wall(w) else "stone"
		if WallSegment.FENCE.has(mat):
			mat = "stone"
		var tex: Texture2D = WallSegment.MATERIALS.get(mat, WallSegment.MATERIALS["stone"])[0]
		var col := _obstacles.get_wall_color(w) if _topo.is_wall(w) else Color.WHITE
		out[c] = [tex, Color(col.r * WallSegment.FACE_SHADE, col.g * WallSegment.FACE_SHADE, col.b * WallSegment.FACE_SHADE)]
	return out

# the side walls are thin rails inside their cells, so the front wall's face stops short of the footprint's
# west and east edges. A gable face is that wall carried up, so it stops at the same x: for each front
# (south-edge) cell at the end of a row run, the x range its wall piece actually covers.
func _face_clip(cells: Dictionary) -> Dictionary:
	var out := {}
	for c: Vector2i in cells:
		if cells.has(c + Vector2i.DOWN) or not _topo.is_wall(c):
			continue
		if cells.has(c + Vector2i.LEFT) and cells.has(c + Vector2i.RIGHT):
			continue
		var lo := INF
		var hi := -INF
		for r: Rect2 in _obstacles.wall_piece_rects({c: true}):
			lo = minf(lo, r.position.x)
			hi = maxf(hi, r.end.x)
		if lo < hi:
			out[c] = Vector2(lo, hi)
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

# one shingle repeat for a slope, laid in SLOPE space: u runs from the eave up toward the ridge, v along
# the ridge. Two courses (the second's joints staggered by half a shingle), each with a lit lip at its
# lower edge, a shadowed seam at its upper edge and a joint between shingles. Built once, shared.
static var _tile: ImageTexture

static func shingle_tile() -> ImageTexture:
	if _tile != null:
		return _tile
	var img := Image.create(ROW * 2, SHINGLE, false, Image.FORMAT_RGBA8)
	img.fill(SLATE)
	for course in 2:
		var u0 := course * ROW
		for v in SHINGLE:
			img.set_pixel(u0, v, SLATE_LIT)
			img.set_pixel(u0 + ROW - 1, v, SLATE_SEAM)
		for u in range(u0 + 1, u0 + ROW - 1):
			img.set_pixel(u, (STAGGER * course) % SHINGLE, SLATE_SEAM)
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

	# per footprint cell: [texture, colour] for a gable face above it (see Roofs._gable_faces)
	var faces: Dictionary = {}
	# front cells at a run's end -> Vector2(x0, x1), the x range their wall face covers (Roofs._face_clip)
	var face_clip: Dictionary = {}
	var _spans: Dictionary = {} # cell -> Vector2(west x, east x) of its row's run, in World px

	func _draw() -> void:
		_spans = _row_spans()
		var rows := {}
		for c: Vector2i in cells:
			rows[c.y] = true
		var order := rows.keys()
		order.sort() # north to south: nearer rows draw over farther ones
		for y: int in order:
			for c: Vector2i in cells:
				if c.y == y:
					_draw_slopes(c)
			for c: Vector2i in cells:
				if c.y == y:
					_draw_face(c)

	# every row of the footprint split into its contiguous runs; each cell maps to its run's [west, east]
	func _row_spans() -> Dictionary:
		var out := {}
		for c: Vector2i in cells:
			if out.has(c):
				continue
			var w := c.x
			while cells.has(Vector2i(w - 1, c.y)):
				w -= 1
			var e := c.x
			while cells.has(Vector2i(e + 1, c.y)):
				e += 1
			var span := Vector2(w * CELL, (e + 1) * CELL)
			for x in range(w, e + 1):
				out[Vector2i(x, c.y)] = span
		return out

	# the roof's height (as an upward shift, px) at World x over cell `c`'s row run; 0 off the footprint
	func _h(c: Vector2i, x: float) -> float:
		if not _spans.has(c):
			return 0.0
		var sp: Vector2 = _spans[c]
		return maxf(minf(x - sp.x, sp.y - x), 0.0) * PITCH

	func _ridge_x(c: Vector2i) -> float:
		var sp: Vector2 = _spans[c]
		return (sp.x + sp.y) / 2.0

	# the eave line (roof height 0) at the north and south of cell `c`, in World y
	func _eave_top(c: Vector2i) -> float:
		return c.y * CELL - LIFT

	func _eave_bottom(c: Vector2i) -> float:
		var top := float(c.y * CELL)
		return top + CAP_BOTTOM if not cells.has(c + Vector2i.DOWN) else top + CELL - LIFT

	# cell `c`'s x range cut at its ridge, if the ridge crosses it
	func _cuts(c: Vector2i) -> Array[float]:
		var a := float(c.x * CELL)
		var b := a + CELL
		var out: Array[float] = [a]
		var rx := _ridge_x(c)
		if rx > a and rx < b:
			out.append(rx)
		out.append(b)
		return out

	func _draw_slopes(c: Vector2i) -> void:
		var y0 := _eave_top(c)
		var y1 := _eave_bottom(c)
		var sp: Vector2 = _spans[c]
		var rx := _ridge_x(c)
		var xs := _cuts(c)
		for i in xs.size() - 1:
			var p := xs[i]
			var q := xs[i + 1]
			var west := q <= rx
			var hp := _h(c, p)
			var hq := _h(c, q)
			var pts := PackedVector2Array([Vector2(p, y0 - hp), Vector2(q, y0 - hq), Vector2(q, y1 - hq), Vector2(p, y1 - hp)])
			# slope space: u from this side's eave toward the ridge, v along the ridge (World y)
			var up := (p - sp.x) if west else (sp.y - p)
			var uq := (q - sp.x) if west else (sp.y - q)
			var tw := float(ROW * 2)
			var th := float(SHINGLE)
			var uvs := PackedVector2Array([Vector2(up / tw, y0 / th), Vector2(uq / tw, y0 / th),
					Vector2(uq / tw, y1 / th), Vector2(up / tw, y1 / th)])
			draw_colored_polygon(pts, SLOPE_LIT if west else SLOPE_SHADE, uvs, Roofs.shingle_tile())
			if not cells.has(c + Vector2i.UP):
				draw_line(pts[0], pts[1], EDGE, 1.0) # the roof's far (north) edge
		# the ridge cap, and the side eaves where the run ends
		if rx >= xs[0] and rx < xs[xs.size() - 1]:
			var hr := _h(c, rx)
			draw_line(Vector2(rx, y0 - hr), Vector2(rx, y1 - hr), RIDGE, 2.0)
		if is_equal_approx(xs[0], sp.x):
			draw_line(Vector2(xs[0] + 0.5, y0), Vector2(xs[0] + 0.5, y1), EDGE, 1.0)
		if is_equal_approx(xs[xs.size() - 1], sp.y):
			draw_line(Vector2(sp.y - 0.5, y0), Vector2(sp.y - 0.5, y1), EDGE, 1.0)

	# the south-facing face below cell `c`'s roof: from its height down to the roof in front of it (or to the
	# eave line, on the building's front), wherever this row stands taller
	func _draw_face(c: Vector2i) -> void:
		var below := c + Vector2i.DOWN
		var y := _eave_bottom(c)
		var xs := _cuts(c)
		if cells.has(below):
			var rb := _ridge_x(below)
			if rb > xs[0] and rb < xs[xs.size() - 1] and not xs.has(rb):
				xs.append(rb)
				xs.sort()
		if face_clip.has(c):
			var clip: Vector2 = face_clip[c]
			var kept: Array[float] = [maxf(xs[0], clip.x)]
			for x in xs:
				if x > kept[0] and x < minf(xs[xs.size() - 1], clip.y):
					kept.append(x)
			kept.append(minf(xs[xs.size() - 1], clip.y))
			xs = kept
		# split further where the two profiles cross, so every piece is one simple quad or triangle
		var pts_x: Array[float] = []
		for i in xs.size() - 1:
			var p := xs[i]
			var q := xs[i + 1]
			pts_x.append(p)
			var dp := _h(c, p) - _h(below, p)
			var dq := _h(c, q) - _h(below, q)
			if dp * dq < 0.0:
				pts_x.append(p + (q - p) * dp / (dp - dq))
		pts_x.append(xs[xs.size() - 1])
		var face: Array = faces.get(c, [null, Color.WHITE])
		var tex: Texture2D = face[0]
		for i in pts_x.size() - 1:
			var p := pts_x[i]
			var q := pts_x[i + 1]
			var up := _h(c, p)
			var uq := _h(c, q)
			var lp := minf(_h(below, p), up)
			var lq := minf(_h(below, q), uq)
			if up - lp <= 0.01 and uq - lq <= 0.01:
				continue
			var pts := PackedVector2Array()
			pts.append(Vector2(p, y - up))
			pts.append(Vector2(q, y - uq))
			if uq - lq > 0.01:
				pts.append(Vector2(q, y - lq))
			if up - lp > 0.01:
				pts.append(Vector2(p, y - lp))
			var uvs := PackedVector2Array()
			if tex != null:
				for v in pts:
					uvs.append(Vector2(v.x / tex.get_width(), v.y / tex.get_height()))
			draw_colored_polygon(pts, face[1], uvs, tex)
			draw_line(pts[0], pts[1], BARGE, 2.0) # the barge board along the gable's sloping edge
