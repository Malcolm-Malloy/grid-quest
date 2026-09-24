extends Node

# Dev-only benchmark: how long does one full map rebuild take for a big house, and where does the time go?
# Builds a large walled structure, then times apply_map (the full rebuild every wall placement triggers)
# and spawn_shadows (the O(n^3) shadow merge) separately.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/bench_rebuild.tscn

func _t() -> int:
	return Time.get_ticks_usec()

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var obs = main.get_node("World/Obstacles")

	# a "big house": a 30x20 outer room with internal dividers, ~ a few hundred wall cells
	var walls: Array = []
	var x0 := 4; var y0 := 4; var w := 30; var h := 20
	for x in range(x0, x0 + w):
		walls.append(Vector2i(x, y0)); walls.append(Vector2i(x, y0 + h))
	for y in range(y0, y0 + h + 1):
		walls.append(Vector2i(x0, y)); walls.append(Vector2i(x0 + w - 1, y))
	# internal dividers (rooms)
	for gx in [10, 16, 22]:
		for y in range(y0, y0 + h):
			walls.append(Vector2i(gx, y))
	for gy in [10, 14]:
		for x in range(x0, x0 + w):
			walls.append(Vector2i(x, gy))
	# dedupe
	var seen := {}
	var uniq: Array = []
	for c in walls:
		if not seen.has(c):
			seen[c] = true
			uniq.append(c)
	print("wall cells: ", uniq.size())

	# time a full rebuild (what each wall placement runs)
	var reps := 5
	var t0 := _t()
	for i in reps:
		obs.apply_map(uniq, [])
	var per_rebuild := float(_t() - t0) / reps / 1000.0
	print("apply_map (full rebuild): %.2f ms each" % per_rebuild)

	# time spawn_shadows alone (the merge)
	var t1 := _t()
	for i in reps:
		obs.spawn_shadows()
	var per_shadow := float(_t() - t1) / reps / 1000.0
	print("spawn_shadows alone:      %.2f ms each" % per_shadow)
	print("shadow poly count: ", obs.wall_shadow_polys.size())

	# the editor paths layered on top: a floor repaint over a big lake (liquid edges + banks are the
	# costly part), a whole-map serialize (every undo commit), and one frame of a wall drag
	var fm = main.get_node("World/FloorManager")
	obs.apply_map(uniq, [])
	await get_tree().process_frame
	for qx in range(0, 40):
		for qy in range(52, 64):
			fm._quad_mat[Vector2i(qx, qy)] = "water"
	print("floor _rebuild (%d quarters, lake): %.2f ms each" % [fm._quad_mat.size(), _time(func(): fm._rebuild(), reps)])
	print("MapIO.serialize:          %.2f ms each" % _time(func(): MapIO.serialize(), reps))
	print("wall-drag frame:          %.2f ms each" % _time(func(): fm._reapply_map(), reps))

	get_tree().quit(0)

func _time(f: Callable, reps: int) -> float:
	var t := _t()
	for i in reps:
		f.call()
	return float(_t() - t) / reps / 1000.0
