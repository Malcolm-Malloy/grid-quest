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
var _status_lbl: Label            # transient note ("Autosaved", "Saved")
var _confirm: ConfirmationDialog  # unsaved-changes warning before New / Load
var _recover_dialog: ConfirmationDialog # launch-time offer to restore a recovery slot
var _game_lbl: Label          # what the saved game points at ("Continue: <map>")
var _save_game_btn: Button
var _continue_btn: Button
var _pending: Callable            # the action to run once the user confirms discarding edits

func _ready() -> void:
	layer = 100 # above the game and the floor-highlight overlay (layer 90)
	process_mode = Node.PROCESS_MODE_ALWAYS # keep working while the game is paused
	visible = false
	add_to_group("save_load_menu") # so the Exit guard can hand an unnamed map to the Save As field
	_build_ui()
	# live-update the current-map label's unsaved marker, and flash a note when autosave fires
	MapIO.dirty_changed.connect(func(_d): if visible: _refresh_current_label())
	# NOT "Saved": a recovery write does not save your map, and saying so would be a lie the user
	# would act on. The map stays marked unsaved, which is the truth.
	MapIO.recovery_written.connect(func(_n): _flash("Recovery saved"))
	MapIO.recovery_available.connect(_on_recovery_available)

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
	title.tooltip_text = Hotkeys.tip("maps")
	vb.add_child(title)

	# current map + overwrite button + New
	var cur_row := HBoxContainer.new()
	_current_lbl = Label.new()
	_current_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cur_row.add_child(_current_lbl)
	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.pressed.connect(_on_new)
	cur_row.add_child(new_btn)
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.pressed.connect(_on_save_current)
	cur_row.add_child(_save_btn)
	vb.add_child(cur_row)

	# transient status note (autosaved / saved), sits under the current-map row
	_status_lbl = Label.new()
	_status_lbl.modulate = Color(0.6, 0.85, 0.6)
	vb.add_child(_status_lbl)

	# --- Saved game (ROADMAP Phase B item 9). Kept VISUALLY APART from the map rows above, behind a
	# separator and its own heading, because it is a different thing entirely: the rows above save the
	# LEVEL you are building, this saves the PLAYTHROUGH -- where your character is standing in it and
	# what they are carrying. Confusing the two would be the easiest mistake in this menu.
	vb.add_child(HSeparator.new())
	var game_head := Label.new()
	game_head.text = "Saved game"
	vb.add_child(game_head)
	_game_lbl = Label.new()
	_game_lbl.add_theme_font_size_override("font_size", 11)
	_game_lbl.add_theme_color_override("font_color", Color(0.68, 0.71, 0.77))
	vb.add_child(_game_lbl)
	var game_row := HBoxContainer.new()
	_save_game_btn = Button.new()
	_save_game_btn.text = "Save Game"
	_save_game_btn.tooltip_text = "Save where your character is and what they carry, in the current map"
	_save_game_btn.pressed.connect(_on_save_game)
	game_row.add_child(_save_game_btn)
	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.tooltip_text = "Load the saved game: its map, then your character back into it"
	_continue_btn.pressed.connect(_on_continue)
	game_row.add_child(_continue_btn)
	vb.add_child(game_row)
	vb.add_child(HSeparator.new())

	# unsaved-changes warning, shown before New / Load discard the live map
	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "You have unsaved changes. Discard them?"
	_confirm.title = "Unsaved changes"
	_confirm.confirmed.connect(func(): if _pending.is_valid(): _pending.call())
	add_child(_confirm)

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
		var cur := MapIO.current()
		if cur != "":
			MapIO.save_map(cur)
			if visible:
				_flash("Saved")
				_refresh()
		get_viewport().set_input_as_handled()

