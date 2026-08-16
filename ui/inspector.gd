extends CanvasLayer

# The properties inspector: a right-side panel that shows the selected object's authored settings and
# edits them live. Populated by the Select tool (FloorManager Mode.SELECT) via inspect_door /
# inspect_wall; clear() empties it. It holds the selected CELL (not a node), so a structural rebuild
# (e.g. flipping a door's orientation) can't leave it pointing at a freed node: it just re-reads.
#
# Editor-only chrome: hidden in PLAY and whenever nothing is selected. Each edit commits one undo
# entry. Doors expose the new authored open/swing/orientation; walls expose colour (the same palette
# as the right-click menu). More object types (spawns, objects) slot in as the roster grows.

# wall colour palette, mirrored from floor_manager.WALL_COLORS (kept in sync by hand; small list)
const WALL_COLORS := [
	["Natural", Color.WHITE], ["Red", Color(0.85, 0.3, 0.28)], ["Green", Color(0.42, 0.72, 0.42)],
	["Blue", Color(0.4, 0.55, 0.85)], ["Yellow", Color(0.9, 0.82, 0.35)],
	["Orange", Color(0.9, 0.58, 0.3)], ["Purple", Color(0.66, 0.45, 0.8)],
]

var _kind := ""            # "", "door" or "wall"
var _cell := Vector2i.ZERO
var _panel: PanelContainer
var _box: VBoxContainer

func _ready() -> void:
	layer = 9 # below the mode toggle (10), above the world
	add_to_group("inspector") # so FloorManager's Select tool can find us
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_right = -8
	_panel.offset_top = 44 # clear the Play/Edit button above
	_panel.offset_left = -212
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_panel.add_child(_box)
	EditorMode.changed.connect(func(_m): _refresh_visibility())
	clear()

# --- selection entry points (called by the Select tool) ---

func inspect_door(cell: Vector2i) -> void:
	_kind = "door"
	_cell = cell
	_rebuild()

func inspect_wall(cell: Vector2i) -> void:
	_kind = "wall"
	_cell = cell
	_rebuild()

func clear() -> void:
	_kind = ""
	_rebuild()

# --- panel construction ---

func _obs():
	return get_tree().get_first_node_in_group("obstacles")

func _refresh_visibility() -> void:
	# shown only in EDIT and only with a live selection
	_panel.visible = EditorMode.is_edit() and _kind != ""

func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	if _kind == "door":
		_build_door()
	elif _kind == "wall":
		_build_wall()
	_refresh_visibility()

func _title(text: String) -> void:
	var l := Label.new()
	l.text = text
	_box.add_child(l)

func _build_door() -> void:
	var obs = _obs()
	var d: Dictionary = obs.door_at(_cell) if obs else {}
	if d.is_empty():
		clear()
		return
	_title("Door  (%d, %d)" % [_cell.x, _cell.y])

	# orientation flip (structural: rebuild through MapIO so the gate respawns)
	var orient: String = d["orientation"]
	var ob := Button.new()
	ob.text = "Orientation: %s" % orient.capitalize()
	ob.pressed.connect(func():
		var flipped := "vertical" if orient == "horizontal" else "horizontal"
		obs.set_door_orientation(_cell, flipped)
		MapIO.apply_serialized(MapIO.serialize(), true)
		EditHistory.commit("door orientation")
		inspect_door(_cell)) # re-read the rebuilt door
	_box.add_child(ob)

	# open default
	var open_btn := CheckButton.new()
	open_btn.text = "Open by default"
	open_btn.button_pressed = bool(d.get("open", false))
	open_btn.toggled.connect(func(on):
		obs.set_door_open(_cell, on)
		EditHistory.commit("door open"))
	_box.add_child(open_btn)

	# swing side (only visibly affects an open door)
	var swing_btn := CheckButton.new()
	swing_btn.text = "Swing (alt side)"
	swing_btn.button_pressed = bool(d.get("swing", false))
	swing_btn.toggled.connect(func(on):
		obs.set_door_swing(_cell, on)
		EditHistory.commit("door swing"))
	_box.add_child(swing_btn)

func _build_wall() -> void:
	var obs = _obs()
	if obs == null or not obs.is_blocked(_cell):
		clear()
		return
	_title("Wall  (%d, %d)" % [_cell.x, _cell.y])
	var current: Color = obs.get_wall_color(_cell)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for entry in WALL_COLORS:
		var name: String = entry[0]
		var col: Color = entry[1]
		var b := Button.new()
		b.text = name.substr(0, 1) # compact swatch label; tooltip carries the full name
		b.tooltip_text = name
		b.custom_minimum_size = Vector2(22, 0)
		if col.is_equal_approx(current):
			b.disabled = true # already the current colour
		b.pressed.connect(func():
			obs.set_wall_color(_cell, col)
			EditHistory.commit("wall colour")
			inspect_wall(_cell)) # refresh which swatch is current
		row.add_child(b)
	_box.add_child(row)
