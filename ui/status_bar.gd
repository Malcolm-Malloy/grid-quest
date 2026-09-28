class_name StatusBar
extends CanvasLayer

# The editor status bar (ROADMAP "Editor layout" -> "A thin status bar"): a strip along the bottom
# showing the live editing state the other chrome does not -- hovered cell, active tool, selection
# size, map dimensions and zoom. Precise placement on a 48x32 grid needs coordinates, and resizing
# needs to see the dimensions change, so this is read-only readout, never a control.
#
# Editor-only chrome, like the tool strip: it hides in PLAY (see EditorMode). The left tool strip
# reserves HEIGHT at the bottom of the window so a full-height strip cannot sit under the bar.
#
# It POLLS rather than subscribing. The hovered cell changes with mouse motion AND with camera pan,
# so there is no one signal to hang it on; a per-frame read of a handful of values is cheaper than
# the plumbing, and the label is only re-set when the composed text actually changes, so a still
# mouse costs nothing downstream.

# The bar's height is whatever the theme's PanelContainer needs around one line of 12px text (36px
# with the default theme), NOT a number we pick: hard-coding one just makes the strip's reservation
# wrong when the theme changes. HEIGHT is only the floor and the pre-instantiation fallback; height()
# below is the truth, and the tool strip asks for it.
const HEIGHT := 24

# the authoring modes are FloorManager's own enum (no local mirror to keep in step)
const Mode := EditorState.Mode

# What each mode is CALLED, in the merged four-tool vocabulary the strip now speaks (Select / Paint /
# Place / Move, see tool_strip.gd): the bar must name the tool the user picked, not the internal mode
# it resolved to, or the readout and the strip would disagree. Erase and Eyedropper have no strip
# button but are still modes you can be in (E / I), so they name themselves.
const TOOL_NAMES := {
	Mode.WAND: "Select", Mode.BOX: "Select", Mode.SELECT: "Select",
	Mode.CELL: "Paint", Mode.FINE: "Paint (Fine)",
	Mode.WALL: "Place: Wall", Mode.DOOR: "Place: Door", Mode.BRIDGE: "Place: Bridge",
	Mode.ITEM: "Place: Item", Mode.SPAWN: "Place: Spawn", Mode.CREATURE: "Place: Creature",
	Mode.MOVE: "Move", Mode.ERASE: "Erase", Mode.EYEDROP: "Eyedropper",
}

const SEP := "   ·   "

var _panel: PanelContainer
var _left: Label   # hovered cell, active tool, selection -- grows rightward from a fixed left edge
var _right: Label  # map size, zoom -- grows leftward from a fixed right edge
var _last_left := ""
var _last_right := ""
# The selection field is the one value that is expensive to derive (a floor selection's cell count
# walks every selected quarter) and the only one that cannot change without announcing itself -- so
# it is the one thing here that is cached off a signal rather than polled each frame.
var _sel_text := ""

func _ready() -> void:
	layer = 8 # below the inspector (9) and the mode toggle (10), above the world
	add_to_group("status_bar")
	visible = EditorMode.is_edit()
	EditorMode.changed.connect(func(_m): visible = EditorMode.is_edit())

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -HEIGHT # a floor, not a cap: the theme's own margins may make it taller
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN # if it is taller, it grows UP, staying flush
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE # a readout is not a target: never steal the hover
	# The default PanelContainer panel is nearly transparent, which left the text washing out over pale
	# floors (verified against a render). A readout has to be readable over ANY map, so the bar brings
	# its own near-opaque dark ground with a hairline top edge to separate it from the world above.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.10, 0.12, 0.92)
	bg.border_color = Color(0.30, 0.33, 0.38, 0.9)
	bg.border_width_top = 1
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", bg)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_panel.add_child(row)

	# The two halves are anchored to opposite edges so neither field DANCES as the other's text
	# changes: only the gap between them moves.
	_left = _make_label()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_left)

	_right = _make_label()
	_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_right)

	var fm := _floor_manager()
	if fm != null:
		EditorState.selection_changed.connect(_on_selection_changed)
	_refresh()

func _on_selection_changed() -> void:
	var fm := _floor_manager()
	_sel_text = fm.selection.summary() if fm != null else ""

# How much room the bar actually takes along the bottom, for whoever has to stay clear of it (the
# tool strip). The COMBINED MINIMUM is what drives the panel's height and, unlike its laid-out size,
# is already correct before the first layout pass -- so an early caller gets the real answer.
func height() -> float:
	return maxf(_panel.get_combined_minimum_size().y, HEIGHT) if _panel != null else float(HEIGHT)

func _make_label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
	return l

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh()

func _refresh() -> void:
	var left := _compose_left()
	if left != _last_left:
		_last_left = left
		_left.text = left
	var right := _compose_right()
	if right != _last_right:
		_last_right = right
		_right.text = right

# hovered cell + active tool + selection size. The selection field is omitted entirely when nothing
# is selected, so the common case stays short rather than reading "Sel: none".
func _compose_left() -> String:
	var fm := _floor_manager()
	if fm == null:
		return ""
	var parts := []
	var cell: Vector2i = fm.hovered_cell()
	# "--" whenever there is no cell to name: off the window, over the UI, or past the map edge. The
	# field never disappears, so the tool/selection fields beside it do not shuffle left.
	parts.append("Cell --" if cell == fm.INVALID_CELL else "Cell %d, %d" % [cell.x, cell.y])
	parts.append(TOOL_NAMES.get(fm.mode(), "?"))
	if _sel_text != "":
		parts.append("Sel " + _sel_text)
	return SEP.join(parts)

# map dimensions + zoom. The dimensions are the BOUNDING BOX, which is the whole story only while the
# map is a full rectangle; once it has holes (the cell-existence model lets you carve jagged maps)
# the box overstates it, so the true cell count is appended in that case and only that case.
func _compose_right() -> String:
	var parts := []
	var gb := get_node_or_null("../World/GridBackground") as GridBackground
	if gb != null:
		var dims := "%d × %d" % [gb.grid_width, gb.grid_height]
		if not gb.absent_cells.is_empty():
			dims += " (%d cells)" % (gb.grid_width * gb.grid_height - gb.absent_cells.size())
		parts.append(dims)
	var cam := get_node_or_null("../Camera2D") as Camera2D
	if cam != null:
		parts.append("%d%%" % roundi(cam.zoom.x * 100.0))
	return SEP.join(parts)

func _floor_manager() -> FloorManager:
	return get_node_or_null("../World/FloorManager")
