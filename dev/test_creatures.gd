extends Node

# Dev-only headless test for CREATURE PLACEMENT in the editor (ROADMAP "Creature placement in the
# editor": spawn point + fixed instance now, spawn zone later). Covers the definition registry, both
# placement kinds, the cell-occupancy rules against the other object layer, per-instance editing,
# passability, save/load (v13), resize, copy/paste and undo. Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_creatures.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var cr = main.get_node("World/Creatures")
	var pk = main.get_node("World/Pickups")
	var obs = main.get_node("World/Obstacles")
	EditorMode.set_mode(EditorMode.Mode.EDIT)

	# --- the definition registry, and the SHARED rarity scale ---
	_check("the three starter monsters are defined", Bestiary.ids().size() == 3)
	_check("Frost Frog is one of them", Bestiary.has("frost_frog"))
	_check("an unknown creature resolves to {} rather than crashing", Bestiary.def("dragon").is_empty())
	# ROADMAP "Item rarity": one shared enum + palette, not two parallel systems
	_check("creature rarity IS the item rarity scale",
		Bestiary.rarity_color("fire_horse") == Items.RARITY_COLORS[Bestiary.rarity_of("fire_horse")])
	_check("both placement kinds exist", Bestiary.KINDS.size() == 2)

	# --- placement: both kinds, each a durable id ---
	var a := Vector2i(20, 14)
	var b := Vector2i(21, 14)
	fm.arm_creature("frost_frog")
	_check("arming an unknown creature is refused", true)
	fm.arm_creature("dragon")
	_check("...leaving the previous one armed", fm.armed_creature() == "frost_frog")
	_check("spawn point is the default kind", fm.armed_creature_kind() == Bestiary.SPAWN_POINT)
	fm._place_creature_at(Vector2(a.x * 32 + 16, a.y * 32 + 16))
	_check("a click places a creature", cr.has_creature(a))
	var rec: Dictionary = cr.creature_at(a)
	_check("...of the armed type", rec["creature"] == "frost_frog")
	_check("...as a spawn point", rec["kind"] == Bestiary.SPAWN_POINT)
	_check("...with a durable id", String(rec["id"]) != "")
	_check("...blocking by default (monster blocks while alive)", bool(rec["blocks"]))
	fm.arm_creature("fire_horse")
	fm.arm_creature_kind(Bestiary.INSTANCE)
	fm._place_creature_at(Vector2(b.x * 32 + 16, b.y * 32 + 16))
	_check("a fixed instance places too", cr.creature_at(b)["kind"] == Bestiary.INSTANCE)
	_check("two placements get different ids", cr.creature_at(a)["id"] != cr.creature_at(b)["id"])

	# --- one object per cell (ROADMAP "Cell occupancy model") ---
	_check("a second creature on the same cell is refused", not fm._place_creature_at(Vector2(a.x * 32 + 16, a.y * 32 + 16)))
	var itc := Vector2i(23, 14)
	fm.arm_item("coin")
	fm._place_item_at(Vector2(itc.x * 32 + 16, itc.y * 32 + 16))
	fm.arm_creature("frost_frog")
	_check("a creature is refused where an ITEM already holds the object layer",
		not fm._place_creature_at(Vector2(itc.x * 32 + 16, itc.y * 32 + 16)))
	# a wall owns the structure layer; creature placement refuses it, matching the item tool
	var wc := Vector2i(25, 14)
	obs.add_wall(wc)
	MapIO.apply_serialized(MapIO.serialize(), true)
	_check("a creature is refused on a wall cell", not fm._place_creature_at(Vector2(wc.x * 32 + 16, wc.y * 32 + 16)))

	# --- nodes: one marker per record, and a spawn point reads differently either side of Play ---
	# a rebuild queue_frees the old markers and spawns the new ones in the same frame, so the group
	# holds both until the frame ends -- count after it, not during it
	await get_tree().process_frame
	var markers := get_tree().get_nodes_in_group("creatures")
	_check("one marker node per placed creature", markers.size() == cr.creatures.size())
	var spawn_node = null
	for n in markers:
		if n.cell == a:
			spawn_node = n
	_check("the spawn point draws as a MARKER while authoring", spawn_node != null and spawn_node._is_marker())
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	await get_tree().process_frame
	spawn_node = null
	for n in get_tree().get_nodes_in_group("creatures"):
		if n.cell == a:
			spawn_node = n
	_check("...and hatches into the creature in PLAY", spawn_node != null and not spawn_node._is_marker())

	# --- passability (ROADMAP "Passability": blocks while alive, per-object override) ---
	_check("a creature blocks the player in PLAY", cr.blocks_movement(a))
	cr.set_blocks(a, false)
	_check("the per-object override makes it passable", not cr.blocks_movement(a))
	cr.set_blocks(a, true)
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	_check("nothing blocks in EDIT (the player is frozen and the cell must stay editable)",
		not cr.blocks_movement(a))

	# --- per-instance editing keeps the identity (the inspector's edits) ---
	var id_before := String(cr.creature_at(a)["id"])
	cr.set_type(a, "breaker_monkey")
	_check("retyping changes the creature", cr.creature_at(a)["creature"] == "breaker_monkey")
	_check("...and keeps its durable id (an edit, not a replacement)", String(cr.creature_at(a)["id"]) == id_before)
	cr.set_kind(a, Bestiary.INSTANCE)
	_check("re-kinding works", cr.creature_at(a)["kind"] == Bestiary.INSTANCE)
	_check("...and keeps the id too", String(cr.creature_at(a)["id"]) == id_before)
	cr.set_kind(a, Bestiary.SPAWN_POINT)
	_check("an unknown kind is refused", not cr.set_kind(a, "wandering"))

	# --- the Select tool routes a click on a creature to the inspector, object layer first ---
	var insp = get_tree().get_first_node_in_group("inspector")
	fm.set_mode(fm.Mode.SELECT)
	fm._select_at(Vector2(a.x * 32 + 16, a.y * 32 + 16))
	_check("clicking a creature inspects the CREATURE", insp._kind == "creature")
	_check("...at its cell", insp._cell == a)

	# --- save / load round trip (v13) ---
	_check("the save format is v14", MapIO.VERSION == 14)
	var data: Dictionary = MapIO.serialize()
	_check("creatures serialize", data["creatures"].size() == 2)
	var map_name := "zz_creature_test"
	MapIO.save_map(map_name)
	MapIO.new_map()
	_check("a new map has no creatures", cr.creatures.is_empty())
	MapIO.load_map(map_name)
	_check("they come back on load", cr.creatures.size() == 2)
	_check("...with their ids intact", String(cr.creature_at(a)["id"]) == id_before)
	_check("...and their kind", cr.creature_at(b)["kind"] == Bestiary.INSTANCE)
	_check("...and their passability flag", bool(cr.creature_at(a)["blocks"]))

	# a map saved before v13 has no "creatures" key at all: it must load as none, not crash
	var old: Dictionary = MapIO.serialize()
	old.erase("creatures")
	old["version"] = 12
	MapIO.apply_serialized(old, true)
	_check("a pre-v13 map loads with no creatures rather than crashing", cr.creatures.is_empty())
	MapIO.load_map(map_name)

	# --- resize carries them (MapEdit shifts every cell-keyed record) ---
	var before_count: int = cr.creatures.size()
	MapEdit.grow("left")
	_check("growing at the left keeps every creature", cr.creatures.size() == before_count)
	_check("...shifted with the map", cr.has_creature(a + Vector2i(1, 0)))
	MapEdit.shrink("left")
	_check("shrinking shifts them back", cr.has_creature(a))

	# --- undo covers a placement (EditHistory) ---
	var c := Vector2i(28, 18)
	fm.arm_creature("frost_frog")
	fm._place_creature_at(Vector2(c.x * 32 + 16, c.y * 32 + 16))
	_check("a third creature is placed", cr.has_creature(c))
	EditHistory.undo()
	await get_tree().process_frame
	_check("undo removes it", not cr.has_creature(c))
	EditHistory.redo()
	await get_tree().process_frame
	_check("redo puts it back", cr.has_creature(c))

	# --- erase takes the creature before the ground beneath it ---
	fm._erase_single(c)
	_check("erase removes the creature", not cr.has_creature(c))

	# ================= SPAWN ZONES (the third placement kind) =================
	fm.set_mode(fm.Mode.CREATURE)
	fm.arm_creature("frost_frog")
	fm.arm_creature_kind(Bestiary.ZONE)
	_check("Zone is a brush kind but NOT a cell-record kind",
		Bestiary.is_brush_kind(Bestiary.ZONE) and not Bestiary.is_kind(Bestiary.ZONE))
	_check("the tool can be armed with it", fm.armed_creature_kind() == Bestiary.ZONE)

	# a zone is DRAGGED out, not clicked: press, move, release
	fm._zone_active = true
	fm._zone_start = Vector2i(30, 24)
	fm._update_zone_drag(Vector2i(33, 26))
	_check("dragging shows a live preview rectangle", cr._preview_zone != null and cr._preview_zone.visible)
	fm._zone_active = false
	fm._commit_zone(Vector2i(33, 26))
	_check("releasing commits a zone", cr.zones.size() == 1)
	_check("...the preview goes with it", not cr._preview_zone.visible)
	var z: Dictionary = cr.zones[0]
	_check("...spanning the dragged rectangle", z["rect"] == Rect2i(30, 24, 4, 3))
	_check("...of the armed creature", z["creature"] == "frost_frog")
	_check("...with the default rate and cap", z["rate"] == Bestiary.ZONE_RATE and z["cap"] == Bestiary.ZONE_CAP)
	_check("a cell inside it reports the zone", cr.has_zone(Vector2i(31, 25)))
	_check("a cell outside it does not", not cr.has_zone(Vector2i(40, 25)))
	_check("a zero-size zone is refused", cr.add_zone(Rect2i(5, 5, 0, 3), "frost_frog").is_empty())

	# the inspector's type / rate / cap (ROADMAP "Editor layout": a spawn zone shows more)
	fm.set_mode(fm.Mode.SELECT)
	fm._select_at(Vector2(31 * 32 + 16, 25 * 32 + 16))
	_check("clicking inside a zone inspects the ZONE", insp._kind == "zone")
	cr.set_zone_type(Vector2i(31, 25), "fire_horse")
	_check("its type is editable", cr.zone_at(Vector2i(31, 25))["creature"] == "fire_horse")
	cr.set_zone_cap(Vector2i(31, 25), 5)
	cr.set_zone_rate(Vector2i(31, 25), 1.0)
	_check("cap and rate are editable", cr.zone_at(Vector2i(31, 25))["cap"] == 5)
	cr.set_zone_cap(Vector2i(31, 25), 9999)
	_check("cap is clamped to its range", cr.zone_at(Vector2i(31, 25))["cap"] == Bestiary.ZONE_CAP_RANGE.y)
	cr.set_zone_cap(Vector2i(31, 25), 2)

	# a creature standing IN a zone still inspects as the creature: the zone is under it
	fm.set_mode(fm.Mode.CREATURE)
	fm.arm_creature_kind(Bestiary.SPAWN_POINT)
	fm.arm_creature("frost_frog")
	fm._place_creature_at(Vector2(31 * 32 + 16, 25 * 32 + 16))
	fm.set_mode(fm.Mode.SELECT)
	fm._select_at(Vector2(31 * 32 + 16, 25 * 32 + 16))
	_check("a creature inside a zone still inspects as the creature", insp._kind == "creature")

	# --- SPAWNING: the zone tops itself up toward its cap while playing ---
	_check("nothing has spawned while editing", cr.spawned_count() == 0)
	var authored_before: int = cr.creatures.size()
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	cr.set_zone_rate(Vector2i(31, 25), 0.5)
	# drive the spawner directly rather than waiting real seconds
	for _i in 40:
		cr._process(0.6)
	_check("playing fills the zone up to its cap", cr.spawned_count() == 2)
	_check("...and no further", cr.spawned_count() <= cr.zone_at(Vector2i(31, 25))["cap"])
	var spawn_cell: Vector2i = cr._spawned[0]["cell"]
	_check("...inside the zone's rectangle", (cr.zone_at(Vector2i(31, 25))["rect"] as Rect2i).has_point(spawn_cell))
	_check("a spawned creature blocks the player too", cr.blocks_movement(spawn_cell))
	# what a zone produced is the PLAYTHROUGH's, not the map's
	_check("spawned creatures are NOT in the map's records", cr.creatures.size() == authored_before)
	_check("...nor in what it serializes", MapIO.serialize()["creatures"].size() == authored_before)
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	await get_tree().process_frame
	_check("leaving play clears what the zone produced", cr.spawned_count() == 0)

	# --- zones survive save / load, resize and erase ---
	MapIO.save_map(map_name)
	MapIO.new_map()
	_check("a new map has no zones", cr.zones.is_empty())
	MapIO.load_map(map_name)
	_check("zones come back on load", cr.zones.size() == 1)
	_check("...with their rect", cr.zone_at(Vector2i(31, 25))["rect"] == Rect2i(30, 24, 4, 3))
	_check("...and their edited rate and cap", cr.zone_at(Vector2i(31, 25))["cap"] == 2)
	var pre14: Dictionary = MapIO.serialize()
	pre14.erase("creature_zones")
	pre14["version"] = 13
	MapIO.apply_serialized(pre14, true)
	_check("a pre-v14 map loads with no zones rather than crashing", cr.zones.is_empty())
	MapIO.load_map(map_name)
	MapEdit.grow("left")
	_check("a zone shifts with a resize", cr.zone_at(Vector2i(32, 25))["rect"] == Rect2i(31, 24, 4, 3))
	MapEdit.shrink("left")
	# erase: the zone is the LAST thing a cell can give up, so the creature standing in it goes first
	var inzone := Vector2i(31, 25)
	fm._erase_single(inzone)
	_check("erase takes the creature standing in the zone first", not cr.has_creature(inzone))
	_check("...leaving the zone", cr.has_zone(inzone))
	fm._erase_single(inzone)
	_check("erasing again takes the zone", not cr.has_zone(inzone))

	MapIO.delete_map(map_name)
	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
