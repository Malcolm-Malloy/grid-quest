extends CanvasLayer

# The persistent editor tool strip (left side). Laid out as collapsible ACCORDION sections (ROADMAP
# "Editor UX revisions" -> accordion left menu): a "Tools" section (the authoring-mode radio group,
# expanded by default) and an "Advanced" section (the Map Size edge controls, collapsed by default so
# the strip stays short for most users, per "remove Map Size from the menu -> Advanced"). Recenter sits
# below, always visible. Map Size grows/shrinks the map at each edge via MapEdit and previews the
# affected row/column on the GridBackground (green = will be added, red = will be removed) on hover.

const EDGES := ["top", "bottom", "left", "right"]

# authoring modes, mirrored from FloorManager.Mode (WAND, CELL, FINE, ERASE, WALL, DOOR); the M_*
# order MUST match that enum since set_mode receives the raw index. The strip owns mode selection now
# (it moved off the right-click popup); each has a single-key shortcut. F is Fine Details, so camera
# recenter dropped F and keeps Home (see camera_follow.gd).
enum { M_WAND, M_CELL, M_FINE, M_ERASE, M_WALL, M_DOOR, M_SELECT, M_BOX }
const MODES := [
	["Magic Wand (W)", M_WAND, KEY_W],
	["Box Select (B)", M_BOX, KEY_B],
	["Cell Selector (C)", M_CELL, KEY_C],
	["Fine Details (F)", M_FINE, KEY_F],
	["Erase (E)", M_ERASE, KEY_E],
	["Wall (L)", M_WALL, KEY_L],
	["Door (D)", M_DOOR, KEY_D],
	["Select (S)", M_SELECT, KEY_S],
]
# which modes get a visible button on the strip. ERASE moved fully into the right-click menu + Delete
# key (note: "Erase ... in the right click menu instead"), so it has no strip button (E still works).
# Wall/Door stay on the strip AS WELL as the menu (note: "wall and door ... in the right menu as well"),
# because their DRAG gesture (drag to draw a wall LINE) has no menu equivalent and needs a reachable mode.
const STRIP_MODES := [M_WAND, M_BOX, M_CELL, M_FINE, M_WALL, M_DOOR, M_SELECT]
var _mode_buttons := {} # mode int -> Button, so a keyboard shortcut can light the right radio
var _sections := {}     # section title -> {"header": Button, "content": VBoxContainer}, for the
						# accordion (and so a test can check collapse/expand)
var _level_dd: OptionButton       # the Level picker (switch which saved map is edited)
var _level_confirm: ConfirmationDialog # unsaved-changes guard before a Level switch loads
var _pending_level := ""          # the map a confirmed Level switch will load
# persistent Brush panel: shows/edits the armed floor material + colour without the right-click menu
var _mat_buttons := {}            # floor material value -> Button (radio); the active one is highlighted
var _col_swatches := []           # [{color, button}] clickable floor-colour boxes; active gets a border
var _brush_preview: TextureRect   # floor combined-brush swatch: the armed texture tinted by the colour
var _wall_mat_buttons := {}       # wall material value -> Button (radio)
var _wall_col_swatches := []      # [{color, button}] clickable wall-colour boxes
var _wall_preview: TextureRect    # wall brush swatch: the armed wall cap texture tinted by the colour

