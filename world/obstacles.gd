class_name Obstacles
extends Node2D

const CELL_SIZE := Grid.CELL
const CAP_HEIGHT := WallSegment.CAP_HEIGHT # thin-rail width
const WALL_HEIGHT := WallSegment.WALL_HEIGHT # cap rises this far above the cell top
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
var bridge_script: Script

# Bridges: crossable decks placed over water. Plain cell+orientation records, mirroring gate_cells
# (a placed-object layer per Architecture review Q1). They re-enable crossing on the water cells they
# cover (see is_bridge / player.gd). MapIO persists them; nodes are respawned in build_world.
var bridge_cells: Array[Dictionary] = [] # [{cell: Vector2i, orientation: "horizontal"/"vertical"}]

# per-cell wall colour (tint over the stone). Only non-white cells are stored; MapIO persists it.
var wall_colors := {} # Vector2i cell -> Color

# per-cell wall material (which face/cap texture pair). Only non-"stone" cells are stored (stone is
# the default); MapIO persists it. Parallel to and independent of wall_colors.
var wall_materials := {} # Vector2i cell -> String ("wood" / "slate"; "stone" = default = unstored)

# cell-keyed indexes over the three stores above, for O(1) lookups (is_blocked runs per step, per flood
# cell and per build). The arrays stay the ordered source of truth MapIO saves; _reindex() rebuilds these
# after every mutation, and every mutation lives in this file.
var _walls := {}   # Vector2i -> true
var _doors := {}   # Vector2i -> its gate_cells record (the same Dictionary, so edits to it show through)
var _bridges := {} # Vector2i -> its bridge_cells record

func _reindex() -> void:
	_walls.clear()
	for c in blocked_cells:
		_walls[c] = true
	_doors.clear()
	for d in gate_cells:
		_doors[d["cell"]] = d
	_bridges.clear()
	for b in bridge_cells:
		_bridges[b["cell"]] = b

func _ready() -> void:
	add_to_group("obstacles") # so MapIO can find the world root to save/rebuild
	wall_segment_script = load("res://world/wall_segment.gd")
	gate_script = load("res://world/gate.gd")
	bridge_script = load("res://world/bridge.gd")
	_reindex()
	build_world()

# --- map (re)building: spawn everything derived from blocked_cells + gate_cells ---

# replace the level with new walls/doors and rebuild the spawned nodes + shadows. The
# lighting (RoomLight) and floors (FloorManager) are rebuilt by MapIO after this, in order.
func apply_map(walls: Array, doors: Array, bridges: Array = []) -> void:
	blocked_cells.clear()
	for w in walls:
		blocked_cells.append(w)
	gate_cells.clear()
	for d in doors:
		gate_cells.append(d)
	bridge_cells.clear()
	for b in bridges:
		bridge_cells.append(b)
	_reindex()
	rebuild()

# respawn every wall/gate/bridge node from the current cell stores (after an in-place edit)
func rebuild() -> void:
	clear_world()
	build_world()

# free every previously spawned wall, gate, gate back-layer and bridge (all group-tagged)
func clear_world() -> void:
	for group in ["walls", "gates", "gate_backlayers", "bridges"]:
		for n in get_tree().get_nodes_in_group(group):
			n.queue_free()

