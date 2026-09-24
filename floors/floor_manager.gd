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
const GRID_COLOR := Color(0.38, 0.64, 0.95, 0.4)


# how a right-click Door edit changes the door (see edit_door)
enum DoorEdit { FLIP, TOGGLE_OPEN, TOGGLE_SWING }

@onready var room_light: RoomLight = get_node("../RoomLight")

# Storage is per 16px quarter: _quad_mat is the SOURCE OF TRUTH (what MapIO saves). Everything
# else is derived in rebuild. A room fill (set_room_style) just writes all four quarters of every
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
var _fills_dirty := false # the floor stores changed since _base_fills was built (rebuilt lazily on read)
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
var cursor: Node2D          # the Cell/Fine square paint cursor (see paint_cursor.gd)
var preview: Node2D         # the lifted terrain drop-preview sprite (see terrain_preview.gd)
var ghosts: PlacementGhosts # the wall / door / bridge placement previews (placement_ghosts.gd)
var menu: ContextMenu # the right-click menu (context_menu.gd)
var selection: SelectionTool # the wand / box selection and its marching ants (selection_tool.gd)
var _clip_ghost: Node2D      # hover ghost for an armed paste / an in-flight move (clip_preview.gd)
var _zone_active := false    # true while a zone rectangle is being dragged out
var _zone_start := Vector2i.ZERO # the cell that drag began on
var _key_warn: ConfirmationDialog # "deleting this door deletes its key" warning, built on first use
var ghost_origin_pin := INVALID_CELL # dev hook (dev/capture.gd): pin the ghost's origin instead of
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
@onready var render := FloorRender.new(_quad_mat, _quad_tint, _quad_pattern, _quad_no_bank, _grid_bg)

func _ready() -> void:
	# recompute the hover AFTER camera_follow has moved the camera this frame (it runs at the
	# default priority 0), so the highlight stays under the mouse while the player walks and the
	# world scrolls, not just when the mouse itself moves. Same rationale as FloorHighlightMask.
	process_priority = 100
	menu = ContextMenu.new()
	add_child(menu)
	menu.setup(self, _obs)
	# the Cell/Fine square paint cursor; Wand uses the mask preview + selection overlay instead
	cursor = Node2D.new()
	cursor.set_script(load("res://floors/paint_cursor.gd"))
	cursor.z_index = 1000
	add_child(cursor)
	# the lifted terrain drop-preview sprite (Cell/Fine placement): armed material floats over the
	# hovered cell and falls in on click. Above the cursor so it reads as lifted over the highlight.
	preview = Node2D.new()
	preview.set_script(load("res://floors/terrain_preview.gd"))
	add_child(preview)
	# the lifted previews of what a WALL / DOOR / BRIDGE click would build
	ghosts = PlacementGhosts.new()
	add_child(ghosts)
	ghosts.setup(_obs)
	# when the cursor leaves the game window, drop every highlight (ROADMAP "Terrain placement UX":
	# cursor off screen clears all highlights); restore tracking when it returns
	get_window().mouse_exited.connect(_on_window_mouse_exited)
	get_window().mouse_entered.connect(_on_window_mouse_entered)
	# the marching-ants selection overlay the Magic Wand builds and the menu fills
	selection = SelectionTool.new()
	add_child(selection)
	selection.setup(self, _obs, room_light)
	# the paste/move hover ghost: draws the armed clip over the cells it would land on. It borrows
	# this manager's texture lookup so the ghost shows the real material art, and its bounds test so
	# cells that would be clipped at the map edge read red before the click.
	_clip_ghost = Node2D.new()
	_clip_ghost.set_script(load("res://floors/clip_preview.gd"))
	add_child(_clip_ghost)
	_clip_ghost.setup(func(mat: String, pat: int) -> Texture2D: return FloorMaterials.texture(mat, pat), in_bounds)
	# leaving EDIT drops every piece of editor state that would otherwise sit frozen on top of the
	# running game: the map tools stand down in PLAY (see _process / _unhandled_input), so anything
	# already on screen would just stay there, and a selection you cannot change is not a selection.
	EditorMode.changed.connect(func(_m):
		if EditorMode.is_play():
			_exit_edit_state())
	_click_tools = {
		EditorState.Mode.ITEM: place_item_at, EditorState.Mode.CREATURE: place_creature_at, EditorState.Mode.SPAWN: set_spawn_at,
		EditorState.Mode.EYEDROP: eyedrop_at, EditorState.Mode.SELECT: select_at, EditorState.Mode.DOOR: place_door_at,
		EditorState.Mode.BRIDGE: place_bridge_at,
	}
	call_deferred("_seed") # keep the existing wooden room once RoomLight has built

# clear everything the editor was holding: the marching-ants selection, an armed paste or half-finished
# move, every hover highlight, and any obstacle dimmed under the cursor. Nothing is restored on the way
# back to EDIT -- you return to a clean slate rather than a stale selection from before you played.
func _exit_edit_state() -> void:
	selection.clear()
	cancel_pending()
	EditorState.armed = false      # an armed terrain brush would otherwise drop a tile on the first click back
	_painting = false
	_box_active = false
	_box_maybe = false
	_cancel_zone_drag() # a half-dragged zone rectangle is live editor state like any other
	reset_highlight()
	restore_faded()
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
	reset_highlight()
	restore_faded()

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
	# doing it per motion event stutters). The walls were already added to the model in place_wall_at.
	if _walls_dirty:
		_walls_dirty = false
		_rebuild_world(MapIO.REBUILD_STRUCTURES)
	# while the cursor is over the editor menu/panels, stand down: clear the hover once on entering the
	# menu and keep it hidden, so no paint cursor / preview / select highlight shows over the UI.
	if _pointer_over_ui():
		if not _ui_hid:
			_ui_hid = true
			reset_highlight()
			restore_faded()
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
	return clamp_cell(Grid.cell_of(get_local_mouse_position()))

