extends Node

# Bestiary (autoload): the CREATURE DEFINITION registry, the creature half of the same split the
# items system uses (ROADMAP "Items and pickups" -> definition vs instance, and "Creature placement
# in the editor"). A DEFINITION is the reusable type (Frost Frog, Fire Horse, ...) with no world
# position; a PLACED CREATURE is a definition put on a cell with a durable id, owned by
# `world/creatures.gd`. Named Bestiary rather than Creatures so the definition registry and the
# world node that holds the instances never read as the same thing.
#
# THIS IS THE EDITOR HALF ONLY. The creature PILLAR -- roaming AI, fighting, Subdued/Entranced
# capture, domestication, absorb -- is Phase C and is NOT built. What exists here is everything the
# editor needs to author creatures into a map and save them, so the AI has something to wake up to.
#
# RARITY IS THE SHARED SCALE, not a parallel one: ROADMAP "Item rarity and rarity highlight" calls
# for "one shared enum + palette that both reference, not two parallel systems", so a creature's
# rarity is an `Items.Rarity` and its colour comes from `Items.rarity_color`. Durable ids come from
# `Items.new_id()` for the same reason -- one minter, so ids never collide across object types.

# The three starter monsters (ROADMAP "Initial monsters": build these three first, one ability each).
# `ability` is recorded from the spec but NOT implemented -- there is no combat yet; it is here so the
# roster carries the design intent rather than leaving it in the doc only.
# `body` is the procedural glyph creature_marker.gd draws: no creature art exists yet, matching how
# walls, water, lava and pickups are all drawn procedurally until art arrives.
const DEFS := {
	"frost_frog": {
		"name": "Frost Frog", "rarity": Items.Rarity.COMMON,
		"body": "frog", "tint": Color(0.45, 0.72, 0.95),
		"ability": "Shoots a ball of ice at the player.",
	},
	"fire_horse": {
		"name": "Fire Horse", "rarity": Items.Rarity.RARE,
		"body": "horse", "tint": Color(0.95, 0.45, 0.18),
		"ability": "Breathes fire at the player.",
	},
	"breaker_monkey": {
		"name": "Breaker Monkey", "rarity": Items.Rarity.UNCOMMON,
		"body": "monkey", "tint": Color(0.62, 0.44, 0.28),
		"ability": "Knocks down wood fences (higher-tier walls as its ability levels).",
	},
}

# How a creature is authored onto the map (ROADMAP "Creature placement in the editor": all three).
# SPAWN_POINT and INSTANCE are single-cell records and are built; ZONE needs region storage plus a
# spawn timer/cap and is deliberately left for later, per that section's own build-order note.
const SPAWN_POINT := "spawn"   # a spot that spawns this creature at play start, then it roams (AI: Phase C)
const INSTANCE := "instance"   # this exact creature, exactly here: scripted / boss / unique / quest
const KINDS := [SPAWN_POINT, INSTANCE]  # the two CELL kinds: what a single placed record can be
const KIND_NAMES := {SPAWN_POINT: "Spawn Point", INSTANCE: "Fixed Instance"}

# The third kind, added 2026-09-05: a REGION rather than a cell, for populating wild areas. It is not
# in KINDS because a zone is not something a creature record can be -- a zone is its own record with a
# rect and spawn rules, and it is authored by dragging rather than by clicking a cell. It shares the
# Creature tool, so it joins the kinds the BRUSH can be armed with.
const ZONE := "zone"
const BRUSH_KINDS := [SPAWN_POINT, INSTANCE, ZONE]
const BRUSH_KIND_NAMES := {SPAWN_POINT: "Spawn Point", INSTANCE: "Fixed Instance", ZONE: "Zone"}

# Zone spawn rules (ROADMAP: "flagged to periodically spawn a chosen type within it ... the zone
# stores a region + spawn rules (rate, cap)"). Defaults chosen to read clearly the moment you press
# Play: a few seconds apart, and a handful at a time rather than a swarm.
const ZONE_RATE := 4.0   # seconds between spawn attempts
const ZONE_CAP := 3      # live creatures this zone will maintain
const ZONE_RATE_RANGE := Vector2(0.5, 60.0)
const ZONE_CAP_RANGE := Vector2i(1, 20)

func ids() -> Array:
	return DEFS.keys()

func has(creature: String) -> bool:
	return DEFS.has(creature)

# the definition dict for `creature`, or {} if unknown -- a map saved with a creature this build no
# longer knows loads as nothing rather than crashing (same contract as Items.def)
func def(creature: String) -> Dictionary:
	return DEFS.get(creature, {})

func display_name(creature: String) -> String:
	return String(DEFS.get(creature, {}).get("name", creature))

func ability(creature: String) -> String:
	return String(DEFS.get(creature, {}).get("ability", ""))

func rarity_of(creature: String) -> int:
	return int(DEFS.get(creature, {}).get("rarity", Items.Rarity.COMMON))

# straight through to the shared item scale, so a Rare creature and a Rare item are the same blue
func rarity_color(creature: String) -> Color:
	return Items.RARITY_COLORS[clampi(rarity_of(creature), 0, Items.RARITY_COLORS.size() - 1)]

func rarity_name(creature: String) -> String:
	return Items.RARITY_NAMES[clampi(rarity_of(creature), 0, Items.RARITY_NAMES.size() - 1)]

func kind_name(kind: String) -> String:
	return String(BRUSH_KIND_NAMES.get(kind, kind))

# is this a kind a single placed CELL record can be? (a zone is not: it is its own record)
func is_kind(kind: String) -> bool:
	return KINDS.has(kind)

# is this a kind the Creature TOOL can be armed with? (the two cell kinds plus zone)
func is_brush_kind(kind: String) -> bool:
	return BRUSH_KINDS.has(kind)

# Whether this creature blocks the player by default. ROADMAP "Passability": type defaults with a
# per-object override, and "monster = blocks while alive". Every creature blocks today; the field
# exists so a future decorative type can default the other way, and the per-instance override in the
# inspector handles the one-off exceptions.
func blocks_by_default(_creature: String) -> bool:
	return true
