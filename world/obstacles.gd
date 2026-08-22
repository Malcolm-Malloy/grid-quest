extends Node2D

const CELL_SIZE := 32
const CAP_HEIGHT := 11 # thin-rail width; must match wall_segment.gd's CAP_HEIGHT
const WALL_HEIGHT := 7 # cap rises this far above the cell top; must match wall_segment.gd
const SHADOW_CAST := 12.0 # 45-degree down-right smear length for the whole-structure shadow

# Four rooms laid out like a window (2x2), doors between neighbours plus one out.
#   A(top-left) | B(top-right)
#   -----------+------------
#   C(bot-left) | D(bot-right)
var gate_cells: Array[Dictionary] = [
	{"cell": Vector2i(10, 5), "orientation": "vertical"},   # A <-> B
	{"cell": Vector2i(10, 9), "orientation": "vertical"},   # C <-> D
	{"cell": Vector2i(8, 7), "orientation": "horizontal"},  # A <-> C
	{"cell": Vector2i(12, 7), "orientation": "horizontal"}, # B <-> D
	{"cell": Vector2i(8, 11), "orientation": "horizontal"}, # C -> outside
]

# outer frame (6,3)-(14,11) with a central cross (column 10, row 7) dividing it
# into four 3x3 rooms; gaps left where the five doors above sit
var blocked_cells: Array[Vector2i] = [
	# top wall (row 3)
	Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3), Vector2i(12, 3), Vector2i(13, 3), Vector2i(14, 3),
	# bottom wall (row 11, gap at 8 for the outside door)
	Vector2i(6, 11), Vector2i(7, 11), Vector2i(9, 11), Vector2i(10, 11), Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11), Vector2i(14, 11),
	# left wall (column 6)
	Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(6, 10),
	# right wall (column 14)
	Vector2i(14, 4), Vector2i(14, 5), Vector2i(14, 6), Vector2i(14, 7), Vector2i(14, 8), Vector2i(14, 9), Vector2i(14, 10),
	# central vertical divider (column 10, gaps at 5 and 9 for doors)
	Vector2i(10, 4), Vector2i(10, 6), Vector2i(10, 7), Vector2i(10, 8), Vector2i(10, 10),
	# central horizontal divider (row 7, gaps at 8 and 12 for doors; 10,7 above)
	Vector2i(7, 7), Vector2i(9, 7), Vector2i(11, 7), Vector2i(13, 7),
]

var wall_segment_script: Script
var gate_script: Script

# per-cell wall colour (tint over the stone). Only non-white cells are stored; MapIO persists it.
var wall_colors := {} # Vector2i cell -> Color

# per-cell wall material (which face/cap texture pair). Only non-"stone" cells are stored (stone is
# the default); MapIO persists it. Parallel to and independent of wall_colors.
var wall_materials := {} # Vector2i cell -> String ("wood" / "slate"; "stone" = default = unstored)

# door cell -> orientation ("horizontal"/"vertical"), rebuilt each build_world for O(1) lookup by the
# corner logic (see _in_wall_line). A door only continues a wall line running in its own orientation.
var _gate_orient := {}

func _ready() -> void:
	add_to_group("obstacles") # so MapIO can find the world root to save/rebuild
	wall_segment_script = load("res://world/wall_segment.gd")
	gate_script = load("res://world/gate.gd")
	build_world()

# --- map (re)building: spawn everything derived from blocked_cells + gate_cells ---

# replace the level with new walls/doors and rebuild the spawned nodes + shadows. The
# lighting (RoomLight) and floors (FloorManager) are rebuilt by MapIO after this, in order.
func apply_map(walls: Array, doors: Array) -> void:
	blocked_cells.clear()
	for w in walls:
		blocked_cells.append(w)
	gate_cells.clear()
	for d in doors:
		gate_cells.append(d)
	clear_world()
	build_world()

# free every previously spawned wall, gate and gate back-layer (all group-tagged)
func clear_world() -> void:
	for group in ["walls", "gates", "gate_backlayers"]:
		for n in get_tree().get_nodes_in_group(group):
			n.queue_free()