func _on_right_press() -> void:
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	# a right-click cancels an armed paste (the standard "drop the loaded brush" gesture, matching
	# the Cell/Fine right-click-disarms rule); the clipboard keeps the clip for the next Ctrl+V.
	if EditorState.pending_kind == EditorState.Pending.PASTE:
		cancel_pending()
		_handled()
		return
	# Cell/Fine: a right-click while a material is armed just cancels the brush (removes the floating
	# drop-preview graphic), no menu. A second right-click (now un-armed) opens the menu as usual.
	# See ROADMAP "Editor UX revisions" -> right-click disarms in Cell/Fine.
	if (EditorState.mode == EditorState.Mode.CELL or EditorState.mode == EditorState.Mode.FINE) and EditorState.armed:
		EditorState.armed = false
		EditorState.brush_changed.emit()
		preview.hide_preview() # drop the lifted tile immediately (the square cursor stays)
		_handled()
		return
	# a right-click off the map, or off the current selection, deselects (rather than opening the
	# menu). A right-click INSIDE the selection falls through to open the menu, so it can still act
	# on the selection. See ROADMAP "Editor UX revisions" -> deselect a Wand selection.
	if selection.overlay.has_selection() and (not in_bounds(cell) or not selection.contains(local)):
		selection.clear()
		_handled()
		return
	if not in_bounds(cell):
		return # right-clicked off the map
	menu.open_at(local) # rebuilt for the clicked target, at the mouse
	_handled()

func _on_left_button(event: InputEventMouseButton) -> void:
	# an armed paste owns the next left click, in ANY mode: it stamps the clip where the ghost sits.
	if EditorState.pending_kind == EditorState.Pending.PASTE:
		if event.pressed:
			drop_pending()
		_handled()
		return
	# clicking off the map deselects the current selection (any mode), per "Editor UX revisions"
	# -> deselect a Wand selection ("clicking off the map would logically deselect").
	if event.pressed and selection.overlay.has_selection() and not in_bounds(Grid.cell_of(get_local_mouse_position())):
		selection.clear()
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

# ONE Select tool, two gestures (2026-09-05: Magic Wand and Box Select merged): a CLICK grows a
# selection (patch -> room, run -> building), a DRAG boxes one. The press just arms both and waits to
# see which happened. Shift adds / Alt subtracts either way ("Editor UX revisions" -> additive/
# subtractive selection). Selecting never paints.
func _left_wand(event: InputEventMouseButton) -> void:
	if event.pressed:
		var local := get_local_mouse_position()
		var pc := clamp_cell(Grid.cell_of(local))
		if in_bounds(pc):
			_box_maybe = true
			_box_press = local
			selection.begin_box(pc, event)
			_handled()
		return
	if _box_active:
		_box_active = false # the drag already committed its rectangle into EditorState.sel_quads
	elif _box_maybe:
		# released without dragging: a wand click, and it also loads whatever was clicked into the
		# properties inspector (the old separate Select tool, now folded in)
		var lc := get_local_mouse_position()
		if in_bounds(Grid.cell_of(lc)):
			selection.wand_click(lc, selection.box_op)
			select_at(lc)
	_box_maybe = false
	_handled()

# drag a rectangle: press starts it, motion grows it (_on_mouse_motion), release finalizes
func _left_box(event: InputEventMouseButton) -> void:
	if event.pressed:
		var cell := _mouse_cell_clamped()
		if in_bounds(cell):
			_box_active = true
			selection.begin_box(cell, event)
			selection.update_box(cell)
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
		if selection.overlay.has_selection() and selection.contains(ml):
			begin_move(Grid.cell_of(ml))
			_handled()
	elif EditorState.pending_kind == EditorState.Pending.MOVE:
		drop_pending()
		_handled()

# a creature ZONE is a REGION, so it is DRAGGED out (press, drag, release) rather than clicked -- the
# same gesture box-select and wall-drawing already use
func _left_zone(event: InputEventMouseButton) -> void:
	if event.pressed:
		begin_zone(_mouse_cell_clamped())
	elif _zone_active:
		end_zone(_mouse_cell_clamped())
	_handled()

# a zone drag: start it on `cell` (ignored off the map), grow it with update_zone_drag, land it at `cell`
func begin_zone(cell: Vector2i) -> void:
	if in_bounds(cell):
		_zone_active = true
		_zone_start = cell
		update_zone_drag(cell)

func end_zone(cell: Vector2i) -> void:
	_zone_active = false
	commit_zone(cell)

# click-and-drag draws a wall line; the whole gesture is one undo entry
func _left_wall(event: InputEventMouseButton) -> void:
	if event.pressed:
		_painting = true
		place_wall_at(get_local_mouse_position())
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
		eyedrop_at(get_local_mouse_position())
		_handled()
		return
	# Erase removes the topmost structure (wall/door) first, as a single click; only once no structure
	# remains does a further click erase the terrain beneath it (cell-occupancy model, ROADMAP "Erase
	# mode"). Structure removal consumes the click (no paint drag).
	if EditorState.mode == EditorState.Mode.ERASE and erase_structure_at(get_local_mouse_position()):
		_handled()
		return
	_painting = true
	paint(get_local_mouse_position(), true) # fresh click: play the drop animation
	_handled()

