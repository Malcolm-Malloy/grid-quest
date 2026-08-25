extends Node

# Dev-only headless test for CharacterIO (ROADMAP Phase B item 9: character save). Verifies the
# serialize/apply round-trip, atomic save/load to disk, inventory persistence, and that loading a
# non-existent save is a safe no-op. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_character_io.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	CharacterIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var player = main.get_node("World/Player")

	# start from a known-clean save slot
	CharacterIO.delete_character()
	_check("no save present at start", not CharacterIO.has_save())
	_check("loading with no save is a safe no-op (returns false)", CharacterIO.load_character() == false)

	# --- place the character, face them, give them an inventory item, then save ---
	player.position = Vector2(272, 368)
	player.target_position = player.position
	player.facing = "left"
	player.inventory = ["brass_key", {"id": "potion", "count": 3}]

	_check("save writes the file", CharacterIO.save_character())
	_check("has_save true after saving", CharacterIO.has_save())

	# serialize snapshot reflects the live state
	var snap: Dictionary = CharacterIO.serialize()
	_check("serialize: position x", is_equal_approx(float(snap["position"]["x"]), 272.0))
	_check("serialize: position y", is_equal_approx(float(snap["position"]["y"]), 368.0))
	_check("serialize: facing", snap["facing"] == "left")
	_check("serialize: inventory size", (snap["inventory"] as Array).size() == 2)

	# --- mutate the live character, then load: it must be restored from disk ---
	player.position = Vector2(16, 16)
	player.target_position = player.position
	player.facing = "up"
	player.inventory = []
	player.is_moving = true

	_check("load returns true", CharacterIO.load_character())
	_check("load restores position", player.position.is_equal_approx(Vector2(272, 368)))
	_check("load restores target_position", player.target_position.is_equal_approx(Vector2(272, 368)))
	_check("load restores facing", player.facing == "left")
	_check("load clears in-progress step", player.is_moving == false)
	_check("load restores inventory size", player.inventory.size() == 2)
	_check("load restores inventory item 0", player.inventory[0] == "brass_key")
	_check("load restores inventory item 1 (dict)", player.inventory[1] is Dictionary and int(player.inventory[1]["count"]) == 3)

	# --- inventory is copied, not aliased: mutating the live array must not change a prior serialize ---
	var before: Array = CharacterIO.serialize()["inventory"]
	player.inventory.append("extra")
	_check("serialize returns an independent inventory copy", (before as Array).size() == 2)

	# --- empty-inventory round trip ---
	player.inventory = []
	CharacterIO.save_character()
	player.inventory = ["stale"]
	CharacterIO.load_character()
	_check("empty inventory round-trips", player.inventory.is_empty())

	# cleanup
	CharacterIO.delete_character()
	_check("delete removes the save", not CharacterIO.has_save())

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
