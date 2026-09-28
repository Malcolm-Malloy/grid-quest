class_name Inspector
extends CanvasLayer

# The properties inspector: a right-side panel that shows the selected object's authored settings and
# edits them live. Populated by the Select tool (FloorManager Mode.SELECT) via inspect_door /
# inspect_wall; clear() empties it. It holds the selected CELL (not a node), so a structural rebuild
# (e.g. flipping a door's orientation) can't leave it pointing at a freed node: it just re-reads.
#
# Editor-only chrome: hidden in PLAY and whenever nothing is selected. Each edit commits one undo
# entry. Doors expose the new authored open/swing/orientation; walls expose colour (the same palette
# as the right-click menu). More object types (spawns, objects) slot in as the roster grows.


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

func inspect_creature(cell: Vector2i) -> void:
	_kind = "creature"
	_cell = cell
	_rebuild()

func inspect_zone(cell: Vector2i) -> void:
	_kind = "zone"
	_cell = cell
	_rebuild()

func clear() -> void:
	_kind = ""
	_rebuild()

# --- panel construction ---

func _obs() -> Obstacles:
	return get_tree().get_first_node_in_group("obstacles")

# the Unique keys already placed for the inspected door, so the button can say so
func _keys_bound_here() -> Array:
	var obs := _obs()
	var pk: Pickups = obs.get_parent().get_node_or_null("Pickups") if obs else null
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
	elif _kind == "creature":
		_build_creature()
	elif _kind == "zone":
		_build_zone()
	_refresh_visibility()

func _title(text: String) -> void:
	var l := Label.new()
	l.text = text
	_box.add_child(l)

# the placed-creature layer (world/creatures.gd), a sibling of Obstacles under World
func _creature_layer() -> Creatures:
	var obs := _obs()
	return obs.get_parent().get_node_or_null("Creatures") if obs else null

# A placed creature: its TYPE, which KIND of placement it is, and the per-object passability override
# (ROADMAP "Passability": a type default with a per-object override for level-specific exceptions).
# Retyping and re-kinding both keep the record's durable id, so this edits the creature that is here
# rather than replacing it with a new one.
func _build_creature() -> void:
	var cr := _creature_layer()
	var rec: Dictionary = cr.creature_at(_cell) if cr else {}
	if rec.is_empty():
		clear()
		return
	var creature := String(rec["creature"])
	_title("%s  (%d, %d)" % [Bestiary.display_name(creature), _cell.x, _cell.y])

	var rar := Label.new()
	rar.text = Bestiary.rarity_name(creature)
	rar.add_theme_color_override("font_color", Bestiary.rarity_color(creature))
	_box.add_child(rar)

	# placement kind
	_title("Placement")
	var kind := String(rec["kind"])
	var kind_row := HBoxContainer.new()
	for k in Bestiary.KINDS:
		var kb := Button.new()
		kb.text = Bestiary.kind_name(k)
		kb.flat = kind != k
		kb.pressed.connect(func():
			if cr.set_kind(_cell, k):
				_reapply()
				inspect_creature(_cell))
		kind_row.add_child(kb)
	_box.add_child(kind_row)

	# type: swap which creature stands here, keeping the cell, kind and id
	_title("Creature")
	var type_grid := GridContainer.new()
	type_grid.columns = 2
	for cid in Bestiary.ids():
		var tb := Button.new()
		tb.text = Bestiary.display_name(cid)
		tb.flat = cid != creature
		tb.add_theme_color_override("font_color", Bestiary.rarity_color(cid))
		tb.pressed.connect(func():
			if cr.set_type(_cell, cid):
				_reapply()
				inspect_creature(_cell))
		type_grid.add_child(tb)
	_box.add_child(type_grid)

	# the per-object passability override. Monsters block by default; this is the exception switch.
	var blocks := CheckButton.new()
	blocks.text = "Blocks movement"
	blocks.tooltip_text = "Monsters block by default. Turn off for a decorative or walk-through creature."
	blocks.button_pressed = bool(rec.get("blocks", true))
	blocks.toggled.connect(func(on: bool):
		if cr.set_blocks(_cell, on):
			_reapply())
	_box.add_child(blocks)

	var ability := Label.new()
	ability.text = Bestiary.ability(creature)
	ability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ability.custom_minimum_size.x = 190
	ability.add_theme_font_size_override("font_size", 11)
	ability.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	_box.add_child(ability)

	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func():
		if cr.remove_creature(_cell):
			_reapply()
			clear())
	_box.add_child(del)

