extends "res://dev/test_case.gd"

# Dev-only headless test for CreatureBrain (ROADMAP "Creature and gameplay systems", Phase C slice 1):
# Wild creatures roam their area, see the player (walls and closed doors block sight, fences don't),
# chase to alongside, give up and walk home, and a fixed instance holds its post. Live occupancy follows
# the moving creature, and flipping back to EDIT puts every creature back where it was placed. The brain
# is stepped by hand (its _physics_process with a fixed delta) so the run is deterministic in time.
#   dev/run_tests.sh test_creature_ai

const HOME := Vector2i(32, 18)   # open grass on the default map, well clear of the house
const POST := Vector2i(40, 26)   # a fixed instance's post
const FAR := Vector2i(20, 28)    # somewhere the player is out of every creature's sight
const DT := 0.05

var cr: Creatures
var player: Player

func _ready() -> void:
	var main: Node = await boot_main()
	cr = main.get_node("World/Creatures")
	player = main.get_node("World/Player")
	var fm: FloorManager = main.get_node("World/FloorManager")
	var obs: Obstacles = main.get_node("World/Obstacles")
	_check("the test cells are open ground", fm.is_walkable(HOME) and fm.is_walkable(POST) and fm.is_walkable(FAR))
	cr.add_creature(HOME, "frost_frog", Bestiary.SPAWN_POINT)
	cr.add_creature(POST, "fire_horse", Bestiary.INSTANCE)
	_put_player(FAR)
	EditorMode.set_mode(EditorMode.Mode.PLAY)
	await get_tree().process_frame
	var frog := _brain_at(HOME)
	var horse := _brain_at(POST)
	_check("PLAY gives each wild creature a brain", frog != null and horse != null)
	_check("a creature occupies its cell", cr.occupant(HOME) != null and cr.blocks_movement(HOME))
	_check("a door is off limits to creatures", not obs.gate_cells.is_empty()
			and not cr.can_enter(obs.gate_cells[0]["cell"], null))

	# roaming stays in its area and occupancy follows it
	var moved := false
	var in_area := true
	for i in 600:
		_tick([frog, horse])
		moved = moved or frog.cell != HOME
		in_area = in_area and frog.area.has_point(frog.cell)
	_check("a spawn point's creature roams", moved)
	_check("...inside its area", in_area)
	_check("the fixed instance holds its post", horse.cell == POST and not horse.is_moving())
	_settle(frog)
	_check("occupancy follows it", cr.occupant(frog.cell) == frog.get_parent()
			and (frog.cell == HOME or cr.occupant(HOME) == null))

	# sight: open ground yes, a wall no, a see-through fence yes
	var eye := frog.cell
	var seen := eye + Vector2i(3, 0)
	var between := eye + Vector2i(1, 0)
	_check("sees the player on open ground", frog.can_see(seen))
	_check("not past SIGHT", not frog.can_see(eye + Vector2i(6, 0)))
	obs.add_wall(between)
	MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)
	_check("a wall blocks sight", not frog.can_see(seen))
	obs.set_wall_material(between, "chainlink")
	_check("a fence does not", frog.can_see(seen))
	obs.remove_structure(between)
	MapIO.rebuild_live(MapIO.REBUILD_STRUCTURES)

	# chase: spotted, then it closes to alongside the player
	_put_player(eye + Vector2i(0, 4))
	for i in 200:
		_tick([frog])
		if frog.mode == CreatureBrain.Mode.CHASE and _alongside(frog):
			break
	_check("it spots the player and chases", frog.mode == CreatureBrain.Mode.CHASE)
	_check("the spot shows a '!'", frog.get_parent()._alert == "!")
	_check("it closes to alongside the player", _alongside(frog))
	_check("it never steps onto the player", frog.cell != Grid.cell_of(player.position))

	# give up: the player gets far away, it turns for home and settles back into roaming
	_put_player(FAR)
	var gave_up := false
	for i in 1200:
		_tick([frog])
		gave_up = gave_up or frog.mode == CreatureBrain.Mode.RETURN
		if gave_up and frog.mode == CreatureBrain.Mode.ROAM:
			break
	_check("losing the player sends it home", gave_up)
	_check("...and it settles back into its area", frog.mode == CreatureBrain.Mode.ROAM and frog.area.has_point(frog.cell))

	# the fixed instance chases too, then walks back to its exact post
	_put_player(POST + Vector2i(-3, 0))
	for i in 200:
		_tick([horse])
		if _alongside(horse):
			break
	_check("a fixed instance chases", horse.mode == CreatureBrain.Mode.CHASE and horse.cell != POST)
	_put_player(FAR)
	for i in 1500:
		_tick([horse])
		if horse.mode == CreatureBrain.Mode.ROAM and not horse.is_moving():
			break
	_check("...and returns to its exact post", horse.cell == POST)

	# EDIT puts everyone back where they were placed; the map never changed
	EditorMode.set_mode(EditorMode.Mode.EDIT)
	await get_tree().process_frame
	var homes := []
	for n in get_tree().get_nodes_in_group("creatures"):
		if not n.is_queued_for_deletion():
			homes.append(Grid.cell_of(n.position))
	_check("EDIT rebuilds creatures at their authored cells", homes.has(HOME) and homes.has(POST))
	_check("the records never moved", cr.has_creature(HOME) and cr.has_creature(POST))
	finish()

func _put_player(c: Vector2i) -> void:
	player.position = Grid.cell_center(c)
	player.target_position = player.position
	player.is_moving = false

func _brain_at(c: Vector2i) -> CreatureBrain:
	var n := cr.occupant(c)
	if n == null:
		return null
	for ch in n.get_children():
		if ch is CreatureBrain:
			return ch
	return null

func _tick(brains: Array) -> void:
	for b: CreatureBrain in brains:
		b._physics_process(DT)

func _settle(b: CreatureBrain) -> void:
	for i in 40:
		if not b.is_moving():
			return
		b._physics_process(DT)

func _alongside(b: CreatureBrain) -> bool:
	var pc := Grid.cell_of(player.position)
	return not b.is_moving() and absi(b.cell.x - pc.x) + absi(b.cell.y - pc.y) == 1
