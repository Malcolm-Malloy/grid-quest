extends Node2D

# Draws the back post + swung-open door of an OPEN vertical gate. It lives as a
# sibling of the gate in World (not a child) sitting a few pixels higher in y, so
# World's y-sort places it BEHIND the player crossing the doorway, while still
# drawing in front of the wall above (which is a full cell higher), preserving the
# join. The gate itself keeps only the front (bottom) post, at z_index 1, so that
# still occludes the player.

var gate: Node2D

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	visibility_layer |= FloorHighlightMask.MASK_BIT # occlude the floor-highlight mask
	add_to_group("gate_backlayers") # freed with the gates on a map reload

func _draw() -> void:
	if gate == null or gate.orientation != Grid.Orient.VERTICAL or not gate.is_open:
		return
	var texture: Texture2D = gate.open_texture_right if gate.swing_right else gate.open_texture_left
	if texture == null:
		return
	var w: float = gate.VERTICAL_OPEN_WIDTH
	# everything above the front post (texture rows 0..FRONT_SPLIT_ROW-1); the node
	# is lifted by BACK_LIFT, so the draw is pushed back down by the same amount to
	# land on the same pixels the gate would have drawn.
	var split: float = gate.FRONT_SPLIT_ROW
	var top: float = gate.vertical_top() + gate.BACK_LIFT
	var src := Rect2(0.0, 0.0, w, split)
	var dst := Rect2(-w / 2.0, top, w, split)
	draw_texture_rect_region(texture, dst, src)
