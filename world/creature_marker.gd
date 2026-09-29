extends Node2D

# One placed creature: the visual half of a creature record (the model lives in world/creatures.gd).
# No creature art exists yet, so the body is drawn procedurally from the definition's `body` glyph,
# exactly as pickups, walls, water and lava are until art arrives. Three starter shapes, each built
# to read at editor zoom rather than to be pretty: a squat wide FROG, a long-backed HORSE with a
# neck, and a round-headed MONKEY with a tail.
#
# THE TWO PLACEMENT KINDS LOOK DIFFERENT, because they mean different things (ROADMAP "Creature
# placement in the editor"):
#   SPAWN POINT -- in EDIT it is a MARKER: a dashed ground ring with the creature drawn ghosted above
#     it, saying "one of these appears here", not "one of these is here". In PLAY it hatches: the
#     ring goes and the creature is drawn solid.
#   FIXED INSTANCE -- always the creature, solid, in both modes. It IS here; that is its whole point.
# So the author can tell at a glance which cells are populated and which merely spawn, and pressing
# Play shows what the map will actually contain.
#
# RARITY uses the SHARED item scale (ROADMAP: one palette both reference), drawn as the same ring
# treatment pickups use -- dark backing first for contrast on any floor, then the tier colour at a
# width that steps up with rarity, so the tier reads without relying on hue alone.
#
# Per the standing convention it sets the floor-highlight mask bit and y-sorts like other ground
# objects, so the room highlight is excluded from it and walls occlude it correctly.

const CELL := Grid.CELL
const R := 9.0           # body radius; the rarity ring sits just outside it
const RING_R := 12.5
const PAD_R := 14.5      # the spawn-point ground pad: wider than the body, so it rings the FEET
const DARK := Color(0.05, 0.05, 0.08, 0.85)
const GHOST := 0.55      # alpha of an unhatched spawn-point creature, so it reads as "will appear"
const BOB := 1.2         # gentle idle bob, the same tell pickups use to catch the eye
const BOB_HZ := 0.9

var cell := Vector2i.ZERO
var creature := "frost_frog"
var kind := "spawn"
var id := ""
var blocks := true
var state := Bestiary.State.WILD # not saved yet: nothing changes it until capture (Phase C)

var _t := 0.0

func _ready() -> void:
	add_to_group("creatures")
	z_index = 6 # just above pickups (5); y-sorting orders it against the player and the walls
	visibility_layer |= FloorHighlightMask.MASK_BIT

func place(c: Vector2i) -> void:
	cell = c
	position = Grid.cell_center(c)
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

# a spawn point shows its authored marker only while authoring; in PLAY the creature has hatched
func _is_marker() -> bool:
	return kind == Bestiary.SPAWN_POINT and EditorMode.is_edit()

func _draw() -> void:
	var d := Bestiary.def(creature)
	if d.is_empty():
		return # a map placed a creature this build no longer defines: draw nothing rather than crash
	var marker := _is_marker()
	var lift := sin(_t * TAU * BOB_HZ) * BOB
	var c := Vector2(0, -R * 0.6 + lift)
	# contact shadow, so the lift reads as standing rather than as a mis-placed sprite
	draw_circle(Vector2(0, 2), R * 0.6, Color(0, 0, 0, 0.20))
	if marker:
		_draw_spawn_ring()
	else:
		# the rarity ring, same treatment as a pickup's: dark backing for contrast on any floor, then
		# the tier colour at its width. A spawn point wears its dashed ring instead.
		var w: float = Items.RARITY_WIDTH[clampi(Bestiary.rarity_of(creature), 0, Items.RARITY_WIDTH.size() - 1)]
		draw_arc(c, RING_R, 0.0, TAU, 28, DARK, w + 2.0)
		draw_arc(c, RING_R, 0.0, TAU, 28, Bestiary.rarity_color(creature), w)
	var tint: Color = d.get("tint", Color.WHITE)
	if marker:
		tint.a *= GHOST
	match String(d.get("body", "frog")):
		"horse": _draw_horse(c, tint)
		"monkey": _draw_monkey(c, tint)
		_: _draw_frog(c, tint)
	# a creature the author has made passable is an exception worth SEEING, not one buried in a panel:
	# a small hollow diamond over it says "the player walks through this one".
	if not blocks and EditorMode.is_edit():
		_draw_passable_pip(c)

# the spawn-point ground ring: dashed, to read as "a spot" rather than a solid thing standing here.
# Green is the editor's ADD colour, which is what a spawn point is -- a place something comes from.
# Drawn at the creature's FEET (wider than the body and centred on the contact shadow, not on the
# body's middle) so it reads as a pad the creature stands in; a render with it centred on the origin
# had the dashes cutting straight across the body.
func _draw_spawn_ring() -> void:
	const SEGS := 12
	var c := Vector2(0, 2)
	for i in SEGS:
		if i % 2 == 1:
			continue
		var a0: float = TAU * float(i) / SEGS
		var a1: float = TAU * float(i + 1) / SEGS
		draw_arc(c, PAD_R, a0, a1, 5, DARK, 3.5)
		draw_arc(c, PAD_R, a0, a1, 5, Color(0.35, 0.85, 0.40, 0.95), 1.75)

# --- the three starter bodies (ROADMAP "Initial monsters") ---

