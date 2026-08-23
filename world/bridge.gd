extends Node2D

# A crossable bridge deck placed over water. It re-enables crossing on a water cell that would
# otherwise block the player (passable-over-impassable): the player's move check treats a bridged
# water cell as walkable (see player.gd + obstacles.is_bridge). Slice 1 is a FLAT, static wooden
# deck drawn procedurally per orientation, no ramp/rail-height art yet (mirrors the water slice-1
# "flat + still first" scope). Directional like a gate: one node per placed record, positioned at
# the cell centre, drawing relative to it.
#
# orientation "horizontal": you cross EAST-WEST (over a river running north-south). Boards are
#   vertical slats; the two rails run along the TOP and BOTTOM edges (parallel to travel).
# orientation "vertical": you cross NORTH-SOUTH (over a river running east-west). Boards are
#   horizontal; the rails run along the LEFT and RIGHT edges.

const CELL_SIZE := 32

# wooden deck palette (warmer/lighter than the brown river bank so the two read as different things).
# High-contrast seams + rails so the planking still reads at native 32px, not just as a dirt patch.
const DECK := Color(0.62, 0.45, 0.27)   # light warm plank
const SEAM := Color(0.30, 0.20, 0.11)   # dark gaps between boards
const RAIL := Color(0.34, 0.23, 0.13)   # dark side rails (framing edge)
const RAIL_HI := Color(0.74, 0.56, 0.34) # rail top highlight

var orientation := "horizontal"
var cell: Vector2i
# preview mode: the same deck art floated above the cursor by the BRIDGE tool (see FloorManager
# _update_bridge_hover). A preview must NOT join the "bridges" group (clear_world would free it) and
# draws lifted/translucent, high above the map. Set this true BEFORE add_child so _ready sees it.
var preview := false

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	if preview:
		z_index = 1200 # above the paint cursor (1000) / terrain preview (1200-), reads as lifted
		modulate.a = 0.7
		queue_redraw()
		return
	visibility_layer |= FloorHighlightMask.MASK_BIT # occlude the floor-highlight mask like other ground objects
	add_to_group("bridges")
	# below the player (z 0) so you walk ON the deck, but above the floor fills (GridBackground z -10)
	# and shadows (ShadowGroup z -5) so the deck covers the water it spans.
	z_index = -4
	queue_redraw()

func _draw() -> void:
	var h := CELL_SIZE / 2.0
	var deck := Rect2(-h, -h, CELL_SIZE, CELL_SIZE)
	draw_rect(deck, DECK)
	var board := 8.0 # board width in px
	if orientation == "vertical":
		# cross N-S: horizontal boards (horizontal seams), rails on left + right
		var y := -h + board
		while y < h:
			draw_line(Vector2(-h, y), Vector2(h, y), SEAM, 1.0)
			y += board
		draw_rect(Rect2(-h, -h, 3, CELL_SIZE), RAIL)
		draw_rect(Rect2(h - 3, -h, 3, CELL_SIZE), RAIL)
		draw_line(Vector2(-h + 1, -h), Vector2(-h + 1, h), RAIL_HI, 1.0)
		draw_line(Vector2(h - 2, -h), Vector2(h - 2, h), RAIL_HI, 1.0)
	else:
		# cross E-W: vertical boards (vertical seams), rails on top + bottom
		var x := -h + board
		while x < h:
			draw_line(Vector2(x, -h), Vector2(x, h), SEAM, 1.0)
			x += board
		draw_rect(Rect2(-h, -h, CELL_SIZE, 3), RAIL)
		draw_rect(Rect2(-h, h - 3, CELL_SIZE, 3), RAIL)
		draw_line(Vector2(-h, -h + 1), Vector2(h, -h + 1), RAIL_HI, 1.0)
		draw_line(Vector2(-h, h - 2), Vector2(h, h - 2), RAIL_HI, 1.0)
