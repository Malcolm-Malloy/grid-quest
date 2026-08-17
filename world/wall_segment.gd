extends Node2D

const CELL_SIZE := 32
const WALL_HEIGHT := 7
const CAP_HEIGHT := WALL_HEIGHT + 4 # thickness used for a horizontal wall's top face
const FACE_SHADE := 0.62 # the front face is in shadow, so its colour is darkened by this

var run_length: int = 1
var align_offset_x: float = 0.0 # shifts the thin strip to hug a tile edge, for joining a corner

# corner pieces override the horizontal extent explicitly so they reach inward to
# the neighbour but stop flush with the vertical rail on the outer side (an L, not
# a T). seg_width <= 0 means "use the automatic full/thin width".
var seg_width: float = 0.0
var seg_x_start: float = 0.0

# one Color per covered cell (top to bottom); a tint multiplied over the stone. Missing or short
# entries default to white (natural stone). Set by Obstacles from its wall_colors store.
var cell_colors: Array = []

# one material name per covered cell (top to bottom); picks the face/cap texture pair for that cell.
# Missing or short entries default to "stone". Set by Obstacles from its wall_materials store, parallel
# to cell_colors: a wall carries an independent colour tint AND material per cell.
var cell_materials: Array = []

# material name -> [face_texture, cap_texture]. Stone is the default/legacy pair. Wood and slate are
# style swaps (ROADMAP "Terrain patterns and material variants" -> wall materials).
const MATERIALS := {
	"stone": [preload("res://world/stone_face.png"), preload("res://world/stone_cap.png")],
	"wood": [preload("res://world/wood_face.png"), preload("res://world/wood_cap.png")],
	"slate": [preload("res://world/slate_face.png"), preload("res://world/slate_cap.png")],
}

var face_texture := preload("res://world/stone_face.png")
var cap_texture := preload("res://world/stone_cap.png")

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	texture_repeat = TEXTURE_REPEAT_ENABLED # per-cell slices region-sample a tiled texture
	visibility_layer |= FloorHighlightMask.MASK_BIT # occlude the floor-highlight mask
	add_to_group("walls") # so a map reload can free every spawned wall in one sweep
	queue_redraw()
	# NOTE: walls no longer cast their own shadow. The whole structure's shadow is
	# built once by obstacles.gd after the map loads (see Obstacles.spawn_shadows),
	# so it reads as one continuous cast instead of per-piece polygons.

# the run's covered cells, top to bottom. Its position is the bottom cell's centre and it
# extends up `run_length` cells (single-cell for horizontal pieces and corners).
func cells() -> Array:
	var col := int(round((position.x - CELL_SIZE / 2.0) / CELL_SIZE))
	var bottom_row := int(round((position.y - CELL_SIZE / 2.0) / CELL_SIZE))
	var out: Array = []
	for i in run_length:
		out.append(Vector2i(col, bottom_row - run_length + 1 + i))
	return out

# index of `cell` within the run, 0 = top. -1 if this run does not cover it.
func _cell_index(cell: Vector2i) -> int:
	var col := int(round((position.x - CELL_SIZE / 2.0) / CELL_SIZE))
	if cell.x != col:
		return -1
	var bottom_row := int(round((position.y - CELL_SIZE / 2.0) / CELL_SIZE))
	var i := cell.y - (bottom_row - run_length + 1)
	return i if i >= 0 and i < run_length else -1

# true if this segment stands on `cell` (used by the ground editor's obstacle fade).
func covers_cell(cell: Vector2i) -> bool:
	return _cell_index(cell) != -1

func _cell_color(i: int) -> Color:
	return cell_colors[i] if i >= 0 and i < cell_colors.size() else Color.WHITE

# the material name for cell `i` (default "stone" when unset/short)
func _cell_material(i: int) -> String:
	return cell_materials[i] if i >= 0 and i < cell_materials.size() else "stone"

