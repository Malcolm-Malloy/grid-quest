extends Node2D

# The ground/floor layer. Material is stored per 16px quarter (a cell is four quarters), so
# floors can be authored at room, cell or quarter grain. Any quarter can be grass (default),
# wood, concrete, tile or carpet. grid_background and shadow_manager read the fills from here,
# so a styled floor draws under the same lighting/shadow system as grass and fills a room up to
# its walls. The material roster will grow over time.
#
# Authoring (unified tool list): the right-click popup lists floor MATERIALS and wall COLOURS.
# Whichever you pick becomes the active tool; picking it also applies it to the clicked target.
#   - A floor material paints the ground at the active SCOPE (Whole room / Cell / Quarter). Grass
#     is the eraser. Any in-bounds cell is paintable, walls included; while the Cell/Quarter cursor
#     is over a wall/door, that obstacle fades to 30% so the ground under it stays visible.
#   - A wall colour tints the wall under the cursor (Cell = one segment, Whole = the whole building;
#     Quarter behaves like Cell). Natural resets to bare stone. The wall highlight (mask) outlines
#     just the wall geometry, no ground or shadows.
#   - Left-click and left-drag apply the active tool. Scope radios and a Grid toggle sit below.
#
# A styled floor is static: it fills up to its walls/doors and does NOT flow through an open
# door. Hovering a room shows a red highlight of the floor the player can actually see; that is
# rendered by FloorHighlightMask (a render mask, not geometry), so it stays pixel-exact under
# walls, doors, the player and any object on the floor.
#
# The reference grid is off by default and toggled from the popup (a check item). When on,
# grid_background and shadow_manager draw the grid in GRID_COLOR instead of leaving it off.

const CELL := 32
const HALF := 16 # a quarter is 16px; a cell is four independently-set quarters

# reference grid: a distinct-but-restrained blue, toggled from the menu (off by default)
const GRID_ID := 100
const GRID_COLOR := Color(0.38, 0.64, 0.95, 0.4)

# paint scope: how far a paint action spreads from the clicked point. Menu id for a scope is
# SCOPE_BASE_ID + the enum value. Whole = whole room (floor) / whole building (wall). Line is
# wall-only (the connected straight run) and always acts on walls, whatever the active tool.
# Quarter is floor-only; a wall tool treats it like Cell.
enum Scope { WHOLE, LINE, CELL, QUARTER }
const SCOPE_BASE_ID := 200
const SCOPE_LABELS := ["Whole", "Line", "Cell", "Quarter"]

var textures := {
	"wood": preload("res://floors/wood_floor.png"),
	"concrete": preload("res://floors/concrete_floor.png"),
	"tile": preload("res://floors/tile_floor.png"),
	"carpet": preload("res://floors/carpet_floor.png"),
}

# popup id -> [label, material]; "" is the grass base (the eraser)
const MENU := [
	["Grass", ""], ["Wood", "wood"], ["Concrete", "concrete"], ["Tile", "tile"], ["Carpet", "carpet"],
]

# wall colours (a tint over the stone). Natural = white = reset. Menu id is WALL_BASE_ID + index.
const WALL_BASE_ID := 300
const WALL_COLORS := [
	["Natural", Color.WHITE],
	["Red", Color(0.85, 0.3, 0.28)],
	["Green", Color(0.42, 0.72, 0.42)],
	["Blue", Color(0.4, 0.55, 0.85)],
	["Yellow", Color(0.9, 0.82, 0.35)],
	["Orange", Color(0.9, 0.58, 0.3)],
	["Purple", Color(0.66, 0.45, 0.8)],
]

@onready var room_light = get_node("../RoomLight")

