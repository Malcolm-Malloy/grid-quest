class_name CreatureBrain
extends Node

# What a Wild creature does in PLAY (Phase C, slice 1): roam, spot the player, chase, give up and go
# home. A child of the creature's node (world/creature_marker.gd), which it moves; Creatures adds one to
# every Wild creature when PLAY builds the world, and the EDIT rebuild throws it away with the node.
#
# Movement is cell by cell like the player's: pick a neighbouring cell, claim it (Creatures.occupy, so
# nothing else steps in), slide there, then let go of the cell it left. Where it may step is
# Creatures.can_enter: the player's walkability rule, minus doors, items, other creatures and the player.
#
#   ROAM   wander its area (a spawn point's radius, or the zone it came from) in short walks with pauses.
#          A fixed instance holds its post instead: it stands, and only moves to chase.
#   CHASE  it has SEEN the player (within SIGHT cells, with no wall or closed door between; fences are
#          see-through) and walks the shortest way to them at its species speed, stopping alongside. The
#          fight itself is the next slice, so for now it just stands there, facing you.
#   RETURN it gave up -- the player got LOSE cells away, stayed out of sight for FORGET seconds, or led it
#          LEASH cells from home -- and it walks home at wandering pace, ignoring the player for a moment
#          (CALM) so it doesn't flip straight back into a chase at the edge of its leash.
#
# A "!" pops over it when it spots you and a "?" when it gives up, so the switch is readable.

enum Mode { ROAM, CHASE, RETURN }

const SIGHT := 5.0        # cells: it notices the player this close, if it can see them
const LOSE := 8.0         # cells: farther than this and it gives up the chase
const FORGET := 2.0       # seconds out of sight before it gives up
const LEASH := 10         # cells from home it will follow before turning back
const WANDER_R := 4       # cells around home a spawn point's creature roams
const WANDER_PACE := 0.5  # roaming and returning speed, as a fraction of its chase speed
const CALM := 2.0         # seconds after giving up during which it ignores the player
const PAUSE := Vector2(0.6, 2.8) # seconds between roaming steps: sometimes a stroll, sometimes a rest
const FIRST_PAUSE := Vector2(1.0, 3.0) # stands still a moment after PLAY starts, so it hatches in place
const SEARCH := 600       # cells a path search may visit before settling for the closest it found

var mode := Mode.ROAM
var home := Vector2i.ZERO
var area := Rect2i()       # where it roams
var roams := true          # false: a fixed instance, which holds its post
var cell := Vector2i.ZERO  # the cell it stands on, or is stepping into

var _creatures: Creatures
var _player: Player
var _body: Node2D
var _from := Vector2i.ZERO # the cell it is stepping out of, held until it lands
var _moving := false
var _goal := Vector2.ZERO
var _pace := 1.0
var _wait := 0.0
var _unseen := 0.0
var _calm := 0.0

func setup(creatures: Creatures, player: Player, at: Vector2i, roam_area: Rect2i, does_roam: bool) -> void:
	_creatures = creatures
	_player = player
	home = at
	cell = at
	area = roam_area
	roams = does_roam
	_wait = randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)

func _ready() -> void:
	_body = get_parent() as Node2D

func speed() -> float:
	return Bestiary.speed_of(String(_body.creature)) * (1.0 if mode == Mode.CHASE else WANDER_PACE)

func is_moving() -> bool:
	return _moving

func _physics_process(delta: float) -> void:
	if EditorMode.is_edit() or _body == null:
		return
	if _moving:
		_body.position = _body.position.move_toward(_goal, Grid.CELL * _pace * delta)
		if not _body.position.is_equal_approx(_goal):
			return
		_body.position = _goal
		_moving = false
		_creatures.release(_from, _body)
	think(delta)

# one decision tick: update the mode from what it can see, then act on it. Public so a test can drive it.
func think(delta: float) -> void:
	_calm = maxf(_calm - delta, 0.0)
	var pc := Grid.cell_of(_player.position)
	var sees := _calm <= 0.0 and can_see(pc)
	if mode != Mode.CHASE and sees:
		mode = Mode.CHASE
		_unseen = 0.0
		_wait = 0.0
		_alert("!")
	elif mode == Mode.CHASE:
		_unseen = 0.0 if sees else _unseen + delta
		if _dist(cell, pc) > LOSE or _unseen > FORGET or _dist(cell, home) > LEASH:
			mode = Mode.RETURN
			_calm = CALM
			_wait = 0.6 # a beat of confusion before it turns for home
			_alert("?")
	_wait -= delta
	if _wait > 0.0:
		return
	match mode:
		Mode.ROAM:
			_roam()
		Mode.CHASE:
			_chase(pc)
		Mode.RETURN:
			_return_home()

