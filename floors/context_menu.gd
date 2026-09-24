class_name ContextMenu
extends Node

# The contextual right-click menu: what it offers depends on what was clicked (a door, a wall, or
# ground), it decodes the picked item, and hands the edit to FloorManager's public actions with the
# clicked point. It holds no map logic of its own. Also owns the "Custom..." floor-colour picker, which
# previews the tint live on the clicked target and commits one undo entry when it closes.
#
# ONE submenu per target, not one per axis (merged 2026-09-05): the STYLE of the clicked thing is one
# submenu ("Floor", "Wall", "Door"), grouped by separator headings; BUILDING moved to the Place tool,
# which drops walls/doors/bridges/items/spawns and can drag a wall line. What is left is what a context
# menu is for: act on the thing under the cursor. See ROADMAP "Optimise the right menu".

# item ids. Single actions sit below 300; swatch ranges are BASE + index, matched highest-first
const GRID_ID := 100             # the reference grid toggle
const ERASE_ID := 101            # erase the selection if one exists, else the clicked target
const DOOR_FLIP_ID := 104        # flip a door's orientation
const DOOR_OPEN_ID := 105        # toggle a door's open-by-default
const DOOR_SWING_ID := 106       # toggle a door's swing side
const WALL_BASE_ID := 300        # + index into WallSegment.COLORS
const FLOOR_COLOR_BASE_ID := 400 # + index into FloorMaterials.COLORS
const FLOOR_PICKER_ID := 500     # "Custom..." opens the colour picker
const WALL_MAT_BASE_ID := 600    # + index into WallSegment.MATERIAL_NAMES
const PATTERN_BASE_ID := 700     # + pattern index of the clicked quarter's material
# ids below 300 that are not actions are floor materials: an index into FloorMaterials.MATERIAL_NAMES

var target := Vector2.ZERO # World-local point of the right-click the menu acts on
var popup: PopupMenu
var _fm: FloorManager
var _obs: Obstacles
var _picker_popup: PopupPanel
var _color_picker: ColorPicker
var _picker_applied := false  # a preview was applied during the current picker session (commit on close)
var _suppress_picker := false # guard so setting the picker's start colour doesn't count as an edit

func setup(fm: FloorManager, obs: Obstacles) -> void:
	_fm = fm
	_obs = obs
	popup = PopupMenu.new()
	# the section submenus are children of the popup; the TOP-LEVEL items are rebuilt per right-click in
	# apply_context so only the section for the clicked target shows (PopupMenu has no set_item_hidden)
	for sub_name in ["floor_sub", "wall_sub", "door_sub"]:
		var sub := PopupMenu.new()
		sub.name = sub_name
		sub.id_pressed.connect(on_id)
		popup.add_child(sub)
	popup.id_pressed.connect(on_id)
	add_child(popup)
	_picker_popup = PopupPanel.new()
	_color_picker = ColorPicker.new()
	_color_picker.edit_alpha = false # tints are opaque multiplies; alpha would just dim confusingly
	_color_picker.custom_minimum_size = Vector2(280, 0)
	_picker_popup.add_child(_color_picker)
	_color_picker.color_changed.connect(_on_picker_changed)
	_picker_popup.popup_hide.connect(_on_picker_closed)
	add_child(_picker_popup)

func is_open() -> bool:
	return popup.visible

# open the menu for the World-local point `local`, at the mouse
func open_at(local: Vector2) -> void:
	target = local
	apply_context(Grid.cell_of(local))
	popup.position = Vector2i(get_viewport().get_mouse_position())
	popup.reset_size() # re-fit after the rebuild so the popup isn't sized for a stale menu
	popup.popup()

# rebuild the top level for what is on `cell`: Door or Wall (the structure there), then Floor, which
# shows on EVERY cell because the ground under a wall/door is editable too, then Erase and Grid
func apply_context(cell: Vector2i) -> void:
	var is_door: bool = _obs != null and not _obs.door_at(cell).is_empty()
	var is_wall: bool = _obs != null and _obs.is_blocked(cell) # a real wall (doors are not blocked)
	popup.clear()
	if is_door:
		_rebuild_door_sub(cell)
		popup.add_submenu_item("Door", "door_sub")
	elif is_wall:
		_rebuild_wall_sub()
		popup.add_submenu_item("Wall", "wall_sub")
	_rebuild_floor_sub()
	popup.add_submenu_item("Floor", "floor_sub")
	popup.add_item("Erase", ERASE_ID)
	# right-click entries carry tooltips too (ROADMAP "Tooltips on menu and tool options"), composed
	# from the one hotkey table
	popup.set_item_tooltip(popup.get_item_index(ERASE_ID),
		Hotkeys.tip("erase", "Acts on the selection if there is one, else the clicked target."))
	popup.add_separator()
	popup.add_check_item("Grid", GRID_ID)
	popup.set_item_checked(popup.get_item_index(GRID_ID), EditorState.grid_on)
	popup.set_item_tooltip(popup.get_item_index(GRID_ID), "Show the reference grid over the map")