func build_world() -> void:
	for gate_data in gate_cells:
		var gate := Node2D.new()
		gate.set_script(gate_script)
		gate.cell = gate_data["cell"]
		gate.orientation = gate_data["orientation"]
		# authored default state (MapIO-persisted); applied here so the gate spawns showing what was
		# authored. In PLAY the player's proximity logic takes over; EDIT resets to these.
		gate.authored_open = gate_data.get("open", false)
		gate.authored_swing = gate_data.get("swing", false)
		gate.is_open = gate.authored_open
		if gate.orientation == "vertical":
			gate.swing_right = gate.authored_swing
		else:
			gate.swing_up = gate.authored_swing
		gate.position = Vector2(
			gate.cell.x * CELL_SIZE + CELL_SIZE / 2.0,
			gate.cell.y * CELL_SIZE + CELL_SIZE / 2.0
		)
		get_parent().add_child.call_deferred(gate)

	# door orientation lookup for the corner logic below (rebuilt each map)
	_gate_orient.clear()
	for d in gate_cells:
		_gate_orient[d["cell"]] = d["orientation"]

	# Two independent passes so the two rail types never fight over a cell:
	#
	#   1. Horizontal rails (top/bottom of the square): full-width pieces. At a
	#      corner cell the piece is TRIMMED so it only reaches inward toward its
	#      horizontal neighbour and stops flush with the vertical rail's outer
	#      edge, instead of sticking out past it. That turns the junction from a T
	#      (three arms) into an L (two arms), which is what a corner should be.
	#
	#   2. Vertical rails (sides of the square): thin and always CENTERED in the
	#      column. A run starts at the top of a vertical span and extends DOWN
	#      through every blocked cell, corner cells included, so it physically
	#      overlaps the corner and the square closes with no grass gap.
	# Corner/junction decisions treat a neighbour as part of the wall LINE if it is a wall, OR a door whose
	# ORIENTATION matches the direction (a "horizontal" door lies in a horizontal line, a "vertical" door in
	# a vertical line). So a wall corners toward a doorway in its OWN line, but not toward a perpendicular
	# door (e.g. a closet's side wall must not connect to the closet's front door). Only WALL cells ever
	# spawn a rail; the door cell itself is never drawn over.
	for cell in blocked_cells:
		var has_left := _in_wall_line(Vector2i(cell.x - 1, cell.y), true)
		var has_right := _in_wall_line(Vector2i(cell.x + 1, cell.y), true)
		if not (has_left or has_right):
			continue
		var has_vertical := _in_wall_line(Vector2i(cell.x, cell.y - 1), false) or _in_wall_line(Vector2i(cell.x, cell.y + 1), false)
		if has_vertical and has_right and not has_left:
			# left corner: horizontal arm reaches right, outer (left) edge flush
			# with the centered vertical rail's left edge
			spawn_corner(cell, -CAP_HEIGHT / 2.0, CELL_SIZE / 2.0 + CAP_HEIGHT / 2.0)
		elif has_vertical and has_left and not has_right:
			# right corner: horizontal arm reaches left, outer (right) edge flush
			# with the vertical rail's right edge
			spawn_corner(cell, -CELL_SIZE / 2.0, CELL_SIZE / 2.0 + CAP_HEIGHT / 2.0)
		else:
			spawn_segment(cell, 1, 0.0)

	for cell in blocked_cells:
		# "part of a vertical line" counts a wall or a VERTICAL door above/below (an orientation-matched
		# doorway), so the wall cell above/below a vertical door still gets a rail and the corner closes,
		# but a perpendicular (horizontal) door does NOT pull a vertical rail. A door interrupts the RUN
		# though (the rail only extends over consecutive WALL cells, stops at the door, new run on the far side).
		var has_above := _in_wall_line(Vector2i(cell.x, cell.y - 1), false)
		var has_below := _in_wall_line(Vector2i(cell.x, cell.y + 1), false)
		if not (has_above or has_below):
			continue # not part of any vertical line
		if blocked_cells.has(Vector2i(cell.x, cell.y - 1)):
			continue # a WALL above already covers this cell via the run that started higher
		var run_length := 1
		while blocked_cells.has(Vector2i(cell.x, cell.y + run_length)):
			run_length += 1
		# A length-1 vertical rail only ever arises here for a wall cell bounded by a door (the old
		# wall-only run always had a wall below, so length >= 2). Force it THIN + centered: a full-width
		# single cell would read as a fat horizontal block, but this piece is the vertical arm of a
		# corner that must line up with the (thin, centered) door post it meets.
		spawn_segment(cell, run_length, 0.0, run_length == 1)

	spawn_shadows()
	# colour the freshly spawned walls once they are actually in the tree (they were added
	# deferred above, so this deferred call runs after them)
	_apply_wall_colors.call_deferred()
	_apply_wall_materials.call_deferred()