# A spawn zone: the region rule. ROADMAP "Editor layout" called for exactly this -- "a spawn zone's
# type/rate/cap", and "complex ones (spawn zones) show more" than the couple of fields a simple object
# gets. Rate and cap are SPINBOXES rather than buttons because they are continuous quantities with a
# sensible range, not a small fixed roster like a creature type.
func _build_zone() -> void:
	var cr := _creature_layer()
	var rec: Dictionary = cr.zone_at(_cell) if cr else {}
	if rec.is_empty():
		clear()
		return
	var rect: Rect2i = rec["rect"]
	_title("Spawn Zone  (%d x %d)" % [rect.size.x, rect.size.y])

	_title("Spawns")
	var type_grid := GridContainer.new()
	type_grid.columns = 2
	for cid in Bestiary.ids():
		var tb := Button.new()
		tb.text = Bestiary.display_name(cid)
		tb.flat = cid != String(rec["creature"])
		tb.add_theme_color_override("font_color", Bestiary.rarity_color(cid))
		tb.pressed.connect(func():
			if cr.set_zone_type(_cell, cid):
				_reapply()
				inspect_zone(_cell))
		type_grid.add_child(tb)
	_box.add_child(type_grid)

	# cap: how many of them the zone keeps alive at once
	var cap_row := HBoxContainer.new()
	var cap_lbl := Label.new()
	cap_lbl.text = "Cap"
	cap_row.add_child(cap_lbl)
	var cap := SpinBox.new()
	cap.min_value = Bestiary.ZONE_CAP_RANGE.x
	cap.max_value = Bestiary.ZONE_CAP_RANGE.y
	cap.step = 1
	cap.value = int(rec["cap"])
	cap.tooltip_text = "How many live creatures this zone keeps in the area"
	cap.value_changed.connect(func(v: float):
		if cr.set_zone_cap(_cell, int(v)):
			_reapply())
	cap_row.add_child(cap)
	_box.add_child(cap_row)

	# rate: seconds between spawn attempts
	var rate_row := HBoxContainer.new()
	var rate_lbl := Label.new()
	rate_lbl.text = "Every"
	rate_row.add_child(rate_lbl)
	var rate := SpinBox.new()
	rate.min_value = Bestiary.ZONE_RATE_RANGE.x
	rate.max_value = Bestiary.ZONE_RATE_RANGE.y
	rate.step = 0.5
	rate.suffix = "s"
	rate.value = float(rec["rate"])
	rate.tooltip_text = "Seconds between spawn attempts while the zone is below its cap"
	rate.value_changed.connect(func(v: float):
		if cr.set_zone_rate(_cell, v):
			_reapply())
	rate_row.add_child(rate)
	_box.add_child(rate_row)

	var note := Label.new()
	note.text = "Spawns while playing. Roaming AI is not built yet."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 190
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	_box.add_child(note)

	var del := Button.new()
	del.text = "Delete Zone"
	del.pressed.connect(func():
		if cr.remove_zone_at(_cell):
			_reapply()
			clear())
	_box.add_child(del)

# respawn the object layer (the same build_world a load runs, so the nodes match) and record a single
# undo entry, the same contract every other inspector edit keeps
func _reapply() -> void:
	MapIO.rebuild_live(MapIO.REBUILD_OBJECTS)
	EditHistory.commit("creature")

func _build_door() -> void:
	var obs := _obs()
	var d: Dictionary = obs.door_at(_cell) if obs else {}
	if d.is_empty():
		clear()
		return
	_title("Door  (%d, %d)" % [_cell.x, _cell.y])

	# orientation flip (structural: rebuild through MapIO so the gate respawns)
	var orient: Grid.Orient = d["orientation"]
	var ob := Button.new()
	ob.text = "Orientation: %s" % Grid.orient_name(orient).capitalize()
	ob.pressed.connect(func():
		var flipped := Grid.flip(orient)
		obs.set_door_orientation(_cell, flipped)
		MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
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
			MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
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
				MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
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
			var fm := get_node_or_null("../World/FloorManager") as FloorManager
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
		MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
		EditHistory.commit("door to wall")
		inspect_wall(_cell))
	_box.add_child(to_wall)

func _build_wall() -> void:
	var obs := _obs()
	if obs == null or not obs.is_blocked(_cell):
		clear()
		return
	_title("Wall  (%d, %d)" % [_cell.x, _cell.y])
	var current: Color = obs.get_wall_color(_cell)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for entry in WallSegment.COLORS:
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
	for entry in WallSegment.MATERIAL_NAMES:
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
		MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
		EditHistory.commit("wall to door")
		inspect_door(_cell))
	_box.add_child(to_door)
