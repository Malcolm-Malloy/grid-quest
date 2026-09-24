class_name Creatures
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

const CELL := Grid.CELL

var creatures: Array[Dictionary] = [] # [{cell, creature, kind, id, blocks}]
# SPAWN ZONES: regions that periodically produce a creature (ROADMAP: "an area authored with
# box-select ... flagged to periodically spawn a chosen type within it, for populating wild areas").
# A zone is {rect: Rect2i, creature, rate, cap, id}. Stored as a RECT rather than a cell set because
# that is what dragging one out produces, and because a rect is what the spawner has to sample from
# and the overlay has to draw -- a sparse cell set would cost both of those for no authoring gain.
var zones: Array[Dictionary] = []
# What the zones have produced THIS session: [{cell, creature, zone_id, node}]. Runtime only -- never
# serialized, cleared on leaving PLAY and on any map apply, so a zone's output is a property of the
# playthrough and the MAP only ever holds the rule that made it.
var _spawned: Array[Dictionary] = []
var _timers := {}   # zone id -> seconds accumulated toward its next spawn attempt
var marker_script: Script
var zone_script: Script
var _preview_zone: Node2D # the live drag rectangle, before the zone is committed

func _ready() -> void:
	marker_script = load("res://world/creature_marker.gd")
	zone_script = load("res://world/creature_zone.gd")
	EditorMode.changed.connect(_on_mode_changed)
	build_world()

# a spawn point looks different either side of the Play/Edit line (an authored marker vs the creature
# it spawns), so the nodes are rebuilt on the mode flip rather than each node watching the mode
func _on_mode_changed(_m: int) -> void:
	_despawn_all() # a zone's output belongs to the playthrough, not to the map
	clear_world()
	build_world()

# --- model ---

# cell -> authored `creatures` record / zone-spawned `_spawned` record, rebuilt after every change to
# those lists (all in this file), so placement checks and the per-step blocking test are O(1)
var _by_cell := {}
var _spawned_by_cell := {}

func _reindex() -> void:
	_by_cell.clear()
	for c in creatures:
		_by_cell[c["cell"]] = c

func creature_at(cell: Vector2i) -> Dictionary:
	return _by_cell.get(cell, {})

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
	_reindex()
	return rec

func remove_creature(cell: Vector2i) -> bool:
	if not _by_cell.has(cell):
		return false
	creatures.erase(_by_cell[cell])
	_reindex()
	return true

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

# --- spawn zones (ROADMAP "Creature placement in the editor" -> spawn zone/region) ---

func zone_at(cell: Vector2i) -> Dictionary:
	# last first, so the most recently drawn zone wins where two overlap -- the same "what you just
	# authored is what you get" rule the paint tools follow
	for i in range(zones.size() - 1, -1, -1):
		if (zones[i]["rect"] as Rect2i).has_point(cell):
			return zones[i]
	return {}

func has_zone(cell: Vector2i) -> bool:
	return not zone_at(cell).is_empty()

# create a zone over `rect` spawning `creature`. Zones MAY overlap each other and anything else: a
# region is a rule about an area, not an occupant of its cells, so the one-object-per-cell model does
# not apply to it (a zone over a room with a wall in it is a perfectly sensible thing to author).
func add_zone(rect: Rect2i, creature: String, rate := Bestiary.ZONE_RATE, cap := Bestiary.ZONE_CAP) -> Dictionary:
	if not Bestiary.has(creature) or rect.size.x <= 0 or rect.size.y <= 0:
		return {}
	var rec := {"rect": rect, "creature": creature, "id": Items.new_id(),
		"rate": clampf(rate, Bestiary.ZONE_RATE_RANGE.x, Bestiary.ZONE_RATE_RANGE.y),
		"cap": clampi(cap, Bestiary.ZONE_CAP_RANGE.x, Bestiary.ZONE_CAP_RANGE.y)}
	zones.append(rec)
	return rec

func remove_zone_at(cell: Vector2i) -> bool:
	var rec := zone_at(cell)
	if rec.is_empty():
		return false
	zones.erase(rec)
	return true

func set_zone_type(cell: Vector2i, creature: String) -> bool:
	var rec := zone_at(cell)
	if rec.is_empty() or not Bestiary.has(creature) or rec["creature"] == creature:
		return false
	rec["creature"] = creature
	return true

func set_zone_rate(cell: Vector2i, rate: float) -> bool:
	var rec := zone_at(cell)
	if rec.is_empty():
		return false
	rec["rate"] = clampf(rate, Bestiary.ZONE_RATE_RANGE.x, Bestiary.ZONE_RATE_RANGE.y)
	return true

func set_zone_cap(cell: Vector2i, cap: int) -> bool:
	var rec := zone_at(cell)
	if rec.is_empty():
		return false
	rec["cap"] = clampi(cap, Bestiary.ZONE_CAP_RANGE.x, Bestiary.ZONE_CAP_RANGE.y)
	return true

# the live drag rectangle, shown while a zone is being dragged out and dropped when it lands
func set_zone_preview(rect: Rect2i, creature: String) -> void:
	if zone_script == null:
		return
	if _preview_zone == null:
		_preview_zone = Node2D.new()
		_preview_zone.set_script(zone_script)
		_preview_zone.preview = true
		add_child(_preview_zone)
	_preview_zone.configure(rect, creature, Bestiary.ZONE_RATE, Bestiary.ZONE_CAP, "")
	_preview_zone.visible = true