func _roam() -> void:
	_wait = randf_range(PAUSE.x, PAUSE.y)
	if not roams:
		return
	var dirs := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	dirs.shuffle()
	for d: Vector2i in dirs:
		var n := cell + d
		if area.has_point(n) and _creatures.can_enter(n, _body):
			_step(n)
			return

func _chase(pc: Vector2i) -> void:
	if _dist_grid(cell, pc) == 1:
		_face(pc - cell)
		_wait = 0.15 # alongside: this is where the attack goes in the next slice
		return
	var next := path_step(pc)
	if next == Grid.INVALID_CELL:
		_wait = 0.3
		return
	_step(next)

func _return_home() -> void:
	var back_in_area := roams and area.has_point(cell)
	if cell == home or back_in_area:
		mode = Mode.ROAM
		_wait = randf_range(PAUSE.x, PAUSE.y)
		return
	var next := path_step(home)
	if next == Grid.INVALID_CELL:
		mode = Mode.ROAM # cut off from home (a door shut, a wall built): settle where it is
		return
	_step(next)

func _step(to: Vector2i) -> void:
	_face(to - cell)
	_creatures.occupy(to, _body)
	_from = cell
	cell = to
	_goal = Grid.cell_center(to)
	_pace = speed()
	_moving = true

# the body is drawn facing right; mirror it to face left (up/down keep the last side)
func _face(d: Vector2i) -> void:
	if d.x != 0:
		_body.scale.x = -1.0 if d.x < 0 else 1.0

func _alert(glyph: String) -> void:
	if _body.has_method("alert"):
		_body.alert(glyph)

# --- sight ---

# can it see cell `pc` from where it stands: close enough, and no wall or closed door on the line
# between (see-through fences don't block it)
func can_see(pc: Vector2i) -> bool:
	if _dist(cell, pc) > SIGHT:
		return false
	for c in _line(cell, pc):
		if c == cell or c == pc:
			continue
		if _blocks_sight(c):
			return false
	return true

func _blocks_sight(c: Vector2i) -> bool:
	var obs := _creatures.get_node_or_null("../Obstacles") as Obstacles
	if obs == null:
		return false
	if obs.is_blocked(c):
		return not WallSegment.FENCE.has(obs.get_wall_material(c))
	if not obs.door_at(c).is_empty():
		for g in get_tree().get_nodes_in_group("gates"):
			if g.cell == c:
				return not g.is_open
	return false

# the cells on the straight line from a to b (Bresenham), both ends included
static func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var s := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var err := d.x - d.y
	var c := a
	while true:
		out.append(c)
		if c == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			c.x += s.x
		if e2 < d.x:
			err += d.x
			c.y += s.y
	return out

# --- paths ---

# the first step on a shortest walk from here toward `goal` (the goal cell itself may be occupied: it is
# where the player stands). If the goal can't be reached within SEARCH cells, heads for the reachable cell
# nearest to it instead, so a creature cut off by water still comes to the bank. INVALID_CELL = no move.
func path_step(goal: Vector2i) -> Vector2i:
	var prev := {cell: cell}
	var q: Array[Vector2i] = [cell]
	var best := cell
	var i := 0
	while i < q.size() and q.size() < SEARCH:
		var c := q[i]
		i += 1
		if _dist_grid(c, goal) < _dist_grid(best, goal):
			best = c
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if prev.has(n):
				continue
			if n == goal:
				prev[n] = c
				# step onto the goal if it's free (home); stop beside it if it isn't (the player)
				return _first_step(prev, n if _creatures.can_enter(n, _body) else c)
			if not _creatures.can_enter(n, _body):
				continue
			prev[n] = c
			q.append(n)
	if best == cell:
		return Grid.INVALID_CELL
	return _first_step(prev, best)

# walk the search tree back from `c` to the step right after the start
func _first_step(prev: Dictionary, c: Vector2i) -> Vector2i:
	if c == cell:
		return Grid.INVALID_CELL # the goal is right beside us: nothing to step onto
	while prev[c] != cell:
		c = prev[c]
	return c

static func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))

static func _dist_grid(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
