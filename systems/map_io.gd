extends Node

# Autoload singleton: the one place that turns the live level into JSON and back. It stores
# ONLY the source of truth (grid size, spawn, walls, doors, per-quarter floor materials). Everything
# derived (wall/gate meshes, shadows, room lighting, floor fills, the highlight, door open
# state) is recomputed on load, so saves stay small and always consistent.
#
# Maps live in user://maps/<name>.json (persistent, writable, cross-platform). Writes are
# atomic (temp file, then rename) so a crash mid-save can't corrupt an existing map.

const VERSION := 12 # v12: door ids + locks (and pickup instance data); v11: placed item pickups; v10: sparse absent_cells (jagged/non-square maps); v9: per-quarter liquid river-bank OFF flags; v8: bridges (crossable decks over water); v7: per-quarter floor patterns; v6: per-cell wall materials; v5: per-quarter floor tints; v4: per-door authored open+swing; v3: per-cell wall colours; v2: per-quarter floor "quads"; v1: per-room "floors"
const DIR := "user://maps"
const LAST_FILE := "user://last_map.txt" # remembers the map to reload on next launch

# on startup we auto-reload the last saved/loaded map. The capture harness turns this off so
# its GQ_LOAD tests stay deterministic.
var auto_load := true

# --- current map + unsaved-changes (dirty) state, for the New / Save / autosave flow ---
const CELL := 32                 # cell size in px, for a blank map's centred spawn
const AUTOSAVE_SEC := 30.0       # autosave a NAMED map this often while it has unsaved edits
signal dirty_changed(is_dirty: bool) # so the menu can show/clear the unsaved marker live
signal autosaved(map_name: String)   # so the menu can flash an "autosaved" note
var dirty := false               # true when the live map has edits not yet written to disk
var autosave_enabled := true
var _current := ""               # current map NAME in memory ("" = unsaved / new); the menu's "current"
var _autosave_accum := 0.0

func _ready() -> void:
	await get_tree().process_frame # let the main scene's world finish building first
	if auto_load:
		var last := get_last()
		if last != "" and FileAccess.file_exists(_path(last)):
			load_map(last)

# autosave loop: while a NAMED map has unsaved edits, write it to disk every AUTOSAVE_SEC. A new
# (unnamed) map is never autosaved silently; the menu's unsaved-warning guards against losing it.
func _process(delta: float) -> void:
	if not autosave_enabled or _current == "" or not dirty:
		_autosave_accum = 0.0
		return
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_SEC:
		if save_map(_current): # save_map clears dirty and resets the accumulator
			autosaved.emit(_current)

# --- node lookup (works whether the scene root is main.tscn or the capture harness) ---

func _world() -> Node:
	var obs := get_tree().get_first_node_in_group("obstacles")
	return obs.get_parent() if obs else null

# --- serialize the live level to the versioned dict ---

