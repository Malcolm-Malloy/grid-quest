extends Node2D

# The Map Size tool's edge band. Draws one row or column to show what a grow/shrink will do:
# green = the row/column that will be ADDED (just outside the edge, in the void), red = the
# edge row/column that will be REMOVED (the innermost one). The tool strip drives it on button
# hover. It lives under World so it shares the ground's transform and lines up with the cells.
# Green = add and red = remove follow the coloured-highlight palette (ROADMAP).

const CELL := 32
const ADD_FILL := Color(0.35, 0.85, 0.4, 0.35)
const ADD_LINE := Color(0.4, 0.95, 0.5, 0.95)
const DEL_FILL := Color(0.9, 0.32, 0.28, 0.35)
const DEL_LINE := Color(1.0, 0.42, 0.36, 0.95)

# a "+" glyph in the true middle of the add-band so it reads as "add here" at a glance. Only on
# the green add-band, not the red remove-band (which reads clearly as delete on its own).
const PLUS_ARM := 4.5    # half-length of each arm, in on-screen pixels
const PLUS_WIDTH := 2.0  # stroke thickness, on-screen pixels

var _rect := Rect2()
var _fill := Color.TRANSPARENT
var _line := Color.TRANSPARENT
var _add := false # this band is an add-band, so it gets the "+" glyph
var _on := false

func show_band(edge: String, mode: String) -> void:
	var gb = get_node_or_null("../GridBackground")
	if gb == null:
		return
	var w: int = gb.grid_width
	var h: int = gb.grid_height
	var add := mode == "add"
	match edge:
		"top":
			_rect = Rect2(0, (-CELL if add else 0), w * CELL, CELL)
		"bottom":
			_rect = Rect2(0, (h * CELL if add else (h - 1) * CELL), w * CELL, CELL)
		"left":
			_rect = Rect2((-CELL if add else 0), 0, CELL, h * CELL)
		"right":
			_rect = Rect2((w * CELL if add else (w - 1) * CELL), 0, CELL, h * CELL)
		_:
			return
	_fill = ADD_FILL if add else DEL_FILL
	_line = ADD_LINE if add else DEL_LINE
	_add = add
	_on = true
	queue_redraw()

# highlight a SINGLE cell (the single-cell edge-editing grain for non-square maps): green to add
# (a void/hole cell a click will fill), red to remove (a present cell a click will punch out). Shares
# the band's draw + clear path, so only one highlight shows at a time.
func show_cell(cell: Vector2i, mode: String) -> void:
	var add := mode == "add"
	_rect = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
	_fill = ADD_FILL if add else DEL_FILL
	_line = ADD_LINE if add else DEL_LINE
	_add = add
	_on = true
	queue_redraw()

func clear_band() -> void:
	if not _on:
		return
	_on = false
	queue_redraw()

func _draw() -> void:
	if not _on:
		return
	draw_rect(_rect, _fill, true)
	draw_rect(_rect, _line, false, 2.0)
	if _add:
		_draw_plus(_rect.get_center())

# World's y-scale squashes local space vertically, so lengthen the vertical arm to keep the "+"
# looking square on screen. A dark backing stroke keeps it legible over any ground colour.
func _draw_plus(c: Vector2) -> void:
	var ys: float = get_parent().scale.y if get_parent() else 1.0
	var vy: float = PLUS_ARM / ys if ys != 0.0 else PLUS_ARM
	var h0 := c - Vector2(PLUS_ARM, 0)
	var h1 := c + Vector2(PLUS_ARM, 0)
	var v0 := c - Vector2(0, vy)
	var v1 := c + Vector2(0, vy)
	var back := Color(0, 0, 0, 0.5)
	draw_line(h0, h1, back, PLUS_WIDTH + 2.0)
	draw_line(v0, v1, back, PLUS_WIDTH + 2.0)
	draw_line(h0, h1, ADD_LINE, PLUS_WIDTH)
	draw_line(v0, v1, ADD_LINE, PLUS_WIDTH)
