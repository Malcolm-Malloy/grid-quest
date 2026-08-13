extends Node

# Autoload singleton: the one place that turns the live level into JSON and back. It stores
# ONLY the source of truth (grid size, spawn, walls, doors, per-room floor styles). Everything
# derived (wall/gate meshes, shadows, room lighting, floor fills, the highlight, door open
# state) is recomputed on load, so saves stay small and always consistent.
#
# Maps live in user://maps/<name>.json (persistent, writable, cross-platform). Writes are
# atomic (temp file, then rename) so a crash mid-save can't corrupt an existing map.

const VERSION := 1
const DIR := "user://maps"
const LAST_FILE := "user://last_map.txt" # remembers the map to reload on next launch

# on startup we auto-reload the last saved/loaded map. The capture harness turns this off so
# its GQ_LOAD tests stay deterministic.
var auto_load := true

func _ready() -> void:
	await get_tree().process_frame # let the main scene's world finish building first
	if auto_load:
		var last := get_last()
		if last != "" and FileAccess.file_exists(_path(last)):
			load_map(last)

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

	var walls: Array = []
	for c in obs.blocked_cells:
		walls.append([c.x, c.y])
	var doors: Array = []
	for d in obs.gate_cells:
		doors.append({"cell": [d["cell"].x, d["cell"].y], "orientation": d["orientation"]})
	var floors: Array = []
	for rep in fm._styles:
		floors.append({"cell": [rep.x, rep.y], "style": fm._styles[rep]})

	return {
		"version": VERSION,
		"grid": {"width": gb.grid_width, "height": gb.grid_height},
		"spawn": {"x": player.position.x, "y": player.position.y},
		"walls": walls,
		"doors": doors,
		"floors": floors,
	}

# --- apply a parsed dict back onto the live level, in dependency order ---

func _apply(data: Dictionary) -> void:
	var w := _world()
	var gb = w.get_node("GridBackground")
	var obs = w.get_node("Obstacles")
	var rl = w.get_node("RoomLight")
	var fm = w.get_node("FloorManager")
	var player = w.get_node("Player")

	# 1. grid size
	var grid: Dictionary = data.get("grid", {"width": gb.grid_width, "height": gb.grid_height})
	gb.set_grid_size(int(grid["width"]), int(grid["height"]))

	# 2. walls + doors -> rebuild wall/gate nodes and shadows
	var walls: Array = []
	for a in data.get("walls", []):
		walls.append(Vector2i(int(a[0]), int(a[1])))
	var doors: Array = []
	for d in data.get("doors", []):
		doors.append({"cell": Vector2i(int(d["cell"][0]), int(d["cell"][1])), "orientation": d["orientation"]})
	obs.apply_map(walls, doors)

	# 3. lighting (depends on walls/doors)
	rl.rebuild()

	# 4. floor styles (depends on rooms existing)
	var floors: Array = []
	for f in data.get("floors", []):
		floors.append({"cell": Vector2i(int(f["cell"][0]), int(f["cell"][1])), "style": f["style"]})
	fm.apply_floors(floors)

	# 5. player spawn
	var spawn: Dictionary = data.get("spawn", {"x": player.position.x, "y": player.position.y})
	var p := Vector2(spawn["x"], spawn["y"])
	player.position = p
	player.target_position = p
	player.is_moving = false

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
