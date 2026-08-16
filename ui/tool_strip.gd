extends CanvasLayer

# The persistent editor tool strip (left side). First occupant: the Map Size control, which
# grows/shrinks the map at each edge via MapEdit and previews the affected row/column on the
# GridBackground (green = will be added, red = will be removed) while a button is hovered. The
# mode tools (Magic Wand / Cell Selector / Fine Details / Erase) will be added to this same
# strip later; this is the foundation they hang on. See ROADMAP "Right-click menu overhaul".

const EDGES := ["top", "bottom", "left", "right"]

# authoring modes, mirrored from FloorManager.Mode (WAND, CELL, FINE, ERASE, WALL, DOOR); the M_*
# order MUST match that enum since set_mode receives the raw index. The strip owns mode selection now
# (it moved off the right-click popup); each has a single-key shortcut. F is Fine Details, so camera
# recenter dropped F and keeps Home (see camera_follow.gd).
enum { M_WAND, M_CELL, M_FINE, M_ERASE, M_WALL, M_DOOR, M_SELECT }
const MODES := [
	["Magic Wand (W)", M_WAND, KEY_W],
	["Cell Selector (C)", M_CELL, KEY_C],
	["Fine Details (F)", M_FINE, KEY_F],
	["Erase (E)", M_ERASE, KEY_E],
	["Wall (L)", M_WALL, KEY_L],
	["Door (D)", M_DOOR, KEY_D],
	["Select (S)", M_SELECT, KEY_S],
]
var _mode_buttons := {} # mode int -> Button, so a keyboard shortcut can light the right radio

func _ready() -> void:
	# the tool strip is editor-only chrome: show it in EDIT, hide it in PLAY (see EditorMode)
	visible = EditorMode.is_edit()
	EditorMode.changed.connect(func(_m): visible = EditorMode.is_edit())

	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# --- authoring modes (radio group) ---
	var tools_title := Label.new()
	tools_title.text = "Tools"
	vb.add_child(tools_title)
	var grp := ButtonGroup.new()
	for m in MODES:
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.button_group = grp
		b.pressed.connect(_on_mode_pressed.bind(m[1]))
		vb.add_child(b)
		_mode_buttons[m[1]] = b
	_mode_buttons[M_WAND].button_pressed = true # Magic Wand is the default, matching FloorManager
	vb.add_child(HSeparator.new())

	var title := Label.new()
	title.text = "Map Size"
	vb.add_child(title)

	# hover-add mode: when on, hovering just outside an edge previews + click-adds that row/column.
	# ON by default (user decision 2026-08-16); this toggle moves to an "advanced options" section
	# later, so most users never see it. Setting button_pressed after connecting fires the handler,
	# which activates MapSizeTool.
	var hover := CheckButton.new()
	hover.text = "Hover-add"
	hover.toggled.connect(_on_hover_toggled)
	vb.add_child(hover)
	hover.button_pressed = true

	for edge in EDGES:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = String(edge).capitalize()
		lbl.custom_minimum_size = Vector2(56, 0)
		row.add_child(lbl)
		row.add_child(_edge_button("+", edge, "add"))
		row.add_child(_edge_button("−", edge, "remove")) # minus sign
		vb.add_child(row)

	vb.add_child(HSeparator.new())
	var recenter := Button.new()
	recenter.text = "Recenter (Home)"
	recenter.pressed.connect(_recenter)
	vb.add_child(recenter)

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