func build_world() -> void:
	for bridge_data in bridge_cells:
		var bridge := Node2D.new()
		bridge.set_script(bridge_script)
		bridge.cell = bridge_data["cell"]
		bridge.orientation = bridge_data["orientation"]
		bridge.position = Grid.cell_center(bridge.cell)
		get_parent().add_child.call_deferred(bridge)
	for gate_data in gate_cells:
		# every door carries a DURABLE id (Architecture review Q3): a Unique key binds to it, so it has
		# to survive save/load, resize and a MOVE. Doors that predate ids (the seeded roster, pre-v12
		# maps) get one minted here, once, so nothing has to migrate on disk.
		if String(gate_data.get("id", "")) == "":
			gate_data["id"] = Items.new_id()
		var gate := Node2D.new()
		gate.set_script(gate_script)
		gate.cell = gate_data["cell"]
		gate.orientation = gate_data["orientation"]
		gate.door_id = String(gate_data["id"])
		# the LOCK (ROADMAP "Locked doors and keys"): "" none, "colour" (a coloured key opens any lock
		# of that colour and is consumed, the lock then gone for good), or "unique" (a named metal key
		# bound to THIS door id; the key is kept and the metal lock stays on the door, open or closed).
		gate.lock = String(gate_data.get("lock", ""))
		gate.lock_color = String(gate_data.get("lock_color", "red"))
		gate.unlocked = gate.lock == "colour" and CharacterIO.is_unlocked(MapIO.current(), gate.door_id)
		# authored default state (MapIO-persisted); applied here so the gate spawns showing what was
		# authored. In PLAY the player's proximity logic takes over; EDIT resets to these.
		gate.authored_open = gate_data.get("open", false)
		gate.authored_swing = gate_data.get("swing", false)
		gate.is_open = gate.authored_open
		if gate.orientation == "vertical":
			gate.swing_right = gate.authored_swing
		else:
			gate.swing_up = gate.authored_swing
		gate.position = Grid.cell_center(gate.cell)
		get_parent().add_child.call_deferred(gate)

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
			# no horizontal line-neighbour. If it also has no VERTICAL line-neighbour, the vertical pass
			# below would skip it too, leaving a cell in blocked_cells (which casts a shadow) with NO wall
			# node ("shadow shows but the wall doesn't build"). Spawn a standalone thin rail here, matching
			# the thin shadow spawn_shadows casts for such a lone cell.
			if not (_in_wall_line(Vector2i(cell.x, cell.y - 1), false) or _in_wall_line(Vector2i(cell.x, cell.y + 1), false)):
				spawn_segment(cell, 1, 0.0, true)
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
		if _walls.has(Vector2i(cell.x, cell.y - 1)):
			continue # a WALL above already covers this cell via the run that started higher
		var run_length := 1
		while _walls.has(Vector2i(cell.x, cell.y + run_length)):
			run_length += 1
		# A length-1 vertical rail only ever arises here for a wall cell bounded by a door (the old
		# wall-only run always had a wall below, so length >= 2). Force it THIN + centered: a full-width
		# single cell would read as a fat horizontal block, but this piece is the vertical arm of a
		# corner that must line up with the (thin, centered) door post it meets.
		spawn_segment(cell, run_length, 0.0, run_length == 1)

	spawn_shadows()
	# colour the freshly spawned walls once they are actually in the tree (they were added
	# deferred above, so this deferred call runs after them)
	_push_wall_props.call_deferred()

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
		if _is_fence(c):
			continue # a SEE-THROUGH fence casts no solid wall shadow (it splits a mixed run's shadow)
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
	return _walls.has(cell)

# see-through fence materials (WallSegment.FENCE) render short/gappy and cast no solid wall shadow. A
# cell's material comes from the wall_materials store (default "stone" = a solid wall).

func _is_fence(cell: Vector2i) -> bool:
	return WallSegment.FENCE.has(wall_materials.get(cell, "stone"))

# is `cell` part of a wall LINE running in the given direction? A WALL always is. A DOOR is only if its
# orientation matches: a "horizontal" door lies in a horizontal line, a "vertical" door in a vertical one.
# This keeps the corner logic from connecting a wall to a perpendicular door.
func _in_wall_line(cell: Vector2i, horizontal: bool) -> bool:
	if _walls.has(cell):
		return true
	return _doors.has(cell) and _doors[cell]["orientation"] == ("horizontal" if horizontal else "vertical")

