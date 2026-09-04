extends Node

# Dev-only headless test for the item / pickup system (ROADMAP Phase B item 10, "Items and pickups"):
# definitions vs instances, the two inventory entry kinds, the split interaction (stackables auto-
# collect on step, uniques must be taken deliberately), where collected state lives, editor placement,
# and persistence through save/load, resize and paste. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_items.tscn

var _fails := 0
func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond: _fails += 1

func _mid(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _nodes() -> int:
	return get_tree().get_nodes_in_group("pickups").size()

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var pk = main.get_node("World/Pickups")
	var player = main.get_node("World/Player")
	CharacterIO.clear_collected()
	EditHistory.reset()

	# --- 1. definitions and the shared rarity scale ---
	_check("the registry knows the three starter items", Items.has("coin") and Items.has("gem") and Items.has("key"))
	_check("coins stack, keys do not", Items.is_stackable("coin") and not Items.is_stackable("key"))
	_check("rarity is a shared 6-tier scale", Items.RARITY_COLORS.size() == 6 and Items.RARITY_NAMES.size() == 6)
	_check("rarity outline width steps up with the tier (the non-colour cue)",
		Items.rarity_width("key") > Items.rarity_width("coin"))
	_check("an unknown item is empty, not a crash", Items.def("sword").is_empty())
	_check("ids are unique per instance", Items.new_id() != Items.new_id())

	# --- 2. editor placement: one per cell, never on a wall or off the map ---
	var coin_cell := Vector2i(20, 12)
	var key_cell := Vector2i(21, 12)
	fm.set_mode(fm.Mode.ITEM)
	fm.arm_item("coin")
	_check("placed a coin", fm._place_item_at(_mid(coin_cell)))
	fm.arm_item("key")
	_check("placed a key", fm._place_item_at(_mid(key_cell)))
	await get_tree().process_frame
	_check("both instances exist in the model", pk.pickups.size() == 2)
	_check("both spawned a node", _nodes() == 2)
	_check("a second item on the same cell is refused", not fm._place_item_at(_mid(coin_cell)))
	_check("an item on a wall cell is refused", not fm._place_item_at(_mid(Vector2i(8, 3))))
	_check("an item off the map is refused", not fm._place_item_at(Vector2(-40, -40)))
	_check("each placement was one undo entry", EditHistory.can_undo())

	# --- 3. the map stores pickups; a save/load round-trip keeps them, ids included ---
	var coin_id: String = pk.pickup_at(coin_cell)["id"]
	var data := MapIO.serialize()
	_check("serialize writes the pickups", data["pickups"].size() == 2)
	_check("the save format holds pickups (v11+)", int(data["version"]) >= 11)
	MapIO.save_map("__items_test")
	MapIO.load_map("__items_test")
	await get_tree().process_frame
	_check("load restored both pickups", pk.pickups.size() == 2)
	_check("the durable id survived the round-trip", pk.pickup_at(coin_cell)["id"] == coin_id)

	# --- 4. stackables auto-collect on step; uniques do not ---
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	await get_tree().process_frame
	_check("stepping on a coin collects it", pk.try_auto_collect(coin_cell) == "coin")
	_check("the coin went into the stack", player.stack_count("coin") == 1)
	await get_tree().process_frame # queue_free lands at the end of the frame
	_check("its node is gone", _nodes() == 1)
	_check("walking onto a KEY collects nothing", pk.try_auto_collect(key_cell) == "")
	_check("the key is still on the ground", pk.has_pickup(key_cell) and _nodes() == 1)

	# --- 5. a unique item is taken deliberately, and lands as its own entry ---
	var key_id: String = pk.pickup_at(key_cell)["id"]
	player.position = _mid(key_cell)
	_check("taking the key works when you are on it", pk.take_at(key_cell) == "key")
	_check("the key is a unique entry, not a stack", player.uniques_of("key").size() == 1 and player.stack_count("key") == 0)
	_check("the entry carries the pickup's durable id", player.has_unique(key_id))
	_check("reach is enforced (a far cell is out of range)", not pk._within_reach(Vector2i(40, 30)))

	# --- 6. collected state is CHARACTER data: the map keeps its items ---
	_check("the map still holds both pickups", pk.pickups.size() == 2)
	_check("this character is marked as having taken them",
		CharacterIO.is_collected("__items_test", coin_id) and CharacterIO.is_collected("__items_test", key_id))
	MapIO.load_map("__items_test") # reopening the map must not respawn what was taken
	await get_tree().process_frame
	_check("a reload does not respawn collected items", _nodes() == 0)
	CharacterIO.clear_collected("__items_test")
	MapIO.load_map("__items_test")
	await get_tree().process_frame
	_check("a fresh character sees them again", _nodes() == 2)
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	await get_tree().process_frame

	# --- 7. inventory persists through CharacterIO (v2 shape) ---
	CharacterIO.save_character()
	player.inventory = {"stacks": {}, "uniques": []}
	CharacterIO.load_character()
	_check("the saved inventory came back", player.stack_count("coin") == 1 and player.uniques_of("key").size() == 1)
	_check("CharacterIO stores the v2+ inventory shape", int(CharacterIO.serialize()["version"]) >= 2)
	CharacterIO.delete_character()

	# --- 8. items ride along with the map: resize and copy/paste ---
	MapEdit.grow("left")
	await get_tree().process_frame
	_check("growing the left edge shifted the items with the map", pk.has_pickup(coin_cell + Vector2i(1, 0)))
	var moved_coin := coin_cell + Vector2i(1, 0)
	var clip := MapClipboard.build_clip(MapIO.serialize(), {moved_coin: true})
	_check("a clip carries the item", clip["pickups"].size() == 1)
	MapEdit.stamp_clip(clip, Vector2i(30, 24))
	await get_tree().process_frame
	_check("the pasted item landed", pk.has_pickup(Vector2i(30, 24)))
	_check("the paste minted a FRESH id (a copied key is a different key)",
		pk.pickup_at(Vector2i(30, 24))["id"] != pk.pickup_at(moved_coin)["id"])

	# --- 9. Erase takes the item before the ground under it ---
	fm.set_mode(fm.Mode.ERASE)
	fm._erase_single(moved_coin)
	await get_tree().process_frame
	_check("erase removed the item", not pk.has_pickup(moved_coin))

	DirAccess.remove_absolute("user://maps/__items_test.json")
	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
