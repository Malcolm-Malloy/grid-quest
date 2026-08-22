extends Node

# Dev-only guard for the wall-shadow accumulation leak (ROADMAP "Investigate lag"): spawn_shadows() runs
# on EVERY map rebuild (every wall placement re-applies the whole map), and `wall_shadow_polys` is a
# member array. It was appended to but never cleared, so it accumulated stale polys from every prior
# rebuild forever, and the O(n^3) shadow merge over that growing array made building progressively laggier.
# Fix: clear the array at the start of spawn_shadows. This test asserts the poly count stays constant
# across repeated rebuilds instead of growing.
# Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_shadow_leak.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var obs = main.get_node("World/Obstacles")

	var n1: int = obs.wall_shadow_polys.size()
	_check("initial build produced shadow polys", n1 > 0)

	# calling spawn_shadows again (as every rebuild does) must NOT grow the array
	obs.spawn_shadows()
	var n2: int = obs.wall_shadow_polys.size()
	obs.spawn_shadows()
	var n3: int = obs.wall_shadow_polys.size()
	_check("repeated spawn_shadows does not accumulate polys", n1 == n2 and n2 == n3)

	# a full map re-apply (what a wall placement triggers) also keeps it stable
	obs.apply_map(obs.blocked_cells.duplicate(), obs.gate_cells.duplicate())
	var n4: int = obs.wall_shadow_polys.size()
	_check("a full rebuild keeps the poly count stable (no leak)", n4 == n1)

	# simulate many placements: rebuild 20 times, the count must stay flat (was quadratic growth before)
	for i in 20:
		obs.spawn_shadows()
	var n5: int = obs.wall_shadow_polys.size()
	_check("20 rebuilds keep the poly count flat (no progressive growth)", n5 == n1)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
