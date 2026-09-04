extends Node2D

# The map's AUTHORED player spawn, as a placeable marker (ROADMAP "Player spawn marker").
#
# Before this, a map's start point was wherever the character happened to STAND when the map was
# saved: authoring meant walking the player into position, and a stroll around in PLAY silently moved
# the start point. Now the spawn is its own thing. This node's position IS the spawn MapIO serializes
# (`spawn`), the Set Spawn tool moves it, and a map load drops the player on it. The character's live
# position is a separate concern that CharacterIO already owns, which is the split its header
# describes: "Maps store an authored spawn (MapIO); this stores where the player actually stands".
#
# Visible in EDIT, hidden in PLAY (it is editor chrome, like the tool strip). One per map: there is one
# node, so "one spawn per map" is structural rather than enforced.
#
# Drawn in World space, so it sits in the world's top/front perspective (the y-squash turns the ground
# ring into an ellipse, exactly like every other round thing in the world reads).

const CELL := 32

# Deliberately NOT one of the editor's role colours (orange ground / green add / red erase / purple
# walls / blue doors / yellow shadow): a neutral white-on-dark pennant reads on grass, wood, stone and
# snow alike and never gets confused with a hover or a selection.
const DARK := Color(0.06, 0.06, 0.09, 0.9)
const LIGHT := Color(1, 1, 1, 0.95)
const POLE_H := 26.0
const RING_R := 11.0

func _ready() -> void:
	z_index = 850 # above the world, below the editor cursors/ghosts (1000+)
	add_to_group("spawn_marker")
	visible = EditorMode.is_edit()
	EditorMode.changed.connect(func(_m): visible = EditorMode.is_edit())

# --- the spawn, in world pixels (the node's own position) ---

func spawn_position() -> Vector2:
	return position

func set_spawn(pos: Vector2) -> void:
	position = pos
	queue_redraw()

func spawn_cell() -> Vector2i:
	return Vector2i(floori(position.x / CELL), floori(position.y / CELL))

# put the spawn at the centre of `cell` (what the Set Spawn tool does with a click)
func set_cell(cell: Vector2i) -> void:
	set_spawn(Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0))

func _draw() -> void:
	# ground ring: marks the CELL the player will stand in, drawn dark-then-light so it reads on any floor
	draw_arc(Vector2.ZERO, RING_R, 0.0, TAU, 28, DARK, 3.5)
	draw_arc(Vector2.ZERO, RING_R, 0.0, TAU, 28, LIGHT, 1.5)
	# pole + pennant, so the marker is findable when zoomed out (a flat ring alone disappears)
	draw_line(Vector2.ZERO, Vector2(0, -POLE_H), DARK, 4.0)
	draw_line(Vector2.ZERO, Vector2(0, -POLE_H), LIGHT, 1.5)
	var flag := PackedVector2Array([
		Vector2(0.5, -POLE_H), Vector2(13, -POLE_H + 5.5), Vector2(0.5, -POLE_H + 11)])
	draw_colored_polygon(flag, LIGHT)
	draw_polyline(flag + PackedVector2Array([flag[0]]), DARK, 1.5)