func _ready() -> void:
	# the tool strip is editor-only chrome: show it in EDIT, hide it in PLAY (see EditorMode)
	visible = EditorMode.is_edit()
	EditorMode.changed.connect(func(_m): visible = EditorMode.is_edit())
	add_to_group("tool_strip") # so tests / other nodes can find the strip

	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# --- Level picker: switch which saved map is being edited (ROADMAP "Editor UX revisions" -> level
	# dropdown). Lists user://maps; picking a different one loads it (guarded if there are unsaved edits).
	var level_row := HBoxContainer.new()
	var level_lbl := Label.new()
	level_lbl.text = "Level"
	level_row.add_child(level_lbl)
	_level_dd = OptionButton.new()
	_level_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_dd.item_selected.connect(_on_level_selected)
	_level_dd.get_popup().about_to_popup.connect(_refresh_levels) # freshen the list on each open
	level_row.add_child(_level_dd)
	vb.add_child(level_row)
	vb.add_child(HSeparator.new())

	_level_confirm = ConfirmationDialog.new()
	_level_confirm.dialog_text = "You have unsaved changes. Discard them and load?"
	_level_confirm.title = "Unsaved changes"
	_level_confirm.confirmed.connect(func(): _load_level(_pending_level))
	_level_confirm.canceled.connect(_refresh_levels) # cancel restores the dropdown to the current map
	add_child(_level_confirm)

	# --- Tools accordion section (expanded): the SELECTION-mode radio group (action modes live in the
	# right-click menu now; see STRIP_MODES) ---
	var tools := _add_section(vb, "Tools", true)
	var grp := ButtonGroup.new()
	for m in MODES:
		if not (m[1] in STRIP_MODES):
			continue
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.button_group = grp
		b.pressed.connect(_on_mode_pressed.bind(m[1]))
		tools.add_child(b)
		_mode_buttons[m[1]] = b
	_mode_buttons[M_WAND].button_pressed = true # Magic Wand is the default, matching FloorManager
	_refresh_levels()

	# --- Brush accordion section (expanded): the armed floor brush (material + colour), always visible
	# and editable here without opening the right-click menu (ROADMAP "Photoshop-style persistent LEFT
	# panel"). Live-synced to FloorManager via its brush_changed signal.
	var fm := get_node_or_null("../World/FloorManager")
	if fm != null:
		var brush := _add_section(vb, "Brush", true)
		_brush_preview = _fill_brush_section(brush, fm.MENU, 2, _on_brush_material, fm.FLOOR_COLORS, _on_brush_color, _mat_buttons, _col_swatches)
		# --- Wall accordion section: the armed wall brush (material + colour), same two-way binding as
		# the floor Brush (a wall selection reflects here; picking here edits the selection in place) ---
		var wall := _add_section(vb, "Wall", false) # collapsed by default; opens when a wall is selected
		_wall_preview = _fill_brush_section(wall, fm.WALL_MATERIALS, 3, _on_wall_material, fm.WALL_COLORS, _on_wall_color, _wall_mat_buttons, _wall_col_swatches)
		fm.brush_changed.connect(_refresh_brush)
		fm.selection_changed.connect(_on_selection_changed)
		_refresh_brush()

	# --- Advanced accordion section (collapsed): the Map Size edge controls ---
	var adv := _add_section(vb, "Advanced", false)
	var title := Label.new()
	title.text = "Map Size"
	adv.add_child(title)

	# hover-add mode: when on, hovering just outside an edge previews + click-adds that row/column.
	# ON by default (user decision 2026-08-16). Setting button_pressed after connecting fires the
	# handler, which activates MapSizeTool.
	var hover := CheckButton.new()
	hover.text = "Hover-add"
	hover.toggled.connect(_on_hover_toggled)
	adv.add_child(hover)
	hover.button_pressed = true

	for edge in EDGES:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = String(edge).capitalize()
		lbl.custom_minimum_size = Vector2(56, 0)
		row.add_child(lbl)
		row.add_child(_edge_button("+", edge, "add"))
		row.add_child(_edge_button("−", edge, "remove")) # minus sign
		adv.add_child(row)

	# --- Recenter (standalone, always visible below the accordion) ---
	vb.add_child(HSeparator.new())
	var recenter := Button.new()
	recenter.text = "Recenter (Home)"
	recenter.pressed.connect(_recenter)
	vb.add_child(recenter)

# add a collapsible accordion section to `parent`: a header button that folds its content VBox. Returns
# the content VBox for the caller to fill. `expanded` sets the initial state. A ▾/▸ arrow shows state.
func _add_section(parent: Node, title: String, expanded: bool) -> VBoxContainer:
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = expanded
	header.text = _section_label(title, expanded)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.visible = expanded
	header.toggled.connect(func(on: bool):
		content.visible = on
		header.text = _section_label(title, on))
	parent.add_child(header)
	parent.add_child(content)
	_sections[title] = {"header": header, "content": content}
	return content

func _section_label(title: String, expanded: bool) -> String:
	return ("▾ " if expanded else "▸ ") + title

# expand/collapse a section programmatically (drives the header toggle so its arrow + content follow)
func _set_section(title: String, expanded: bool) -> void:
	if _sections.has(title):
		_sections[title]["header"].button_pressed = expanded

# surface the section matching the current selection: a wall selection opens Wall (and folds the floor
# Brush), a floor selection opens Brush (and folds Wall), so the reflected material + colour are visible
# and the panel never overflows with both open. No selection leaves the sections as the user set them.
func _on_selection_changed() -> void:
	var fm := get_node_or_null("../World/FloorManager")
	if fm == null:
		return
	if fm.has_wall_selection():
		_set_section("Wall", true)
		_set_section("Brush", false)
	elif fm.has_floor_selection():
		_set_section("Brush", true)
		_set_section("Wall", false)

# --- Brush panel: swatches + live highlight of the active material/colour ---

