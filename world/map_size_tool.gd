extends Node2D

# Map Size tool (hover-add, rectangular row/column grain). When active, hovering just outside a
# map edge shows the green add-band (that whole row/column) and a left-click grows the map there
# via MapEdit. Remove stays on the tool strip's − buttons for now.
#
# This is the Magic Wand / Line grain from the coloured-highlight plan (whole line). The single-
# cell grain (hover one perimeter cell, make non-square maps) is the next step and needs the
# cell-existence model; see ROADMAP "Map extent and edge editing".
#
# Uses _input (not _unhandled_input) so the void-click is caught before floor_manager's
# _unhandled_input, which consumes every left-click. Tool-strip button clicks are GUI input and
# are handled before _input, so they are never mistaken for a map click.

const CELL := 32
const BAND := 32.0 # how far into the void (px) beyond an edge the add-zone reaches

var active := false
var _edge := "" # currently hovered add edge ("" = none)

func _process(_delta: float) -> void:
	if not active:
		_set_edge("")
		return
	_set_edge(_hovered_edge())

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var edge := _hovered_edge()
		if edge != "":
			MapEdit.grow(edge)
			get_viewport().set_input_as_handled()
			_set_edge(_hovered_edge()) # refresh preview against the new size

func _hovered_edge() -> String:
	var gb = get_node_or_null("../GridBackground")
	if gb == null:
		return ""
	return edge_at(get_local_mouse_position(), gb.grid_width, gb.grid_height)

# which edge's add-zone the point falls in ("" = none). Pure geometry, unit-tested headlessly.
# The zone is the BAND-deep strip of void just outside an edge, within that edge's span (so the
# corners, outside both spans, match nothing).
func edge_at(p: Vector2, gw: int, gh: int) -> String:
	var w := gw * CELL
	var h := gh * CELL
	var in_x := p.x >= 0 and p.x < w
	var in_y := p.y >= 0 and p.y < h
	if in_x and p.y < 0 and p.y >= -BAND:
		return "top"
	if in_x and p.y >= h and p.y < h + BAND:
		return "bottom"
	if in_y and p.x < 0 and p.x >= -BAND:
		return "left"
	if in_y and p.x >= w and p.x < w + BAND:
		return "right"
	return ""

func _set_edge(edge: String) -> void:
	if edge == _edge:
		return
	_edge = edge
	var eh = get_node_or_null("../EdgeHighlight")
	if eh == null:
		return
	if edge == "":
		eh.clear_band()
	else:
		eh.show_band(edge, "add")
