extends Camera2D

# Two modes. FOLLOW keeps the player centred (normal play). FREE is the editor camera:
# middle-mouse drag pans, the wheel zooms toward the cursor, and the view is clamped to the
# map plus a margin so the edges (and the green add-band just outside them) stay reachable.
# Any pan/zoom drops into FREE; F or Home recentres on the player and returns to FOLLOW.
# A dedicated Play/Edit toggle will drive this split later; for now the input auto-switches.

enum Mode { FOLLOW, FREE }

const CELL := 32
const ZOOM_MIN := 0.4
const ZOOM_MAX := 5.0
const ZOOM_STEP := 1.1
const MARGIN := 160.0 # global px of slack beyond the map edge, so the add-band stays in view

@export var target_path: NodePath = ^"../World/Player"
@onready var target := get_node(target_path) as Node2D

var mode: int = Mode.FOLLOW
var _panning := false

func _process(_delta: float) -> void:
	if mode == Mode.FOLLOW and target:
		global_position = target.global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			if event.pressed:
				mode = Mode.FREE
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(get_global_mouse_position(), ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(get_global_mouse_position(), 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning:
		# move opposite the drag, scaled by zoom so a screen-px drag moves that many world px
		global_position -= event.relative / zoom
		_clamp_to_map()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F or event.keycode == KEY_HOME:
			recenter_on_player()

func _zoom_at(world_point: Vector2, factor: float) -> void:
	mode = Mode.FREE
	var z := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	# keep the world point under the cursor fixed across the zoom change
	var after := get_global_mouse_position()
	global_position += world_point - after
	_clamp_to_map()

func recenter_on_player() -> void:
	mode = Mode.FOLLOW
	if target:
		global_position = target.global_position

# frame the whole map (used by the capture harness to verify the edge band headlessly)
func fit_map() -> void:
	mode = Mode.FREE
	var world := get_node_or_null("../World") as Node2D
	var gb := get_node_or_null("../World/GridBackground")
	if world == null or gb == null:
		return
	var xf: Transform2D = world.get_global_transform()
	var tl: Vector2 = xf * Vector2.ZERO
	var br: Vector2 = xf * Vector2(gb.grid_width * float(CELL), gb.grid_height * float(CELL))
	global_position = (tl + br) / 2.0
	var vp := get_viewport_rect().size
	var map_w: float = absf(br.x - tl.x) + 2 * CELL
	var map_h: float = absf(br.y - tl.y) + 2 * CELL
	var z: float = min(vp.x / map_w, vp.y / map_h)
	zoom = Vector2(z, z)

# clamp the camera centre to the map rect plus a margin, so it can't fly off into the void
func _clamp_to_map() -> void:
	var world := get_node_or_null("../World") as Node2D
	var gb := get_node_or_null("../World/GridBackground")
	if world == null or gb == null:
		return
	var xf: Transform2D = world.get_global_transform()
	var tl: Vector2 = xf * Vector2.ZERO
	var br: Vector2 = xf * Vector2(gb.grid_width * float(CELL), gb.grid_height * float(CELL))
	global_position.x = clampf(global_position.x, min(tl.x, br.x) - MARGIN, max(tl.x, br.x) + MARGIN)
	global_position.y = clampf(global_position.y, min(tl.y, br.y) - MARGIN, max(tl.y, br.y) + MARGIN)
