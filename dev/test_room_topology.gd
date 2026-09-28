extends "res://dev/test_case.gd"

# Dev-only headless test for RoomTopology (ROADMAP "Architecture review" Q2): the room layout service
# that lighting, floors, shadows and the player all read. Checks the cell classification and the room
# queries on the default map, then that a structure edit re-floods the rooms and RoomLight follows the
# rebuilt signal (its memoised lit region must not survive the layout change). Text only.
#   dev/run_tests.sh test_room_topology

const ROOM := Vector2i(8, 9)  # floor inside the default map's room
const WALL := Vector2i(8, 3)  # a cell on that room's top wall run
const DOOR := Vector2i(8, 11) # the room's bottom doorway
const OUTSIDE := Vector2i(2, 2)

func _ready() -> void:
	var main: Node = await boot_main()
	var topo: RoomTopology = main.get_node("World/RoomTopology")
	var light: RoomLight = main.get_node("World/RoomLight")
	var player: Player = main.get_node("World/Player")

	# cell classification
	_check("has a layout on the default map", topo.has_layout())
	_check("wall cell is a wall", topo.is_wall(WALL) and not topo.is_door(WALL))
	_check("door cell is a door", topo.is_door(DOOR) and not topo.is_wall(DOOR))
	_check("room floor is enclosed", topo.is_enclosed_floor(ROOM) and not topo.is_exterior(ROOM))
	_check("outside cell is exterior", topo.is_exterior(OUTSIDE) and not topo.is_enclosed_floor(OUTSIDE))
	_check("far beyond the box is exterior", topo.is_exterior(Vector2i(-500, -500)))
	_check("a doorway is indoor but not enclosed floor", topo.is_indoor(DOOR) and not topo.is_enclosed_floor(DOOR))
	_check("a wall is neither indoor nor enclosed", not topo.is_indoor(WALL) and not topo.is_enclosed_floor(WALL))

	# room queries
	var room := topo.room_floor_cells(ROOM)
	_check("room flood finds the room", room.has(ROOM) and room.size() > 1)
	_check("room flood stops at walls and doors", not room.has(WALL) and not room.has(DOOR))
	_check("room flood never reaches outside", not room.has(OUTSIDE))
	_check("room flood from a wall is empty", topo.room_floor_cells(WALL).is_empty())
	_check("room flood from outside is empty", topo.room_floor_cells(OUTSIDE).is_empty())
	var enclosed := topo.enclosed_floor_cells()
	var all_in := true
	for c in room:
		all_in = all_in and enclosed.has(c)
	_check("every room cell is in enclosed_floor_cells", all_in)
	var ring := topo.wall_ring_quads(room)
	var ring_on_structure := true
	for r in ring:
		var c := Grid.cell_of(r.position)
		ring_on_structure = ring_on_structure and (topo.is_wall(c) or topo.is_door(c))
	_check("wall ring is non-empty and only on wall/door cells", not ring.is_empty() and ring_on_structure)
	_check("wall ring of nothing is empty", topo.wall_ring_quads({}).is_empty())

	# a structure edit re-floods the rooms, and lighting follows the signal
	player.position = Grid.cell_center(ROOM)
	_check("indoors with the door closed: the outdoor is not lit", not light.exterior_lit())
	# a perimeter wall: one side is this room's floor, the other the outdoor
	var gap := Vector2i(-1, -1)
	for c in ring.map(func(r: Rect2) -> Vector2i: return Grid.cell_of(r.position)):
		if not topo.is_wall(c):
			continue
		var sides: Array = RoomTopology.neighbours(c)
		if sides.any(func(n: Vector2i) -> bool: return room.has(n)) \
				and sides.any(func(n: Vector2i) -> bool: return topo.is_exterior(n)):
			gap = c
			break
	_check("found a perimeter wall to open", gap != Vector2i(-1, -1))
	var fired := [false]
	topo.rebuilt.connect(func() -> void: fired[0] = true)
	main.get_node("World/Obstacles").remove_structure(gap)
	MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
	_check("rebuild emits rebuilt", fired[0])
	_check("the removed wall is gone from the layout", not topo.is_wall(gap))
	_check("opening the wall makes the room exterior", topo.is_exterior(ROOM) and topo.room_floor_cells(ROOM).is_empty())
	_check("lighting re-derived: the player now stands outdoors", light.exterior_lit())

	finish()
