extends CharacterBody2D

const CELL_SIZE := 32
const MOVE_SPEED := 6.0 # cells per second
# Movement bounds come from GridBackground (the single source of grid size), not local
# consts, so the walkable range always matches the current map's edge even after a resize
# or map load. See grid_bg.min_walkable_position() / max_walkable_position().

const IN_SHADOW_TINT := Color(0.65, 0.65, 0.65, 1.0)

const DOWN_FRAMES := [
	preload("res://player/villager_down_0.png"),
	preload("res://player/villager_down_1.png"),
]
const UP_FRAMES := [
	preload("res://player/villager_up_0.png"),
	preload("res://player/villager_up_1.png"),
]
const SIDE_FRAMES := [
	preload("res://player/villager_side_0.png"),
	preload("res://player/villager_side_1.png"),
]

var is_moving := false
var target_position := Vector2.ZERO
var facing := "down"
# What the character carries, persisted by CharacterIO. TWO entry kinds, because keys force both
# (ROADMAP "Items and pickups" -> inventory model): `stacks` holds stackable items as {item id: count}
# (coins and the like, carry many, later consume one per use), and `uniques` holds one entry per
# one-of-a-kind item ({item, id}, and a door_id once locked doors land). Capacity is unlimited for now.
var inventory := {"stacks": {}, "uniques": []}
var frame_index := 0
var in_shadow := false
var shadow_scale := 1.0 # 1 outdoors; shrinks to a third indoors (softer indoor light)

@onready var obstacles := get_node("../Obstacles")
@onready var floor_manager := get_node("../FloorManager") # for impassable floors (water)
@onready var grid_bg := get_node("../GridBackground")
@onready var room_light := get_node_or_null("../RoomLight")
@onready var sprite := $Sprite2D
@onready var shadow_sprite := $Shadow

func _ready() -> void:
	target_position = position
	# not in the wall ShadowGroup (a single shape, no overlap to double-blend),
	# so it needs its own transparency instead of relying on a group modulate
	shadow_sprite.shadow_color = Color(0.05, 0.08, 0.05, 0.55)
	# the body AND its shadow occlude the floor-highlight mask, so the highlight is excluded
	# from both (it traces the character, not the shadow). Canvas culling is hierarchical, so
	# the Player root must carry the bit too for the mask viewport to reach the child visuals.
	visibility_layer |= FloorHighlightMask.MASK_BIT
	sprite.visibility_layer |= FloorHighlightMask.MASK_BIT
	shadow_sprite.visibility_layer |= FloorHighlightMask.MASK_BIT
	update_sprite()
	add_to_group("player") # so Pickups (and later NPCs/enemies) can find the character
	EditorMode.changed.connect(_on_mode_changed)

# entering EDIT halts any in-progress step and returns every door to its AUTHORED default (open/closed
# + swing), so the frozen map shows what the author set and no door is stuck in a play-driven state.
# Leaving EDIT needs nothing: the play loop takes over.
func _on_mode_changed(_mode: int) -> void:
	if EditorMode.is_edit():
		is_moving = false
		target_position = position
		for gate in get_tree().get_nodes_in_group("gates"):
			gate.set_player_here(false)
			gate.reset_to_authored()

# shared base points used by both shadow shapes below
const SPRITE_TOP := -18.0
const BOTTOM_EDGE := 16.0 # the character's true feet position, matching the main sprite's offset
const HALF_WIDTH := 6.0
const DIAGONAL := 11.0
const EXTRA_DEPTH := 5.0

func get_shadow_points_frontback(cast := 1.0) -> PackedVector2Array:
	# used for facing up/down: both share the same silhouette contour
	# (extracted from the sprites: fairly straight, then the arm/sleeve steps
	# out a few px, then steps back in for the legs), offset outward by the
	# same amount the diagonal already pushed it, instead of a flat line.
	# `cast` shrinks only the projected part (the diagonal reach + extra depth):
	# the character-attached silhouette (top edge and left edge) stays put, so the
	# shadow keeps touching the character while its cast distance shortens indoors.
	var diag := DIAGONAL * cast
	var depth := EXTRA_DEPTH * cast
	var top_left := Vector2(-HALF_WIDTH, SPRITE_TOP)
	var top_right := Vector2(HALF_WIDTH, SPRITE_TOP)
	var mid_right := top_right + Vector2(diag, diag)
	var arm_bottom := Vector2(mid_right.x, 3.0)
	var legs_start := Vector2(mid_right.x - 3.0, 4.0)
	var legs_end := Vector2(legs_start.x, BOTTOM_EDGE - 1.0)
	var bottom_right := Vector2(legs_end.x, BOTTOM_EDGE + depth)
	var bottom_left := Vector2(-HALF_WIDTH + depth, bottom_right.y)
	var base_left := Vector2(-HALF_WIDTH, BOTTOM_EDGE)
	return PackedVector2Array([top_left, top_right, mid_right, arm_bottom, legs_start, legs_end, bottom_right, bottom_left, base_left])

