class_name Minimap
extends CanvasLayer

# The PLAY-mode minimap (ROADMAP "Minimap"): a square window of the map around the player, top-right
# under the Play/Exit buttons. It shows boundaries and nearby life, not everything:
#
#   Outdoors: the ground, liquids (rivers, lava), free-standing walls and fences, the map's edge, and
#             every building as one solid block (no interior walls).
#   Indoors:  only the building you are in, its rooms, walls and doors; everything outside greys out.
#
# "A building" and "inside" mean exactly what they mean for roofs (Roofs.piece_at / buildings()), so the
# minimap switches to the interior at the same moment the roof fades. A fenced pen is not a building, so
# standing in a paddock keeps the outdoor view.
#
# Creatures in the window are dots coloured by their state (Bestiary.STATE_COLORS); indoors, only the
# ones inside with you. The player is the white dot in the centre, with a nub showing which way they face.
#
# The terrain is baked to a tiny image (one pixel per cell) whenever the player changes cell or the layout
# changes, and drawn scaled up; only the dots are drawn every frame. The window scrolls smoothly with the
# player's exact position, not in whole-cell jumps.

const VIEW := 30          # cells across the window
const PX := 6             # screen pixels per cell
const SIZE := VIEW * PX
const BAKE := VIEW + 2    # cells across the baked image: one spare ring for the sub-cell scroll
const TOP := 46           # clear of the Play/Exit row above it
const MARGIN := 8

const OFF_MAP := Color(0.07, 0.07, 0.09)
const GROUND := Color(0.29, 0.44, 0.27)
const WATER := Color(0.24, 0.45, 0.78)
const LAVA := Color(0.88, 0.36, 0.14)
const WALL := Color(0.80, 0.80, 0.78)    # a free-standing wall or fence, outdoors
const BUILDING := Color(0.62, 0.55, 0.45)
const IN_FLOOR := Color(0.78, 0.74, 0.66)
const IN_WALL := Color(0.24, 0.24, 0.27)
const IN_DOOR := Color(0.62, 0.42, 0.22)
const GREYED := Color(0.30, 0.30, 0.32)  # the outdoors, seen from inside
const BORDER := Color(0.0, 0.0, 0.0, 0.85)
const PLAYER := Color(1, 1, 1)
const LIQUID_COLORS := {"water": WATER, "lava": LAVA}

@onready var _player: Player = get_node("../World/Player")
@onready var _topo: RoomTopology = get_node("../World/RoomTopology")
@onready var _roofs: Roofs = get_node("../World/Roofs")
@onready var _grid: GridBackground = get_node("../World/GridBackground")
@onready var _fm: FloorManager = get_node("../World/FloorManager")

var _view: Control
var _img: Image                       # the last bake, one pixel per cell (kept for reads; the GPU copy is _tex)
var _tex: ImageTexture
var _origin := Vector2i.ZERO          # the cell at the baked image's top-left pixel
var _baked_at := Grid.INVALID_CELL    # the player cell the image was baked for
var _inside: Roofs.RoofPiece          # the building the image was baked for (null = outdoors)
var _dirty := true                    # the layout changed since the last bake

func _ready() -> void:
	layer = 8 # with the status bar: above the world, below the mode toggle
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_view.offset_left = -MARGIN - SIZE
	_view.offset_right = -MARGIN
	_view.offset_top = TOP
	_view.offset_bottom = TOP + SIZE
	_view.clip_contents = true
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_view)
	add_child(_view)
	_topo.rebuilt.connect(_mark_dirty)
	EditorMode.changed.connect(func(_m: int) -> void:
		_mark_dirty()
		_refresh_visible())
	_refresh_visible()

func _mark_dirty() -> void:
	_dirty = true

func _refresh_visible() -> void:
	visible = EditorMode.is_play()

func _process(_delta: float) -> void:
	if not visible:
		return
	var pc := Grid.cell_of(_player.position)
	if _dirty or pc != _baked_at or _roofs.piece_at(pc) != _inside:
		_bake(pc)
	_view.queue_redraw()

# what the minimap shows at cell `c`, given the building the player is in (null = outdoors)
func cell_color(c: Vector2i, inside: Roofs.RoofPiece, buildings: Dictionary) -> Color:
	if not _grid.cell_present(c.x, c.y):
		return OFF_MAP
	if inside != null:
		if not inside.cells.has(c):
			return GREYED
		if _topo.is_wall(c):
			return IN_WALL
		return IN_DOOR if _topo.is_door(c) else IN_FLOOR
	if buildings.has(c):
		return BUILDING
	if _topo.is_wall(c):
		return WALL
	for q in Grid.quads_of(c):
		var mat := _fm.material_at(q)
		if LIQUID_COLORS.has(mat):
			return LIQUID_COLORS[mat]
	return GROUND

# bake one pixel per cell for a BAKE-cell square around `pc`: the spare ring covers the sub-cell scroll,
# so the window's edge never shows a gap
func _bake(pc: Vector2i) -> void:
	_dirty = false
	_baked_at = pc
	_inside = _roofs.piece_at(pc)
	var buildings := {}
	if _inside == null:
		for b in _roofs.buildings():
			buildings.merge(b)
	_origin = pc - Vector2i(BAKE, BAKE) / 2
	_img = Image.create(BAKE, BAKE, false, Image.FORMAT_RGBA8)
	for x in BAKE:
		for y in BAKE:
			_img.set_pixel(x, y, cell_color(_origin + Vector2i(x, y), _inside, buildings))
	if _tex != null:
		_tex.update(_img)
	else:
		_tex = ImageTexture.create_from_image(_img)

# where World point `p` lands in the window (the player's exact position is the centre)
func _to_view(p: Vector2) -> Vector2:
	return (p - _player.position) / Grid.CELL * PX + Vector2(SIZE, SIZE) / 2.0

func _draw_view() -> void:
	if _tex == null:
		return
	var top_left := _to_view(Vector2(_origin * Grid.CELL))
	_view.draw_texture_rect(_tex, Rect2(top_left, _tex.get_size() * PX), false)
	# creatures: indoors, only the ones in here with you
	var bounds := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	for n in get_tree().get_nodes_in_group("creatures"):
		var cm := n as Node2D
		if cm == null or not cm.visible:
			continue
		if _inside != null and not _inside.cells.has(Grid.cell_of(cm.position)):
			continue
		var at := _to_view(cm.position)
		if not bounds.has_point(at):
			continue
		var state: int = cm.get("state") if cm.get("state") != null else Bestiary.State.WILD
		_view.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Color.BLACK)
		_view.draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), Bestiary.STATE_COLORS[state])
	# the player, with a nub on the side they face
	var c := Vector2(SIZE, SIZE) / 2.0
	_view.draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color.BLACK)
	_view.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), PLAYER)
	var nub: Vector2 = [Vector2(0, 5), Vector2(0, -5), Vector2(-5, 0), Vector2(5, 0)][_player.facing]
	_view.draw_rect(Rect2(c + nub - Vector2(1, 1), Vector2(2, 2)), PLAYER)
	_view.draw_rect(bounds, BORDER, false, 2.0)
