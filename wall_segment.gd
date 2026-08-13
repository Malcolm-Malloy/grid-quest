extends Node2D

const CELL_SIZE := 32
const WALL_HEIGHT := 7
const CAP_HEIGHT := WALL_HEIGHT + 4 # thickness used for a horizontal wall's top face

var run_length: int = 1
var align_offset_x: float = 0.0 # shifts the thin strip to hug a tile edge, for joining a corner

# corner pieces override the horizontal extent explicitly so they reach inward to
# the neighbour but stop flush with the vertical rail on the outer side (an L, not
# a T). seg_width <= 0 means "use the automatic full/thin width".
var seg_width: float = 0.0
var seg_x_start: float = 0.0

var face_texture := preload("res://sprites/stone_face.png")
var cap_texture := preload("res://sprites/stone_cap.png")

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	visibility_layer |= FloorHighlightMask.MASK_BIT # occlude the floor-highlight mask
	queue_redraw()
	# NOTE: walls no longer cast their own shadow. The whole structure's shadow is
	# built once by obstacles.gd after the map loads (see Obstacles.spawn_shadows),
	# so it reads as one continuous cast instead of per-piece polygons.

# horizontal extent of the drawn body as [x_start, width], honouring an explicit
# corner override when one is set
func get_x_extent() -> Array:
	if seg_width > 0.0:
		return [seg_x_start, seg_width]
	var width := CAP_HEIGHT if run_length > 1 else CELL_SIZE
	return [-width / 2.0 + align_offset_x, float(width)]

func _draw() -> void:
	var face_height := CELL_SIZE - 4
	var bottom_edge := CELL_SIZE / 2.0
	var top_edge := bottom_edge - run_length * CELL_SIZE

	# a run extending away from camera is seen edge-on, so it should read as a thin
	# wall of the same thickness as a horizontal wall's cap, not a full tile wide
	var extent := get_x_extent()
	var x_start: float = extent[0]
	var width: float = extent[1]

	var cap_top := top_edge - WALL_HEIGHT
	var cap_bottom := bottom_edge - face_height

	# front face is in shadow (sun lights the top/cap, not this side), so tint it darker
	var face_rect := Rect2(Vector2(x_start, bottom_edge - face_height), Vector2(width, face_height))
	draw_texture_rect(face_texture, face_rect, true, Color(0.62, 0.62, 0.62, 1.0))

	var cap_rect := Rect2(Vector2(x_start, cap_top), Vector2(width, cap_bottom - cap_top))
	draw_texture_rect(cap_texture, cap_rect, true)
