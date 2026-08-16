extends Node2D

# Marching-ants selection overlay for the Magic Wand (and later box-select). Draws a translucent
# wash over the selected quarters / walls plus an animated dashed boundary ("marching ants"), so the
# current selection and its scope read at a glance. Lives in World space as a child of FloorManager,
# at a high z_index, exactly like the paint cursor (paint_cursor.gd). The dashed pattern is keyed to
# world coordinates (not per-segment) so dashes stay continuous across collinear edges and corners
# meet; the phase animates in _process to make the ants march. See ROADMAP "Magic Wand" and the
# marching-ants note under "Coloured highlight system".

const HALF := 16 # a floor quarter
const CELL := 32 # a wall cell
const DASH := 6.0
const PERIOD := DASH * 2.0 # dash + gap
const SPEED := 20.0 # px/sec the ants march

const FILL := Color(0.30, 0.65, 1.0, 0.18)      # cool blue wash, distinct from the red paint cursor
const ANTS_BACK := Color(0.05, 0.05, 0.08, 0.85) # dark backing so the white dashes read on any floor
const ANTS_FORE := Color(1, 1, 1, 0.95)

var _fill_rects: Array = [] # Rect2 to wash
var _edges: Array = []      # [Vector2 a, Vector2 b], axis-aligned, a is the min-coord end
var _phase := 0.0
var _active := false

# set the selection to a set of floor quarters (Vector2i in the 16px quarter grid)
func set_floor(quads: Dictionary) -> void:
	_fill_rects.clear()
	for q in quads:
		_fill_rects.append(Rect2(q.x * HALF, q.y * HALF, HALF, HALF))
	_edges = _boundary_edges(quads, HALF)
	_active = not quads.is_empty()
	queue_redraw()

# set the selection to a set of wall cells (Vector2i in the 32px cell grid); piece_rects are the
# actual wall geometry to wash, while the ants trace the cell boundary (good enough for v1).
func set_wall(cells: Dictionary, piece_rects: Array) -> void:
	_fill_rects = piece_rects.duplicate()
	_edges = _boundary_edges(cells, CELL)
	_active = not cells.is_empty()
	queue_redraw()

func clear() -> void:
	if not _active:
		return
	_fill_rects.clear()
	_edges.clear()
	_active = false
	queue_redraw()

func has_selection() -> bool:
	return _active

func _process(delta: float) -> void:
	if not _active:
		return
	_phase = fposmod(_phase + delta * SPEED, PERIOD)
	queue_redraw()

# the outline of a set of grid squares of side `size`: every edge whose neighbour is not selected.
# Each edge is emitted in the +x (top/bottom) or +y (left/right) direction so `a` is its min end.
func _boundary_edges(cells: Dictionary, size: int) -> Array:
	var edges: Array = []
	for c in cells:
		var x: float = c.x * size
		var y: float = c.y * size
		if not cells.has(c + Vector2i(0, -1)):
			edges.append([Vector2(x, y), Vector2(x + size, y)])
		if not cells.has(c + Vector2i(0, 1)):
			edges.append([Vector2(x, y + size), Vector2(x + size, y + size)])
		if not cells.has(c + Vector2i(-1, 0)):
			edges.append([Vector2(x, y), Vector2(x, y + size)])
		if not cells.has(c + Vector2i(1, 0)):
			edges.append([Vector2(x + size, y), Vector2(x + size, y + size)])
	return edges

func _draw() -> void:
	if not _active:
		return
	for r in _fill_rects:
		draw_rect(r, FILL, true)
	for e in _edges:
		draw_line(e[0], e[1], ANTS_BACK, 2.0)
		_draw_dashes(e[0], e[1])

# draw the "on" dashes of one axis-aligned edge, using a world-coordinate-keyed pattern offset by
# the animated phase so collinear edges share the same dash rhythm and the ants march.
func _draw_dashes(a: Vector2, b: Vector2) -> void:
	var horiz := absf(b.x - a.x) > absf(b.y - a.y)
	var base := a.x if horiz else a.y
	var stop := b.x if horiz else b.y
	var k := floori((base - _phase) / PERIOD)
	while true:
		var on_start := k * PERIOD + _phase
		if on_start > stop:
			break
		var s := maxf(on_start, base)
		var e := minf(on_start + DASH, stop)
		if e > s:
			if horiz:
				draw_line(Vector2(s, a.y), Vector2(e, a.y), ANTS_FORE, 2.0)
			else:
				draw_line(Vector2(a.x, s), Vector2(a.x, e), ANTS_FORE, 2.0)
		k += 1
