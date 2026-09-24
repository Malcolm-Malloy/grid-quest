extends Node2D
class_name GridBackground

const CELL_SIZE := Grid.CELL
const FLOOR_TEX := 128 # floor textures are 128x128, tiled by world position

# grid size (vars, not consts, so a loaded map can resize the grid). This is the SINGLE
# source of truth for map dimensions: map_io, floor_manager, and the player all read from
# here rather than keeping their own copies. Default bumped to 48x32 (from 20x14) so real
# levels can be laid out now (see ROADMAP "Map extent and edge editing").
var grid_width := 48
var grid_height := 32

# Cell-existence model for NON-SQUARE (jagged) maps (ROADMAP "Map extent and edge editing" ->
# cell-existence model). The map is a bounding box grid_width x grid_height MINUS this sparse set of
# holes: `absent_cells` lists the in-box cells that are NOT part of the map. An EMPTY set is exactly
# today's solid rectangle, so old maps, the fast render path, and every rectangle assumption keep
# working; a jagged map just lists its missing cells. Keyed by Vector2i, value true (used as a set).
var absent_cells := {}

func set_grid_size(w: int, h: int) -> void:
	grid_width = w
	grid_height = h
	queue_redraw()

# replace the hole set (Vector2i -> true). Called by MapIO on load and MapEdit on single-cell edits.
func set_absent_cells(cells: Dictionary) -> void:
	absent_cells = cells
	queue_redraw()

# true if cell (cx, cy) is part of the map: inside the bounding box AND not a hole. The one predicate
# ground rendering, walkability, and the void look all share, so "what cells exist" has a single answer.
func cell_present(cx: int, cy: int) -> bool:
	return cx >= 0 and cx < grid_width and cy >= 0 and cy < grid_height \
		and not absent_cells.has(Vector2i(cx, cy))

# Walkable bounds in world pixels, derived from the grid. The player clamps movement to
# these so its range always matches the grid edge (beyond the grid is void, not walkable).
func min_walkable_position() -> Vector2:
	return Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)

func max_walkable_position() -> Vector2:
	return Vector2((grid_width - 1) * CELL_SIZE + CELL_SIZE / 2.0, (grid_height - 1) * CELL_SIZE + CELL_SIZE / 2.0)

var ground_texture := preload("res://world/ground_grass.png")

# Out-of-map void look: instead of a jarring pure-black cutoff, the area beyond the grid reads as
# a field of INACTIVE cells (grey tiles, each with a subtle darker-grey "+"), so the edge says
# "buildable void" rather than "hole" (ROADMAP "Beyond the edge"). Tiled on the cell grid and
# clipped to the visible viewport so it always fills the screen without drawing the whole plane.
const VOID_FILL := Color(0.16, 0.16, 0.18)   # dark neutral grey, softer than pure black
const VOID_LINE := Color(0.0, 0.0, 0.0, 0.18) # faint cell separation so tiles read individually
const VOID_PLUS := Color(0.24, 0.24, 0.27)   # subtle, slightly lighter "+" centred in each tile
const VOID_PLUS_ARM := 4.0                    # half arm length in px (pre y-scale)
const VOID_MAX_CELLS := 6000                  # safety cap so a far zoom-out can't draw forever

var _last_view := Transform2D()

# Water shimmer: animated water fills (flagged by FloorManager) get a subtle brightness pulse that moves
# across the surface. AMP is the +/- brightness fraction (kept small so it reads as a gentle shimmer, not
# a flash); SPEED is radians/sec; K spreads the phase by world position so the wave ripples across a body
# instead of pulsing in unison. The floor redraws at ~SHIMMER_HZ only while water is present (else zero cost).
const WATER_SHIMMER_AMP := 0.09
const WATER_SHIMMER_SPEED := 2.2
const WATER_SHIMMER_K := 0.05
const SHIMMER_HZ := 20.0
var _wphase := 0.0   # accumulated shimmer time (sec), advanced while water is on the map
var _waccum := 0.0   # redraw throttle accumulator

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	texture_repeat = TEXTURE_REPEAT_ENABLED # so the ground tiles across grids bigger than the texture
	queue_redraw()

# redraw when the camera pans/zooms so the void tiles keep filling the visible area
func _process(_delta: float) -> void:
	var x := get_global_transform_with_canvas()
	if x != _last_view:
		_last_view = x
		queue_redraw()
	# advance the water shimmer and redraw at ~SHIMMER_HZ, ONLY while the map has water (a dry map never
	# enters this branch, so animation costs nothing). Throttled so it isn't a full per-frame floor redraw.
	var fm := get_node_or_null("../FloorManager")
	if fm != null and fm.has_method("has_animated_water") and fm.has_animated_water():
		_wphase += _delta
		_waccum += _delta
		if _waccum >= 1.0 / SHIMMER_HZ:
			_waccum = 0.0
			queue_redraw()

# the source rect that makes a destination rect sample a 128x128 floor texture tiled by
# world position, so neighbouring pieces line up into one continuous floor (shared by the
# shadow-manager stamp). Works for full cells and half-cell wall quadrants alike.
static func tiled_src(dst: Rect2) -> Rect2:
	return Rect2(fposmod(dst.position.x, float(FLOOR_TEX)), fposmod(dst.position.y, float(FLOOR_TEX)), dst.size.x, dst.size.y)

