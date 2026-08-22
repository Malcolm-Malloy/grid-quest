extends Node2D

# Draws the wall + gate shadows as one merged union at a single opacity. Two rules keep
# darkness from ever stacking on the z axis:
#
#  1. Only ONE darkness layer is ever active. While the player stands in a room the
#     RoomLight paints a single flat dim over everything unlit and this layer draws
#     NOTHING; outside the rooms this layer draws and the RoomLight paints nothing.
#     The two are mutually exclusive, so a floor pixel can only ever take one 0.55 pass.
#  2. Within a single draw the shadows are merged into a disjoint union (no self overlap)
#     and every room interior is cut out of them, so no wall shadow can fall inside a
#     room and no two shadow pieces can overlap.

const ALPHA := 0.55
const CELL := 32
const HALF := 16 # a floor quarter; the door-open floor restamp works per quarter

var shadow_color := Color(0.05, 0.08, 0.05, ALPHA)
var ground_texture := preload("res://world/ground_grass.png") # to stamp interiors clean
var static_union: Array = [] # pre-merged static wall regions, in World/grid space
var merged_regions: Array = [] # the pieces actually drawn, for the in-shadow test

func _ready() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST

func set_static(polys: Array) -> void:
	static_union = _merge_all(polys)
	queue_redraw()

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	merged_regions = []
	var rl := get_parent().get_node_or_null("RoomLight")
	# rule 1: only ONE darkness layer is ever active. When the outdoor is NOT lit (the
	# player is purely indoors) the RoomLight owns all the darkness and shadows draw
	# nothing, which is what makes double-darkening impossible. Shadows draw only when
	# the outdoor is lit (player outside, or crossing an open outdoor door).
	if rl and not rl.exterior_lit():
		return
	var polys: Array = static_union.duplicate()
	for gate in get_tree().get_nodes_in_group("gates"):
		for p in gate.shadow_polys():
			polys.append(p)
	# rule 2: merge to a disjoint union so shadow can never overlap itself
	merged_regions = _merge_all(polys)
	for region in merged_regions:
		draw_colored_polygon(region, shadow_color)
	# With no room lit (player outside), each room interior reads as a dark, shadowed
	# space, but WITHOUT the wall-shadow pattern the merge just filled it with (a filled
	# polygon can't carve a hole in an enclosed shadow). So per interior: stamp the clean
	# ground back (erasing that fill), then lay ONE flat shadow over it. Exactly one pass,
	# so it's a uniform shade with no doubling and no wall-shadow shapes inside.
	if rl:
		var lit: Dictionary = rl.lit_cells()
		var fm := get_parent().get_node_or_null("FloorManager")
		var grid_on: bool = fm.grid_on() if fm else false
		var grid: Color = fm.grid_color() if fm else Color(1, 1, 1, 0.12)
		for c in rl.enclosed_floor_cells():
			var r := Rect2(c.x * CELL, c.y * CELL, CELL, CELL)
			# erase the wall-shadow fill with the cell's real floor, quarter by quarter so
			# quarter-level painting survives (the whole-cell stamp used to grass mixed cells)
			_stamp_floor(fm, c.x * 2, c.y * 2)
			_stamp_floor(fm, c.x * 2 + 1, c.y * 2)
			_stamp_floor(fm, c.x * 2, c.y * 2 + 1)
			_stamp_floor(fm, c.x * 2 + 1, c.y * 2 + 1)
			# a room joined to the outdoor by an open door stays bright; the rest shade
			if not lit.has(c):
				draw_rect(r, shadow_color)
			elif grid_on:
				# the stamp above also paints over the grid lines, so redraw them on the
				# lit floor when the grid is toggled on (top + left edge per cell draws
				# every interior line exactly once)
				draw_line(r.position, r.position + Vector2(CELL, 0), grid, 1.0, true)
				draw_line(r.position, r.position + Vector2(0, CELL), grid, 1.0, true)
		# wipe the wall shadows off the interior wall/corner tiles of lit rooms so they read
		# clean like indoors, restamping each quarter with the ground under it (a uniform room's
		# wall-ring fill, or a quarter painted under the wall) instead of blanket grass
		for r in rl.lit_wall_stamps():
			_stamp_floor(fm, floori(r.position.x / HALF), floori(r.position.y / HALF))

# stamp one 16px floor quarter (coords in quarter units) with its real material, matching the
# indoor base_fills: fm.floor_tex_at_quad gives a painted quarter or a uniform room's wall-ring
# fill, and null falls back to the grass base.
func _stamp_floor(fm, qx: int, qy: int) -> void:
	var r := Rect2(qx * HALF, qy * HALF, HALF, HALF)
	var tex = fm.floor_tex_at_quad(Vector2i(qx, qy)) if fm else null
	# a floor tint (white = none) multiplies the restamp too, so a coloured floor stays coloured
	# where a lit room's wall shadows are wiped and under an open door (matches base_fills).
	var tint: Color = fm.floor_tint_at_quad(Vector2i(qx, qy)) if fm else Color.WHITE
	if tex:
		draw_texture_rect_region(tex, r, GridBackground.tiled_src(r), tint)
	else:
		draw_texture_rect_region(ground_texture, r, r, tint)

# true if a global-space point falls inside a drawn shadow piece (player tint test).
# Empty in room mode, so the player is never tinted while a room is lit.
func point_in_shadow(global_pt: Vector2) -> bool:
	var local := to_local(global_pt)
	if _in_any_room(local):
		return false # the player is never inside an interior while outdoors; skip it
	for region in merged_regions:
		if Geometry2D.is_point_in_polygon(local, region):
			return true
	return false

func _in_any_room(local: Vector2) -> bool:
	var rl := get_parent().get_node_or_null("RoomLight")
	if rl == null:
		return false
	return rl.is_enclosed_floor(Vector2i(floori(local.x / CELL), floori(local.y / CELL)))

# merges a list of polygons into disjoint boundary (CCW) regions. Holes (CW rings)
# are dropped; directional cast shadows don't enclose anything, so none arise here.
func _merge_all(polys: Array) -> Array:
	# union the shadow polys into non-overlapping regions. Incremental accumulation: each poly is merged
	# into the existing regions in a single pass, re-checking after each merge because a combined region
	# grows and may then overlap another. O(n^2) worst case vs the old full-restart-scan's O(n^3), which
	# mattered on big houses (see "Investigate lag"). Two polys "combine" when their union is a single
	# outer (CCW) polygon; if they don't overlap, merge_polygons returns both, so nothing is merged.
	var regions: Array = []
	for p in polys:
		var cur: PackedVector2Array = p
		var merged := true
		while merged:
			merged = false
			for i in range(regions.size()):
				var m := Geometry2D.merge_polygons(cur, regions[i])
				var ccw: Array = []
				for q in m:
					if not Geometry2D.is_polygon_clockwise(q):
						ccw.append(q)
				if ccw.size() == 1: # overlapped -> combined into one region
					cur = ccw[0]
					regions.remove_at(i)
					merged = true
					break
		regions.append(cur)
	return regions
