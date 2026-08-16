extends CanvasLayer

# The persistent editor tool strip (left side). First occupant: the Map Size control, which
# grows/shrinks the map at each edge via MapEdit and previews the affected row/column on the
# GridBackground (green = will be added, red = will be removed) while a button is hovered. The
# mode tools (Magic Wand / Cell Selector / Fine Details / Erase) will be added to this same
# strip later; this is the foundation they hang on. See ROADMAP "Right-click menu overhaul".

const EDGES := ["top", "bottom", "left", "right"]

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

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
	recenter.text = "Recenter (F)"
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
