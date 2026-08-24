extends Node

# Window mode toggle. The game LAUNCHES fullscreen (project.godot display/window/size/mode=3) so it
# fills the user's screen; since a fullscreen window has no title bar, this gives a way back to a normal
# desktop window. Toggle with F11 or Alt+Enter (both common; F11 can be grabbed by the OS on some Macs,
# so Alt+Enter is the fallback). Autoloaded, so the shortcut works from any scene. In headless runs no
# input events fire, so this never touches DisplayServer there.

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var toggle: bool = event.keycode == KEY_F11 or (event.alt_pressed and event.keycode == KEY_ENTER)
	if toggle:
		_set_fullscreen(not _is_fullscreen())
		get_viewport().set_input_as_handled()

func _is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
