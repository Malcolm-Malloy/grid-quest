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

# wall material list, mirrored from floor_manager.WALL_MATERIALS (kept in sync by hand)
const WALL_MATERIALS := [["Stone", "stone"], ["Wood", "wood"], ["Slate", "slate"], ["Brick", "brick"], ["Hedge", "hedge"], ["Wood Fence", "wood_fence"], ["Metal Bars", "metal_bars"], ["Chainlink", "chainlink"]]

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

# the Unique keys already placed for the inspected door, so the button can say so
func _keys_bound_here() -> Array:
	var obs = _obs()
	var pk = obs.get_parent().get_node_or_null("Pickups") if obs else null
	return pk.keys_for_door(obs.door_id_at(_cell)) if pk else []

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

	# --- Lock (ROADMAP "Locked doors and keys"). Two types, and the authoring differs because the
	# types differ: a COLOURED lock only needs a colour (any key of that colour opens it, and is spent),
	# while a UNIQUE lock is bound to THIS door, so it also needs a name and an actual key placed
	# somewhere in the level -- hence the "Place its key" button, which arms the Item tool with a key
	# already bound to this door instead of making you hunt for a pick-the-door mode.
	var lock_kind := String(d.get("lock", ""))
	_title("Lock: %s" % ("None" if lock_kind == "" else lock_kind.capitalize()))
	var lock_row := HBoxContainer.new()
	for opt in [["None", ""], ["Coloured", "colour"], ["Unique", "unique"]]:
		var lb := Button.new()
		lb.text = opt[0]
		lb.flat = lock_kind != opt[1]
		lb.pressed.connect(func():
			obs.set_door_lock(_cell, opt[1], String(d.get("lock_color", "red")), String(d.get("lock_name", "")))
			MapIO.apply_serialized(MapIO.serialize(), true)
			EditHistory.commit("door lock")
			inspect_door(_cell))
		lock_row.add_child(lb)
	_box.add_child(lock_row)

	if lock_kind == "colour":
		# the lock colour: a key of the SAME colour opens it, matched by colour only
		var col_row := HBoxContainer.new()
		var current := String(d.get("lock_color", "red"))
		for cname in Items.lock_color_names():
			var cb := Button.new()
			cb.custom_minimum_size = Vector2(28, 22)
			cb.tooltip_text = "%s lock (opened by a %s Key)" % [String(cname).capitalize(), String(cname).capitalize()]
			var sb := StyleBoxFlat.new()
			sb.bg_color = Items.lock_color(cname)
			if cname == current:
				sb.border_width_bottom = 3
				sb.border_width_top = 3
				sb.border_width_left = 3
				sb.border_width_right = 3
				sb.border_color = Color.WHITE
			cb.add_theme_stylebox_override("normal", sb)
			cb.pressed.connect(func():
				obs.set_door_lock(_cell, "colour", cname, "")
				MapIO.apply_serialized(MapIO.serialize(), true)
				EditHistory.commit("lock colour")
				inspect_door(_cell))
			col_row.add_child(cb)
		_box.add_child(col_row)

	if lock_kind == "unique":
		# the key's player-facing name ("Malcolm's Door Key")
		var name_edit := LineEdit.new()
		name_edit.placeholder_text = "Key name"
		name_edit.text = String(d.get("lock_name", ""))
		name_edit.text_submitted.connect(func(t):
			obs.set_door_lock(_cell, "unique", "red", t)
			EditHistory.commit("key name"))
		_box.add_child(name_edit)
		var place := Button.new()
		var bound: int = _keys_bound_here().size()
		place.text = "Place its key" if bound == 0 else "Place another key (%d placed)" % bound
		place.pressed.connect(func():
			var fm = get_node_or_null("../World/FloorManager")
			if fm != null:
				fm.arm_bound_key(obs.door_id_at(_cell), name_edit.text))
		_box.add_child(place)

	# convert this door back into a solid wall, in place (structural: rebuild through MapIO). Re-inspects
	# as a wall so the panel stays on the same cell, now showing the wall's colour/material controls.
	var to_wall := Button.new()
	to_wall.text = "Convert to Wall"
	to_wall.pressed.connect(func():
		obs.remove_structure(_cell) # drop the door
		obs.add_wall(_cell)         # put a wall on the cell
		MapIO.apply_serialized(MapIO.serialize(), true)
		EditHistory.commit("door to wall")
		inspect_wall(_cell))
	_box.add_child(to_wall)

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

	# material row (Stone/Wood/Slate): the face/cap texture swap, independent of the colour tint above
	var current_mat: String = obs.get_wall_material(_cell)
	var mat_row := HBoxContainer.new()
	mat_row.add_theme_constant_override("separation", 2)
	for entry in WALL_MATERIALS:
		var mname: String = entry[0]
		var mat: String = entry[1]
		var mb := Button.new()
		mb.text = mname
		mb.tooltip_text = mname
		if mat == current_mat:
			mb.disabled = true # already the current material
		mb.pressed.connect(func():
			obs.set_wall_material(_cell, mat)
			EditHistory.commit("wall material")
			inspect_wall(_cell)) # refresh which material is current
		mat_row.add_child(mb)
	_box.add_child(mat_row)

	# convert this wall into a doorway, in place, following the wall run's orientation (structural:
	# rebuild through MapIO). Re-inspects as a door so the panel shows the door's open/swing controls.
	var to_door := Button.new()
	to_door.text = "Convert to Door"
	to_door.pressed.connect(func():
		obs.add_door(_cell, obs.wall_run_orientation(_cell))
		MapIO.apply_serialized(MapIO.serialize(), true)
		EditHistory.commit("wall to door")
		inspect_door(_cell))
	_box.add_child(to_door)
