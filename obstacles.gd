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

func _ready() -> void:
	wall_segment_script = load("res://wall_segment.gd")
	var gate_script := load("res://gate.gd")
	for gate_data in gate_cells:
		var gate := Node2D.new()
		gate.set_script(gate_script)
		gate.cell = gate_data["cell"]
		gate.orientation = gate_data["orientation"]
		gate.position = Vector2(
			gate.cell.x * CELL_SIZE + CELL_SIZE / 2.0,
			gate.cell.y * CELL_SIZE + CELL_SIZE / 2.0
		)
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
	for cell in blocked_cells:
		var has_left := blocked_cells.has(Vector2i(cell.x - 1, cell.y))
		var has_right := blocked_cells.has(Vector2i(cell.x + 1, cell.y))
		if not (has_left or has_right):
			continue
		var has_vertical := blocked_cells.has(Vector2i(cell.x, cell.y - 1)) or blocked_cells.has(Vector2i(cell.x, cell.y + 1))
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
		var has_above := blocked_cells.has(Vector2i(cell.x, cell.y - 1))
		var has_below := blocked_cells.has(Vector2i(cell.x, cell.y + 1))
		if not (has_above or has_below):
			continue # not part of any vertical rail
		if has_above:
			continue # covered by the run that started higher in this column
		var run_length := 1
		while blocked_cells.has(Vector2i(cell.x, cell.y + run_length)):
			run_length += 1
		spawn_segment(cell, run_length, 0.0)

	spawn_shadows()

# Builds the whole structure's shadow, once, after the map is known. Rather than one
# polygon per cell (which overlap and read as layered pieces), it casts ONE shadow
# per continuous wall RUN, so each long wall is a single seamless shape. The casting
# structure includes the gate cells, so the cast stays continuous across gate gaps.
var wall_shadow_polys: Array = [] # collected static wall shadow hexagons

func spawn_shadows() -> void:
	var structure: Dictionary = {}
	for c in blocked_cells:
		structure[c] = true
	# gate cells are deliberately excluded: each gate casts its OWN shadow (see
	# gate_shadow.gd) so the cast updates dynamically as it opens and closes,
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

func spawn_segment(cell: Vector2i, run_length: int, align_offset_x: float) -> void:
	var segment := make_segment(cell, run_length)
	segment.align_offset_x = align_offset_x
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
