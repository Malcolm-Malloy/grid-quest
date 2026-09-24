class_name FloorManager
extends Node2D

# The ground/floor layer. Material is stored per 16px quarter (a cell is four quarters), so
# floors can be authored at room, cell or quarter grain. Any quarter can be grass (default),
# wood, concrete, tile or carpet. grid_background and shadow_manager read the fills from here,
# so a styled floor draws under the same lighting/shadow system as grass and fills a room up to
# its walls. The material roster will grow over time.
#
# Authoring: the active MODE is chosen on the tool strip (Magic Wand / Cell Selector / Fine Details /
# Erase, see EditorState.Mode); the right-click popup is purely contextual, listing floor
# MATERIALS, wall COLOURS and the Grid toggle. Picking a material/colour applies it to the target.
#   - Cell Selector / Fine Details paint the ground at cell / quarter grain on click and drag; Erase
#     removes topmost-first: a click first deletes the wall/door on the cell (the structure layer),
#     and only once no structure remains does a further click write grass over the terrain. Any
#     in-bounds cell is paintable, walls included; while the cursor is over a wall/door, that
#     obstacle fades to 30% so the ground under it stays visible.
#   - Magic Wand builds a click-to-grow selection (floor patch -> whole room; wall run -> building);
#     the marching-ants overlay draws it, and picking a material/colour then fills the whole
#     selection. With no selection, a floor material fills the clicked room and a wall colour the
#     clicked building (the old right-click-to-fill behaviour). Natural resets a wall to bare stone.
#
# A styled floor is static: it fills up to its walls/doors and does NOT flow through an open
# door. Hovering a room shows a red highlight of the floor the player can actually see; that is
# rendered by FloorHighlightMask (a render mask, not geometry), so it stays pixel-exact under
# walls, doors, the player and any object on the floor.
#
# The reference grid is off by default and toggled from the popup (a check item). When on,
# grid_background and shadow_manager draw the grid in GRID_COLOR instead of leaving it off.

const CELL := Grid.CELL
const HALF := Grid.HALF # a quarter is 16px; a cell is four independently-set quarters

# reference grid: a distinct-but-restrained blue, toggled from the menu (off by default)
const GRID_ID := 100
# right-click-menu ACTION ids (single items, not swatch ranges). All < 300 so they are matched by
# explicit equality in _on_menu_id BEFORE the range branches (and before the FloorMaterials.MATERIAL_NAMES-index fallthrough).
const ERASE_ID := 101       # erase the selection if one exists, else the clicked target
const BUILD_WALL_ID := 102  # build a wall on the clicked (empty) cell
const BUILD_DOOR_ID := 103  # build a door on the clicked (empty) cell
const DOOR_FLIP_ID := 104   # flip a door's orientation
const DOOR_OPEN_ID := 105   # toggle a door's open-by-default
const DOOR_SWING_ID := 106  # toggle a door's swing side
const GRID_COLOR := Color(0.38, 0.64, 0.95, 0.4)


# floor patterns: a per-quarter pattern index into the material's `FloorMaterials.TEXTURES` variant array, separate
# from the colour tint. Menu id is PATTERN_BASE_ID + index. Base is 700 so it sits above every other
# id range and is matched FIRST in _on_menu_id. The submenu is rebuilt per right-click (material-aware).
const PATTERN_BASE_ID := 700

# wall materials (WallSegment.MATERIAL_NAMES; the face/cap pair, separate from the tint). Menu id is WALL_MAT_BASE_ID + index. Base is 600 so it sits above every other id range (floor 0-4,
# scopes 200+, walls 300+, floor colours 400+, picker 500), and is matched BEFORE them in _on_menu_id.
const WALL_MAT_BASE_ID := 600
# wall colours (WallSegment.COLORS, a tint over the stone). Menu id is WALL_BASE_ID + index.
const WALL_BASE_ID := 300

# floor colours: a multiply TINT over whatever texture (or grass) is at the quarter, parallel to
# WallSegment.COLORS. Natural = white = reset (erases the tint). Menu id is FLOOR_COLOR_BASE_ID + index.
# Slice 1 = the 8 fixed "fun" swatches; slice 2 adds the full colour PICKER (arbitrary tint, below).
# Still deferred: the 8 material-aware swatches (a per-material colour table; wants a design pass).
# The colour values match WallSegment.COLORS where they overlap so the two palettes read as one system.
const FLOOR_COLOR_BASE_ID := 400
const FLOOR_PICKER_ID := 500 # "Custom..." opens the colour picker; checked before the 400+ swatches

@onready var room_light: RoomLight = get_node("../RoomLight")

# Storage is per 16px quarter: _quad_mat is the SOURCE OF TRUTH (what MapIO saves). Everything
# else is derived in _rebuild. A room fill (set_room_style) just writes all four quarters of every
# cell in the room, so nothing built on the old per-room model breaks.
var _quad_mat := {}   # quarter coord (Vector2i, 16px grid) -> material name; the whole floor
var _quad_tint := {}  # quarter coord (Vector2i, 16px grid) -> Color; a multiply tint over the floor.
					  # Parallel to _quad_mat and also SOURCE OF TRUTH (MapIO saves it). White/absent
					  # = no tint. A quarter may carry a tint with no material (a tinted grass patch).
var _quad_pattern := {} # quarter coord (Vector2i, 16px grid) -> int pattern index into the material's
					  # `FloorMaterials.TEXTURES` variant array. Parallel to _quad_mat and also SOURCE OF TRUTH (MapIO
					  # saves it). Absent / 0 = the default pattern. Only meaningful with a material.
var _quad_no_bank := {} # LIQUID quarter coords (Vector2i, 16px grid) painted with the bank switch OFF.
					  # SOURCE OF TRUTH (MapIO saves it). Absent = bank ON (default). Both the derived bank
					  # ring and the shore underlay skip these, so that body has no brown river bank.
var _base_fills: Array = [] # [Rect2, Texture2D, Color, (src_override), (animate)], one per painted/tinted
							# quarter. A 4th element overrides the sampled src rect (shoreline atlas); a 5th
							# truthy element flags an ANIMATED water fill (grid_background shimmers it).
var _has_water := false # any water fill emitted this _rebuild, so grid_background knows to run the shimmer
var _fills_dirty := false # the floor stores changed since _base_fills was built (rebuilt lazily on read)
var _menu: PopupMenu
var _pending := Vector2.ZERO # local (World-space) position of the last right-click, for the menu
var _build_wall_sub: PopupMenu # the Build Wall configurator (colour + material + Start), built in _ready
var _picker_popup: PopupPanel   # the "Custom..." floor-colour picker popup
var _color_picker: ColorPicker  # its ColorPicker (live-previews the tint as you drag)
var _picker_applied := false    # a preview was applied during the current picker session (commit on close)
var _suppress_picker := false   # guard so setting the picker's start colour doesn't count as an edit
var _click_tools := {} # single-click modes -> the method a press calls at the mouse (see _on_left_button)
var _painting := false       # true while the left button is held, for drag painting
var _walls_dirty := false    # a wall drag added cells this frame; rebuild ONCE in _process instead of
							 # per motion event (a full map rebuild per cell stutters, see "Investigate lag")
# Box-select (EditorState.Mode.BOX): drag a rectangle to select every quarter inside it, regardless of material or
# room. Combines with the current selection per the drag-start modifier (Shift add / Alt subtract).
var _box_maybe := false       # SELECT: a press landed, but it is not yet a drag. Beyond DRAG_SLOP it
							  # becomes a box drag; released before that, it is a wand click. One tool,
							  # two gestures (the merged Select tool, 2026-09-05).
const DRAG_SLOP := 6.0        # px of movement that turns a press into a box drag
var _box_press := Vector2.ZERO # where the press landed, to measure the slop
var _box_active := false      # true while a box drag is in progress
var _box_start := Vector2i.ZERO # the cell the drag began on
var _box_op: EditorState.SelOp = EditorState.SelOp.REPLACE # captured from the modifier at press
var _box_base := {}           # selection quads snapshot at drag start (the base add/subtract build on)
var _cursor: Node2D          # the Cell/Fine square paint cursor (see paint_cursor.gd)
var _preview: Node2D         # the lifted terrain drop-preview sprite (see terrain_preview.gd)
var _ghosts: PlacementGhosts # the wall / door / bridge placement previews (placement_ghosts.gd)
var _selection: Node2D       # marching-ants selection overlay (see selection_overlay.gd)
var _clip_ghost: Node2D      # hover ghost for an armed paste / an in-flight move (clip_preview.gd)
var _zone_active := false    # true while a zone rectangle is being dragged out
var _zone_start := Vector2i.ZERO # the cell that drag began on
var _key_warn: ConfirmationDialog # "deleting this door deletes its key" warning, built on first use
var _ghost_origin_pin := INVALID_CELL # dev hook (dev/capture.gd): pin the ghost's origin instead of
									  # reading the OS cursor, which a capture run cannot place reliably
var _mouse_inside := true    # false while the OS cursor is off the game window; hides all highlights
var _ui_hid := false         # true while the cursor is over the editor menu/panels, so hover is cleared
var _faded: Array = []       # [node, original_modulate] of obstacles dimmed under the cursor
var _faded_cell := Grid.INVALID_CELL # cell the current fade is for (dedupe)
const INVALID_CELL := Grid.INVALID_CELL # "no cell" sentinel for the dedupe trackers below
var _hover_cell := INVALID_CELL   # raw mouse cell last seen (room-mask dedupe)
var _wall_hover := INVALID_CELL   # wall cell currently highlighted (dedupe)
var _whole_hover_key := ""        # descriptor of the current Whole highlight target (sub-cell dedupe):
								  # "w:<cell>" a building, "r:<cell>" a room, "" nothing

# the hover highlight is drawn by the mask system (FloorHighlightMask): we just detect which
# room the mouse is over and hand it that room's floor shape; it renders the pixel-exact fill
# and outline of the visible floor.
@onready var _mask: FloorHighlightMask = get_node("../FloorHighlightMask")
# sibling World nodes, looked up once (World is the parent in main.tscn; each may be absent in a stripped scene)
@onready var _grid_bg: GridBackground = get_node_or_null("../GridBackground")
@onready var _obs: Obstacles = get_node_or_null("../Obstacles")
@onready var _pickups: Pickups = get_node_or_null("../Pickups")
@onready var _creatures: Creatures = get_node_or_null("../Creatures")
@onready var _shadows: ShadowManager = get_node_or_null("../ShadowGroup")
@onready var _spawn_marker: SpawnMarker = get_node_or_null("../SpawnMarker")
# derives the fills from the stores below (see floor_render.gd)
@onready var _render := FloorRender.new(_quad_mat, _quad_tint, _quad_pattern, _quad_no_bank, _grid_bg)

func _ready() -> void:
	# recompute the hover AFTER camera_follow has moved the camera this frame (it runs at the
	# default priority 0), so the highlight stays under the mouse while the player walks and the
	# world scrolls, not just when the mouse itself moves. Same rationale as FloorHighlightMask.
	process_priority = 100
	_menu = PopupMenu.new()
	# Floor materials and wall colours sit in submenus so the top menu stays short (a flat list
	# of all of them plus scopes overflowed the screen). Submenu items share _on_menu_id since
	# every id is namespaced (floor 0-4, walls 300+, scopes 200+, grid 100).
	# The two section submenus are built once as children of _menu. The TOP-LEVEL items are (re)built
	# per right-click in _apply_menu_context so only the section for the clicked target shows (Godot's
	# PopupMenu has no set_item_hidden, so contextual = rebuild the top level). See ROADMAP item 4.
	var floor_sub := PopupMenu.new()
	floor_sub.name = "floor_sub"
	for i in FloorMaterials.MATERIAL_NAMES.size():
		floor_sub.add_item(FloorMaterials.MATERIAL_NAMES[i][0], i)
	floor_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(floor_sub)

	var wall_sub := PopupMenu.new()
	wall_sub.name = "wall_sub"
	for i in WallSegment.COLORS.size():
		wall_sub.add_item(WallSegment.COLORS[i][0], WALL_BASE_ID + i)
	wall_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(wall_sub)

	# Wall Material: the face/cap texture swap (Stone/Wood/Slate), shown beside Wall Colour on a
	# structure cell. Ids namespaced at WALL_MAT_BASE_ID+, routed through the shared _on_menu_id.
	var wall_mat_sub := PopupMenu.new()
	wall_mat_sub.name = "wall_mat_sub"
	for i in WallSegment.MATERIAL_NAMES.size():
		wall_mat_sub.add_item(WallSegment.MATERIAL_NAMES[i][0], WALL_MAT_BASE_ID + i)
	wall_mat_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(wall_mat_sub)

	# Pattern: a MATERIAL-AWARE submenu shown beside Floor Textures/Colours on a floor cell. Its items
	# are rebuilt per right-click from the clicked quarter's material (see _apply_menu_context), so it
	# lists that material's pattern variants (e.g. wood -> Planks/Diagonal). Ids namespaced at
	# PATTERN_BASE_ID+, routed through the shared _on_menu_id.
	var pattern_sub := PopupMenu.new()
	pattern_sub.name = "pattern_sub"
	pattern_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(pattern_sub)

	# Door: shown on a door cell (rebuilt per right-click from the door's state, see
	# _rebuild_door_submenu). Mirrors the inspector's door controls. Ids are the DOOR_* action ids.
	var door_sub := PopupMenu.new()
	door_sub.name = "door_sub"
	door_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(door_sub)

	# Build Wall configurator: pick a colour + material (radio checkables that KEEP the menu open), then
	# "Start Building" arms a draggable wall brush and closes. Local id scheme (colour i, material 100+j,
	# start 999), routed to _on_build_wall_id, NOT _on_menu_id, so it needs no global id range.
	var build_wall_sub := PopupMenu.new()
	build_wall_sub.name = "build_wall_sub"
	build_wall_sub.hide_on_checkable_item_selection = false # picking colour/material keeps it open
	build_wall_sub.add_separator("Colour")
	for i in WallSegment.COLORS.size():
		build_wall_sub.add_radio_check_item(WallSegment.COLORS[i][0], i)
	build_wall_sub.add_separator("Material")
	for j in WallSegment.MATERIAL_NAMES.size():
		build_wall_sub.add_radio_check_item(WallSegment.MATERIAL_NAMES[j][0], 100 + j)
	build_wall_sub.add_separator()
	build_wall_sub.add_item("Start Building (drag to place)", 999)
	build_wall_sub.id_pressed.connect(_on_build_wall_id)
	_menu.add_child(build_wall_sub)
	_build_wall_sub = build_wall_sub
	_sync_build_wall_checks() # show the current brush as checked

	# Floor Colours: a tint submenu shown beside Floor Textures on a floor cell (the two share the
	# floor-cell branch of _apply_menu_context). Ids are namespaced (FLOOR_COLOR_BASE_ID+), so it
	# routes through the same _on_menu_id like the other submenus.
	var floor_color_sub := PopupMenu.new()
	floor_color_sub.name = "floor_color_sub"
	for i in FloorMaterials.COLORS.size():
		floor_color_sub.add_item(FloorMaterials.COLORS[i][0], FLOOR_COLOR_BASE_ID + i)
	floor_color_sub.add_separator()
	floor_color_sub.add_item("Custom...", FLOOR_PICKER_ID) # opens the full colour picker
	floor_color_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(floor_color_sub)

	# the "Custom..." floor-colour picker: a ColorPicker in a popup that live-previews the tint on the
	# clicked target as you drag, committing one undo entry when it closes (see _open_floor_picker).
	_picker_popup = PopupPanel.new()
	_color_picker = ColorPicker.new()
	_color_picker.edit_alpha = false # tints are opaque multiplies; alpha would just dim confusingly
	_color_picker.custom_minimum_size = Vector2(280, 0)
	_picker_popup.add_child(_color_picker)
	_color_picker.color_changed.connect(_on_floor_picker_changed)
	_picker_popup.popup_hide.connect(_on_floor_picker_closed)
	add_child(_picker_popup)

	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)
	# the Cell/Fine square paint cursor; Wand uses the mask preview + selection overlay instead
	_cursor = Node2D.new()
	_cursor.set_script(load("res://floors/paint_cursor.gd"))
	_cursor.z_index = 1000
	add_child(_cursor)
	# the lifted terrain drop-preview sprite (Cell/Fine placement): armed material floats over the
	# hovered cell and falls in on click. Above the cursor so it reads as lifted over the highlight.
	_preview = Node2D.new()
	_preview.set_script(load("res://floors/terrain_preview.gd"))
	add_child(_preview)
	# the lifted previews of what a WALL / DOOR / BRIDGE click would build
	_ghosts = PlacementGhosts.new()
	add_child(_ghosts)
	_ghosts.setup(_obs)
	# when the cursor leaves the game window, drop every highlight (ROADMAP "Terrain placement UX":
	# cursor off screen clears all highlights); restore tracking when it returns
	get_window().mouse_exited.connect(_on_window_mouse_exited)
	get_window().mouse_entered.connect(_on_window_mouse_entered)
	# the marching-ants selection overlay the Magic Wand builds and the menu fills
	_selection = Node2D.new()
	_selection.set_script(load("res://floors/selection_overlay.gd"))
	_selection.z_index = 1000
	add_child(_selection)
	# the paste/move hover ghost: draws the armed clip over the cells it would land on. It borrows
	# this manager's texture lookup so the ghost shows the real material art, and its bounds test so
	# cells that would be clipped at the map edge read red before the click.
	_clip_ghost = Node2D.new()
	_clip_ghost.set_script(load("res://floors/clip_preview.gd"))
	add_child(_clip_ghost)
	_clip_ghost.setup(func(mat: String, pat: int) -> Texture2D: return FloorMaterials.texture(mat, pat), _in_bounds)
	# leaving EDIT drops every piece of editor state that would otherwise sit frozen on top of the
	# running game: the map tools stand down in PLAY (see _process / _unhandled_input), so anything
	# already on screen would just stay there, and a selection you cannot change is not a selection.
	EditorMode.changed.connect(func(_m):
		if EditorMode.is_play():
			_exit_edit_state())
	_click_tools = {
		EditorState.Mode.ITEM: _place_item_at, EditorState.Mode.CREATURE: _place_creature_at, EditorState.Mode.SPAWN: _set_spawn_at,
		EditorState.Mode.EYEDROP: _eyedrop_at, EditorState.Mode.SELECT: _select_at, EditorState.Mode.DOOR: _place_door_at,
		EditorState.Mode.BRIDGE: _place_bridge_at,
	}
	call_deferred("_seed") # keep the existing wooden room once RoomLight has built

