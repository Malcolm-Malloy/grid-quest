extends "res://dev/test_case.gd"

# Dev-only headless test for the Minimap (ROADMAP "Minimap"): PLAY-only, buildings as solid blocks from
# outside, only the current building (outdoors greyed) from inside, liquids and free-standing walls as
# boundaries, the map edge, and the baked image following the player. Text only.
#   dev/run_tests.sh test_minimap

const ROOM := Vector2i(8, 9)  # floor inside the default map's room
const WALL := Vector2i(8, 3)  # a wall of that building
const DOOR := Vector2i(8, 11) # the room's bottom doorway
const OUTSIDE := Vector2i(2, 2)
const POND := Vector2i(3, 20) # open grass on the default map, for a liquid
const POST := Vector2i(4, 24) # open grass, for a free-standing wall

func _ready() -> void:
	var main: Node = await boot_main()
	var mm: Minimap = main.get_node("Minimap")
	var roofs: Roofs = main.get_node("World/Roofs")
	var player: Player = main.get_node("World/Player")
	var fm: FloorManager = main.get_node("World/FloorManager")
	var obs: Obstacles = main.get_node("World/Obstacles")
	var baked := func(c: Vector2i) -> Color: return mm._img.get_pixelv(c - mm._origin)
	var near := func(a: Color, b: Color) -> bool: return a.is_equal_approx(b) or \
			(absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01)

	EditorMode.set_mode(EditorMode.Mode.EDIT)
	_check("hidden while editing", not mm.visible)
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	_check("shown in play", mm.visible)

	# outdoors: the building is one block, the rest is ground, beyond the map is off-map
	player.position = Grid.cell_center(OUTSIDE)
	mm._process(0.0)
	_check("outdoors: nothing is 'inside'", mm._inside == null)
	_check("outdoors: room floor reads as the building block", near.call(baked.call(ROOM), Minimap.BUILDING))
	_check("outdoors: its walls are the same block (no interior detail)", near.call(baked.call(WALL), Minimap.BUILDING))
	_check("outdoors: open grass is ground", near.call(baked.call(OUTSIDE + Vector2i(1, 0)), Minimap.GROUND))
	_check("past the map edge is off-map", near.call(baked.call(Vector2i(-1, OUTSIDE.y)), Minimap.OFF_MAP))

	# boundaries: a liquid and a free-standing wall
	for q in Grid.quads_of(POND):
		fm.write_quad(q, "water")
	fm.rebuild()
	obs.add_wall(POST)
	MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
	_check("water shows as a boundary", near.call(mm.cell_color(POND, null, {}), Minimap.WATER))
	_check("a free-standing wall shows as a wall", near.call(mm.cell_color(POST, null, {}), Minimap.WALL))
	_check("a layout change re-bakes", mm._dirty)

	# indoors: only this building, the outdoors greyed
	player.position = Grid.cell_center(ROOM)
	mm._process(0.0)
	_check("indoors: inside the room's building", mm._inside != null and mm._inside == roofs.piece_at(ROOM))
	_check("indoors: floor", near.call(baked.call(ROOM), Minimap.IN_FLOOR))
	_check("indoors: wall", near.call(baked.call(WALL), Minimap.IN_WALL))
	_check("indoors: door", near.call(baked.call(DOOR), Minimap.IN_DOOR))
	_check("indoors: the outdoors greys out", near.call(baked.call(OUTSIDE), Minimap.GREYED))
	var before := mm._origin
	player.position = Grid.cell_center(ROOM + Vector2i(1, 0))
	mm._process(0.0)
	_check("the image follows the player", mm._origin == before + Vector2i(1, 0))

	# every creature state has a dot colour; creatures start wild
	var all_coloured := true
	for s in Bestiary.State.values():
		all_coloured = all_coloured and Bestiary.STATE_COLORS.has(s)
	_check("every creature state has a minimap colour", all_coloured)
	var marker: Node2D = load("res://world/creature_marker.gd").new()
	_check("a creature starts wild", marker.state == Bestiary.State.WILD)
	marker.free()

	EditorMode.set_mode(EditorMode.Mode.EDIT)
	finish()