func _on_mouse_motion() -> void:
	if _box_maybe and not _box_active and get_local_mouse_position().distance_to(_box_press) > DRAG_SLOP:
		_box_active = true # far enough to mean "drag a box", not "click that thing"
	if _zone_active:
		update_zone_drag(_mouse_cell_clamped())
	if _painting:
		paint(get_local_mouse_position())
	elif _box_active:
		selection.update_box(_mouse_cell_clamped())
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
		copy_selection()
		get_viewport().set_input_as_handled()
		return
	if mod and event.keycode == KEY_V:
		arm_paste(MapClipboard.clip())
		get_viewport().set_input_as_handled()
		return
	if mod and event.keycode == KEY_D:
		# duplicate = copy the selection and immediately arm it, so the copy is dropped by the next click
		if copy_selection():
			arm_paste(MapClipboard.clip())
		get_viewport().set_input_as_handled()
		return
	# --- rotate / flip the clip about to land (paste ghost or move drag) ---
	if not EditorState.pending_clip.is_empty() and event.keycode == KEY_R:
		transform_pending(MapClipboard.rotate_cw(EditorState.pending_clip))
		get_viewport().set_input_as_handled()
		return
	if not EditorState.pending_clip.is_empty() and event.keycode == KEY_H:
		transform_pending(MapClipboard.flip_v(EditorState.pending_clip) if event.shift_pressed else MapClipboard.flip_h(EditorState.pending_clip))
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and not EditorState.pending_clip.is_empty():
		cancel_pending() # Esc drops the armed paste / aborts the move drag before it lands
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and selection.overlay.has_selection():
		selection.clear()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DELETE and selection.overlay.has_selection():
		# Delete erases the current selection (ROADMAP "Editor UX revisions" -> Erase = also the Delete key)
		_erase_selection()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and EditorState.mode == EditorState.Mode.DOOR:
		EditorState.door_orient = Grid.flip(EditorState.door_orient)
		call_deferred("_update_hover")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and EditorState.mode == EditorState.Mode.BRIDGE:
		EditorState.bridge_orient = Grid.flip(EditorState.bridge_orient)
		call_deferred("_update_hover")
		get_viewport().set_input_as_handled()

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
	cancel_pending()   # nor an armed paste / half-finished move drag
	if EditorState.mode != EditorState.Mode.WAND:
		EditorState.tool_kind = EditorState.Brush.FLOOR
	# Cell/Fine must not start with a material armed to drop: the user picks one from the menu first
	# (ROADMAP "Editor UX revisions" -> Cell/Fine must not pre-arm a material).
	if EditorState.mode == EditorState.Mode.CELL or EditorState.mode == EditorState.Mode.FINE:
		EditorState.armed = false
	EditorState.brush_changed.emit()
	reset_highlight()
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
	return cell if in_bounds(cell) else INVALID_CELL

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

# --- wall side of the Brush panel: read + set the armed wall material + colour (mirrors the floor API
# above). A WALL selection reflects its look here, and picking here edits the wall selection in place.

func armed_wall_material() -> String:
	return EditorState.wall_mat

func active_wall_color() -> Color:
	return EditorState.wall_color

func armed_wall_texture() -> Texture2D:
	return WallSegment.swatch_texture(EditorState.wall_mat)

func arm_wall_material(mat: String) -> void:
	EditorState.tool_kind = EditorState.Brush.WALL_MATERIAL
	EditorState.wall_mat = mat
	if selection.has_wall():
		_obs.material_cells(EditorState.sel_cells, mat)
		EditHistory.commit("wall material")
	EditorState.brush_changed.emit()

func arm_wall_color(color: Color) -> void:
	EditorState.tool_kind = EditorState.Brush.WALL_COLOR
	EditorState.wall_color = color
	if selection.has_wall():
		_obs.color_cells(EditorState.sel_cells, color)
		EditHistory.commit("wall colour")
	EditorState.brush_changed.emit()

# arm a floor material from the panel (same as picking it in the Floor Textures menu in Cell/Fine: it
# arms the brush; the user then paints/drops it). No selection-fill here (that stays a menu convenience).
func arm_floor_material(mat: String) -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.brush = mat
	EditorState.armed = true
	# with a floor selection active, picking a material RE-TEXTURES the selection in place (the two-way
	# panel binding), keeping its colour and the selection itself so the user can keep tweaking.
	if selection.has_floor():
		_fill_floor_selection(mat) # rebuilds
		EditHistory.commit("paint")
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

# arm the floor-colour from the panel with `color`. Unlike the Floor Colours *menu* (which arms a
# tint-only recolour tool), the panel brush is COMBINED: colour and texture are two axes of one floor
# brush, so setting the colour keeps the armed material and a paint lays both together (see paint).
# White = Natural = lays the plain (untinted) material. The material stays armed and lit in the panel.
func arm_floor_color(color: Color) -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.floor_color = color
	EditorState.armed = true
	# with a floor selection active, picking a colour RE-TINTS the selection in place (the two-way panel
	# binding), keeping its texture and the selection itself. White = Natural clears the tint.
	if selection.has_floor():
		if _write_quads(EditorState.sel_quads, func(q: Vector2i) -> bool: return write_tint(q, color)):
			rebuild()
			EditHistory.commit("floor colour")
	EditorState.brush_changed.emit()
	call_deferred("_update_hover")

# --- Magic Wand selection ---

# clamp a cell to the map so a box drag never runs off the edge
func clamp_cell(cell: Vector2i) -> Vector2i:
	if _grid_bg == null:
		return cell
	return Vector2i(clampi(cell.x, 0, _grid_bg.grid_width - 1), clampi(cell.y, 0, _grid_bg.grid_height - 1))

# every quarter of a room: the interior cells' quarters plus the wall-ring quarters, matching
# _write_room so a whole-room selection fill reaches under the walls the same way a room fill does.
func room_quads(cells: Dictionary) -> Dictionary:
	var out := {}
	for c in cells:
		for cq in Grid.quads_of(c):
			out[cq] = true
	for rect in room_light.wall_ring_quads(cells):
		out[Grid.quad_of(rect.position)] = true
	return out

# --- the floor, by 16px quarter, for tools and tests. The stores stay private; write through write_quad /
# write_tint / write_pattern (then rebuild()), read through these. The views are read-only by contract.

# the material at quarter `q` ("" = plain grass)
func material_at(q: Vector2i) -> String:
	return _quad_mat.get(q, "")

func quad_materials() -> Dictionary:
	return _quad_mat

func quad_tints() -> Dictionary:
	return _quad_tint

func quad_patterns() -> Dictionary:
	return _quad_pattern

func quad_no_bank() -> Dictionary:
	return _quad_no_bank

# back to all grass: every material, tint, pattern and bank flag cleared
func clear_floor() -> void:
	_quad_mat.clear()
	_quad_tint.clear()
	_quad_pattern.clear()
	_quad_no_bank.clear()
	rebuild()

# --- Eyedropper (ROADMAP "Eyedropper"): load the brush from what is already on the map ---