# Builds the whole structure's shadow, once, after the map is known. Rather than one
# polygon per cell (which overlap and read as layered pieces), it casts ONE shadow
# per continuous wall RUN, so each long wall is a single seamless shape. The casting
# structure includes the gate cells, so the cast stays continuous across gate gaps.
var wall_shadow_polys: Array = [] # collected static wall shadow hexagons

func spawn_shadows() -> void:
	# reset first: build_world/spawn_shadows runs on EVERY map rebuild (every wall placement re-applies the
	# map), and this array is a member, so without clearing it accumulated stale polys from every prior
	# rebuild forever, making the shadow merge grow without bound (progressive lag + memory leak).
	wall_shadow_polys.clear()
	var structure: Dictionary = {}
	for c in blocked_cells:
		structure[c] = true
	# gate cells are deliberately excluded: each gate casts its OWN shadow (see
	# gate.gd shadow_polys) so the cast updates dynamically as it opens and closes,
	# while these wall runs stay static

	# horizontal walls: one FULL-WIDTH shadow per left-to-right run
	for c in structure:
		if not _is_horiz(structure, c):
			continue
		if structure.has(Vector2i(c.x - 1, c.y)):
			continue # start only from the left end of the run
		var run := 1
		while structure.has(Vector2i(c.x + run, c.y)):
			run += 1
		var last_x = c.x + run - 1
		var inset := (CELL_SIZE - CAP_HEIGHT) / 2.0
		var hleft: float = c.x * CELL_SIZE
		var hright: float = (last_x + 1) * CELL_SIZE
		# a run end that is also a corner (has a vertical neighbour) is an L-piece,
		# narrower than the full cell, so pull the shadow in to match it instead of
		# spilling past the corner on the outer side
		if structure.has(Vector2i(c.x, c.y - 1)) or structure.has(Vector2i(c.x, c.y + 1)):
			hleft += inset
		if structure.has(Vector2i(last_x, c.y - 1)) or structure.has(Vector2i(last_x, c.y + 1)):
			hright -= inset
		wall_shadow_polys.append(hexagon(hleft, hright, c.y * CELL_SIZE - WALL_HEIGHT, (c.y + 1) * CELL_SIZE))

	# vertical walls: one THIN, centered shadow per top-to-bottom run (the cells that
	# aren't part of a horizontal run; corners belong to the horizontal runs above)
	for c in structure:
		if _is_horiz(structure, c):
			continue
		if structure.has(Vector2i(c.x, c.y - 1)) and not _is_horiz(structure, Vector2i(c.x, c.y - 1)):
			continue # start only from the top end of the run
		var run := 1
		while structure.has(Vector2i(c.x, c.y + run)) and not _is_horiz(structure, Vector2i(c.x, c.y + run)):
			run += 1
		var thin_left: float = c.x * CELL_SIZE + (CELL_SIZE - CAP_HEIGHT) / 2.0
		wall_shadow_polys.append(hexagon(thin_left, thin_left + CAP_HEIGHT, c.y * CELL_SIZE - WALL_HEIGHT, (c.y + run) * CELL_SIZE))

	# hand the collected wall shadows to the manager, which merges them into one
	# continuous shape and draws them together with the (dynamic) gate shadows
	get_parent().get_node("ShadowGroup").set_static(wall_shadow_polys)

