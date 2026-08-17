extends Node

# Dev-only headless test for Persistence slice 1 (ROADMAP "Persistence & library"): current-map
# tracking, the dirty (unsaved-changes) flag hooked through EditHistory, New Map, and autosave.
# Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_persistence.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

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
	fm._write_quad(Vector2i(4, 4), "wood")
	fm._rebuild()
	EditHistory.commit("paint")
	_check("after an edit: dirty is set", MapIO.dirty)

	# --- undo also counts as an unsaved change; save clears dirty ---
	EditHistory.undo()
	_check("after undo: still dirty (moved off saved state)", MapIO.dirty)
	MapIO.save_map("_persist_test")
	_check("after save: dirty cleared", not MapIO.dirty)

	# --- autosave: a named, dirty map writes on the tick and clears dirty ---
	MapIO.autosave_enabled = true
	fm._write_quad(Vector2i(5, 5), "tile")
	fm._rebuild()
	EditHistory.commit("paint")
	_check("autosave setup: dirty before tick", MapIO.dirty)
	MapIO._process(MapIO.AUTOSAVE_SEC + 1.0) # force the autosave interval
	_check("autosave: dirty cleared after the tick", not MapIO.dirty)
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

	# --- autosave skips an unnamed (new) map even when dirty ---
	MapIO.autosave_enabled = true
	fm._write_quad(Vector2i(6, 6), "carpet")
	fm._rebuild()
	EditHistory.commit("paint")
	MapIO._process(MapIO.AUTOSAVE_SEC + 1.0)
	_check("autosave: an unnamed map is NOT autosaved (stays dirty)", MapIO.dirty)

	# --- deleting the current map from disk clears the in-memory current pointer ---
	MapIO.save_map("_persist_test2")
	MapIO.delete_map("_persist_test2")
	_check("delete current: current pointer cleared", MapIO.current() == "")

	# cleanup the test map files
	MapIO.delete_map("_persist_test")

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