# build one brush section's body: a preview swatch, a Material radio grid, and a Colour swatch grid.
# `materials` = Array of [label, value]; `colors` = Array of [label, Color]. `mat_cb`/`col_cb` receive
# the value on click. Records buttons into `mat_out` (value -> Button) and `col_out` ([{color,button}]).
# Returns the preview TextureRect. Shared by the floor Brush and the Wall sections.
func _fill_brush_section(sec: Control, materials: Array, mat_cols: int, mat_cb: Callable, colors: Array, col_cb: Callable, mat_out: Dictionary, col_out: Array) -> TextureRect:
	var pv_box := PanelContainer.new()
	pv_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN # hug the swatch, don't stretch full width
	var pv_sb := StyleBoxFlat.new()
	pv_sb.bg_color = Color(0, 0, 0, 0)
	pv_sb.set_border_width_all(1)
	pv_sb.border_color = Color(0, 0, 0, 0.5)
	pv_sb.set_content_margin_all(2)
	pv_box.add_theme_stylebox_override("panel", pv_sb)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(36, 36) # one tile, roughly cell-sized
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE # let it shrink below the 128px texture
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED # fill the square (crop): grass is 4:3, tiles square
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv_box.add_child(preview)
	sec.add_child(pv_box)
	var mlbl := Label.new()
	mlbl.text = "Material"
	sec.add_child(mlbl)
	var mgrid := GridContainer.new()
	mgrid.columns = mat_cols
	sec.add_child(mgrid)
	var mgrp := ButtonGroup.new()
	for entry in materials:
		var mval: String = entry[1]
		var mb := Button.new()
		mb.text = entry[0]
		mb.toggle_mode = true
		mb.button_group = mgrp
		mb.pressed.connect(mat_cb.bind(mval))
		mgrid.add_child(mb)
		mat_out[mval] = mb
	var clbl := Label.new()
	clbl.text = "Colour"
	sec.add_child(clbl)
	var cgrid := GridContainer.new()
	cgrid.columns = 5
	sec.add_child(cgrid)
	for entry in colors:
		var cval: Color = entry[1]
		var sw := _make_swatch(cval, entry[0])
		sw.pressed.connect(col_cb.bind(cval))
		cgrid.add_child(sw)
		col_out.append({"color": cval, "button": sw})
	return preview

func _make_swatch(color: Color, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(24, 20)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _swatch_box(color, false))
	b.add_theme_stylebox_override("hover", _swatch_box(color, false))
	b.add_theme_stylebox_override("pressed", _swatch_box(color, true))
	return b