# squat and wide, sitting low, with two high eyes and folded back legs
func _draw_frog(c: Vector2, tint: Color) -> void:
	_blob(c + Vector2(0, R * 0.15), Vector2(R * 1.05, R * 0.72), tint)
	_blob(c + Vector2(-R * 0.62, R * 0.42), Vector2(R * 0.34, R * 0.24), tint.darkened(0.15))
	_blob(c + Vector2(R * 0.62, R * 0.42), Vector2(R * 0.34, R * 0.24), tint.darkened(0.15))
	_eye(c + Vector2(-R * 0.34, -R * 0.42))
	_eye(c + Vector2(R * 0.34, -R * 0.42))

# A horse has to read from a ~20px silhouette. Two renders taught what does and does not survive
# there: an UPRIGHT neck reads as a bird no matter how thick it is, and legs shorter than the body is
# tall vanish under the world's y-squash. What works is the horizontal profile -- a long low body, a
# neck angled FORWARD at roughly 45 degrees, a long muzzle, and a MANE, which is the cue nothing else
# in the roster has.
func _draw_horse(c: Vector2, tint: Color) -> void:
	var dark := tint.darkened(0.30)
	var mane := tint.darkened(0.45)
	# tail: a thick sweep off the rear
	draw_line(c + Vector2(-R * 1.00, -R * 0.20), c + Vector2(-R * 1.40, R * 0.50), mane, 3.4)
	# body: long and LOW, so the silhouette is wider than it is tall
	_blob(c + Vector2(-R * 0.22, R * 0.18), Vector2(R * 0.92, R * 0.40), tint)
	# legs, drawn long enough to clear the body's bottom edge under the y-squash
	for lx in [-R * 0.80, -R * 0.40, R * 0.10, R * 0.44]:
		draw_line(c + Vector2(lx, R * 0.35), c + Vector2(lx, R * 1.15), dark, 2.4)
	# neck: a wedge angled FORWARD, wide at the shoulder and narrowing into the head
	var neck := PackedVector2Array([
		c + Vector2(R * 0.20, -R * 0.10), c + Vector2(R * 0.62, R * 0.18),
		c + Vector2(R * 1.16, -R * 0.52), c + Vector2(R * 0.74, -R * 0.86)])
	draw_colored_polygon(neck, tint)
	draw_polyline(neck + PackedVector2Array([neck[0]]), DARK, 1.0)
	# the mane along the neck's upper edge -- the cue that says horse rather than any other quadruped
	draw_line(c + Vector2(R * 0.22, -R * 0.16), c + Vector2(R * 0.80, -R * 0.90), mane, 3.0)
	# head: a long muzzle running forward off the neck, level rather than raised
	_blob(c + Vector2(R * 1.20, -R * 0.72), Vector2(R * 0.44, R * 0.24), tint)
	_blob(c + Vector2(R * 1.52, -R * 0.62), Vector2(R * 0.16, R * 0.15), dark) # nose
	draw_line(c + Vector2(R * 0.92, -R * 0.92), c + Vector2(R * 0.86, -R * 1.22), tint, 2.0) # ear
	_eye(c + Vector2(R * 1.12, -R * 0.80), 0.85)

# round head on a smaller body, with a curled tail
func _draw_monkey(c: Vector2, tint: Color) -> void:
	_blob(c + Vector2(0, R * 0.42), Vector2(R * 0.62, R * 0.55), tint)
	_blob(c + Vector2(0, -R * 0.42), Vector2(R * 0.62, R * 0.58), tint)
	_blob(c + Vector2(-R * 0.72, -R * 0.45), Vector2(R * 0.22, R * 0.22), tint.darkened(0.15)) # ears
	_blob(c + Vector2(R * 0.72, -R * 0.45), Vector2(R * 0.22, R * 0.22), tint.darkened(0.15))
	draw_arc(c + Vector2(-R * 0.85, R * 0.55), R * 0.42, -PI * 0.5, PI * 0.9, 10, tint.darkened(0.2), 2.5)
	_eye(c + Vector2(-R * 0.24, -R * 0.48), 1.2)
	_eye(c + Vector2(R * 0.24, -R * 0.48), 1.2)

# --- drawing helpers ---

# a filled ellipse with a dark outline, the shared building block of all three bodies. Drawn as a
# polygon rather than a scaled circle so the outline stays an even width in the world's y-squash.
func _blob(c: Vector2, radii: Vector2, tint: Color) -> void:
	const SEGS := 18
	var pts := PackedVector2Array()
	for i in SEGS:
		var a: float = TAU * float(i) / SEGS
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, tint)
	draw_polyline(pts + PackedVector2Array([pts[0]]), DARK, 1.0)

func _eye(c: Vector2, scale := 1.0) -> void:
	draw_circle(c, 2.0 * scale, Color(0.97, 0.97, 1.0))
	draw_circle(c, 1.0 * scale, DARK)

# the "walks through this one" cue for a per-instance passability override
func _draw_passable_pip(c: Vector2) -> void:
	var p := c + Vector2(0, -RING_R - 5.0)
	var dia := PackedVector2Array([p + Vector2(0, -3.5), p + Vector2(3.0, 0),
		p + Vector2(0, 3.5), p + Vector2(-3.0, 0)])
	draw_polyline(dia + PackedVector2Array([dia[0]]), DARK, 2.5)
	draw_polyline(dia + PackedVector2Array([dia[0]]), Color(0.95, 0.95, 1.0, 0.9), 1.2)