# clear everything the editor was holding: the marching-ants selection, an armed paste or half-finished
# move, every hover highlight, and any obstacle dimmed under the cursor. Nothing is restored on the way
# back to EDIT -- you return to a clean slate rather than a stale selection from before you played.
func _exit_edit_state() -> void:
	_clear_selection()
	_cancel_pending()
	EditorState.armed = false      # an armed terrain brush would otherwise drop a tile on the first click back
	_painting = false
	_box_active = false
	_box_maybe = false
	_cancel_zone_drag() # a half-dragged zone rectangle is live editor state like any other
	_reset_highlight()
	_restore_faded()
	var inspector := get_tree().get_first_node_in_group("inspector") as Inspector
	if inspector != null:
		inspector.clear() # it hides itself in PLAY, but it should not come back holding an old target
	EditorState.brush_changed.emit()

func _seed() -> void:
	set_room_style(Vector2i(8, 9), "wood")

# cursor left / re-entered the game window: clear every highlight while it is away so nothing
# lingers under an absent pointer, and stop recomputing the hover until it returns.
func _on_window_mouse_exited() -> void:
	_mouse_inside = false
	_reset_highlight()
	_restore_faded()

func _on_window_mouse_entered() -> void:
	_mouse_inside = true

# keep the highlight under the pointer as the camera scrolls with the player. get_local_mouse_position
# tracks the current camera, so re-detecting the hovered cell each frame follows the world. The
# hover updates are deduped by cell/rect, so a still camera and mouse cost nothing.
func _process(_delta: float) -> void:
	# no editor highlights while playing (same EDIT-only rule as the input above)
	if EditorMode.is_play():
		return
	# coalesce a wall drag's map rebuilds to at most ONE per frame (each rebuild is a full map re-apply;
	# doing it per motion event stutters). The walls were already added to the model in _place_wall_at.
	if _walls_dirty:
		_walls_dirty = false
		_rebuild_world(MapIO.REBUILD_STRUCTURES)
	# while the cursor is over the editor menu/panels, stand down: clear the hover once on entering the
	# menu and keep it hidden, so no paint cursor / preview / select highlight shows over the UI.
	if _pointer_over_ui():
		if not _ui_hid:
			_ui_hid = true
			_reset_highlight()
			_restore_faded()
		return
	elif _ui_hid:
		_ui_hid = false
	_update_hover()

# true when a GUI Control (the tool strip, inspector, save menu, a popup, ...) is under the cursor, so
# map editing/preview must stand down. Respects each Control's mouse_filter (IGNORE controls don't count).
func _pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _unhandled_input(event: InputEvent) -> void:
	# the map tools are EDIT-only. The strip already hides in PLAY, but clicks still reached the paint
	# and select paths, so playing could silently repaint the map; PLAY also needs the mouse now, to
	# click up unique items (world/pickups.gd).
	if EditorMode.is_play():
		return
	# a mouse PRESS that starts over the editor menu/panels is not a map action (paint, any select, or the
	# right-click menu): the GUI owns it. Motion/release still pass so a drag begun on the map can finish.
	if event is InputEventMouseButton and event.pressed and _pointer_over_ui():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_on_right_press()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_on_left_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion()

func _handled() -> void:
	get_viewport().set_input_as_handled()

# the map cell under the mouse, clamped into the grid box (drag gestures keep tracking past the edge)
func _mouse_cell_clamped() -> Vector2i:
	return _clamp_cell(Grid.cell_of(get_local_mouse_position()))

func _on_right_press() -> void:
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	# a right-click cancels an armed paste (the standard "drop the loaded brush" gesture, matching
	# the Cell/Fine right-click-disarms rule); the clipboard keeps the clip for the next Ctrl+V.
	if EditorState.pending_kind == EditorState.Pending.PASTE:
		_cancel_pending()
		_handled()
		return
	# Cell/Fine: a right-click while a material is armed just cancels the brush (removes the floating
	# drop-preview graphic), no menu. A second right-click (now un-armed) opens the menu as usual.
	# See ROADMAP "Editor UX revisions" -> right-click disarms in Cell/Fine.
	if (EditorState.mode == EditorState.Mode.CELL or EditorState.mode == EditorState.Mode.FINE) and EditorState.armed:
		EditorState.armed = false
		EditorState.brush_changed.emit()
		_preview.hide_preview() # drop the lifted tile immediately (the square cursor stays)
		_handled()
		return
	# a right-click off the map, or off the current selection, deselects (rather than opening the
	# menu). A right-click INSIDE the selection falls through to open the menu, so it can still act
	# on the selection. See ROADMAP "Editor UX revisions" -> deselect a Wand selection.
	if _selection.has_selection() and (not _in_bounds(cell) or not _click_in_selection(local)):
		_clear_selection()
		_handled()
		return
	if not _in_bounds(cell):
		return # right-clicked off the map
	_pending = local
	_apply_menu_context(cell) # rebuilds the top level for the clicked target + sets Grid's check
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.reset_size() # re-fit after the rebuild so the popup isn't sized for a stale menu
	_menu.popup()
	_handled()

func _on_left_button(event: InputEventMouseButton) -> void:
	# an armed paste owns the next left click, in ANY mode: it stamps the clip where the ghost sits.
	if EditorState.pending_kind == EditorState.Pending.PASTE:
		if event.pressed:
			_drop_pending()
		_handled()
		return
	# clicking off the map deselects the current selection (any mode), per "Editor UX revisions"
	# -> deselect a Wand selection ("clicking off the map would logically deselect").
	if event.pressed and _selection.has_selection() and not _in_bounds(Grid.cell_of(get_local_mouse_position())):
		_clear_selection()
		_handled()
		return
	# single-click tools: one press = one action at the mouse (= one undo entry where it edits). None drags:
	# a dragged door line or a smeared row of items is rarely wanted.
	if _click_tools.has(EditorState.mode) and not (EditorState.mode == EditorState.Mode.CREATURE and EditorState.creature_kind == Bestiary.ZONE):
		if event.pressed:
			_click_tools[EditorState.mode].call(get_local_mouse_position())
			_handled()
		return
	match EditorState.mode:
		EditorState.Mode.WAND: _left_wand(event)
		EditorState.Mode.BOX: _left_box(event)
		EditorState.Mode.MOVE: _left_move(event)
		EditorState.Mode.CREATURE: _left_zone(event) # a zone kind (the single-click kinds are handled above)
		EditorState.Mode.WALL: _left_wall(event)
		_: _left_paint(event) # Cell / Fine / Erase

# start a (possible) box selection at `cell`. The modifier at press decides replace / add / subtract
# against the current selection, whose floor quarters are snapshotted as the base to build on.
func _begin_box(cell: Vector2i, event: InputEventMouseButton) -> void:
	_box_start = cell
	_box_op = _sel_op(event)
	_box_base = EditorState.sel_quads.duplicate() if (EditorState.sel_kind == EditorState.SelKind.FLOOR and _box_op != EditorState.SelOp.REPLACE) else {}

# ONE Select tool, two gestures (2026-09-05: Magic Wand and Box Select merged): a CLICK grows a
# selection (patch -> room, run -> building), a DRAG boxes one. The press just arms both and waits to
# see which happened. Shift adds / Alt subtracts either way ("Editor UX revisions" -> additive/
# subtractive selection). Selecting never paints.
func _left_wand(event: InputEventMouseButton) -> void:
	if event.pressed:
		var local := get_local_mouse_position()
		var pc := _clamp_cell(Grid.cell_of(local))
		if _in_bounds(pc):
			_box_maybe = true
			_box_press = local
			_begin_box(pc, event)
			_handled()
		return
	if _box_active:
		_box_active = false # the drag already committed its rectangle into EditorState.sel_quads
	elif _box_maybe:
		# released without dragging: a wand click, and it also loads whatever was clicked into the
		# properties inspector (the old separate Select tool, now folded in)
		var lc := get_local_mouse_position()
		if _in_bounds(Grid.cell_of(lc)):
			_wand_click(lc, _box_op)
			_select_at(lc)
	_box_maybe = false
	_handled()

# drag a rectangle: press starts it, motion grows it (_on_mouse_motion), release finalizes
func _left_box(event: InputEventMouseButton) -> void:
	if event.pressed:
		var cell := _mouse_cell_clamped()
		if _in_bounds(cell):
			_box_active = true
			_begin_box(cell, event)
			_update_box(cell)
			_handled()
	elif _box_active:
		_box_active = false # selection already committed into EditorState.sel_quads during the drag
		_handled()

# drag the current selection to a new place: press INSIDE it to grab (the ghost then follows the grab
# point), release to drop. Pressing outside does nothing, so a stray click never moves a room by
# accident. Rotate/flip (R / H / Shift+H) work mid-drag like they do for paste.
func _left_move(event: InputEventMouseButton) -> void:
	if event.pressed:
		var ml := get_local_mouse_position()
		if _selection.has_selection() and _click_in_selection(ml):
			_begin_move(Grid.cell_of(ml))
			_handled()
	elif EditorState.pending_kind == EditorState.Pending.MOVE:
		_drop_pending()
		_handled()

# a creature ZONE is a REGION, so it is DRAGGED out (press, drag, release) rather than clicked -- the
# same gesture box-select and wall-drawing already use
func _left_zone(event: InputEventMouseButton) -> void:
	if event.pressed:
		var zc := _mouse_cell_clamped()
		if _in_bounds(zc):
			_zone_active = true
			_zone_start = zc
			_update_zone_drag(zc)
	elif _zone_active:
		_zone_active = false
		_commit_zone(_mouse_cell_clamped())
	_handled()

# click-and-drag draws a wall line; the whole gesture is one undo entry
func _left_wall(event: InputEventMouseButton) -> void:
	if event.pressed:
		_painting = true
		_place_wall_at(get_local_mouse_position())
		_handled()
	elif _painting:
		_painting = false
		if _walls_dirty: # flush the final pending rebuild so the commit captures it
			_walls_dirty = false
			_rebuild_world(MapIO.REBUILD_STRUCTURES)
		EditHistory.commit("wall")

# Cell / Fine / Erase: left-click and left-drag paint; the whole stroke is one undo entry
func _left_paint(event: InputEventMouseButton) -> void:
	if not event.pressed:
		if _painting:
			_painting = false
			EditHistory.commit("paint")
		return
	# Alt+click is the eyedropper while a PAINT brush is active (ROADMAP "Eyedropper"). No clash with
	# Alt = subtract-from-selection: that only applies while a SELECTION tool is active, and the two
	# sets of modes are disjoint, so the active tool disambiguates.
	if event.alt_pressed and (EditorState.mode == EditorState.Mode.CELL or EditorState.mode == EditorState.Mode.FINE):
		_eyedrop_at(get_local_mouse_position())
		_handled()
		return
	# Erase removes the topmost structure (wall/door) first, as a single click; only once no structure
	# remains does a further click erase the terrain beneath it (cell-occupancy model, ROADMAP "Erase
	# mode"). Structure removal consumes the click (no paint drag).
	if EditorState.mode == EditorState.Mode.ERASE and _erase_structure_at(get_local_mouse_position()):
		_handled()
		return
	_painting = true
	_paint(get_local_mouse_position(), true) # fresh click: play the drop animation
	_handled()

func _on_mouse_motion() -> void:
	if _box_maybe and not _box_active and get_local_mouse_position().distance_to(_box_press) > DRAG_SLOP:
		_box_active = true # far enough to mean "drag a box", not "click that thing"
	if _zone_active:
		_update_zone_drag(_mouse_cell_clamped())
	if _painting:
		_paint(get_local_mouse_position())
	elif _box_active:
		_update_box(_mouse_cell_clamped())
	_update_hover()

