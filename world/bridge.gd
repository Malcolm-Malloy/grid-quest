extends Node2D

# A crossable bridge deck placed over water. It re-enables crossing on a water cell that would
# otherwise block the player (passable-over-impassable): the player's move check treats a bridged
# water cell as walkable (see player.gd + obstacles.is_bridge). The deck is drawn procedurally per
# orientation as shaded planks (alternating tone + lit leading edge + dark seam), nail heads at the
# plank ends, side rails with a highlight, and corner posts, so it reads as a plank bridge at native
# 32px rather than a lighter-brown block. Still FLAT / top-down (no ramp or rail-height art yet).
# Directional like a gate: one node per placed record, positioned at the cell centre, drawing relative
# to it. Both orientations (and the lifted preview) share this _draw, so they stay in sync.
#
# orientation HORIZONTAL: you cross EAST-WEST (over a river running north-south). Boards are
#   vertical slats; the two rails run along the TOP and BOTTOM edges (parallel to travel).
# orientation VERTICAL: you cross NORTH-SOUTH (over a river running east-west). Boards are
#   horizontal; the rails run along the LEFT and RIGHT edges.

const CELL_SIZE := Grid.CELL

# wooden deck palette (warmer/lighter than the brown river bank so the two read as different things).
# High-contrast plank shading + rails so the planking reads at native 32px, not just as a dirt patch.
const DECK := Color(0.62, 0.45, 0.27)    # light warm plank (default board)
const PLANK_LO := Color(0.52, 0.37, 0.21) # alternate darker board, so individual planks read
const PLANK_HI := Color(0.74, 0.56, 0.34) # lit leading edge of each plank
const SEAM := Color(0.28, 0.18, 0.10)    # dark gaps between boards
const RAIL := Color(0.34, 0.23, 0.13)    # dark side rails (framing edge)
const RAIL_HI := Color(0.76, 0.58, 0.36) # rail top highlight
const NAIL := Color(0.22, 0.14, 0.08)    # nail heads at the plank ends, by the rails
const POST := Color(0.25, 0.16, 0.09)    # corner posts (rail ends)

var orientation: Grid.Orient = Grid.Orient.HORIZONTAL
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

const BOARD := 7.0 # plank width in px

func _draw() -> void:
	var h := CELL_SIZE / 2.0
	draw_rect(Rect2(-h, -h, CELL_SIZE, CELL_SIZE), DECK)
	var i := 0
	if orientation == Grid.Orient.VERTICAL:
		# cross N-S: horizontal planks (step down y), rails on LEFT + RIGHT
		var y := -h
		while y < h:
			var bh: float = minf(BOARD, h - y)
			if i % 2 == 1:
				draw_rect(Rect2(-h, y, CELL_SIZE, bh), PLANK_LO) # alternate board tone
			draw_line(Vector2(-h, y + 0.5), Vector2(h, y + 0.5), PLANK_HI, 1.0)       # lit leading edge
			draw_line(Vector2(-h, y + bh - 0.5), Vector2(h, y + bh - 0.5), SEAM, 1.0) # dark seam
			draw_rect(Rect2(-h + 4, y + bh / 2.0 - 1, 2, 2), NAIL) # nail near the left rail
			draw_rect(Rect2(h - 6, y + bh / 2.0 - 1, 2, 2), NAIL)  # nail near the right rail
			y += BOARD
			i += 1
		draw_rect(Rect2(-h, -h, 4, CELL_SIZE), RAIL)
		draw_rect(Rect2(h - 4, -h, 4, CELL_SIZE), RAIL)
		draw_line(Vector2(-h + 3.5, -h), Vector2(-h + 3.5, h), RAIL_HI, 1.0)
		draw_line(Vector2(h - 3.5, -h), Vector2(h - 3.5, h), RAIL_HI, 1.0)
	else:
		# cross E-W: vertical planks (step across x), rails on TOP + BOTTOM
		var x := -h
		while x < h:
			var bw: float = minf(BOARD, h - x)
			if i % 2 == 1:
				draw_rect(Rect2(x, -h, bw, CELL_SIZE), PLANK_LO) # alternate board tone
			draw_line(Vector2(x + 0.5, -h), Vector2(x + 0.5, h), PLANK_HI, 1.0)       # lit leading edge
			draw_line(Vector2(x + bw - 0.5, -h), Vector2(x + bw - 0.5, h), SEAM, 1.0) # dark seam
			draw_rect(Rect2(x + bw / 2.0 - 1, -h + 4, 2, 2), NAIL) # nail near the top rail
			draw_rect(Rect2(x + bw / 2.0 - 1, h - 6, 2, 2), NAIL)  # nail near the bottom rail
			x += BOARD
			i += 1
		draw_rect(Rect2(-h, -h, CELL_SIZE, 4), RAIL)
		draw_rect(Rect2(-h, h - 4, CELL_SIZE, 4), RAIL)
		draw_line(Vector2(-h, -h + 3.5), Vector2(h, -h + 3.5), RAIL_HI, 1.0)
		draw_line(Vector2(-h, h - 3.5), Vector2(h, h - 3.5), RAIL_HI, 1.0)
	# corner posts (the rail ends), drawn last so they sit over the rails; same 4 corners either way
	for py in [-h, h - 5.0]:
		for px in [-h, h - 5.0]:
			draw_rect(Rect2(px, py, 5, 5), POST)
			draw_rect(Rect2(px, py, 5, 1), RAIL_HI) # tiny lit top
