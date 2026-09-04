extends Node2D

# One placed item sitting on the ground: the visual half of a pickup instance (the model lives in
# world/pickups.gd). Draws the item's glyph plus its RARITY OUTLINE, per ROADMAP "Item rarity and
# rarity highlight": a coloured ring around the item with NO fill, Diablo-style, readable at a glance
# while the item is on the floor.
#
# Three render rules from that spec, all implemented here:
#  - CONTRAST ON ANY FLOOR: the ring is drawn dark first, one step wider, so a white or gold outline
#    still reads over a pale coloured-floor tile.
#  - NON-COLOUR CUE: ring thickness steps up with rarity (Items.RARITY_WIDTH), so the tier is legible
#    without relying on the green/blue/purple hues a colourblind player cannot separate.
#  - It is a GAMEPLAY render on the item, deliberately unrelated to the editor's action-highlight
#    palette (orange ground / green add / red erase), which happens to share some hue names.
#
# Per the standing convention it sets the floor-highlight mask bit and y-sorts like other ground
# objects, so the room highlight is excluded from it and walls occlude it correctly.

const CELL := 32
const R := 8.0          # glyph radius; the ring sits just outside it
const RING_R := 11.0
const DARK := Color(0.05, 0.05, 0.08, 0.85)
const BOB := 1.5        # gentle idle bob so a dropped item catches the eye
const BOB_HZ := 1.2

var cell := Vector2i.ZERO
var item := "coin"
var id := ""
var data := {} # per-instance extra: a Unique key's {door_id, name}

var _t := 0.0

func _ready() -> void:
	add_to_group("pickups")
	z_index = 5 # above the floor, below the editor cursors; y-sorting orders it against the player
	visibility_layer |= FloorHighlightMask.MASK_BIT

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var d := Items.def(item)
	if d.is_empty():
		return # a map placed an item this build no longer defines: draw nothing rather than crash
	var lift := sin(_t * TAU * BOB_HZ) * BOB
	var c := Vector2(0, -R * 0.5 + lift)
	# contact shadow on the ground, so the lift reads as hovering rather than as a mis-placed sprite
	draw_circle(Vector2(0, 2), R * 0.55, Color(0, 0, 0, 0.20))
	# the rarity ring: dark backing first (contrast on any floor), then the tier colour at its width
	var w: float = Items.rarity_width(item)
	draw_arc(c, RING_R, 0.0, TAU, 26, DARK, w + 2.0)
	draw_arc(c, RING_R, 0.0, TAU, 26, Items.rarity_color(item), w)
	# the item glyph itself
	var tint: Color = d.get("tint", Color.WHITE)
	match String(d.get("body", "disc")):
		"gem":
			var gem := PackedVector2Array([c + Vector2(0, -R), c + Vector2(R * 0.75, 0),
				c + Vector2(0, R), c + Vector2(-R * 0.75, 0)])
			draw_colored_polygon(gem, tint)
			draw_polyline(gem + PackedVector2Array([gem[0]]), DARK, 1.0)
		"key":
			# bow (the ring you hold) + shaft + two teeth, drawn small enough to read at editor zoom
			draw_arc(c + Vector2(-R * 0.35, 0), R * 0.45, 0.0, TAU, 14, tint, 2.5)
			draw_line(c + Vector2(-R * 0.05, 0), c + Vector2(R * 0.8, 0), tint, 2.5)
			draw_line(c + Vector2(R * 0.45, 0), c + Vector2(R * 0.45, R * 0.5), tint, 2.0)
			draw_line(c + Vector2(R * 0.75, 0), c + Vector2(R * 0.75, R * 0.5), tint, 2.0)
		_:
			draw_circle(c, R * 0.6, tint)
			draw_arc(c, R * 0.6, 0.0, TAU, 18, DARK, 1.0)

func place(at_cell: Vector2i) -> void:
	cell = at_cell
	position = Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0)
