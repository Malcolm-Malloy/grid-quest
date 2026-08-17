extends Node

# Dev-only headless test for the Magic Wand marching-ants outline (selection_overlay.gd). The wall
# selection's ants must trace the UNION SILHOUETTE of the actual wall cap/face rectangles, not the
# 32px cell grid (ROADMAP "Coloured floors" bug: "the ant line does not trace around the obstacle
# layer"). Checks _rect_union_edges cancels shared interior edges and matches the true perimeter.
# Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_selection_overlay.tscn

var _fails := 0
var _overlay: Node2D

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

# total length of a list of [a, b] axis-aligned edges
func _total_len(edges: Array) -> float:
	var sum := 0.0
	for e in edges:
		sum += (e[1] - e[0]).length()
	return sum

# true if any edge lies strictly interior to the union (i.e. both sides covered) -- there should be
# none. We detect this indirectly: an outline's total length must equal the true perimeter; a stray
# interior edge would push the total above it. So the length check is the interior-edge guard.

func _ready() -> void:
	MapIO.auto_load = false # no World in this bare scene; skip the startup map auto-load
	_overlay = Node2D.new()
	_overlay.set_script(load("res://floors/selection_overlay.gd"))
	add_child(_overlay)

	# --- single rect: perimeter of a 32x32 square is 128 ---
	var e1: Array = _overlay._rect_union_edges([Rect2(0, 0, 32, 32)])
	_check("single rect: outline length is the 128px perimeter", is_equal_approx(_total_len(e1), 128.0))

	# --- two horizontally adjacent rects: the shared inner edge (x=32) must cancel ---
	# union is 64x32, perimeter 192; a naive per-rect outline would be 256 (two full squares).
	var e2: Array = _overlay._rect_union_edges([Rect2(0, 0, 32, 32), Rect2(32, 0, 32, 32)])
	_check("adjacent rects: shared edge cancels (length 192, not 256)", is_equal_approx(_total_len(e2), 192.0))
	var has_inner := false
	for e in e2:
		# an interior vertical edge would sit at x=32 spanning y 0..32
		if is_equal_approx(e[0].x, 32.0) and is_equal_approx(e[1].x, 32.0):
			has_inner = true
	_check("adjacent rects: no interior edge at the shared seam", not has_inner)

	# --- wall-like L: a full-width cap (32 wide) over a thin face (11 wide), like a real wall ---
	# cap [0,0,32,11] + face [0,11,11,28]. Union is an L; perimeter = 2*(32) top/rail region...
	# compute expected directly: outline goes 0,0 -> 32,0 -> 32,11 -> 11,11 -> 11,39 -> 0,39 -> 0,0
	# lengths: 32 + 11 + 21 + 28 + 11 + 39 = 142
	var e3: Array = _overlay._rect_union_edges([Rect2(0, 0, 32, 11), Rect2(0, 11, 11, 28)])
	_check("wall-like L: outline hugs the silhouette (length 142)", is_equal_approx(_total_len(e3), 142.0))

	# --- vertically stacked rects sharing a full edge also cancel (cap over face, aligned) ---
	# [0,0,32,11] + [0,11,32,28] -> a single 32x39 rect, perimeter 2*(32+39)=142
	var e4: Array = _overlay._rect_union_edges([Rect2(0, 0, 32, 11), Rect2(0, 11, 32, 28)])
	_check("stacked aligned rects: merge into one, length 142", is_equal_approx(_total_len(e4), 142.0))

	# --- empty input yields no edges ---
	_check("empty input: no edges", _overlay._rect_union_edges([]).is_empty())

	# --- rect subtraction: a floor region minus a wall occluder traces the VISIBLE floor ---
	# floor [0,0,64,64], wall occluder covering the top strip [0,0,64,16] -> visible is [0,16,64,48].
	var region: Dictionary = _overlay._region_from_rects([Rect2(0, 0, 64, 64)], [Rect2(0, 0, 64, 16)])
	_check("subtract: outline is the visible rect perimeter (2*(64+48)=224)", is_equal_approx(_total_len(region["edges"]), 224.0))
	# no edge should run along the fully-covered top (y=0)
	var top_edge := false
	for e in region["edges"]:
		if is_equal_approx(e[0].y, 0.0) and is_equal_approx(e[1].y, 0.0):
			top_edge = true
	_check("subtract: no ants along the fully-occluded top edge", not top_edge)
	# the visible boundary sits at y=16 (the wall's bottom), not y=0
	var seam := false
	for e in region["edges"]:
		if is_equal_approx(e[0].y, 16.0) and is_equal_approx(e[1].y, 16.0):
			seam = true
	_check("subtract: ants run along the wall's bottom edge (y=16)", seam)

	# a floor fully covered by walls yields no visible region at all
	var gone: Dictionary = _overlay._region_from_rects([Rect2(0, 0, 32, 32)], [Rect2(0, 0, 32, 32)])
	_check("subtract: fully-occluded floor has no edges", gone["edges"].is_empty())

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