func serialize() -> Dictionary:
	var w := _world()
	var obs = w.get_node("Obstacles")
	var fm = w.get_node("FloorManager")
	var gb = w.get_node("GridBackground")
	var player = w.get_node("Player")
	# the AUTHORED spawn is the SpawnMarker's position, not wherever the character happens to stand
	# (ROADMAP "Player spawn marker"); older scenes without the marker fall back to the player.
	var marker = w.get_node_or_null("SpawnMarker")

	var walls: Array = []
	for c in obs.blocked_cells:
		walls.append([c.x, c.y])
	var doors: Array = []
	for d in obs.gate_cells:
		# v12: a door carries a durable id (a Unique key binds to it) and its authored lock
		var rec := {"cell": [d["cell"].x, d["cell"].y], "orientation": d["orientation"],
			"open": d.get("open", false), "swing": d.get("swing", false), "id": d.get("id", "")}
		if String(d.get("lock", "")) != "":
			rec["lock"] = d["lock"]
			rec["lock_color"] = d.get("lock_color", "red")
			if String(d.get("lock_name", "")) != "":
				rec["lock_name"] = d["lock_name"]
		doors.append(rec)
	# bridges (crossable decks over water) as cell + orientation; a placed-object layer like doors
	var bridges: Array = []
	for b in obs.bridge_cells:
		bridges.append({"cell": [b["cell"].x, b["cell"].y], "orientation": b["orientation"]})
	# floors are stored per 16px quarter: a flat list of [qx, qy, material]. Sparse by design
	# (only painted quarters are written), so save size scales with painted area, not map area.
	var quads: Array = []
	for q in fm._quad_mat:
		quads.append([q.x, q.y, fm._quad_mat[q]])
	# per-cell wall colours as [cx, cy, r, g, b]; sparse (only non-white cells are stored)
	var wall_colors: Array = []
	for c in obs.wall_colors:
		var col: Color = obs.wall_colors[c]
		wall_colors.append([c.x, c.y, col.r, col.g, col.b])
	# per-quarter floor tints as [qx, qy, r, g, b]; sparse (only tinted quarters are stored)
	var floor_tints: Array = []
	for q in fm._quad_tint:
		var fcol: Color = fm._quad_tint[q]
		floor_tints.append([q.x, q.y, fcol.r, fcol.g, fcol.b])
	# per-cell wall materials as [cx, cy, name]; sparse (only non-stone cells are stored)
	var wall_materials: Array = []
	for c in obs.wall_materials:
		wall_materials.append([c.x, c.y, obs.wall_materials[c]])
	# per-quarter floor patterns as [qx, qy, index]; sparse (only non-default indices are stored)
	var floor_patterns: Array = []
	for q in fm._quad_pattern:
		floor_patterns.append([q.x, q.y, fm._quad_pattern[q]])
	# per-quarter LIQUID river-bank OFF flags as [qx, qy]; sparse (only bank-suppressed liquid quarters)
	var floor_no_bank: Array = []
	for q in fm._quad_no_bank:
		floor_no_bank.append([q.x, q.y])
	# placed item pickups as {cell, item, id}: a definition (Items) placed at a cell with a DURABLE id,
	# so a Unique key stays the same key across saves. Whether a character already TOOK one is not here:
	# that is character data (CharacterIO.collected), so the map keeps its items for the editor.
	var pickups: Array = []
	var pk = w.get_node_or_null("Pickups")
	if pk:
		for r in pk.pickups:
			var prec := {"cell": [r["cell"].x, r["cell"].y], "item": r["item"], "id": r["id"]}
			if not r.get("data", {}).is_empty():
				prec["data"] = r["data"] # a unique key's binding: {door_id, name}
			pickups.append(prec)
	# cell-existence holes as [cx, cy]; sparse (only absent cells). Empty = a solid rectangle (v9-and-
	# earlier maps have no key, so they load as the full rect). See GridBackground.absent_cells.
	var absent_cells: Array = []
	for c in gb.absent_cells:
		absent_cells.append([c.x, c.y])

	return {
		"version": VERSION,
		"grid": {"width": gb.grid_width, "height": gb.grid_height},
		"absent_cells": absent_cells,
		"spawn": {"x": marker.position.x if marker else player.position.x,
			"y": marker.position.y if marker else player.position.y},
		"walls": walls,
		"doors": doors,
		"bridges": bridges,
		"quads": quads,
		"wall_colors": wall_colors,
		"wall_materials": wall_materials,
		"floor_tints": floor_tints,
		"floor_patterns": floor_patterns,
		"floor_no_bank": floor_no_bank,
		"pickups": pickups,
	}

# apply a serialize()-shaped dict onto the live level without touching disk. Used by
# MapEdit (grid resize) and, later, undo/redo, which both work by transforming the dict
# and re-applying it through this one rebuild path.
func apply_serialized(data: Dictionary, keep_player := false) -> void:
	_apply(data, keep_player)