func get_shadow_points_side(cast := 1.0) -> PackedVector2Array:
	# used for facing left: the side sprite's contour is nearly a straight
	# edge (no arm bulge, since only the near arm is visible), so no stepping.
	# `cast` shrinks only the projected reach (see get_shadow_points_frontback),
	# keeping the character-attached top and left edges pinned in place.
	var diag := DIAGONAL * cast
	var depth := EXTRA_DEPTH * cast
	var straight_height := (BOTTOM_EDGE - SPRITE_TOP) - diag + depth
	var top_left := Vector2(-HALF_WIDTH, SPRITE_TOP)
	var top_right := Vector2(HALF_WIDTH, SPRITE_TOP)
	var mid_right := top_right + Vector2(diag, diag)
	var bottom_right := mid_right + Vector2(0, straight_height)
	var bottom_left := Vector2(-HALF_WIDTH + depth, bottom_right.y)
	var base_left := Vector2(-HALF_WIDTH, BOTTOM_EDGE)
	return PackedVector2Array([top_left, top_right, mid_right, bottom_right, bottom_left, base_left])

func update_shadow_shape() -> void:
	var points: PackedVector2Array
	# indoors the shadow's cast reach shrinks (shadow_scale < 1) while the silhouette
	# stays welded to the character, so it shortens toward the feet without detaching at
	# the corners. The shape builders take the cast factor directly.
	match facing:
		"left", "right":
			# the shadow's cast direction is a fixed world-space property (the
			# sun doesn't move when the character turns), so unlike the sprite
			# this never mirrors, both directions use the same shape
			points = get_shadow_points_side(shadow_scale)
		_:
			points = get_shadow_points_frontback(shadow_scale)
	shadow_sprite.setup(points, false)

# picks the shadow size from where the player is: a third indoors, full outside
func _update_shadow_scale() -> void:
	var cell := Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))
	var indoor: bool = room_light != null and room_light.is_indoor(cell)
	var target := 1.0 / 3.0 if indoor else 1.0
	if not is_equal_approx(target, shadow_scale):
		shadow_scale = target
		update_shadow_shape()

func _physics_process(delta: float) -> void:
	# EDIT mode freezes the player: no movement input and no gate proximity logic, so the map stays
	# static for authoring and doors keep their authored/spawned state instead of reacting (see
	# EditorMode). PLAY mode runs the full loop below.
	if EditorMode.is_edit():
		return
	if is_moving:
		position = position.move_toward(target_position, CELL_SIZE * MOVE_SPEED * delta)
		if position.is_equal_approx(target_position):
			position = target_position
			is_moving = false
			# the step landed: STACKABLE items on this cell are collected automatically, with no input
			# at all (ROADMAP "Items and pickups"). Unique items ignore this and wait to be clicked.
			var pickups := get_node_or_null("../Pickups")
			if pickups != null:
				pickups.try_auto_collect(Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE)))
	else:
		var input_dir := Vector2.ZERO
		if Input.is_action_pressed("ui_right"):
			input_dir = Vector2.RIGHT
		elif Input.is_action_pressed("ui_left"):
			input_dir = Vector2.LEFT
		elif Input.is_action_pressed("ui_up"):
			input_dir = Vector2.UP
		elif Input.is_action_pressed("ui_down"):
			input_dir = Vector2.DOWN

		if input_dir != Vector2.ZERO:
			var new_facing := direction_to_facing(input_dir)
			if new_facing != facing:
				facing = new_facing
				update_sprite()

			var new_target := position + input_dir * CELL_SIZE
			var min_pos: Vector2 = grid_bg.min_walkable_position()
			var max_pos: Vector2 = grid_bg.max_walkable_position()
			var in_bounds := new_target.x >= min_pos.x and new_target.x <= max_pos.x and new_target.y >= min_pos.y and new_target.y <= max_pos.y
			var cell := Vector2i(floori(new_target.x / CELL_SIZE), floori(new_target.y / CELL_SIZE))
			# a jagged map has holes: the target cell must actually exist (in-box and not absent), else the
			# coarse box clamp above would let the player step onto void where a single edge cell was removed.
			if in_bounds and grid_bg.cell_present(cell.x, cell.y):
				# blocked by a wall/gate (is_blocked) OR by an impassable floor (water). Kept as two
				# separate checks so is_blocked stays "is a wall" for the editor; floors block here.
				# A bridge re-enables crossing on the water cell it covers (passable-over-impassable).
				var floor_blocks: bool = floor_manager.is_cell_impassable(cell) and not obstacles.is_bridge(cell)
				# a LOCKED door blocks like a wall until the right key opens it. Walking into it IS the
				# attempt: a coloured lock spends one matching key and is gone for good, a unique lock
				# just checks the bound key is in hand (ROADMAP "Locked doors and keys"). Kept out of
				# is_blocked so that stays "is a wall" for the editor, like the impassable-floor check.
				var locked: bool = obstacles.is_locked(cell, self) and not obstacles.try_unlock(cell, self)
				# a creature standing there stops you (ROADMAP "Passability": monster blocks while
				# alive, with a per-object override the inspector exposes). Kept out of is_blocked for
				# the same reason as the two checks above: that stays "is a wall" for the editor.
				var creatures = get_node_or_null("../Creatures")
				var creature_blocks: bool = creatures != null and creatures.blocks_movement(cell)
				if not obstacles.is_blocked(cell) and not floor_blocks and not locked and not creature_blocks:
					target_position = new_target
					is_moving = true
					frame_index = 1 - frame_index
					update_sprite()

	update_shadow_state()
	_update_shadow_scale()
	update_gate_state()