# pick what is under `local` into the active brush, so matching existing terrain needs no palette
# hunting. A picked value NEVER edits the map: it writes the brush fields directly rather than going
# through arm_floor_material / arm_wall_material, which deliberately re-fill an active selection.
# Returns whether anything was picked.
func eyedrop_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
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
func set_spawn_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
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
func place_item_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
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
func place_creature_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
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

func update_zone_drag(cur: Vector2i) -> void:
	if _creatures != null:
		_creatures.set_zone_preview(_zone_rect(cur), EditorState.creature)

# the drag landed: turn the dragged rectangle into a real zone, as one undo entry
func commit_zone(cur: Vector2i) -> bool:
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

# Ctrl+C: put the current selection's region on the (cross-map, disk-backed) clipboard.
func copy_selection() -> bool:
	var cells := selection.cells()
	if cells.is_empty():
		return false
	MapClipboard.set_clip(MapClipboard.build_clip(MapIO.serialize(), cells))
	return true

# Ctrl+V (and duplicate): arm `clip` as a paste brush; the ghost follows the cursor until a click.
func arm_paste(clip: Dictionary) -> void:
	if clip.is_empty():
		return
	EditorState.pending_clip = clip
	EditorState.pending_kind = EditorState.Pending.PASTE
	EditorState.pending_changed = false
	EditorState.pending_id += 1
	reset_highlight()
	call_deferred("_update_hover")

# MOVE mode: grab the current selection at `grab` and start dragging it.
func begin_move(grab: Vector2i) -> void:
	var cells := selection.cells()
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
func transform_pending(clip: Dictionary) -> void:
	if clip.is_empty():
		return
	EditorState.pending_clip = clip
	EditorState.pending_changed = true # so a move that only rotates still counts as an edit
	EditorState.pending_id += 1
	call_deferred("_update_hover")

# where the armed clip's top-left cell currently sits: a PASTE centres the block on the cursor (so
# hovering reads as carrying it), a MOVE keeps the offset from the cell the drag grabbed.
func _pending_origin() -> Vector2i:
	if ghost_origin_pin != INVALID_CELL:
		return ghost_origin_pin # pinned by the capture harness; never set in normal play
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	if EditorState.pending_kind == EditorState.Pending.MOVE:
		return EditorState.move_origin + (cell - EditorState.move_grab)
	return cell - Vector2i(int(EditorState.pending_clip.get("w", 1)) / 2, int(EditorState.pending_clip.get("h", 1)) / 2)

# drop the armed clip: stamp a paste, or complete a move (clear the source + stamp), one undo entry.
# The landed region becomes the selection, so it can be moved again or filled straight away.
func drop_pending() -> void:
	var origin := _pending_origin()
	var stamped := {}
	if EditorState.pending_kind == EditorState.Pending.MOVE:
		if origin != EditorState.move_origin or EditorState.pending_changed:
			stamped = MapEdit.move_clip(EditorState.move_src, EditorState.pending_clip, origin)
		else:
			stamped = EditorState.move_src # dropped where it started: no edit, keep the selection put
	else:
		stamped = MapEdit.stamp_clip(EditorState.pending_clip, origin)
	cancel_pending()
	if not stamped.is_empty():
		selection.select_cells(stamped)
	reset_highlight()
	call_deferred("_update_hover")

# drop the armed paste / abort the move drag without editing the map
func cancel_pending() -> void:
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
	rebuild()

# world-space quarter rects of the current floor selection, EXCLUDING quarters under a wall/door (the
# selection's under-structure ring), so the shape-drop animation lands on visible floor only and does
# not draw a lifted tile over a wall. Used to animate a selection fill (see play_shape_drop).
func selection_drop_rects() -> Array:
	var out: Array = []
	for q in EditorState.sel_quads:
		var cell := Grid.cell_of_quad(q) # 2 quarters per 32px cell axis
		if _obs != null and _obs.has_structure(cell):
			continue
		out.append(Grid.quad_rect(q))
	return out

# hide every highlight so a fresh edit reads clearly; they return on the next mouse move
func reset_highlight() -> void:
	_hover_cell = INVALID_CELL
	_wall_hover = INVALID_CELL
	_whole_hover_key = ""
	_mask.hide_floor()
	cursor.hide_cursor()
	preview.hide_preview()
	if ghosts != null:
		ghosts.hide_all()
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
	if menu.is_open():
		return # keep the highlight put while the menu is open
	if not _mouse_inside:
		return # cursor is off the game window; highlights were cleared on exit
	var local := get_local_mouse_position()
	var cell := Grid.cell_of(local)
	# an armed paste / an in-flight move owns the hover surface: the clip ghost replaces every other
	# cursor, so what is about to land is the only thing previewed.
	if not EditorState.pending_clip.is_empty():
		_clear_room_hover()
		cursor.hide_cursor()
		preview.hide_preview()
		restore_faded()
		_clip_ghost.show_clip(EditorState.pending_clip, _pending_origin(), EditorState.pending_id)
		return
	_clip_ghost.hide_clip()
	if EditorState.mode == EditorState.Mode.MOVE:
		# MOVE with nothing grabbed: the marching ants already mark what a drag would pick up, so no
		# extra cursor (a paint cursor here would read as "this cell will be edited", which it will not)
		_clear_room_hover()
		cursor.hide_cursor()
		preview.hide_preview()
		restore_faded()
		return
	# Wand: preview the ONE thing a click would select (building walls over a wall, room floor over
	# a floor). The committed selection is drawn separately by the marching-ants overlay.
	if EditorState.mode == EditorState.Mode.WAND:
		_update_whole_hover(cell)
		return
	if EditorState.mode == EditorState.Mode.BOX:
		# box-select draws its rectangle during the drag (marching-ants overlay); no paint cursor/preview
		_clear_room_hover()
		cursor.hide_cursor()
		preview.hide_preview()
		restore_faded()
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
		preview.hide_preview()
		restore_faded()
		if not in_bounds(cell):
			cursor.hide_cursor()
			return
		cursor.set_role(PaintCursor.Role.GROUND)
		var eq := Grid.quad_of(local)
		cursor.show_rect(Grid.quad_rect(eq))
		return
	# after a wall colour or material is picked, outline the single wall under the cursor
	if EditorState.tool_kind == EditorState.Brush.WALL_COLOR or EditorState.tool_kind == EditorState.Brush.WALL_MATERIAL:
		_update_wall_hover(cell)
		return
	# Cell / Fine / Erase: the square paint cursor over paintable ground, and any obstacle over that
	# cell dimmed so the ground under it stays visible while painting
	_clear_room_hover()
	if not in_bounds(cell):
		cursor.hide_cursor()
		preview.hide_preview()
		restore_faded()
		return
	fade_obstacles_at(cell)
	# terrain paint is a ground edit (orange); erase is destructive (red)
	cursor.set_role(PaintCursor.Role.ERASE if EditorState.mode == EditorState.Mode.ERASE else PaintCursor.Role.GROUND)
	if EditorState.mode == EditorState.Mode.FINE:
		var q := Grid.quad_of(local)
		var r := Grid.quad_rect(q)
		cursor.show_rect(r)
		_show_preview(r)
	else: # Cell or Erase -> the whole cell
		var r := Grid.cell_rect(cell)
		cursor.show_rect(r)
		_show_preview(r)