# Esc clears the current Magic Wand selection (also cleared by starting a new selection elsewhere).
# R (in DOOR mode) flips the default door orientation used when placing in open space, so a door with
# no wall run to embed in can still be laid either way (ROADMAP "directional placement (auto + R)").
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# --- clipboard: copy / paste / duplicate (ROADMAP "Copy, paste, and duplicate") ---
	var mod: bool = event.ctrl_pressed or event.meta_pressed
	if mod and event.keycode == KEY_C:
		_copy_selection()
		get_viewport().set_input_as_handled()
		return
	if mod and event.keycode == KEY_V:
		_arm_paste(MapClipboard.clip())
		get_viewport().set_input_as_handled()
		return
	if mod and event.keycode == KEY_D:
		# duplicate = copy the selection and immediately arm it, so the copy is dropped by the next click
		if _copy_selection():
			_arm_paste(MapClipboard.clip())
		get_viewport().set_input_as_handled()
		return
	# --- rotate / flip the clip about to land (paste ghost or move drag) ---
	if not EditorState.pending_clip.is_empty() and event.keycode == KEY_R:
		_transform_pending(MapClipboard.rotate_cw(EditorState.pending_clip))
		get_viewport().set_input_as_handled()
		return
	if not EditorState.pending_clip.is_empty() and event.keycode == KEY_H:
		_transform_pending(MapClipboard.flip_v(EditorState.pending_clip) if event.shift_pressed else MapClipboard.flip_h(EditorState.pending_clip))
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and not EditorState.pending_clip.is_empty():
		_cancel_pending() # Esc drops the armed paste / aborts the move drag before it lands
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _selection.has_selection():
		_clear_selection()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DELETE and _selection.has_selection():
		# Delete erases the current selection (ROADMAP "Editor UX revisions" -> Erase = also the Delete key)
		_erase_selection()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and EditorState.mode == EditorState.Mode.DOOR:
		EditorState.door_orient = "vertical" if EditorState.door_orient == "horizontal" else "horizontal"
		call_deferred("_update_hover")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and EditorState.mode == EditorState.Mode.BRIDGE:
		EditorState.bridge_orient = "vertical" if EditorState.bridge_orient == "horizontal" else "horizontal"
		call_deferred("_update_hover")
		get_viewport().set_input_as_handled()

# contextual right-click menu: rebuild the top level so ONLY the section for what was clicked shows.
# A wall/door cell (the structure layer) gets the Wall Colour submenu; any other cell is floor, so
# gets Floor Textures (descriptive heading, kept distinct from the future "Floor Colours" tint). The
# Grid toggle is a tool setting and stays regardless. PopupMenu has no set_item_hidden in Godot 4, so
# contextual visibility = clear + re-add the relevant items each right-click.
func _apply_menu_context(cell: Vector2i) -> void:
	var is_door: bool = _obs != null and not _obs.door_at(cell).is_empty()
	var is_wall: bool = _obs != null and _obs.is_blocked(cell) # a real wall (doors are not blocked)
	_menu.clear()
	# ONE submenu per target, not one per axis (merged 2026-09-05). The menu had grown to seven
	# top-level entries by listing every axis separately (Floor Textures / Floor Colours / Pattern /
	# Wall Colour / Wall Material / Build Wall / Build Door) while the persistent left panel offered the
	# same choices -- the duplication ROADMAP "Optimise the right menu" warned about, and the
	# reconciliation the Build Wall configurator note asked for. Now:
	#   - STYLE of the clicked thing collapses into one submenu per target ("Floor", "Wall", "Door"),
	#     grouped inside by separator headings, so it is still one level deep, never two.
	#   - BUILDING moved out entirely: the Place tool drops walls/doors/bridges/items/spawns and can
	#     DRAG a wall line, which the menu items never could.
	# What is left is what a context menu is for: act on the thing under the cursor.
	if is_door:
		_rebuild_door_submenu(cell)
		_menu.add_submenu_item("Door", "door_sub")
	elif is_wall:
		_rebuild_wall_submenu()
		_menu.add_submenu_item("Wall", "wall_sub")
	# the ground under a wall/door is editable too, so Floor shows on EVERY cell (the "terrain option"
	# the notes ask for on walls and doors), not only on bare floor cells.
	_rebuild_floor_submenu()
	_menu.add_submenu_item("Floor", "floor_sub")
	_menu.add_item("Erase", ERASE_ID) # acts on the selection if there is one, else the clicked target
	# right-click entries carry tooltips too (ROADMAP "Tooltips on menu and tool options": the sweep
	# covers "right-click menu entries", not only the tool strip), composed from the one hotkey table
	_menu.set_item_tooltip(_menu.get_item_index(ERASE_ID),
		Hotkeys.tip("erase", "Acts on the selection if there is one, else the clicked target."))
	_menu.add_separator()
	_menu.add_check_item("Grid", GRID_ID)
	_menu.set_item_checked(_menu.get_item_index(GRID_ID), EditorState.grid_on)
	_menu.set_item_tooltip(_menu.get_item_index(GRID_ID), "Show the reference grid over the map")

# The Floor submenu: texture, colour and pattern for the clicked ground, in one list with separator
# headings. Rebuilt per right-click because the PATTERN entries are material-aware (they depend on what
# the clicked quarter is made of, which is exactly why patterns stayed in the contextual menu rather
# than moving to the brush panel).
func _rebuild_floor_submenu() -> void:
	var sub: PopupMenu = _menu.get_node("floor_sub")
	sub.clear()
	sub.add_separator("Texture")
	for i in FloorMaterials.MATERIAL_NAMES.size():
		sub.add_item(FloorMaterials.MATERIAL_NAMES[i][0], i)
	sub.add_separator("Colour")
	for i in FloorMaterials.COLORS.size():
		sub.add_item(FloorMaterials.COLORS[i][0], FLOOR_COLOR_BASE_ID + i)
	sub.add_item("Custom...", FLOOR_PICKER_ID)
	var pq := Grid.quad_of(_pending)
	var mat: String = _quad_mat.get(pq, "")
	var variants: int = FloorMaterials.TEXTURES[mat].size() if FloorMaterials.TEXTURES.has(mat) else 0
	if variants > 1:
		sub.add_separator("Pattern")
		var names: Array = FloorMaterials.PATTERN_NAMES.get(mat, [])
		for i in variants:
			sub.add_item(names[i] if i < names.size() else "Pattern %d" % (i + 1), PATTERN_BASE_ID + i)

# The Wall submenu: colour and material for the clicked wall, in one list with separator headings
# (they were two top-level entries offering the two axes of the same brush).
func _rebuild_wall_submenu() -> void:
	var sub: PopupMenu = _menu.get_node("wall_sub")
	sub.clear()
	sub.add_separator("Colour")
	for i in WallSegment.COLORS.size():
		sub.add_item(WallSegment.COLORS[i][0], WALL_BASE_ID + i)
	sub.add_separator("Material")
	for i in WallSegment.MATERIAL_NAMES.size():
		sub.add_item(WallSegment.MATERIAL_NAMES[i][0], WALL_MAT_BASE_ID + i)

# rebuild the Door submenu from the door on `cell` (state-reflecting check items, like the inspector)
func _rebuild_door_submenu(cell: Vector2i) -> void:
	var d: Dictionary = _obs.door_at(cell) if _obs != null else {}
	var ds: PopupMenu = _menu.get_node("door_sub")
	ds.clear()
	ds.add_item("Flip Orientation", DOOR_FLIP_ID)
	ds.add_check_item("Open by default", DOOR_OPEN_ID)
	ds.set_item_checked(ds.get_item_index(DOOR_OPEN_ID), bool(d.get("open", false)))
	ds.add_check_item("Swing (alt side)", DOOR_SWING_ID)
	ds.set_item_checked(ds.get_item_index(DOOR_SWING_ID), bool(d.get("swing", false)))

func _on_menu_id(id: int) -> void:
	if id == GRID_ID:
		set_grid(not EditorState.grid_on)
		return
	var cell := Grid.cell_of(_pending)
	# action items (all < 300, matched here before the swatch-range branches and the FloorMaterials.MATERIAL_NAMES fallthrough)
	if id == ERASE_ID:
		_menu_erase(cell)
		return
	if id == BUILD_WALL_ID:
		if _obs != null and _obs.add_wall(cell):
			_rebuild_world(MapIO.REBUILD_STRUCTURES)
			EditHistory.commit("wall")
		_reset_highlight()
		return
	if id == BUILD_DOOR_ID:
		_place_door_at(_pending) # commits internally, no-ops if a door is already there
		_reset_highlight()
		return
	if id == DOOR_FLIP_ID or id == DOOR_OPEN_ID or id == DOOR_SWING_ID:
		_edit_door(cell, id)
		return
	if id >= PATTERN_BASE_ID:
		# a floor pattern. Mirrors the floor-tint branch: apply to the active floor selection, else the
		# clicked target at the current grain (Wand -> room, Cell -> cell, Fine -> quarter). Arms
		# EditorState.tool_kind = EditorState.Brush.PATTERN so a left-drag keeps applying it (see _paint -> _paint_floor_pattern).
		EditorState.tool_kind = EditorState.Brush.PATTERN
		EditorState.pattern = id - PATTERN_BASE_ID
		if _apply_floor_pattern(EditorState.pattern):
			_rebuild()
			EditHistory.commit("floor pattern") # one menu apply = one undo step
		_reset_highlight()
		return
	if id >= WALL_MAT_BASE_ID:
		# a wall material. Mirrors the wall-colour branch below: fill the active wall selection if one
		# exists; otherwise material the wall under the click (whole building in Wand, single segment in
		# Cell/Fine). Arms EditorState.tool_kind = EditorState.Brush.WALL_MATERIAL so a left-drag keeps applying it (see _paint).
		EditorState.tool_kind = EditorState.Brush.WALL_MATERIAL
		EditorState.wall_mat = WallSegment.MATERIAL_NAMES[id - WALL_MAT_BASE_ID][1]
		var did_mat := false
		if EditorState.sel_kind == EditorState.SelKind.WALL and _selection.has_selection():
			_fill_wall_material_selection(EditorState.wall_mat)
			did_mat = true
		else:
			# is_blocked (a real wall), not has_structure: doors keep stone (their own art), so on a
			# door this is a no-op.
			if _obs != null and _obs.is_blocked(cell):
				if EditorState.mode == EditorState.Mode.WAND:
					_obs.material_building(cell, EditorState.wall_mat)
				else:
					_obs.set_wall_material(cell, EditorState.wall_mat)
				did_mat = true
		if did_mat:
			EditHistory.commit("wall material") # one menu apply = one undo step
		_reset_highlight()
		return
	if id == FLOOR_PICKER_ID:
		_open_floor_picker() # "Custom..." -> the full colour picker (arbitrary tint)
		return
	if id >= FLOOR_COLOR_BASE_ID:
		# a floor tint. Fill the active floor selection if one exists; otherwise tint what was
		# clicked at the current grain (Wand -> whole room, Cell -> the cell, Fine -> the quarter).
		# Mirrors the wall-colour branch below. Leaves EditorState.tool_kind = EditorState.Brush.FLOOR_COLOR armed so a
		# left-drag keeps tinting (see _paint) with the orange ground cursor (see _update_hover).
		EditorState.tool_kind = EditorState.Brush.FLOOR_COLOR
		EditorState.floor_color = FloorMaterials.COLORS[id - FLOOR_COLOR_BASE_ID][1]
		EditorState.brush_changed.emit()
		if _apply_floor_tint(EditorState.floor_color):
			_rebuild()
			EditHistory.commit("floor colour") # one menu tint = one undo step
		_reset_highlight()
		return
	if id >= WALL_BASE_ID:
		# a wall colour. Fill the active wall selection if one exists; otherwise colour the wall
		# under the click (the whole building in Wand mode, a single segment in Cell/Fine).
		EditorState.tool_kind = EditorState.Brush.WALL_COLOR
		EditorState.wall_color = WallSegment.COLORS[id - WALL_BASE_ID][1]
		var did_edit := false
		if EditorState.sel_kind == EditorState.SelKind.WALL and _selection.has_selection():
			_fill_wall_selection(EditorState.wall_color)
			did_edit = true
		else:
			# is_blocked (a real wall), not has_structure: doors keep their own independent colour
			# (unbuilt), so the wall tint only applies to walls. On a door this is a no-op.
			if _obs != null and _obs.is_blocked(cell):
				if EditorState.mode == EditorState.Mode.WAND:
					_obs.color_building(cell, EditorState.wall_color)
				else:
					_obs.set_wall_color(cell, EditorState.wall_color)
				did_edit = true
		if did_edit:
			EditHistory.commit("wall colour") # one menu paint = one undo step
		_reset_highlight()
		return
	# a floor material. Fill the active floor selection if one exists; otherwise, in Wand mode fill
	# the clicked room. In Cell/Fine, selecting a terrain no longer auto-places: it just arms the
	# brush and the user clicks the target to drop it (ROADMAP "Terrain placement UX").
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.brush = FloorMaterials.MATERIAL_NAMES[id][1]
	EditorState.armed = true # a material was explicitly chosen: Cell/Fine may now drop it
	EditorState.brush_changed.emit()
	if EditorState.sel_kind == EditorState.SelKind.FLOOR and _selection.has_selection():
		var drop_rects := _selection_drop_rects() # capture the shape before the highlight resets
		_fill_floor_selection(EditorState.brush)
		EditHistory.commit("paint") # one menu fill = one undo step
		if EditorState.brush != "" and FloorMaterials.TEXTURES.has(EditorState.brush):
			_preview.play_shape_drop(drop_rects, FloorMaterials.texture(EditorState.brush, 0)) # animate the whole shape dropping in
		_reset_highlight()
	elif EditorState.mode == EditorState.Mode.WAND:
		set_room_style(cell, EditorState.brush) # convenience room fill; may no-op outside a room
		EditHistory.commit("paint")
		_reset_highlight()
	else:
		# arm only: nothing changed yet (no undo entry). Refresh the hover so the lifted drop-
		# preview of the freshly-armed material appears over the cursor immediately.
		call_deferred("_update_hover")

# --- floor colour: shared apply + the "Custom..." picker ---

# apply `color` as the floor tint to the right-clicked target, at the current grain: the active
# floor selection, else the clicked room (Wand) / quarter (Fine) / cell (Cell). Returns whether any
# quarter changed. Shared by the preset swatches and the live colour picker.
func _apply_floor_tint(color: Color) -> bool:
	return _write_quads(_menu_scope(), func(q: Vector2i) -> bool: return _write_tint(q, color))

# open the colour picker seeded from the current tint (or a default), previewing live on the target
func _open_floor_picker() -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR_COLOR
	_picker_applied = false
	_suppress_picker = true # setting .color must not count as a user edit
	_color_picker.color = EditorState.floor_color if EditorState.floor_color != Color.WHITE else Color(0.85, 0.3, 0.28)
	_suppress_picker = false
	_picker_popup.popup_centered()

# live preview: each drag in the picker re-tints the target with the new colour
func _on_floor_picker_changed(c: Color) -> void:
	if _suppress_picker:
		return
	EditorState.floor_color = c
	if _apply_floor_tint(c):
		_rebuild()
		_picker_applied = true

# picker closed: the whole session commits as ONE undo entry (or nothing if never previewed)
func _on_floor_picker_closed() -> void:
	if _picker_applied:
		EditHistory.commit("floor colour")
		_picker_applied = false
	_reset_highlight()

# --- authoring mode (driven by the tool strip) ---