# Storage is per 16px quarter: _quad_mat is the SOURCE OF TRUTH (what MapIO saves). Everything
# else is derived in _rebuild. A room fill (set_room_style) just writes all four quarters of every
# cell in the room, so nothing built on the old per-room model breaks.
var _quad_mat := {}   # quarter coord (Vector2i, 16px grid) -> material name; the whole floor
var _base_fills: Array = [] # [Rect2, Texture2D], one per painted quarter (derived from _quad_mat)
var _menu: PopupMenu
var _pending := Vector2.ZERO # local (World-space) position of the last right-click, for the menu
var _tool_kind := "floor"    # "floor" (paint _brush) or "wall" (colour with _wall_color)
var _brush := "wood"         # active floor material ("" = grass eraser)
var _wall_color := Color.WHITE # active wall colour tint (white = natural / reset)
var _scope: Scope = Scope.WHOLE # active scope; Whole keeps the old right-click-fill behaviour
var _painting := false       # true while the left button is held, for drag painting
var _cursor: Node2D          # the Cell/Quarter scope square cursor (see paint_cursor.gd)
var _faded: Array = []       # [node, original_modulate] of obstacles dimmed under the cursor
var _faded_cell := Vector2i(-9999, -9999) # cell the current fade is for (dedupe)
var _grid_on := false
const INVALID_CELL := Vector2i(-9999, -9999) # "no cell" sentinel for the dedupe trackers below
var _hover_cell := INVALID_CELL   # raw mouse cell last seen (room-mask dedupe)
var _wall_hover := INVALID_CELL   # wall cell currently highlighted (dedupe)
var _whole_hover := INVALID_CELL  # cell the combined Whole highlight is for (dedupe)

# the hover highlight is drawn by the mask system (FloorHighlightMask): we just detect which
# room the mouse is over and hand it that room's floor shape; it renders the pixel-exact fill
# and outline of the visible floor.
@onready var _mask = get_node("../FloorHighlightMask")

func _ready() -> void:
	# recompute the hover AFTER camera_follow has moved the camera this frame (it runs at the
	# default priority 0), so the highlight stays under the mouse while the player walks and the
	# world scrolls, not just when the mouse itself moves. Same rationale as FloorHighlightMask.
	process_priority = 100
	_menu = PopupMenu.new()
	# Floor materials and wall colours sit in submenus so the top menu stays short (a flat list
	# of all of them plus scopes overflowed the screen). Submenu items share _on_menu_id since
	# every id is namespaced (floor 0-4, walls 300+, scopes 200+, grid 100).
	var floor_sub := PopupMenu.new()
	floor_sub.name = "floor_sub"
	for i in MENU.size():
		floor_sub.add_item(MENU[i][0], i)
	floor_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(floor_sub)
	_menu.add_submenu_item("Floor", "floor_sub")

	var wall_sub := PopupMenu.new()
	wall_sub.name = "wall_sub"
	for i in WALL_COLORS.size():
		wall_sub.add_item(WALL_COLORS[i][0], WALL_BASE_ID + i)
	wall_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(wall_sub)
	_menu.add_submenu_item("Wall Colour", "wall_sub")

	_menu.add_separator("Scope")
	for s in SCOPE_LABELS.size():
		_menu.add_radio_check_item(SCOPE_LABELS[s], SCOPE_BASE_ID + s)
	_menu.add_separator()
	_menu.add_check_item("Grid", GRID_ID)
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)
	# the Cell/Quarter scope cursor (a plain square); Room scope uses the mask highlight instead
	_cursor = Node2D.new()
	_cursor.set_script(load("res://floors/paint_cursor.gd"))
	_cursor.z_index = 1000
	add_child(_cursor)
	call_deferred("_seed") # keep the existing wooden room once RoomLight has built

func _seed() -> void:
	set_room_style(Vector2i(8, 9), "wood")