# arm the lifted drop-preview over `rect` when a real material is armed in a placement mode; Erase
# (removal) and the grass eraser show only the square cursor, no floating tile.
func _show_preview(rect: Rect2) -> void:
	# the floor-colour and pattern tools re-texture/tint an existing floor, so they show only the
	# square cursor, no lifted tile (there is nothing being dropped). Same for Erase, the grass eraser,
	# and an un-armed Cell/Fine (no material picked yet).
	if EditorState.mode == EditorState.Mode.ERASE or EditorState.tool_kind == EditorState.Brush.FLOOR_COLOR or EditorState.tool_kind == EditorState.Brush.PATTERN or not EditorState.armed or not FloorMaterials.TEXTURES.has(EditorState.brush):
		preview.hide_preview()
		return
	preview.arm(FloorMaterials.texture(EditorState.brush, 0), EditorState.floor_color)
	preview.show_at(rect)

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
	cursor.hide_cursor()
	restore_faded()
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
	cursor.hide_cursor()
	_clear_room_hover()
	restore_faded()
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
func paint(local: Vector2, drop := false) -> void:
	var cell := Grid.cell_of(local)
	# Wall mode drag: draw a wall line (routed here via the shared _painting drag path)
	if EditorState.mode == EditorState.Mode.WALL:
		place_wall_at(local)
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
	if not in_bounds(cell):
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
		changed = write_quad(q, mat)
		changed = write_tint(q, tint) or changed
	else: # Cell or Erase -> the whole cell
		for q in Grid.quads_of(cell):
			changed = write_quad(q, mat) or changed
			changed = write_tint(q, tint) or changed
	if changed:
		rebuild()
		if drop and mat != "" and FloorMaterials.TEXTURES.has(mat):
			preview.play_drop(rect) # falling-tile effect for this placement

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
	if _write_quads(_stroke_scope(local), func(q: Vector2i) -> bool: return write_tint(q, EditorState.floor_color)):
		rebuild()

func _paint_floor_pattern(local: Vector2) -> void:
	if _write_quads(_stroke_scope(local), func(q: Vector2i) -> bool: return write_pattern(q, EditorState.pattern)):
		rebuild()

# set one quarter's tint (Natural/white erases the entry, so the floor reads its plain material).
# Returns whether anything changed, so a drag inside one quarter doesn't trigger a redundant rebuild.
func write_tint(q: Vector2i, color: Color) -> bool:
	if color == Color.WHITE:
		if not _quad_tint.has(q):
			return false
		_quad_tint.erase(q)
		return true
	if _quad_tint.get(q) == color:
		return false
	_quad_tint[q] = color
	return true

# --- floor scopes: tint and pattern each have ONE quarter writer (write_tint / write_pattern) applied
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
	return [] if cells.is_empty() else room_quads(cells).keys()

# what a right-click menu action targets at the current grain: the floor selection, else Wand -> the
# clicked room, Fine -> the clicked quarter, Cell/Erase -> the clicked cell
func _menu_scope(at: Vector2) -> Array:
	if EditorState.sel_kind == EditorState.SelKind.FLOOR and selection.overlay.has_selection():
		return EditorState.sel_quads.keys()
	if EditorState.mode == EditorState.Mode.WAND:
		return _room_scope(Grid.cell_of(at))
	if EditorState.mode == EditorState.Mode.FINE:
		return [Grid.quad_of(at)]
	return Grid.quads_of(Grid.cell_of(at))

# what a drag stroke at `local` covers: Fine -> the quarter, else the cell (nothing off the map)
func _stroke_scope(local: Vector2) -> Array:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
		return []
	return [Grid.quad_of(local)] if EditorState.mode == EditorState.Mode.FINE else Grid.quads_of(cell)

# named scopes the capture harness and tests drive directly
func tint_cell(cell: Vector2i, color: Color) -> bool:
	return _write_quads(Grid.quads_of(cell), func(q: Vector2i) -> bool: return write_tint(q, color))

func tint_room(cell: Vector2i, color: Color) -> bool:
	return _write_quads(_room_scope(cell), func(q: Vector2i) -> bool: return write_tint(q, color))

func pattern_cell(cell: Vector2i, idx: int) -> bool:
	return _write_quads(Grid.quads_of(cell), func(q: Vector2i) -> bool: return write_pattern(q, idx))

func pattern_room(cell: Vector2i, idx: int) -> bool:
	return _write_quads(_room_scope(cell), func(q: Vector2i) -> bool: return write_pattern(q, idx))

