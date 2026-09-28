class_name ToolStrip
extends CanvasLayer

# The persistent editor tool strip (left side). Laid out as collapsible ACCORDION sections (ROADMAP
# "Editor UX revisions" -> accordion left menu): a "Tools" section (the authoring-mode radio group,
# expanded by default) and an "Advanced" section (the Map Size edge controls, collapsed by default so
# the strip stays short for most users, per "remove Map Size from the menu -> Advanced"). Recenter sits
# below, always visible. Map Size grows/shrinks the map at each edge via MapEdit and previews the
# affected row/column on the GridBackground (green = will be added, red = will be removed) on hover.

const EDGES := ["top", "bottom", "left", "right"]

# only for its HEIGHT: the strip stops short of the status bar rather than overlapping it

# the authoring modes are FloorManager's own enum (no local mirror to keep in step)
const Mode := EditorState.Mode

# THE STRIP IS FOUR TOOLS (merged 2026-09-05, from twelve). The modes above did not go away -- they are
# what each tool switches between -- but a tool is now the thing you pick, and WHAT it acts with is a
# property you set in the panel below it, per ROADMAP "Optimise the right menu": "separate the axes ...
# a small persistent toolbar for the current action + mode, and a properties strip for style/colour".
#   Select  = click grows a selection, drag boxes one, and it inspects what you click (was Magic Wand
#             + Box Select + Select)
#   Paint   = lay terrain, at cell or quarter grain per the Fine switch (was Cell Selector + Fine Details)
#   Place   = drop a thing: wall, door, bridge, item or the player spawn (was five separate tools)
#   Move    = drag the current selection
# Erase and Eyedropper keep no button on purpose: Erase lives in the right-click menu + Delete + E, and
# the Eyedropper is Alt+click while painting (its whole point), + I.
const T_SELECT := 0
const T_PAINT := 1
const T_PLACE := 2
const T_MOVE := 3
# name + tool id + the Hotkeys action it is bound to. The visible label and the tooltip are both
# COMPOSED from that action (ROADMAP "Tooltips on menu and tool options": read the shortcut from the
# same hotkey map so tooltip and binding never drift), rather than spelling "(S)" out here as a second
# copy of the binding that could quietly go stale.
const TOOLS := [
	["Select", T_SELECT, "select"],
	["Paint", T_PAINT, "paint"],
	["Place", T_PLACE, "place"],
	["Move", T_MOVE, "move"],
]
# what the Place tool drops, and the mode each maps to. The label is the whole roster of placeable
# things in one row, so adding one later is one line here rather than another strip button.
const PLACE_KINDS := [
	["Wall", Mode.WALL, KEY_L, "place_wall"], ["Door", Mode.DOOR, KEY_D, "place_door"],
	["Bridge", Mode.BRIDGE, KEY_G, "place_bridge"], ["Item", Mode.ITEM, KEY_T, "place_item"],
	["Creature", Mode.CREATURE, KEY_A, "place_creature"], ["Spawn", Mode.SPAWN, KEY_P, "place_spawn"],
]
# EVERY pre-merge shortcut still works and simply selects the merged tool with the right sub-choice, so
# muscle memory survives the consolidation: W/B/S -> Select, C -> Paint (cell), F -> Paint (fine),
# L/D/G/T/A/P -> Place with that kind, V -> Move, E -> Erase, I -> Eyedropper. A is the creature tool
# ("animal", the glossary's other word for one): C is already Paint and R is the rotate action.
const SHORTCUTS := [
	[KEY_W, T_SELECT, -1], [KEY_B, T_SELECT, -1], [KEY_S, T_SELECT, -1],
	[KEY_C, T_PAINT, 0], [KEY_F, T_PAINT, 1],
	[KEY_L, T_PLACE, 0], [KEY_D, T_PLACE, 1], [KEY_G, T_PLACE, 2], [KEY_T, T_PLACE, 3],
	[KEY_A, T_PLACE, 4], [KEY_P, T_PLACE, 5],
	[KEY_V, T_MOVE, -1], [KEY_E, -1, Mode.ERASE], [KEY_I, -1, Mode.EYEDROP],
]

var _tool_buttons := {} # tool id -> Button, so a shortcut can light the right radio
var _fine_check: CheckButton # Paint grain: off = whole cell, on = 16px quarter (was the Fine Details tool)
var _place_buttons := {}     # place-kind index -> Button
var _place_kind := 0         # which kind the Place tool drops (index into PLACE_KINDS)
var _place_grid: GridContainer # the kind row, shown only while Place is the active tool
var _sections := {}     # section title -> {"header": Button, "content": VBoxContainer}, for the
						# accordion (and so a test can check collapse/expand)
