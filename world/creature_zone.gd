extends Node2D

# One spawn zone: a rectangular REGION flagged to periodically spawn a creature within it (ROADMAP
# "Creature placement in the editor" -> spawn zone/region, "for populating wild areas"). The model
# lives in world/creatures.gd; this is the visual.
#
# It is EDITOR CHROME, not world art: a zone is an authoring construct, so it draws in EDIT and hides
# in PLAY, where what you should see is the creatures it produced, not the box that produced them.
# (The same rule the tool strip and the player spawn marker follow.)
#
# Drawn as a translucent wash with a dashed border in the creature's own rarity colour, so a Rare
# zone and a Rare creature read as the same thing, and a label naming what it spawns and how many.
# The wash is deliberately faint: a zone can cover a large part of the map and must not bury the
# terrain being authored underneath it.

const CELL := 32
const DARK := Color(0.05, 0.05, 0.08, 0.85)
const DASH := 7.0   # px of dash, matched by an equal gap
const WASH_A := 0.10
const EDGE_A := 0.85

var rect := Rect2i(0, 0, 1, 1)
var creature := "frost_frog"
var rate := 4.0
var cap := 3
var id := ""
var preview := false # the live drag, before the zone is committed: no label, brighter edge

func _ready() -> void:
	add_to_group("creature_zones")
	# below the creatures (6) and pickups (5): a zone is the ground they stand on, not another object
	z_index = 2
	# Deliberately NOT tagged into the floor-highlight mask, unlike the creatures and pickups that
	# stand on the floor. That bit is for things which OCCLUDE the floor, so the room highlight is cut
	# around them; a zone is a translucent wash that hides nothing, and putting it in the mask pass
	# would let it corrupt the magenta key the highlight is keyed from.
	_refresh_visibility()
	EditorMode.changed.connect(func(_m): _refresh_visibility())

func _refresh_visibility() -> void:
	visible = EditorMode.is_edit()
	queue_redraw()

func configure(r: Rect2i, c: String, rt: float, cp: int, zid: String) -> void:
	rect = r
	creature = c
	rate = rt
	cap = cp
	id = zid
	queue_redraw()

func _px() -> Rect2:
	return Rect2(Vector2(rect.position) * CELL, Vector2(rect.size) * CELL)

func _draw() -> void:
	var r := _px()
	var col: Color = Bestiary.rarity_color(creature)
	draw_rect(r, Color(col.r, col.g, col.b, WASH_A if not preview else WASH_A * 1.6), true)
	_dashed_rect(r, col)
	if preview:
		return
	# the label says what it spawns and how many it keeps alive, so a zone is readable without
	# selecting it -- the whole point of authoring one is the rule, and the rule is invisible otherwise
	var font := ThemeDB.fallback_font
	var text := "%s  x%d" % [Bestiary.display_name(creature), cap]
	var pos := r.position + Vector2(4, 13)
	draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DARK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)

# a dashed border, drawn dark-then-colour so the edge reads on any floor, exactly as every other
# overlay in the editor does
func _dashed_rect(r: Rect2, col: Color) -> void:
	var corners := [r.position, r.position + Vector2(r.size.x, 0),
		r.position + r.size, r.position + Vector2(0, r.size.y)]
	for i in 4:
		_dashed_line(corners[i], corners[(i + 1) % 4], col)

func _dashed_line(a: Vector2, b: Vector2, col: Color) -> void:
	var span := a.distance_to(b)
	if span <= 0.0:
		return
	var dir := (b - a) / span
	var t := 0.0
	while t < span:
		var t2: float = minf(t + DASH, span)
		draw_line(a + dir * t, a + dir * t2, DARK, 3.0)
		draw_line(a + dir * t, a + dir * t2, Color(col.r, col.g, col.b, EDGE_A), 1.5)
		t += DASH * 2.0
