extends "res://dev/test_case.gd"

# Dev-only headless test for Roofs (ROADMAP "Future terrain and world objects" -> Roofs): one roof per
# building (rooms joined by a shared wall or door, plus their wall/door ring), hidden while the player
# is inside it, off in EDIT until Show Roofs is on, always on in PLAY, no roof over a fenced pen, and
# rebuilt when the layout changes. Fades are stepped by calling _process directly. Text only.
#   dev/run_tests.sh test_roofs

const ROOM := Vector2i(8, 9)  # floor inside the default map's room
const WALL := Vector2i(8, 3)  # a cell on that room's top wall run
const DOOR := Vector2i(8, 11) # the room's bottom doorway
const OUTSIDE := Vector2i(2, 2)

func _ready() -> void:
	var main: Node = await boot_main()
	var roofs: Roofs = main.get_node("World/Roofs")
	var topo: RoomTopology = main.get_node("World/RoomTopology")
	var obs: Obstacles = main.get_node("World/Obstacles")
	var player: Player = main.get_node("World/Player")
	var settle := func() -> void: roofs._process(1.0) # longer than FADE: every fade completes

	# the footprint
	var piece := roofs.piece_at(ROOM)
	_check("the default room has a roof", piece != null and roofs.buildings().size() >= 1)
	_check("the roof covers the room, its walls and its door",
			piece != null and piece.cells.has(ROOM) and piece.cells.has(WALL) and piece.cells.has(DOOR))
	_check("standing in the doorway counts as inside", roofs.piece_at(DOOR) == piece)
	_check("no roof outside", roofs.piece_at(OUTSIDE) == null and not piece.cells.has(OUTSIDE))

	# visibility: EDIT hides until Show Roofs, then the building you're in hides
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	player.position = Grid.cell_center(OUTSIDE)
	settle.call()
	_check("EDIT: roofs are off by default", not roofs.show_in_edit and not piece.visible)
	roofs.show_in_edit = true
	settle.call()
	_check("EDIT + Show Roofs: the roof shows", piece.visible and is_equal_approx(piece.alpha, 1.0))
	_check("a solid roof occludes the floor-highlight mask",
			piece.visibility_layer & FloorHighlightMask.MASK_BIT != 0)
	player.position = Grid.cell_center(ROOM)
	roofs._process(Roofs.FADE / 2.0)
	_check("walking in starts a fade, not a pop", piece.alpha > 0.0 and piece.alpha < 1.0)
	_check("a fading roof leaves the mask alone", piece.visibility_layer & FloorHighlightMask.MASK_BIT == 0)
	settle.call()
	_check("inside: the roof over you is gone", not piece.visible)
	player.position = Grid.cell_center(OUTSIDE)
	settle.call()
	_check("back outside: the roof returns", piece.visible)
	roofs.show_in_edit = false
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	settle.call()
	_check("PLAY: roofs show without the switch", piece.visible)
	EditorMode.set_mode(EditorMode.Mode.EDIT)

	# two rooms split by an inner wall are still ONE building
	var room := topo.room_floor_cells(ROOM)
	var lo := ROOM
	var hi := ROOM
	for c: Vector2i in room:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var split := lo.x + 1 # the room is 3 wide: one column each side of the split
	for y in range(lo.y, hi.y + 1):
		obs.add_wall(Vector2i(split, y))
	MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
	var west := roofs.piece_at(Vector2i(lo.x, lo.y))
	var east := roofs.piece_at(Vector2i(hi.x, hi.y))
	_check("the split made two rooms", topo.room_floor_cells(Vector2i(lo.x, lo.y)).size() < room.size())
	_check("rooms sharing a wall share one roof", west != null and west == east)

	# a fenced ring is a pen, not a building
	var walls: Array = west.cells.keys().filter(func(c: Vector2i) -> bool: return topo.is_wall(c))
	obs.material_cells(walls, "wood_fence")
	_check("a fenced room gets no roof", roofs.piece_at(Vector2i(lo.x, lo.y)) == null)
	obs.material_cells(walls, "stone")
	_check("turning the fence back to stone restores the roof", roofs.piece_at(Vector2i(lo.x, lo.y)) != null)

	# opening a perimeter wall (room floor on one side, the outdoor on the other) removes that roof
	var ring: Array = roofs.piece_at(Vector2i(lo.x, lo.y)).cells.keys() # a live piece: edits rebuild them
	var gap := Vector2i(-1, -1)
	var opened := Vector2i(-1, -1)
	for c: Vector2i in ring:
		if not topo.is_wall(c):
			continue
		var sides: Array = RoomTopology.neighbours(c)
		var inner: Array = sides.filter(func(n: Vector2i) -> bool: return topo.is_enclosed_floor(n))
		if not inner.is_empty() and sides.any(func(n: Vector2i) -> bool: return topo.is_exterior(n)):
			gap = c
			opened = inner[0]
			break
	_check("found a perimeter wall", gap != Vector2i(-1, -1))
	obs.remove_structure(gap)
	MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
	_check("an opened room loses its roof", topo.is_exterior(opened) and roofs.piece_at(opened) == null)

	finish()