# The wall PIECE(S) a cell WOULD get if a wall were placed there, using the SAME per-cell shaping as
# build_world (the horizontal + vertical passes + corner trimming) against the CURRENT walls/doors, so a
# hover ghost can show the real horizontal / vertical / corner / T / cross shape. Each entry is a segment
# config {run_length, align, x_start, width} (width 0 = the segment's default full width); FloorManager
# applies them to translucent preview wall_segments. Assumes `cell` itself becomes blocked.
func preview_wall_configs(cell: Vector2i) -> Array:
	var out: Array = []
	var has_left := _in_wall_line(Vector2i(cell.x - 1, cell.y), true)
	var has_right := _in_wall_line(Vector2i(cell.x + 1, cell.y), true)
	var has_vertical := _in_wall_line(Vector2i(cell.x, cell.y - 1), false) or _in_wall_line(Vector2i(cell.x, cell.y + 1), false)
	# horizontal pass: a full-width piece, or a trimmed L-arm at a corner (mirrors build_world exactly)
	if has_left or has_right:
		if has_vertical and has_right and not has_left:
			out.append({"run_length": 1, "align": 0.0, "x_start": -CAP_HEIGHT / 2.0, "width": CELL_SIZE / 2.0 + CAP_HEIGHT / 2.0})
		elif has_vertical and has_left and not has_right:
			out.append({"run_length": 1, "align": 0.0, "x_start": -CELL_SIZE / 2.0, "width": CELL_SIZE / 2.0 + CAP_HEIGHT / 2.0})
		else:
			out.append({"run_length": 1, "align": 0.0, "x_start": 0.0, "width": 0.0})
	# vertical pass: a thin, centered rail when the cell is part of a vertical line (also gives T/cross the
	# vertical arm on top of the horizontal piece above)
	if has_vertical:
		out.append({"run_length": 1, "align": 0.0, "x_start": -CAP_HEIGHT / 2.0, "width": CAP_HEIGHT})
	# a lone cell (no wall-line neighbour) is a thin standalone post, matching build_world
	if not (has_left or has_right or has_vertical):
		out.append({"run_length": 1, "align": 0.0, "x_start": -CAP_HEIGHT / 2.0, "width": CAP_HEIGHT})
	return out

# --- structure removal (Erase tool) ---

# is there a wall OR a door on this cell? (the structure layer of the cell-occupancy model)
func has_structure(cell: Vector2i) -> bool:
	return _walls.has(cell) or _doors.has(cell)

# remove the wall or door occupying `cell` (a cell holds at most one of each per the occupancy
# model, and a wall and door never share a cell). Returns "wall", "door", or "" if nothing was
# there. ONLY mutates the source-of-truth arrays; the caller re-applies the map through MapIO so
# the wall/gate nodes, lighting, floors and shadows all rebuild consistently in one pass.
func remove_structure(cell: Vector2i) -> String:
	if _walls.has(cell):
		blocked_cells.erase(cell)
		wall_colors.erase(cell) # drop any tint stored for the gone wall
		wall_materials.erase(cell) # ...and its material
		_reindex()
		return "wall"
	if _doors.has(cell):
		gate_cells.erase(_doors[cell])
		_reindex()
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
	_reindex()
	return true

# add a door on `cell` with `orientation` ("horizontal"/"vertical"). A wall already there becomes a
# doorway (the wall is replaced, so a door and wall never share a cell). No-op if a door is already
# on the cell. Returns whether anything changed.
func add_door(cell: Vector2i, orientation: String) -> bool:
	if _doors.has(cell):
		return false
	blocked_cells.erase(cell) # a wall under the new door becomes a doorway
	wall_colors.erase(cell)   # drop any tint stored for the replaced wall
	wall_materials.erase(cell) # ...and its material
	gate_cells.append({"cell": cell, "orientation": orientation, "open": false, "swing": false})
	_reindex()
	return true

# --- bridges (crossable decks over water) ---

func is_bridge(cell: Vector2i) -> bool:
	return _bridges.has(cell)

func bridge_orientation(cell: Vector2i) -> String:
	return _bridges[cell]["orientation"] if _bridges.has(cell) else ""

# place a bridge on `cell` (no-op if one is already there). Returns whether it changed anything.
func add_bridge(cell: Vector2i, orientation: String) -> bool:
	if is_bridge(cell):
		return false
	bridge_cells.append({"cell": cell, "orientation": orientation})
	_reindex()
	return true

# remove the bridge on `cell` if present. Returns whether it changed anything.
func remove_bridge(cell: Vector2i) -> bool:
	if not _bridges.has(cell):
		return false
	bridge_cells.erase(_bridges[cell])
	_reindex()
	return true

# --- door authored-state edits (the properties inspector) ---
# open/swing update the live gate node directly (cheap, keeps the node ref) AND the source-of-truth
# dict so the change persists. Orientation is structural (different textures/z/back-layer), so the
# caller re-applies the whole map through MapIO after set_door_orientation.

func door_at(cell: Vector2i) -> Dictionary:
	return _doors.get(cell, {})

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

# --- locks (ROADMAP "Locked doors and keys") ---