func update_gate_state() -> void:
	if is_moving:
		return # wait until fully settled on a cell before re-checking, not mid-slide
	var occupied_cell := Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))
	for gate in get_tree().get_nodes_in_group("gates"):
		# a still-locked door never swings open on approach: it reads as shut until a key opens it
		if obstacles.is_locked(gate.cell, self):
			if gate.is_open:
				gate.set_open(false)
			continue
		var on_gate_cell: bool = occupied_cell == gate.cell
		# open only when standing on an adjacent block AND facing the gate, so it
		# doesn't re-open (and flip its swing) once you've walked through and are
		# now facing away. Standing in the doorway itself keeps it open so the
		# closed door never draws through the player mid-crossing.
		var should_open := on_gate_cell
		if gate.orientation == "vertical":
			# walked through left-to-right: same row, adjacent column
			var dx: int = occupied_cell.x - gate.cell.x
			if occupied_cell.y == gate.cell.y and ((dx == -1 and facing == "right") or (dx == 1 and facing == "left")):
				should_open = true
			# the door always swings the way the player is facing. Set it whenever
			# the door is open (adjacent OR standing in the doorway), so it never
			# keeps a stale swing from an earlier approach. A perpendicular facing
			# isn't on this gate's axis, so it leaves the swing as-is.
			if should_open:
				if facing == "right":
					gate.set_swing_right(true)
				elif facing == "left":
					gate.set_swing_right(false)
		else:
			# walked through top-to-bottom: same column, adjacent row
			var dy: int = occupied_cell.y - gate.cell.y
			if occupied_cell.x == gate.cell.x and ((dy == -1 and facing == "down") or (dy == 1 and facing == "up")):
				should_open = true
			if should_open:
				if facing == "down":
					gate.set_swing_up(false)
				elif facing == "up":
					gate.set_swing_up(true)
		gate.set_open(should_open)
		gate.set_player_here(on_gate_cell)

func direction_to_facing(dir: Vector2) -> String:
	if dir == Vector2.RIGHT:
		return "right"
	elif dir == Vector2.LEFT:
		return "left"
	elif dir == Vector2.UP:
		return "up"
	else:
		return "down"

func update_sprite() -> void:
	sprite.flip_h = facing == "right"
	match facing:
		"down":
			sprite.texture = DOWN_FRAMES[frame_index]
		"up":
			sprite.texture = UP_FRAMES[frame_index]
		"left", "right":
			sprite.texture = SIDE_FRAMES[frame_index]
	update_shadow_shape()

func update_shadow_state() -> void:
	var was_in_shadow := in_shadow
	in_shadow = false
	var shadows := get_node_or_null("../ShadowGroup")
	if shadows:
		in_shadow = shadows.point_in_shadow(global_position)
	if in_shadow != was_in_shadow:
		# approximation: tints the whole sprite rather than only the covered
		# portion, true per-pixel masking would need a shader
		sprite.modulate = IN_SHADOW_TINT if in_shadow else Color.WHITE

# --- inventory (see `inventory` above; CharacterIO persists whatever these write) ---

# add `count` of a STACKABLE item
func add_to_stack(item: String, count := 1) -> void:
	inventory["stacks"][item] = stack_count(item) + count

# take `count` of a stackable item (a lock consuming a coloured key, later). Returns whether there
# was enough to take; the entry is dropped at zero so the inventory never shows empty stacks.
func take_from_stack(item: String, count := 1) -> bool:
	if stack_count(item) < count:
		return false
	var left: int = stack_count(item) - count
	if left > 0:
		inventory["stacks"][item] = left
	else:
		inventory["stacks"].erase(item)
	return true

func stack_count(item: String) -> int:
	return int(inventory["stacks"].get(item, 0))

# add a UNIQUE item instance, carrying the pickup's durable id so it stays that exact object, plus
# any binding it holds (a Unique key's {door_id, name}, which is what a locked door checks for)
func add_unique(item: String, id: String, data := {}) -> void:
	inventory["uniques"].append({"item": item, "id": id, "data": data.duplicate(true)})

func has_unique(id: String) -> bool:
	for u in inventory["uniques"]:
		if String(u.get("id", "")) == id:
			return true
	return false

# every unique entry of a type (all the keys you are carrying, say)
func uniques_of(item: String) -> Array:
	var out: Array = []
	for u in inventory["uniques"]:
		if String(u.get("item", "")) == item:
			out.append(u)
	return out

func inventory_count() -> int:
	var n: int = inventory["uniques"].size()
	for k in inventory["stacks"]:
		n += int(inventory["stacks"][k])
	return n
