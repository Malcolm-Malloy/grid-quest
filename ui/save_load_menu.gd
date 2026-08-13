extends CanvasLayer

# Minimal in-game save/load menu (toggle with the M key). Shows the current map with a Save
# button that overwrites it, a "Save as" field for making a new map, and a list of saved maps
# to load or delete. Ctrl/Cmd+S re-saves the current map without opening the menu. This is the
# roadmap's "load maps from a menu" starting point; character/game saves will extend it. Built
# entirely in code, so there is no separate .tscn to keep in sync.

var _name_edit: LineEdit
var _list: VBoxContainer
var _current_lbl: Label
var _save_btn: Button

func _ready() -> void:
	layer = 100 # above the game and the floor-highlight overlay (layer 90)
	process_mode = Node.PROCESS_MODE_ALWAYS # keep working while the game is paused
	visible = false
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5) # dim the game and swallow clicks behind the menu
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(320, 320)
	bg.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Maps"
	vb.add_child(title)

	# current map + overwrite button
	var cur_row := HBoxContainer.new()
	_current_lbl = Label.new()
	_current_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur_row.add_child(_current_lbl)
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.pressed.connect(_on_save_current)
	cur_row.add_child(_save_btn)
	vb.add_child(cur_row)

	# save as a new named map
	var save_row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "new map name"
	_name_edit.custom_minimum_size = Vector2(210, 0)
	save_row.add_child(_name_edit)
	var save_as := Button.new()
	save_as.text = "Save As"
	save_as.pressed.connect(_on_save_as)
	save_row.add_child(save_as)
	vb.add_child(save_row)

	var lbl := Label.new()
	lbl.text = "Saved maps:"
	vb.add_child(lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 150)
	vb.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close)
	vb.add_child(close_btn)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_M:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S and (event.ctrl_pressed or event.meta_pressed):
		# quick re-save of the current map, no menu needed
		var cur := MapIO.get_last()
		if cur != "":
			MapIO.save_map(cur)
			if visible:
				_refresh()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if visible:
		_close()
	else:
		_open()

func _open() -> void:
	_refresh()
	visible = true
	get_tree().paused = true

func _close() -> void:
	visible = false
	get_tree().paused = false

func _refresh() -> void:
	var cur := MapIO.get_last()
	_current_lbl.text = "Current: " + (cur if cur != "" else "(unsaved)")
	_save_btn.disabled = cur == "" # nothing to overwrite until first save/load
	for c in _list.get_children():
		c.queue_free()
	for map_name in MapIO.list_maps():
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = map_name + (" (current)" if map_name == cur else "")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var load_btn := Button.new()
		load_btn.text = "Load"
		load_btn.pressed.connect(_on_load.bind(map_name))
		row.add_child(load_btn)
		var del_btn := Button.new()
		del_btn.text = "X"
		del_btn.pressed.connect(_on_delete.bind(map_name))
		row.add_child(del_btn)
		_list.add_child(row)

func _on_save_current() -> void:
	var cur := MapIO.get_last()
	if cur != "":
		MapIO.save_map(cur) # overwrites in place
		_refresh()

func _on_save_as() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		return
	MapIO.save_map(n) # becomes the current map
	_name_edit.text = ""
	_refresh()

func _on_load(map_name: String) -> void:
	MapIO.load_map(map_name)
	_close()

func _on_delete(map_name: String) -> void:
	MapIO.delete_map(map_name)
	_refresh()