# Erase mode: remove the wall or door on the clicked cell (the structure layer, topmost after any
# object). Rebuilds the level through the same MapIO path load/resize use, so lighting, floors and
# shadows recompute consistently after a wall opens a room up. Returns true if a structure was
# removed, so the caller leaves the terrain for a follow-up click and skips the paint drag. One
# click = one removal = one undo entry (ROADMAP "Erase mode").
func erase_structure_at(local: Vector2) -> bool:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
		return false
	if _obs == null:
		return false
	# topmost-first: a wall/door goes before a bridge (they never coexist, but keep the order explicit),
	# and both go before the floor beneath. remove_bridge is only tried when no wall/door was removed.
	if _obs.remove_structure(cell) == "" and not _obs.remove_bridge(cell):
		return false
	_rebuild_world(MapIO.REBUILD_STRUCTURES) # respawn walls/doors/bridges + lighting + shadows
	EditHistory.commit("erase")
	reset_highlight()
	call_deferred("_update_hover") # re-detect the hover now the structure is gone
	return true

# Wall mode: add a wall on the clicked/dragged cell. add_wall no-ops on a cell that already holds a
# structure, so a drag over existing walls (or a repeat within one cell) triggers no rebuild.
func place_wall_at(local: Vector2) -> void:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
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

# Door mode: add a door on the clicked cell, orienting it to the wall run it bridges (falling back to
# the R-toggled default in open space). A wall on the cell becomes a doorway. One click = one undo.
func place_door_at(local: Vector2) -> void:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
		return
	if _obs == null:
		return
	var orient: Grid.Orient = _obs.wall_run_orientation(cell)
	if orient == Grid.Orient.NONE:
		orient = EditorState.door_orient
	if not _obs.add_door(cell, orient):
		return
	_rebuild_world(MapIO.REBUILD_STRUCTURES)
	EditHistory.commit("door")

# BRIDGE tool: drop a crossable deck on the clicked cell, auto-oriented to the water run it spans.
# A horizontal river (water to the left/right) is crossed north-south, so the bridge is "vertical";
# a vertical river (water above/below) gets a "horizontal" bridge. When the run is ambiguous (water on
# both axes, or none) fall back to EditorState.bridge_orient (R flips it), mirroring the door open-space default.
func place_bridge_at(local: Vector2) -> void:
	var cell := Grid.cell_of(local)
	if not in_bounds(cell):
		return
	if _obs == null:
		return
	if cell_liquid(cell) == "lava":
		return # wooden bridges burn: they can only be built over WATER, not lava
	var orient := bridge_river_orientation(cell)
	if orient == Grid.Orient.NONE:
		orient = EditorState.bridge_orient
	if not _obs.add_bridge(cell, orient):
		return
	_rebuild_world(MapIO.REBUILD_STRUCTURES)
	EditHistory.commit("bridge")

# the majority liquid material at `cell` ("water"/"lava"/""), using the same >=2-of-4-quarters rule as
# is_cell_impassable. Lets bridges tell water (crossable) from lava (never bridgeable).
func cell_liquid(cell: Vector2i) -> String:
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
func bridge_river_orientation(cell: Vector2i) -> Grid.Orient:
	var horiz_river := cell_liquid(cell + Vector2i(1, 0)) == "water" or cell_liquid(cell + Vector2i(-1, 0)) == "water"
	var vert_river := cell_liquid(cell + Vector2i(0, 1)) == "water" or cell_liquid(cell + Vector2i(0, -1)) == "water"
	if horiz_river and not vert_river:
		return Grid.Orient.VERTICAL
	if vert_river and not horiz_river:
		return Grid.Orient.HORIZONTAL
	return Grid.Orient.NONE

# Select tool: load the door or wall on the clicked cell into the properties inspector (a door wins
# if somehow both are present, matching the topmost-structure model). An empty cell clears it.
func select_at(local: Vector2) -> void:
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
	restore_faded()
	MapIO.rebuild_live(parts)
	call_deferred("_update_hover")

# --- right-click menu actions (ContextMenu decodes the item; these do the edit at World point `at`) ---

# apply `color` as the floor tint to the menu target at the current grain (see _menu_scope), redrawing
# if anything changed. The colour picker calls this live on every drag; returns whether it changed.
func tint_target(color: Color, at: Vector2) -> bool:
	var changed := _write_quads(_menu_scope(at), func(q: Vector2i) -> bool: return write_tint(q, color))
	if changed:
		rebuild()
	return changed

# a floor colour swatch: arm it as the colour brush (a left-drag keeps tinting) and tint the target
func apply_floor_color(color: Color, at: Vector2) -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR_COLOR
	EditorState.floor_color = color
	EditorState.brush_changed.emit()
	if tint_target(color, at):
		EditHistory.commit("floor colour") # one menu tint = one undo step
	reset_highlight()

# a floor pattern: arm it (a left-drag keeps applying it) and re-pattern the target
func apply_floor_pattern(idx: int, at: Vector2) -> void:
	EditorState.tool_kind = EditorState.Brush.PATTERN
	EditorState.pattern = idx
	if _write_quads(_menu_scope(at), func(q: Vector2i) -> bool: return write_pattern(q, idx)):
		rebuild()
		EditHistory.commit("floor pattern")
	reset_highlight()

# a floor material: fill the active floor selection if one exists; otherwise, in Wand mode fill the
# clicked room. In Cell/Fine, picking a terrain does not auto-place: it arms the brush and the user
# clicks the target to drop it (ROADMAP "Terrain placement UX").
func apply_floor_material(mat: String, at: Vector2) -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.brush = mat
	EditorState.armed = true # a material was explicitly chosen: Cell/Fine may now drop it
	EditorState.brush_changed.emit()
	if EditorState.sel_kind == EditorState.SelKind.FLOOR and selection.overlay.has_selection():
		var drop_rects := selection_drop_rects() # capture the shape before the highlight resets
		_fill_floor_selection(mat)
		EditHistory.commit("paint")
		if mat != "" and FloorMaterials.TEXTURES.has(mat):
			preview.play_shape_drop(drop_rects, FloorMaterials.texture(mat, 0)) # the whole shape drops in
		reset_highlight()
	elif EditorState.mode == EditorState.Mode.WAND:
		set_room_style(Grid.cell_of(at), mat) # convenience room fill; may no-op outside a room
		EditHistory.commit("paint")
		reset_highlight()
	else:
		# arm only: nothing changed yet (no undo entry). Refresh the hover so the lifted drop-preview of
		# the freshly-armed material appears over the cursor immediately.
		call_deferred("_update_hover")

