extends CanvasLayer

# The one persistent control that flips EditorMode between EDIT and PLAY. Unlike the tool strip (which
# hides in play), this button stays visible in BOTH modes, top-right, so play mode can always be left.
# Tab toggles too. The label reflects the ACTION the button performs, not the current mode:
# in EDIT it offers "Play", in PLAY it offers "Edit".

var _button: Button

func _ready() -> void:
	layer = 10 # above the tool strip and save/load chrome
	_button = Button.new()
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# nudge in from the corner; PRESET_TOP_RIGHT pins the right edge, so offset left/down a little
	_button.offset_right = -8
	_button.offset_top = 8
	_button.offset_left = -128
	_button.pressed.connect(func(): EditorMode.toggle())
	add_child(_button)
	EditorMode.changed.connect(func(_m): _refresh())
	_refresh()

func _refresh() -> void:
	_button.text = "▶ Play (Tab)" if EditorMode.is_edit() else "■ Edit (Tab)"

# Tab flips the mode from anywhere. Ignored while a LineEdit (e.g. the save-name field) has focus so
# it doesn't hijack tab-out, matching the tool-strip shortcut guard.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB:
		EditorMode.toggle()
		get_viewport().set_input_as_handled()