func _swatch_box(color: Color, active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(2)
	if active:
		sb.set_border_width_all(3)
		sb.border_color = Color(0.95, 0.85, 0.1) # bright border reads on any swatch colour
	else:
		sb.set_border_width_all(1)
		sb.border_color = Color(0, 0, 0, 0.4)
	return sb

# highlight the active material (radio) + active colour swatch (border) for BOTH the floor Brush and the
# Wall sections, from FloorManager's live state (fires on every brush_changed)
func _refresh_brush() -> void:
	var fm := get_node_or_null("../World/FloorManager")
	if fm == null:
		return
	_refresh_brush_section(_mat_buttons, fm.armed_material(), _col_swatches, fm.active_floor_color(), _brush_preview, fm.armed_brush_texture())
	_refresh_brush_section(_wall_mat_buttons, fm.armed_wall_material(), _wall_col_swatches, fm.active_wall_color(), _wall_preview, fm.armed_wall_texture())

# highlight one section: press the active material radio, border the active colour swatch, and set the
# preview swatch to the armed texture multiplied by the armed colour (so it reads as the real result).
func _refresh_brush_section(mat_buttons: Dictionary, active_mat: String, col_swatches: Array, active_col: Color, preview: TextureRect, tex: Texture2D) -> void:
	if mat_buttons.has(active_mat):
		mat_buttons[active_mat].button_pressed = true
	for s in col_swatches:
		var active: bool = (s["color"] as Color).is_equal_approx(active_col)
		var b: Button = s["button"]
		b.add_theme_stylebox_override("normal", _swatch_box(s["color"], active))
		b.add_theme_stylebox_override("hover", _swatch_box(s["color"], active))
	if preview != null:
		preview.texture = tex
		preview.modulate = active_col

# picking a material/colour in the panel means "I want to paint with it", so drop into a
# painting mode (Cell) if we're not already in one, then arm the brush. In Cell/Fine we leave the
# mode alone so the panel just edits the live brush.
# with a floor selection active, the pick EDITS the selection in place (arm_floor_material/color do the
# fill), so we leave the mode alone. With no selection, picking means "I want to paint", so drop into
# Cell if not already in a painting mode.
func _on_brush_material(mval: String) -> void:
	var fm := get_node_or_null("../World/FloorManager")
	if fm == null:
		return
	if not fm.has_floor_selection() and fm.mode() != M_CELL and fm.mode() != M_FINE:
		_select_mode(M_CELL)
	fm.arm_floor_material(mval)

func _on_brush_color(cval: Color) -> void:
	var fm := get_node_or_null("../World/FloorManager")
	if fm == null:
		return
	if not fm.has_floor_selection() and fm.mode() != M_CELL and fm.mode() != M_FINE:
		_select_mode(M_CELL)
	fm.arm_floor_color(cval)

# wall picks: with a wall selection active they EDIT it in place (arm_wall_* do the fill); otherwise they
# just arm the wall tool. Walls don't use the Cell/Fine paint grain, so no mode switch is needed.
func _on_wall_material(mval: String) -> void:
	var fm := get_node_or_null("../World/FloorManager")
	if fm != null:
		fm.arm_wall_material(mval)

func _on_wall_color(cval: Color) -> void:
	var fm := get_node_or_null("../World/FloorManager")
	if fm != null:
		fm.arm_wall_color(cval)

func _edge_button(text: String, edge: String, mode: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(28, 0)
	b.pressed.connect(_on_press.bind(edge, mode))
	b.mouse_entered.connect(_show_band.bind(edge, mode))
	b.mouse_exited.connect(_clear_band)
	return b

func _on_press(edge: String, mode: String) -> void:
	if mode == "add":
		MapEdit.grow(edge)
	else:
		MapEdit.shrink(edge)
	_show_band(edge, mode) # refresh the preview against the new size

func _show_band(edge: String, mode: String) -> void:
	var eh := get_node_or_null("../World/EdgeHighlight")
	if eh:
		eh.show_band(edge, mode)

func _clear_band() -> void:
	var eh := get_node_or_null("../World/EdgeHighlight")
	if eh:
		eh.clear_band()

func _recenter() -> void:
	var cam := get_node_or_null("../Camera2D")
	if cam and cam.has_method("recenter_on_player"):
		cam.recenter_on_player()

func _on_hover_toggled(on: bool) -> void:
	var mst := get_node_or_null("../World/MapSizeTool")
	if mst:
		mst.active = on

# --- authoring mode selection ---

func _on_mode_pressed(mode: int) -> void:
	var fm := get_node_or_null("../World/FloorManager")
	if fm and fm.has_method("set_mode"):
		fm.set_mode(mode)

# light the radio button for `mode` without re-triggering set_mode. Used when the mode is changed from
# elsewhere (e.g. FloorManager arming the Wall brush from the Build Wall menu) so the strip stays in sync.
func reflect_mode(mode: int) -> void:
	if _mode_buttons.has(mode):
		_mode_buttons[mode].button_pressed = true # setter does not emit pressed, so no recursion

# --- Level picker ---

# rebuild the dropdown from user://maps, selecting the current map (or a leading "(unsaved)" entry when
# the live map has never been saved). Setting OptionButton.selected does not emit item_selected, so this
# never recurses into a load.
func _refresh_levels() -> void:
	if _level_dd == null:
		return
	_level_dd.clear()
	var cur := MapIO.current()
	var sel_idx := 0
	if cur == "":
		_level_dd.add_item("(unsaved)")
	for map_name in MapIO.list_maps():
		_level_dd.add_item(map_name)
		if map_name == cur:
			sel_idx = _level_dd.item_count - 1
	_level_dd.selected = sel_idx

func _on_level_selected(idx: int) -> void:
	var map_name := _level_dd.get_item_text(idx)
	if map_name == "(unsaved)" or map_name == MapIO.current():
		return
	if MapIO.dirty:
		_pending_level = map_name # confirm before discarding unsaved edits
		_level_confirm.popup_centered()
	else:
		_load_level(map_name)

func _load_level(map_name: String) -> void:
	if map_name != "" and map_name != "(unsaved)":
		MapIO.load_map(map_name)
	_refresh_levels()

# light the matching radio and switch the mode, for the keyboard shortcuts below
func _select_mode(mode: int) -> void:
	if _mode_buttons.has(mode):
		_mode_buttons[mode].button_pressed = true # visual only; button_pressed doesn't emit pressed
	_on_mode_pressed(mode)

# W / C / F / E pick the mode. Ignored while a LineEdit (e.g. the save name field) has focus, since
# those events are consumed before reaching _unhandled_key_input.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return
	for m in MODES:
		if event.keycode == m[2]:
			_select_mode(m[1])
			get_viewport().set_input_as_handled()
			return
