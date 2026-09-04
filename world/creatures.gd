extends Node2D

# Creatures: the placed creature records on the current map, and the nodes drawn from them. The
# definitions live in the Bestiary autoload; this is the world half, built exactly like Pickups (a
# model array plus spawned nodes rebuilt from it, so MapIO's one rebuild path recreates everything).
#
# A record is {cell, creature, kind, id, blocks}: a definition placed at a cell, with
#   kind  = Bestiary.SPAWN_POINT (a spot that spawns this creature at play start, then it roams) or
#           Bestiary.INSTANCE (this exact creature, exactly here -- scripted / boss / quest),
#   id    = a DURABLE id (Architecture review Q3) minted at placement and carried through save/load,
#           resize and move, so capture/respawn tracking can key off it once Phase C exists,
#   blocks = the per-object passability override (ROADMAP "Passability": monster blocks while alive,
#           any individual object can have the flag toggled).
#
# THE AI IS NOT HERE. Roaming, fighting, capture and domestication are Phase C. What a placed
# creature does today is stand where it was authored and block the player, which is enough to author
# and play a map around. The spawn-point/instance distinction is REAL now (a spawn point draws as a
# marker pad in EDIT and hatches its creature in PLAY, an instance is simply always the creature), so
# the AI has the right two hooks waiting rather than one retrofitted later.
#
# ONE OBJECT PER CELL (ROADMAP "Cell occupancy model": terrain / structure / object, at most one of
# each). A creature IS an object, so it cannot share a cell with a pickup, and vice versa -- the
# refusal is enforced here and in Pickups' placement path.

const CELL := 32

var creatures: Array[Dictionary] = [] # [{cell, creature, kind, id, blocks}]
var marker_script: Script

func _ready() -> void:
	marker_script = load("res://world/creature_marker.gd")
	EditorMode.changed.connect(_on_mode_changed)
	build_world()

# a spawn point looks different either side of the Play/Edit line (an authored marker vs the creature
# it spawns), so the nodes are rebuilt on the mode flip rather than each node watching the mode
func _on_mode_changed(_m: int) -> void:
	clear_world()
	build_world()

# --- model ---

func creature_at(cell: Vector2i) -> Dictionary:
	for c in creatures:
		if c["cell"] == cell:
			return c
	return {}

func has_creature(cell: Vector2i) -> bool:
	return not creature_at(cell).is_empty()

# place `creature` on `cell` as `kind`, minting a durable id. One object per cell, so a cell already
# holding a creature is refused (the PICKUP check lives in the caller, which can see both layers).
# Returns the new record, or {} if refused.
func add_creature(cell: Vector2i, creature: String, kind := Bestiary.SPAWN_POINT) -> Dictionary:
	if not Bestiary.has(creature) or not Bestiary.is_kind(kind) or has_creature(cell):
		return {}
	var rec := {
		"cell": cell, "creature": creature, "kind": kind, "id": Items.new_id(),
		"blocks": Bestiary.blocks_by_default(creature),
	}
	creatures.append(rec)
	return rec

func remove_creature(cell: Vector2i) -> bool:
	for i in creatures.size():
		if creatures[i]["cell"] == cell:
			creatures.remove_at(i)
			return true
	return false

# --- per-instance edits (the inspector's authoring surface) ---

# swap which creature stands here, keeping the cell, kind and durable id: retyping a placed creature
# is an EDIT of that creature, not a new one, so anything keyed to its id still resolves.
func set_type(cell: Vector2i, creature: String) -> bool:
	var rec := creature_at(cell)
	if rec.is_empty() or not Bestiary.has(creature) or rec["creature"] == creature:
		return false
	rec["creature"] = creature
	return true

func set_kind(cell: Vector2i, kind: String) -> bool:
	var rec := creature_at(cell)
	if rec.is_empty() or not Bestiary.is_kind(kind) or rec["kind"] == kind:
		return false
	rec["kind"] = kind
	return true

func set_blocks(cell: Vector2i, blocks: bool) -> bool:
	var rec := creature_at(cell)
	if rec.is_empty() or bool(rec["blocks"]) == blocks:
		return false
	rec["blocks"] = blocks
	return true

# --- passability (ROADMAP "Passability") ---

# does a creature on `cell` stop the player? Deliberately NOT folded into Obstacles.is_blocked, which
# stays "is a wall" for the editor's sake -- the same separation the impassable-floor and locked-door
# checks make in player.gd. Only in PLAY: in EDIT the player is frozen anyway and the author must be
# able to see the cell as editable.
func blocks_movement(cell: Vector2i) -> bool:
	if EditorMode.is_edit():
		return false
	var rec := creature_at(cell)
	return not rec.is_empty() and bool(rec.get("blocks", true))

# --- rebuild (MapIO load / resize / undo path) ---

func apply_map(list: Array) -> void:
	creatures.clear()
	for c in list:
		creatures.append(c)
	clear_world()
	build_world()

func clear_world() -> void:
	for n in get_tree().get_nodes_in_group("creatures"):
		n.queue_free()

func build_world() -> void:
	if marker_script == null:
		return
	for rec in creatures:
		var node := Node2D.new()
		node.set_script(marker_script)
		node.creature = String(rec["creature"])
		node.kind = String(rec["kind"])
		node.id = String(rec["id"])
		node.blocks = bool(rec.get("blocks", true))
		node.place(rec["cell"])
		add_child(node)
