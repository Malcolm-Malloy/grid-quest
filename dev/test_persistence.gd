extends "res://dev/test_case.gd"

# Dev-only headless test for Persistence slice 1 (ROADMAP "Persistence & library"): current-map
# tracking, the dirty (unsaved-changes) flag hooked through EditHistory, New Map, and autosave.
# Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_persistence.tscn

func _ready() -> void:
	MapIO.auto_load = false
	MapIO.autosave_enabled = false # drive autosave manually so timing is deterministic
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var gb = main.get_node("World/GridBackground")

	# --- save establishes a current map and a clean (not-dirty) state ---
	MapIO.save_map("_persist_test")
	_check("after save: current is the saved name", MapIO.current() == "_persist_test")
	_check("after save: not dirty", not MapIO.dirty)

	# --- a real edit (committed through EditHistory) marks the map dirty ---
	EditHistory.reset()
	fm.write_quad(Vector2i(4, 4), "wood")
	fm.rebuild()
	EditHistory.commit("paint")
	_check("after an edit: dirty is set", MapIO.dirty)

	# --- undo also counts as an unsaved change; save clears dirty ---
	EditHistory.undo()
	_check("after undo: still dirty (moved off saved state)", MapIO.dirty)
	MapIO.save_map("_persist_test")
	_check("after save: dirty cleared", not MapIO.dirty)

	# --- autosave writes the RECOVERY SLOT, never the real map (ROADMAP "Unsaved-work protection") ---
	MapIO.autosave_enabled = true
	fm.write_quad(Vector2i(5, 5), "tile")
	fm.rebuild()
	EditHistory.commit("paint")
	_check("autosave setup: dirty before tick", MapIO.dirty)
	var saved_before: int = FileAccess.get_modified_time("user://maps/_persist_test.json")
	MapIO._process(MapIO.RECOVERY_IDLE_SEC + 1.0) # force the idle debounce
	_check("autosave: a recovery slot is written", FileAccess.file_exists(MapIO.RECOVERY_FILE))
	# the whole point of the separate slot: your saved map is left exactly as you saved it
	_check("autosave: the REAL map file is untouched",
		FileAccess.get_modified_time("user://maps/_persist_test.json") == saved_before)
	_check("autosave: the map stays marked unsaved (a recovery write is not a save)", MapIO.dirty)
	# ...and an explicit save drops the slot, since the work is in the real file now
	MapIO.save_map("_persist_test")
	_check("saving clears the recovery slot", not FileAccess.file_exists(MapIO.RECOVERY_FILE))
	MapIO.autosave_enabled = false

	# --- New Map: blank grid, centred spawn, no walls/doors/floors, unsaved, not dirty ---
	MapIO.new_map()
	_check("new map: current cleared to unsaved", MapIO.current() == "")
	_check("new map: not dirty", not MapIO.dirty)
	var snap: Dictionary = MapIO.serialize()
	_check("new map: default grid 48x32", int(snap["grid"]["width"]) == 48 and int(snap["grid"]["height"]) == 32)
	_check("new map: no walls", snap["walls"].is_empty())
	_check("new map: no doors", snap["doors"].is_empty())
	_check("new map: no floor quads", snap["quads"].is_empty())
	_check("new map: live grid resized to 48x32", gb.grid_width == 48 and gb.grid_height == 32)

	# --- an UNNAMED map is covered too: it is the case where a crash costs the most, since there is
	# no saved file to fall back on at all. (The old real-file autosave had to skip it; a slot need not.)
	MapIO.autosave_enabled = true
	fm.write_quad(Vector2i(6, 6), "carpet")
	fm.rebuild()
	EditHistory.commit("paint")
	MapIO._process(MapIO.RECOVERY_IDLE_SEC + 1.0)
	_check("recovery: an unnamed map IS captured", FileAccess.file_exists(MapIO.RECOVERY_FILE))
	_check("recovery: it stays unsaved (nothing was written to a map file)", MapIO.dirty and MapIO.current() == "")
	var slot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MapIO.RECOVERY_FILE))
	_check("recovery: the slot records which map it belongs to", String(slot["map"]) == "")
	_check("recovery: ...and when it was written", int(slot["at"]) > 0)
	_check("recovery: ...and the whole map", int(slot["data"]["grid"]["width"]) == 48)

	# the debounce: a write only happens once you PAUSE, and one write is enough until the next edit
	MapIO.clear_recovery()
	fm.write_quad(Vector2i(7, 7), "wood")
	fm.rebuild()
	EditHistory.commit("paint")
	MapIO._process(MapIO.RECOVERY_IDLE_SEC * 0.5)
	_check("recovery: nothing written while you are still editing", not FileAccess.file_exists(MapIO.RECOVERY_FILE))
	MapIO._process(MapIO.RECOVERY_IDLE_SEC * 0.6) # crossing the debounce
	_check("recovery: written once you pause", FileAccess.file_exists(MapIO.RECOVERY_FILE))
	MapIO.clear_recovery()
	MapIO._process(MapIO.RECOVERY_IDLE_SEC + 1.0)
	_check("recovery: no rewrite without a new edit", not FileAccess.file_exists(MapIO.RECOVERY_FILE))

	# the newer-than check decides whether a slot is worth OFFERING on launch
	MapIO.save_map("_persist_recov")
	var rec_old := {"map": "_persist_recov", "at": 1, "data": {}}
	_check("a slot older than its saved map is not offered", not MapIO._recovery_is_newer(rec_old))
	var rec_new := {"map": "_persist_recov", "at": int(Time.get_unix_time_from_system()) + 60, "data": {}}
	_check("a slot newer than its saved map IS offered", MapIO._recovery_is_newer(rec_new))
	_check("a slot for a never-saved map is always offered",
		MapIO._recovery_is_newer({"map": "", "at": 1, "data": {}}))
	_check("a slot whose map has been deleted is still offered",
		MapIO._recovery_is_newer({"map": "_persist_gone", "at": 1, "data": {}}))

	# restoring brings the work back, DIRTY -- recovered work is by definition unsaved
	fm.write_quad(Vector2i(9, 9), "tile")
	fm.rebuild()
	EditHistory.commit("paint")
	MapIO.write_recovery()
	var stash: Dictionary = MapIO._read_recovery()
	MapIO.new_map()
	_check("New clears the recovery slot", not FileAccess.file_exists(MapIO.RECOVERY_FILE))
	MapIO._pending_recovery = stash
	_check("a pending recovery is reported", MapIO.has_recovery())
	MapIO.restore_recovery()
	_check("restoring brings the map back", MapIO.serialize()["quads"].size() > 0)
	_check("...marked unsaved, because it is", MapIO.dirty)
	_check("...and the slot is consumed", not MapIO.has_recovery())
	MapIO.delete_map("_persist_recov")
	MapIO.new_map()

	# the launch OFFER: a slot is never restored silently -- the user may prefer the version they
	# deliberately saved, and only they know which. Check the menu actually raises the choice.
	var menu = get_tree().get_first_node_in_group("save_load_menu")
	_check("the maps menu exists to raise the offer", menu != null)
	if menu != null:
		MapIO.recovery_available.emit("_persist_test", int(Time.get_unix_time_from_system()))
		await get_tree().process_frame
		_check("a recovery offer raises a dialog", menu._recover_dialog != null and menu._recover_dialog.visible)
		_check("...naming the map it belongs to", "_persist_test" in menu._recover_dialog.dialog_text)
		_check("...offering Restore", menu._recover_dialog.ok_button_text == "Restore")
		menu._recover_dialog.hide()
		# an unnamed map has no name to show, so it must not render an empty quoted name
		MapIO.recovery_available.emit("", int(Time.get_unix_time_from_system()))
		await get_tree().process_frame
		_check("...and describing an unsaved new map without an empty name",
			"unsaved new map" in menu._recover_dialog.dialog_text)
		menu._recover_dialog.hide()
		MapIO.discard_recovery()
	MapIO.autosave_enabled = false

	# --- deleting the current map from disk clears the in-memory current pointer ---
	MapIO.save_map("_persist_test2")
	MapIO.delete_map("_persist_test2")
	_check("delete current: current pointer cleared", MapIO.current() == "")

	# cleanup the test map files
	MapIO.delete_map("_persist_test")

	finish()