var _scroll: ScrollContainer      # wraps the panel body so it scrolls instead of overflowing the window
var _content: VBoxContainer       # the scrolled body (all sections); its min height drives _relayout
var _level_dd: OptionButton       # the Level picker (switch which saved map is edited)
var _level_confirm: ConfirmationDialog # unsaved-changes guard before a Level switch loads
var _pending_level := ""          # the map a confirmed Level switch will load
# persistent Brush panel: shows/edits the armed floor material + colour without the right-click menu
var _mat_buttons := {}            # floor material value -> Button (radio); the active one is highlighted
var _col_swatches := []           # [{color, button}] clickable floor-colour boxes; active gets a border
var _mat_col_label: Label         # heading for the material-aware swatch row (hidden with the row)
var _mat_col_grid: GridContainer  # the row itself; rebuilt whenever the armed material changes
var _mat_col_swatches := []       # [{color, button}] of that row, so the active one can be bordered
var _mat_col_for := ""            # which material the row is currently showing, so it only rebuilds on a change
var _brush_preview: TextureRect   # floor combined-brush swatch: the armed texture tinted by the colour
var _bank_check: CheckButton      # River Bank switch (on = liquids grow a brown bank when laid)
var _wall_mat_buttons := {}       # wall material value -> Button (radio)
var _wall_col_swatches := []      # [{color, button}] clickable wall-colour boxes
var _wall_preview: TextureRect    # wall brush swatch: the armed wall cap texture tinted by the colour
var _item_buttons := {}           # item id -> Button (radio-ish); the armed one is highlighted
var _creature_buttons := {}       # creature id -> Button (radio-ish); the armed one is highlighted
var _kind_buttons := {}           # Bestiary kind -> Button: spawn point vs fixed instance

@onready var _fm: FloorManager = get_node_or_null("../World/FloorManager")
@onready var _edge_highlight: EdgeHighlight = get_node_or_null("../World/EdgeHighlight")
@onready var _map_size_tool: MapSizeTool = get_node_or_null("../World/MapSizeTool")