# is this cell a door that is LOCKED right now, for `player`? A coloured lock stops being locked once
# this character has opened it (the lock is consumed and gone). A unique lock is checked against the
# inventory every time: lose the key and the door is shut again, which is why nothing is persisted for it.
func is_locked(cell: Vector2i, player = null) -> bool:
	var d := door_at(cell)
	var lock := String(d.get("lock", ""))
	if lock == "":
		return false
	var id := String(d.get("id", ""))
	if lock == "colour":
		return not CharacterIO.is_unlocked(MapIO.current(), id)
	# unique: locked unless the bound key is in hand
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	return player == null or not _has_unique_key_for(player, id)

func _has_unique_key_for(player, door_id: String) -> bool:
	for u in player.inventory.get("uniques", []):
		if String(u.get("item", "")) == "key" and String(u.get("data", {}).get("door_id", "")) == door_id:
			return true
	return false

# try to open a locked door with what the player carries. A COLOURED lock consumes one matching key
# and is then gone for good (recorded per character, since the MAP keeps its authored lock). A UNIQUE
# lock consumes nothing and leaves its metal lock in place; it just checks the key is there.
# Returns true if the door is now passable.
func try_unlock(cell: Vector2i, player) -> bool:
	var d := door_at(cell)
	var lock := String(d.get("lock", ""))
	if lock == "":
		return true
	var id := String(d.get("id", ""))
	if lock == "colour":
		if CharacterIO.is_unlocked(MapIO.current(), id):
			return true
		var key := Items.key_for_color(String(d.get("lock_color", "red")))
		if not player.take_from_stack(key, 1):
			return false
		CharacterIO.mark_unlocked(MapIO.current(), id)
		var g = gate_node_at(cell)
		if g:
			g.unlocked = true # the lock is removed from the door, so it needs no open-state art
			g.queue_redraw()
		return true
	return _has_unique_key_for(player, id)

# author a door's lock: kind "" (none) / "colour" / "unique". `color` is a LOCK_COLORS name, used by
# the coloured kind; `key_name` is the player-facing name a unique key shows.
func set_door_lock(cell: Vector2i, kind: String, color := "red", key_name := "") -> void:
	var d := door_at(cell)
	if d.is_empty():
		return
	if kind == "":
		d.erase("lock")
		d.erase("lock_color")
		d.erase("lock_name")
	else:
		d["lock"] = kind
		d["lock_color"] = color
		if key_name != "":
			d["lock_name"] = key_name
	var g = gate_node_at(cell)
	if g:
		g.lock = kind
		g.lock_color = color
		g.unlocked = false
		g.queue_redraw()

func door_id_at(cell: Vector2i) -> String:
	return String(door_at(cell).get("id", ""))

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

# --- per-cell wall properties: colour (a tint over the material; white = natural) and material (the
# face/cap texture pair; "stone" = the default). Both stores are sparse -- the default is never stored --
# and both are pushed onto the spawned segments together. ---

func get_wall_color(cell: Vector2i) -> Color:
	return wall_colors.get(cell, Color.WHITE)

func get_wall_material(cell: Vector2i) -> String:
	return wall_materials.get(cell, "stone")

func set_wall_color(cell: Vector2i, color: Color) -> void:
	color_cells([cell], color)

func set_wall_material(cell: Vector2i, material: String) -> void:
	material_cells([cell], material)

# every wall of the building `cell` belongs to
func color_building(cell: Vector2i, color: Color) -> void:
	color_cells(building_cells(cell), color)

func material_building(cell: Vector2i, material: String) -> void:
	material_cells(building_cells(cell), material)

# `cells` is any iterable of cells (an Array, or a Dictionary used as a set)
func color_cells(cells, color: Color) -> void:
	_set_cells(wall_colors, Color.WHITE, cells, color)

func material_cells(cells, material: String) -> void:
	_set_cells(wall_materials, "stone", cells, material)

# write `value` into the sparse `store` for each cell (the `default` value erases the entry), then repaint
func _set_cells(store: Dictionary, default, cells, value) -> void:
	for c in cells:
		if value == default:
			store.erase(c)
		else:
			store[c] = value
	_push_wall_props()

# replace a whole store from saved rows (MapIO load): colours as [cx, cy, r, g, b], materials [cx, cy, name]
func apply_wall_colors(list: Array) -> void:
	wall_colors.clear()
	for a in list:
		wall_colors[Vector2i(int(a[0]), int(a[1]))] = Color(a[2], a[3], a[4])
	_push_wall_props()

func apply_wall_materials(list: Array) -> void:
	wall_materials.clear()
	for a in list:
		wall_materials[Vector2i(int(a[0]), int(a[1]))] = String(a[2])
	_push_wall_props()