# keep the highlight under the pointer as the camera scrolls with the player. get_local_mouse_position
# tracks the current camera, so re-detecting the hovered cell each frame follows the world. The
# hover updates are deduped by cell/rect, so a still camera and mouse cost nothing.
func _process(_delta: float) -> void:
	_update_hover()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var local := get_local_mouse_position()
		if not _in_bounds(Vector2i(floori(local.x / CELL), floori(local.y / CELL))):
			return # right-clicked off the map
		_pending = local
		_menu.set_item_checked(_menu.get_item_index(GRID_ID), _grid_on)
		for s in SCOPE_LABELS.size():
			_menu.set_item_checked(_menu.get_item_index(SCOPE_BASE_ID + s), _scope == s)
		_menu.position = Vector2i(get_viewport().get_mouse_position())
		_menu.popup()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# left-click / left-drag paints with the active brush at the active scope
		if event.pressed:
			_painting = true
			_paint(get_local_mouse_position())
			get_viewport().set_input_as_handled()
		elif _painting:
			# stroke ended: the whole drag (or single click) is one undo step
			_painting = false
			EditHistory.commit("paint")
	elif event is InputEventMouseMotion:
		if _painting:
			_paint(get_local_mouse_position())
		_update_hover()

func _on_menu_id(id: int) -> void:
	if id == GRID_ID:
		set_grid(not _grid_on)
		return
	if id >= WALL_BASE_ID:
		# a wall colour: switch to the wall tool and colour the right-clicked target at scope
		_tool_kind = "wall"
		_wall_color = WALL_COLORS[id - WALL_BASE_ID][1]
		_paint(_pending)
		EditHistory.commit("wall colour") # one menu paint = one undo step
		_reset_highlight()
		return
	if id >= SCOPE_BASE_ID:
		_scope = (id - SCOPE_BASE_ID) as Scope # just switch the scope; nothing painted yet
		_reset_highlight() # drop the old-scope highlight; the new one shows on the next move
		call_deferred("_update_hover")
		return
	# a floor material: switch to the floor tool, set the brush, and paint the right-clicked
	# target at the current scope (so "right-click room, pick Wood" still fills the room at Whole).
	_tool_kind = "floor"
	_brush = MENU[id][1]
	_paint(_pending)
	EditHistory.commit("paint") # one menu paint = one undo step
	_reset_highlight()

# hide every highlight so a fresh edit reads clearly; they return on the next mouse move
func _reset_highlight() -> void:
	_hover_cell = INVALID_CELL
	_wall_hover = INVALID_CELL
	_whole_hover = INVALID_CELL
	_mask.hide_floor()
	_cursor.hide_cursor()

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

# the highlight tracks the active scope and tool: Whole outlines the one thing under the cursor
# (that building's walls over a wall, that room's floor over a floor); a wall tool at Cell/Line
# outlines the wall geometry; a floor tool at Cell/Quarter shows the plain square paint cursor.
func _update_hover() -> void:
	if _menu.visible:
		return # keep the highlight put while the menu is open
	var local := get_local_mouse_position()
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	# Whole scope highlights whichever ONE thing is under the cursor (building walls over a wall,
	# room floor over a floor), regardless of which tool is active.
	if _scope == Scope.WHOLE:
		_update_whole_hover(cell)
		return
	# a wall tool outlines walls; Line is wall-only and outlines the run regardless of tool
	if _tool_kind == "wall" or _scope == Scope.LINE:
		_update_wall_hover(cell)
		return
	# floor tool at Cell / Quarter: the square cursor over paintable ground, and any obstacle over
	# that cell dimmed so the ground under it stays visible while painting
	_clear_room_hover()
	if not _paintable(cell):
		_cursor.hide_cursor()
		_restore_faded()
		return
	_fade_obstacles_at(cell)
	if _scope == Scope.QUARTER:
		var q := Vector2i(floori(local.x / HALF), floori(local.y / HALF))
		_cursor.show_rect(Rect2(q.x * HALF, q.y * HALF, HALF, HALF))
	else: # Cell (Line and Whole are handled earlier)
		_cursor.show_rect(Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL))

# clear the mask highlight and reset the dedupe cells so a later hover recomputes cleanly
func _clear_room_hover() -> void:
	if _hover_cell == INVALID_CELL:
		return
	_hover_cell = INVALID_CELL
	_mask.hide_floor()