func _ready() -> void:
	# the tool strip is editor-only chrome: show it in EDIT, hide it in PLAY (see EditorMode)
	visible = EditorMode.is_edit()
	EditorMode.changed.connect(func(_m): visible = EditorMode.is_edit())
	add_to_group("tool_strip") # so tests / other nodes can find the strip

	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	add_child(panel)

	# The body scrolls when it is taller than the window, so a growing tool/material roster is never cut
	# off (the strip used to overflow the bottom edge once Sand/Snow were added). A ScrollContainer's OWN
	# minimum height ignores its scrollable content, so _relayout caps it to the viewport height: shorter
	# content hugs, taller content scrolls. Horizontal scroll is off, so width still hugs the widest button.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(_scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_scroll.add_child(vb)
	_content = vb
	get_viewport().size_changed.connect(_relayout)
	call_deferred("_relayout")

	# --- Level picker: switch which saved map is being edited (ROADMAP "Editor UX revisions" -> level
	# dropdown). Lists user://maps; picking a different one loads it (guarded if there are unsaved edits).
	var level_row := HBoxContainer.new()
	var level_lbl := Label.new()
	level_lbl.text = "Level"
	level_row.add_child(level_lbl)
	_level_dd = OptionButton.new()
	_level_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_dd.item_selected.connect(_on_level_selected)
	_level_dd.get_popup().about_to_popup.connect(_refresh_levels) # freshen the list on each open
	level_row.add_child(_level_dd)
	vb.add_child(level_row)
	vb.add_child(HSeparator.new())

	_level_confirm = ConfirmationDialog.new()
	_level_confirm.dialog_text = "You have unsaved changes. Discard them and load?"
	_level_confirm.title = "Unsaved changes"
	_level_confirm.confirmed.connect(func(): _load_level(_pending_level))
	_level_confirm.canceled.connect(_refresh_levels) # cancel restores the dropdown to the current map
	add_child(_level_confirm)

	# --- Tools accordion section (expanded): FOUR tools (see TOOLS above). What each one acts with
	# lives in the sections below, not in more buttons. ---
	var tools := _add_section(vb, "Tools", true)
	var grp := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = Hotkeys.labelled(t[0], t[2])
		b.tooltip_text = Hotkeys.tip(t[2])
		b.toggle_mode = true
		b.button_group = grp
		b.pressed.connect(_on_tool_pressed.bind(t[1]))
		tools.add_child(b)
		_tool_buttons[t[1]] = b
	_tool_buttons[T_SELECT].button_pressed = true # Select is the default, matching FloorManager's WAND

	# Paint grain, the old Fine Details tool as what it always was: a property of the paint brush.
	_fine_check = CheckButton.new()
	_fine_check.text = "Fine (quarter)"
	_fine_check.tooltip_text = Hotkeys.tip("paint_fine", "16px quarters instead of whole cells.")
	_fine_check.toggled.connect(func(_on):
		if _current_tool() == T_PAINT:
			_apply_tool(T_PAINT))
	tools.add_child(_fine_check)

	# What Place drops. One row instead of five strip buttons; adding a placeable later is one entry
	# in PLACE_KINDS rather than another tool.
	var place_grid := GridContainer.new()
	place_grid.columns = 3
	for i in PLACE_KINDS.size():
		var pb := Button.new()
		pb.text = PLACE_KINDS[i][0]
		pb.tooltip_text = Hotkeys.tip(PLACE_KINDS[i][3])
		pb.pressed.connect(_on_place_kind.bind(i))
		place_grid.add_child(pb)
		_place_buttons[i] = pb
	tools.add_child(place_grid)
	_place_grid = place_grid
	_sync_place_buttons()

	_refresh_levels()

	# --- Brush accordion section (expanded): the armed floor brush (material + colour), always visible
	# and editable here without opening the right-click menu (ROADMAP "Photoshop-style persistent LEFT
	# panel"). Live-synced to FloorManager via its brush_changed signal.
	if _fm != null:
		# collapsed at startup: with an exclusive accordion only one section can be open, and Tools is
		# the one you always need. Selecting a floor opens this automatically (see _on_selection_changed).
		var brush := _add_section(vb, "Brush", false)
		# 4-column material grid: keeps the Brush section short as the roster grows (8 materials = 2 rows,
		# not 4), so the panel needs little scrolling. Buttons hug their text, so 4 short labels stay narrow.
		_brush_preview = _fill_brush_section(brush, FloorMaterials.MATERIAL_NAMES, 4, _on_brush_material, FloorMaterials.COLORS, _on_brush_color, _mat_buttons, _col_swatches)
		# --- the MATERIAL-AWARE half of the palette (ROADMAP "Colour palette: 16 swatches, half
		# material-aware"). The row above is the eight constant "fun" tints; this one swaps to eight
		# realistic tints for whatever material is armed -- wood tones for wood, greys for concrete,
		# greens through dry yellow for grass. Only the floor brush has it: the wall palette's own
		# material-aware set is a separate future entry.
		_mat_col_label = Label.new()
		_mat_col_label.text = "For this material"
		brush.add_child(_mat_col_label)
		_mat_col_grid = GridContainer.new()
		_mat_col_grid.columns = 4
		brush.add_child(_mat_col_grid)
		_rebuild_material_colors(_fm.armed_material())
		# --- Item accordion section (collapsed): which item the Item (T) tool places. Each button is
		# labelled with the definition's name and carries its RARITY colour, so the ramp is visible where
		# you choose, not only on the ground (ROADMAP "Item rarity and rarity highlight").
		var items_box := _add_section(vb, "Item", false)
		var item_grid := GridContainer.new()
		item_grid.columns = 3
		items_box.add_child(item_grid)
		for iid in Items.ids():
			var ib := Button.new()
			ib.text = Items.display_name(iid)
			ib.tooltip_text = Hotkeys.tip("place_item", "%s -- %s." % [Items.display_name(iid), Items.rarity_name(iid)])
			ib.add_theme_color_override("font_color", Items.rarity_color(iid))
			ib.pressed.connect(_on_item_pressed.bind(iid))
			item_grid.add_child(ib)
			_item_buttons[iid] = ib
		_sync_item_buttons(_fm.armed_item())

		# --- Creature accordion section (collapsed): which creature the Creature (A) tool places, and
		# as WHICH KIND. The kind is a sub-choice of the one tool rather than two Place kinds, the same
		# shape as Paint's grain switch: a spawn point and a fixed instance place the same creature, they
		# differ in whether it is authored as "one appears here" or "this one IS here".
		var creature_box := _add_section(vb, "Creature", false)
		var kind_row := HBoxContainer.new()
		creature_box.add_child(kind_row)
		for k in Bestiary.BRUSH_KINDS:
			var kb := Button.new()
			kb.text = Bestiary.kind_name(k)
			kb.tooltip_text = _kind_tip(k)
			kb.pressed.connect(_on_creature_kind_pressed.bind(k))
			kind_row.add_child(kb)
			_kind_buttons[k] = kb
		var creature_grid := GridContainer.new()
		creature_grid.columns = 2
		creature_box.add_child(creature_grid)
		for cid in Bestiary.ids():
			var cb := Button.new()
			cb.text = Bestiary.display_name(cid)
			# the ability is design intent only until Phase C builds combat, so the tooltip says so
			cb.tooltip_text = Hotkeys.tip("place_creature", "%s -- %s.\n%s" % [Bestiary.display_name(cid),
				Bestiary.rarity_name(cid), Bestiary.ability(cid)])
			cb.add_theme_color_override("font_color", Bestiary.rarity_color(cid))
			cb.pressed.connect(_on_creature_pressed.bind(cid))
			creature_grid.add_child(cb)
			_creature_buttons[cid] = cb
		_sync_creature_buttons(_fm.armed_creature(), _fm.armed_creature_kind())

		# River Bank switch: set BEFORE laying a liquid (Water/Lava) to give that body a brown bank or not.
		_bank_check = CheckButton.new()
		_bank_check.text = "River Bank"
		_bank_check.tooltip_text = "When on, Water/Lava you lay grows a brown bank ring. Set before painting."
		_bank_check.button_pressed = _fm.bank_on()
		_bank_check.toggled.connect(func(on: bool): _fm.set_bank_on(on))
		brush.add_child(_bank_check)
		# --- Wall accordion section: the armed wall brush (material + colour), same two-way binding as
		# the floor Brush (a wall selection reflects here; picking here edits the selection in place) ---
		var wall := _add_section(vb, "Wall", false) # collapsed by default; opens when a wall is selected
		_wall_preview = _fill_brush_section(wall, WallSegment.MATERIAL_NAMES, 3, _on_wall_material, WallSegment.COLORS, _on_wall_color, _wall_mat_buttons, _wall_col_swatches)
		EditorState.brush_changed.connect(_refresh_brush)
		EditorState.selection_changed.connect(_on_selection_changed)
		_refresh_brush()

	# --- Advanced accordion section (collapsed): the Map Size edge controls ---
	var adv := _add_section(vb, "Advanced", false)
	var title := Label.new()
	title.text = "Map Size"
	adv.add_child(title)

	# hover-add mode: when on, hovering just outside an edge previews + click-adds that row/column.
	# ON by default (user decision 2026-08-16). Setting button_pressed after connecting fires the
	# handler, which activates MapSizeTool.
	var hover := CheckButton.new()
	hover.text = "Hover-add"
	hover.toggled.connect(_on_hover_toggled)
	adv.add_child(hover)
	hover.button_pressed = true

	for edge in EDGES:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = String(edge).capitalize()
		lbl.custom_minimum_size = Vector2(56, 0)
		row.add_child(lbl)
		row.add_child(_edge_button("+", edge, "add"))
		row.add_child(_edge_button("−", edge, "remove")) # minus sign
		adv.add_child(row)

	# --- Recenter (standalone, always visible below the accordion) ---
	vb.add_child(HSeparator.new())
	var recenter := Button.new()
	recenter.text = Hotkeys.labelled("Recenter", "recenter")
	recenter.tooltip_text = Hotkeys.tip("recenter")
	recenter.pressed.connect(_recenter)
	vb.add_child(recenter)

