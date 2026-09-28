extends Node

# Autoload singleton: the one place that turns the live level into JSON and back. It stores
# ONLY the source of truth (grid size, spawn, walls, doors, per-quarter floor materials). Everything
# derived (wall/gate meshes, shadows, room lighting, floor fills, the highlight, door open
# state) is recomputed on load, so saves stay small and always consistent.
#
# Maps live in user://maps/<name>.json (persistent, writable, cross-platform). Writes are
# atomic (temp file, then rename) so a crash mid-save can't corrupt an existing map.

const VERSION := 14 # v14: creature spawn zones (region + rate + cap); v13: placed creatures (spawn points + fixed instances); v12: door ids + locks (and pickup instance data); v11: placed item pickups; v10: sparse absent_cells (jagged/non-square maps); v9: per-quarter liquid river-bank OFF flags; v8: bridges (crossable decks over water); v7: per-quarter floor patterns; v6: per-cell wall materials; v5: per-quarter floor tints; v4: per-door authored open+swing; v3: per-cell wall colours; v2: per-quarter floor "quads"; v1: per-room "floors"
const DIR := "user://maps"
const LAST_FILE := "user://last_map.txt" # remembers the map to reload on next launch

# on startup we auto-reload the last saved/loaded map. The capture harness turns this off so
# its GQ_LOAD tests stay deterministic.
var auto_load := true

# --- current map + unsaved-changes (dirty) state, for the New / Save / recovery flow ---
const CELL := Grid.CELL                 # cell size in px, for a blank map's centred spawn

# AUTOSAVE WRITES A RECOVERY SLOT, NOT YOUR MAP (ROADMAP "Unsaved-work protection", decided
# 2026-08-16). The two concepts are kept apart on purpose:
#   explicit Save (the Maps menu) writes the real user://maps/<name>.json,
#   autosave writes user://recovery.json, a SEPARATE slot,
#   the dirty warning guards navigation (New / Load / Quit).
# So a crash is recoverable without the editor ever silently overwriting the map you saved. An
# earlier build (2026-08-17) autosaved straight over the real file every 30s, which meant a saved
# map could not be gone back to -- it had already been replaced by the edits you wanted to abandon.
const RECOVERY_FILE := "user://recovery.json"
const RECOVERY_IDLE_SEC := 3.0   # write this long after you STOP editing (the debounce)
const RECOVERY_MAX_SEC := 120.0  # ...and at least this often through a long unbroken editing run
signal dirty_changed(is_dirty: bool) # so the menu can show/clear the unsaved marker live
signal recovery_written(map_name: String) # so the menu can flash a note
# raised once at launch when a recovery slot is newer than the map it belongs to, so the UI can offer
# to restore it. Carries the snapshot, since auto-loading the last map clears the file itself.
signal recovery_available(map_name: String, at: int)
var dirty := false               # true when the live map has edits not yet written to disk
var autosave_enabled := true
var _current := ""               # current map NAME in memory ("" = unsaved / new); the menu's "current"
var _idle := 0.0                 # since the last edit
var _since_write := 0.0          # since the last recovery write
var _recovery_stale := false     # there are edits the recovery slot does not have yet
var _pending_recovery := {}      # a launch-time recovery snapshot waiting to be offered

func _ready() -> void:
	# Read the recovery slot BEFORE anything touches it: the auto-load below clears it (loading a map
	# supersedes whatever was being recovered), so the snapshot has to be taken first.
	_pending_recovery = _read_recovery()
	await get_tree().process_frame # let the main scene's world finish building first
	if auto_load:
		var last := get_last()
		if last != "" and FileAccess.file_exists(_path(last)):
			load_map(last)
	if not _pending_recovery.is_empty() and _recovery_is_newer(_pending_recovery):
		recovery_available.emit(String(_pending_recovery.get("map", "")), int(_pending_recovery.get("at", 0)))
	else:
		_pending_recovery = {} # nothing worth offering; a stale slot is not a prompt