# --- apply a parsed dict back onto the live level, in dependency order ---
# keep_player: leave the player where it currently stands instead of snapping it to the dict's
# spawn. Undo/redo passes true so history never teleports the player (ROADMAP undo caveat).
func _apply(data: Dictionary, keep_player := false) -> void:
	var w := _world()
	var gb = w.get_node("GridBackground")
	var obs = w.get_node("Obstacles")
	var rl = w.get_node("RoomLight")
	var fm = w.get_node("FloorManager")
	var player = w.get_node("Player")

	# 1. grid size + cell-existence holes (both define the map's extent, so set them together before
	# anything reads bounds). A pre-v10 map has no "absent_cells" key -> an empty set -> a solid rectangle.
	var grid: Dictionary = data.get("grid", {"width": gb.grid_width, "height": gb.grid_height})
	gb.set_grid_size(int(grid["width"]), int(grid["height"]))
	var absent := {}
	for a in data.get("absent_cells", []):
		absent[Vector2i(int(a[0]), int(a[1]))] = true
	gb.set_absent_cells(absent)

	# 2. walls + doors -> rebuild wall/gate nodes and shadows
	var walls: Array = []
	for a in data.get("walls", []):
		walls.append(Vector2i(int(a[0]), int(a[1])))
	var bridges: Array = []
	for b in data.get("bridges", []):
		bridges.append({"cell": Vector2i(int(b["cell"][0]), int(b["cell"][1])), "orientation": String(b["orientation"])})
	var doors: Array = []
	for d in data.get("doors", []):
		# a pre-v12 door has no id: Obstacles mints one when it spawns the gate, so old maps just work
		var rec := {"cell": Vector2i(int(d["cell"][0]), int(d["cell"][1])), "orientation": d["orientation"],
			"open": bool(d.get("open", false)), "swing": bool(d.get("swing", false)),
			"id": String(d.get("id", ""))}
		if String(d.get("lock", "")) != "":
			rec["lock"] = String(d["lock"])
			rec["lock_color"] = String(d.get("lock_color", "red"))
			rec["lock_name"] = String(d.get("lock_name", ""))
		doors.append(rec)
	obs.apply_map(walls, doors, bridges)

	# 3. lighting (depends on walls/doors)
	rl.rebuild()

	# 4. floors (depends on rooms existing). v2 stores quarters directly; v1 stored per-room
	# styles, migrated here by flood-filling each room's cells into their quarters.
	if int(data.get("version", 1)) >= 2:
		var quads: Array = []
		for a in data.get("quads", []):
			quads.append([int(a[0]), int(a[1]), String(a[2])])
		fm.apply_quads(quads)
	else:
		var floors: Array = []
		for f in data.get("floors", []):
			floors.append({"cell": Vector2i(int(f["cell"][0]), int(f["cell"][1])), "style": f["style"]})
		fm.apply_floors(floors)

	# 4a-pre. floor patterns (v7+). Set BEFORE apply_tints because apply_tints ends with the rebuild
	# that draws them; apply_patterns itself does not rebuild. A pre-v7 map has no "floor_patterns"
	# key, so apply_patterns([]) clears to all-default.
	var fpat: Array = []
	for a in data.get("floor_patterns", []):
		fpat.append([int(a[0]), int(a[1]), int(a[2])])
	fm.apply_patterns(fpat)

	# 4a-pre2. liquid river-bank OFF flags (v9+). Set BEFORE apply_tints' final rebuild, like patterns.
	# A pre-v9 map has no "floor_no_bank" key, so apply_no_bank([]) leaves every liquid with its bank on.
	var nobank: Array = []
	for a in data.get("floor_no_bank", []):
		nobank.append([int(a[0]), int(a[1])])
	fm.apply_no_bank(nobank)

	# 4a. floor tints (v5+; runs after the materials above so the rebuild draws tints over them).
	# A pre-v5 map has no "floor_tints" key, so apply_tints([]) just clears any stale tints.
	var ftints: Array = []
	for a in data.get("floor_tints", []):
		ftints.append([int(a[0]), int(a[1]), float(a[2]), float(a[3]), float(a[4])])
	fm.apply_tints(ftints)

	# 4b. wall colours (walls exist after apply_map; build_world's deferred _apply_wall_colors
	# paints the freshly spawned segments once they are in the tree)
	var wcols: Array = []
	for a in data.get("wall_colors", []):
		wcols.append([int(a[0]), int(a[1]), float(a[2]), float(a[3]), float(a[4])])
	obs.apply_wall_colors(wcols)

	# 4c. wall materials (v6+; same deferred-paint story as wall colours). A pre-v6 map has no
	# "wall_materials" key, so apply_wall_materials([]) just clears to all-stone.
	var wmats: Array = []
	for a in data.get("wall_materials", []):
		wmats.append([int(a[0]), int(a[1]), String(a[2])])
	obs.apply_wall_materials(wmats)

	# 4d. item pickups (v11+; after the floors they sit on). A pre-v11 map has no "pickups" key, so
	# apply_map([]) just clears any instances left from the previously loaded map.
	var pk2 = w.get_node_or_null("Pickups")
	if pk2:
		var picks: Array = []
		for r in data.get("pickups", []):
			picks.append({"cell": Vector2i(int(r["cell"][0]), int(r["cell"][1])),
				"item": String(r["item"]), "id": String(r.get("id", "")),
				"data": (r.get("data", {}) as Dictionary).duplicate(true)})
		pk2.apply_map(picks)

	# 5. spawn. The MARKER always follows the map (a resize/undo must move the authored spawn with
	# everything else), while snapping the PLAYER onto it is skipped for undo/redo so history never
	# teleports the character mid-edit. A map load (keep_player false) starts the player on the marker.
	var spawn: Dictionary = data.get("spawn", {"x": player.position.x, "y": player.position.y})
	var p := Vector2(spawn["x"], spawn["y"])
	var marker = w.get_node_or_null("SpawnMarker")
	if marker:
		marker.set_spawn(p)
	if not keep_player:
		player.position = p
		player.target_position = p
		player.is_moving = false

# --- disk I/O ---

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)

# the name of the map currently in memory ("" = a new/unsaved map). Read by CharacterIO's collected
# store, which keys what this character has picked up by map.
func current_map() -> String:
	return _current

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
	return true

func load_map(map_name: String) -> bool:
	var path := _path(map_name)
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
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
	if not dirty:
		dirty = true
		dirty_changed.emit(true)

func _clear_dirty() -> void:
	_autosave_accum = 0.0
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

func _blank_map() -> Dictionary:
	var w := 48
	var h := 32
	return {
		"version": VERSION,
		"grid": {"width": w, "height": h},
		"absent_cells": [],
		"spawn": {"x": w * CELL / 2.0, "y": h * CELL / 2.0},
		"walls": [], "doors": [], "quads": [], "wall_colors": [], "wall_materials": [], "floor_tints": [],
		"floor_patterns": [], "floor_no_bank": [],
	}