# add a collapsible accordion section to `parent`: a header button that folds its content VBox. Returns
# the content VBox for the caller to fill. `expanded` sets the initial state. A ▾/▸ arrow shows state.
func _add_section(parent: Node, title: String, expanded: bool) -> VBoxContainer:
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = expanded
	header.text = _section_label(title, expanded)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.visible = expanded
	header.toggled.connect(func(on: bool):
		content.visible = on
		header.text = _section_label(title, on)
		if on:
			_collapse_others(title) # ONE section open at a time (see _collapse_others)
		call_deferred("_relayout")) # expanding/collapsing changes the body height
	parent.add_child(header)
	parent.add_child(content)
	_sections[title] = {"header": header, "content": content}
	return content

# The accordion is EXCLUSIVE: opening a section folds every other one, so the strip stays one screen
# of controls instead of growing as sections pile up open. Collapsing the open one leaves them all
# shut, which is fine -- the header row is still the whole menu.
# Guarded against re-entry: setting button_pressed fires `toggled`, which would otherwise bounce
# straight back in here from each section we close.
var _collapsing := false

func _collapse_others(keep: String) -> void:
	if _collapsing:
		return
	_collapsing = true
	for title in _sections:
		if title != keep:
			_sections[title]["header"].button_pressed = false
	_collapsing = false

