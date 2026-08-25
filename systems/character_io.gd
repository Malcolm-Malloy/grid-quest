extends Node

# Autoload singleton: persists the CHARACTER's live state (world position, facing, and inventory),
# separate from the map. Maps store an authored spawn (MapIO); this stores where the player actually
# stands right now, which way they face, and what they carry, so a whole-game save can restore the
# character independent of which map is loaded (ROADMAP Phase B item 9: "Character save (position,
# facing, inventory) ... as a separate JSON section/file reusing the same MapIO atomic-write +
# versioning path"). Inventory is an ordinary Array, empty until the item system lands (item 10);
# persisting it now is the prerequisite for locked doors + keys (item 11).
#
# Lives in user://character.json (persistent, writable). Writes are atomic (temp file, then rename),
# the same pattern MapIO uses, so a crash mid-save can't corrupt an existing save.

const VERSION := 1
const PATH := "user://character.json"

# On startup we do NOT auto-restore the character: the game defaults to EDIT mode (editor-first, see
# EditorMode) and a map load uses that map's authored spawn, so silently teleporting the player to a
# saved position would fight the editor. Restoring is explicit (load_character), to be wired into a
# future Continue/Play flow. The flag mirrors MapIO.auto_load and stays off unless deliberately set.
var auto_load := false

func _ready() -> void:
	await get_tree().process_frame # let the main scene's world (and the Player) finish building first
	if auto_load:
		load_character()

# --- node lookup (works whether the scene root is main.tscn or the capture/test harness) ---

func _player() -> Node:
	var obs := get_tree().get_first_node_in_group("obstacles")
	var w := obs.get_parent() if obs else null
	return w.get_node_or_null("Player") if w else null

# --- serialize the live character to the versioned dict ---

func serialize() -> Dictionary:
	var player := _player()
	if player == null:
		return {"version": VERSION, "position": {"x": 0.0, "y": 0.0}, "facing": "down", "inventory": []}
	# inventory is stored as-is; it must stay JSON-safe (the item system will keep it so). duplicate()
	# so a later mutation of the live array can't retroactively change a dict we already handed out.
	var inv: Array = player.inventory.duplicate(true) if "inventory" in player else []
	return {
		"version": VERSION,
		"position": {"x": player.position.x, "y": player.position.y},
		"facing": player.facing,
		"inventory": inv,
	}

# apply a serialize()-shaped dict onto the live character. Snaps the player to the saved position
# (no in-progress step), restores facing + sprite, and loads the inventory.
func apply(data: Dictionary) -> void:
	var player := _player()
	if player == null:
		return
	var pos: Dictionary = data.get("position", {"x": player.position.x, "y": player.position.y})
	var p := Vector2(pos["x"], pos["y"])
	player.position = p
	player.target_position = p
	player.is_moving = false
	player.facing = String(data.get("facing", player.facing))
	if "inventory" in player:
		var inv = data.get("inventory", [])
		player.inventory = (inv as Array).duplicate(true) if inv is Array else []
	if player.has_method("update_sprite"):
		player.update_sprite() # redraw with the restored facing (also refreshes the shadow shape)

# --- disk I/O (atomic write, mirroring MapIO.save_map) ---

func save_character() -> bool:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("CharacterIO: cannot open %s for writing" % tmp)
		return false
	f.store_string(JSON.stringify(serialize(), "\t"))
	f.close()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	DirAccess.rename_absolute(tmp, PATH) # atomic swap in place of the old save
	return true

func load_character() -> bool:
	if not FileAccess.file_exists(PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("CharacterIO: %s is not valid character JSON" % PATH)
		return false
	# migration hook: future versions convert older dicts up to VERSION here
	if int(data.get("version", 0)) > VERSION:
		push_warning("CharacterIO: %s was saved by a newer version" % PATH)
	apply(data)
	return true

func has_save() -> bool:
	return FileAccess.file_exists(PATH)

func delete_character() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