# push both stores onto the spawned wall segments so they redraw with their tints and materials
func _push_wall_props() -> void:
	for w in get_tree().get_nodes_in_group("walls"):
		var cols: Array = []
		var mats: Array = []
		for c in w.cells():
			cols.append(get_wall_color(c))
			mats.append(get_wall_material(c))
		w.cell_colors = cols
		w.cell_materials = mats
		w.queue_redraw()


# the connected straight wall run(s) through `cell`: extend along the row and along the column
# while cells are walls, stopping at any gap (a doorway breaks the run). At a junction this is
# the whole cross of straight arms meeting there.
func line_cells(start: Vector2i) -> Dictionary:
	var out := {}
	if not _walls.has(start):
		return out
	out[start] = true
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = start + step
		while _walls.has(c):
			out[c] = true
			c += step
	return out

# the wall cells forming one building: flood-fill over orthogonally-adjacent walls, bridging a
# single door/gate gap in a wall line (so a wall broken by a doorway is still one building).
func building_cells(start: Vector2i) -> Dictionary:
	var out := {}
	if not _walls.has(start):
		return out
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	out[start] = true
	var q: Array = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d in dirs:
			var n: Vector2i = c + d
			var target: Vector2i
			var hit := false
			if _walls.has(n):
				target = n
				hit = true
			elif _doors.has(n) and _walls.has(n + d):
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


# --- persistence: this layer's slice of the MapIO map dict (walls, doors, bridges, wall colours and
# materials), and loading it back. Encode and decode live side by side so they cannot drift apart. ---

func to_data() -> Dictionary:
	var walls: Array = []
	for c in blocked_cells:
		walls.append([c.x, c.y])
	var doors: Array = []
	for d in gate_cells:
		# v12: a door carries a durable id (a Unique key binds to it) and its authored lock
		var rec := {"cell": [d["cell"].x, d["cell"].y], "orientation": d["orientation"],
			"open": d.get("open", false), "swing": d.get("swing", false), "id": d.get("id", "")}
		if String(d.get("lock", "")) != "":
			rec["lock"] = d["lock"]
			rec["lock_color"] = d.get("lock_color", "red")
			if String(d.get("lock_name", "")) != "":
				rec["lock_name"] = d["lock_name"]
		doors.append(rec)
	var bridges: Array = []
	for b in bridge_cells:
		bridges.append({"cell": [b["cell"].x, b["cell"].y], "orientation": b["orientation"]})
	# sparse: only non-white colours and non-stone materials are stored
	var colors: Array = []
	for c in wall_colors:
		var col: Color = wall_colors[c]
		colors.append([c.x, c.y, col.r, col.g, col.b])
	var mats: Array = []
	for c in wall_materials:
		mats.append([c.x, c.y, wall_materials[c]])
	return {"walls": walls, "doors": doors, "bridges": bridges, "wall_colors": colors, "wall_materials": mats}

# replace the whole layer from a map dict and rebuild its nodes. Older maps simply lack the newer keys
# (pre-v12 doors have no id -> build_world mints one; pre-v6 has no materials -> all stone).
func load_data(data: Dictionary) -> void:
	var walls: Array = []
	for a in data.get("walls", []):
		walls.append(Vector2i(int(a[0]), int(a[1])))
	var doors: Array = []
	for d in data.get("doors", []):
		var rec := {"cell": Vector2i(int(d["cell"][0]), int(d["cell"][1])), "orientation": d["orientation"],
			"open": bool(d.get("open", false)), "swing": bool(d.get("swing", false)),
			"id": String(d.get("id", ""))}
		if String(d.get("lock", "")) != "":
			rec["lock"] = String(d["lock"])
			rec["lock_color"] = String(d.get("lock_color", "red"))
			rec["lock_name"] = String(d.get("lock_name", ""))
		doors.append(rec)
	var bridges: Array = []
	for b in data.get("bridges", []):
		bridges.append({"cell": Vector2i(int(b["cell"][0]), int(b["cell"][1])), "orientation": String(b["orientation"])})
	apply_map(walls, doors, bridges)
	# colours/materials land on the segments once build_world's deferred spawns are in the tree
	apply_wall_colors(data.get("wall_colors", []))
	apply_wall_materials(data.get("wall_materials", []))
