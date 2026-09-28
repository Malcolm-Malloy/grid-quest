extends Node2D

# Hover ghost for a clip that is about to land: the PASTE brush (Ctrl+V) and the MOVE drag both
# show the copied region floating over the cells it will occupy, so the drop is previewed before it
# commits (ROADMAP "Ctrl+V / duplicate arms a paste brush that shows the copied block as a hover
# preview", and the Move tool's "hover/drop-preview shows the destination before release").
#
# Reuses the language of the other placement ghosts: the content is lifted a few px off the ground
# with a contact shadow (terrain_preview.gd) and the footprint is outlined in the ADD-green of the
# coloured-highlight palette (paint_cursor.gd). Cells that would be CLIPPED -- off the map or on an
# absent-cell hole -- are outlined in ERASE-red instead, so the edge case reads before the click.
#
# Drawn in World space as a child of FloorManager, above the paint cursor like the other previews.

const CELL := Grid.CELL
const HALF := Grid.HALF
const LIFT := 6.0
const SHADOW := Color(0, 0, 0, 0.18)
const OK_FILL := Color(0.25, 0.85, 0.35, 0.16)   # ADD green (a cell that will land)
const OK_LINE := Color(0.25, 0.85, 0.35, 0.95)
const BAD_FILL := Color(0.95, 0.15, 0.15, 0.16)  # ERASE red (a cell that will be clipped)
const BAD_LINE := Color(0.95, 0.15, 0.15, 0.85)
const STRUCT := Color(0.34, 0.34, 0.38, 0.85)    # a wall/door in the clip, as a lifted block
const CONTENT_ALPHA := 0.8

var _clip := {}
var _origin := Vector2i.ZERO
var _clip_id := -1     # caller-supplied id, bumped whenever the pending clip changes (rotate/flip/new
					   # copy), so a still hover redraws nothing while a transformed clip redraws once
var _shown := false
var _tex_fn: Callable  # (material: String, pattern: int) -> Texture2D, from FloorManager
var _ok_fn: Callable   # (cell: Vector2i) -> bool: would this cell land, or be clipped?

func _ready() -> void:
	z_index = 1300 # above the terrain drop-preview (1200), which is above the paint cursor (1000)

func setup(tex_fn: Callable, ok_fn: Callable) -> void:
	_tex_fn = tex_fn
	_ok_fn = ok_fn

# show `clip` (identified by `id`, see _clip_id) with its bounding box's top-left at cell `origin`
func show_clip(clip: Dictionary, origin: Vector2i, id: int) -> void:
	if clip.is_empty():
		hide_clip()
		return
	if _shown and _origin == origin and _clip_id == id:
		return # same ghost in the same place: nothing to redraw
	_clip = clip
	_clip_id = id
	_origin = origin
	_shown = true
	queue_redraw()

func hide_clip() -> void:
	if not _shown:
		return
	_shown = false
	_clip = {}
	queue_redraw()

func _draw() -> void:
	if not _shown or _clip.is_empty():
		return
	# 1. the footprint: a contact shadow on the ground plus a green (or red, where it clips) outline
	var ok_cells := {}
	for a in _clip.get("cells", []):
		var cell := _origin + Vector2i(int(a[0]), int(a[1]))
		var r := Grid.cell_rect(cell)
		var lands: bool = _ok_fn.is_null() or _ok_fn.call(cell)
		if lands:
			ok_cells[cell] = true
		draw_rect(r, SHADOW, true)
		draw_rect(r, OK_FILL if lands else BAD_FILL, true)
		draw_rect(r, OK_LINE if lands else BAD_LINE, false, 1.0)
	# 2. the clip's floor, lifted: each quarter drawn with its material texture at the destination's
	# tile phase, so the ghost shows the exact pixels that will land
	var tints := {}
	for a in _clip.get("floor_tints", []):
		tints[Vector2i(int(a[0]), int(a[1]))] = Color(float(a[2]), float(a[3]), float(a[4]))
	var patterns := {}
	for a in _clip.get("floor_patterns", []):
		patterns[Vector2i(int(a[0]), int(a[1]))] = int(a[2])
	for a in _clip.get("quads", []):
		var rel := Vector2i(int(a[0]), int(a[1]))
		var q := Vector2i(_origin.x * 2 + rel.x, _origin.y * 2 + rel.y)
		if not ok_cells.has(Grid.cell_of_quad(q)):
			continue
		var ground := Grid.quad_rect(q)
		var tex: Texture2D = _tex_fn.call(String(a[2]), patterns.get(rel, 0)) if not _tex_fn.is_null() else null
		if tex == null:
			continue
		var tint: Color = tints.get(rel, Color.WHITE)
		draw_texture_rect_region(tex, Rect2(ground.position - Vector2(0, LIFT), ground.size),
			GridBackground.tiled_src(ground), Color(tint.r, tint.g, tint.b, CONTENT_ALPHA))
	# 3. structures in the clip (walls, doors, bridges) as lifted blocks: the real art is derived from
	# neighbours at build time, so the ghost marks WHERE they land rather than faking their shape
	for key in ["walls"]:
		for a in _clip.get(key, []):
			_draw_struct(_origin + Vector2i(int(a[0]), int(a[1])), ok_cells)
	for key in ["doors", "bridges"]:
		for r in _clip.get(key, []):
			_draw_struct(_origin + Vector2i(int(r["cell"][0]), int(r["cell"][1])), ok_cells)

func _draw_struct(cell: Vector2i, ok_cells: Dictionary) -> void:
	if not ok_cells.has(cell):
		return
	var r := Rect2(cell.x * CELL, cell.y * CELL - LIFT, CELL, CELL)
	draw_rect(r, STRUCT, true)
	draw_rect(r, OK_LINE, false, 1.0)