# called by the tool strip. Switching mode drops transient hover; leaving the wand re-arms the floor
# tool so Cell/Fine paint floors. The selection persists across mode switches (cleared on Esc or a
# new wand pick), so you can wand-select a room and then Cell-tweak a corner of it.
func set_mode(mode: int) -> void:
	if EditorState.mode == mode:
		return
	EditorState.mode = mode as EditorState.Mode
	_box_active = false # never carry a box drag across a mode switch
	_box_maybe = false
	_cancel_pending()   # nor an armed paste / half-finished move drag
	if EditorState.mode != EditorState.Mode.WAND:
		EditorState.tool_kind = EditorState.Brush.FLOOR
	# Cell/Fine must not start with a material armed to drop: the user picks one from the menu first
	# (ROADMAP "Editor UX revisions" -> Cell/Fine must not pre-arm a material).
	if EditorState.mode == EditorState.Mode.CELL or EditorState.mode == EditorState.Mode.FINE:
		EditorState.armed = false
	EditorState.brush_changed.emit()
	_reset_highlight()
	call_deferred("_update_hover")

func mode() -> int:
	return EditorState.mode

# --- status bar API (ui/status_bar.gd): read-only descriptions of the current editing state ---

# The map cell under the pointer, or INVALID_CELL when there is no cell to report: in PLAY, with the
# cursor off the game window or over the editor UI, or past the edge of the map (a hole in a jagged
# map counts as past it -- an absent cell is void, not part of the map). The gating deliberately
# mirrors _process's, so the readout goes blank exactly when the hover highlights stand down.
# NOT the same thing as _hover_cell, which is a dedupe tracker the highlight paths blank out while
# the cursor is still very much over a cell.
func hovered_cell() -> Vector2i:
	if EditorMode.is_play() or not _mouse_inside or _pointer_over_ui():
		return INVALID_CELL
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	return cell if _in_bounds(cell) else INVALID_CELL

# How big the committed selection is, in the unit it was actually made in ("" when nothing is
# selected). A floor selection is QUARTER-grained, so it reports cells only when its quarters tile
# whole cells and quads otherwise: half a cell must never read as a whole one.
func selection_summary() -> String:
	if has_floor_selection():
		var cells: int = selection_lit_cells().size()
		if EditorState.sel_quads.size() == cells * 4:
			return "%d cell%s" % [cells, "" if cells == 1 else "s"]
		return "%d quad%s" % [EditorState.sel_quads.size(), "" if EditorState.sel_quads.size() == 1 else "s"]
	if has_wall_selection():
		var n: int = EditorState.sel_cells.size()
		return "%d wall%s" % [n, "" if n == 1 else "s"]
	return ""

# --- persistent Brush panel API (tool_strip.gd): read + set the armed floor brush without the menu ---

func is_armed() -> bool:
	return EditorState.armed

func active_tool_kind() -> EditorState.Brush:
	return EditorState.tool_kind

func armed_material() -> String:
	return EditorState.brush

func active_floor_color() -> Color:
	return EditorState.floor_color

# the base texture of the armed floor material, for the panel's combined-brush preview swatch. Grass
# ("" / unknown) previews the grass base, so tinting it reads the same as a tinted grass patch.
func armed_brush_texture() -> Texture2D:
	if EditorState.brush == "" or not FloorMaterials.TEXTURES.has(EditorState.brush):
		return FloorMaterials.GRASS
	return FloorMaterials.texture(EditorState.brush, 0)

# is there a committed FLOOR selection? Used by the panel to decide whether picking a material/colour
# EDITS the selection (recolour/re-texture in place) rather than arming a brush to paint by hand.
func has_floor_selection() -> bool:
	return EditorState.sel_kind == EditorState.SelKind.FLOOR and _selection != null and _selection.has_selection()

# mirror the current floor selection's material + colour into the armed brush, so the Brush panel
# lights up the tile+colour the selection already has (e.g. red tiles -> Tile + Red). Uses the most
# common value across the selected quarters, so a mostly-uniform room reflects its dominant look. Only
# re-emits when something actually changed, so it is safe to call on every selection refresh.
func _reflect_selection_brush() -> void:
	if EditorState.sel_quads.is_empty():
		return
	var mat: String = _dominant(EditorState.sel_quads, _quad_mat, "")
	var col: Color = _dominant(EditorState.sel_quads, _quad_tint, Color.WHITE)
	if mat == EditorState.brush and col == EditorState.floor_color and EditorState.tool_kind == EditorState.Brush.FLOOR:
		return
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.brush = mat
	EditorState.floor_color = col
	EditorState.brush_changed.emit()

# --- wall side of the Brush panel: read + set the armed wall material + colour (mirrors the floor API
# above). A WALL selection reflects its look here, and picking here edits the wall selection in place.

func armed_wall_material() -> String:
	return EditorState.wall_mat

func active_wall_color() -> Color:
	return EditorState.wall_color

func armed_wall_texture() -> Texture2D:
	return WallSegment.swatch_texture(EditorState.wall_mat)

func has_wall_selection() -> bool:
	return EditorState.sel_kind == EditorState.SelKind.WALL and _selection != null and _selection.has_selection()

func arm_wall_material(mat: String) -> void:
	EditorState.tool_kind = EditorState.Brush.WALL_MATERIAL
	EditorState.wall_mat = mat
	if has_wall_selection():
		_fill_wall_material_selection(mat)
		EditHistory.commit("wall material")
	EditorState.brush_changed.emit()

func arm_wall_color(color: Color) -> void:
	EditorState.tool_kind = EditorState.Brush.WALL_COLOR
	EditorState.wall_color = color
	if has_wall_selection():
		_fill_wall_selection(color)
		EditHistory.commit("wall colour")
	EditorState.brush_changed.emit()

# mirror the current wall selection's dominant material + colour into the armed wall brush, so the
# panel lights up the wall's material + tint (like the floor reflect). Reads per-cell values via
# Obstacles (which return the stone/white defaults), so a mostly-plain selection reflects Stone/Natural.
func _reflect_wall_selection_brush() -> void:
	if EditorState.sel_cells.is_empty():
		return
	if _obs == null:
		return
	var matmap := {}
	var colmap := {}
	for c in EditorState.sel_cells:
		matmap[c] = _obs.get_wall_material(c)
		colmap[c] = _obs.get_wall_color(c)
	var mat: String = _dominant(EditorState.sel_cells, matmap, "stone")
	var col: Color = _dominant(EditorState.sel_cells, colmap, Color.WHITE)
	if mat == EditorState.wall_mat and col == EditorState.wall_color:
		return
	EditorState.wall_mat = mat
	EditorState.wall_color = col
	EditorState.brush_changed.emit()

# the most common value in `store` (a quarter -> value map) across the quarters in `quads`, ignoring
# quarters with no entry; `default_val` when none of them carry a value.
func _dominant(quads: Dictionary, store: Dictionary, default_val: Variant) -> Variant:
	var counts := {}
	var best: Variant = default_val
	var best_n := 0
	for q in quads:
		if not store.has(q):
			continue
		var v: Variant = store[q]
		var n: int = int(counts.get(v, 0)) + 1
		counts[v] = n
		if n > best_n:
			best_n = n
			best = v
	return best

# arm a floor material from the panel (same as picking it in the Floor Textures menu in Cell/Fine: it
# arms the brush; the user then paints/drops it). No selection-fill here (that stays a menu convenience).
func arm_floor_material(mat: String) -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.brush = mat
	EditorState.armed = true
	# with a floor selection active, picking a material RE-TEXTURES the selection in place (the two-way
	# panel binding), keeping its colour and the selection itself so the user can keep tweaking.
	if has_floor_selection():
		_fill_floor_selection(mat) # rebuilds
		EditHistory.commit("paint")
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

# arm the floor-colour from the panel with `color`. Unlike the Floor Colours *menu* (which arms a
# tint-only recolour tool), the panel brush is COMBINED: colour and texture are two axes of one floor
# brush, so setting the colour keeps the armed material and a paint lays both together (see _paint).
# White = Natural = lays the plain (untinted) material. The material stays armed and lit in the panel.
func arm_floor_color(color: Color) -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.floor_color = color
	EditorState.armed = true
	# with a floor selection active, picking a colour RE-TINTS the selection in place (the two-way panel
	# binding), keeping its texture and the selection itself. White = Natural clears the tint.
	if has_floor_selection():
		if _write_quads(EditorState.sel_quads, func(q: Vector2i) -> bool: return _write_tint(q, color)):
			_rebuild()
			EditHistory.commit("floor colour")
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

# --- Magic Wand selection ---

# a wand click either starts a new selection or grows the current one (patch -> whole room for a
# floor, run -> whole building for a wall). See ROADMAP "Magic Wand".
func _wand_click(local: Vector2, op := EditorState.SelOp.REPLACE) -> void:
	var cell := Grid.cell_of(local)
	var q := Grid.quad_of(local)
	var is_wall: bool = _obs != null and _obs.is_blocked(cell)
	if op == EditorState.SelOp.REPLACE:
		# plain click: new selection, or grow-on-repeat (patch -> room, run -> building)
		if is_wall:
			_wand_wall(_obs, cell)
		else:
			_wand_floor(cell, q)
	elif is_wall:
		# Shift/Alt: add or subtract the clicked wall run (no growing while compositing)
		_modify_wall_selection(_obs.line_cells(cell), op)
	else:
		_modify_floor_selection(_with_ring(_patch_quads(cell, q)), op)
	_refresh_selection_overlay()

# the selection compositing op for a mouse event: Alt subtracts, Shift adds, plain replaces.
func _sel_op(event: InputEvent) -> EditorState.SelOp:
	if event.alt_pressed:
		return EditorState.SelOp.SUBTRACT
	if event.shift_pressed:
		return EditorState.SelOp.ADD
	return EditorState.SelOp.REPLACE

# clamp a cell to the map so a box drag never runs off the edge
func _clamp_cell(cell: Vector2i) -> Vector2i:
	if _grid_bg == null:
		return cell
	return Vector2i(clampi(cell.x, 0, _grid_bg.grid_width - 1), clampi(cell.y, 0, _grid_bg.grid_height - 1))

# union (add) or difference (subtract) a floor `region` (quarter set) into the current selection,
# switching the selection kind to floor if it was a wall selection.
func _modify_floor_selection(region: Dictionary, op: EditorState.SelOp) -> void:
	if EditorState.sel_kind != EditorState.SelKind.FLOOR:
		EditorState.sel_kind = EditorState.SelKind.FLOOR
		EditorState.sel_quads = {}
		EditorState.sel_cells = {}
	EditorState.sel_level = 0 # a composited selection has no single grow level
	if op == EditorState.SelOp.SUBTRACT:
		for k in region:
			EditorState.sel_quads.erase(k)
	else:
		for k in region:
			EditorState.sel_quads[k] = true
	if EditorState.sel_quads.is_empty():
		EditorState.sel_kind = EditorState.SelKind.NONE

func _modify_wall_selection(region: Dictionary, op: EditorState.SelOp) -> void:
	if EditorState.sel_kind != EditorState.SelKind.WALL:
		EditorState.sel_kind = EditorState.SelKind.WALL
		EditorState.sel_cells = {}
		EditorState.sel_quads = {}
	EditorState.sel_level = 0
	if op == EditorState.SelOp.SUBTRACT:
		for k in region:
			EditorState.sel_cells.erase(k)
	else:
		for k in region:
			EditorState.sel_cells[k] = true
	if EditorState.sel_cells.is_empty():
		EditorState.sel_kind = EditorState.SelKind.NONE

# box-select: set the selection to the rectangle from _box_start to `cur` (all quarters of every cell
# inside), composited onto _box_base per _box_op. Called live during the drag.
func _update_box(cur: Vector2i) -> void:
	var lo := Vector2i(mini(_box_start.x, cur.x), mini(_box_start.y, cur.y))
	var hi := Vector2i(maxi(_box_start.x, cur.x), maxi(_box_start.y, cur.y))
	var region := {}
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for cq in Grid.quads_of(Vector2i(cx, cy)):
				region[cq] = true
	var result: Dictionary = _box_base.duplicate()
	if _box_op == EditorState.SelOp.SUBTRACT:
		for k in region:
			result.erase(k)
	else: # add, or replace (whose base is empty)
		for k in region:
			result[k] = true
	EditorState.sel_cells = {}
	EditorState.sel_level = 0
	EditorState.sel_quads = result
	EditorState.sel_kind = EditorState.SelKind.FLOOR if not result.is_empty() else ""
	_refresh_selection_overlay()

func _wand_floor(cell: Vector2i, q: Vector2i) -> void:
	# repeat click inside the patch grows it to the whole room floor (all materials, wall-bounded)
	if EditorState.sel_kind == EditorState.SelKind.FLOOR and EditorState.sel_quads.has(q) and EditorState.sel_level == 1:
		var cells: Dictionary = room_light.room_floor_cells(cell)
		if not cells.is_empty():
			EditorState.sel_quads = _room_quads(cells) # interior + under-wall ring (the overlay subtracts walls)
			EditorState.sel_level = 2
		return
	# otherwise start a new patch: the connected same-material quarters touching the click, PLUS the
	# ring around them, so the patch also hugs the visible wood on the adjacent wall tiles (the overlay
	# subtracts the wall sprites), consistent with the whole-room grow.
	EditorState.sel_kind = EditorState.SelKind.FLOOR
	EditorState.sel_cells = {}
	EditorState.sel_quads = _with_ring(_patch_quads(cell, q))
	EditorState.sel_level = 1

# add the room-facing wall/door ring quarters around a quarter set, so a selection reaches the
# visible floor that shows on the surrounding wall tiles (the ants hug it, the fill reaches under).
func _with_ring(quads: Dictionary) -> Dictionary:
	var cells := {}
	for q in quads:
		cells[Grid.cell_of_quad(q)] = true
	var out: Dictionary = quads.duplicate()
	for r in room_light.wall_ring_quads(cells):
		out[Grid.quad_of(r.position)] = true
	return out

func _wand_wall(obs, cell: Vector2i) -> void:
	# repeat click on the run grows it to the whole building's connected walls
	if EditorState.sel_kind == EditorState.SelKind.WALL and EditorState.sel_cells.has(cell) and EditorState.sel_level == 1:
		EditorState.sel_cells = obs.building_cells(cell)
		EditorState.sel_level = 2
		return
	EditorState.sel_kind = EditorState.SelKind.WALL
	EditorState.sel_quads = {}
	EditorState.sel_cells = obs.line_cells(cell)
	EditorState.sel_level = 1

# the connected same-material quarters touching `q`, bounded to the cells of `cell`'s room. In a
# uniform room this already equals the whole room, so one click grabs the expected floor; grow-on-
# repeat only matters in a mixed room. Outdoors (no enclosed room) the patch is just the cell.
func _patch_quads(cell: Vector2i, q: Vector2i) -> Dictionary:
	var room: Dictionary = room_light.room_floor_cells(cell)
	if room.is_empty():
		var single := {}
		for cq in Grid.quads_of(cell):
			single[cq] = true
		return single
	var allowed := {}
	for c in room:
		for cq in Grid.quads_of(c):
			allowed[cq] = true
	var seed_mat: String = _quad_mat.get(q, "")
	var sel := {q: true}
	var stack: Array = [q]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if sel.has(n) or not allowed.has(n):
				continue
			if _quad_mat.get(n, "") == seed_mat:
				sel[n] = true
				stack.append(n)
	return sel

