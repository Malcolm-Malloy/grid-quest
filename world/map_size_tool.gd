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

const CELL := Grid.CELL
const BAND := 32.0 # how far into the void (px) beyond an edge the add-zone reaches
const M_CELL := 1  # FloorManager.Mode.CELL; the single-cell grain runs in Cell mode

var active := false
var _edge := "" # currently hovered add edge ("" = none, whole row/column grain)
var _cell := Grid.INVALID_CELL # currently hovered addable cell ("" via _no_cell, single grain)
const _NO_CELL := Grid.INVALID_CELL

# single-cell DRAG state: press-and-drag lays a whole strip of edge cells, committed as ONE undo entry
# on release (like a paint stroke), rather than one undo step per cell.
var _dragging := false
var _drag_changed := false

@onready var _fm: FloorManager = get_node_or_null("../FloorManager")
@onready var _grid_bg: GridBackground = get_node_or_null("../GridBackground")
@onready var _edge_highlight = get_node_or_null("../EdgeHighlight")

func _process(_delta: float) -> void:
	# EDIT-only, like every other map tool: this one uses _input (which runs before the GUI), so without
	# the guard its green add-band would sit frozen over a running game AND a click would still resize
	# the map mid-play.
	if EditorMode.is_play():
		_clear()
		return
	# never preview or edit while the pointer is over the editor menu/panels (see _pointer_over_ui):
	# the map size tool uses _input, which runs BEFORE the GUI, so without this it would fire over the menu.
	if not active or _pointer_over_ui():
		_clear()
		return
	# GRAIN by mode: Cell mode adds ONE perimeter cell (non-square maps); the line/wand modes add a
	# whole row/column, per the coloured-highlight plan (ROADMAP "hover-to-add UX").
	if _single_cell_grain():
		_set_edge("")
		# while dragging, keep laying cells the cursor passes over (each add_cell_applied is idempotent:
		# a present cell is a no-op), so a drag along an edge fills a continuous strip
		if _dragging:
			var c := _hovered_cell()
			if c != _NO_CELL and MapEdit.add_cell_applied(c):
				_drag_changed = true
			_set_cell(_hovered_cell()) # re-evaluate against the new size
		else:
			_set_cell(_hovered_cell())
	else:
		_set_cell(_NO_CELL)
		_set_edge(_hovered_edge())

func _input(event: InputEvent) -> void:
	if not active or EditorMode.is_play():
		return # EDIT-only: a click must never resize the map while the game is being played
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# a click that starts over the menu is not a map action (the GUI owns it)
		if event.pressed and _pointer_over_ui():
			return
		if _single_cell_grain():
			if event.pressed:
				# start an add-drag ONLY when the press is over an addable void/hole cell; a press on the
				# open map is left to the painter (so a paint-drag that reaches the edge never adds cells)
				var cell := _hovered_cell()
				if cell == _NO_CELL:
					return
				_dragging = true
				_drag_changed = MapEdit.add_cell_applied(cell)
				get_viewport().set_input_as_handled() # this gesture owns the void; don't also deselect/paint
				_set_cell(_hovered_cell())
			elif _dragging:
				# end the drag: the whole strip is ONE undo entry
				_dragging = false
				if _drag_changed:
					EditHistory.commit("add cells")
					get_viewport().set_input_as_handled()
				_set_cell(_hovered_cell())
			return
		if event.pressed:
			var edge := _hovered_edge()
			if edge != "":
				MapEdit.grow(edge)
				get_viewport().set_input_as_handled()
				_set_edge(_hovered_edge()) # refresh preview against the new size

# true when a GUI Control (the tool strip, inspector, save menu, a popup, ...) is under the cursor, so
# map editing/preview must stand down. Uses the viewport's own hover tracking, which respects each
# Control's mouse_filter (IGNORE controls like the floor-highlight mask don't count).
func _pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

# is the editor in Cell mode? (drives the single-cell grain). Defaults to the row/column grain if the
# FloorManager can't be found, matching the pre-single-cell behaviour.
func _single_cell_grain() -> bool:
	return _fm != null and _fm.has_method("mode") and _fm.mode() == M_CELL

# the addable void/hole cell under the cursor, or _NO_CELL. Uses MapEdit.can_add_cell so the highlight
# only lights where a click would actually add (a perimeter spur or a fillable hole).
func _hovered_cell() -> Vector2i:
	var p := get_local_mouse_position()
	var cell := Grid.cell_of(p)
	return cell if MapEdit.can_add_cell(cell) else _NO_CELL

func _hovered_edge() -> String:
	if _grid_bg == null:
		return ""
	return edge_at(get_local_mouse_position(), _grid_bg.grid_width, _grid_bg.grid_height)

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
	if _edge_highlight == null:
		return
	if edge == "":
		_edge_highlight.clear_band()
	else:
		_edge_highlight.show_band(edge, "add")

func _set_cell(cell: Vector2i) -> void:
	if cell == _cell:
		return
	_cell = cell
	if _edge_highlight == null:
		return
	if cell == _NO_CELL:
		_edge_highlight.clear_band()
	else:
		_edge_highlight.show_cell(cell, "add")

# clear whichever highlight (edge band or single cell) is currently showing
func _clear() -> void:
	_set_edge("")
	_set_cell(_NO_CELL)
