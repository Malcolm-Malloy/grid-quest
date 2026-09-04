extends CanvasLayer

# The persistent top-right chrome: the EDIT/PLAY toggle and the Exit button. Unlike the tool strip
# (which hides in play), both stay visible in BOTH modes -- play mode must always be leavable, and the
# game launches FULLSCREEN with no title bar (see systems/window_mode.gd), so without an on-screen
# Exit the only ways out are Cmd+Q or dropping out of fullscreen first.
#
# The toggle's label reflects the ACTION it performs, not the current mode: in EDIT it offers "Play",
# in PLAY it offers "Edit". Tab toggles too.
#
# QUITTING GUARDS UNSAVED WORK, per ROADMAP "Unsaved-work protection": on quit with unsaved changes,
# prompt Save / Discard / Cancel. Only when actually dirty -- a clean map exits straight away.

var _button: Button
var _exit: Button
var _confirm: ConfirmationDialog
var _discard_btn: Button # the "quit anyway" escape hatch on the unsaved-changes guard

func _ready() -> void:
	layer = 10 # above the tool strip and save/load chrome
	# both buttons in one right-aligned row, so neither has to know the other's width
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN # extend leftward from the right edge
	row.offset_right = -8
	row.offset_top = 8
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_button = Button.new()
	_button.pressed.connect(func(): EditorMode.toggle())
	row.add_child(_button)

	_exit = Button.new()
	_exit.text = "✕ Exit"
	_exit.tooltip_text = "Close the game"
	_exit.pressed.connect(_on_exit_pressed)
	row.add_child(_exit)

	# Save / Discard / Cancel. ConfirmationDialog gives OK + Cancel, so "Save and Quit" is the OK
	# action (the safe default) and Discard is an extra button: quitting should never silently throw
	# away edits, and the safe choice should be the one your hand is already on.
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Unsaved changes"
	_confirm.dialog_text = "This map has unsaved changes."
	_confirm.ok_button_text = "Save and Quit"
	_discard_btn = _confirm.add_button("Quit without Saving", true, "discard")
	_confirm.confirmed.connect(_save_and_quit)
	_confirm.custom_action.connect(func(action: StringName):
		if action == "discard":
			_quit())
	add_child(_confirm)

	EditorMode.changed.connect(func(_m): _refresh())
	_refresh()

func _refresh() -> void:
	_button.text = "▶ Play (Tab)" if EditorMode.is_edit() else "■ Edit (Tab)"

# quit, but never on top of unsaved edits
func _on_exit_pressed() -> void:
	if MapIO.dirty:
		_confirm.popup_centered()
	else:
		_quit()

# "Save and Quit" only writes when the map has a name; an unsaved NEW map has nowhere to go, so it
# falls back to the Maps menu (M) rather than inventing a filename behind the user's back.
func _save_and_quit() -> void:
	var name := MapIO.current()
	if name == "":
		_confirm.hide()
		var menu := get_tree().get_first_node_in_group("save_load_menu")
		if menu and menu.has_method("open"):
			menu.open()
		return
	MapIO.save_map(name)
	_quit()

func _quit() -> void:
	get_tree().quit()

# Tab flips the mode from anywhere. Ignored while a LineEdit (e.g. the save-name field) has focus so
# it doesn't hijack tab-out, matching the tool-strip shortcut guard.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		EditorMode.toggle()
		get_viewport().set_input_as_handled()
