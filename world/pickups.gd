class_name Pickups
extends Node2D

# Pickups: the placed item INSTANCES on the current map, and the rules for collecting them.
# The definitions live in the Items autoload; this is the world half, built like Obstacles (a model
# array plus spawned nodes rebuilt from it, so MapIO's one rebuild path recreates everything).
#
# A pickup record is {cell, item, id}: a definition placed at a cell with a DURABLE id (Architecture
# review Q3), minted at placement and carried through save/load, resize and move -- so a Unique key
# stays the same key. A PASTE deliberately mints fresh ids (a copied key is a different key).
#
# COLLECTION IS SPLIT BY ITEM TYPE (ROADMAP "Items and pickups", refined 2026-08-16):
#  - STACKABLE items auto-collect when the player STEPS on the cell. No input at all, so looting the
#    common case stays fast.
#  - UNIQUE items (keys) are never grabbed by walking: the player CLICKS them. That is this file's
#    _unhandled_input, active in PLAY only, and it requires the player to be standing on or next to
#    the item -- clicking a key from across the map would not be "reaching for it".
#    (This resolves the spec's open question -- mouse click on the sprite vs a general interact button
#    while standing on the cell -- toward the mouse click the note itself described, since there is no
#    general interact button yet. When one lands, it should become a second way in, not a replacement.)
#
# WHERE COLLECTED STATE LIVES (the ROADMAP save call, Q4): the MAP always keeps its pickups, so the
# key is there when you open the map in the editor; whether THIS character already took it is
# character data, held by CharacterIO. So build_world() skips instances CharacterIO reports collected.


var pickups: Array[Dictionary] = [] # [{cell: Vector2i, item: String, id: String}]
var pickup_script: Script

func _ready() -> void:
	pickup_script = load("res://world/pickup.gd")
	build_world()

# --- model ---

# cell -> its `pickups` record, rebuilt by _reindex() after every change to `pickups` (all in this file),
# so the per-step auto-collect and the placement checks are O(1)
var _by_cell := {}

func _reindex() -> void:
	_by_cell.clear()
	for p in pickups:
		_by_cell[p["cell"]] = p

func pickup_at(cell: Vector2i) -> Dictionary:
	return _by_cell.get(cell, {})

func has_pickup(cell: Vector2i) -> bool:
	return not pickup_at(cell).is_empty()

# place `item` on `cell`, minting a durable id. One item per cell (the cell-occupancy model), so a
# cell that already holds one is refused. Returns the new record, or {} if refused.
func add_pickup(cell: Vector2i, item: String, data := {}) -> Dictionary:
	if not Items.has(item) or has_pickup(cell):
		return {}
	# `data` is per-instance extra: a Unique key carries {door_id, name}, binding it to one door
	var rec := {"cell": cell, "item": item, "id": Items.new_id(), "data": data.duplicate(true)}
	pickups.append(rec)
	_reindex()
	return rec

func remove_pickup(cell: Vector2i) -> bool:
	if not _by_cell.has(cell):
		return false
	pickups.erase(_by_cell[cell])
	_reindex()
	return true

# replace the whole model and rebuild the nodes (MapIO load / resize / undo path)
func apply_map(list: Array) -> void:
	pickups.clear()
	for p in list:
		pickups.append(p)
	_reindex()
	rebuild()

# --- nodes ---

# respawn the pickup nodes from `pickups` (after an in-place edit)
func rebuild() -> void:
	clear_world()
	build_world()

func clear_world() -> void:
	for n in get_tree().get_nodes_in_group("pickups"):
		n.queue_free()

func build_world() -> void:
	if pickup_script == null:
		return
	var map := MapIO.current()
	for rec in pickups:
		if CharacterIO.is_collected(map, String(rec["id"])):
			continue # this character already took it; the MAP still holds it (editor + a fresh game)
		var node := Node2D.new()
		node.set_script(pickup_script)
		node.item = String(rec["item"])
		node.id = String(rec["id"])
		node.data = (rec.get("data", {}) as Dictionary).duplicate(true)
		node.place(rec["cell"])
		add_child(node)

# --- collection ---

# the player stepped onto `cell`: take a STACKABLE item automatically. Returns the item id taken,
# or "" (nothing there, or a unique item, which waits to be clicked).
func try_auto_collect(cell: Vector2i) -> String:
	var rec := pickup_at(cell)
	if rec.is_empty() or not Items.is_stackable(String(rec["item"])):
		return ""
	return _collect(rec)

# deliberate take of a UNIQUE item (the click path). Returns the item id taken, or "".
func take_at(cell: Vector2i) -> String:
	var rec := pickup_at(cell)
	if rec.is_empty() or Items.is_stackable(String(rec["item"])):
		return ""
	return _collect(rec)

# move a pickup into the character's inventory: the record stays in the MAP (so the editor and a new
# game still have it), the instance is marked collected for THIS character, and its node goes.
func _collect(rec: Dictionary) -> String:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return ""
	var item := String(rec["item"])
	if Items.is_stackable(item):
		player.add_to_stack(item, 1)
	else:
		player.add_unique(item, String(rec["id"]), rec.get("data", {}))
	CharacterIO.mark_collected(MapIO.current(), String(rec["id"]))
	for n in get_tree().get_nodes_in_group("pickups"):
		if n.id == rec["id"]:
			n.queue_free()
	return item

# every placed pickup bound to `door_id` (its Unique keys). Drives the editor's warning before a
# bound door is deleted, since deleting the door takes its key with it.
func keys_for_door(door_id: String) -> Array:
	var out: Array = []
	if door_id == "":
		return out
	for p in pickups:
		if String(p.get("data", {}).get("door_id", "")) == door_id:
			out.append(p)
	return out

# --- click to take a unique item (PLAY only) ---

func _unhandled_input(event: InputEvent) -> void:
	if EditorMode.is_edit():
		return # in EDIT the mouse belongs to the editor tools
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	var rec := pickup_at(cell)
	if rec.is_empty() or Items.is_stackable(String(rec["item"])):
		return
	if not _within_reach(cell):
		return # you have to be next to it to pick it up
	take_at(cell)
	get_viewport().set_input_as_handled()

# the player must be standing on the item's cell or one step away (including diagonals)
func _within_reach(cell: Vector2i) -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var pc := Grid.cell_of(player.position)
	return absi(pc.x - cell.x) <= 1 and absi(pc.y - cell.y) <= 1

# --- persistence: placed items as {cell, item, id, data?}. Whether a character already TOOK one is not
# here -- that is character data (CharacterIO), so the map keeps its items for the editor. ---

func to_data() -> Dictionary:
	var out: Array = []
	for r in pickups:
		var rec := {"cell": [r["cell"].x, r["cell"].y], "item": r["item"], "id": r["id"]}
		if not r.get("data", {}).is_empty():
			rec["data"] = r["data"] # a unique key's binding: {door_id, name}
		out.append(rec)
	return {"pickups": out}

# replace every placed item (pre-v11 maps have no key -> none)
func load_data(data: Dictionary) -> void:
	var list: Array = []
	for r in data.get("pickups", []):
		list.append({"cell": Vector2i(int(r["cell"][0]), int(r["cell"][1])),
			"item": String(r["item"]), "id": String(r.get("id", "")),
			"data": (r.get("data", {}) as Dictionary).duplicate(true)})
	apply_map(list)