func _draw() -> void:
	# Beyond the grid: a field of inactive-cell tiles (see _draw_void), drawn first so the ground
	# and floor fills paint over the in-grid part. This replaces the old pure-black cutoff.
	_draw_void()
	# Draw ground ONLY within the grid, tiled to fill it. Everything beyond the grid edge is the
	# inactive-cell void above, so the map edge reads clearly. Previously the full ground texture
	# was blitted at origin, overrunning the walkable area and hiding where the map ends.
	if absent_cells.is_empty():
		# fast path: a solid rectangle blits the whole ground in one tiled draw
		var grid_px := Vector2(grid_width * CELL_SIZE, grid_height * CELL_SIZE)
		draw_texture_rect(ground_texture, Rect2(Vector2.ZERO, grid_px), true)
	else:
		# jagged map: draw ground per cell so holes stay void. Only the present cells get grass; the
		# absent ones fall through to the inactive-cell void drawn above.
		for cy in range(grid_height):
			for cx in range(grid_width):
				if absent_cells.has(Vector2i(cx, cy)):
					continue
				var r := Rect2(cx * CELL_SIZE, cy * CELL_SIZE, CELL_SIZE, CELL_SIZE)
				draw_texture_rect_region(ground_texture, r, tiled_src(r))
	# any room with a floor style fills its WHOLE area (interior cells + the room-facing
	# wall/door quadrants) with that texture, so no grass shows between floor and walls.
	# FloorManager supplies the [dst_rect, texture] pieces; they tile by world position.
	var fm := get_node_or_null("../FloorManager")
	if fm:
		# f = [dst_rect, texture, tint] with an OPTIONAL 4th element = a source-rect override (in
		# texture space) and an OPTIONAL 5th truthy element = ANIMATE (a water fill). Most fills omit
		# both and sample the 128px tile by world position (tiled_src) so neighbours line up; the shoreline
		# autotile passes an atlas src rect instead. Animated water fills get a subtle brightness shimmer
		# that varies by world position + time, so the surface reads as gently rippling rather than a fade.
		for f in fm.base_fills():
			var src: Rect2 = f[3] if f.size() > 3 else tiled_src(f[0])
			var tint: Color = f[2]
			if f.size() > 4 and f[4]:
				var ph: float = _wphase * WATER_SHIMMER_SPEED + (f[0].position.x + f[0].position.y) * WATER_SHIMMER_K
				var pulse: float = 1.0 + WATER_SHIMMER_AMP * sin(ph)
				tint = Color(tint.r * pulse, tint.g * pulse, tint.b * pulse, tint.a)
			draw_texture_rect_region(f[1], f[0], src, tint)
	# the reference grid draws only when toggled on from the floor menu (off by default so
	# it doesn't tint the floor textures the rest of the time)
	if fm and fm.grid_on():
		var color: Color = fm.grid_color()
		for x in range(grid_width + 1):
			draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, grid_height * CELL_SIZE), color, 1.0, true)
		for y in range(grid_height + 1):
			draw_line(Vector2(0, y * CELL_SIZE), Vector2(grid_width * CELL_SIZE, y * CELL_SIZE), color, 1.0, true)

# fill the on-screen void (outside the grid) with inactive-cell tiles: a grey square + faint
# border + a subtle darker "+" per cell. Clipped to the visible viewport so it never draws the
# whole infinite plane; the ground drawn afterwards covers the in-grid cells.
func _draw_void() -> void:
	var vis := _visible_local_rect()
	if vis.size.x <= 0 or vis.size.y <= 0:
		return
	# widen to whole cells so tiles align to the grid
	var cx0 := floori(vis.position.x / CELL_SIZE)
	var cy0 := floori(vis.position.y / CELL_SIZE)
	var cx1 := ceili((vis.position.x + vis.size.x) / CELL_SIZE)
	var cy1 := ceili((vis.position.y + vis.size.y) / CELL_SIZE)
	if (cx1 - cx0) * (cy1 - cy0) > VOID_MAX_CELLS:
		return # zoomed out past the cap: skip rather than stall (rare, edit-time only)
	var ys := scale.y if scale.y != 0.0 else 1.0
	var vy := VOID_PLUS_ARM / ys # counter World's y-scale so the "+" reads square
	for cy in range(cy0, cy1):
		for cx in range(cx0, cx1):
			if cell_present(cx, cy):
				continue # a present cell; the ground covers it. Absent (hole) cells fall through to void.
			var o := Vector2(cx * CELL_SIZE, cy * CELL_SIZE)
			var r := Rect2(o, Vector2(CELL_SIZE, CELL_SIZE))
			draw_rect(r, VOID_FILL, true)
			draw_rect(r, VOID_LINE, false, 1.0)
			var c := o + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
			draw_line(c - Vector2(VOID_PLUS_ARM, 0), c + Vector2(VOID_PLUS_ARM, 0), VOID_PLUS, 1.0)
			draw_line(c - Vector2(0, vy), c + Vector2(0, vy), VOID_PLUS, 1.0)

# the on-screen viewport mapped back into this node's local space (World is scaled/zoomed, so map
# all four screen corners and take their bounds; no rotation is involved).
func _visible_local_rect() -> Rect2:
	var inv := get_global_transform_with_canvas().affine_inverse()
	var s := get_viewport_rect().size
	var a := inv * Vector2(0, 0)
	var b := inv * Vector2(s.x, 0)
	var c := inv * Vector2(0, s.y)
	var d := inv * s
	var mn := Vector2(min(a.x, b.x, c.x, d.x), min(a.y, b.y, c.y, d.y))
	var mx := Vector2(max(a.x, b.x, c.x, d.x), max(a.y, b.y, c.y, d.y))
	return Rect2(mn, mx - mn)
