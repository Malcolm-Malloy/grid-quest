extends Node2D

# Marching-ants selection overlay for the Magic Wand (and later box-select). Draws a translucent
# wash over the selected quarters / walls plus an animated dashed boundary ("marching ants"), so the
# current selection and its scope read at a glance. Lives in World space as a child of FloorManager,
# at a high z_index, exactly like the paint cursor (paint_cursor.gd). The dashed pattern is keyed to
# world coordinates (not per-segment) so dashes stay continuous across collinear edges and corners
# meet; the phase animates in _process to make the ants march. See ROADMAP "Magic Wand" and the
# marching-ants note under "Coloured highlight system".

const HALF := Grid.HALF # a floor quarter
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
var _wash := true           # draw the translucent fill? Off for FLOOR selections (ants only) so the
							# blue wash never tints the floor colour the user is editing; on for walls.

# set the selection to a set of floor quarters (Vector2i in the 16px quarter grid). `occluders` are
# wall sprite rects that cover the floor (cap/face pieces): the wash + ants trace the VISIBLE floor,
# i.e. the quarters MINUS the wall pieces, so the outline hugs the floor the player actually sees
# (including where a wall's drooping front face covers the top of the interior floor).
func set_floor(quads: Dictionary, occluders: Array = []) -> void:
	var floor_rects: Array = []
	for q in quads:
		floor_rects.append(Grid.quad_rect(q))
	var region := _region_from_rects(floor_rects, occluders)
	_fill_rects = region["fills"]
	_edges = region["edges"]
	_wash = false # floor selection: marching ants only, so the true floor colour shows through
	_active = not quads.is_empty()
	queue_redraw()

# set the selection to a set of wall cells (Vector2i in the 32px cell grid); piece_rects are the
# actual wall geometry. Both the wash AND the marching ants now trace the real wall silhouette (the
# union of the cap/face rects), so the ants hug the drawn walls instead of blocky 32px cell squares.
func set_wall(cells: Dictionary, piece_rects: Array) -> void:
	_fill_rects = piece_rects.duplicate()
	_edges = _rect_union_edges(piece_rects)
	_wash = true # wall selection keeps the wash: it reads the 3D wall silhouette better than ants alone
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

# the outline of a UNION of arbitrary axis-aligned rectangles (the wall cap/face pieces), so the
# ants hug the real wall silhouette rather than the cell grid.
func _rect_union_edges(rects: Array) -> Array:
	return _region_from_rects(rects, [])["edges"]

# the VISIBLE region = union(include) MINUS union(exclude), as both a set of sub-cell fill rects
# (for the wash) and its boundary edges (for the ants). Coordinate-compress every include/exclude
# rect edge into a non-uniform sub-grid; a sub-cell is visible when its centre lies in some include
# rect and in NO exclude rect; emit each visible sub-cell edge that borders a non-visible neighbour
# (in true world coords). Collinear sub-edges stay separate but the world-keyed dash pattern keeps
# the ants continuous. Runs once per selection (not per frame), so O(sub-cells * rects) is fine at
# editor scale. Returns {"fills": Array[Rect2], "edges": Array[[Vector2, Vector2]]}.
func _region_from_rects(include: Array, exclude: Array) -> Dictionary:
	if include.is_empty():
		return {"fills": [], "edges": []}
	var xset := {}
	var yset := {}
	for r in include + exclude:
		xset[r.position.x] = true
		xset[r.position.x + r.size.x] = true
		yset[r.position.y] = true
		yset[r.position.y + r.size.y] = true
	var xs: Array = xset.keys(); xs.sort()
	var ys: Array = yset.keys(); ys.sort()
	var filled := {}
	var fills: Array = []
	for i in xs.size() - 1:
		var cx: float = (xs[i] + xs[i + 1]) * 0.5
		for j in ys.size() - 1:
			var cy: float = (ys[j] + ys[j + 1]) * 0.5
			var p := Vector2(cx, cy)
			if not _in_any(include, p) or _in_any(exclude, p):
				continue
			filled[Vector2i(i, j)] = true
			fills.append(Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j]))
	var edges: Array = []
	for key in filled:
		var i: int = key.x
		var j: int = key.y
		var x0: float = xs[i]; var x1: float = xs[i + 1]
		var y0: float = ys[j]; var y1: float = ys[j + 1]
		if not filled.has(Vector2i(i, j - 1)):
			edges.append([Vector2(x0, y0), Vector2(x1, y0)])
		if not filled.has(Vector2i(i, j + 1)):
			edges.append([Vector2(x0, y1), Vector2(x1, y1)])
		if not filled.has(Vector2i(i - 1, j)):
			edges.append([Vector2(x0, y0), Vector2(x0, y1)])
		if not filled.has(Vector2i(i + 1, j)):
			edges.append([Vector2(x1, y0), Vector2(x1, y1)])
	return {"fills": fills, "edges": edges}

func _in_any(rects: Array, p: Vector2) -> bool:
	for r in rects:
		if r.has_point(p):
			return true
	return false

func _draw() -> void:
	if not _active:
		return
	if _wash:
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