# The recovery loop, on the decided cadence: a short IDLE debounce so work is captured almost as soon
# as you pause, plus a periodic fallback so an unbroken hour of editing is not one unwritten blob.
# Unlike the old autosave this covers an UNNAMED map too -- that is the case where a crash costs the
# most, since there is no saved file to fall back on at all.
func _process(delta: float) -> void:
	if not autosave_enabled or not dirty or not _recovery_stale:
		return
	_idle += delta
	_since_write += delta
	if _idle >= RECOVERY_IDLE_SEC or _since_write >= RECOVERY_MAX_SEC:
		write_recovery()

# --- node lookup (works whether the scene root is main.tscn or the capture harness) ---

func _world() -> Node:
	var obs := get_tree().get_first_node_in_group("obstacles")
	return obs.get_parent() if obs else null

# --- serialize the live level to the versioned dict ---

func serialize() -> Dictionary:
	var w := _world()
	# each layer owner writes its own slice (to_data): the extent, structures, floors, then the objects
	var out := {"version": VERSION}
	for owner in _layer_owners(w):
		out.merge(owner.to_data())
	# the AUTHORED spawn is the SpawnMarker's position, not wherever the character happens to stand
	# (ROADMAP "Player spawn marker"); older scenes without the marker fall back to the player.
	var marker := w.get_node_or_null("SpawnMarker") as SpawnMarker
	var p: Vector2 = marker.position if marker else w.get_node("Player").position
	out["spawn"] = {"x": p.x, "y": p.y}
	return out

# the nodes that each own a slice of the map dict (to_data / load_data); Pickups and Creatures may be
# absent from a stripped scene
func _layer_owners(w: Node) -> Array:
	var owners: Array = []
	for n in ["GridBackground", "Obstacles", "FloorManager", "Pickups", "Creatures"]:
		var node := w.get_node_or_null(n)
		if node:
			owners.append(node)
	return owners

# apply a serialize()-shaped dict onto the live level without touching disk. Used by
# MapEdit (grid resize) and, later, undo/redo, which both work by transforming the dict
# and re-applying it through this one rebuild path.
func apply_serialized(data: Dictionary, keep_player := false) -> void:
	_apply(data, keep_player)

# --- in-place rebuild after an editor edit ---
# An edit already changed the live stores (Obstacles' cells, Pickups' records, ...). Rather than
# serialize the whole map and re-apply all of it, respawn only the layers the edit touched. Floors
# never depend on these layers, so they are never rebuilt here.
const REBUILD_STRUCTURES := 1 # walls / doors / bridges -> their nodes, then lighting + shadows
const REBUILD_OBJECTS := 2    # pickups / creatures / zones -> their nodes

func rebuild_live(parts: int) -> void:
	var w := _world()
	if parts & REBUILD_STRUCTURES:
		w.get_node("Obstacles").rebuild()
		w.get_node("RoomTopology").rebuild() # re-floods rooms; lighting + shadows follow its signal
	if parts & REBUILD_OBJECTS:
		var pk := w.get_node_or_null("Pickups") as Pickups
		if pk:
			pk.rebuild()
		var cr := w.get_node_or_null("Creatures") as Creatures
		if cr:
			cr.rebuild()

