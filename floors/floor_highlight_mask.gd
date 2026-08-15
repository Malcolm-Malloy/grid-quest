extends Node2D
class_name FloorHighlightMask

# Renders the floor-hover highlight by MASK, not geometry. The hovered room's floor is drawn
# in a magenta key on a private visibility layer (MASK_BIT); a SubViewport that shares the
# real world renders ONLY that layer, so the real walls, doors, player and any tagged object
# occlude the key. The magenta that survives is exactly the floor the player can see, and a
# fullscreen shader turns it into the low-opacity red fill plus a red edge line.
#
# Anything that can sit on a floor opts in as an occluder with one line in its _ready:
#     visibility_layer |= FloorHighlightMask.MASK_BIT
# (see wall_segment.gd, gate.gd, gate_backlayer.gd, player.gd). Nothing else is needed; the
# highlight then cuts around it automatically, and updates live as it moves or a door opens.

const MASK_BIT := 1 << 19

var _mask_vp: SubViewport
var _key: Node2D      # floor key, below the walls (they occlude it, tracing visible floor)
var _wall_key: Node2D # wall key, above the walls (highlights the wall geometry itself)
var _overlay: CanvasLayer
var _mat: ShaderMaterial
var _active := false

func _ready() -> void:
	# sync the mask AFTER the camera has moved this frame (camera_follow runs at the default
	# priority 0), so the mask is framed with the current camera transform, not last frame's.
	# Without this the mask lags a frame behind fast movement and the outline clips the walls.
	process_priority = 100
	# the magenta key must never appear in the main view (it lives only on the mask layer)
	get_viewport().canvas_cull_mask &= ~MASK_BIT
	# canvas culling is hierarchical: the mask viewport skips a parent that lacks the bit and
	# its whole subtree, so the ancestors of the key/occluders must carry it too. Each leaf is
	# still culled by its own layer, so only the key and tagged occluders actually render.
	get_parent().visibility_layer |= MASK_BIT              # World
	get_parent().get_parent().visibility_layer |= MASK_BIT # Main

	_mask_vp = SubViewport.new()
	_mask_vp.transparent_bg = true
	_mask_vp.canvas_cull_mask = MASK_BIT
	_mask_vp.size = get_viewport().get_visible_rect().size
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED # only while hovering
	add_child(_mask_vp)
	_mask_vp.world_2d = get_viewport().world_2d # render the real scene

	_key = Node2D.new()
	_key.set_script(load("res://floors/floor_mask_key.gd"))
	_key.visibility_layer = MASK_BIT
	_key.z_index = -4 # below the walls, so they occlude it exactly like the real floor
	get_parent().add_child.call_deferred(_key)

	# the wall highlight key: same magenta-key script, but ABOVE the walls so they do not occlude
	# their own highlight (we are highlighting the walls, not the floor they stand on)
	_wall_key = Node2D.new()
	_wall_key.set_script(load("res://floors/floor_mask_key.gd"))
	_wall_key.visibility_layer = MASK_BIT
	_wall_key.z_index = 60 # above walls (and the z=1 vertical gates)
	get_parent().add_child.call_deferred(_wall_key)

	_overlay = CanvasLayer.new()
	_overlay.layer = 90
	_overlay.visible = false
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://floors/floor_outline.gdshader")
	_mat.set_shader_parameter("mask_tex", _mask_vp.get_texture())
	_mat.set_shader_parameter("tex_size", Vector2(_mask_vp.size))
	rect.material = _mat
	_overlay.add_child(rect)
	add_child(_overlay)

# show the highlight for a room's floor shape (interior cells + room-facing wall quads)
func show_floor(cells: Dictionary, quads: Array) -> void:
	if _key == null or not _key.is_inside_tree():
		call_deferred("show_floor", cells, quads) # key is added deferred on the first frame
		return
	_key.set_shape(cells, quads)
	if _wall_key and _wall_key.is_inside_tree():
		_wall_key.set_shape({}, []) # floor and wall highlights are mutually exclusive
	_activate()

# show the wall highlight for a set of wall-piece rects (World-local coords). Only the wall
# geometry lights up; ground and shadows are absent from the mask viewport, so they are excluded.
func show_walls(rects: Array) -> void:
	if _wall_key == null or not _wall_key.is_inside_tree():
		call_deferred("show_walls", rects)
		return
	_wall_key.set_shape({}, rects)
	if _key and _key.is_inside_tree():
		_key.set_shape({}, [])
	_activate()

func _activate() -> void:
	_active = true
	_mask_vp.canvas_transform = get_viewport().canvas_transform
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_overlay.visible = true

func hide_floor() -> void:
	_active = false
	if _overlay:
		_overlay.visible = false
	if _mask_vp:
		_mask_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _key and _key.is_inside_tree():
		_key.set_shape({}, [])
	if _wall_key and _wall_key.is_inside_tree():
		_wall_key.set_shape({}, [])

func _process(_delta: float) -> void:
	if not _active:
		return
	# keep the mask framed and sized exactly like the main view so it aligns pixel-for-pixel
	var vp := get_viewport()
	var sz: Vector2i = vp.get_visible_rect().size
	if _mask_vp.size != sz:
		_mask_vp.size = sz
		_mat.set_shader_parameter("tex_size", Vector2(sz))
	_mask_vp.canvas_transform = vp.canvas_transform
