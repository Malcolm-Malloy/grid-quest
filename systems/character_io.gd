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

const VERSION := 2 # v2: inventory is {stacks, uniques} + per-map collected pickup ids; v1: a flat array
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
		return {"version": VERSION, "position": {"x": 0.0, "y": 0.0}, "facing": "down",
			"inventory": {"stacks": {}, "uniques": []}, "collected": collected.duplicate(true)}
	# inventory is stored as-is; it must stay JSON-safe (the item system keeps it so). duplicate()
	# so a later mutation of the live structure can't retroactively change a dict we already handed out.
	var inv = player.inventory.duplicate(true) if "inventory" in player else {"stacks": {}, "uniques": []}
	return {
		"version": VERSION,
		"position": {"x": player.position.x, "y": player.position.y},
		"facing": player.facing,
		"inventory": inv,
		# which pickups THIS character has already taken, per map (ROADMAP "Items and pickups" -> where
		# collected state lives: the MAP always keeps its pickups, a saved game remembers what was taken)
		"collected": collected.duplicate(true),
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
		# v2 is {stacks, uniques}. A v1 save stored a flat Array, which was always empty (nothing could
		# add to it before the item system), so it migrates to an empty v2 inventory.
		var inv = data.get("inventory", {})
		if inv is Dictionary:
			player.inventory = {
				"stacks": (inv.get("stacks", {}) as Dictionary).duplicate(true),
				"uniques": (inv.get("uniques", []) as Array).duplicate(true),
			}
		else:
			player.inventory = {"stacks": {}, "uniques": []}
	var col = data.get("collected", {})
	collected = (col as Dictionary).duplicate(true) if col is Dictionary else {}
	if player.has_method("update_sprite"):
		player.update_sprite() # redraw with the restored facing (also refreshes the shadow shape)

# --- collected pickups (character/game-save data, NOT map data) ---
#
# ROADMAP "Items and pickups" -> where collected state lives: "the map definition always keeps its
# pickups (the key is present when the map is opened in the editor); a saved game remembers it was
# taken so it does not respawn on load". So the flag lives here, keyed by map name then pickup id.
# An unsaved map ("") still tracks in memory, so collecting works before a map is ever named.
var collected := {} # map name -> {pickup id: true}

func is_collected(map_name: String, pickup_id: String) -> bool:
	return collected.get(map_name, {}).has(pickup_id)

func mark_collected(map_name: String, pickup_id: String) -> void:
	if not collected.has(map_name):
		collected[map_name] = {}
	collected[map_name][pickup_id] = true

# forget what this character collected on a map, so its pickups are all there again (a fresh game,
# or the editor wanting to see the map as authored)
func clear_collected(map_name := "") -> void:
	if map_name == "":
		collected.clear()
	else:
		collected.erase(map_name)

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