# every quarter of a room: the interior cells' quarters plus the wall-ring quarters, matching
# _write_room so a whole-room selection fill reaches under the walls the same way a room fill does.
func _room_quads(cells: Dictionary) -> Dictionary:
	var out := {}
	for c in cells:
		for cq in Grid.quads_of(c):
			out[cq] = true
	for rect in room_light.wall_ring_quads(cells):
		out[Grid.quad_of(rect.position)] = true
	return out

# the 32px CELLS covered by the active FLOOR selection, read by RoomLight so it lights them (skips its
# dim overlay) while selected. Empty unless a floor selection is active. The marching ants still mark
# the selection; lighting it just lets the true (lit) colour show while the user edits the colour.
func selection_lit_cells() -> Dictionary:
	if EditorState.sel_kind != EditorState.SelKind.FLOOR:
		return {}
	var out := {}
	for q in EditorState.sel_quads:
		out[Grid.cell_of_quad(q)] = true
	return out

func _refresh_selection_overlay() -> void:
	# a selection change doesn't move the player or alter the layout, so RoomLight won't redraw on its
	# own; nudge it here so the "selection reads lit" overlay updates as the selection grows/clears.
	if room_light != null:
		room_light.queue_redraw()
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		# trace the full fill set (interior + under-wall ring) MINUS the surrounding wall sprites, so
		# the ants hug the VISIBLE wood exactly: interior plus the ring slivers that show on the wall
		# tiles where the narrow cap doesn't cover them. Verified by rasterising the geometry.
		_selection.set_floor(EditorState.sel_quads, _floor_occluders())
		_reflect_selection_brush() # mirror the selection's material + colour into the Brush panel
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		var rects: Array = _obs.wall_piece_rects(EditorState.sel_cells) if _obs != null else []
		_selection.set_wall(EditorState.sel_cells, rects)
		_reflect_wall_selection_brush() # mirror the wall selection's material + colour into the panel
	else:
		_selection.clear()
	EditorState.selection_changed.emit() # let the panel surface the section matching the current selection kind

# the wall sprite rects that cover the floor selection, so the overlay can subtract them and trace
# the visible floor. Gathers every wall in the selection's cell bounding box (expanded by one cell,
# since a wall's front face droops down into the cell below), then their cap/face piece rects. Only
# real walls occlude here (doors are separate nodes and keep their own handling).
func _floor_occluders() -> Array:
	if _obs == null or EditorState.sel_quads.is_empty():
		return []
	var minc := Vector2i(1 << 30, 1 << 30)
	var maxc := Vector2i(-(1 << 30), -(1 << 30))
	for q in EditorState.sel_quads:
		var c := Grid.cell_of_quad(q) # quarter -> owning cell
		minc.x = mini(minc.x, c.x); minc.y = mini(minc.y, c.y)
		maxc.x = maxi(maxc.x, c.x); maxc.y = maxi(maxc.y, c.y)
	var walls := {}
	for cx in range(minc.x - 1, maxc.x + 2):
		for cy in range(minc.y - 1, maxc.y + 2):
			var cc := Vector2i(cx, cy)
			if _obs.is_blocked(cc):
				walls[cc] = true
	return _obs.wall_piece_rects(walls)

func _clear_selection() -> void:
	EditorState.sel_kind = EditorState.SelKind.NONE
	EditorState.sel_quads = {}
	EditorState.sel_cells = {}
	EditorState.sel_level = 0
	_selection.clear()

# does the world-local point `local` fall inside the current selection? Floor selections are keyed by
# 16px quarter, wall selections by 32px cell. Used to decide whether a right-click acts on the
# selection (inside) or deselects it (outside), per "Editor UX revisions" -> deselect a Wand selection.
func _click_in_selection(local: Vector2) -> bool:
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		return EditorState.sel_quads.has(Grid.quad_of(local))
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		return EditorState.sel_cells.has(Grid.cell_of(local))
	return false

# --- Eyedropper (ROADMAP "Eyedropper"): load the brush from what is already on the map ---

# pick what is under `local` into the active brush, so matching existing terrain needs no palette
# hunting. A picked value NEVER edits the map: it writes the brush fields directly rather than going
# through arm_floor_material / arm_wall_material, which deliberately re-fill an active selection.
# Returns whether anything was picked.
func _eyedrop_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return false
	# A WALL under the cursor loads the WALL brush (material + colour). The 2026-08-16 spec deferred
	# this ("a wall eyedropper could come later") because wall materials did not exist yet; they do
	# now, they are a brush with the same two axes as the floor, and picking nothing on a wall would
	# just read as broken.
	if _obs != null and _obs.is_blocked(cell):
		EditorState.tool_kind = EditorState.Brush.WALL_MATERIAL
		EditorState.wall_mat = _obs.get_wall_material(cell)
		EditorState.wall_color = _obs.get_wall_color(cell)
		EditorState.brush_changed.emit()
		call_deferred("_update_hover")
		return true
	# otherwise the FLOOR quarter under the cursor: material + tint, the two axes of the floor brush.
	# Bare grass ("") is a real answer -- it arms the grass eraser, which is how you match plain ground.
	var q := Grid.quad_of(local)
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.brush = _quad_mat.get(q, "")
	EditorState.floor_color = _quad_tint.get(q, Color.WHITE)
	EditorState.armed = true # picked = loaded and ready to lay, so the next click in Cell/Fine paints it
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")
	return true

# --- Set Spawn (ROADMAP "Player spawn marker"): move the map's authored start point ---

# put the spawn marker on the clicked cell. One click = one undo entry. Walls are refused: the player
# would start stuck inside one. The character is NOT moved -- that is the whole point of the marker
# (authoring the start point without walking the character there); a map LOAD is what puts the player
# on it.
func _set_spawn_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return false # off the map, or on an absent-cell hole
	if _obs != null and _obs.is_blocked(cell):
		return false # never spawn inside a wall
	if _spawn_marker == null:
		return false
	if _spawn_marker.spawn_cell() == cell:
		return false # already there: no empty undo entry
	_spawn_marker.set_cell(cell)
	EditHistory.commit("set spawn")
	return true

# --- Item placement (ROADMAP "Items and pickups" -> editor placement) ---

# drop the armed item definition on the clicked cell. One click = one undo entry. Refuses a cell that
# already holds an item (one per cell, the cell-occupancy model) or that has a wall/door on it, and
# the void outside the map. Binding a Unique key to a specific door comes with locked doors (item 11).
func _place_item_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return false
	if _obs != null and _obs.has_structure(cell):
		return false # a wall/door owns that cell
	if _pickups == null or _pickups.has_pickup(cell):
		return false
	_pickups.add_pickup(cell, EditorState.item, EditorState.item_data)
	EditorState.item_data = {} # a binding is spent by the placement it was armed for; the next key is unbound
	_rebuild_world(MapIO.REBUILD_OBJECTS)
	EditHistory.commit("place item")
	return true

# the armed item definition, for the panel
func armed_item() -> String:
	return EditorState.item

func arm_item(item: String) -> void:
	if not Items.has(item):
		return
	EditorState.item = item
	EditorState.item_data = {}
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

# arm the UNIQUE key belonging to `door_id`, so the next Item click drops THAT door's key. This is the
# "place its key" flow: you author a door's unique lock, then put its key somewhere in the level --
# no separate pick-the-door mode, because the door is already the thing you are editing.
func arm_bound_key(door_id: String, key_name: String) -> void:
	EditorState.item = "key"
	EditorState.item_data = {"door_id": door_id, "name": key_name}
	set_mode(EditorState.Mode.ITEM)
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

func armed_item_binding() -> Dictionary:
	return EditorState.item_data

# --- creature placement (ROADMAP "Creature placement in the editor") ---

# Drop the armed creature on the clicked cell, as the armed KIND. Refused on the void outside the
# map, on a cell a wall/door owns, and on a cell that already holds an OBJECT -- a pickup or another
# creature -- because the cell-occupancy model allows one object per cell and a creature is an object.
func _place_creature_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return false
	if _obs != null and _obs.has_structure(cell):
		return false # a wall/door owns that cell
	if _pickups != null and _pickups.has_pickup(cell):
		return false # the object layer is taken by an item
	if _creatures == null or _creatures.has_creature(cell):
		return false
	_creatures.add_creature(cell, EditorState.creature, EditorState.creature_kind)
	_rebuild_world(MapIO.REBUILD_OBJECTS)
	EditHistory.commit("place creature")
	return true

# the armed creature + kind, for the panel and the status readout
func armed_creature() -> String:
	return EditorState.creature

func armed_creature_kind() -> String:
	return EditorState.creature_kind

func arm_creature(creature: String) -> void:
	if not Bestiary.has(creature):
		return
	EditorState.creature = creature
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

func arm_creature_kind(kind: String) -> void:
	if not Bestiary.is_brush_kind(kind):
		return
	EditorState.creature_kind = kind
	if kind != Bestiary.ZONE:
		_cancel_zone_drag()
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