func _is_horiz(structure: Dictionary, c: Vector2i) -> bool:
	return structure.has(Vector2i(c.x - 1, c.y)) or structure.has(Vector2i(c.x + 1, c.y))

# one wall run's footprint [left,right]x[top,bottom] smeared down-right at 45 degrees
# into a hexagon polygon (world/grid space)
func hexagon(left: float, right: float, top: float, bottom: float) -> PackedVector2Array:
	var cast := SHADOW_CAST
	return PackedVector2Array([
		Vector2(left, top),
		Vector2(right, top),
		Vector2(right + cast, top + cast), # top-right 45-degree diagonal
		Vector2(right + cast, bottom + cast),
		Vector2(left + cast, bottom + cast),
		Vector2(left, bottom), # bottom-left 45-degree diagonal
	])

func spawn_segment(cell: Vector2i, run_length: int, align_offset_x: float, thin := false) -> void:
	var segment := make_segment(cell, run_length)
	segment.align_offset_x = align_offset_x
	if thin:
		# force the thin, centered vertical-rail width (wall_segment defaults a single cell to full
		# width). Used for a length-1 vertical rail at a corner that abuts a door (see the vertical pass).
		segment.seg_x_start = -CAP_HEIGHT / 2.0
		segment.seg_width = CAP_HEIGHT
	get_parent().add_child.call_deferred(segment)

# a trimmed single-cell horizontal piece with an explicit local x extent, used for
# L-shaped corners
func spawn_corner(cell: Vector2i, x_start: float, width: float) -> void:
	var segment := make_segment(cell, 1)
	segment.seg_x_start = x_start
	segment.seg_width = width
	get_parent().add_child.call_deferred(segment)

func make_segment(cell: Vector2i, run_length: int) -> Node2D:
	var segment := Node2D.new()
	segment.set_script(wall_segment_script)
	segment.run_length = run_length
	segment.position = Vector2(
		cell.x * CELL_SIZE + CELL_SIZE / 2.0,
		(cell.y + run_length - 1) * CELL_SIZE + CELL_SIZE / 2.0
	)
	# a sibling (not a child of this node) so it can be y-sorted against the player;
	# the caller adds it deferred because World is still finishing _ready() here
	return segment

func is_blocked(cell: Vector2i) -> bool:
	return blocked_cells.has(cell)

# is `cell` part of a wall LINE running in the given direction? A WALL always is. A DOOR is only if its
# orientation matches: a "horizontal" door lies in a horizontal line, a "vertical" door in a vertical one.
# This keeps the corner logic from connecting a wall to a perpendicular door. Uses the _gate_orient
# lookup built in build_world (O(1)); call only during/after a build.
func _in_wall_line(cell: Vector2i, horizontal: bool) -> bool:
	if blocked_cells.has(cell):
		return true
	return _gate_orient.get(cell, "") == ("horizontal" if horizontal else "vertical")

# --- structure removal (Erase tool) ---

# is there a wall OR a door on this cell? (the structure layer of the cell-occupancy model)
func has_structure(cell: Vector2i) -> bool:
	if blocked_cells.has(cell):
		return true
	for g in gate_cells:
		if g["cell"] == cell:
			return true
	return false

# remove the wall or door occupying `cell` (a cell holds at most one of each per the occupancy
# model, and a wall and door never share a cell). Returns "wall", "door", or "" if nothing was
# there. ONLY mutates the source-of-truth arrays; the caller re-applies the map through MapIO so
# the wall/gate nodes, lighting, floors and shadows all rebuild consistently in one pass.
func remove_structure(cell: Vector2i) -> String:
	if blocked_cells.has(cell):
		blocked_cells.erase(cell)
		wall_colors.erase(cell) # drop any tint stored for the gone wall
		wall_materials.erase(cell) # ...and its material
		return "wall"
	for i in gate_cells.size():
		if gate_cells[i]["cell"] == cell:
			gate_cells.remove_at(i)
			return "door"
	return ""