# the [face, cap] texture pair for cell `i`'s material (falls back to stone for an unknown name)
func _cell_textures(i: int) -> Array:
	return MATERIALS.get(_cell_material(i), MATERIALS["stone"])

# horizontal extent of the drawn body as [x_start, width], honouring an explicit
# corner override when one is set
func get_x_extent() -> Array:
	if seg_width > 0.0:
		return [seg_x_start, seg_width]
	var width := CAP_HEIGHT if run_length > 1 else CELL_SIZE
	return [-width / 2.0 + align_offset_x, float(width)]

# the cap slice + (bottom cell only) face rect for `cell`, in WORLD-LOCAL coords (position +
# local). Used by the wall highlight to trace the exact wall silhouette.
func piece_rects(cell: Vector2i) -> Array:
	var i := _cell_index(cell)
	if i == -1:
		return []
	var g := _geometry()
	var x_start: float = g[0]
	var width: float = g[1]
	var top_edge: float = g[2]
	var cap_top: float = g[3]
	var cap_bottom: float = g[4]
	var face_height: float = g[5]
	var slice_top: float = cap_top if i == 0 else top_edge + i * CELL_SIZE
	var slice_bottom: float = cap_bottom if i == run_length - 1 else top_edge + (i + 1) * CELL_SIZE
	var out: Array = []
	if slice_bottom > slice_top:
		out.append(Rect2(position.x + x_start, position.y + slice_top, width, slice_bottom - slice_top))
	if i == run_length - 1:
		out.append(Rect2(position.x + x_start, position.y + cap_bottom, width, face_height))
	return out

# shared geometry (local coords, node origin = bottom-cell centre):
# [x_start, width, top_edge, cap_top, cap_bottom, face_height]
func _geometry() -> Array:
	var bottom_edge := CELL_SIZE / 2.0
	var face_height := float(CELL_SIZE - 4)
	var top_edge := bottom_edge - run_length * CELL_SIZE
	var extent := get_x_extent()
	return [extent[0], extent[1], top_edge, top_edge - WALL_HEIGHT, bottom_edge - face_height, face_height]

func _draw() -> void:
	var g := _geometry()
	var x_start: float = g[0]
	var width: float = g[1]
	var top_edge: float = g[2]
	var cap_top: float = g[3]
	var cap_bottom: float = g[4]
	var face_height: float = g[5]
	# the cap and face each tile from a fixed origin, so slices line up seamlessly AND match the
	# pre-colour single-rect phase (an uncoloured/white wall looks identical to before).
	var cap_origin := Vector2(x_start, cap_top)
	var face_origin := Vector2(x_start, cap_bottom)

	# cap: one slice per cell, so each cell can carry its own colour AND material
	for i in run_length:
		var slice_top: float = cap_top if i == 0 else top_edge + i * CELL_SIZE
		var slice_bottom: float = cap_bottom if i == run_length - 1 else top_edge + (i + 1) * CELL_SIZE
		if slice_bottom > slice_top:
			_stamp(_cell_textures(i)[1], Rect2(x_start, slice_top, width, slice_bottom - slice_top), cap_origin, _cell_color(i))

	# front face: only the bottom cell shows one (the run is seen edge-on), tinted darker, in the
	# bottom cell's material
	var fc := _cell_color(run_length - 1)
	_stamp(_cell_textures(run_length - 1)[0], Rect2(x_start, cap_bottom, width, face_height), face_origin,
			Color(fc.r * FACE_SHADE, fc.g * FACE_SHADE, fc.b * FACE_SHADE, 1.0))

# draw `tex` into `dst` sampling it tiled from `origin`, tinted by `color`. Tiling by a fixed
# origin (not per-slice) keeps neighbouring slices continuous; texture_repeat handles the wrap.
func _stamp(tex: Texture2D, dst: Rect2, origin: Vector2, color: Color) -> void:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var src := Rect2(fposmod(dst.position.x - origin.x, tw), fposmod(dst.position.y - origin.y, th), dst.size.x, dst.size.y)
	draw_texture_rect_region(tex, dst, src, color)