# the rectangle from the drag's start cell to `cur`, inclusive both ends
func _zone_rect(cur: Vector2i) -> Rect2i:
	var lo := Vector2i(mini(_zone_start.x, cur.x), mini(_zone_start.y, cur.y))
	var hi := Vector2i(maxi(_zone_start.x, cur.x), maxi(_zone_start.y, cur.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)

func _update_zone_drag(cur: Vector2i) -> void:
	if _creatures != null:
		_creatures.set_zone_preview(_zone_rect(cur), EditorState.creature)

# the drag landed: turn the dragged rectangle into a real zone, as one undo entry
func _commit_zone(cur: Vector2i) -> bool:
	if _creatures == null:
		return false
	_creatures.clear_zone_preview()
	if _creatures.add_zone(_zone_rect(cur), EditorState.creature).is_empty():
		return false
	_rebuild_world(MapIO.REBUILD_OBJECTS)
	EditHistory.commit("spawn zone")
	return true

func _cancel_zone_drag() -> void:
	_zone_active = false
	if _creatures != null:
		_creatures.clear_zone_preview()

# --- copy / paste / duplicate / move (ROADMAP "Copy, paste, and duplicate" + "Move tool") ---
#
# All four gestures ride ONE pending-clip state: an armed clip (`EditorState.pending_clip`) plus how it will be
# dropped (`EditorState.pending_kind`). The hover ghost, the rotate/flip keys and the drop are shared; only the
# origin differs (a paste centres on the cursor, a move follows the grab point) and what happens on
# drop (a paste stamps, a move stamps AND clears its source, in one undo entry).

# the CELLS the current selection covers: every cell owning a selected floor quarter, or the selected
# wall cells. This is the clip footprint, so magic-wand-selecting a room (floor + its wall ring) and
# copying takes the room's floor AND the walls/doors around it.
func _selection_cells() -> Dictionary:
	var out := {}
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		for q in EditorState.sel_quads:
			out[Grid.cell_of_quad(q)] = true
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		for c in EditorState.sel_cells:
			out[c] = true
	return out

# Ctrl+C: put the current selection's region on the (cross-map, disk-backed) clipboard.
func _copy_selection() -> bool:
	var cells := _selection_cells()
	if cells.is_empty():
		return false
	MapClipboard.set_clip(MapClipboard.build_clip(MapIO.serialize(), cells))
	return true

# Ctrl+V (and duplicate): arm `clip` as a paste brush; the ghost follows the cursor until a click.
func _arm_paste(clip: Dictionary) -> void:
	if clip.is_empty():
		return
	EditorState.pending_clip = clip
	EditorState.pending_kind = EditorState.Pending.PASTE
	EditorState.pending_changed = false
	EditorState.pending_id += 1
	_reset_highlight()
	call_deferred("_update_hover")

# MOVE mode: grab the current selection at `grab` and start dragging it.
func _begin_move(grab: Vector2i) -> void:
	var cells := _selection_cells()
	if cells.is_empty():
		return
	var minc := Vector2i(1 << 30, 1 << 30)
	for c in cells:
		minc.x = mini(minc.x, c.x); minc.y = mini(minc.y, c.y)
	# built from the live map, NOT from the clipboard: a move must never clobber what the user copied
	EditorState.pending_clip = MapClipboard.build_clip(MapIO.serialize(), cells)
	EditorState.pending_kind = EditorState.Pending.MOVE
	EditorState.pending_changed = false
	EditorState.pending_id += 1
	EditorState.move_src = cells
	EditorState.move_origin = minc
	EditorState.move_grab = grab
	call_deferred("_update_hover")

# rotate/flip the armed clip in place (R / H / Shift+H), keeping the gesture going.
func _transform_pending(clip: Dictionary) -> void:
	if clip.is_empty():
		return
	EditorState.pending_clip = clip
	EditorState.pending_changed = true # so a move that only rotates still counts as an edit
	EditorState.pending_id += 1
	call_deferred("_update_hover")

# where the armed clip's top-left cell currently sits: a PASTE centres the block on the cursor (so
# hovering reads as carrying it), a MOVE keeps the offset from the cell the drag grabbed.
func _pending_origin() -> Vector2i:
	if _ghost_origin_pin != INVALID_CELL:
		return _ghost_origin_pin # pinned by the capture harness; never set in normal play
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	if EditorState.pending_kind == EditorState.Pending.MOVE:
		return EditorState.move_origin + (cell - EditorState.move_grab)
	return cell - Vector2i(int(EditorState.pending_clip.get("w", 1)) / 2, int(EditorState.pending_clip.get("h", 1)) / 2)

# drop the armed clip: stamp a paste, or complete a move (clear the source + stamp), one undo entry.
# The landed region becomes the selection, so it can be moved again or filled straight away.
func _drop_pending() -> void:
	var origin := _pending_origin()
	var stamped := {}
	if EditorState.pending_kind == EditorState.Pending.MOVE:
		if origin != EditorState.move_origin or EditorState.pending_changed:
			stamped = MapEdit.move_clip(EditorState.move_src, EditorState.pending_clip, origin)
		else:
			stamped = EditorState.move_src # dropped where it started: no edit, keep the selection put
	else:
		stamped = MapEdit.stamp_clip(EditorState.pending_clip, origin)
	_cancel_pending()
	if not stamped.is_empty():
		_select_cells(stamped)
	_reset_highlight()
	call_deferred("_update_hover")

# make `cells` the current selection (every quarter of each), used after a paste/move so the landed
# region is immediately actionable.
func _select_cells(cells: Dictionary) -> void:
	EditorState.sel_kind = EditorState.SelKind.FLOOR
	EditorState.sel_cells = {}
	EditorState.sel_level = 0
	EditorState.sel_quads = {}
	for c in cells:
		for q in Grid.quads_of(c):
			EditorState.sel_quads[q] = true
	_refresh_selection_overlay()

# drop the armed paste / abort the move drag without editing the map
func _cancel_pending() -> void:
	EditorState.pending_clip = {}
	EditorState.pending_kind = EditorState.Pending.NONE
	EditorState.pending_changed = false
	EditorState.move_src = {}
	_clip_ghost.hide_clip()

func _fill_floor_selection(mat: String) -> void:
	var valid := mat != "" and FloorMaterials.TEXTURES.has(mat)
	for q in EditorState.sel_quads:
		if valid:
			_quad_mat[q] = mat
			_stamp_bank(q, mat)
		else:
			_quad_mat.erase(q)
			_quad_no_bank.erase(q)
	_rebuild()

# world-space quarter rects of the current floor selection, EXCLUDING quarters under a wall/door (the
# selection's under-structure ring), so the shape-drop animation lands on visible floor only and does
# not draw a lifted tile over a wall. Used to animate a selection fill (see play_shape_drop).
func _selection_drop_rects() -> Array:
	var out: Array = []
	for q in EditorState.sel_quads:
		var cell := Grid.cell_of_quad(q) # 2 quarters per 32px cell axis
		if _obs != null and _obs.has_structure(cell):
			continue
		out.append(Grid.quad_rect(q))
	return out

func _fill_wall_selection(color: Color) -> void:
	if _obs != null:
		_obs.color_cells(EditorState.sel_cells, color)

func _fill_wall_material_selection(material: String) -> void:
	if _obs != null:
		_obs.material_cells(EditorState.sel_cells, material)

# hide every highlight so a fresh edit reads clearly; they return on the next mouse move
func _reset_highlight() -> void:
	_hover_cell = INVALID_CELL
	_wall_hover = INVALID_CELL
	_whole_hover_key = ""
	_mask.hide_floor()
	_cursor.hide_cursor()
	_preview.hide_preview()
	if _ghosts != null:
		_ghosts.hide_all()
	if _clip_ghost != null:
		_clip_ghost.hide_clip() # an armed clip re-shows it on the next hover; off-window/over-UI it goes

# --- reference grid toggle ---

func set_grid(on: bool) -> void:
	if EditorState.grid_on == on:
		return
	EditorState.grid_on = on
	_redraw_floor_layers()

func grid_on() -> bool:
	return EditorState.grid_on

func grid_color() -> Color:
	return GRID_COLOR

# --- hover highlight ---

# the highlight tracks the active scope and tool: Whole outlines the one thing under the cursor
# (that building's walls over a wall, that room's floor over a floor); a wall tool at Cell/Line
# outlines the wall geometry; a floor tool at Cell/Quarter shows the plain square paint cursor.
func _update_hover() -> void:
	if _menu.visible:
		return # keep the highlight put while the menu is open
	if not _mouse_inside:
		return # cursor is off the game window; highlights were cleared on exit
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	# an armed paste / an in-flight move owns the hover surface: the clip ghost replaces every other
	# cursor, so what is about to land is the only thing previewed.
	if not EditorState.pending_clip.is_empty():
		_clear_room_hover()
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		_clip_ghost.show_clip(EditorState.pending_clip, _pending_origin(), EditorState.pending_id)
		return
	_clip_ghost.hide_clip()
	if EditorState.mode == EditorState.Mode.MOVE:
		# MOVE with nothing grabbed: the marching ants already mark what a drag would pick up, so no
		# extra cursor (a paint cursor here would read as "this cell will be edited", which it will not)
		_clear_room_hover()
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		return
	# Wand: preview the ONE thing a click would select (building walls over a wall, room floor over
	# a floor). The committed selection is drawn separately by the marching-ants overlay.
	if EditorState.mode == EditorState.Mode.WAND:
		_update_whole_hover(cell)
		return
	if EditorState.mode == EditorState.Mode.BOX:
		# box-select draws its rectangle during the drag (marching-ants overlay); no paint cursor/preview
		_clear_room_hover()
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		return
	# Bridge: a green target cell + the actual deck art lifted above it, oriented to the water run
	if EditorState.mode == EditorState.Mode.BRIDGE:
		_update_bridge_hover(cell)
		return
	# Wall / Door / Set Spawn placement and Select: a green cell cursor marks the target cell
	if EditorState.mode == EditorState.Mode.WALL or EditorState.mode == EditorState.Mode.DOOR or EditorState.mode == EditorState.Mode.SELECT or EditorState.mode == EditorState.Mode.SPAWN \
			or EditorState.mode == EditorState.Mode.ITEM or EditorState.mode == EditorState.Mode.CREATURE:
		_update_structure_placement_hover(cell)
		return
	# Eyedropper: an ORANGE (ground-edit palette) cursor over the cell that will be SAMPLED. Fine-grain
	# is deliberate: it shows the quarter, because that is the grain the floor store actually holds.
	if EditorState.mode == EditorState.Mode.EYEDROP:
		_clear_room_hover()
		_preview.hide_preview()
		_restore_faded()
		if not _in_bounds(cell):
			_cursor.hide_cursor()
			return
		_cursor.set_role(PaintCursor.Role.GROUND)
		var eq := Grid.quad_of(local)
		_cursor.show_rect(Grid.quad_rect(eq))
		return
	# after a wall colour or material is picked, outline the single wall under the cursor
	if EditorState.tool_kind == EditorState.Brush.WALL_COLOR or EditorState.tool_kind == EditorState.Brush.WALL_MATERIAL:
		_update_wall_hover(cell)
		return
	# Cell / Fine / Erase: the square paint cursor over paintable ground, and any obstacle over that
	# cell dimmed so the ground under it stays visible while painting
	_clear_room_hover()
	if not _in_bounds(cell):
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		return
	_fade_obstacles_at(cell)
	# terrain paint is a ground edit (orange); erase is destructive (red)
	_cursor.set_role(PaintCursor.Role.ERASE if EditorState.mode == EditorState.Mode.ERASE else PaintCursor.Role.GROUND)
	if EditorState.mode == EditorState.Mode.FINE:
		var q := Grid.quad_of(local)
		var r := Grid.quad_rect(q)
		_cursor.show_rect(r)
		_show_preview(r)
	else: # Cell or Erase -> the whole cell
		var r := Grid.cell_rect(cell)
		_cursor.show_rect(r)
		_show_preview(r)

# arm the lifted drop-preview over `rect` when a real material is armed in a placement mode; Erase
# (removal) and the grass eraser show only the square cursor, no floating tile.
func _show_preview(rect: Rect2) -> void:
	# the floor-colour and pattern tools re-texture/tint an existing floor, so they show only the
	# square cursor, no lifted tile (there is nothing being dropped). Same for Erase, the grass eraser,
	# and an un-armed Cell/Fine (no material picked yet).
	if EditorState.mode == EditorState.Mode.ERASE or EditorState.tool_kind == EditorState.Brush.FLOOR_COLOR or EditorState.tool_kind == EditorState.Brush.PATTERN or not EditorState.armed or not FloorMaterials.TEXTURES.has(EditorState.brush):
		_preview.hide_preview()
		return
	_preview.arm(FloorMaterials.texture(EditorState.brush, 0), EditorState.floor_color)
	_preview.show_at(rect)

# clear the mask highlight and reset the dedupe cells so a later hover recomputes cleanly
func _clear_room_hover() -> void:
	if _hover_cell == INVALID_CELL:
		return
	_hover_cell = INVALID_CELL
	_mask.hide_floor()

# Whole scope (either tool): outline the ONE thing under the cursor. Over a wall's STONE it outlines
# that building's walls; over a room floor (incl. the floor part of a wall cell, where the ring wood
# shows) it outlines that room's floor. Never both at once. Sub-cell aware: hovering the exposed
# floor of a wall cell highlights the room, not the wall (per user request).
func _update_whole_hover(cell: Vector2i) -> void:
	var local := get_local_mouse_position()
	var on_stone: bool = _obs != null and _over_wall(cell, local)
	# which room to highlight when not over stone: this cell if it is a room floor, else the adjacent
	# room whose ring wood the cursor is sitting on (the floor part of a wall/door cell).
	var room_seed := INVALID_CELL
	if not on_stone:
		if room_light.is_enclosed_floor(cell):
			room_seed = cell
		else:
			room_seed = _adjacent_room_cell(cell, local)
	var key := ("w:" + str(cell)) if on_stone else (("r:" + str(room_seed)) if room_seed != INVALID_CELL else "")
	if key == _whole_hover_key:
		return
	_whole_hover_key = key
	_cursor.hide_cursor()
	_restore_faded()
	_hover_cell = INVALID_CELL
	_wall_hover = INVALID_CELL
	if on_stone:
		_mask.show_walls(_obs.wall_piece_rects(_obs.building_cells(cell)))
	elif room_seed != INVALID_CELL:
		var room_cells: Dictionary = room_light.room_floor_cells(room_seed)
		_mask.show_floor(room_cells, room_light.wall_ring_quads(room_cells))
	else:
		_mask.hide_floor()

# wall tool: outline the wall the cursor is over via the mask (no ground, no shadows). Only lights up
# when the cursor is over the actual STONE geometry, not the exposed floor part of a wall cell.
func _update_wall_hover(cell: Vector2i) -> void:
	if _obs == null or not _over_wall(cell, get_local_mouse_position()):
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
	_mask.show_walls(_obs.wall_piece_rects({cell: true}))

# true only when `local` (World-space) sits on the actual wall STONE of `cell` (its cap/face rects),
# not the exposed floor part of a wall cell. Used so hovering the visible floor of a wall cell does
# not light up the wall.
func _over_wall(cell: Vector2i, local: Vector2) -> bool:
	if _obs == null or not _obs.is_blocked(cell):
		return false
	for r in _obs.wall_piece_rects({cell: true}):
		if r.has_point(local):
			return true
	return false

# the enclosed-floor room cell nearest `local` among `cell`'s orthogonal neighbours, or INVALID_CELL
# if none: the room whose ring wood the cursor is over when hovering the floor part of a wall/door.
func _adjacent_room_cell(cell: Vector2i, local: Vector2) -> Vector2i:
	var best := INVALID_CELL
	var best_d := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if room_light.is_enclosed_floor(n):
			var c := Grid.cell_center(n)
			var dist := local.distance_squared_to(c)
			if dist < best_d:
				best_d = dist
				best = n
	return best

# --- floor styles ---

# the four quarters a cell owns: cell c owns 2c, 2c+(1,0), 2c+(0,1), 2c+(1,1).
# --- painting (the authoring surface over the quarter store) ---

# apply the active tool at the active scope, at World-space local position `local`.
# `drop` (set on a fresh click, not on drag-moves) plays the terrain drop animation when a real
# material lands, so a single placement gets the falling-tile effect without spamming it per cell
# as a drag sweeps across the map.
func _paint(local: Vector2, drop := false) -> void:
	var cell := Grid.cell_of(local)
	# Wall mode drag: draw a wall line (routed here via the shared _painting drag path)
	if EditorState.mode == EditorState.Mode.WALL:
		_place_wall_at(local)
		return
	# after a wall colour was picked, a drag colours the walls it passes over
	if EditorState.tool_kind == EditorState.Brush.WALL_COLOR:
		_paint_wall(cell)
		return
	# after a wall material was picked, a drag applies it to the walls it passes over
	if EditorState.tool_kind == EditorState.Brush.WALL_MATERIAL:
		_paint_wall_material(cell)
		return
	# after a floor colour was picked, a drag tints the cells/quarters it passes over
	if EditorState.tool_kind == EditorState.Brush.FLOOR_COLOR:
		_paint_floor_color(local)
		return
	# after a floor pattern was picked, a drag re-patterns the cells/quarters it passes over
	if EditorState.tool_kind == EditorState.Brush.PATTERN:
		_paint_floor_pattern(local)
		return
	if not _in_bounds(cell):
		return
	# Cell/Fine place nothing until a material is armed (picked from the menu); Erase is always active.
	if EditorState.mode != EditorState.Mode.ERASE and not EditorState.armed:
		return
	# Erase writes grass ("") over the cell; Cell/Fine write the active brush.
	var mat := "" if EditorState.mode == EditorState.Mode.ERASE else EditorState.brush
	# the floor brush is COMBINED: a paint lays the armed material AND the armed colour into the same
	# quarter (material and tint are independent axes, stored in _quad_mat / _quad_tint). Natural/white
	# tint clears any prior tint; erasing clears the tint too so the cell returns to plain grass.
	var tint := Color.WHITE if EditorState.mode == EditorState.Mode.ERASE else EditorState.floor_color
	var changed := false
	var rect := Grid.cell_rect(cell)
	if EditorState.mode == EditorState.Mode.FINE:
		var q := Grid.quad_of(local)
		rect = Grid.quad_rect(q)
		changed = _write_quad(q, mat)
		changed = _write_tint(q, tint) or changed
	else: # Cell or Erase -> the whole cell
		for q in Grid.quads_of(cell):
			changed = _write_quad(q, mat) or changed
			changed = _write_tint(q, tint) or changed
	if changed:
		_rebuild()
		if drop and mat != "" and FloorMaterials.TEXTURES.has(mat):
			_preview.play_drop(rect) # falling-tile effect for this placement

# wall tool drag: colour the single wall segment under the cursor. No-op off a wall. Whole-building
# colouring is done from the menu path (Wand mode) or a wall selection, not by dragging.
func _paint_wall(cell: Vector2i) -> void:
	if _obs == null or not _obs.is_blocked(cell):
		return
	_obs.set_wall_color(cell, EditorState.wall_color)

# wall-material tool drag: apply the active EditorState.wall_mat to the single wall segment under the cursor.
# No-op off a wall. Whole-building materialling is done from the menu (Wand mode) or a selection.
func _paint_wall_material(cell: Vector2i) -> void:
	if _obs == null or not _obs.is_blocked(cell):
		return
	_obs.set_wall_material(cell, EditorState.wall_mat)

# floor-colour / pattern tool drags: apply the active EditorState.floor_color / EditorState.pattern to the stroke under the
# cursor (Fine -> the quarter, else the whole cell). Whole-room / selection targets come from the menu.
func _paint_floor_color(local: Vector2) -> void:
	if _write_quads(_stroke_scope(local), func(q: Vector2i) -> bool: return _write_tint(q, EditorState.floor_color)):
		_rebuild()

func _paint_floor_pattern(local: Vector2) -> void:
	if _write_quads(_stroke_scope(local), func(q: Vector2i) -> bool: return _write_pattern(q, EditorState.pattern)):
		_rebuild()

# set one quarter's tint (Natural/white erases the entry, so the floor reads its plain material).
# Returns whether anything changed, so a drag inside one quarter doesn't trigger a redundant rebuild.
func _write_tint(q: Vector2i, color: Color) -> bool:
	if color == Color.WHITE:
		if not _quad_tint.has(q):
			return false
		_quad_tint.erase(q)
		return true
	if _quad_tint.get(q) == color:
		return false
	_quad_tint[q] = color
	return true

# --- floor scopes: tint and pattern each have ONE quarter writer (_write_tint / _write_pattern) applied
# over a scope of quarters, so the two tools can never disagree about what "the room" or "the cell" is.

# apply `write(q) -> bool` to every quarter in `quads`; true if any changed
func _write_quads(quads, write: Callable) -> bool:
	var changed := false
	for q in quads:
		changed = write.call(q) or changed
	return changed

# a room fill's quarters: every interior quarter plus the room-facing wall/door ring, so the floor
# genuinely reaches under the walls. Empty outside a room.
func _room_scope(cell: Vector2i) -> Array:
	var cells: Dictionary = room_light.room_floor_cells(cell)
	return [] if cells.is_empty() else _room_quads(cells).keys()

# what a right-click menu action targets at the current grain: the floor selection, else Wand -> the
# clicked room, Fine -> the clicked quarter, Cell/Erase -> the clicked cell
func _menu_scope() -> Array:
	if EditorState.sel_kind == EditorState.SelKind.FLOOR and _selection.has_selection():
		return EditorState.sel_quads.keys()
	if EditorState.mode == EditorState.Mode.WAND:
		return _room_scope(Grid.cell_of(_pending))
	if EditorState.mode == EditorState.Mode.FINE:
		return [Grid.quad_of(_pending)]
	return Grid.quads_of(Grid.cell_of(_pending))

# what a drag stroke at `local` covers: Fine -> the quarter, else the cell (nothing off the map)
func _stroke_scope(local: Vector2) -> Array:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return []
	return [Grid.quad_of(local)] if EditorState.mode == EditorState.Mode.FINE else Grid.quads_of(cell)

# named scopes the capture harness and tests drive directly
func _tint_cell(cell: Vector2i, color: Color) -> bool:
	return _write_quads(Grid.quads_of(cell), func(q: Vector2i) -> bool: return _write_tint(q, color))

func _tint_room(cell: Vector2i, color: Color) -> bool:
	return _write_quads(_room_scope(cell), func(q: Vector2i) -> bool: return _write_tint(q, color))

func _pattern_cell(cell: Vector2i, idx: int) -> bool:
	return _write_quads(Grid.quads_of(cell), func(q: Vector2i) -> bool: return _write_pattern(q, idx))

func _pattern_room(cell: Vector2i, idx: int) -> bool:
	return _write_quads(_room_scope(cell), func(q: Vector2i) -> bool: return _write_pattern(q, idx))

# apply pattern `idx` to the right-clicked target at the current grain (see _menu_scope)
func _apply_floor_pattern(idx: int) -> bool:
	return _write_quads(_menu_scope(), func(q: Vector2i) -> bool: return _write_pattern(q, idx))

# Erase mode: remove the wall or door on the clicked cell (the structure layer, topmost after any
# object). Rebuilds the level through the same MapIO path load/resize use, so lighting, floors and
# shadows recompute consistently after a wall opens a room up. Returns true if a structure was
# removed, so the caller leaves the terrain for a follow-up click and skips the paint drag. One
# click = one removal = one undo entry (ROADMAP "Erase mode").
func _erase_structure_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return false
	if _obs == null:
		return false
	# topmost-first: a wall/door goes before a bridge (they never coexist, but keep the order explicit),
	# and both go before the floor beneath. remove_bridge is only tried when no wall/door was removed.
	if _obs.remove_structure(cell) == "" and not _obs.remove_bridge(cell):
		return false
	_rebuild_world(MapIO.REBUILD_STRUCTURES) # respawn walls/doors/bridges + lighting + shadows
	EditHistory.commit("erase")
	_reset_highlight()
	call_deferred("_update_hover") # re-detect the hover now the structure is gone
	return true

# Wall mode: add a wall on the clicked/dragged cell. add_wall no-ops on a cell that already holds a
# structure, so a drag over existing walls (or a repeat within one cell) triggers no rebuild.
func _place_wall_at(local: Vector2) -> void:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return
	if _obs == null or not _obs.add_wall(cell):
		return
	# stamp the armed wall brush onto the new wall (set the source-of-truth dicts BEFORE the rebuild so
	# serialize carries them). Natural white / stone leave the wall plain. Same EditorState.wall_color / EditorState.wall_mat the
	# Brush panel and the Build Wall configurator arm, so what you picked is what you build.
	if EditorState.wall_color != Color.WHITE:
		_obs.wall_colors[cell] = EditorState.wall_color
	if EditorState.wall_mat != "stone":
		_obs.wall_materials[cell] = EditorState.wall_mat
	_walls_dirty = true # rebuild once in _process (coalesces a fast drag's many cells into one rebuild/frame)

# --- Build Wall configurator (right-click "Build Wall" submenu) ---

# reflect the current wall brush (EditorState.wall_color / EditorState.wall_mat) as the checked radio items
func _sync_build_wall_checks() -> void:
	if _build_wall_sub == null:
		return
	for i in WallSegment.COLORS.size():
		_build_wall_sub.set_item_checked(_build_wall_sub.get_item_index(i), WallSegment.COLORS[i][1] == EditorState.wall_color)
	for j in WallSegment.MATERIAL_NAMES.size():
		_build_wall_sub.set_item_checked(_build_wall_sub.get_item_index(100 + j), WallSegment.MATERIAL_NAMES[j][1] == EditorState.wall_mat)

func _on_build_wall_id(id: int) -> void:
	if id == 999:
		_arm_wall_build() # done configuring: enter Wall mode with the brush, close the menu
		return
	if id >= 100:
		EditorState.wall_mat = WallSegment.MATERIAL_NAMES[id - 100][1]
	else:
		EditorState.wall_color = WallSegment.COLORS[id][1]
	EditorState.brush_changed.emit() # keep the left Brush panel's Wall section in sync with the configurator
	_sync_build_wall_checks() # update the ticks in place (the menu stays open for more options)

# arm the draggable wall brush: switch to Wall mode (so a drag draws a wall line carrying the brush),
# light the strip's Wall radio to match, and close the menu so the user can drop tiles in place.
func _arm_wall_build() -> void:
	set_mode(EditorState.Mode.WALL)
	var ts := get_tree().get_first_node_in_group("tool_strip") as ToolStrip
	if ts != null and ts.has_method("reflect_mode"):
		ts.reflect_mode(EditorState.Mode.WALL)
	_menu.hide()

# Door mode: add a door on the clicked cell, orienting it to the wall run it bridges (falling back to
# the R-toggled default in open space). A wall on the cell becomes a doorway. One click = one undo.
func _place_door_at(local: Vector2) -> void:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return
	if _obs == null:
		return
	var orient: String = _obs.wall_run_orientation(cell)
	if orient == "":
		orient = EditorState.door_orient
	if not _obs.add_door(cell, orient):
		return
	_rebuild_world(MapIO.REBUILD_STRUCTURES)
	EditHistory.commit("door")

# BRIDGE tool: drop a crossable deck on the clicked cell, auto-oriented to the water run it spans.
# A horizontal river (water to the left/right) is crossed north-south, so the bridge is "vertical";
# a vertical river (water above/below) gets a "horizontal" bridge. When the run is ambiguous (water on
# both axes, or none) fall back to EditorState.bridge_orient (R flips it), mirroring the door open-space default.
func _place_bridge_at(local: Vector2) -> void:
	var cell := Grid.cell_of(local)
	if not _in_bounds(cell):
		return
	if _obs == null:
		return
	if _cell_liquid(cell) == "lava":
		return # wooden bridges burn: they can only be built over WATER, not lava
	var orient := _bridge_river_orientation(cell)
	if orient == "":
		orient = EditorState.bridge_orient
	if not _obs.add_bridge(cell, orient):
		return
	_rebuild_world(MapIO.REBUILD_STRUCTURES)
	EditHistory.commit("bridge")

# the majority liquid material at `cell` ("water"/"lava"/""), using the same >=2-of-4-quarters rule as
# is_cell_impassable. Lets bridges tell water (crossable) from lava (never bridgeable).
func _cell_liquid(cell: Vector2i) -> String:
	var water := 0
	var lava := 0
	for dx in 2:
		for dy in 2:
			match _quad_mat.get(Vector2i(cell.x * 2 + dx, cell.y * 2 + dy), ""):
				"water": water += 1
				"lava": lava += 1
	if water >= 2:
		return "water"
	if lava >= 2:
		return "lava"
	return ""

# the bridge orientation the WATER around `cell` implies, or "" if ambiguous. A horizontal river
# (water left/right) -> "vertical" bridge; a vertical river (water above/below) -> "horizontal". Lava is
# NOT counted here, so a bridge never orients to (or bridges) lava.
func _bridge_river_orientation(cell: Vector2i) -> String:
	var horiz_river := _cell_liquid(cell + Vector2i(1, 0)) == "water" or _cell_liquid(cell + Vector2i(-1, 0)) == "water"
	var vert_river := _cell_liquid(cell + Vector2i(0, 1)) == "water" or _cell_liquid(cell + Vector2i(0, -1)) == "water"
	if horiz_river and not vert_river:
		return "vertical"
	if vert_river and not horiz_river:
		return "horizontal"
	return ""

# Select tool: load the door or wall on the clicked cell into the properties inspector (a door wins
# if somehow both are present, matching the topmost-structure model). An empty cell clears it.
func _select_at(local: Vector2) -> void:
	var cell := Grid.cell_of(local)
	var inspector := get_tree().get_first_node_in_group("inspector") as Inspector
	if inspector == null:
		return
	# object layer first, then structure: a creature stands ON a cell, so clicking it should inspect
	# the creature, not the floor or a wall behind it (the cell-occupancy model's topmost-first order)
	if _creatures != null and _creatures.has_creature(cell):
		inspector.inspect_creature(cell)
	elif _obs != null and not _obs.door_at(cell).is_empty():
		inspector.inspect_door(cell)
	elif _obs != null and _obs.is_blocked(cell):
		inspector.inspect_wall(cell)
	elif _creatures != null and _creatures.has_zone(cell):
		# a zone is a rule about the REGION, under every object and structure in it, so it is the last
		# thing a click can mean -- clicking a wall inside a zone still means the wall
		inspector.inspect_zone(cell)
	else:
		inspector.clear()

# rebuild the level after a structure was added, through the same MapIO path erase/resize/load use,
# so lighting, floors and shadows recompute together (a newly enclosed room turns indoors). Undo is
# committed by the caller (per-gesture for walls, per-click for doors), not here.
# respawn the world layers an edit touched (MapIO.REBUILD_* flags), then refresh the hover
func _rebuild_world(parts: int) -> void:
	_restore_faded()
	MapIO.rebuild_live(parts)
	call_deferred("_update_hover")

# --- right-click menu: Door edits (mirror the inspector, one undo each) ---
func _edit_door(cell: Vector2i, id: int) -> void:
	var d: Dictionary = _obs.door_at(cell) if _obs != null else {}
	if d.is_empty():
		return
	if id == DOOR_FLIP_ID:
		var flipped := "vertical" if d["orientation"] == "horizontal" else "horizontal"
		_obs.set_door_orientation(cell, flipped)
		_rebuild_world(MapIO.REBUILD_STRUCTURES) # structural: respawn the gate
		EditHistory.commit("door orientation")
	elif id == DOOR_OPEN_ID:
		_obs.set_door_open(cell, not bool(d.get("open", false)))
		EditHistory.commit("door open")
	elif id == DOOR_SWING_ID:
		_obs.set_door_swing(cell, not bool(d.get("swing", false)))
		EditHistory.commit("door swing")

# --- right-click menu / Delete key: Erase ---
# Erase acts on the current selection when there is one, else on the clicked target. Delete (see
# _unhandled_key_input) is the selection-only entry point. See ROADMAP "Editor UX revisions" -> Erase.
func _menu_erase(cell: Vector2i) -> void:
	if _selection.has_selection():
		_erase_selection()
	else:
		_erase_single(cell)

# erase the whole active selection: floor quarters back to grass (clearing material/pattern/tint), or
# every wall in a wall selection. One undo entry; the selection is cleared afterwards.
func _erase_selection() -> void:
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		for q in EditorState.sel_quads:
			_quad_mat.erase(q)
			_quad_pattern.erase(q)
			_quad_tint.erase(q)
		_rebuild()
		EditHistory.commit("erase")
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		# one warning for the whole selection if any door in it has a Unique key bound to it
		if _warn_bound_keys(EditorState.sel_cells.keys(), _erase_wall_selection):
			return
		_erase_wall_selection()
	_clear_selection()
	_reset_highlight()
	call_deferred("_update_hover")

# The keys bound to any door in `cells`. Deleting such a door deletes its Unique key too (the key
# would open nothing), which ROADMAP "Locked doors and keys" requires a popup warning for.
func _bound_keys_in(cells: Array) -> Array:
	if _obs == null or _pickups == null:
		return []
	var out: Array = []
	for c in cells:
		var id: String = _obs.door_id_at(c)
		if id != "":
			out.append_array(_pickups.keys_for_door(id))
	return out

# ask before an erase that would take a bound key with it. Returns true when it asked (the caller
# stops; `on_yes` runs if the user confirms), false when there was nothing to warn about.
func _warn_bound_keys(cells: Array, on_yes: Callable) -> bool:
	var keys := _bound_keys_in(cells)
	if keys.is_empty():
		return false
	var names: Array = []
	for k in keys:
		var n := String(k.get("data", {}).get("name", ""))
		names.append(n if n != "" else Items.display_name(String(k["item"])))
	if _key_warn == null:
		_key_warn = ConfirmationDialog.new()
		_key_warn.title = "Delete door?"
		add_child(_key_warn)
	for c in _key_warn.confirmed.get_connections():
		_key_warn.confirmed.disconnect(c["callable"])
	_key_warn.dialog_text = "This door's key will be deleted with it:\n  %s\n\nDelete both?" % "\n  ".join(names)
	_key_warn.confirmed.connect(on_yes, CONNECT_ONE_SHOT)
	_key_warn.popup_centered()
	return true

# remove a door (or wall) plus any Unique keys bound to it, as ONE undo entry
func _delete_structure_with_keys(cell: Vector2i) -> void:
	if _obs == null:
		return
	var id: String = _obs.door_id_at(cell)
	_obs.remove_structure(cell)
	if _pickups != null and id != "":
		for k in _pickups.keys_for_door(id):
			_pickups.remove_pickup(k["cell"])
	_rebuild_world(MapIO.REBUILD_STRUCTURES | MapIO.REBUILD_OBJECTS)
	EditHistory.commit("erase")
	_reset_highlight()
	call_deferred("_update_hover")

# remove every wall/door in the selection, plus any Unique keys bound to those doors, as one entry
func _erase_wall_selection() -> void:
	var any := false
	if _obs != null:
		for c in EditorState.sel_cells:
			var id: String = _obs.door_id_at(c)
			if _obs.remove_structure(c) != "":
				any = true
				if _pickups != null and id != "":
					for k in _pickups.keys_for_door(id):
						_pickups.remove_pickup(k["cell"])
	if any:
		_rebuild_world(MapIO.REBUILD_STRUCTURES | MapIO.REBUILD_OBJECTS)
		EditHistory.commit("erase")
	_clear_selection()
	_reset_highlight()
	call_deferred("_update_hover")

# erase the single clicked target: remove a wall/door if one is there, else clear the cell's ground.
func _erase_single(cell: Vector2i) -> void:
	if _obs != null and _obs.has_structure(cell):
		# a door with a Unique key bound to it warns before taking the key with it
		if _warn_bound_keys([cell], _delete_structure_with_keys.bind(cell)):
			return
		_delete_structure_with_keys(cell)
		return
	# a placed item sits on top of the ground: erase it before the terrain beneath it
	if _pickups != null and _pickups.has_pickup(cell):
		_pickups.remove_pickup(cell)
		_rebuild_world(MapIO.REBUILD_OBJECTS)
		EditHistory.commit("erase")
		_reset_highlight()
		call_deferred("_update_hover")
		return
	# a placed creature shares that object layer, so it erases at the same depth as an item
	if _creatures != null and _creatures.has_creature(cell):
		_creatures.remove_creature(cell)
		_rebuild_world(MapIO.REBUILD_OBJECTS)
		EditHistory.commit("erase")
		_reset_highlight()
		call_deferred("_update_hover")
		return
	# a bridge is the next layer down (over the water floor): erase it before the ground beneath
	if _obs != null and _obs.is_bridge(cell):
		_obs.remove_bridge(cell)
		_rebuild_world(MapIO.REBUILD_STRUCTURES)
		EditHistory.commit("erase")
		_reset_highlight()
		call_deferred("_update_hover")
		return
	var changed := false
	for q in Grid.quads_of(cell):
		if _quad_mat.has(q) or _quad_pattern.has(q) or _quad_tint.has(q):
			_quad_mat.erase(q)
			_quad_pattern.erase(q)
			_quad_tint.erase(q)
			changed = true
	if changed:
		_rebuild()
		EditHistory.commit("erase")
		_reset_highlight()
		return
	# A ZONE is the LAST thing erase can mean: it is a rule about the region, sitting under every
	# object, structure and terrain in it, so it only goes once there is nothing else on the cell to
	# take. Otherwise erasing a creature standing in a zone would delete the zone out from under it.
	if _creatures != null and _creatures.remove_zone_at(cell):
		_rebuild_world(MapIO.REBUILD_OBJECTS)
		EditHistory.commit("erase")
	_reset_highlight()

# Wall/Door placement hover: a plain green cell cursor over any in-bounds cell showing where the next
# wall or door lands. No drop-preview sprite yet (walls/doors have no lifted tile art), just the cell.
func _update_structure_placement_hover(cell: Vector2i) -> void:
	_clear_room_hover()
	_restore_faded()
	_preview.hide_preview()
	if not _in_bounds(cell):
		_cursor.hide_cursor()
		_ghosts.hide_all()
		return
	_cursor.set_role(PaintCursor.Role.ADD) # green: placing a wall/door is additive
	_cursor.show_rect(Grid.cell_rect(cell))
	# Also float the REAL thing a click would place, like the bridge deck preview. WALL: the wall shape
	# (horizontal/vertical/corner/T/cross) in the armed colour+material, over an empty cell. DOOR: the
	# closed door, auto-oriented to the wall run it would bridge.
	if EditorState.mode == EditorState.Mode.WALL and _obs != null and not _obs.is_blocked(cell):
		_ghosts.show_wall(cell)
		_ghosts.hide_door()
	elif EditorState.mode == EditorState.Mode.DOOR and _obs != null:
		_ghosts.hide_wall()
		_ghosts.show_door(cell)
	else:
		_ghosts.hide_wall()
		_ghosts.hide_door()

# Bridge placement hover: a green ADD cell cursor (like wall/door) PLUS the real deck art lifted a few
# px above the cell, oriented to the water run the click would span (or the R-flippable default). Shows
# the bridge that will land instead of the last floor material's drop-preview.
func _update_bridge_hover(cell: Vector2i) -> void:
	_clear_room_hover()
	_restore_faded()
	_preview.hide_preview() # never show the leftover floor-material drop-preview in BRIDGE mode
	if not _in_bounds(cell):
		_cursor.hide_cursor()
		_ghosts.hide_bridge()
		return
	# lava can't be bridged (wooden bridges burn): mark it invalid (red cursor, no deck preview)
	if _cell_liquid(cell) == "lava":
		_cursor.set_role(PaintCursor.Role.ERASE)
		_cursor.show_rect(Grid.cell_rect(cell))
		_ghosts.hide_bridge()
		return
	_cursor.set_role(PaintCursor.Role.ADD)
	_cursor.show_rect(Grid.cell_rect(cell))
	var orient := _bridge_river_orientation(cell)
	if orient == "":
		orient = EditorState.bridge_orient
	_ghosts.show_bridge(cell, orient)

# set one quarter's material ("" erases it back to grass). Returns whether anything changed,
# so a drag that stays inside the same quarter doesn't trigger a redundant rebuild.
func _write_quad(q: Vector2i, mat: String) -> bool:
	if mat != "" and FloorMaterials.TEXTURES.has(mat):
		# a change is the material OR the bank flag flipping (re-painting a liquid with the switch toggled)
		var want_no_bank: bool = FloorMaterials.LIQUID_SHORE.has(mat) and not EditorState.bank_on
		var changed: bool = _quad_mat.get(q) != mat or _quad_no_bank.has(q) != want_no_bank
		_quad_mat[q] = mat
		_stamp_bank(q, mat)
		return changed
	if not _quad_mat.has(q):
		return _quad_no_bank.erase(q) # erasing already-grass: only a change if it cleared a stray flag
	_quad_mat.erase(q)
	_quad_pattern.erase(q) # grass carries no pattern; drop the orphaned index
	_quad_no_bank.erase(q)
	return true

# record the river-bank switch for a freshly-painted quarter: a LIQUID quarter laid with the switch OFF
# goes into _quad_no_bank (so it grows no bank); anything else clears any stale flag.
func _stamp_bank(q: Vector2i, mat: String) -> void:
	if FloorMaterials.LIQUID_SHORE.has(mat) and not EditorState.bank_on:
		_quad_no_bank[q] = true
	else:
		_quad_no_bank.erase(q)

# the Brush-panel river-bank switch (set BEFORE laying a liquid): on = new liquid grows a brown bank,
# off = none. Only affects quarters painted while it is on/off (stored per-quarter in _quad_no_bank).
func set_bank_on(on: bool) -> void:
	EditorState.bank_on = on
	EditorState.brush_changed.emit()

func bank_on() -> bool:
	return EditorState.bank_on

# dim any wall/door standing on `cell` to 30% so its ground shows through while it is edited.
func _fade_obstacles_at(cell: Vector2i) -> void:
	if cell == _faded_cell:
		return # already dimmed for this cell
	_restore_faded()
	_faded_cell = cell
	# skip nodes already queued for deletion: an Erase rebuild frees the old wall/gate nodes but
	# they linger in their group for the rest of the frame, and fading one would leave a freed
	# reference in _faded that _restore_faded would later touch (use-after-free).
	for w in get_tree().get_nodes_in_group("walls"):
		if not w.is_queued_for_deletion() and w.has_method("covers_cell") and w.covers_cell(cell):
			_fade(w)
	for g in get_tree().get_nodes_in_group("gates"):
		if not g.is_queued_for_deletion() and g.cell == cell:
			_fade(g)
			if g.back_layer and not g.back_layer.is_queued_for_deletion():
				_fade(g.back_layer) # vertical gate's behind-player post + door

func _fade(node: CanvasItem) -> void:
	_faded.append([node, node.modulate])
	node.modulate.a = 0.3

# put every dimmed obstacle back to full opacity. Guards is_instance_valid because an Erase rebuild
# can free a faded wall/gate between fading and restoring, and touching a freed node throws.
func _restore_faded() -> void:
	for e in _faded:
		if is_instance_valid(e[0]):
			e[0].modulate = e[1]
	_faded.clear()
	_faded_cell = Grid.INVALID_CELL

# does `cell` exist on the map (inside the grid AND not a hole)? Every tool and the floor render treat a
# hole exactly like off-map: nothing is painted, placed, stamped or banked into one. Walls don't stop a
# paint: the ground under a wall/door is editable (the obstacle fades while you paint, _fade_obstacles_at).
func _in_bounds(cell: Vector2i) -> bool:
	return _grid_bg == null or _grid_bg.cell_present(cell.x, cell.y)

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
	for q in _room_quads(cells):
		_write_quad(q, style)

# replace all floors from a v1 per-room style list (used by the MapIO v1->v2 load migration).
# Must run AFTER RoomLight has rebuilt, since the room a style fills is found by flood fill.
func apply_floors(list: Array) -> void:
	_quad_mat.clear()
	for f in list:
		var style: String = f["style"]
		if style == "" or not FloorMaterials.TEXTURES.has(style):
			continue
		_write_room(room_light.room_floor_cells(f["cell"]), style)
	_rebuild()

# replace all floors from a v2 quarter list [[qx, qy, material], ...] (used by MapIO on load).
func apply_quads(list: Array) -> void:
	_quad_mat.clear()
	_quad_no_bank.clear() # repopulated by apply_no_bank (MapIO calls it before the final rebuild)
	for a in list:
		var mat: String = a[2]
		if not FloorMaterials.TEXTURES.has(mat):
			continue
		_quad_mat[Vector2i(int(a[0]), int(a[1]))] = mat
	_rebuild()

# load the LIQUID river-bank OFF flags (MapIO v9+). No rebuild here (apply_tints does the final one),
# mirroring apply_patterns. A pre-v9 load passes [] so every liquid keeps its default bank.
func apply_no_bank(list: Array) -> void:
	_quad_no_bank.clear()
	for a in list:
		_quad_no_bank[Vector2i(int(a[0]), int(a[1]))] = true

# replace all floor patterns from a saved list [[qx, qy, index], ...] (used by MapIO on load). Only
# meaningful over quarters that also carry a material; a stale index is clamped at draw. Does NOT
# rebuild: apply_quads/apply_tints (which run around it) do, and the caller ends with a rebuild.
func apply_patterns(list: Array) -> void:
	_quad_pattern.clear()
	for a in list:
		var idx := int(a[2])
		if idx != 0:
			_quad_pattern[Vector2i(int(a[0]), int(a[1]))] = idx

# set one quarter's pattern index (0 erases the entry back to the default pattern). Returns whether
# anything changed. A no-op if the quarter has no material (pattern only means something over one).
func _write_pattern(q: Vector2i, idx: int) -> bool:
	if not _quad_mat.has(q):
		return false
	var cur: int = _quad_pattern.get(q, 0)
	if cur == idx:
		return false
	if idx == 0:
		_quad_pattern.erase(q)
	else:
		_quad_pattern[q] = idx
	return true

# the pattern index at 16px quarter `q` (0 = default). Read by the shadow restamp so a door-open
# relight redraws the same pattern the base_fills use.
func floor_pattern_at_quad(q: Vector2i) -> int:
	return _quad_pattern.get(q, 0)

# replace all floor tints from a v5 list [[qx, qy, r, g, b], ...] (used by MapIO on load). An
# empty list (a pre-v5 map) simply clears any tints. Must run AFTER apply_quads so the rebuild
# draws tints over the materials just restored.
func apply_tints(list: Array) -> void:
	_quad_tint.clear()
	for a in list:
		_quad_tint[Vector2i(int(a[0]), int(a[1]))] = Color(float(a[2]), float(a[3]), float(a[4]))
	_rebuild()

# the floor stores changed: mark the render derivation stale and queue the redraw. The fills themselves are
# built lazily on the next read (grid_background's _draw), so a paint drag that writes many quarters in one
# frame, or a load that sets materials, patterns and tints back to back, derives them once, not per write.
func _rebuild() -> void:
	_fills_dirty = true
	_redraw_floor_layers()

func _ensure_fills() -> void:
	if _fills_dirty:
		_fills_dirty = false
		_base_fills = _render.build()
		_has_water = _render.has_water

func _redraw_floor_layers() -> void:
	if _grid_bg:
		_grid_bg.queue_redraw()
	if _shadows:
		_shadows.refresh()

# --- read by grid_background and shadow_manager ---

func base_fills() -> Array:
	_ensure_fills()
	return _base_fills

# any water on the map this rebuild, so grid_background runs the shimmer redraw loop only when needed
# (zero cost on a dry map). Set in _rebuild whenever a water quarter emits a fill.
func has_animated_water() -> bool:
	_ensure_fills()
	return _has_water

# the floor texture that renders at 16px quarter `q`, or null for the grass base. The single
# source of truth the door-open shadow pass restamps from, so it matches the indoor base_fills
# exactly (every painted quarter, interior or under a wall/door).
func floor_tex_at_quad(q: Vector2i) -> Texture2D:
	return FloorMaterials.texture(_quad_mat[q], _quad_pattern.get(q, 0)) if _quad_mat.has(q) else null

# the multiply tint at 16px quarter `q` (white = none), so the door-open shadow restamp tints the
# floor the same way base_fills does (see shadow_manager._stamp_floor).
func floor_tint_at_quad(q: Vector2i) -> Color:
	return _quad_tint.get(q, Color.WHITE)

# can something stand on `cell`? The TERRAIN rule the player's movement and zone spawning share: the cell
# exists, holds no wall, and its floor is passable -- or bridged, a deck re-enabling crossing over water.
# Doors, locks and occupants are layered on by each caller (is_blocked stays "is a wall" for the editor).
func is_walkable(cell: Vector2i) -> bool:
	if not _in_bounds(cell) or (_obs != null and _obs.is_blocked(cell)):
		return false
	return not is_cell_impassable(cell) or (_obs != null and _obs.is_bridge(cell))

# does the FLOOR at 32px cell `cell` block movement? Cell-level granularity (matches the 32px move
# grid): a cell holds 2x2 quarters, and it blocks when a MAJORITY (>=2 of 4) carry a FloorMaterials.IMPASSABLE
# material. Majority (not "any") keeps a lone stray quarter - e.g. a future shoreline/bank quarter -
# from sealing an otherwise-walkable cell; a full-water cell has all four, so it always blocks.
# Consulted by the player alongside obstacles.is_blocked (walls); see the FloorMaterials.IMPASSABLE note above.
func is_cell_impassable(cell: Vector2i) -> bool:
	var count := 0
	for dx in 2:
		for dy in 2:
			var q := Vector2i(cell.x * 2 + dx, cell.y * 2 + dy)
			if FloorMaterials.IMPASSABLE.has(_quad_mat.get(q, "")):
				count += 1
	return count >= 2

# --- persistence: the floor's slice of the MapIO map dict. Every store is sparse, as 16px-quarter rows:
# quads [qx, qy, material], floor_tints [qx, qy, r, g, b], floor_patterns [qx, qy, index] (non-default
# only), floor_no_bank [qx, qy] (liquid quarters laid with the bank switch off). ---

func to_data() -> Dictionary:
	var quads: Array = []
	for q in _quad_mat:
		quads.append([q.x, q.y, _quad_mat[q]])
	var tints: Array = []
	for q in _quad_tint:
		var c: Color = _quad_tint[q]
		tints.append([q.x, q.y, c.r, c.g, c.b])
	var patterns: Array = []
	for q in _quad_pattern:
		patterns.append([q.x, q.y, _quad_pattern[q]])
	var no_bank: Array = []
	for q in _quad_no_bank:
		no_bank.append([q.x, q.y])
	return {"quads": quads, "floor_tints": tints, "floor_patterns": patterns, "floor_no_bank": no_bank}

# replace the whole floor from a map dict. Must run AFTER RoomLight has rebuilt: a v1 map stored per-room
# styles, migrated here by flood-filling each room into its quarters. Missing keys (older maps) clear to
# the default: no patterns (pre-v7), every liquid banked (pre-v9), no tints (pre-v5).
func load_data(data: Dictionary) -> void:
	if int(data.get("version", 1)) >= 2:
		apply_quads(data.get("quads", []))
	else:
		var floors: Array = []
		for f in data.get("floors", []):
			floors.append({"cell": Vector2i(int(f["cell"][0]), int(f["cell"][1])), "style": f["style"]})
		apply_floors(floors)
	apply_patterns(data.get("floor_patterns", []))
	apply_no_bank(data.get("floor_no_bank", []))
	apply_tints(data.get("floor_tints", []))