# --- structure placement (Wall / Door tools) ---
# Both ONLY mutate the source-of-truth arrays; the caller re-applies the map through MapIO so the
# wall/gate nodes, lighting, floors and shadows rebuild consistently. Adding a wall that re-encloses
# a room flips it back to indoors for free, the inverse of the erase-opens-a-room reclassification.

# add a wall on `cell`. No-op (returns false) if a wall or door already occupies it, keeping one
# structure per cell (the occupancy model). Ground under the wall is untouched (separate AREA layer).
func add_wall(cell: Vector2i) -> bool:
	if has_structure(cell):
		return false
	blocked_cells.append(cell)
	return true

# add a door on `cell` with `orientation` ("horizontal"/"vertical"). A wall already there becomes a
# doorway (the wall is replaced, so a door and wall never share a cell). No-op if a door is already
# on the cell. Returns whether anything changed.
func add_door(cell: Vector2i, orientation: String) -> bool:
	for g in gate_cells:
		if g["cell"] == cell:
			return false
	blocked_cells.erase(cell) # a wall under the new door becomes a doorway
	wall_colors.erase(cell)   # drop any tint stored for the replaced wall
	wall_materials.erase(cell) # ...and its material
	gate_cells.append({"cell": cell, "orientation": orientation, "open": false, "swing": false})
	return true

# --- door authored-state edits (the properties inspector) ---
# open/swing update the live gate node directly (cheap, keeps the node ref) AND the source-of-truth
# dict so the change persists. Orientation is structural (different textures/z/back-layer), so the
# caller re-applies the whole map through MapIO after set_door_orientation.

func door_at(cell: Vector2i) -> Dictionary:
	for d in gate_cells:
		if d["cell"] == cell:
			return d
	return {}

func gate_node_at(cell: Vector2i):
	for g in get_tree().get_nodes_in_group("gates"):
		if g.cell == cell:
			return g
	return null

func set_door_open(cell: Vector2i, value: bool) -> void:
	var d := door_at(cell)
	if d.is_empty():
		return
	d["open"] = value
	var g = gate_node_at(cell)
	if g:
		g.authored_open = value
		g.reset_to_authored()

func set_door_swing(cell: Vector2i, value: bool) -> void:
	var d := door_at(cell)
	if d.is_empty():
		return
	d["swing"] = value
	var g = gate_node_at(cell)
	if g:
		g.authored_swing = value
		g.reset_to_authored()

# flip the door's orientation between "horizontal" and "vertical". Structural, so only the dict is
# mutated here; the caller rebuilds via MapIO to respawn the gate with the right textures/layers.
func set_door_orientation(cell: Vector2i, orientation: String) -> void:
	var d := door_at(cell)
	if not d.is_empty():
		d["orientation"] = orientation

# orientation of the wall run through `cell`: "horizontal" if it has a horizontal wall/door
# neighbour, "vertical" if a vertical one, "" if isolated (the caller falls back to its armed
# default). A door embeds in the run it bridges, mirroring how walls auto-orient from neighbours
# (see build_world): a door in a left-right wall line is "horizontal" (walked top-to-bottom).
func wall_run_orientation(cell: Vector2i) -> String:
	if has_structure(Vector2i(cell.x - 1, cell.y)) or has_structure(Vector2i(cell.x + 1, cell.y)):
		return "horizontal"
	if has_structure(Vector2i(cell.x, cell.y - 1)) or has_structure(Vector2i(cell.x, cell.y + 1)):
		return "vertical"
	return ""

# --- wall colouring (per-cell tint over the stone) ---

func get_wall_color(cell: Vector2i) -> Color:
	return wall_colors.get(cell, Color.WHITE)

# colour one wall cell (white resets it to natural stone)
func set_wall_color(cell: Vector2i, color: Color) -> void:
	if color == Color.WHITE:
		wall_colors.erase(cell)
	else:
		wall_colors[cell] = color
	_apply_wall_colors()

# colour every wall of the building `cell` belongs to
func color_building(cell: Vector2i, color: Color) -> void:
	_color_cells(building_cells(cell), color)

# colour the connected straight wall run(s) through `cell` (the horizontal + vertical arms)
func color_line(cell: Vector2i, color: Color) -> void:
	_color_cells(line_cells(cell), color)

