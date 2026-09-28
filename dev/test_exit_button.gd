extends "res://dev/test_case.gd"

# Dev-only headless test for the Exit button (top-right chrome, beside the EDIT/PLAY toggle). The game
# launches fullscreen with no title bar, so this is the on-screen way out -- and quitting must never
# silently discard unsaved edits (ROADMAP "Unsaved-work protection": on quit with unsaved changes,
# prompt Save / Discard / Cancel). Text-only, no rendering; nothing here actually quits.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_exit_button.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var chrome = main.get_node("ModeToggle")
	var menu = get_tree().get_first_node_in_group("save_load_menu")

	# --- 1. the button is there, in both modes (play must always be leavable) ---
	_check("the Exit button exists", chrome._exit != null)
	_check("it is labelled as an exit", "Exit" in chrome._exit.text)
	_check("it sits beside the mode toggle in one row", chrome._exit.get_parent() == chrome._button.get_parent())
	_check("visible in EDIT", chrome._exit.is_visible_in_tree())
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	await get_tree().process_frame
	_check("still visible in PLAY (the tool strip hides, this must not)", chrome._exit.is_visible_in_tree())
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	await get_tree().process_frame

	# --- 2. a clean map exits without nagging ---
	MapIO.dirty = false
	chrome._on_exit_pressed()
	_check("a clean map raises no dialog", not chrome._confirm.visible)

	# --- 3. unsaved edits stop the quit and offer all three ways out ---
	MapIO.dirty = true
	chrome._on_exit_pressed()
	_check("unsaved edits raise the guard instead of quitting", chrome._confirm.visible)
	_check("the safe choice is the default button", chrome._confirm.ok_button_text == "Save and Quit")
	_check("discarding is offered explicitly", chrome._discard_btn != null
		and chrome._discard_btn.text == "Quit without Saving")
	_check("cancelling is offered (ConfirmationDialog's own)", chrome._confirm.get_cancel_button() != null)
	chrome._confirm.hide()

	# --- 4. "Save and Quit" on a NEVER-SAVED map has no filename, so it hands over the Save As field
	# rather than inventing one ---
	MapIO._current = ""
	MapIO.dirty = true
	chrome._save_and_quit()
	# no await here: opening the Maps menu PAUSES the tree, and awaiting a frame under a paused tree
	# never returns in a headless run
	_check("an unnamed map opens the Maps menu instead of quitting", menu != null and menu.visible)
	_check("...and the guard closed behind it", not chrome._confirm.visible)
	menu._close()

	# --- 5. a named map saves to that file, then quits (checked by the file landing on disk) ---
	MapIO._current = "__exit_test"
	MapIO.dirty = true
	MapIO.save_map("__exit_test") # what _save_and_quit does before get_tree().quit()
	_check("a named map has somewhere to save to", FileAccess.file_exists("user://maps/__exit_test.json"))
	_check("saving cleared the dirty flag", not MapIO.dirty)
	DirAccess.remove_absolute("user://maps/__exit_test.json")

	finish()
