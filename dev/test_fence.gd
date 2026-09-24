extends "res://dev/test_case.gd"

# Dev-only headless test for SEE-THROUGH fences (ROADMAP item 7 fence roster): Wood Fence / Metal Bars /
# Chainlink are wall materials that render short + gappy (procedurally in wall_segment) and cast NO solid
# wall shadow, while still blocking + enclosing like any wall. Checks registration, the fence set is in
# sync (wall_segment.FENCE == obstacles.FENCE_MATERIALS), _is_fence, collision is unchanged, the segment
# reports the fence material, and a fully-fenced map casts no wall shadow. Text-only.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_fence.tscn

const FENCES := ["wood_fence", "metal_bars", "chainlink"]

func _ready() -> void:
	var main: Node = await boot_main()
	var obs = main.get_node("World/Obstacles")
	var fm = main.get_node("World/FloorManager")
	EditHistory.reset()

	# --- registration + set sync ---
	var menu := {}
	for e in fm.WALL_MATERIALS:
		menu[e[1]] = true
	for f in FENCES:
		_check("%s in the wall-material menu" % f, menu.has(f))
		_check("%s has a preview icon" % f, fm.WALL_TEX.has(f))
	_check("obstacles.FENCE_MATERIALS matches the 3 fences", obs.FENCE_MATERIALS.size() == 3 and obs.FENCE_MATERIALS.has("chainlink"))

	# --- _is_fence + collision unchanged ---
	var wall := Vector2i(6, 3)
	_check("setup: (6,3) is a solid wall", obs.is_blocked(wall) and not obs._is_fence(wall))
	obs.set_wall_material(wall, "wood_fence")
	_check("a fenced cell reports _is_fence", obs._is_fence(wall))
	_check("a fenced cell STILL blocks movement", obs.is_blocked(wall))
	await get_tree().process_frame # let _apply_wall_materials push onto the segments
	var seg_ok := false
	for w in get_tree().get_nodes_in_group("walls"):
		var idx: int = w.cells().find(wall)
		if idx != -1 and w._cell_material(idx) == "wood_fence" and w.FENCE.has("wood_fence"):
			seg_ok = true
	_check("the segment covering (6,3) reports the fence material", seg_ok)
	obs.set_wall_material(wall, "stone")
	_check("reset to stone clears _is_fence", not obs._is_fence(wall))

	# --- a fully-fenced map casts NO solid wall shadow (each fence cell is excluded) ---
	obs.build_world()
	await get_tree().process_frame
	_check("baseline: solid walls cast some shadow", obs.wall_shadow_polys.size() > 0)
	for c in obs.blocked_cells:
		obs.set_wall_material(c, "metal_bars")
	obs.build_world()
	await get_tree().process_frame
	_check("all-fence map casts no solid wall shadow", obs.wall_shadow_polys.size() == 0)
	# fences still block after the material change
	_check("fenced cells still block", obs.is_blocked(wall))

	finish()
