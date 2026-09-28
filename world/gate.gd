class_name Gate
extends Node2D

const CELL_SIZE := Grid.CELL
const WALL_HEIGHT := 7 # must match wall_segment.gd's cap height
const VERTICAL_WIDTH := 11 # must match wall_segment.gd's CAP_HEIGHT
const VERTICAL_OPEN_WIDTH := 56 # wider canvas for the vertical gate's swung-open braced door
const FRONT_SPLIT_ROW := 49 # texture rows below this are the front (bottom) post; above is back post + door
const BACK_LIFT := 8.0 # how far up (in y) the back layer sits, so y-sort puts it behind the player
const SHADOW_CAST := 12.0 # 45-degree shadow smear length; must match obstacles.SHADOW_CAST
const POST_W := 5.0 # horizontal-gate post thickness for its shadow
# closed-door textures for the DOOR-mode hover GHOST (see FloorManager), preloaded so preview_orientation
# can swap them as the door auto-orients under the cursor.
const CLOSED_H := preload("res://world/gate_closed.png")
const CLOSED_V := preload("res://world/gate_vertical_closed.png")

# HORIZONTAL: embedded in a horizontal fence, walked through top-to-bottom.
# VERTICAL: embedded in a vertical fence, walked through left-to-right.
# more orientations/styles can be added the same way as the gate roster grows.
var orientation: Grid.Orient = Grid.Orient.HORIZONTAL

# preview mode: a lifted, translucent GHOST of the closed door a DOOR-mode click would place, auto-oriented
# to the wall run under the cursor (see FloorManager). Draws only the CLOSED door (no back layer, no
# shadow, not in the "gates" group build_world frees). Set true BEFORE add_child so _ready sees it.
var preview := false

var cell: Vector2i
var is_open := false
var swing_right := true # vertical gates only: which side the panel swings toward
var swing_up := false # horizontal gates only: true when the door swings north (away)

# Authored default state (set by Obstacles from the saved door data, MapIO-persisted). In PLAY the
# live is_open/swing above are driven by player proximity; on returning to EDIT the door is reset to
# these so the frozen map shows what was authored. `authored_swing` is a single bool interpreted per
# orientation (vertical -> swing_right, horizontal -> swing_up); it only shows when authored_open.
var authored_open := false
var authored_swing := false

# --- lock (ROADMAP "Locked doors and keys"), set by Obstacles from the door record ---
var door_id := ""        # this door's durable id; a Unique key binds to it
var lock := ""           # "" none / "colour" (consumed on first open) / "unique" (metal, stays)
var lock_color := "red"  # an Items.LOCK_COLORS name, for the coloured kind
var unlocked := false    # a COLOURED lock this character already opened: consumed, so it is gone

var closed_texture: Texture2D
var open_texture: Texture2D # horizontal, swung south (toward camera): top + front
var open_texture_north: Texture2D # horizontal, swung north (away): top only
var open_texture_right: Texture2D
var open_texture_left: Texture2D

var back_layer: Node2D # vertical gates only: draws the back post + door behind the player

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	if preview:
		z_index = 1150 # lifted above the paint cursor (1000) / wall ghost (1100) so it reads as floating
		modulate.a = 0.6
		set_preview_orientation(orientation) # load the matching closed texture
		return
	visibility_layer |= FloorHighlightMask.MASK_BIT # occlude the floor-highlight mask
	add_to_group("gates")
	# VERTICAL gates overlap the wall above/below in their own column, so they need
	# z_index 1 to draw over it. HORIZONTAL gates sit in a horizontal wall with floor
	# above and below, so they overlap no wall and stay at z_index 0, y-sorted with the
	# player: anything a row behind the player (north) then draws behind it, so a
	# horizontal gate no longer clips the player standing one row in front of it.
	z_index = 1 if orientation == Grid.Orient.VERTICAL else 0
	if orientation == Grid.Orient.VERTICAL:
		closed_texture = preload("res://world/gate_vertical_closed.png")
		open_texture_right = preload("res://world/gate_vertical_open_right.png")
		open_texture_left = preload("res://world/gate_vertical_open_left.png")
		spawn_back_layer()
	else:
		closed_texture = preload("res://world/gate_closed.png")
		open_texture = preload("res://world/gate_open.png")
		open_texture_north = preload("res://world/gate_open_north.png")
	refresh_shadow.call_deferred() # draw once this gate is in the tree/group
	queue_redraw()

