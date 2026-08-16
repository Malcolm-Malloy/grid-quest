extends Node2D

# Floating preview of the armed terrain material, shown over the hovered cell in the Cell Selector
# and Fine Details placement modes (ROADMAP "Terrain placement UX"). Selecting a terrain no longer
# auto-places it; it arms a brush that hovers a few px above the target so the user previews exactly
# what will land, then plays a short drop animation on placement: the tile falls from above and
# settles into the cell. The floor paint commits immediately underneath, so this just sells the
# drop; afterwards the preview returns to its resting hover for the next placement.
#
# Drawn in World space (a child of FloorManager) at a z_index above the square paint cursor, so it
# reads as lifted "on top of the highlight". The texture is sampled with GridBackground.tiled_src,
# the same phase the real floor uses, so the preview matches the exact tile that will be placed.

const REST_LIFT := 6.0    # resting hover height above the cell (px)
const DROP_LIFT := 16.0   # height the drop animation falls from
const REST_ALPHA := 1.0   # the hovering preview is solid (opaque); the lift + shadow read it as not-yet-placed
const SHADOW := Color(0, 0, 0, 0.18) # contact shadow, so the lift reads

var _tex: Texture2D        # armed material texture (null = nothing to preview)
var _rect := Rect2()       # world-space destination cell/quarter rect (on the ground, no lift)
var _lift := REST_LIFT     # current vertical offset, animated during a drop
var _alpha := REST_ALPHA
var _shown := false
var _tween: Tween

func _ready() -> void:
	z_index = 1200 # above paint_cursor (1000) so the preview reads as lifted over the highlight

func arm(tex: Texture2D) -> void:
	_tex = tex

# show the resting (hovering) preview over `rect`, unless a drop animation is mid-flight (then the
# tween owns _lift/_alpha and we only follow the rect on the next rest).
func show_at(rect: Rect2) -> void:
	if _tex == null:
		hide_preview()
		return
	_rect = rect
	_shown = true
	if _tween == null or not _tween.is_running():
		_lift = REST_LIFT
		_alpha = REST_ALPHA
	queue_redraw()

func hide_preview() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	if not _shown:
		return
	_shown = false
	queue_redraw()

# drop the tile into `rect`: fall from DROP_LIFT down to the ground and fade out, then return to the
# resting hover so the next placement previews again. Call right after the floor paint commits.
func play_drop(rect: Rect2) -> void:
	if _tex == null:
		return
	_rect = rect
	_shown = true
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_lift, DROP_LIFT, 0.0, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_set_alpha, 0.95, 0.0, 0.13)
	_tween.tween_callback(_rest)

func _set_lift(v: float) -> void:
	_lift = v
	queue_redraw()

func _set_alpha(v: float) -> void:
	_alpha = v
	queue_redraw()

func _rest() -> void:
	_lift = REST_LIFT
	_alpha = REST_ALPHA
	queue_redraw()

func _draw() -> void:
	if not _shown or _tex == null:
		return
	# contact shadow on the ground, tightening as the tile nears the floor, so the height reads
	var t := clampf(_lift / DROP_LIFT, 0.0, 1.0)
	var inset := _rect.size * (0.12 + 0.16 * t)
	draw_rect(Rect2(_rect.position + inset * 0.5, _rect.size - inset), SHADOW, true)
	# the lifted tile, sampled at the same phase the real floor uses (from the un-lifted ground rect)
	# so it shows the exact pixels that will land in this cell
	var dst := Rect2(_rect.position - Vector2(0, _lift), _rect.size)
	draw_texture_rect_region(_tex, dst, GridBackground.tiled_src(_rect), Color(1, 1, 1, _alpha))