# open the menu from elsewhere (the Exit button's "Save and Quit" on a never-saved map, which has no
# filename to write to and so hands the user the Save As field instead of inventing one)
# A recovery slot survived from a previous session and is newer than the map it belongs to, so the
# last session ended without saving -- a crash, or a kill. Offer it rather than restoring silently:
# the user may well prefer the version they deliberately saved, and only they know which.
func _on_recovery_available(map_name: String, at: int) -> void:
	if _recover_dialog == null:
		_recover_dialog = ConfirmationDialog.new()
		_recover_dialog.title = "Recover unsaved work"
		_recover_dialog.ok_button_text = "Restore"
		_recover_dialog.add_cancel_button("Discard")
		_recover_dialog.confirmed.connect(func():
			MapIO.restore_recovery()
			_refresh_current_label()
			_flash("Recovered"))
		# Cancel here means "I do not want it", so the slot goes: leaving it would re-offer the same
		# work on every launch after the user has already said no.
		_recover_dialog.canceled.connect(func(): MapIO.discard_recovery())
		add_child(_recover_dialog)
	var when := Time.get_datetime_string_from_unix_time(at, true).replace("T", " ")
	var which := ("\"%s\"" % map_name) if map_name != "" else "an unsaved new map"
	_recover_dialog.dialog_text = ("Grid Quest closed with unsaved changes to %s.\n\nAutosaved %s."
		% [which, when])
	_recover_dialog.popup_centered()

# --- saved game (the PLAYTHROUGH, not the level) ---

# A game save points at the map BY NAME, so it is only as good as the saved map it names. Rather than
# silently writing the map (the trap the recovery-slot work just removed) or saving a reference to
# something that no longer matches, it says so and lets the user decide.
func _on_save_game() -> void:
	if MapIO.current() == "":
		_flash("Name the map first (Save As)")
		return
	if MapIO.dirty:
		_flash("Save the map first")
		return
	if GameIO.save_game():
		_refresh_game_label()
		_flash("Game saved")

func _on_continue() -> void:
	if not GameIO.has_save():
		return
	if GameIO.load_game():
		# a saved game is a moment of PLAY, so it resumes in play rather than dropping you into the
		# editor looking at the map it happens to live in
		EditorMode.set_mode(EditorMode.Mode.PLAY)
		_refresh_current_label()
		_refresh_game_label()
		_flash("Game loaded")
	else:
		_flash("That map is gone")

func _refresh_game_label() -> void:
	if _game_lbl == null:
		return
	var map_name := GameIO.saved_map()
	if map_name == "":
		_game_lbl.text = "No saved game"
		_continue_btn.disabled = true
		return
	var when := Time.get_datetime_string_from_unix_time(GameIO.saved_at(), true).replace("T", " ")
	_game_lbl.text = "%s  --  %s" % [map_name, when]
	_continue_btn.disabled = not MapIO.has_map(map_name)
	if _continue_btn.disabled:
		_game_lbl.text = "%s (map deleted)" % map_name

func open() -> void:
	_open()

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
	_refresh_current_label()
	_refresh_game_label()
	var cur := MapIO.current()
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

# the "Current: <name> *" label, with a trailing * when there are unsaved edits
func _refresh_current_label() -> void:
	var cur := MapIO.current()
	var mark := " *" if MapIO.dirty else ""
	_current_lbl.text = "Current: " + (cur if cur != "" else "(unsaved)") + mark

# briefly show a status note (autosaved / saved), then clear it
func _flash(msg: String) -> void:
	_status_lbl.text = msg
	get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(_status_lbl): _status_lbl.text = "")

# run `action` now, or after confirming if the live map has unsaved edits (New / Load discard it)
func _confirm_if_dirty(action: Callable) -> void:
	if MapIO.dirty:
		_pending = action
		_confirm.popup_centered()
	else:
		action.call()

func _on_new() -> void:
	_confirm_if_dirty(func():
		MapIO.new_map()
		_flash("New map")
		_refresh())

func _on_save_current() -> void:
	var cur := MapIO.current()
	if cur != "":
		MapIO.save_map(cur) # overwrites in place
		_flash("Saved")
		_refresh()

func _on_save_as() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		return
	MapIO.save_map(n) # becomes the current map
	_name_edit.text = ""
	_flash("Saved")
	_refresh()

func _on_load(map_name: String) -> void:
	# discard-warning first: loading replaces the live map and its unsaved edits
	_confirm_if_dirty(func():
		MapIO.load_map(map_name)
		_close())

func _on_delete(map_name: String) -> void:
	MapIO.delete_map(map_name)
	_refresh()