# --- apply a parsed dict back onto the live level, in dependency order ---
# keep_player: leave the player where it currently stands instead of snapping it to the dict's
# spawn. Undo/redo passes true so history never teleports the player (ROADMAP undo caveat).
func _apply(data: Dictionary, keep_player := false) -> void:
	var w := _world()
	var player: Player = w.get_node("Player")
	# dependency order: the extent first (everything reads bounds), then walls/doors, then the room
	# flood over them, then floors (a v1 map's per-room floors need those rooms), then the objects
	w.get_node("GridBackground").load_data(data)
	w.get_node("Obstacles").load_data(data)
	w.get_node("RoomTopology").rebuild()
	w.get_node("FloorManager").load_data(data)
	for n in ["Pickups", "Creatures"]:
		var node := w.get_node_or_null(n)
		if node:
			node.load_data(data)

	# spawn. The MARKER always follows the map (a resize/undo must move the authored spawn with
	# everything else), while snapping the PLAYER onto it is skipped for undo/redo so history never
	# teleports the character mid-edit. A map load (keep_player false) starts the player on the marker.
	var spawn: Dictionary = data.get("spawn", {"x": player.position.x, "y": player.position.y})
	var p := Vector2(spawn["x"], spawn["y"])
	var marker := w.get_node_or_null("SpawnMarker") as SpawnMarker
	if marker:
		marker.set_spawn(p)
	if not keep_player:
		player.position = p
		player.target_position = p
		player.is_moving = false

# --- the recovery slot (ROADMAP "Unsaved-work protection" -> autosave to a recovery file) ---

# Write the live map to the recovery slot. Same atomic temp-then-rename the real save uses, so a
# crash mid-write cannot leave a half-written slot that then fails to parse when it is needed most.
# The slot records WHICH map it belongs to (or "" for a never-saved one) and WHEN, which is what the
# newer-than check on launch compares against.
func write_recovery() -> bool:
	var payload := {"map": _current, "at": int(Time.get_unix_time_from_system()),
		"version": VERSION, "data": serialize()}
	var tmp := RECOVERY_FILE + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("MapIO: cannot open %s for writing" % tmp)
		return false
	f.store_string(JSON.stringify(payload))
	f.close()
	if FileAccess.file_exists(RECOVERY_FILE):
		DirAccess.remove_absolute(RECOVERY_FILE)
	DirAccess.rename_absolute(tmp, RECOVERY_FILE)
	_idle = 0.0
	_since_write = 0.0
	_recovery_stale = false
	recovery_written.emit(_current)
	return true

func _read_recovery() -> Dictionary:
	if not FileAccess.file_exists(RECOVERY_FILE):
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECOVERY_FILE))
	if typeof(raw) != TYPE_DICTIONARY or not (raw as Dictionary).has("data"):
		return {} # an unreadable slot is not worth offering; it will be overwritten on the next edit
	return raw

# Is this slot worth offering? For a NAMED map, only when it is newer than the file on disk -- if you
# saved after the last autosave there is nothing in it you do not already have. A never-saved map has
# no file to compare against, so any slot for it is worth offering: that work exists nowhere else.
func _recovery_is_newer(rec: Dictionary) -> bool:
	var map_name := String(rec.get("map", ""))
	if map_name == "":
		return true
	var path := _path(map_name)
	if not FileAccess.file_exists(path):
		return true # the map it belongs to is gone; the slot is all that is left of it
	return int(rec.get("at", 0)) > int(FileAccess.get_modified_time(path))

# is there a launch-time recovery waiting to be offered?
func has_recovery() -> bool:
	return not _pending_recovery.is_empty()

# Apply the recovered map. It comes back DIRTY on purpose: recovered work is by definition work that
# was never saved, so the editor must keep saying so until the user actually writes it somewhere.
func restore_recovery() -> bool:
	if _pending_recovery.is_empty():
		return false
	var rec := _pending_recovery
	_pending_recovery = {}
	_apply(rec["data"])
	_current = String(rec.get("map", ""))
	EditHistory.reset()
	mark_dirty()
	clear_recovery()
	return true

func discard_recovery() -> void:
	_pending_recovery = {}
	clear_recovery()

# drop the slot: called whenever its contents stop being the thing worth recovering -- an explicit
# save (the work is in the real file now), a load or a New (the live map has been replaced)
func clear_recovery() -> void:
	if FileAccess.file_exists(RECOVERY_FILE):
		DirAccess.remove_absolute(RECOVERY_FILE)
	_recovery_stale = false
	_idle = 0.0
	_since_write = 0.0