func clear_zone_preview() -> void:
	if _preview_zone != null:
		_preview_zone.visible = false

# --- zone spawning (PLAY only) ---
#
# Each zone tops itself up toward its cap, one creature per `rate` seconds, at a random FREE cell
# inside it. There is no AI yet (Phase C), so what a spawned creature does is stand there and block
# -- but the RULE is real and testable now, which is what the zone record exists to express.

func _process(delta: float) -> void:
	if EditorMode.is_edit() or zones.is_empty():
		return
	for z in zones:
		var zid := String(z["id"])
		var t: float = float(_timers.get(zid, 0.0)) + delta
		if t < float(z["rate"]):
			_timers[zid] = t
			continue
		_timers[zid] = 0.0
		if _live_count(zid) < int(z["cap"]):
			_spawn_one(z)

func _live_count(zone_id: String) -> int:
	var n := 0
	for sp in _spawned:
		if String(sp["zone_id"]) == zone_id:
			n += 1
	return n

# put one creature on a random free cell of `z`. Tries a bounded number of random cells rather than
# scanning the whole rect: a zone can be large, this runs during play, and a zone with almost no room
# left should give up cheaply rather than sweep thousands of cells every few seconds.
func _spawn_one(z: Dictionary) -> void:
	var rect: Rect2i = z["rect"]
	for _try in 12:
		var cell := Vector2i(rect.position.x + randi() % maxi(rect.size.x, 1),
			rect.position.y + randi() % maxi(rect.size.y, 1))
		if not _spawnable(cell):
			continue
		var node := Node2D.new()
		node.set_script(marker_script)
		node.creature = String(z["creature"])
		node.kind = Bestiary.INSTANCE # it has hatched; it is a creature standing here now
		node.id = Items.new_id()
		node.blocks = Bestiary.blocks_by_default(String(z["creature"]))
		node.place(cell)
		add_child(node)
		var sp := {"cell": cell, "creature": z["creature"], "zone_id": z["id"], "node": node}
		_spawned.append(sp)
		_spawned_by_cell[cell] = sp
		return

# a cell a zone may put a creature on: it must exist, be free of walls/doors, of impassable floor,
# and of anything already occupying the object layer (an item, an authored creature, or one of ours)
func _spawnable(cell: Vector2i) -> bool:
	var w := get_parent()
	var gb = w.get_node_or_null("GridBackground")
	if gb == null or not gb.cell_present(cell.x, cell.y):
		return false
	var obs = w.get_node_or_null("Obstacles")
	if obs != null and (obs.is_blocked(cell) or not obs.door_at(cell).is_empty()):
		return false
	var fm = w.get_node_or_null("FloorManager")
	if fm != null and fm.is_cell_impassable(cell) and (obs == null or not obs.is_bridge(cell)):
		return false
	var pk = w.get_node_or_null("Pickups")
	if pk != null and pk.has_pickup(cell):
		return false
	return not has_creature(cell) and not _spawned_by_cell.has(cell)

func _despawn_all() -> void:
	for sp in _spawned:
		var n = sp["node"]
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	_spawned_by_cell.clear()
	_timers.clear()

# what the zones have produced right now, for tests and for the status of a running map
func spawned_count() -> int:
	return _spawned.size()

# --- passability (ROADMAP "Passability") ---

# does a creature on `cell` stop the player? Deliberately NOT folded into Obstacles.is_blocked, which
# stays "is a wall" for the editor's sake -- the same separation the impassable-floor and locked-door
# checks make in player.gd. Only in PLAY: in EDIT the player is frozen anyway and the author must be
# able to see the cell as editable.
func blocks_movement(cell: Vector2i) -> bool:
	if EditorMode.is_edit():
		return false
	var rec := creature_at(cell)
	if not rec.is_empty():
		return bool(rec.get("blocks", true))
	# a creature a zone produced blocks exactly like an authored one: it is just as much standing there
	if _spawned_by_cell.has(cell):
		return Bestiary.blocks_by_default(String(_spawned_by_cell[cell]["creature"]))
	return false

# --- rebuild (MapIO load / resize / undo path) ---

func apply_map(list: Array, zone_list := []) -> void:
	creatures.clear()
	for c in list:
		creatures.append(c)
	_reindex()
	zones.clear()
	for z in zone_list:
		zones.append(z)
	_despawn_all() # the new map's zones start from nothing; the old map's output does not carry over
	rebuild()

# respawn the authored creature + zone nodes from `creatures` / `zones` (after an in-place edit)
func rebuild() -> void:
	clear_world()
	build_world()

func clear_world() -> void:
	for n in get_tree().get_nodes_in_group("creatures"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("creature_zones"):
		if n != _preview_zone:
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
	if zone_script == null:
		return
	for z in zones:
		var zn := Node2D.new()
		zn.set_script(zone_script)
		zn.configure(z["rect"], String(z["creature"]), float(z["rate"]), int(z["cap"]), String(z["id"]))
		add_child(zn)