func _section_label(title: String, expanded: bool) -> String:
	return ("▾ " if expanded else "▸ ") + title

# cap the scroll body to the visible window height (minus the 8px top/bottom margins): when the body is
# shorter it hugs its content (no scrollbar), when taller it scrolls. Re-run whenever the body height or
# the window size changes (accordion toggles, viewport resize). Robust to the tool/material roster growing.
func _relayout() -> void:
	if _scroll == null or _content == null:
		return
	# reserve the status bar's strip along the bottom, so a strip tall enough to fill the window stops
	# above it instead of running underneath the readout (both are EDIT-only, so they always coexist).
	# Asked of the bar itself, since its height comes from the theme, not from a number either of us picks.
	var sb := get_tree().get_first_node_in_group("status_bar") as StatusBar
	var bar: float = sb.height() if sb != null else float(StatusBar.HEIGHT)
	var avail: float = maxf(get_viewport().get_visible_rect().size.y - 16.0 - bar, 80.0)
	var want: float = _content.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = minf(want, avail)

# expand/collapse a section programmatically (drives the header toggle so its arrow + content follow)
func _set_section(title: String, expanded: bool) -> void:
	if _sections.has(title):
		_sections[title]["header"].button_pressed = expanded

# surface the section matching the current selection: a wall selection opens Wall, a floor selection
# opens Brush, so the reflected material + colour are visible. Folding the sibling is no longer done by
# hand -- the exclusive accordion closes whatever else was open. No selection leaves the sections alone.
func _on_selection_changed() -> void:
	if _fm == null:
		return
	if _fm.selection.has_wall():
		_set_section("Wall", true)
	elif _fm.selection.has_floor():
		_set_section("Brush", true)

# --- Brush panel: swatches + live highlight of the active material/colour ---

# build one brush section's body: a preview swatch, a Material radio grid, and a Colour swatch grid.
# `materials` = Array of [label, value]; `colors` = Array of [label, Color]. `mat_cb`/`col_cb` receive
# the value on click. Records buttons into `mat_out` (value -> Button) and `col_out` ([{color,button}]).
# Returns the preview TextureRect. Shared by the floor Brush and the Wall sections.
func _fill_brush_section(sec: Control, materials: Array, mat_cols: int, mat_cb: Callable, colors: Array, col_cb: Callable, mat_out: Dictionary, col_out: Array) -> TextureRect:
	var pv_box := PanelContainer.new()
	pv_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN # hug the swatch, don't stretch full width
	var pv_sb := StyleBoxFlat.new()
	pv_sb.bg_color = Color(0, 0, 0, 0)
	pv_sb.set_border_width_all(1)
	pv_sb.border_color = Color(0, 0, 0, 0.5)
	pv_sb.set_content_margin_all(2)
	pv_box.add_theme_stylebox_override("panel", pv_sb)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(36, 36) # one tile, roughly cell-sized
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE # let it shrink below the 128px texture
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED # fill the square (crop): grass is 4:3, tiles square
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pv_box.add_child(preview)
	sec.add_child(pv_box)
	var mlbl := Label.new()
	mlbl.text = "Material"
	sec.add_child(mlbl)
	var mgrid := GridContainer.new()
	mgrid.columns = mat_cols
	sec.add_child(mgrid)
	var mgrp := ButtonGroup.new()
	for entry in materials:
		var mval: String = entry[1]
		var mb := Button.new()
		mb.text = entry[0]
		mb.toggle_mode = true
		mb.button_group = mgrp
		mb.pressed.connect(mat_cb.bind(mval))
		mgrid.add_child(mb)
		mat_out[mval] = mb
	var clbl := Label.new()
	clbl.text = "Colour"
	sec.add_child(clbl)
	var cgrid := GridContainer.new()
	cgrid.columns = 5
	sec.add_child(cgrid)
	for entry in colors:
		var cval: Color = entry[1]
		var sw := _make_swatch(cval, entry[0])
		sw.pressed.connect(col_cb.bind(cval))
		cgrid.add_child(sw)
		col_out.append({"color": cval, "button": sw})
	return preview

