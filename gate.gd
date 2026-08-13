extends Node2D

const CELL_SIZE := 32
const WALL_HEIGHT := 7 # must match wall_segment.gd's cap height
const VERTICAL_WIDTH := 11 # must match wall_segment.gd's CAP_HEIGHT
const VERTICAL_OPEN_WIDTH := 56 # wider canvas for the vertical gate's swung-open braced door
const FRONT_SPLIT_ROW := 49 # texture rows below this are the front (bottom) post; above is back post + door
const BACK_LIFT := 8.0 # how far up (in y) the back layer sits, so y-sort puts it behind the player
const SHADOW_CAST := 12.0 # 45-degree shadow smear length; must match obstacles.SHADOW_CAST
const POST_W := 5.0 # horizontal-gate post thickness for its shadow

# "horizontal": embedded in a horizontal fence, walked through top-to-bottom.
# "vertical": embedded in a vertical fence, walked through left-to-right.
# more orientations/styles can be added the same way as the gate roster grows.
var orientation := "horizontal"

var cell: Vector2i
var is_open := false
var swing_right := true # vertical gates only: which side the panel swings toward
var swing_up := false # horizontal gates only: true when the door swings north (away)

var closed_texture: Texture2D
var open_texture: Texture2D # horizontal, swung south (toward camera): top + front
var open_texture_north: Texture2D # horizontal, swung north (away): top only
var open_texture_right: Texture2D
var open_texture_left: Texture2D

var back_layer: Node2D # vertical gates only: draws the back post + door behind the player

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	visibility_layer |= FloorHighlightMask.MASK_BIT # occlude the floor-highlight mask
	add_to_group("gates")
	# VERTICAL gates overlap the wall above/below in their own column, so they need
	# z_index 1 to draw over it. HORIZONTAL gates sit in a horizontal wall with floor
	# above and below, so they overlap no wall and stay at z_index 0, y-sorted with the
	# player: anything a row behind the player (north) then draws behind it, so a
	# horizontal gate no longer clips the player standing one row in front of it.
	z_index = 1 if orientation == "vertical" else 0
	if orientation == "vertical":
		closed_texture = preload("res://sprites/gate_vertical_closed.png")
		open_texture_right = preload("res://sprites/gate_vertical_open_right.png")
		open_texture_left = preload("res://sprites/gate_vertical_open_left.png")
		spawn_back_layer()
	else:
		closed_texture = preload("res://sprites/gate_closed.png")
		open_texture = preload("res://sprites/gate_open.png")
		open_texture_north = preload("res://sprites/gate_open_north.png")
	refresh_shadow.call_deferred() # draw once this gate is in the tree/group
	queue_redraw()

func spawn_back_layer() -> void:
	back_layer = Node2D.new()
	back_layer.set_script(load("res://gate_backlayer.gd"))
	back_layer.gate = self
	# a sibling of the gate in World, lifted up by BACK_LIFT so y-sort draws it
	# behind the player but still in front of the wall above
	back_layer.position = position - Vector2(0.0, BACK_LIFT)
	get_parent().add_child.call_deferred(back_layer)

func refresh_shadow() -> void:
	# a gate change flips which darkness layer is active (room dim vs wall shadows), so
	# refresh BOTH in the same frame; refreshing only the shadow layer here would let it
	# show a frame before the room light reacts, briefly leaving shadow inside the room.
	var group := get_parent().get_node_or_null("ShadowGroup")
	if group:
		group.refresh()
	var room_light := get_parent().get_node_or_null("RoomLight")
	if room_light:
		room_light.queue_redraw()

# polygons (world/grid space) this gate casts in its CURRENT state, for the shadow
# manager to merge with the walls. Each state is a set of [left,right,top,bottom]
# rects smeared down-right at 45 degrees.
func shadow_polys() -> Array:
	var out: Array = []
	for rect in _shadow_rects():
		var l: float = rect[0]
		var r: float = rect[1]
		var t: float = rect[2]
		var b: float = rect[3]
		out.append(PackedVector2Array([
			Vector2(l, t), Vector2(r, t),
			Vector2(r + SHADOW_CAST, t + SHADOW_CAST), Vector2(r + SHADOW_CAST, b + SHADOW_CAST),
			Vector2(l + SHADOW_CAST, b + SHADOW_CAST), Vector2(l, b),
		]))
	return out

