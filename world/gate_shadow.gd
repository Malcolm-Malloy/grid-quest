extends Node2D

# Dynamic cast shadow for one gate. It redraws whenever the gate opens/closes or
# its door swings, so the door's shadow follows it. It lives in the ShadowGroup
# next to the static wall shadows and merges with them (drawn opaque; the group
# applies the one transparency, so no double-darkening at overlaps).
#
# Each state is expressed as a set of [left, right, top, bottom] rects in world/grid
# space; every rect is smeared down-right at 45 degrees into a hexagon, matching the
# wall shadows. Closed => a single strip continuous with the wall. Open => the two
# posts plus the swung door offset to the side.

const CELL := 32
const WALL_H := 7 # cap rise, matches wall_segment/obstacles
const THIN := 11 # thin-rail / post width, matches CAP_HEIGHT
const CAST := 12.0 # 45-degree smear length, matches obstacles.SHADOW_CAST

var gate: Node2D
var shadow_color := Color(0.05, 0.08, 0.05, 1.0)

func _draw() -> void:
	if gate == null:
		return
	for rect in _rects():
		var l: float = rect[0]
		var r: float = rect[1]
		var t: float = rect[2]
		var b: float = rect[3]
		draw_colored_polygon(PackedVector2Array([
			Vector2(l, t),
			Vector2(r, t),
			Vector2(r + CAST, t + CAST), # top-right 45-degree diagonal
			Vector2(r + CAST, b + CAST),
			Vector2(l + CAST, b + CAST),
			Vector2(l, b), # bottom-left 45-degree diagonal
		]), shadow_color)

func _rects() -> Array:
	var cx: int = gate.cell.x
	var cy: int = gate.cell.y
	var center_x := cx * CELL + CELL / 2.0
	var cap_top := float(cy * CELL - WALL_H)
	var cell_top := float(cy * CELL) # closed gates start here, not at cap_top, so the
	# 7px cap doesn't spill a shadow above the cell where there's no wall overhead
	var base := float(cy * CELL + CELL)
	var thin_l := center_x - THIN / 2.0
	var thin_r := center_x + THIN / 2.0
	var out := []
	if gate.orientation == "vertical":
		if not gate.is_open:
			out.append([thin_l, thin_r, cell_top, base]) # closed: thin strip (like the wall)
		else:
			out.append([thin_l, thin_r, cap_top, cy * CELL + 6.0]) # top post
			out.append([thin_l, thin_r, base - 6.0, base]) # bottom post
			if gate.swing_right:
				out.append([center_x + 3.0, center_x + 24.0, cap_top, base]) # door swung east
			else:
				out.append([center_x - 24.0, center_x - 3.0, cap_top, base]) # door swung west
	else:
		var left := float(cx * CELL)
		var right := float(cx * CELL + CELL)
		if not gate.is_open:
			out.append([left, right, cell_top, base]) # closed: full-width strip
		else:
			out.append([left, left + 5.0, cap_top, base]) # left post
			out.append([right - 5.0, right, cap_top, base]) # right post
			if gate.swing_up:
				out.append([left + 1.0, left + 6.0, cap_top - 22.0, cap_top + 4.0]) # door swung up
			else:
				out.append([left + 1.0, left + 6.0, base - 4.0, base + 22.0]) # door swung down
	return out
