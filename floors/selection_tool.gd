class_name SelectionTool
extends Node2D

# The editor's selection: the Magic Wand (click a floor patch -> grow to the room; click a wall run ->
# grow to the building), box select, Shift-add / Alt-subtract compositing, the marching-ants overlay,
# and mirroring the selection's look into the Brush panel. The selection itself lives in EditorState
# (sel_kind / sel_quads / sel_cells / sel_level) so every panel can read it; this owns the logic that
# changes it. A child of FloorManager, so the overlay draws in World space.

var overlay: Node2D # the marching ants (selection_overlay.gd)
# the box-select in progress: where it started, how it combines, and the selection it builds on
var box_start := Vector2i.ZERO
var box_op: EditorState.SelOp = EditorState.SelOp.REPLACE
var box_base := {}
var _fm: FloorManager
var _obs: Obstacles
var _topology: RoomTopology
var _room_light: RoomLight # only to relight when the selection changes

func setup(fm: FloorManager, obs: Obstacles, topology: RoomTopology, room_light: RoomLight) -> void:
	_fm = fm
	_obs = obs
	_topology = topology
	_room_light = room_light
	overlay = Node2D.new()
	overlay.set_script(load("res://floors/selection_overlay.gd"))
	overlay.z_index = 1000
	add_child(overlay)

# a wand click either starts a new selection or grows the current one (patch -> whole room for a
# floor, run -> whole building for a wall). See ROADMAP "Magic Wand".
func wand_click(local: Vector2, op := EditorState.SelOp.REPLACE) -> void:
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
		_modify_wall(_obs.line_cells(cell), op)
	else:
		_modify_floor(_with_ring(_patch_quads(cell, q)), op)
	refresh()

# the selection compositing op for a mouse event: Alt subtracts, Shift adds, plain replaces.
static func sel_op(event: InputEvent) -> EditorState.SelOp:
	if event.alt_pressed:
		return EditorState.SelOp.SUBTRACT
	if event.shift_pressed:
		return EditorState.SelOp.ADD
	return EditorState.SelOp.REPLACE

# start a (possible) box selection at `cell`. The modifier at press decides replace / add / subtract
# against the current selection, whose floor quarters are snapshotted as the base to build on.
func begin_box(cell: Vector2i, event: InputEventMouseButton) -> void:
	box_start = cell
	box_op = sel_op(event)
	box_base = EditorState.sel_quads.duplicate() if (EditorState.sel_kind == EditorState.SelKind.FLOOR and box_op != EditorState.SelOp.REPLACE) else {}

# box-select: set the selection to the rectangle from box_start to `cur` (all quarters of every cell
# inside), composited onto box_base per box_op. Called live during the drag.
func update_box(cur: Vector2i) -> void:
	var lo := Vector2i(mini(box_start.x, cur.x), mini(box_start.y, cur.y))
	var hi := Vector2i(maxi(box_start.x, cur.x), maxi(box_start.y, cur.y))
	var region := {}
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for cq in Grid.quads_of(Vector2i(cx, cy)):
				region[cq] = true
	var result: Dictionary = box_base.duplicate()
	if box_op == EditorState.SelOp.SUBTRACT:
		for k in region:
			result.erase(k)
	else: # add, or replace (whose base is empty)
		for k in region:
			result[k] = true
	EditorState.sel_cells = {}
	EditorState.sel_level = 0
	EditorState.sel_quads = result
	EditorState.sel_kind = EditorState.SelKind.FLOOR if not result.is_empty() else EditorState.SelKind.NONE
	refresh()

# union (add) or difference (subtract) a floor `region` (quarter set) into the current selection,
# switching the selection kind to floor if it was a wall selection.
func _modify_floor(region: Dictionary, op: EditorState.SelOp) -> void:
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

func _modify_wall(region: Dictionary, op: EditorState.SelOp) -> void:
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

func _wand_floor(cell: Vector2i, q: Vector2i) -> void:
	# repeat click inside the patch grows it to the whole room floor (all materials, wall-bounded)
	if EditorState.sel_kind == EditorState.SelKind.FLOOR and EditorState.sel_quads.has(q) and EditorState.sel_level == 1:
		var cells: Dictionary = _topology.room_floor_cells(cell)
		if not cells.is_empty():
			EditorState.sel_quads = _fm.room_quads(cells) # interior + under-wall ring (the overlay subtracts walls)
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
	for r in _topology.wall_ring_quads(cells):
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
	var room: Dictionary = _topology.room_floor_cells(cell)
	if room.is_empty():
		var single := {}
		for cq in Grid.quads_of(cell):
			single[cq] = true
		return single
	var allowed := {}
	for c in room:
		for cq in Grid.quads_of(c):
			allowed[cq] = true
	var seed_mat: String = _fm.quad_materials().get(q, "")
	var sel := {q: true}
	var stack: Array = [q]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if sel.has(n) or not allowed.has(n):
				continue
			if _fm.quad_materials().get(n, "") == seed_mat:
				sel[n] = true
				stack.append(n)
	return sel

