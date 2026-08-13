extends Node2D
class_name GridBackground

const CELL_SIZE := 32
const GRID_WIDTH := 20
const GRID_HEIGHT := 14
const FLOOR_TEX := 128 # floor textures are 128x128, tiled by world position

var ground_texture := preload("res://sprites/ground_grass.png")

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	queue_redraw()

# the source rect that makes a destination rect sample a 128x128 floor texture tiled by
# world position, so neighbouring pieces line up into one continuous floor (shared by the
# shadow-manager stamp). Works for full cells and half-cell wall quadrants alike.
static func tiled_src(dst: Rect2) -> Rect2:
	return Rect2(fposmod(dst.position.x, float(FLOOR_TEX)), fposmod(dst.position.y, float(FLOOR_TEX)), dst.size.x, dst.size.y)

func _draw() -> void:
	draw_texture(ground_texture, Vector2.ZERO)
	# any room with a floor style fills its WHOLE area (interior cells + the room-facing
	# wall/door quadrants) with that texture, so no grass shows between floor and walls.
	# FloorManager supplies the [dst_rect, texture] pieces; they tile by world position.
	var fm := get_node_or_null("../FloorManager")
	if fm:
		for f in fm.base_fills():
			draw_texture_rect_region(f[1], f[0], tiled_src(f[0]))
	# the reference grid draws only when toggled on from the floor menu (off by default so
	# it doesn't tint the floor textures the rest of the time)
	if fm and fm.grid_on():
		var color: Color = fm.grid_color()
		for x in range(GRID_WIDTH + 1):
			draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, GRID_HEIGHT * CELL_SIZE), color, 1.0, true)
		for y in range(GRID_HEIGHT + 1):
			draw_line(Vector2(0, y * CELL_SIZE), Vector2(GRID_WIDTH * CELL_SIZE, y * CELL_SIZE), color, 1.0, true)
