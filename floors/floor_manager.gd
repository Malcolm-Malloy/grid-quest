extends Node2D

# Per-room floor styles. Any room can be grass (default), wood, concrete, tile or carpet.
# A room is identified by a canonical cell (its top-left-most floor cell). Right-click a
# room and pick a style from the popup. grid_background and shadow_manager read the fills
# from here, so a styled floor draws under the same lighting/shadow system as grass and
# fills the whole room up to the walls. The popup roster will grow over time.
#
# A styled floor is static per room: it fills the room up to its walls/doors and does NOT
# flow through an open door. Hovering a room shows a red highlight of the floor the player
# can actually see; that is rendered by FloorHighlightMask (a render mask, not geometry), so
# it stays pixel-exact under walls, doors, the player and any object on the floor.
#
# The reference grid is off by default and toggled from the popup (a check item). When on,
# grid_background and shadow_manager draw the grid in GRID_COLOR instead of leaving it off.

const CELL := 32

# reference grid: a distinct-but-restrained blue, toggled from the menu (off by default)
const GRID_ID := 100
const GRID_COLOR := Color(0.38, 0.64, 0.95, 0.4)

var textures := {
	"wood": preload("res://floors/wood_floor.png"),
	"concrete": preload("res://floors/concrete_floor.png"),
	"tile": preload("res://floors/tile_floor.png"),
	"carpet": preload("res://floors/carpet_floor.png"),
}

# popup id -> [label, style]; "" clears the room back to grass
const MENU := [
	["Grass", ""], ["Wood", "wood"], ["Concrete", "concrete"], ["Tile", "tile"], ["Carpet", "carpet"],
]

@onready var room_light = get_node("../RoomLight")

var _styles := {}     # rep_cell (Vector2i) -> style name
var _cell_tex := {}   # Vector2i -> Texture2D for styled floor cells (incl. open doorways)
var _room_quads := {} # rep_cell -> Array[Rect2] of its wall-ring quadrants
var _base_fills: Array = [] # [Rect2, Texture2D] for cells AND wall quads (base floor)
var _menu: PopupMenu
var _pending := Vector2i.ZERO
var _grid_on := false
var _hover_cell := Vector2i(-9999, -9999) # raw mouse cell last seen (dedupe)

# the hover highlight is drawn by the mask system (FloorHighlightMask): we just detect which
# room the mouse is over and hand it that room's floor shape; it renders the pixel-exact fill
# and outline of the visible floor.
@onready var _mask = get_node("../FloorHighlightMask")

func _ready() -> void:
	_menu = PopupMenu.new()
	for i in MENU.size():
		_menu.add_item(MENU[i][0], i)
	_menu.add_separator()
	_menu.add_check_item("Grid", GRID_ID)
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)
	call_deferred("_seed") # keep the existing wooden room once RoomLight has built

func _seed() -> void:
	set_room_style(Vector2i(8, 9), "wood")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var local := get_local_mouse_position()
		var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		if room_light.room_floor_cells(cell).is_empty():
			return # right-clicked a wall or the outdoors, not a room
		_pending = cell
		_menu.set_item_checked(_menu.get_item_index(GRID_ID), _grid_on)
		_menu.position = Vector2i(get_viewport().get_mouse_position())
		_menu.popup()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_update_hover()

func _on_menu_id(id: int) -> void:
	if id == GRID_ID:
		set_grid(not _grid_on)
		return
	set_room_style(_pending, MENU[id][1])
	# hide the red highlight so the new floor reads clearly; it returns on the next mouse
	# move (the reset cell forces a fresh detect once the mouse moves again)
	_hover_cell = Vector2i(-9999, -9999)
	_mask.hide_floor()

# --- reference grid toggle ---

func set_grid(on: bool) -> void:
	if _grid_on == on:
		return
	_grid_on = on
	_redraw_floor_layers()

func grid_on() -> bool:
	return _grid_on

func grid_color() -> Color:
	return GRID_COLOR

# --- hover highlight ---

func _update_hover() -> void:
	if _menu.visible:
		return # keep the highlight on the right-clicked room while the menu is open
	var local := get_local_mouse_position()
	_set_hover(Vector2i(floori(local.x / CELL), floori(local.y / CELL)))

func _set_hover(cell: Vector2i) -> void:
	if cell == _hover_cell:
		return # still over the same cell, nothing to update
	_hover_cell = cell
	_recompute_hover()

# hand the room the mouse is over to the mask, which renders the pixel-exact visible-floor
# highlight (or clears it when the mouse is off any room). The floor is static, so we only
# pass the room's shape; the mask re-renders live, so doors opening and the player moving are
# reflected automatically without recomputing here.
func _recompute_hover() -> void:
	var cells: Dictionary = room_light.room_floor_cells(_hover_cell)
	if cells.is_empty():
		_mask.hide_floor()
		return
	_mask.show_floor(cells, room_light.wall_ring_quads(cells))

# --- floor styles ---

# give the room containing `cell` a floor style ("" resets it to grass)
func set_room_style(cell: Vector2i, style: String) -> void:
	var cells: Dictionary = room_light.room_floor_cells(cell)
	if cells.is_empty():
		return
	var rep := _rep(cells)
	if style == "" or not textures.has(style):
		_styles.erase(rep)
	else:
		_styles[rep] = style
	_rebuild()

# replace all room floor styles at once (used by MapIO on load). Must run AFTER RoomLight has
# rebuilt, since the room a style belongs to is found by flood fill.
func apply_floors(list: Array) -> void:
	_styles.clear()
	for f in list:
		var cell: Vector2i = f["cell"]
		var style: String = f["style"]
		if style == "" or not textures.has(style):
			continue
		var cells: Dictionary = room_light.room_floor_cells(cell)
		if not cells.is_empty():
			_styles[_rep(cells)] = style
	_rebuild()

func _rep(cells: Dictionary) -> Vector2i:
	var best := Vector2i(1 << 30, 1 << 30)
	for c in cells:
		if c.y < best.y or (c.y == best.y and c.x < best.x):
			best = c
	return best

func _rebuild() -> void:
	_cell_tex = {}
	_room_quads = {}
	_base_fills = []
	for rep in _styles:
		var tex: Texture2D = textures[_styles[rep]]
		# a room's floor is static: it fills that room's cells and the room-facing wall/door
		# quadrants up to the walls, and does NOT change with door state (an open door must
		# not let the floor bleed into the next room).
		var cells: Dictionary = room_light.room_floor_cells(rep)
		var quads: Array = room_light.wall_ring_quads(cells)
		_room_quads[rep] = quads
		for c in cells:
			_cell_tex[c] = tex
			_base_fills.append([Rect2(c.x * CELL, c.y * CELL, CELL, CELL), tex])
		for q in quads:
			_base_fills.append([q, tex])
	_redraw_floor_layers()

func _redraw_floor_layers() -> void:
	var gb = get_node_or_null("../GridBackground")
	if gb:
		gb.queue_redraw()
	var sg = get_node_or_null("../ShadowGroup")
	if sg:
		sg.refresh()

# --- read by grid_background and shadow_manager ---

func base_fills() -> Array:
	return _base_fills

func cell_texture(cell: Vector2i):
	return _cell_tex.get(cell)

# wall-ring quads (with texture) of styled rooms that are currently lit, so the shadow
# manager restamps them with the room's floor instead of grass
func lit_quad_fills(lit: Dictionary) -> Array:
	var out: Array = []
	for rep in _room_quads:
		if not lit.has(rep):
			continue
		var tex: Texture2D = textures[_styles[rep]]
		for q in _room_quads[rep]:
			out.append([q, tex])
	return out