func _shadow_rects() -> Array:
	var cx: int = cell.x
	var cy: int = cell.y
	var center_x := cx * CELL_SIZE + CELL_SIZE / 2.0
	var cell_top := float(cy * CELL_SIZE) # start at the cell top, not the cap, so no overhang
	var base := float(cy * CELL_SIZE + CELL_SIZE)
	var thin_l := center_x - VERTICAL_WIDTH / 2.0
	var thin_r := center_x + VERTICAL_WIDTH / 2.0
	var out: Array = []
	if orientation == "vertical":
		if not is_open:
			out.append([thin_l, thin_r, cell_top, base]) # closed: thin strip
		else:
			out.append([thin_l, thin_r, cell_top, cy * CELL_SIZE + 6.0]) # top post
			out.append([thin_l, thin_r, base - 6.0, base]) # bottom post
			if swing_right:
				out.append([center_x + 3.0, center_x + 24.0, cell_top, base]) # door east
			else:
				out.append([center_x - 24.0, center_x - 3.0, cell_top, base]) # door west
	else:
		var left := float(cx * CELL_SIZE)
		var right := float(cx * CELL_SIZE + CELL_SIZE)
		if not is_open:
			out.append([left, right, cell_top, base]) # closed: full-width strip
		else:
			out.append([left, left + POST_W, cell_top, base]) # left post
			out.append([right - POST_W, right, cell_top, base]) # right post
			if swing_up:
				out.append([left + 1.0, left + 6.0, cell_top - 22.0, cell_top + 4.0]) # door up
			else:
				out.append([left + 1.0, left + 6.0, base - 4.0, base + 22.0]) # door down
	return out

func set_open(value: bool) -> void:
	if value != is_open:
		is_open = value
		queue_redraw()
		if back_layer:
			back_layer.queue_redraw()
		refresh_shadow()

func set_swing_right(value: bool) -> void:
	if value != swing_right:
		swing_right = value
		if is_open:
			queue_redraw()
			if back_layer:
				back_layer.queue_redraw()
			refresh_shadow()

func set_swing_up(value: bool) -> void:
	if value != swing_up:
		swing_up = value
		if is_open:
			queue_redraw()
			refresh_shadow()

func set_player_here(value: bool) -> void:
	# horizontal gates: when the player is standing in this exact cell, both
	# are at the same y-sort position, and the tie happened to favor the
	# gate's posts drawing in front of (clipping) the character, so drop
	# behind them in that case. Vertical gates don't need this (and doing it
	# would drop the gate below the neighboring walls too, since both are
	# z_index 0, making the posts disappear wherever they overlap wall
	# territory) so they always stay at their normal priority.
	if orientation == "vertical":
		z_index = 1
	else:
		# on the cell: sit behind the player (doorway). Otherwise z_index 0 so y-sort
		# decides: gate behind the player when the player is south of it, in front when
		# north. (It overlaps no wall, so z_index 0 is safe.)
		z_index = -1 if value else 0

# local y of the open/closed vertical texture's top edge.
# top: extends up by face_height (28) from the plain cell edge, to reach the top
# of the wall-above's shaded face. bottom: the wall below's own cap already
# extends UP by WALL_HEIGHT past the plain cell edge, so stopping at the plain
# edge would overlap that cap by 7px; pull the bottom back by WALL_HEIGHT so it
# ends exactly where the wall-below's cap begins, with zero overlap.
func vertical_top() -> float:
	var face_height := CELL_SIZE - 4
	var plain_bottom := CELL_SIZE / 2.0
	return plain_bottom - (CELL_SIZE + face_height)

func _draw() -> void:
	if orientation == "vertical":
		var plain_bottom := CELL_SIZE / 2.0
		var bottom := plain_bottom - WALL_HEIGHT
		var top := vertical_top()
		var full_height := bottom - top
		if is_open:
			# only the front (bottom) post here, at z_index 1, so it still occludes
			# the player. The back post + swung door are drawn by back_layer, below
			# the player in y-sort, so the player passes in front of them.
			var texture := open_texture_right if swing_right else open_texture_left
			var src := Rect2(0.0, float(FRONT_SPLIT_ROW), VERTICAL_OPEN_WIDTH, full_height - FRONT_SPLIT_ROW)
			var dst := Rect2(-VERTICAL_OPEN_WIDTH / 2.0, top + FRONT_SPLIT_ROW, VERTICAL_OPEN_WIDTH, full_height - FRONT_SPLIT_ROW)
			draw_texture_rect_region(texture, dst, src)
		else:
			var rect := Rect2(Vector2(-VERTICAL_WIDTH / 2.0, top), Vector2(VERTICAL_WIDTH, full_height))
			draw_texture_rect(closed_texture, rect, false)
	else:
		# full fence height (face + cap), matching wall_segment's silhouette so
		# the gate's posts line up with the top of the surrounding wall pieces
		var full_height := (CELL_SIZE - 4) + WALL_HEIGHT
		var bottom_edge := CELL_SIZE / 2.0
		var top := bottom_edge - full_height
		if is_open:
			# the open texture is taller than the wall because the swung door hangs
			# out past the gate. Swung south (toward camera) the door hangs DOWN and
			# the posts sit at the texture top, so draw from the wall top. Swung north
			# (away) the door extends UP and the posts sit in the bottom `full_height`
			# rows, so shift the draw up so those posts still land on the wall.
			var tex := open_texture_north if swing_up else open_texture
			var oh := float(tex.get_height())
			var wall_top := (oh - full_height) if swing_up else 0.0
			draw_texture_rect(tex, Rect2(Vector2(-CELL_SIZE / 2.0, top - wall_top), Vector2(CELL_SIZE, oh)), false)
		else:
			draw_texture_rect(closed_texture, Rect2(Vector2(-CELL_SIZE / 2.0, top), Vector2(CELL_SIZE, full_height)), false)