# a wall colour / material: fill the active wall selection if one exists, otherwise the wall under the
# click (the whole building in Wand mode, a single segment in Cell/Fine). Armed either way, so a
# left-drag keeps applying it. A door is not a wall (it keeps its own look), so on a door this no-ops.
func apply_wall_color(color: Color, at: Vector2) -> void:
	EditorState.tool_kind = EditorState.Brush.WALL_COLOR
	EditorState.wall_color = color
	_apply_to_walls(at, func(cells) -> void: _obs.color_cells(cells, color), "wall colour")

func apply_wall_material(mat: String, at: Vector2) -> void:
	EditorState.tool_kind = EditorState.Brush.WALL_MATERIAL
	EditorState.wall_mat = mat
	_apply_to_walls(at, func(cells) -> void: _obs.material_cells(cells, mat), "wall material")

func _apply_to_walls(at: Vector2, apply: Callable, label: String) -> void:
	var cell := Grid.cell_of(at)
	var cells = null
	if EditorState.sel_kind == EditorState.SelKind.WALL and selection.overlay.has_selection():
		cells = EditorState.sel_cells
	elif _obs != null and _obs.is_blocked(cell):
		cells = _obs.building_cells(cell) if EditorState.mode == EditorState.Mode.WAND else [cell]
	if cells != null and _obs != null:
		apply.call(cells)
		EditHistory.commit(label) # one menu apply = one undo step
	reset_highlight()

# the Door submenu's edits (they mirror the inspector's door controls), one undo entry each
func edit_door(cell: Vector2i, edit: DoorEdit) -> void:
	var d: Dictionary = _obs.door_at(cell) if _obs != null else {}
	if d.is_empty():
		return
	match edit:
		DoorEdit.FLIP:
			var flipped := Grid.flip(d["orientation"])
			_obs.set_door_orientation(cell, flipped)
			_rebuild_world(MapIO.REBUILD_STRUCTURES) # structural: respawn the gate
			EditHistory.commit("door orientation")
		DoorEdit.TOGGLE_OPEN:
			_obs.set_door_open(cell, not bool(d.get("open", false)))
			EditHistory.commit("door open")
		DoorEdit.TOGGLE_SWING:
			_obs.set_door_swing(cell, not bool(d.get("swing", false)))
			EditHistory.commit("door swing")

# --- right-click menu / Delete key: Erase ---
# Erase acts on the current selection when there is one, else on the clicked target. Delete (see
# _unhandled_key_input) is the selection-only entry point. See ROADMAP "Editor UX revisions" -> Erase.
func erase_target(cell: Vector2i) -> void:
	if selection.overlay.has_selection():
		_erase_selection()
	else:
		erase_single(cell)

# erase the whole active selection: floor quarters back to grass (clearing material/pattern/tint), or
# every wall in a wall selection. One undo entry; the selection is cleared afterwards.
func _erase_selection() -> void:
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		for q in EditorState.sel_quads:
			_quad_mat.erase(q)
			_quad_pattern.erase(q)
			_quad_tint.erase(q)
		rebuild()
		EditHistory.commit("erase")
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		# one warning for the whole selection if any door in it has a Unique key bound to it
		if warn_bound_keys(EditorState.sel_cells.keys(), _erase_wall_selection):
			return
		_erase_wall_selection()
	selection.clear()
	reset_highlight()
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
func warn_bound_keys(cells: Array, on_yes: Callable) -> bool:
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
func delete_structure_with_keys(cell: Vector2i) -> void:
	if _obs == null:
		return
	var id: String = _obs.door_id_at(cell)
	_obs.remove_structure(cell)
	if _pickups != null and id != "":
		for k in _pickups.keys_for_door(id):
			_pickups.remove_pickup(k["cell"])
	_rebuild_world(MapIO.REBUILD_STRUCTURES | MapIO.REBUILD_OBJECTS)
	EditHistory.commit("erase")
	reset_highlight()
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
	selection.clear()
	reset_highlight()
	call_deferred("_update_hover")

# erase the single clicked target: remove a wall/door if one is there, else clear the cell's ground.
func erase_single(cell: Vector2i) -> void:
	if _obs != null and _obs.has_structure(cell):
		# a door with a Unique key bound to it warns before taking the key with it
		if warn_bound_keys([cell], delete_structure_with_keys.bind(cell)):
			return
		delete_structure_with_keys(cell)
		return
	# a placed item sits on top of the ground: erase it before the terrain beneath it
	if _pickups != null and _pickups.has_pickup(cell):
		_pickups.remove_pickup(cell)
		_rebuild_world(MapIO.REBUILD_OBJECTS)
		EditHistory.commit("erase")
		reset_highlight()
		call_deferred("_update_hover")
		return
	# a placed creature shares that object layer, so it erases at the same depth as an item
	if _creatures != null and _creatures.has_creature(cell):
		_creatures.remove_creature(cell)
		_rebuild_world(MapIO.REBUILD_OBJECTS)
		EditHistory.commit("erase")
		reset_highlight()
		call_deferred("_update_hover")
		return
	# a bridge is the next layer down (over the water floor): erase it before the ground beneath
	if _obs != null and _obs.is_bridge(cell):
		_obs.remove_bridge(cell)
		_rebuild_world(MapIO.REBUILD_STRUCTURES)
		EditHistory.commit("erase")
		reset_highlight()
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
		rebuild()
		EditHistory.commit("erase")
		reset_highlight()
		return
	# A ZONE is the LAST thing erase can mean: it is a rule about the region, sitting under every
	# object, structure and terrain in it, so it only goes once there is nothing else on the cell to
	# take. Otherwise erasing a creature standing in a zone would delete the zone out from under it.
	if _creatures != null and _creatures.remove_zone_at(cell):
		_rebuild_world(MapIO.REBUILD_OBJECTS)
		EditHistory.commit("erase")
	reset_highlight()

