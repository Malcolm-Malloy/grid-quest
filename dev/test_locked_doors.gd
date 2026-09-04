extends Node

# Dev-only headless test for locked doors and keys (ROADMAP Phase B item 11, the terminal item of the
# 2026-08-13 chain): the two lock types, what each does to the key, how a locked door blocks, where
# the opened state lives, and the editor rules (authoring, durable door ids, deleting a bound door).
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_locked_doors.tscn

var _fails := 0
func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond: _fails += 1

func _mid(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var obs = main.get_node("World/Obstacles")
	var fm = main.get_node("World/FloorManager")
	var pk = main.get_node("World/Pickups")
	var player = main.get_node("World/Player")
	CharacterIO.clear_collected()
	CharacterIO.clear_unlocked()
	player.inventory = {"stacks": {}, "uniques": []}
	EditHistory.reset()

	var door := Vector2i(8, 11) # the seeded room's door to the outside
	_check("setup: that cell is a door", not obs.door_at(door).is_empty())

	# --- 1. doors carry a durable id, minted for the pre-v12 roster too ---
	var door_id: String = obs.door_id_at(door)
	_check("the door has a durable id", door_id != "")
	_check("an unlocked door is not locked", not obs.is_locked(door, player))

	# --- 2. a COLOURED lock: any key of that colour opens it, and is consumed ---
	obs.set_door_lock(door, "colour", "red")
	_check("the door reports its lock", obs.door_at(door)["lock"] == "colour")
	_check("a coloured lock locks the door", obs.is_locked(door, player))
	_check("without a key it will not open", not obs.try_unlock(door, player))
	player.add_to_stack("key_blue", 1)
	_check("the WRONG colour does not open it", not obs.try_unlock(door, player))
	_check("and the wrong key is not spent", player.stack_count("key_blue") == 1)
	player.add_to_stack("key_red", 2)
	_check("the right colour opens it", obs.try_unlock(door, player))
	_check("one red key was consumed", player.stack_count("key_red") == 1)
	_check("the door is no longer locked", not obs.is_locked(door, player))
	_check("a coloured lock, once opened, is recorded on the CHARACTER",
		CharacterIO.is_unlocked(MapIO.current(), door_id))
	_check("the MAP still holds the authored lock", obs.door_at(door)["lock"] == "colour")
	_check("re-opening it costs nothing more", obs.try_unlock(door, player) and player.stack_count("key_red") == 1)

	# --- 3. a UNIQUE lock: bound to THIS door, key kept, never consumed ---
	CharacterIO.clear_unlocked()
	obs.set_door_lock(door, "unique", "red", "Malcolm's Door Key")
	_check("a unique lock locks the door", obs.is_locked(door, player))
	_check("a coloured key does not open a unique lock", not obs.try_unlock(door, player))
	player.add_unique("key", "pk1", {"door_id": "some-other-door", "name": "Wrong Key"})
	_check("a key bound to ANOTHER door does not open it", obs.is_locked(door, player))
	player.add_unique("key", "pk2", {"door_id": door_id, "name": "Malcolm's Door Key"})
	_check("the bound key opens it", not obs.is_locked(door, player) and obs.try_unlock(door, player))
	_check("the unique key is NOT consumed", player.uniques_of("key").size() == 2)
	_check("nothing was recorded: a unique lock is re-checked every time",
		not CharacterIO.is_unlocked(MapIO.current(), door_id))
	# losing the key shuts the door again -- the reason unique locks persist no opened flag
	player.inventory["uniques"] = [{"item": "key", "id": "pk1", "data": {"door_id": "some-other-door"}}]
	_check("losing the key locks the door again", obs.is_locked(door, player))
	player.add_unique("key", "pk2", {"door_id": door_id, "name": "Malcolm's Door Key"})

	# --- 4. a locked door blocks movement, and the lock survives a save/load ---
	obs.set_door_lock(door, "colour", "green")
	CharacterIO.clear_unlocked()
	MapIO.save_map("__lock_test")
	MapIO.load_map("__lock_test")
	await get_tree().process_frame
	_check("the lock round-tripped through the save", obs.door_at(door).get("lock", "") == "colour")
	_check("the lock colour round-tripped", obs.door_at(door).get("lock_color", "") == "green")
	_check("the door id round-tripped", obs.door_id_at(door) == door_id)
	_check("it is still locked after loading", obs.is_locked(door, player))
	var gate = obs.gate_node_at(door)
	_check("the gate node knows its lock (so it can draw it)", gate != null and gate.lock == "colour")
	_check("a locked door does not open on approach", not gate.is_open)

	# --- 5. the editor: placing a bound key, and deleting the door that owns it ---
	obs.set_door_lock(door, "unique", "red", "Malcolm's Door Key")
	fm.arm_bound_key(obs.door_id_at(door), "Malcolm's Door Key")
	_check("the Item tool armed the bound key", fm.armed_item() == "key" and fm.armed_item_binding()["door_id"] == door_id)
	_check("placed the key", fm._place_item_at(_mid(Vector2i(20, 14))))
	await get_tree().process_frame
	var placed: Dictionary = pk.pickup_at(Vector2i(20, 14))
	_check("the placed key is bound to the door", String(placed["data"]["door_id"]) == door_id)
	_check("it carries the player-facing name", String(placed["data"]["name"]) == "Malcolm's Door Key")
	_check("the binding is spent: the next key is unbound", fm.armed_item_binding().is_empty())
	_check("the door can find its keys", pk.keys_for_door(door_id).size() == 1)
	_check("erasing that door WARNS first (it would take the key with it)",
		fm._warn_bound_keys([door], func(): pass))
	fm._delete_structure_with_keys(door)
	await get_tree().process_frame
	_check("confirming removed the door", obs.door_at(door).is_empty())
	_check("...and its now-useless key", not pk.has_pickup(Vector2i(20, 14)))
	EditHistory.undo()
	await get_tree().process_frame
	_check("one undo restores the door AND the key",
		not obs.door_at(door).is_empty() and pk.has_pickup(Vector2i(20, 14)))

	# --- 6. copy/paste vs move: a pasted door is a NEW door, a moved one is the same door ---
	var moved_id: String = obs.door_id_at(door)
	var clip := MapClipboard.build_clip(MapIO.serialize(), {door: true})
	MapEdit.stamp_clip(clip, Vector2i(30, 20))
	await get_tree().process_frame
	_check("a PASTED door gets a fresh id (its original's key must not open the copy)",
		obs.door_id_at(Vector2i(30, 20)) != moved_id)
	MapEdit.move_clip({door: true}, MapClipboard.build_clip(MapIO.serialize(), {door: true}), Vector2i(8, 12))
	await get_tree().process_frame
	_check("a MOVED door keeps its id (its Unique key still resolves)", obs.door_id_at(Vector2i(8, 12)) == moved_id)
	_check("the moved door kept its lock", obs.door_at(Vector2i(8, 12)).get("lock", "") == "unique")

	DirAccess.remove_absolute("user://maps/__lock_test.json")
	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