# Whole scope (either tool): outline the ONE thing under the cursor. Over a wall it outlines that
# building's walls; over a room floor it outlines that room's floor. Never both at once, and it
# works regardless of which tool is active, so moving between wall and floor swaps the highlight.
func _update_whole_hover(cell: Vector2i) -> void:
	if cell == _whole_hover:
		return
	_whole_hover = cell
	_cursor.hide_cursor()
	_restore_faded()
	_hover_cell = INVALID_CELL
	_wall_hover = INVALID_CELL
	var obs = get_node_or_null("../Obstacles")
	if obs != null and obs.is_blocked(cell):
		_mask.show_walls(obs.wall_piece_rects(obs.building_cells(cell)))
	elif room_light.is_enclosed_floor(cell):
		var room_cells: Dictionary = room_light.room_floor_cells(cell)
		_mask.show_floor(room_cells, room_light.wall_ring_quads(room_cells))
	else:
		_mask.hide_floor()

# wall tool: outline the wall the cursor is over (Cell = one segment, Whole = the whole building)
# via the mask, so only the wall geometry lights up (no ground, no shadows). Deduped by cell.
func _update_wall_hover(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs == null or not obs.is_blocked(cell):
		if _wall_hover != INVALID_CELL:
			_wall_hover = INVALID_CELL
			_mask.hide_floor()
		return
	if cell == _wall_hover:
		return # already outlining this wall
	_wall_hover = cell
	_cursor.hide_cursor()
	_clear_room_hover()
	_restore_faded()
	var cells: Dictionary
	if _scope == Scope.WHOLE:
		cells = obs.building_cells(cell)
	elif _scope == Scope.LINE:
		cells = obs.line_cells(cell)
	else:
		cells = {cell: true}
	_mask.show_walls(obs.wall_piece_rects(cells))

# --- floor styles ---

# the four quarters a cell owns: cell c owns 2c, 2c+(1,0), 2c+(0,1), 2c+(1,1).
func _cell_quads(c: Vector2i) -> Array:
	return [Vector2i(c.x * 2, c.y * 2), Vector2i(c.x * 2 + 1, c.y * 2),
			Vector2i(c.x * 2, c.y * 2 + 1), Vector2i(c.x * 2 + 1, c.y * 2 + 1)]

# --- painting (the authoring surface over the quarter store) ---

# apply the active tool at the active scope, at World-space local position `local`.
func _paint(local: Vector2) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	# a wall tool colours walls; Line is wall-only and colours the run regardless of tool
	if _tool_kind == "wall" or _scope == Scope.LINE:
		_paint_wall(cell)
		return
	if _scope == Scope.WHOLE:
		set_room_style(cell, _brush) # convenience fill; rebuilds itself, may no-op outside a room
		return
	if not _paintable(cell):
		return
	var changed := false
	if _scope == Scope.QUARTER:
		var q := Vector2i(floori(local.x / HALF), floori(local.y / HALF))
		changed = _write_quad(q, _brush)
	else: # Cell (Line and Whole are handled earlier)
		for q in _cell_quads(cell):
			changed = _write_quad(q, _brush) or changed
	if changed:
		_rebuild()

# wall tool: colour the wall under the cursor (Cell = one segment, Whole = the whole building).
# No-op off a wall. Quarter behaves like Cell (a cap section is per cell, not per quarter).
func _paint_wall(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs == null or not obs.is_blocked(cell):
		return
	if _scope == Scope.WHOLE:
		obs.color_building(cell, _wall_color)
	elif _scope == Scope.LINE:
		obs.color_line(cell, _wall_color)
	else: # Cell / Quarter -> the single segment
		obs.set_wall_color(cell, _wall_color)

# set one quarter's material ("" erases it back to grass). Returns whether anything changed,
# so a drag that stays inside the same quarter doesn't trigger a redundant rebuild.
func _write_quad(q: Vector2i, mat: String) -> bool:
	if mat != "" and textures.has(mat):
		if _quad_mat.get(q) == mat:
			return false
		_quad_mat[q] = mat
		return true
	if not _quad_mat.has(q):
		return false
	_quad_mat.erase(q)
	return true

# cells you may paint on: any cell inside the grid, walls included (the ground under a wall or
# door is editable; the obstacle over it fades to 30% while you paint, see _fade_obstacles_at)
func _paintable(cell: Vector2i) -> bool:
	return _in_bounds(cell)

# dim any wall/door standing on `cell` to 30% so its ground shows through while it is edited.
func _fade_obstacles_at(cell: Vector2i) -> void:
	if cell == _faded_cell:
		return # already dimmed for this cell
	_restore_faded()
	_faded_cell = cell
	for w in get_tree().get_nodes_in_group("walls"):
		if w.has_method("covers_cell") and w.covers_cell(cell):
			_fade(w)
	for g in get_tree().get_nodes_in_group("gates"):
		if g.cell == cell:
			_fade(g)
			if g.back_layer:
				_fade(g.back_layer) # vertical gate's behind-player post + door

func _fade(node: CanvasItem) -> void:
	_faded.append([node, node.modulate])
	node.modulate.a = 0.3

# put every dimmed obstacle back to full opacity
func _restore_faded() -> void:
	for e in _faded:
		e[0].modulate = e[1]
	_faded.clear()
	_faded_cell = Vector2i(-9999, -9999)

func _in_bounds(cell: Vector2i) -> bool:
	var gb = get_node_or_null("../GridBackground")
	if gb == null:
		return true
	return cell.x >= 0 and cell.y >= 0 and cell.x < gb.grid_width and cell.y < gb.grid_height

# give the room containing `cell` a floor style ("" resets it to grass). A room fill is a
# convenience over the quarter store: it writes all four quarters of every cell in the room.
func set_room_style(cell: Vector2i, style: String) -> void:
	var cells: Dictionary = room_light.room_floor_cells(cell)
	if cells.is_empty():
		return
	_write_room(cells, style)
	_rebuild()

# fill a whole room with `style` ("" erases it to grass): every interior floor quarter AND the
# room-facing wall/door ring quarters, so the floor genuinely reaches under the walls and stays
# there as real data. Cell/Quarter painting deliberately never touches the ring, so laying a tile
# does not change the ground already stored under the walls.
func _write_room(cells: Dictionary, style: String) -> void:
	var valid := style != "" and textures.has(style)
	var quads: Array = []
	for c in cells:
		for q in _cell_quads(c):
			quads.append(q)
	for rect in room_light.wall_ring_quads(cells):
		quads.append(Vector2i(floori(rect.position.x / HALF), floori(rect.position.y / HALF)))
	for q in quads:
		if valid:
			_quad_mat[q] = style
		else:
			_quad_mat.erase(q)

# replace all floors from a v1 per-room style list (used by the MapIO v1->v2 load migration).
# Must run AFTER RoomLight has rebuilt, since the room a style fills is found by flood fill.
func apply_floors(list: Array) -> void:
	_quad_mat.clear()
	for f in list:
		var style: String = f["style"]
		if style == "" or not textures.has(style):
			continue
		_write_room(room_light.room_floor_cells(f["cell"]), style)
	_rebuild()

# replace all floors from a v2 quarter list [[qx, qy, material], ...] (used by MapIO on load).
func apply_quads(list: Array) -> void:
	_quad_mat.clear()
	for a in list:
		var mat: String = a[2]
		if not textures.has(mat):
			continue
		_quad_mat[Vector2i(int(a[0]), int(a[1]))] = mat
	_rebuild()

# _quad_mat is the whole floor (interior + under-wall quarters written by room fills), so the
# render is a straight one-rect-per-quarter pass. No room/uniformity derivation: laying a tile
# changes only that quarter and never disturbs the under-wall ground already stored.
func _rebuild() -> void:
	_base_fills = []
	for q in _quad_mat:
		_base_fills.append([Rect2(q.x * HALF, q.y * HALF, HALF, HALF), textures[_quad_mat[q]]])
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

# the floor texture that renders at 16px quarter `q`, or null for the grass base. The single
# source of truth the door-open shadow pass restamps from, so it matches the indoor base_fills
# exactly (every painted quarter, interior or under a wall/door).
func floor_tex_at_quad(q: Vector2i):
	return textures[_quad_mat[q]] if _quad_mat.has(q) else null