# make `cells` the current selection (every quarter of each), used after a paste/move so the landed
# region is immediately actionable.
func select_cells(cells: Dictionary) -> void:
	EditorState.sel_kind = EditorState.SelKind.FLOOR
	EditorState.sel_cells = {}
	EditorState.sel_level = 0
	EditorState.sel_quads = {}
	for c in cells:
		for q in Grid.quads_of(c):
			EditorState.sel_quads[q] = true
	refresh()

func clear() -> void:
	EditorState.sel_kind = EditorState.SelKind.NONE
	EditorState.sel_quads = {}
	EditorState.sel_cells = {}
	EditorState.sel_level = 0
	overlay.clear()

func refresh() -> void:
	# a selection change doesn't move the player or alter the layout, so RoomLight won't redraw on its
	# own; nudge it here so the "selection reads lit" overlay updates as the selection grows/clears.
	if _room_light != null:
		_room_light.queue_redraw()
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		# trace the full fill set (interior + under-wall ring) MINUS the surrounding wall sprites, so
		# the ants hug the VISIBLE wood exactly: interior plus the ring slivers that show on the wall
		# tiles where the narrow cap doesn't cover them. Verified by rasterising the geometry.
		overlay.set_floor(EditorState.sel_quads, _floor_occluders())
		_reflect_selection_brush() # mirror the selection's material + colour into the Brush panel
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		var rects: Array = _obs.wall_piece_rects(EditorState.sel_cells) if _obs != null else []
		overlay.set_wall(EditorState.sel_cells, rects)
		_reflect_wall_selection_brush() # mirror the wall selection's material + colour into the panel
	else:
		overlay.clear()
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

# mirror the current floor selection's material + colour into the armed brush, so the Brush panel
# lights up the tile+colour the selection already has (e.g. red tiles -> Tile + Red). Uses the most
# common value across the selected quarters, so a mostly-uniform room reflects its dominant look. Only
# re-emits when something actually changed, so it is safe to call on every selection refresh.
func _reflect_selection_brush() -> void:
	if EditorState.sel_quads.is_empty():
		return
	var mat: String = _dominant(EditorState.sel_quads, _fm.quad_materials(), "")
	var col: Color = _dominant(EditorState.sel_quads, _fm.quad_tints(), Color.WHITE)
	if mat == EditorState.brush and col == EditorState.floor_color and EditorState.tool_kind == EditorState.Brush.FLOOR:
		return
	EditorState.tool_kind = EditorState.Brush.FLOOR
	EditorState.brush = mat
	EditorState.floor_color = col
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

# is there a committed FLOOR selection? Used by the panel to decide whether picking a material/colour
# EDITS the selection (recolour/re-texture in place) rather than arming a brush to paint by hand.
func has_floor() -> bool:
	return EditorState.sel_kind == EditorState.SelKind.FLOOR and overlay != null and overlay.has_selection()

func has_wall() -> bool:
	return EditorState.sel_kind == EditorState.SelKind.WALL and overlay != null and overlay.has_selection()

# does the world-local point `local` fall inside the current selection? Floor selections are keyed by
# 16px quarter, wall selections by 32px cell. Used to decide whether a right-click acts on the
# selection (inside) or deselects it (outside), per "Editor UX revisions" -> deselect a Wand selection.
func contains(local: Vector2) -> bool:
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		return EditorState.sel_quads.has(Grid.quad_of(local))
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		return EditorState.sel_cells.has(Grid.cell_of(local))
	return false

# the CELLS the current selection covers: every cell owning a selected floor quarter, or the selected
# wall cells. This is the clip footprint, so magic-wand-selecting a room (floor + its wall ring) and
# copying takes the room's floor AND the walls/doors around it.
func cells() -> Dictionary:
	var out := {}
	if EditorState.sel_kind == EditorState.SelKind.FLOOR:
		for q in EditorState.sel_quads:
			out[Grid.cell_of_quad(q)] = true
	elif EditorState.sel_kind == EditorState.SelKind.WALL:
		for c in EditorState.sel_cells:
			out[c] = true
	return out

# the 32px CELLS covered by the active FLOOR selection, read by RoomLight so it lights them (skips its
# dim overlay) while selected. Empty unless a floor selection is active. The marching ants still mark
# the selection; lighting it just lets the true (lit) colour show while the user edits the colour.
func lit_cells() -> Dictionary:
	if EditorState.sel_kind != EditorState.SelKind.FLOOR:
		return {}
	var out := {}
	for q in EditorState.sel_quads:
		out[Grid.cell_of_quad(q)] = true
	return out

# How big the committed selection is, in the unit it was actually made in ("" when nothing is
# selected). A floor selection is QUARTER-grained, so it reports cells only when its quarters tile
# whole cells and quads otherwise: half a cell must never read as a whole one.
func summary() -> String:
	if has_floor():
		var cells: int = lit_cells().size()
		if EditorState.sel_quads.size() == cells * 4:
			return "%d cell%s" % [cells, "" if cells == 1 else "s"]
		return "%d quad%s" % [EditorState.sel_quads.size(), "" if EditorState.sel_quads.size() == 1 else "s"]
	if has_wall():
		var n: int = EditorState.sel_cells.size()
		return "%d wall%s" % [n, "" if n == 1 else "s"]
	return ""
