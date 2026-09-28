extends "res://dev/test_case.gd"

# Dev-only headless test for CharacterIO (ROADMAP Phase B item 9: character save). Verifies the
# serialize/apply round-trip, atomic save/load to disk, inventory persistence, and that loading a
# non-existent save is a safe no-op. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_character_io.tscn

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
	player.facing = Player.Facing.LEFT
	# v2 inventory: a stack entry and a unique entry, the two kinds the item system introduced
	player.add_to_stack("coin", 3)
	player.add_unique("key", "abc123")

	_check("save writes the file", CharacterIO.save_character())
	_check("has_save true after saving", CharacterIO.has_save())

	# serialize snapshot reflects the live state
	var snap: Dictionary = CharacterIO.serialize()
	_check("serialize: position x", is_equal_approx(float(snap["position"]["x"]), 272.0))
	_check("serialize: position y", is_equal_approx(float(snap["position"]["y"]), 368.0))
	_check("serialize: facing", snap["facing"] == "left")
	_check("serialize: inventory carries both entry kinds",
		int(snap["inventory"]["stacks"]["coin"]) == 3 and (snap["inventory"]["uniques"] as Array).size() == 1)

	# --- mutate the live character, then load: it must be restored from disk ---
	player.position = Vector2(16, 16)
	player.target_position = player.position
	player.facing = Player.Facing.UP
	player.inventory = {"stacks": {}, "uniques": []}
	player.is_moving = true

	_check("load returns true", CharacterIO.load_character())
	_check("load restores position", player.position.is_equal_approx(Vector2(272, 368)))
	_check("load restores target_position", player.target_position.is_equal_approx(Vector2(272, 368)))
	_check("load restores facing", player.facing == Player.Facing.LEFT)
	_check("load clears in-progress step", player.is_moving == false)
	_check("load restores the stack count", player.stack_count("coin") == 3)
	_check("load restores the unique entry", player.has_unique("abc123"))

	# --- inventory is copied, not aliased: mutating the live array must not change a prior serialize ---
	var before: Dictionary = CharacterIO.serialize()["inventory"]
	player.add_to_stack("coin", 5)
	_check("serialize returns an independent inventory copy", int(before["stacks"]["coin"]) == 3)

	# --- empty-inventory round trip ---
	player.inventory = {"stacks": {}, "uniques": []}
	CharacterIO.save_character()
	player.inventory = {"stacks": {"stale": 1}, "uniques": []}
	CharacterIO.load_character()
	_check("empty inventory round-trips", player.inventory["stacks"].is_empty() and player.inventory["uniques"].is_empty())

	# cleanup
	CharacterIO.delete_character()
	_check("delete removes the save", not CharacterIO.has_save())

	finish()