# ghost only: point the preview door at orientation `o`, loading the matching CLOSED texture, then redraw.
# Called by FloorManager as the door auto-orients to the wall run under the cursor.
func set_preview_orientation(o: Grid.Orient) -> void:
	orientation = o
	closed_texture = CLOSED_V if o == Grid.Orient.VERTICAL else CLOSED_H
	queue_redraw()

func spawn_back_layer() -> void:
	back_layer = Node2D.new()
	back_layer.set_script(load("res://world/gate_backlayer.gd"))
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
	# A CLOSED door sits flush inside its wall line, so its shadow should NOT trail off at 45 degrees on
	# the bottom-left: that cut showed as an uncovered triangle when the door's neighbour was a thin
	# vertical rail (a corner/closet layout) that could not cover it. Fill it (left edge straight down).
	# An OPEN door's posts/swung panel are free-standing, so they keep the normal hexagon cut.
	var flush := not is_open
	var out: Array = []
	for rect in _shadow_rects():
		var l: float = rect[0]
		var r: float = rect[1]
		var t: float = rect[2]
		var b: float = rect[3]
		var poly := PackedVector2Array([
			Vector2(l, t), Vector2(r, t),
			Vector2(r + SHADOW_CAST, t + SHADOW_CAST), Vector2(r + SHADOW_CAST, b + SHADOW_CAST),
		])
		if flush:
			poly.append(Vector2(l, b + SHADOW_CAST)) # flush: left edge runs straight down (no cut)
		else:
			poly.append(Vector2(l + SHADOW_CAST, b + SHADOW_CAST))
			poly.append(Vector2(l, b)) # bottom-left 45-degree diagonal
		out.append(poly)
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
	if orientation == Grid.Orient.VERTICAL:
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

# return the door to its authored default (open/closed + swing). Called when entering EDIT, so a
# door the player left open/swung in PLAY snaps back to what the map author set.
func reset_to_authored() -> void:
	if orientation == Grid.Orient.VERTICAL:
		set_swing_right(authored_swing)
	else:
		set_swing_up(authored_swing)
	set_open(authored_open)

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
	if orientation == Grid.Orient.VERTICAL:
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

# The lock, drawn on the door's FRONT layer over the closed panel, in every orientation (ROADMAP:
# "A lock renders on the front layer of a closed door, in every orientation"). Two behaviours:
#  - COLOURED: shows only while closed, and vanishes for good once opened (the lock is consumed), so
#    it never needs open-state art -- exactly the reason the spec chose that rule.
#  - UNIQUE: metal, and stays on the door OPEN or closed, since the key is kept rather than spent.
const LOCK_DARK := Color(0.05, 0.05, 0.08, 0.9)
const LOCK_METAL := Color(0.78, 0.80, 0.86)

func _draw_lock(centre: Vector2) -> void:
	if lock == "" or (lock == "colour" and (unlocked or is_open)):
		return
	var col: Color = LOCK_METAL if lock == "unique" else Items.lock_color(lock_color)
	# shackle (the arc you hook through) then the body, dark-outlined so it reads on any door colour
	draw_arc(centre + Vector2(0, -3.0), 2.6, PI, TAU, 10, LOCK_DARK, 3.0)
	draw_arc(centre + Vector2(0, -3.0), 2.6, PI, TAU, 10, col, 1.6)
	var body := Rect2(centre + Vector2(-3.6, -1.4), Vector2(7.2, 6.0))
	draw_rect(body.grow(0.8), LOCK_DARK, true)
	draw_rect(body, col, true)
	draw_rect(Rect2(centre + Vector2(-0.7, 0.8), Vector2(1.4, 2.2)), LOCK_DARK, true) # keyhole

func _draw() -> void:
	if orientation == Grid.Orient.VERTICAL:
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
		# the lock sits on the panel, a little above the door's midline in both states
		_draw_lock(Vector2(0, top + full_height * 0.62))
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
		_draw_lock(Vector2(0, top + full_height * 0.55))