# Wall/Door placement hover: a plain green cell cursor over any in-bounds cell showing where the next
# wall or door lands. No drop-preview sprite yet (walls/doors have no lifted tile art), just the cell.
func _update_structure_placement_hover(cell: Vector2i) -> void:
	_clear_room_hover()
	restore_faded()
	preview.hide_preview()
	if not in_bounds(cell):
		cursor.hide_cursor()
		ghosts.hide_all()
		return
	cursor.set_role(PaintCursor.Role.ADD) # green: placing a wall/door is additive
	cursor.show_rect(Grid.cell_rect(cell))
	# Also float the REAL thing a click would place, like the bridge deck preview. WALL: the wall shape
	# (horizontal/vertical/corner/T/cross) in the armed colour+material, over an empty cell. DOOR: the
	# closed door, auto-oriented to the wall run it would bridge.
	if EditorState.mode == EditorState.Mode.WALL and _obs != null and not _obs.is_blocked(cell):
		ghosts.show_wall(cell)
		ghosts.hide_door()
	elif EditorState.mode == EditorState.Mode.DOOR and _obs != null:
		ghosts.hide_wall()
		ghosts.show_door(cell)
	else:
		ghosts.hide_wall()
		ghosts.hide_door()

# Bridge placement hover: a green ADD cell cursor (like wall/door) PLUS the real deck art lifted a few
# px above the cell, oriented to the water run the click would span (or the R-flippable default). Shows
# the bridge that will land instead of the last floor material's drop-preview.
func _update_bridge_hover(cell: Vector2i) -> void:
	_clear_room_hover()
	restore_faded()
	preview.hide_preview() # never show the leftover floor-material drop-preview in BRIDGE mode
	if not in_bounds(cell):
		cursor.hide_cursor()
		ghosts.hide_bridge()
		return
	# lava can't be bridged (wooden bridges burn): mark it invalid (red cursor, no deck preview)
	if cell_liquid(cell) == "lava":
		cursor.set_role(PaintCursor.Role.ERASE)
		cursor.show_rect(Grid.cell_rect(cell))
		ghosts.hide_bridge()
		return
	cursor.set_role(PaintCursor.Role.ADD)
	cursor.show_rect(Grid.cell_rect(cell))
	var orient := bridge_river_orientation(cell)
	if orient == Grid.Orient.NONE:
		orient = EditorState.bridge_orient
	ghosts.show_bridge(cell, orient)

# set one quarter's material ("" erases it back to grass). Returns whether anything changed,
# so a drag that stays inside the same quarter doesn't trigger a redundant rebuild.
func write_quad(q: Vector2i, mat: String) -> bool:
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
func fade_obstacles_at(cell: Vector2i) -> void:
	if cell == _faded_cell:
		return # already dimmed for this cell
	restore_faded()
	_faded_cell = cell
	# skip nodes already queued for deletion: an Erase rebuild frees the old wall/gate nodes but
	# they linger in their group for the rest of the frame, and fading one would leave a freed
	# reference in _faded that restore_faded would later touch (use-after-free).
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
func restore_faded() -> void:
	for e in _faded:
		if is_instance_valid(e[0]):
			e[0].modulate = e[1]
	_faded.clear()
	_faded_cell = Grid.INVALID_CELL

# does `cell` exist on the map (inside the grid AND not a hole)? Every tool and the floor render treat a
# hole exactly like off-map: nothing is painted, placed, stamped or banked into one. Walls don't stop a
# paint: the ground under a wall/door is editable (the obstacle fades while you paint, fade_obstacles_at).
func in_bounds(cell: Vector2i) -> bool:
	return _grid_bg == null or _grid_bg.cell_present(cell.x, cell.y)

# give the room containing `cell` a floor style ("" resets it to grass). A room fill is a
# convenience over the quarter store: it writes all four quarters of every cell in the room.
func set_room_style(cell: Vector2i, style: String) -> void:
	var cells: Dictionary = room_light.room_floor_cells(cell)
	if cells.is_empty():
		return
	_write_room(cells, style)
	rebuild()

# fill a whole room with `style` ("" erases it to grass): every interior floor quarter AND the
# room-facing wall/door ring quarters, so the floor genuinely reaches under the walls and stays
# there as real data. Cell/Quarter painting deliberately never touches the ring, so laying a tile
# does not change the ground already stored under the walls.
func _write_room(cells: Dictionary, style: String) -> void:
	for q in room_quads(cells):
		write_quad(q, style)

# replace all floors from a v1 per-room style list (used by the MapIO v1->v2 load migration).
# Must run AFTER RoomLight has rebuilt, since the room a style fills is found by flood fill.
func apply_floors(list: Array) -> void:
	_quad_mat.clear()
	for f in list:
		var style: String = f["style"]
		if style == "" or not FloorMaterials.TEXTURES.has(style):
			continue
		_write_room(room_light.room_floor_cells(f["cell"]), style)
	rebuild()

# replace all floors from a v2 quarter list [[qx, qy, material], ...] (used by MapIO on load).
func apply_quads(list: Array) -> void:
	_quad_mat.clear()
	_quad_no_bank.clear() # repopulated by apply_no_bank (MapIO calls it before the final rebuild)
	for a in list:
		var mat: String = a[2]
		if not FloorMaterials.TEXTURES.has(mat):
			continue
		_quad_mat[Vector2i(int(a[0]), int(a[1]))] = mat
	rebuild()

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
func write_pattern(q: Vector2i, idx: int) -> bool:
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
	rebuild()

# the floor stores changed: mark the render derivation stale and queue the redraw. The fills themselves are
# built lazily on the next read (grid_background's _draw), so a paint drag that writes many quarters in one
# frame, or a load that sets materials, patterns and tints back to back, derives them once, not per write.
func rebuild() -> void:
	_fills_dirty = true
	_redraw_floor_layers()

func _ensure_fills() -> void:
	if _fills_dirty:
		_fills_dirty = false
		_base_fills = render.build()

func _redraw_floor_layers() -> void:
	if _grid_bg:
		_grid_bg.queue_redraw()
	if _shadows:
		_shadows.refresh()

# --- read by grid_background and shadow_manager ---

func base_fills() -> Array:
	_ensure_fills()
	return _base_fills

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
	if not in_bounds(cell) or (_obs != null and _obs.is_blocked(cell)):
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