func _make_swatch(color: Color, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(24, 20)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _swatch_box(color, false))
	b.add_theme_stylebox_override("hover", _swatch_box(color, false))
	b.add_theme_stylebox_override("pressed", _swatch_box(color, true))
	return b

func _swatch_box(color: Color, active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(2)
	if active:
		sb.set_border_width_all(3)
		sb.border_color = Color(0.95, 0.85, 0.1) # bright border reads on any swatch colour
	else:
		sb.set_border_width_all(1)
		sb.border_color = Color(0, 0, 0, 0.4)
	return sb

# highlight the active material (radio) + active colour swatch (border) for BOTH the floor Brush and the
# Wall sections, from FloorManager's live state (fires on every brush_changed)
func _refresh_brush() -> void:
	if _fm == null:
		return
	_refresh_brush_section(_mat_buttons, _fm.armed_material(), _col_swatches, _fm.active_floor_color(), _brush_preview, _fm.armed_brush_texture())
	_rebuild_material_colors(_fm.armed_material())
	_mark_active_swatch(_mat_col_swatches, _fm.active_floor_color())
	_refresh_brush_section(_wall_mat_buttons, _fm.armed_wall_material(), _wall_col_swatches, _fm.active_wall_color(), _wall_preview, _fm.armed_wall_texture())

# highlight one section: press the active material radio, border the active colour swatch, and set the
# preview swatch to the armed texture multiplied by the armed colour (so it reads as the real result).
func _refresh_brush_section(mat_buttons: Dictionary, active_mat: String, col_swatches: Array, active_col: Color, preview: TextureRect, tex: Texture2D) -> void:
	if mat_buttons.has(active_mat):
		mat_buttons[active_mat].button_pressed = true
	for s in col_swatches:
		var active: bool = (s["color"] as Color).is_equal_approx(active_col)
		var b: Button = s["button"]
		b.add_theme_stylebox_override("normal", _swatch_box(s["color"], active))
		b.add_theme_stylebox_override("hover", _swatch_box(s["color"], active))
	if preview != null:
		preview.texture = tex
		preview.modulate = active_col

# Swap the material-aware swatch row to `material`'s realistic tints. Rebuilt rather than restyled
# because the colours, the names and even the COUNT differ per material; only on an actual change, so
# a brush_changed for something else (an arm flag, a tint) costs nothing. A material with no table
# hides the row entirely rather than showing swatches that mean nothing for it.
func _rebuild_material_colors(material: String) -> void:
	if _mat_col_grid == null or material == _mat_col_for:
		return
	_mat_col_for = material
	var entries: Array = FloorMaterials.material_colors(material) if _fm != null else []
	for c in _mat_col_grid.get_children():
		_mat_col_grid.remove_child(c)
		c.queue_free()
	_mat_col_swatches.clear()
	var show := not entries.is_empty()
	_mat_col_grid.visible = show
	_mat_col_label.visible = show
	if not show:
		return
	_mat_col_label.text = "For %s" % material.capitalize()
	for entry in entries:
		var cval: Color = entry[1]
		var sw := _make_swatch(cval, entry[0])
		sw.pressed.connect(_on_brush_color.bind(cval))
		_mat_col_grid.add_child(sw)
		_mat_col_swatches.append({"color": cval, "button": sw})

# border whichever swatch in `row` matches the active colour (the same cue the fun row uses)
func _mark_active_swatch(row: Array, active_col: Color) -> void:
	for sw in row:
		var active: bool = (sw["color"] as Color).is_equal_approx(active_col)
		var b: Button = sw["button"]
		b.add_theme_stylebox_override("normal", _swatch_box(sw["color"], active))
		b.add_theme_stylebox_override("hover", _swatch_box(sw["color"], active))

# picking a material/colour in the panel means "I want to paint with it", so drop into a
# painting mode (Cell) if we're not already in one, then arm the brush. In Cell/Fine we leave the
# mode alone so the panel just edits the live brush.
# with a floor selection active, the pick EDITS the selection in place (arm_floor_material/color do the
# fill), so we leave the mode alone. With no selection, picking means "I want to paint", so drop into
# Cell if not already in a painting mode.
func _on_brush_material(mval: String) -> void:
	if _fm == null:
		return
	if not _fm.selection.has_floor() and _fm.mode() != Mode.CELL and _fm.mode() != Mode.FINE:
		_select_mode(Mode.CELL)
	_fm.arm_floor_material(mval)

func _on_brush_color(cval: Color) -> void:
	if _fm == null:
		return
	if not _fm.selection.has_floor() and _fm.mode() != Mode.CELL and _fm.mode() != Mode.FINE:
		_select_mode(Mode.CELL)
	_fm.arm_floor_color(cval)

# wall picks: with a wall selection active they EDIT it in place (arm_wall_* do the fill); with NO
# selection, picking a wall material/colour means "I want to build with it", so drop into Wall mode (the
# same _wall brush also stamps new walls now) - mirroring the floor brush dropping into Cell to paint.
func _on_wall_material(mval: String) -> void:
	if _fm == null:
		return
	if not _fm.selection.has_wall() and _fm.mode() != Mode.WALL:
		_select_mode(Mode.WALL)
	_fm.arm_wall_material(mval)

func _on_wall_color(cval: Color) -> void:
	if _fm == null:
		return
	if not _fm.selection.has_wall() and _fm.mode() != Mode.WALL:
		_select_mode(Mode.WALL)
	_fm.arm_wall_color(cval)

func _edge_button(text: String, edge: String, mode: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(28, 0)
	b.pressed.connect(_on_press.bind(edge, mode))
	b.mouse_entered.connect(_show_band.bind(edge, mode))
	b.mouse_exited.connect(_clear_band)
	return b

func _on_press(edge: String, mode: String) -> void:
	if mode == "add":
		MapEdit.grow(edge)
	else:
		MapEdit.shrink(edge)
	_show_band(edge, mode) # refresh the preview against the new size

func _show_band(edge: String, mode: String) -> void:
	if _edge_highlight:
		_edge_highlight.show_band(edge, mode)

func _clear_band() -> void:
	if _edge_highlight:
		_edge_highlight.clear_band()

func _recenter() -> void:
	var cam := get_node_or_null("../Camera2D")
	if cam and cam.has_method("recenter_on_player"):
		cam.recenter_on_player()

func _on_hover_toggled(on: bool) -> void:
	if _map_size_tool:
		_map_size_tool.active = on

# --- authoring mode selection ---

func _on_mode_pressed(mode: int) -> void:
	if _fm and _fm.has_method("set_mode"):
		_fm.set_mode(mode)

# which tool is lit right now
func _current_tool() -> int:
	for t in _tool_buttons:
		if _tool_buttons[t].button_pressed:
			return t
	return T_SELECT

# a tool button was pressed: switch to the mode it currently means
func _on_tool_pressed(tool_id: int) -> void:
	_apply_tool(tool_id)

# the mode a tool means right now, given its sub-choice (Paint's grain, Place's kind)
func _mode_for_tool(tool_id: int) -> int:
	match tool_id:
		T_PAINT:
			return Mode.FINE if (_fine_check and _fine_check.button_pressed) else Mode.CELL
		T_PLACE:
			return PLACE_KINDS[_place_kind][1]
		T_MOVE:
			return Mode.MOVE
		_:
			return Mode.WAND

func _apply_tool(tool_id: int) -> void:
	if _tool_buttons.has(tool_id):
		_tool_buttons[tool_id].button_pressed = true # visual only; the setter emits no pressed signal
	_sync_place_buttons()
	_on_mode_pressed(_mode_for_tool(tool_id))

# picking what Place drops also selects the Place tool: choosing "Door" plainly means "I want to put a
# door down", the same way picking a wall material drops you into placing walls.
func _on_place_kind(index: int) -> void:
	_place_kind = index
	_apply_tool(T_PLACE)

# A tool's sub-choice is only on screen while that tool is active: Paint's grain switch and Place's
# kind row appear when you pick them and get out of the way otherwise. That is the other half of the
# merge -- four buttons plus, at most, the one row that the current tool actually needs.
func _sync_place_buttons() -> void:
	var tool_id := _current_tool()
	if _place_grid:
		_place_grid.visible = tool_id == T_PLACE
	if _fine_check:
		_fine_check.visible = tool_id == T_PAINT
	for i in _place_buttons:
		_place_buttons[i].flat = not (tool_id == T_PLACE and i == _place_kind)
	call_deferred("_relayout") # the strip got shorter or taller

# light the tool matching a mode set from elsewhere (e.g. FloorManager arming a bound key drops into
# Place/Item), so the strip never disagrees with what the map tools are actually doing.
func reflect_mode(mode: int) -> void:
	match mode:
		Mode.CELL, Mode.FINE:
			if _fine_check:
				_fine_check.set_pressed_no_signal(mode == Mode.FINE)
			_tool_buttons[T_PAINT].button_pressed = true
		Mode.MOVE:
			_tool_buttons[T_MOVE].button_pressed = true
		Mode.WAND, Mode.BOX, Mode.SELECT:
			_tool_buttons[T_SELECT].button_pressed = true
		_:
			for i in PLACE_KINDS.size():
				if PLACE_KINDS[i][1] == mode:
					_place_kind = i
					_tool_buttons[T_PLACE].button_pressed = true
					break
	_sync_place_buttons()

# --- Level picker ---

# rebuild the dropdown from user://maps, selecting the current map (or a leading "(unsaved)" entry when
# the live map has never been saved). Setting OptionButton.selected does not emit item_selected, so this
# never recurses into a load.
func _refresh_levels() -> void:
	if _level_dd == null:
		return
	_level_dd.clear()
	var cur := MapIO.current()
	var sel_idx := 0
	if cur == "":
		_level_dd.add_item("(unsaved)")
	for map_name in MapIO.list_maps():
		_level_dd.add_item(map_name)
		if map_name == cur:
			sel_idx = _level_dd.item_count - 1
	_level_dd.selected = sel_idx

func _on_level_selected(idx: int) -> void:
	var map_name := _level_dd.get_item_text(idx)
	if map_name == "(unsaved)" or map_name == MapIO.current():
		return
	if MapIO.dirty:
		_pending_level = map_name # confirm before discarding unsaved edits
		_level_confirm.popup_centered()
	else:
		_load_level(map_name)

func _load_level(map_name: String) -> void:
	if map_name != "" and map_name != "(unsaved)":
		MapIO.load_map(map_name)
	_refresh_levels()

# picking an item in the panel arms it AND drops into the Item tool, matching how picking a wall
# material drops into Wall mode ("I want to place this").
func _on_item_pressed(item: String) -> void:
	if _fm == null:
		return
	_fm.arm_item(item)
	_sync_item_buttons(item)
	_select_mode(Mode.ITEM)

# show which item is armed: the active button keeps its rarity font colour and gains a flat highlight
func _sync_item_buttons(active: String) -> void:
	for iid in _item_buttons:
		var b: Button = _item_buttons[iid]
		b.flat = iid != active
		b.disabled = false

# picking a creature arms it AND drops into the Creature tool, the same "I want to place this" move
# the item and wall-material buttons make.
func _on_creature_pressed(creature: String) -> void:
	if _fm == null:
		return
	_fm.arm_creature(creature)
	_sync_creature_buttons(creature, _fm.armed_creature_kind())
	_select_mode(Mode.CREATURE)

# the KIND is a property of the armed brush, not a tool of its own, so picking one does NOT switch
# tools: you can set "fixed instance" before ever choosing a creature.
func _on_creature_kind_pressed(kind: String) -> void:
	if _fm == null:
		return
	_fm.arm_creature_kind(kind)
	_sync_creature_buttons(_fm.armed_creature(), kind)

func _kind_tip(kind: String) -> String:
	match kind:
		Bestiary.INSTANCE: return "This exact creature, exactly here (boss / scripted / quest)"
		Bestiary.ZONE: return Hotkeys.tip("place_creature", "DRAG a region that keeps spawning this creature while you play.")
		_: return "Spawns this creature at play start, then it roams"

func _sync_creature_buttons(active: String, kind: String) -> void:
	for cid in _creature_buttons:
		_creature_buttons[cid].flat = cid != active
	for k in _kind_buttons:
		_kind_buttons[k].flat = k != kind

# every pre-merge letter still works (see SHORTCUTS): it picks the merged tool AND its sub-choice, so
# F still means "fine grain paint" and D still means "place a door", they just no longer need a button
# each. Ignored while a LineEdit (e.g. the save name field) has focus, since those events are consumed
# before reaching _unhandled_key_input.
func _select_mode(mode: int) -> void:
	reflect_mode(mode)
	_on_mode_pressed(mode)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
		return
	for sc in SHORTCUTS:
		if event.keycode != sc[0]:
			continue
		if sc[1] == -1:
			_select_mode(sc[2]) # Erase / Eyedropper: a mode with no button of its own
		elif sc[1] == T_PAINT:
			if _fine_check:
				_fine_check.set_pressed_no_signal(sc[2] == 1)
			_apply_tool(T_PAINT)
		elif sc[1] == T_PLACE:
			_on_place_kind(sc[2])
		else:
			_apply_tool(sc[1])
		get_viewport().set_input_as_handled()
		return