# texture, colour and pattern for the clicked ground. Rebuilt per right-click because the PATTERN
# entries depend on what the clicked quarter is made of (why patterns stayed in the contextual menu)
func _rebuild_floor_sub() -> void:
	var sub: PopupMenu = popup.get_node("floor_sub")
	sub.clear()
	sub.add_separator("Texture")
	for i in FloorMaterials.MATERIAL_NAMES.size():
		sub.add_item(FloorMaterials.MATERIAL_NAMES[i][0], i)
	sub.add_separator("Colour")
	for i in FloorMaterials.COLORS.size():
		sub.add_item(FloorMaterials.COLORS[i][0], FLOOR_COLOR_BASE_ID + i)
	sub.add_item("Custom...", FLOOR_PICKER_ID)
	var mat: String = _fm.quad_materials().get(Grid.quad_of(target), "")
	var variants: int = FloorMaterials.TEXTURES[mat].size() if FloorMaterials.TEXTURES.has(mat) else 0
	if variants > 1:
		sub.add_separator("Pattern")
		var names: Array = FloorMaterials.PATTERN_NAMES.get(mat, [])
		for i in variants:
			sub.add_item(names[i] if i < names.size() else "Pattern %d" % (i + 1), PATTERN_BASE_ID + i)

func _rebuild_wall_sub() -> void:
	var sub: PopupMenu = popup.get_node("wall_sub")
	sub.clear()
	sub.add_separator("Colour")
	for i in WallSegment.COLORS.size():
		sub.add_item(WallSegment.COLORS[i][0], WALL_BASE_ID + i)
	sub.add_separator("Material")
	for i in WallSegment.MATERIAL_NAMES.size():
		sub.add_item(WallSegment.MATERIAL_NAMES[i][0], WALL_MAT_BASE_ID + i)

# the Door submenu reflects the door's state (check items, like the inspector)
func _rebuild_door_sub(cell: Vector2i) -> void:
	var d: Dictionary = _obs.door_at(cell) if _obs != null else {}
	var ds: PopupMenu = popup.get_node("door_sub")
	ds.clear()
	ds.add_item("Flip Orientation", DOOR_FLIP_ID)
	ds.add_check_item("Open by default", DOOR_OPEN_ID)
	ds.set_item_checked(ds.get_item_index(DOOR_OPEN_ID), bool(d.get("open", false)))
	ds.add_check_item("Swing (alt side)", DOOR_SWING_ID)
	ds.set_item_checked(ds.get_item_index(DOOR_SWING_ID), bool(d.get("swing", false)))

# decode a picked item into the FloorManager action it stands for, applied at `target`
func on_id(id: int) -> void:
	var cell := Grid.cell_of(target)
	match id:
		GRID_ID:
			_fm.set_grid(not EditorState.grid_on)
		ERASE_ID:
			_fm.erase_target(cell)
		DOOR_FLIP_ID:
			_fm.edit_door(cell, FloorManager.DoorEdit.FLIP)
		DOOR_OPEN_ID:
			_fm.edit_door(cell, FloorManager.DoorEdit.TOGGLE_OPEN)
		DOOR_SWING_ID:
			_fm.edit_door(cell, FloorManager.DoorEdit.TOGGLE_SWING)
		FLOOR_PICKER_ID:
			_open_picker()
		_:
			if id >= PATTERN_BASE_ID:
				_fm.apply_floor_pattern(id - PATTERN_BASE_ID, target)
			elif id >= WALL_MAT_BASE_ID:
				_fm.apply_wall_material(WallSegment.MATERIAL_NAMES[id - WALL_MAT_BASE_ID][1], target)
			elif id >= FLOOR_COLOR_BASE_ID:
				_fm.apply_floor_color(FloorMaterials.COLORS[id - FLOOR_COLOR_BASE_ID][1], target)
			elif id >= WALL_BASE_ID:
				_fm.apply_wall_color(WallSegment.COLORS[id - WALL_BASE_ID][1], target)
			else:
				_fm.apply_floor_material(FloorMaterials.MATERIAL_NAMES[id][1], target)

# --- the "Custom..." floor-colour picker ---

# open the picker seeded from the current tint (or a default), previewing live on the target
func _open_picker() -> void:
	EditorState.tool_kind = EditorState.Brush.FLOOR_COLOR
	_picker_applied = false
	_suppress_picker = true # setting .color must not count as a user edit
	_color_picker.color = EditorState.floor_color if EditorState.floor_color != Color.WHITE else Color(0.85, 0.3, 0.28)
	_suppress_picker = false
	_picker_popup.popup_centered()

# live preview: each drag in the picker re-tints the target with the new colour
func _on_picker_changed(c: Color) -> void:
	if _suppress_picker:
		return
	EditorState.floor_color = c
	if _fm.tint_target(c, target):
		_picker_applied = true

# picker closed: the whole session commits as ONE undo entry (or nothing if never previewed)
func _on_picker_closed() -> void:
	if _picker_applied:
		EditHistory.commit("floor colour")
		_picker_applied = false
	_fm.reset_highlight()
