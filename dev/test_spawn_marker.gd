extends Node

# Dev-only headless test for the authored player spawn (ROADMAP "Player spawn marker"): the Set Spawn
# tool, the marker as MapIO's source of truth for `spawn`, and the decoupling from where the character
# happens to stand. Text-only, no rendering.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_spawn_marker.tscn

var _fails := 0
func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond: _fails += 1

func _mid(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 32 + 16)

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var fm = main.get_node("World/FloorManager")
	var obs = main.get_node("World/Obstacles")
	var player = main.get_node("World/Player")
	var marker = main.get_node_or_null("World/SpawnMarker")
	EditHistory.reset()

	_check("the world has a spawn marker", marker != null)
	_check("the marker is visible in EDIT (editor chrome)", marker.visible)

	# --- 1. the Set Spawn tool moves the marker, one click = one undo entry ---
	var target := Vector2i(30, 20)
	fm.set_mode(fm.Mode.SPAWN)
	_check("set spawn on an open cell", fm._set_spawn_at(_mid(target)))
	_check("the marker moved to that cell", marker.spawn_cell() == target)
	_check("serialize now stores the MARKER's position", MapIO.serialize()["spawn"]["x"] == 30 * 32 + 16)
	_check("it committed one undo entry", EditHistory.can_undo())
	EditHistory.undo()
	await get_tree().process_frame
	_check("undo moved the marker back", marker.spawn_cell() != target)
	EditHistory.redo()
	await get_tree().process_frame
	_check("redo put it back", marker.spawn_cell() == target)

	# --- 2. setting the spawn does NOT move the character (that is the whole point) ---
	var was: Vector2 = player.position
	fm._set_spawn_at(_mid(Vector2i(28, 18)))
	_check("the character stayed put while the spawn moved", player.position == was)
	_check("the marker is where the click was", marker.spawn_cell() == Vector2i(28, 18))

	# --- 3. refusals: walls, off-map, and a no-op re-click ---
	_check("a repeat click on the same cell commits nothing", not fm._set_spawn_at(_mid(Vector2i(28, 18))))
	var wall := Vector2i(8, 3) # a cell on the seeded room's top wall run
	_check("setup: that cell is a wall", obs.is_blocked(wall))
	_check("the spawn refuses a wall cell (the player would start stuck)", not fm._set_spawn_at(_mid(wall)))
	_check("the marker did not move", marker.spawn_cell() == Vector2i(28, 18))
	_check("the spawn refuses a cell off the map", not fm._set_spawn_at(Vector2(-40, -40)))

	# --- 4. walking the character no longer moves the map's start point (the bug this fixes) ---
	MapIO.save_map("__spawn_test")
	player.position = Vector2(64, 64) # "walk" somewhere else
	await get_tree().process_frame
	_check("a moved character does not change the serialized spawn",
		MapIO.serialize()["spawn"]["x"] == 28 * 32 + 16)

	# --- 5. a map LOAD puts the character on the marker ---
	MapIO.load_map("__spawn_test")
	await get_tree().process_frame
	_check("load moved the character onto the authored spawn", player.position == _mid(Vector2i(28, 18)))
	_check("load put the marker there too", marker.spawn_cell() == Vector2i(28, 18))
	DirAccess.remove_absolute("user://maps/__spawn_test.json")

	# --- 6. a map resize carries the spawn with the world ---
	MapEdit.grow("left") # everything shifts +1 in x, the spawn included
	await get_tree().process_frame
	_check("growing the left edge shifted the marker with the map", marker.spawn_cell() == Vector2i(29, 18))

	# --- 7. the marker hides in PLAY ---
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	await get_tree().process_frame
	_check("the marker hides in PLAY", not marker.visible)
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	await get_tree().process_frame
	_check("and returns in EDIT", marker.visible)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