func _color_cells(cells: Dictionary, color: Color) -> void:
	for c in cells:
		if color == Color.WHITE:
			wall_colors.erase(c)
		else:
			wall_colors[c] = color
	_apply_wall_colors()

# the connected straight wall run(s) through `cell`: extend along the row and along the column
# while cells are walls, stopping at any gap (a doorway breaks the run). At a junction this is
# the whole cross of straight arms meeting there.
func line_cells(start: Vector2i) -> Dictionary:
	var out := {}
	if not blocked_cells.has(start):
		return out
	var walls := {}
	for c in blocked_cells:
		walls[c] = true
	out[start] = true
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = start + step
		while walls.has(c):
			out[c] = true
			c += step
	return out

# the wall cells forming one building: flood-fill over orthogonally-adjacent walls, bridging a
# single door/gate gap in a wall line (so a wall broken by a doorway is still one building).
func building_cells(start: Vector2i) -> Dictionary:
	var out := {}
	if not blocked_cells.has(start):
		return out
	var walls := {}
	for c in blocked_cells:
		walls[c] = true
	var doors := {}
	for g in gate_cells:
		doors[g["cell"]] = true
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	out[start] = true
	var q: Array = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d in dirs:
			var n: Vector2i = c + d
			var target: Vector2i
			var hit := false
			if walls.has(n):
				target = n
				hit = true
			elif doors.has(n) and walls.has(n + d):
				target = n + d # bridge the one-cell door gap to the wall beyond
				hit = true
			if hit and not out.has(target):
				out[target] = true
				q.append(target)
	return out

# every wall piece rect (cap slice + face) of the given wall cells, for the highlight
func wall_piece_rects(cells: Dictionary) -> Array:
	var out: Array = []
	for w in get_tree().get_nodes_in_group("walls"):
		for c in w.cells():
			if cells.has(c):
				out.append_array(w.piece_rects(c))
	return out

# push wall_colors onto the spawned wall segments so they redraw with their tints
func _apply_wall_colors() -> void:
	for w in get_tree().get_nodes_in_group("walls"):
		var cols: Array = []
		for c in w.cells():
			cols.append(get_wall_color(c))
		w.cell_colors = cols
		w.queue_redraw()

# replace all wall colours from a saved list of [cx, cy, r, g, b] (used by MapIO on load)
func apply_wall_colors(list: Array) -> void:
	wall_colors.clear()
	for a in list:
		wall_colors[Vector2i(int(a[0]), int(a[1]))] = Color(a[2], a[3], a[4])
	_apply_wall_colors()

# --- wall materials (per-cell face/cap texture pair; parallel to wall colours above) ---

func get_wall_material(cell: Vector2i) -> String:
	return wall_materials.get(cell, "stone")

# set one wall cell's material ("stone" resets it to the default and drops the entry)
func set_wall_material(cell: Vector2i, material: String) -> void:
	if material == "stone":
		wall_materials.erase(cell)
	else:
		wall_materials[cell] = material
	_apply_wall_materials()

# set the material of every wall of the building `cell` belongs to
func material_building(cell: Vector2i, material: String) -> void:
	_material_cells(building_cells(cell), material)

func _material_cells(cells: Dictionary, material: String) -> void:
	for c in cells:
		if material == "stone":
			wall_materials.erase(c)
		else:
			wall_materials[c] = material
	_apply_wall_materials()

# push wall_materials onto the spawned wall segments so they redraw with their materials
func _apply_wall_materials() -> void:
	for w in get_tree().get_nodes_in_group("walls"):
		var mats: Array = []
		for c in w.cells():
			mats.append(get_wall_material(c))
		w.cell_materials = mats
		w.queue_redraw()

# replace all wall materials from a saved list of [cx, cy, name] (used by MapIO on load)
func apply_wall_materials(list: Array) -> void:
	wall_materials.clear()
	for a in list:
		wall_materials[Vector2i(int(a[0]), int(a[1]))] = String(a[2])
	_apply_wall_materials()