# --- disk I/O ---

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)

func _path(map_name: String) -> String:
	return "%s/%s.json" % [DIR, map_name]

func save_map(map_name: String) -> bool:
	_ensure_dir()
	var path := _path(map_name)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("MapIO: cannot open %s for writing" % tmp)
		return false
	f.store_string(JSON.stringify(serialize(), "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path) # atomic swap in place of the old map
	_set_last(map_name)
	_current = map_name
	_clear_dirty()
	clear_recovery() # the work is in the real file now; the slot has nothing left to protect
	return true

func load_map(map_name: String) -> bool:
	var path := _path(map_name)
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("MapIO: %s is not valid map JSON" % path)
		return false
	# migration hook: future versions convert older dicts up to VERSION here
	if int(data.get("version", 0)) > VERSION:
		push_warning("MapIO: %s was saved by a newer version" % path)
	_apply(data)
	_set_last(map_name)
	_current = map_name
	# a loaded map is a fresh baseline: undo history from the previous map must not carry over
	EditHistory.reset()
	_clear_dirty()
	clear_recovery() # the live map has been replaced; the slot described the old one
	return true

# the map reloaded on next launch (last one saved or loaded)

func get_last() -> String:
	if not FileAccess.file_exists(LAST_FILE):
		return ""
	return FileAccess.get_file_as_string(LAST_FILE).strip_edges()

func _set_last(map_name: String) -> void:
	var f := FileAccess.open(LAST_FILE, FileAccess.WRITE)
	if f:
		f.store_string(map_name)
		f.close()

# is there a saved map by this name? (GameIO checks before pointing a saved game at one)
func has_map(map_name: String) -> bool:
	return map_name != "" and FileAccess.file_exists(_path(map_name))

func list_maps() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for file in d.get_files():
		if file.ends_with(".json"):
			out.append(file.trim_suffix(".json"))
	out.sort()
	return out

func delete_map(map_name: String) -> void:
	var path := _path(map_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if map_name == _current:
		_current = "" # the current map was deleted from under us; it is now unsaved

# --- current map + unsaved-changes (dirty) state ---

# the current map's NAME in memory, or "" when the map is new/unsaved. Authoritative for the menu's
# "current" (get_last() is only the on-disk pointer for launch-reload, which lags a new/unsaved map).
func current() -> String:
	return _current

# mark the live map as having unsaved edits. Called from EditHistory on every committed edit / undo /
# redo, the single choke point through which all authoring changes pass.
func mark_dirty() -> void:
	# every edit restarts the debounce and means the slot is behind again
	_idle = 0.0
	_recovery_stale = true
	if not dirty:
		dirty = true
		dirty_changed.emit(true)

func _clear_dirty() -> void:
	_idle = 0.0
	_since_write = 0.0
	_recovery_stale = false
	if dirty:
		dirty = false
		dirty_changed.emit(false)

# start a fresh blank map: a grass grid at the default size, spawn centred, no walls/doors/floors.
# Unsaved until the user names it (Save As), so _current is cleared and the map is not dirty.
func new_map() -> void:
	_apply(_blank_map())
	_current = ""
	EditHistory.reset()
	_clear_dirty()
	clear_recovery() # the live map is gone; the slot described it, so it is not worth recovering

func _blank_map() -> Dictionary:
	var w := 48
	var h := 32
	return {
		"version": VERSION,
		"grid": {"width": w, "height": h},
		"absent_cells": [],
		"spawn": {"x": w * CELL / 2.0, "y": h * CELL / 2.0},
		"walls": [], "doors": [], "quads": [], "wall_colors": [], "wall_materials": [], "floor_tints": [],
		"floor_patterns": [], "floor_no_bank": [], "pickups": [], "creatures": [], "creature_zones": [],
	}
