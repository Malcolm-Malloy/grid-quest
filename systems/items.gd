extends Node

# Items (autoload): the ITEM DEFINITION registry and the shared RARITY scale.
#
# The roadmap's structural call (ROADMAP "Items and pickups"): a DEFINITION is the reusable type
# (key, coin, ...) with no world position; a PICKUP INSTANCE is a definition placed at a cell with a
# durable id. This file owns the definitions; `world/pickups.gd` owns the instances. Keys are only
# the first item, so nothing here is key-shaped: a definition is data, and new types are one entry.
#
# INTERACTION IS A PROPERTY OF THE TYPE, not of the pickup code (ROADMAP, refined 2026-08-16):
#   kind "stack"  -> auto-collects when the player steps on it (coins, collectibles, consumables),
#                    and stacks in the inventory as {item id: count}.
#   kind "unique" -> never grabbed by walking; the player must deliberately CLICK it, and it enters
#                    the inventory as its own entry (a Unique key will carry its door_id here).
#
# RARITY is one shared scale so items and (later) creatures use the same colours, per ROADMAP "Item
# rarity and rarity highlight" -> "the same colour coding reused for minion / creature rarity ...
# one shared enum + palette that both reference, not two parallel systems".

enum Rarity { JUNK, COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

# The 2026-08-16 decided ramp, low to high. Top tier is ORANGE-gold rather than pure gold: a thin
# pure-yellow outline goes muddy on light or sandy floors, so it is pushed warm and bright.
const RARITY_COLORS := [
	Color(0.55, 0.55, 0.58), # JUNK      grey
	Color(0.96, 0.96, 0.96), # COMMON    white
	Color(0.30, 0.85, 0.35), # UNCOMMON  green
	Color(0.30, 0.60, 1.00), # RARE      blue
	Color(0.70, 0.40, 0.95), # EPIC      purple
	Color(1.00, 0.60, 0.15), # LEGENDARY orange-gold
]
const RARITY_NAMES := ["Junk", "Common", "Uncommon", "Rare", "Epic", "Legendary"]
# The REQUIRED non-colour cue (ROADMAP: "rarity must never be colour-only" -- green/blue/purple are
# the colourblind confusion zone). Outline thickness steps up with rarity, so the tier reads by shape
# as well as hue. A rarity pip on the item is the other suggested cue, still open.
const RARITY_WIDTH := [1.0, 1.5, 2.0, 2.5, 3.0, 3.5]

# The definitions. `body` is the procedural glyph pickup.gd draws (no item art exists yet, matching
# how walls/water/lava are drawn procedurally); `tint` is that glyph's colour.
const DEFS := {
	"coin": {
		"name": "Coin", "kind": "stack", "rarity": Rarity.COMMON,
		"body": "disc", "tint": Color(0.95, 0.78, 0.25),
	},
	"gem": {
		"name": "Gem", "kind": "stack", "rarity": Rarity.RARE,
		"body": "gem", "tint": Color(0.45, 0.85, 0.95),
	},
	"key": {
		# the first UNIQUE item, and the one locked doors (ROADMAP item 11) will consume. Binding a
		# key to a specific door (`door_id`) lands with that item; today a key is just a key.
		"name": "Key", "kind": "unique", "rarity": Rarity.EPIC,
		"body": "key", "tint": Color(0.93, 0.85, 0.45),
	},
}

# --- definitions ---

func ids() -> Array:
	return DEFS.keys()

func has(item: String) -> bool:
	return DEFS.has(item)

# the definition dict for `item`, or {} if unknown (a map saved with an item this build no longer
# knows loads as nothing rather than crashing)
func def(item: String) -> Dictionary:
	return DEFS.get(item, {})

func display_name(item: String) -> String:
	return String(DEFS.get(item, {}).get("name", item))

func is_stackable(item: String) -> bool:
	return String(DEFS.get(item, {}).get("kind", "stack")) == "stack"

func rarity_of(item: String) -> int:
	return int(DEFS.get(item, {}).get("rarity", Rarity.COMMON))

func rarity_color(item: String) -> Color:
	return RARITY_COLORS[clampi(rarity_of(item), 0, RARITY_COLORS.size() - 1)]

func rarity_width(item: String) -> float:
	return RARITY_WIDTH[clampi(rarity_of(item), 0, RARITY_WIDTH.size() - 1)]

func rarity_name(item: String) -> String:
	return RARITY_NAMES[clampi(rarity_of(item), 0, RARITY_NAMES.size() - 1)]

# --- instance ids (Architecture review Q3: placed things carry a DURABLE id) ---

# A random id, not a counter: nothing has to store "the next number", ids stay unique when a map is
# pasted into another map, and a Unique key's door reference keeps resolving across saves. Minted at
# placement and carried through save/load, resize and move; a PASTE deliberately mints a fresh one.
func new_id() -> String:
	return "%08x" % (randi() & 0x7fffffff)
