extends Node2D

# The ground/floor layer. Material is stored per 16px quarter (a cell is four quarters), so
# floors can be authored at room, cell or quarter grain. Any quarter can be grass (default),
# wood, concrete, tile or carpet. grid_background and shadow_manager read the fills from here,
# so a styled floor draws under the same lighting/shadow system as grass and fills a room up to
# its walls. The material roster will grow over time.
#
# Authoring: the active MODE is chosen on the tool strip (Magic Wand / Cell Selector / Fine Details /
# Erase, see the Mode enum below); the right-click popup is purely contextual, listing floor
# MATERIALS, wall COLOURS and the Grid toggle. Picking a material/colour applies it to the target.
#   - Cell Selector / Fine Details paint the ground at cell / quarter grain on click and drag; Erase
#     removes topmost-first: a click first deletes the wall/door on the cell (the structure layer),
#     and only once no structure remains does a further click write grass over the terrain. Any
#     in-bounds cell is paintable, walls included; while the cursor is over a wall/door, that
#     obstacle fades to 30% so the ground under it stays visible.
#   - Magic Wand builds a click-to-grow selection (floor patch -> whole room; wall run -> building);
#     the marching-ants overlay draws it, and picking a material/colour then fills the whole
#     selection. With no selection, a floor material fills the clicked room and a wall colour the
#     clicked building (the old right-click-to-fill behaviour). Natural resets a wall to bare stone.
#
# A styled floor is static: it fills up to its walls/doors and does NOT flow through an open
# door. Hovering a room shows a red highlight of the floor the player can actually see; that is
# rendered by FloorHighlightMask (a render mask, not geometry), so it stays pixel-exact under
# walls, doors, the player and any object on the floor.
#
# The reference grid is off by default and toggled from the popup (a check item). When on,
# grid_background and shadow_manager draw the grid in GRID_COLOR instead of leaving it off.

const CELL := 32
const HALF := 16 # a quarter is 16px; a cell is four independently-set quarters

# reference grid: a distinct-but-restrained blue, toggled from the menu (off by default)
const GRID_ID := 100
# right-click-menu ACTION ids (single items, not swatch ranges). All < 300 so they are matched by
# explicit equality in _on_menu_id BEFORE the range branches (and before the MENU-index fallthrough).
const ERASE_ID := 101       # erase the selection if one exists, else the clicked target
const BUILD_WALL_ID := 102  # build a wall on the clicked (empty) cell
const BUILD_DOOR_ID := 103  # build a door on the clicked (empty) cell
const DOOR_FLIP_ID := 104   # flip a door's orientation
const DOOR_OPEN_ID := 105   # toggle a door's open-by-default
const DOOR_SWING_ID := 106  # toggle a door's swing side
const GRID_COLOR := Color(0.38, 0.64, 0.95, 0.4)

# authoring modes, selected from the persistent tool strip (ui/tool_strip.gd), no longer the popup:
#   WAND  - Magic Wand: click-to-grow selection (floor patch -> whole room; wall run -> building),
#           then pick a material/colour from the right-click menu to fill the whole selection.
#   CELL  - Cell Selector: paint one 32px cell.
#   FINE  - Fine Details: paint one 16px quarter.
#   ERASE - remove topmost-first: click deletes the wall/door on the cell (structure layer) first,
#           then a further click erases the floor material of the cell back to grass.
#   WALL  - add a wall on the clicked cell; drag to draw a wall line. Re-enclosing a room flips it
#           back to indoors (the inverse of ERASE opening a room), free via the MapIO rebuild.
#   DOOR  - add a door on the clicked cell (a wall there becomes a doorway). Orientation auto-follows
#           the wall run it bridges; R flips the default used when placing in open space.
#   SELECT- click a door or wall to load it into the properties inspector (no map edit itself).
#   BRIDGE- add a crossable bridge deck on the clicked water cell. Orientation auto-follows the water
#           run it spans (a horizontal river gets a N-S bridge); R flips the default in open space.
# Cell/Fine/Erase paint directly on click/drag; Wand builds a selection the menu then fills. See
# ROADMAP "Authoring surface" (mode rename), "Applying edits to a selection" and "Wall editing".
# NOTE: BRIDGE is appended LAST so existing Mode indices stay stable (tool_strip.M_* mirrors this).
enum Mode { WAND, CELL, FINE, ERASE, WALL, DOOR, SELECT, BOX, BRIDGE, MOVE }

# each material maps to an ARRAY of pattern variants (index 0 = default, matches the pre-pattern
# single texture). The active pattern per quarter is stored in _quad_pattern (parallel to _quad_mat /
# _quad_tint), so pattern is an axis distinct from material and colour. A stale pattern index (e.g. a
# quarter that was herringbone wood, then painted concrete) is clamped to the material's range at draw.
var textures := {
	# grass is the base terrain, now a real material so it can carry PATTERNS. Index 0 (Plain) is the
	# ground-grass tile (used for the Brush preview); in _rebuild Plain draws NOTHING so the base ground
	# shows through with no patch seam. Wild/Tuft are ALPHA overlays of extra blades drawn over the base.
	"grass": [preload("res://world/ground_grass.png"), preload("res://floors/grass_wild.png"), preload("res://floors/grass_tuft.png")],
	"wood": [preload("res://floors/wood_floor.png"), preload("res://floors/wood_diagonal.png")],
	"concrete": [preload("res://floors/concrete_floor.png")],
	"tile": [preload("res://floors/tile_floor.png"), preload("res://floors/tile_diamond.png")],
	"carpet": [preload("res://floors/carpet_floor.png"), preload("res://floors/carpet_argyle.png")],
	# outdoor natural terrains (walkable) that AUTO-MATCH: they feather into lower-precedence naturals
	# via the shared edge autotile (see TERRAIN_RANK / EDGE_ATLAS below), so grass/sand/snow blend.
	"sand": [preload("res://floors/sand.png")],
	"snow": [preload("res://floors/snow.png")],
	# water + lava are the IMPASSABLE "liquids" (see IMPASSABLE / LIQUID_SHORE): still, tintable tiles that
	# shimmer and grow a feathered shore. Lava works just like water but is its OWN material, so wooden
	# bridges cannot be built over it (see _place_bridge_at).
	"water": [preload("res://floors/water_still.png")],
	"lava": [preload("res://floors/lava_still.png")],
}
# human names for each material's pattern variants, aligned by index with `textures`. Drives the
# per-material Pattern submenu (rebuilt per right-click from the clicked quarter's material).
const PATTERN_NAMES := {
	"grass": ["Plain", "Wild", "Tuft"],
	"wood": ["Planks", "Diagonal"],
	"concrete": ["Plain"],
	"tile": ["Square", "Diamond"],
	"carpet": ["Solid", "Argyle"],
	"sand": ["Sand"],
	"snow": ["Snow"],
	"water": ["Still"],
	"lava": ["Still"],
}
# the grass base, so a quarter that carries a floor TINT but no material still draws (a tinted
# patch of grass): _rebuild emits it as a tinted grass fill. Matches grid_background/shadow_manager.
const GRASS := preload("res://world/ground_grass.png")

# popup id -> [label, material]; "" is the grass base (the eraser)
const MENU := [
	["Grass", "grass"], ["Wood", "wood"], ["Concrete", "concrete"], ["Tile", "tile"], ["Carpet", "carpet"],
	["Sand", "sand"], ["Snow", "snow"], ["Water", "water"], ["Lava", "lava"],
]

# floor materials that BLOCK the player. Today only walls/gates block (obstacles.is_blocked, which
# every editor tool reads as "is a wall"); water is the first FLOOR that blocks, so the check lives
# here (is_cell_impassable) and is consulted separately by the player, NOT folded into is_blocked.
const IMPASSABLE := {"water": true, "lava": true}

# River-bank auto-edge: the surrounding tile-quarters of water auto-render a brown, WALKABLE bank
# texture that outlines every body of water regardless of the neighbouring terrain. It is DERIVED
# in _rebuild (never stored in _quad_mat), so it is not saved, needs no editing, and stays passable
# (is_cell_impassable only counts _quad_mat water quarters, so a bank quarter never blocks). The
# first concrete case of the Ground-layer phase-2 auto-matching / better-edging system.
const RIVER_BANK := preload("res://floors/river_bank.png")
const BANK_AROUND := {"water": true, "lava": true} # materials whose non-matching quarter-neighbours become bank
# The river bank is now a per-body SWITCH (set before laying a liquid): a liquid quarter painted with the
# bank OFF is recorded in _quad_no_bank, and both the derived ring (_bank_quads) and the shore underlay
# skip it, so that body has no brown bank. Default ON, matching older maps (no _quad_no_bank entries).

# Shoreline autotile (feathered beach): a water quarter that touches LAND on an orthogonal side draws
# a per-configuration variant whose blue feathers into a wavy, foam-fringed transparent edge, so a body
# reads as an organic shore rather than a blue grid. Purely visual: the quarter stays material "water"
# in _quad_mat, so collision (is_cell_impassable) is unchanged. WATER_SHORE is a 4x4 atlas of 32px tiles
# indexed by a 4-bit LAND mask (N=1 E=2 S=4 W=8); tile 0 (open water) is never used here (mask 0 keeps
# the flat, seamless, world-tiled tile). Under a shore quarter we lay the brown bank first so the feather
# reveals wet sand, extending the dry river-bank ring (RIVER_BANK) onto the water side.
const WATER_SHORE := preload("res://floors/water_shore.png")
const LAVA_SHORE := preload("res://floors/lava_shore.png")
const SHORE_TILE := 32 # one atlas cell is 32px (drawn stretched into the 16px quarter)
# the feathered shore atlas per LIQUID (water/lava). A liquid quarter renders through the shoreline branch
# in _rebuild (bank underlay + this atlas), NOT the EDGE_ATLAS auto-match path. Both shimmer.
const LIQUID_SHORE := {"water": WATER_SHORE, "lava": LAVA_SHORE}

# Auto-matching (ground-layer phase 2, item 8): OUTDOOR natural terrains blend where they meet, using
# the SAME feathered edge autotile the water shoreline pioneered. Each natural has a PRECEDENCE rank;
# a higher-rank terrain feathers its edge over any orthogonally-adjacent LOWER-rank natural, revealing
# it through the wavy transparent edge (an underlay draws the revealed terrain when it is not the grass
# base). Grass is the base (rank 0, material ""); water sits at the top and keeps its own shoreline
# branch (it also lays a brown bank underlay, unlike the dry naturals). INDOOR/constructed materials
# (wood/concrete/tile/carpet) are absent from this table, so they never auto-match: a hard edge is
# correct for a rug or a wood floor. A quarter's stored material is unchanged, so collision/save are too.
const TERRAIN_RANK := {"": 0, "grass": 0, "sand": 1, "snow": 2, "water": 99, "lava": 99}
# the feathered edge atlas per auto-matching terrain (4x4 of 32px cells, same layout as WATER_SHORE).
# Water is NOT here: it renders through the dedicated shoreline branch (bank underlay + WATER_SHORE).
const EDGE_ATLAS := {
	"sand": preload("res://floors/sand_edge.png"),
	"snow": preload("res://floors/snow_edge.png"),
}

# floor patterns: a per-quarter pattern index into the material's `textures` variant array, separate
# from the colour tint. Menu id is PATTERN_BASE_ID + index. Base is 700 so it sits above every other
# id range and is matched FIRST in _on_menu_id. The submenu is rebuilt per right-click (material-aware).
const PATTERN_BASE_ID := 700

# wall materials (the face/cap texture pair, separate from the colour tint). Stone is the default.
# Menu id is WALL_MAT_BASE_ID + index. Base is 600 so it sits above every other id range (floor 0-4,
# scopes 200+, walls 300+, floor colours 400+, picker 500), and is matched BEFORE them in _on_menu_id.
const WALL_MAT_BASE_ID := 600
const WALL_MATERIALS := [
	["Stone", "stone"], ["Wood", "wood"], ["Slate", "slate"], ["Brick", "brick"], ["Hedge", "hedge"],
	# see-through fences (short, gappy; rendered procedurally in wall_segment). Same colour-tint system.
	["Wood Fence", "wood_fence"], ["Metal Bars", "metal_bars"], ["Chainlink", "chainlink"],
]
# the cap (top-face) texture per wall material, for the Brush panel's wall preview swatch. Mirrors
# WallSegment.MATERIALS (kept in sync); the panel shows the cap tinted by the armed wall colour.
const WALL_TEX := {
	"stone": preload("res://world/stone_cap.png"),
	"wood": preload("res://world/wood_cap.png"),
	"slate": preload("res://world/slate_cap.png"),
	"brick": preload("res://world/brick_cap.png"),
	"hedge": preload("res://world/hedge_cap.png"),
	# fences have no cap texture (drawn procedurally); these icons are just the Brush-panel/inspector swatch.
	"wood_fence": preload("res://floors/wood_fence_icon.png"),
	"metal_bars": preload("res://floors/metal_bars_icon.png"),
	"chainlink": preload("res://floors/chainlink_icon.png"),
}

# wall colours (a tint over the stone). Natural = white = reset. Menu id is WALL_BASE_ID + index.
const WALL_BASE_ID := 300
const WALL_COLORS := [
	["Natural", Color.WHITE],
	["Red", Color(0.85, 0.3, 0.28)],
	["Green", Color(0.42, 0.72, 0.42)],
	["Blue", Color(0.4, 0.55, 0.85)],
	["Yellow", Color(0.9, 0.82, 0.35)],
	["Orange", Color(0.9, 0.58, 0.3)],
	["Purple", Color(0.66, 0.45, 0.8)],
]

# floor colours: a multiply TINT over whatever texture (or grass) is at the quarter, parallel to
# WALL_COLORS. Natural = white = reset (erases the tint). Menu id is FLOOR_COLOR_BASE_ID + index.
# Slice 1 = the 8 fixed "fun" swatches; slice 2 adds the full colour PICKER (arbitrary tint, below).
# Still deferred: the 8 material-aware swatches (a per-material colour table; wants a design pass).
# The colour values match WALL_COLORS where they overlap so the two palettes read as one system.
const FLOOR_COLOR_BASE_ID := 400
const FLOOR_PICKER_ID := 500 # "Custom..." opens the colour picker; checked before the 400+ swatches
const FLOOR_COLORS := [
	["Natural", Color.WHITE],
	["Red", Color(0.85, 0.3, 0.28)],
	["Orange", Color(0.9, 0.58, 0.3)],
	["Yellow", Color(0.9, 0.82, 0.35)],
	["Green", Color(0.42, 0.72, 0.42)],
	["Blue", Color(0.4, 0.55, 0.85)],
	["Purple", Color(0.66, 0.45, 0.8)],
	["Pink", Color(0.9, 0.55, 0.7)],
	# Grey culled 2026-08-23: a grey tint over the greyscale bases just darkens them (no hue), so it read
	# as a muddy near-duplicate of Natural. Existing grey-tinted floors still render (tints store raw Color).
]

# emitted whenever the armed floor brush changes (material, armed flag, tool kind, or colour), so the
# persistent left-panel Brush inspector (tool_strip.gd) can highlight the active material + colour live.
signal brush_changed
# emitted whenever the selection changes (floor/wall/none), so the panel can surface the matching
# section (a wall selection opens the Wall section, a floor selection the Brush section). Fires even
# when the reflected brush values did not change, unlike brush_changed.
signal selection_changed

@onready var room_light = get_node("../RoomLight")

# Storage is per 16px quarter: _quad_mat is the SOURCE OF TRUTH (what MapIO saves). Everything
# else is derived in _rebuild. A room fill (set_room_style) just writes all four quarters of every
# cell in the room, so nothing built on the old per-room model breaks.
var _quad_mat := {}   # quarter coord (Vector2i, 16px grid) -> material name; the whole floor
var _quad_tint := {}  # quarter coord (Vector2i, 16px grid) -> Color; a multiply tint over the floor.
					  # Parallel to _quad_mat and also SOURCE OF TRUTH (MapIO saves it). White/absent
					  # = no tint. A quarter may carry a tint with no material (a tinted grass patch).
var _quad_pattern := {} # quarter coord (Vector2i, 16px grid) -> int pattern index into the material's
					  # `textures` variant array. Parallel to _quad_mat and also SOURCE OF TRUTH (MapIO
					  # saves it). Absent / 0 = the default pattern. Only meaningful with a material.
var _quad_no_bank := {} # LIQUID quarter coords (Vector2i, 16px grid) painted with the bank switch OFF.
					  # SOURCE OF TRUTH (MapIO saves it). Absent = bank ON (default). Both the derived bank
					  # ring and the shore underlay skip these, so that body has no brown river bank.
var _base_fills: Array = [] # [Rect2, Texture2D, Color, (src_override), (animate)], one per painted/tinted
							# quarter. A 4th element overrides the sampled src rect (shoreline atlas); a 5th
							# truthy element flags an ANIMATED water fill (grid_background shimmers it).
var _has_water := false # any water fill emitted this _rebuild, so grid_background knows to run the shimmer
var _menu: PopupMenu
var _pending := Vector2.ZERO # local (World-space) position of the last right-click, for the menu
var _tool_kind := "floor"    # "floor" (paint _brush), "wall" (colour _wall_color), "wall_mat" (material
							 # _wall_mat) or "floor_color" (tint _floor_color)
var _brush := "wood"         # active floor material ("" = grass eraser)
var _armed := false          # Cell/Fine only: is a material armed to drop? Cleared on entering Cell/
							 # Fine so the mode never starts placeable; set true when a material is picked
							 # from the Floor Textures menu. Until then Cell/Fine show no drop-preview and
							 # a click places nothing (the user selects a material first).
var _wall_color := Color.WHITE # active wall colour tint (white = natural / reset)
var _wall_mat := "stone"     # active wall material ("stone" = default)
var _pattern := 0            # active floor pattern index (for the "pattern" tool drag)
var _bank_on := true         # river-bank switch: when a LIQUID (water/lava) is painted, its quarters get a
							 # brown bank ring iff this is on. Set from the Brush panel BEFORE laying; only
							 # affects quarters painted while it is on/off (stored per quarter in _quad_no_bank).
# The armed wall brush is UNIFIED: _wall_color / _wall_mat above are BOTH the colour/material that
# recolour an existing wall (a selection, or a clicked wall) AND the ones Wall-mode placement stamps onto
# each NEW wall it lays. So picking a wall colour/material in the left Brush panel (or the right-click
# "Build Wall" configurator) applies to whatever you build next, exactly like the floor brush. White/stone
# = natural, so a plain wall stays plain.
var _build_wall_sub: PopupMenu # the Build Wall configurator (colour + material + Start), built in _ready
var _floor_color := Color.WHITE # active floor tint (white = natural / reset the tint)
var _picker_popup: PopupPanel   # the "Custom..." floor-colour picker popup
var _color_picker: ColorPicker  # its ColorPicker (live-previews the tint as you drag)
var _picker_applied := false    # a preview was applied during the current picker session (commit on close)
var _suppress_picker := false   # guard so setting the picker's start colour doesn't count as an edit
var _mode: Mode = Mode.WAND  # active authoring mode (set by the tool strip)
var _door_orient := "horizontal" # DOOR mode: orientation used when the cell has no wall run (R flips)
var _bridge_orient := "horizontal" # BRIDGE mode: orientation used when the water run is ambiguous (R flips)
var _painting := false       # true while the left button is held, for drag painting
var _walls_dirty := false    # a wall drag added cells this frame; rebuild ONCE in _process instead of
							 # per motion event (a full map rebuild per cell stutters, see "Investigate lag")
# Box-select (Mode.BOX): drag a rectangle to select every quarter inside it, regardless of material or
# room. Combines with the current selection per the drag-start modifier (Shift add / Alt subtract).
var _box_active := false      # true while a box drag is in progress
var _box_start := Vector2i.ZERO # the cell the drag began on
var _box_op := "replace"      # "replace" / "add" / "subtract", captured from the modifier at press
var _box_base := {}           # selection quads snapshot at drag start (the base add/subtract build on)
var _cursor: Node2D          # the Cell/Fine square paint cursor (see paint_cursor.gd)
var _preview: Node2D         # the lifted terrain drop-preview sprite (see terrain_preview.gd)
var _bridge_preview: Node2D  # the lifted BRIDGE deck preview (bridge.gd in preview mode), BRIDGE mode only
const WallSegmentScript := preload("res://world/wall_segment.gd")
var _wall_ghost: Array = []  # up to 2 reused translucent wall_segments: the shape a WALL-mode click would
							 # place (horizontal/vertical/corner/T/cross), in the armed wall colour+material
var _wall_ghost_key := ""    # dedupe: cell + colour + material + piece-count, so the ghost only re-configs on change
var _door_preview: Node2D    # the lifted DOOR ghost (gate.gd in preview mode), DOOR mode only
var _door_ghost_key := ""    # dedupe the door ghost by cell + orientation
var _selection: Node2D       # marching-ants selection overlay (see selection_overlay.gd)
var _clip_ghost: Node2D      # hover ghost for an armed paste / an in-flight move (clip_preview.gd)
# --- copy / paste / move: the ARMED clip and the gesture that will drop it (ROADMAP "Copy, paste,
# and duplicate" + "Move tool"). One pending-clip state serves both, so the ghost, the rotate/flip
# keys and the drop all have a single code path; only how the origin is computed differs.
var _pending_clip := {}          # the clip about to land ({} = nothing armed)
var _pending_kind := ""          # "paste" (armed by Ctrl+V, drops on click) or "move" (drag in MOVE mode)
var _pending_id := 0             # bumped on every arm/rotate/flip so the ghost knows to redraw
var _pending_changed := false    # the pending clip was rotated/flipped (so a zero-delta move still acts)
var _move_src := {}              # MOVE: the source footprint cells, cleared when the move lands
var _move_origin := Vector2i.ZERO # MOVE: the source footprint's top-left cell
var _move_grab := Vector2i.ZERO  # MOVE: the cell the drag started on, so the ghost follows the grab point
var _ghost_origin_pin := INVALID_CELL # dev hook (dev/capture.gd): pin the ghost's origin instead of
									  # reading the OS cursor, which a capture run cannot place reliably
var _mouse_inside := true    # false while the OS cursor is off the game window; hides all highlights
var _ui_hid := false         # true while the cursor is over the editor menu/panels, so hover is cleared
# Magic Wand selection state, so a repeat click on the same selection grows its scope:
var _sel_kind := ""          # "" none, "floor" (quarters) or "wall" (cells)
var _sel_quads := {}         # floor selection FILL set: quarter Vector2i (16px grid) -> true (incl. the
							 # under-wall ring for fills; the overlay subtracts wall sprites for display)
var _sel_cells := {}         # wall selection: cell Vector2i (32px grid) -> true
var _sel_level := 0          # grow level: floor 1=patch 2=room; wall 1=run 2=building
var _faded: Array = []       # [node, original_modulate] of obstacles dimmed under the cursor
var _faded_cell := Vector2i(-9999, -9999) # cell the current fade is for (dedupe)
var _grid_on := false
const INVALID_CELL := Vector2i(-9999, -9999) # "no cell" sentinel for the dedupe trackers below
var _hover_cell := INVALID_CELL   # raw mouse cell last seen (room-mask dedupe)
var _wall_hover := INVALID_CELL   # wall cell currently highlighted (dedupe)
var _whole_hover_key := ""        # descriptor of the current Whole highlight target (sub-cell dedupe):
								  # "w:<cell>" a building, "r:<cell>" a room, "" nothing

# the hover highlight is drawn by the mask system (FloorHighlightMask): we just detect which
# room the mouse is over and hand it that room's floor shape; it renders the pixel-exact fill
# and outline of the visible floor.
@onready var _mask = get_node("../FloorHighlightMask")

func _ready() -> void:
	# recompute the hover AFTER camera_follow has moved the camera this frame (it runs at the
	# default priority 0), so the highlight stays under the mouse while the player walks and the
	# world scrolls, not just when the mouse itself moves. Same rationale as FloorHighlightMask.
	process_priority = 100
	_menu = PopupMenu.new()
	# Floor materials and wall colours sit in submenus so the top menu stays short (a flat list
	# of all of them plus scopes overflowed the screen). Submenu items share _on_menu_id since
	# every id is namespaced (floor 0-4, walls 300+, scopes 200+, grid 100).
	# The two section submenus are built once as children of _menu. The TOP-LEVEL items are (re)built
	# per right-click in _apply_menu_context so only the section for the clicked target shows (Godot's
	# PopupMenu has no set_item_hidden, so contextual = rebuild the top level). See ROADMAP item 4.
	var floor_sub := PopupMenu.new()
	floor_sub.name = "floor_sub"
	for i in MENU.size():
		floor_sub.add_item(MENU[i][0], i)
	floor_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(floor_sub)

	var wall_sub := PopupMenu.new()
	wall_sub.name = "wall_sub"
	for i in WALL_COLORS.size():
		wall_sub.add_item(WALL_COLORS[i][0], WALL_BASE_ID + i)
	wall_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(wall_sub)

	# Wall Material: the face/cap texture swap (Stone/Wood/Slate), shown beside Wall Colour on a
	# structure cell. Ids namespaced at WALL_MAT_BASE_ID+, routed through the shared _on_menu_id.
	var wall_mat_sub := PopupMenu.new()
	wall_mat_sub.name = "wall_mat_sub"
	for i in WALL_MATERIALS.size():
		wall_mat_sub.add_item(WALL_MATERIALS[i][0], WALL_MAT_BASE_ID + i)
	wall_mat_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(wall_mat_sub)

	# Pattern: a MATERIAL-AWARE submenu shown beside Floor Textures/Colours on a floor cell. Its items
	# are rebuilt per right-click from the clicked quarter's material (see _apply_menu_context), so it
	# lists that material's pattern variants (e.g. wood -> Planks/Diagonal). Ids namespaced at
	# PATTERN_BASE_ID+, routed through the shared _on_menu_id.
	var pattern_sub := PopupMenu.new()
	pattern_sub.name = "pattern_sub"
	pattern_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(pattern_sub)

	# Door: shown on a door cell (rebuilt per right-click from the door's state, see
	# _rebuild_door_submenu). Mirrors the inspector's door controls. Ids are the DOOR_* action ids.
	var door_sub := PopupMenu.new()
	door_sub.name = "door_sub"
	door_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(door_sub)

	# Build Wall configurator: pick a colour + material (radio checkables that KEEP the menu open), then
	# "Start Building" arms a draggable wall brush and closes. Local id scheme (colour i, material 100+j,
	# start 999), routed to _on_build_wall_id, NOT _on_menu_id, so it needs no global id range.
	var build_wall_sub := PopupMenu.new()
	build_wall_sub.name = "build_wall_sub"
	build_wall_sub.hide_on_checkable_item_selection = false # picking colour/material keeps it open
	build_wall_sub.add_separator("Colour")
	for i in WALL_COLORS.size():
		build_wall_sub.add_radio_check_item(WALL_COLORS[i][0], i)
	build_wall_sub.add_separator("Material")
	for j in WALL_MATERIALS.size():
		build_wall_sub.add_radio_check_item(WALL_MATERIALS[j][0], 100 + j)
	build_wall_sub.add_separator()
	build_wall_sub.add_item("Start Building (drag to place)", 999)
	build_wall_sub.id_pressed.connect(_on_build_wall_id)
	_menu.add_child(build_wall_sub)
	_build_wall_sub = build_wall_sub
	_sync_build_wall_checks() # show the current brush as checked

	# Floor Colours: a tint submenu shown beside Floor Textures on a floor cell (the two share the
	# floor-cell branch of _apply_menu_context). Ids are namespaced (FLOOR_COLOR_BASE_ID+), so it
	# routes through the same _on_menu_id like the other submenus.
	var floor_color_sub := PopupMenu.new()
	floor_color_sub.name = "floor_color_sub"
	for i in FLOOR_COLORS.size():
		floor_color_sub.add_item(FLOOR_COLORS[i][0], FLOOR_COLOR_BASE_ID + i)
	floor_color_sub.add_separator()
	floor_color_sub.add_item("Custom...", FLOOR_PICKER_ID) # opens the full colour picker
	floor_color_sub.id_pressed.connect(_on_menu_id)
	_menu.add_child(floor_color_sub)

	# the "Custom..." floor-colour picker: a ColorPicker in a popup that live-previews the tint on the
	# clicked target as you drag, committing one undo entry when it closes (see _open_floor_picker).
	_picker_popup = PopupPanel.new()
	_color_picker = ColorPicker.new()
	_color_picker.edit_alpha = false # tints are opaque multiplies; alpha would just dim confusingly
	_color_picker.custom_minimum_size = Vector2(280, 0)
	_picker_popup.add_child(_color_picker)
	_color_picker.color_changed.connect(_on_floor_picker_changed)
	_picker_popup.popup_hide.connect(_on_floor_picker_closed)
	add_child(_picker_popup)

	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)
	# the Cell/Fine square paint cursor; Wand uses the mask preview + selection overlay instead
	_cursor = Node2D.new()
	_cursor.set_script(load("res://floors/paint_cursor.gd"))
	_cursor.z_index = 1000
	add_child(_cursor)
	# the lifted terrain drop-preview sprite (Cell/Fine placement): armed material floats over the
	# hovered cell and falls in on click. Above the cursor so it reads as lifted over the highlight.
	_preview = Node2D.new()
	_preview.set_script(load("res://floors/terrain_preview.gd"))
	add_child(_preview)
	# the lifted BRIDGE drop-preview: the actual deck art (bridge.gd in preview mode) floats over the
	# hovered cell in BRIDGE mode, oriented to the water run under the cursor, so the tool shows what
	# will land instead of the last floor material. Hidden until BRIDGE-mode hover shows it.
	_bridge_preview = Node2D.new()
	_bridge_preview.set_script(load("res://world/bridge.gd"))
	_bridge_preview.preview = true
	_bridge_preview.visible = false
	add_child(_bridge_preview)
	# Wall placement ghost pool: 2 translucent preview wall_segments (a cell gets at most a horizontal
	# piece + a vertical rail). Shown on WALL-mode hover, configured from obstacles.preview_wall_configs so
	# the ghost is the REAL shape a click would place, in the armed wall colour+material.
	for _i in 2:
		var wp := Node2D.new()
		wp.set_script(WallSegmentScript)
		wp.preview = true
		wp.visible = false
		add_child(wp)
		_wall_ghost.append(wp)
	# Door placement ghost: gate.gd in preview mode, auto-oriented to the wall run under the cursor,
	# shown on DOOR-mode hover (mirrors the wall ghost + bridge deck preview).
	_door_preview = Node2D.new()
	_door_preview.set_script(load("res://world/gate.gd"))
	_door_preview.preview = true
	_door_preview.visible = false
	add_child(_door_preview)
	# when the cursor leaves the game window, drop every highlight (ROADMAP "Terrain placement UX":
	# cursor off screen clears all highlights); restore tracking when it returns
	get_window().mouse_exited.connect(_on_window_mouse_exited)
	get_window().mouse_entered.connect(_on_window_mouse_entered)
	# the marching-ants selection overlay the Magic Wand builds and the menu fills
	_selection = Node2D.new()
	_selection.set_script(load("res://floors/selection_overlay.gd"))
	_selection.z_index = 1000
	add_child(_selection)
	# the paste/move hover ghost: draws the armed clip over the cells it would land on. It borrows
	# this manager's texture lookup so the ghost shows the real material art, and its bounds test so
	# cells that would be clipped at the map edge read red before the click.
	_clip_ghost = Node2D.new()
	_clip_ghost.set_script(load("res://floors/clip_preview.gd"))
	add_child(_clip_ghost)
	_clip_ghost.setup(func(mat: String, pat: int) -> Texture2D: return _mat_tex(mat, pat), _stampable)
	call_deferred("_seed") # keep the existing wooden room once RoomLight has built

func _seed() -> void:
	set_room_style(Vector2i(8, 9), "wood")

# cursor left / re-entered the game window: clear every highlight while it is away so nothing
# lingers under an absent pointer, and stop recomputing the hover until it returns.
func _on_window_mouse_exited() -> void:
	_mouse_inside = false
	_reset_highlight()
	_restore_faded()

func _on_window_mouse_entered() -> void:
	_mouse_inside = true

# keep the highlight under the pointer as the camera scrolls with the player. get_local_mouse_position
# tracks the current camera, so re-detecting the hovered cell each frame follows the world. The
# hover updates are deduped by cell/rect, so a still camera and mouse cost nothing.
func _process(_delta: float) -> void:
	# coalesce a wall drag's map rebuilds to at most ONE per frame (each rebuild is a full map re-apply;
	# doing it per motion event stutters). The walls were already added to the model in _place_wall_at.
	if _walls_dirty:
		_walls_dirty = false
		_reapply_map()
	# while the cursor is over the editor menu/panels, stand down: clear the hover once on entering the
	# menu and keep it hidden, so no paint cursor / preview / select highlight shows over the UI.
	if _pointer_over_ui():
		if not _ui_hid:
			_ui_hid = true
			_reset_highlight()
			_restore_faded()
		return
	elif _ui_hid:
		_ui_hid = false
	_update_hover()

# true when a GUI Control (the tool strip, inspector, save menu, a popup, ...) is under the cursor, so
# map editing/preview must stand down. Respects each Control's mouse_filter (IGNORE controls don't count).
func _pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _unhandled_input(event: InputEvent) -> void:
	# a mouse PRESS that starts over the editor menu/panels is not a map action (paint, any select, or the
	# right-click menu): the GUI owns it. Motion/release still pass so a drag begun on the map can finish.
	if event is InputEventMouseButton and event.pressed and _pointer_over_ui():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var local := get_local_mouse_position()
		var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		# a right-click cancels an armed paste (the standard "drop the loaded brush" gesture, matching
		# the Cell/Fine right-click-disarms rule); the clipboard keeps the clip for the next Ctrl+V.
		if _pending_kind == "paste":
			_cancel_pending()
			get_viewport().set_input_as_handled()
			return
		# Cell/Fine: a right-click while a material is armed just cancels the brush (removes the floating
		# drop-preview graphic), no menu. A second right-click (now un-armed) opens the menu as usual.
		# See ROADMAP "Editor UX revisions" -> right-click disarms in Cell/Fine.
		if (_mode == Mode.CELL or _mode == Mode.FINE) and _armed:
			_armed = false
			brush_changed.emit()
			_preview.hide_preview() # drop the lifted tile immediately (the square cursor stays)
			get_viewport().set_input_as_handled()
			return
		# a right-click off the map, or off the current selection, deselects (rather than opening the
		# menu). A right-click INSIDE the selection falls through to open the menu, so it can still act
		# on the selection. See ROADMAP "Editor UX revisions" -> deselect a Wand selection.
		if _selection.has_selection() and (not _in_bounds(cell) or not _click_in_selection(local)):
			_clear_selection()
			get_viewport().set_input_as_handled()
			return
		if not _in_bounds(cell):
			return # right-clicked off the map
		_pending = local
		_apply_menu_context(cell) # rebuilds the top level for the clicked target + sets Grid's check
		_menu.position = Vector2i(get_viewport().get_mouse_position())
		_menu.reset_size() # re-fit after the rebuild so the popup isn't sized for a stale menu
		_menu.popup()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# an armed paste owns the next left click, in ANY mode: it stamps the clip where the ghost sits.
		if _pending_kind == "paste":
			if event.pressed:
				_drop_pending()
			get_viewport().set_input_as_handled()
			return
		# clicking off the map deselects the current selection (any mode), per "Editor UX revisions"
		# -> deselect a Wand selection ("clicking off the map would logically deselect").
		if event.pressed and _selection.has_selection():
			var lc := get_local_mouse_position()
			if not _in_bounds(Vector2i(floori(lc.x / CELL), floori(lc.y / CELL))):
				_clear_selection()
				get_viewport().set_input_as_handled()
				return
		if _mode == Mode.WAND:
			# the wand selects (click to grow); it never paints directly. Shift adds / Alt subtracts,
			# per "Editor UX revisions" -> additive/subtractive selection.
			if event.pressed:
				var local := get_local_mouse_position()
				if _in_bounds(Vector2i(floori(local.x / CELL), floori(local.y / CELL))):
					_wand_click(local, _sel_op(event))
					get_viewport().set_input_as_handled()
			return
		if _mode == Mode.BOX:
			# drag a rectangle: press starts it, motion (below) grows it, release finalizes. The modifier
			# at press decides replace / add / subtract against the current selection.
			if event.pressed:
				var local := get_local_mouse_position()
				var cell := _clamp_cell(Vector2i(floori(local.x / CELL), floori(local.y / CELL)))
				if _in_bounds(cell):
					_box_active = true
					_box_start = cell
					_box_op = _sel_op(event)
					_box_base = _sel_quads.duplicate() if (_sel_kind == "floor" and _box_op != "replace") else {}
					_update_box(cell)
					get_viewport().set_input_as_handled()
			elif _box_active:
				_box_active = false # selection already committed into _sel_quads during the drag
				get_viewport().set_input_as_handled()
			return
		if _mode == Mode.MOVE:
			# drag the current selection to a new place: press INSIDE it to grab (the ghost then follows
			# the grab point), release to drop. Pressing outside does nothing, so a stray click never
			# moves a room by accident. Rotate/flip (R / H / Shift+H) work mid-drag like they do for paste.
			if event.pressed:
				var ml := get_local_mouse_position()
				if _selection.has_selection() and _click_in_selection(ml):
					_begin_move(Vector2i(floori(ml.x / CELL), floori(ml.y / CELL)))
					get_viewport().set_input_as_handled()
			elif _pending_kind == "move":
				_drop_pending()
				get_viewport().set_input_as_handled()
			return
		if _mode == Mode.SELECT:
			# selecting an object never edits the map; it loads the inspector. No drag.
			if event.pressed:
				_select_at(get_local_mouse_position())
				get_viewport().set_input_as_handled()
			return
		if _mode == Mode.DOOR:
			# one click = one door = one undo entry (no drag: a dragged door line is rarely wanted)
			if event.pressed:
				_place_door_at(get_local_mouse_position())
				get_viewport().set_input_as_handled()
			return
		if _mode == Mode.BRIDGE:
			# one click = one bridge = one undo entry (auto-oriented to the water run it spans)
			if event.pressed:
				_place_bridge_at(get_local_mouse_position())
				get_viewport().set_input_as_handled()
			return
		if _mode == Mode.WALL:
			# click-and-drag draws a wall line; the whole gesture is one undo entry
			if event.pressed:
				_painting = true
				_place_wall_at(get_local_mouse_position())
				get_viewport().set_input_as_handled()
			elif _painting:
				_painting = false
				if _walls_dirty: # flush the final pending rebuild so the commit captures it
					_walls_dirty = false
					_reapply_map()
				EditHistory.commit("wall")
			return
		# Cell / Fine / Erase: left-click and left-drag paint
		if event.pressed:
			# Erase removes the topmost structure (wall/door) first, as a single click; only once
			# no structure remains does a further click erase the terrain beneath it (cell-occupancy
			# model, ROADMAP "Erase mode"). Structure removal consumes the click (no paint drag).
			if _mode == Mode.ERASE and _erase_structure_at(get_local_mouse_position()):
				get_viewport().set_input_as_handled()
				return
			_painting = true
			_paint(get_local_mouse_position(), true) # fresh click: play the drop animation
			get_viewport().set_input_as_handled()
		elif _painting:
			# stroke ended: the whole drag (or single click) is one undo step
			_painting = false
			EditHistory.commit("paint")
	elif event is InputEventMouseMotion:
		if _painting:
			_paint(get_local_mouse_position())
		elif _box_active:
			var l := get_local_mouse_position()
			_update_box(_clamp_cell(Vector2i(floori(l.x / CELL), floori(l.y / CELL))))
		_update_hover()

# Esc clears the current Magic Wand selection (also cleared by starting a new selection elsewhere).
# R (in DOOR mode) flips the default door orientation used when placing in open space, so a door with
# no wall run to embed in can still be laid either way (ROADMAP "directional placement (auto + R)").
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# --- clipboard: copy / paste / duplicate (ROADMAP "Copy, paste, and duplicate") ---
	var mod: bool = event.ctrl_pressed or event.meta_pressed
	if mod and event.keycode == KEY_C:
		_copy_selection()
		get_viewport().set_input_as_handled()
		return
	if mod and event.keycode == KEY_V:
		_arm_paste(MapClipboard.clip())
		get_viewport().set_input_as_handled()
		return
	if mod and event.keycode == KEY_D:
		# duplicate = copy the selection and immediately arm it, so the copy is dropped by the next click
		if _copy_selection():
			_arm_paste(MapClipboard.clip())
		get_viewport().set_input_as_handled()
		return
	# --- rotate / flip the clip about to land (paste ghost or move drag) ---
	if not _pending_clip.is_empty() and event.keycode == KEY_R:
		_transform_pending(MapClipboard.rotate_cw(_pending_clip))
		get_viewport().set_input_as_handled()
		return
	if not _pending_clip.is_empty() and event.keycode == KEY_H:
		_transform_pending(MapClipboard.flip_v(_pending_clip) if event.shift_pressed else MapClipboard.flip_h(_pending_clip))
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and not _pending_clip.is_empty():
		_cancel_pending() # Esc drops the armed paste / aborts the move drag before it lands
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _selection.has_selection():
		_clear_selection()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DELETE and _selection.has_selection():
		# Delete erases the current selection (ROADMAP "Editor UX revisions" -> Erase = also the Delete key)
		_erase_selection()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and _mode == Mode.DOOR:
		_door_orient = "vertical" if _door_orient == "horizontal" else "horizontal"
		call_deferred("_update_hover")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and _mode == Mode.BRIDGE:
		_bridge_orient = "vertical" if _bridge_orient == "horizontal" else "horizontal"
		call_deferred("_update_hover")
		get_viewport().set_input_as_handled()

# contextual right-click menu: rebuild the top level so ONLY the section for what was clicked shows.
# A wall/door cell (the structure layer) gets the Wall Colour submenu; any other cell is floor, so
# gets Floor Textures (descriptive heading, kept distinct from the future "Floor Colours" tint). The
# Grid toggle is a tool setting and stays regardless. PopupMenu has no set_item_hidden in Godot 4, so
# contextual visibility = clear + re-add the relevant items each right-click.
func _apply_menu_context(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	var is_door: bool = obs != null and not obs.door_at(cell).is_empty()
	var is_wall: bool = obs != null and obs.is_blocked(cell) # a real wall (doors are not blocked)
	_menu.clear()
	# structure section: a DOOR gets Door options; a WALL gets Wall Colour + Material (ROADMAP "Editor
	# UX revisions" -> Wall/Door contextual menu: walls show Wall + Terrain, doors show Door + Terrain).
	if is_door:
		_rebuild_door_submenu(cell)
		_menu.add_submenu_item("Door", "door_sub")
	elif is_wall:
		_menu.add_submenu_item("Wall Colour", "wall_sub")
		_menu.add_submenu_item("Wall Material", "wall_mat_sub")
	# terrain section: the ground under a wall/door is editable, so the Floor submenus now show on EVERY
	# cell (the "terrain option" the notes ask for on walls and doors), not only on bare floor cells.
	_menu.add_submenu_item("Floor Textures", "floor_sub")
	_menu.add_submenu_item("Floor Colours", "floor_color_sub")
	_maybe_add_pattern()
	_menu.add_separator()
	# action section: Build Wall/Door on an empty cell (ROADMAP "Editor UX revisions" -> Wall/Door into
	# the menu), and Erase everywhere (acts on the selection if one exists, else the clicked target).
	if not (is_door or is_wall):
		_menu.add_submenu_item("Build Wall", "build_wall_sub") # configurator: colour + material, then Start
		_menu.add_item("Build Door", BUILD_DOOR_ID)
	_menu.add_item("Erase", ERASE_ID)
	_menu.add_separator()
	_menu.add_check_item("Grid", GRID_ID)
	_menu.set_item_checked(_menu.get_item_index(GRID_ID), _grid_on)

# add the material-aware Pattern submenu for the clicked quarter's material, when that material has more
# than one variant (grass/none has none). Rebuilt each right-click. Shared by every cell's terrain section.
func _maybe_add_pattern() -> void:
	var pq := Vector2i(floori(_pending.x / HALF), floori(_pending.y / HALF))
	var mat: String = _quad_mat.get(pq, "")
	var variants: int = textures[mat].size() if textures.has(mat) else 0
	if variants > 1:
		var psub: PopupMenu = _menu.get_node("pattern_sub")
		psub.clear()
		var names: Array = PATTERN_NAMES.get(mat, [])
		for i in variants:
			psub.add_item(names[i] if i < names.size() else "Pattern %d" % (i + 1), PATTERN_BASE_ID + i)
		_menu.add_submenu_item("Pattern", "pattern_sub")

# rebuild the Door submenu from the door on `cell` (state-reflecting check items, like the inspector)
func _rebuild_door_submenu(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	var d: Dictionary = obs.door_at(cell) if obs != null else {}
	var ds: PopupMenu = _menu.get_node("door_sub")
	ds.clear()
	ds.add_item("Flip Orientation", DOOR_FLIP_ID)
	ds.add_check_item("Open by default", DOOR_OPEN_ID)
	ds.set_item_checked(ds.get_item_index(DOOR_OPEN_ID), bool(d.get("open", false)))
	ds.add_check_item("Swing (alt side)", DOOR_SWING_ID)
	ds.set_item_checked(ds.get_item_index(DOOR_SWING_ID), bool(d.get("swing", false)))

func _on_menu_id(id: int) -> void:
	if id == GRID_ID:
		set_grid(not _grid_on)
		return
	var cell := Vector2i(floori(_pending.x / CELL), floori(_pending.y / CELL))
	# action items (all < 300, matched here before the swatch-range branches and the MENU fallthrough)
	if id == ERASE_ID:
		_menu_erase(cell)
		return
	if id == BUILD_WALL_ID:
		var obsw = get_node_or_null("../Obstacles")
		if obsw != null and obsw.add_wall(cell):
			_reapply_map()
			EditHistory.commit("wall")
		_reset_highlight()
		return
	if id == BUILD_DOOR_ID:
		_place_door_at(_pending) # commits internally, no-ops if a door is already there
		_reset_highlight()
		return
	if id == DOOR_FLIP_ID or id == DOOR_OPEN_ID or id == DOOR_SWING_ID:
		_edit_door(cell, id)
		return
	if id >= PATTERN_BASE_ID:
		# a floor pattern. Mirrors the floor-tint branch: apply to the active floor selection, else the
		# clicked target at the current grain (Wand -> room, Cell -> cell, Fine -> quarter). Arms
		# _tool_kind = "pattern" so a left-drag keeps applying it (see _paint -> _paint_floor_pattern).
		_tool_kind = "pattern"
		_pattern = id - PATTERN_BASE_ID
		if _apply_floor_pattern(_pattern):
			_rebuild()
			EditHistory.commit("floor pattern") # one menu apply = one undo step
		_reset_highlight()
		return
	if id >= WALL_MAT_BASE_ID:
		# a wall material. Mirrors the wall-colour branch below: fill the active wall selection if one
		# exists; otherwise material the wall under the click (whole building in Wand, single segment in
		# Cell/Fine). Arms _tool_kind = "wall_mat" so a left-drag keeps applying it (see _paint).
		_tool_kind = "wall_mat"
		_wall_mat = WALL_MATERIALS[id - WALL_MAT_BASE_ID][1]
		var did_mat := false
		if _sel_kind == "wall" and _selection.has_selection():
			_fill_wall_material_selection(_wall_mat)
			did_mat = true
		else:
			var obs_m = get_node_or_null("../Obstacles")
			# is_blocked (a real wall), not has_structure: doors keep stone (their own art), so on a
			# door this is a no-op.
			if obs_m != null and obs_m.is_blocked(cell):
				if _mode == Mode.WAND:
					obs_m.material_building(cell, _wall_mat)
				else:
					obs_m.set_wall_material(cell, _wall_mat)
				did_mat = true
		if did_mat:
			EditHistory.commit("wall material") # one menu apply = one undo step
		_reset_highlight()
		return
	if id == FLOOR_PICKER_ID:
		_open_floor_picker() # "Custom..." -> the full colour picker (arbitrary tint)
		return
	if id >= FLOOR_COLOR_BASE_ID:
		# a floor tint. Fill the active floor selection if one exists; otherwise tint what was
		# clicked at the current grain (Wand -> whole room, Cell -> the cell, Fine -> the quarter).
		# Mirrors the wall-colour branch below. Leaves _tool_kind = "floor_color" armed so a
		# left-drag keeps tinting (see _paint) with the orange ground cursor (see _update_hover).
		_tool_kind = "floor_color"
		_floor_color = FLOOR_COLORS[id - FLOOR_COLOR_BASE_ID][1]
		brush_changed.emit()
		if _apply_floor_tint(_floor_color):
			_rebuild()
			EditHistory.commit("floor colour") # one menu tint = one undo step
		_reset_highlight()
		return
	if id >= WALL_BASE_ID:
		# a wall colour. Fill the active wall selection if one exists; otherwise colour the wall
		# under the click (the whole building in Wand mode, a single segment in Cell/Fine).
		_tool_kind = "wall"
		_wall_color = WALL_COLORS[id - WALL_BASE_ID][1]
		var did_edit := false
		if _sel_kind == "wall" and _selection.has_selection():
			_fill_wall_selection(_wall_color)
			did_edit = true
		else:
			var obs = get_node_or_null("../Obstacles")
			# is_blocked (a real wall), not has_structure: doors keep their own independent colour
			# (unbuilt), so the wall tint only applies to walls. On a door this is a no-op.
			if obs != null and obs.is_blocked(cell):
				if _mode == Mode.WAND:
					obs.color_building(cell, _wall_color)
				else:
					obs.set_wall_color(cell, _wall_color)
				did_edit = true
		if did_edit:
			EditHistory.commit("wall colour") # one menu paint = one undo step
		_reset_highlight()
		return
	# a floor material. Fill the active floor selection if one exists; otherwise, in Wand mode fill
	# the clicked room. In Cell/Fine, selecting a terrain no longer auto-places: it just arms the
	# brush and the user clicks the target to drop it (ROADMAP "Terrain placement UX").
	_tool_kind = "floor"
	_brush = MENU[id][1]
	_armed = true # a material was explicitly chosen: Cell/Fine may now drop it
	brush_changed.emit()
	if _sel_kind == "floor" and _selection.has_selection():
		var drop_rects := _selection_drop_rects() # capture the shape before the highlight resets
		_fill_floor_selection(_brush)
		EditHistory.commit("paint") # one menu fill = one undo step
		if _brush != "" and textures.has(_brush):
			_preview.play_shape_drop(drop_rects, _mat_tex(_brush, 0)) # animate the whole shape dropping in
		_reset_highlight()
	elif _mode == Mode.WAND:
		set_room_style(cell, _brush) # convenience room fill; may no-op outside a room
		EditHistory.commit("paint")
		_reset_highlight()
	else:
		# arm only: nothing changed yet (no undo entry). Refresh the hover so the lifted drop-
		# preview of the freshly-armed material appears over the cursor immediately.
		call_deferred("_update_hover")

# --- floor colour: shared apply + the "Custom..." picker ---

# apply `color` as the floor tint to the right-clicked target, at the current grain: the active
# floor selection, else the clicked room (Wand) / quarter (Fine) / cell (Cell). Returns whether any
# quarter changed. Shared by the preset swatches and the live colour picker.
func _apply_floor_tint(color: Color) -> bool:
	var cell := Vector2i(floori(_pending.x / CELL), floori(_pending.y / CELL))
	if _sel_kind == "floor" and _selection.has_selection():
		return _tint_selection(color)
	elif _mode == Mode.WAND:
		return _tint_room(cell, color)
	elif _mode == Mode.FINE:
		return _write_tint(Vector2i(floori(_pending.x / HALF), floori(_pending.y / HALF)), color)
	else: # Cell / Erase -> the whole cell
		return _tint_cell(cell, color)

# open the colour picker seeded from the current tint (or a default), previewing live on the target
func _open_floor_picker() -> void:
	_tool_kind = "floor_color"
	_picker_applied = false
	_suppress_picker = true # setting .color must not count as a user edit
	_color_picker.color = _floor_color if _floor_color != Color.WHITE else Color(0.85, 0.3, 0.28)
	_suppress_picker = false
	_picker_popup.popup_centered()

# live preview: each drag in the picker re-tints the target with the new colour
func _on_floor_picker_changed(c: Color) -> void:
	if _suppress_picker:
		return
	_floor_color = c
	if _apply_floor_tint(c):
		_rebuild()
		_picker_applied = true

# picker closed: the whole session commits as ONE undo entry (or nothing if never previewed)
func _on_floor_picker_closed() -> void:
	if _picker_applied:
		EditHistory.commit("floor colour")
		_picker_applied = false
	_reset_highlight()

# --- authoring mode (driven by the tool strip) ---

# called by the tool strip. Switching mode drops transient hover; leaving the wand re-arms the floor
# tool so Cell/Fine paint floors. The selection persists across mode switches (cleared on Esc or a
# new wand pick), so you can wand-select a room and then Cell-tweak a corner of it.
func set_mode(mode: int) -> void:
	if _mode == mode:
		return
	_mode = mode as Mode
	_box_active = false # never carry a box drag across a mode switch
	_cancel_pending()   # nor an armed paste / half-finished move drag
	if _mode != Mode.WAND:
		_tool_kind = "floor"
	# Cell/Fine must not start with a material armed to drop: the user picks one from the menu first
	# (ROADMAP "Editor UX revisions" -> Cell/Fine must not pre-arm a material).
	if _mode == Mode.CELL or _mode == Mode.FINE:
		_armed = false
	brush_changed.emit()
	_reset_highlight()
	call_deferred("_update_hover")

func mode() -> int:
	return _mode

# --- persistent Brush panel API (tool_strip.gd): read + set the armed floor brush without the menu ---

func is_armed() -> bool:
	return _armed

func active_tool_kind() -> String:
	return _tool_kind

func armed_material() -> String:
	return _brush

func active_floor_color() -> Color:
	return _floor_color

# the base texture of the armed floor material, for the panel's combined-brush preview swatch. Grass
# ("" / unknown) previews the grass base, so tinting it reads the same as a tinted grass patch.
func armed_brush_texture() -> Texture2D:
	if _brush == "" or not textures.has(_brush):
		return GRASS
	return _mat_tex(_brush, 0)

# is there a committed FLOOR selection? Used by the panel to decide whether picking a material/colour
# EDITS the selection (recolour/re-texture in place) rather than arming a brush to paint by hand.
func has_floor_selection() -> bool:
	return _sel_kind == "floor" and _selection != null and _selection.has_selection()

# mirror the current floor selection's material + colour into the armed brush, so the Brush panel
# lights up the tile+colour the selection already has (e.g. red tiles -> Tile + Red). Uses the most
# common value across the selected quarters, so a mostly-uniform room reflects its dominant look. Only
# re-emits when something actually changed, so it is safe to call on every selection refresh.
func _reflect_selection_brush() -> void:
	if _sel_quads.is_empty():
		return
	var mat: String = _dominant(_sel_quads, _quad_mat, "")
	var col: Color = _dominant(_sel_quads, _quad_tint, Color.WHITE)
	if mat == _brush and col == _floor_color and _tool_kind == "floor":
		return
	_tool_kind = "floor"
	_brush = mat
	_floor_color = col
	brush_changed.emit()

# --- wall side of the Brush panel: read + set the armed wall material + colour (mirrors the floor API
# above). A WALL selection reflects its look here, and picking here edits the wall selection in place.

func armed_wall_material() -> String:
	return _wall_mat

func active_wall_color() -> Color:
	return _wall_color

func armed_wall_texture() -> Texture2D:
	return WALL_TEX.get(_wall_mat, WALL_TEX["stone"])

func has_wall_selection() -> bool:
	return _sel_kind == "wall" and _selection != null and _selection.has_selection()

func arm_wall_material(mat: String) -> void:
	_tool_kind = "wall_mat"
	_wall_mat = mat
	if has_wall_selection():
		_fill_wall_material_selection(mat)
		EditHistory.commit("wall material")
	brush_changed.emit()

func arm_wall_color(color: Color) -> void:
	_tool_kind = "wall"
	_wall_color = color
	if has_wall_selection():
		_fill_wall_selection(color)
		EditHistory.commit("wall colour")
	brush_changed.emit()

# mirror the current wall selection's dominant material + colour into the armed wall brush, so the
# panel lights up the wall's material + tint (like the floor reflect). Reads per-cell values via
# Obstacles (which return the stone/white defaults), so a mostly-plain selection reflects Stone/Natural.
func _reflect_wall_selection_brush() -> void:
	if _sel_cells.is_empty():
		return
	var obs = get_node_or_null("../Obstacles")
	if obs == null:
		return
	var matmap := {}
	var colmap := {}
	for c in _sel_cells:
		matmap[c] = obs.get_wall_material(c)
		colmap[c] = obs.get_wall_color(c)
	var mat: String = _dominant(_sel_cells, matmap, "stone")
	var col: Color = _dominant(_sel_cells, colmap, Color.WHITE)
	if mat == _wall_mat and col == _wall_color:
		return
	_wall_mat = mat
	_wall_color = col
	brush_changed.emit()

# the most common value in `store` (a quarter -> value map) across the quarters in `quads`, ignoring
# quarters with no entry; `default_val` when none of them carry a value.
func _dominant(quads: Dictionary, store: Dictionary, default_val):
	var counts := {}
	var best = default_val
	var best_n := 0
	for q in quads:
		if not store.has(q):
			continue
		var v = store[q]
		var n: int = int(counts.get(v, 0)) + 1
		counts[v] = n
		if n > best_n:
			best_n = n
			best = v
	return best

# arm a floor material from the panel (same as picking it in the Floor Textures menu in Cell/Fine: it
# arms the brush; the user then paints/drops it). No selection-fill here (that stays a menu convenience).
func arm_floor_material(mat: String) -> void:
	_tool_kind = "floor"
	_brush = mat
	_armed = true
	# with a floor selection active, picking a material RE-TEXTURES the selection in place (the two-way
	# panel binding), keeping its colour and the selection itself so the user can keep tweaking.
	if has_floor_selection():
		_fill_floor_selection(mat) # rebuilds
		EditHistory.commit("paint")
	brush_changed.emit()
	call_deferred("_update_hover")

# arm the floor-colour from the panel with `color`. Unlike the Floor Colours *menu* (which arms a
# tint-only recolour tool), the panel brush is COMBINED: colour and texture are two axes of one floor
# brush, so setting the colour keeps the armed material and a paint lays both together (see _paint).
# White = Natural = lays the plain (untinted) material. The material stays armed and lit in the panel.
func arm_floor_color(color: Color) -> void:
	_tool_kind = "floor"
	_floor_color = color
	_armed = true
	# with a floor selection active, picking a colour RE-TINTS the selection in place (the two-way panel
	# binding), keeping its texture and the selection itself. White = Natural clears the tint.
	if has_floor_selection():
		if _tint_selection(color):
			_rebuild()
			EditHistory.commit("floor colour")
	brush_changed.emit()
	call_deferred("_update_hover")

# --- Magic Wand selection ---

# a wand click either starts a new selection or grows the current one (patch -> whole room for a
# floor, run -> whole building for a wall). See ROADMAP "Magic Wand".
func _wand_click(local: Vector2, op := "replace") -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	var q := Vector2i(floori(local.x / HALF), floori(local.y / HALF))
	var obs = get_node_or_null("../Obstacles")
	var is_wall: bool = obs != null and obs.is_blocked(cell)
	if op == "replace":
		# plain click: new selection, or grow-on-repeat (patch -> room, run -> building)
		if is_wall:
			_wand_wall(obs, cell)
		else:
			_wand_floor(cell, q)
	elif is_wall:
		# Shift/Alt: add or subtract the clicked wall run (no growing while compositing)
		_modify_wall_selection(obs.line_cells(cell), op)
	else:
		_modify_floor_selection(_with_ring(_patch_quads(cell, q)), op)
	_refresh_selection_overlay()

# the selection compositing op for a mouse event: Alt subtracts, Shift adds, plain replaces.
func _sel_op(event: InputEvent) -> String:
	if event.alt_pressed:
		return "subtract"
	if event.shift_pressed:
		return "add"
	return "replace"

# clamp a cell to the map so a box drag never runs off the edge
func _clamp_cell(cell: Vector2i) -> Vector2i:
	var gb = get_node_or_null("../GridBackground")
	if gb == null:
		return cell
	return Vector2i(clampi(cell.x, 0, gb.grid_width - 1), clampi(cell.y, 0, gb.grid_height - 1))

# union (add) or difference (subtract) a floor `region` (quarter set) into the current selection,
# switching the selection kind to floor if it was a wall selection.
func _modify_floor_selection(region: Dictionary, op: String) -> void:
	if _sel_kind != "floor":
		_sel_kind = "floor"
		_sel_quads = {}
		_sel_cells = {}
	_sel_level = 0 # a composited selection has no single grow level
	if op == "subtract":
		for k in region:
			_sel_quads.erase(k)
	else:
		for k in region:
			_sel_quads[k] = true
	if _sel_quads.is_empty():
		_sel_kind = ""

func _modify_wall_selection(region: Dictionary, op: String) -> void:
	if _sel_kind != "wall":
		_sel_kind = "wall"
		_sel_cells = {}
		_sel_quads = {}
	_sel_level = 0
	if op == "subtract":
		for k in region:
			_sel_cells.erase(k)
	else:
		for k in region:
			_sel_cells[k] = true
	if _sel_cells.is_empty():
		_sel_kind = ""

# box-select: set the selection to the rectangle from _box_start to `cur` (all quarters of every cell
# inside), composited onto _box_base per _box_op. Called live during the drag.
func _update_box(cur: Vector2i) -> void:
	var lo := Vector2i(mini(_box_start.x, cur.x), mini(_box_start.y, cur.y))
	var hi := Vector2i(maxi(_box_start.x, cur.x), maxi(_box_start.y, cur.y))
	var region := {}
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for cq in _cell_quads(Vector2i(cx, cy)):
				region[cq] = true
	var result: Dictionary = _box_base.duplicate()
	if _box_op == "subtract":
		for k in region:
			result.erase(k)
	else: # add, or replace (whose base is empty)
		for k in region:
			result[k] = true
	_sel_cells = {}
	_sel_level = 0
	_sel_quads = result
	_sel_kind = "floor" if not result.is_empty() else ""
	_refresh_selection_overlay()

func _wand_floor(cell: Vector2i, q: Vector2i) -> void:
	# repeat click inside the patch grows it to the whole room floor (all materials, wall-bounded)
	if _sel_kind == "floor" and _sel_quads.has(q) and _sel_level == 1:
		var cells: Dictionary = room_light.room_floor_cells(cell)
		if not cells.is_empty():
			_sel_quads = _room_quads(cells) # interior + under-wall ring (the overlay subtracts walls)
			_sel_level = 2
		return
	# otherwise start a new patch: the connected same-material quarters touching the click, PLUS the
	# ring around them, so the patch also hugs the visible wood on the adjacent wall tiles (the overlay
	# subtracts the wall sprites), consistent with the whole-room grow.
	_sel_kind = "floor"
	_sel_cells = {}
	_sel_quads = _with_ring(_patch_quads(cell, q))
	_sel_level = 1

# add the room-facing wall/door ring quarters around a quarter set, so a selection reaches the
# visible floor that shows on the surrounding wall tiles (the ants hug it, the fill reaches under).
func _with_ring(quads: Dictionary) -> Dictionary:
	var cells := {}
	for q in quads:
		cells[Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))] = true
	var out: Dictionary = quads.duplicate()
	for r in room_light.wall_ring_quads(cells):
		out[Vector2i(floori(r.position.x / HALF), floori(r.position.y / HALF))] = true
	return out

func _wand_wall(obs, cell: Vector2i) -> void:
	# repeat click on the run grows it to the whole building's connected walls
	if _sel_kind == "wall" and _sel_cells.has(cell) and _sel_level == 1:
		_sel_cells = obs.building_cells(cell)
		_sel_level = 2
		return
	_sel_kind = "wall"
	_sel_quads = {}
	_sel_cells = obs.line_cells(cell)
	_sel_level = 1

# the connected same-material quarters touching `q`, bounded to the cells of `cell`'s room. In a
# uniform room this already equals the whole room, so one click grabs the expected floor; grow-on-
# repeat only matters in a mixed room. Outdoors (no enclosed room) the patch is just the cell.
func _patch_quads(cell: Vector2i, q: Vector2i) -> Dictionary:
	var room: Dictionary = room_light.room_floor_cells(cell)
	if room.is_empty():
		var single := {}
		for cq in _cell_quads(cell):
			single[cq] = true
		return single
	var allowed := {}
	for c in room:
		for cq in _cell_quads(c):
			allowed[cq] = true
	var seed_mat = _quad_mat.get(q, "")
	var sel := {q: true}
	var stack: Array = [q]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if sel.has(n) or not allowed.has(n):
				continue
			if _quad_mat.get(n, "") == seed_mat:
				sel[n] = true
				stack.append(n)
	return sel

# every quarter of a room: the interior cells' quarters plus the wall-ring quarters, matching
# _write_room so a whole-room selection fill reaches under the walls the same way a room fill does.
func _room_quads(cells: Dictionary) -> Dictionary:
	var out := {}
	for c in cells:
		for cq in _cell_quads(c):
			out[cq] = true
	for rect in room_light.wall_ring_quads(cells):
		out[Vector2i(floori(rect.position.x / HALF), floori(rect.position.y / HALF))] = true
	return out

# the 32px CELLS covered by the active FLOOR selection, read by RoomLight so it lights them (skips its
# dim overlay) while selected. Empty unless a floor selection is active. The marching ants still mark
# the selection; lighting it just lets the true (lit) colour show while the user edits the colour.
func selection_lit_cells() -> Dictionary:
	if _sel_kind != "floor":
		return {}
	var out := {}
	for q in _sel_quads:
		out[Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))] = true
	return out

func _refresh_selection_overlay() -> void:
	# a selection change doesn't move the player or alter the layout, so RoomLight won't redraw on its
	# own; nudge it here so the "selection reads lit" overlay updates as the selection grows/clears.
	if room_light != null:
		room_light.queue_redraw()
	if _sel_kind == "floor":
		# trace the full fill set (interior + under-wall ring) MINUS the surrounding wall sprites, so
		# the ants hug the VISIBLE wood exactly: interior plus the ring slivers that show on the wall
		# tiles where the narrow cap doesn't cover them. Verified by rasterising the geometry.
		_selection.set_floor(_sel_quads, _floor_occluders())
		_reflect_selection_brush() # mirror the selection's material + colour into the Brush panel
	elif _sel_kind == "wall":
		var obs = get_node_or_null("../Obstacles")
		var rects: Array = obs.wall_piece_rects(_sel_cells) if obs != null else []
		_selection.set_wall(_sel_cells, rects)
		_reflect_wall_selection_brush() # mirror the wall selection's material + colour into the panel
	else:
		_selection.clear()
	selection_changed.emit() # let the panel surface the section matching the current selection kind

# the wall sprite rects that cover the floor selection, so the overlay can subtract them and trace
# the visible floor. Gathers every wall in the selection's cell bounding box (expanded by one cell,
# since a wall's front face droops down into the cell below), then their cap/face piece rects. Only
# real walls occlude here (doors are separate nodes and keep their own handling).
func _floor_occluders() -> Array:
	var obs = get_node_or_null("../Obstacles")
	if obs == null or _sel_quads.is_empty():
		return []
	var minc := Vector2i(1 << 30, 1 << 30)
	var maxc := Vector2i(-(1 << 30), -(1 << 30))
	for q in _sel_quads:
		var c := Vector2i(floori(q.x / 2.0), floori(q.y / 2.0)) # quarter -> owning cell
		minc.x = mini(minc.x, c.x); minc.y = mini(minc.y, c.y)
		maxc.x = maxi(maxc.x, c.x); maxc.y = maxi(maxc.y, c.y)
	var walls := {}
	for cx in range(minc.x - 1, maxc.x + 2):
		for cy in range(minc.y - 1, maxc.y + 2):
			var cc := Vector2i(cx, cy)
			if obs.is_blocked(cc):
				walls[cc] = true
	return obs.wall_piece_rects(walls)

func _clear_selection() -> void:
	_sel_kind = ""
	_sel_quads = {}
	_sel_cells = {}
	_sel_level = 0
	_selection.clear()

# does the world-local point `local` fall inside the current selection? Floor selections are keyed by
# 16px quarter, wall selections by 32px cell. Used to decide whether a right-click acts on the
# selection (inside) or deselects it (outside), per "Editor UX revisions" -> deselect a Wand selection.
func _click_in_selection(local: Vector2) -> bool:
	if _sel_kind == "floor":
		return _sel_quads.has(Vector2i(floori(local.x / HALF), floori(local.y / HALF)))
	elif _sel_kind == "wall":
		return _sel_cells.has(Vector2i(floori(local.x / CELL), floori(local.y / CELL)))
	return false

# --- copy / paste / duplicate / move (ROADMAP "Copy, paste, and duplicate" + "Move tool") ---
#
# All four gestures ride ONE pending-clip state: an armed clip (`_pending_clip`) plus how it will be
# dropped (`_pending_kind`). The hover ghost, the rotate/flip keys and the drop are shared; only the
# origin differs (a paste centres on the cursor, a move follows the grab point) and what happens on
# drop (a paste stamps, a move stamps AND clears its source, in one undo entry).

# the CELLS the current selection covers: every cell owning a selected floor quarter, or the selected
# wall cells. This is the clip footprint, so magic-wand-selecting a room (floor + its wall ring) and
# copying takes the room's floor AND the walls/doors around it.
func _selection_cells() -> Dictionary:
	var out := {}
	if _sel_kind == "floor":
		for q in _sel_quads:
			out[Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))] = true
	elif _sel_kind == "wall":
		for c in _sel_cells:
			out[c] = true
	return out

# would a stamped cell actually land? (in bounds and not an absent-cell hole) -- drives the ghost's
# green/red footprint and matches MapEdit._apply_clip's clipping rule exactly.
func _stampable(cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return false
	var gb = get_node_or_null("../GridBackground")
	return gb == null or gb.cell_present(cell.x, cell.y)

# Ctrl+C: put the current selection's region on the (cross-map, disk-backed) clipboard.
func _copy_selection() -> bool:
	var cells := _selection_cells()
	if cells.is_empty():
		return false
	MapClipboard.set_clip(MapClipboard.build_clip(MapIO.serialize(), cells))
	return true

# Ctrl+V (and duplicate): arm `clip` as a paste brush; the ghost follows the cursor until a click.
func _arm_paste(clip: Dictionary) -> void:
	if clip.is_empty():
		return
	_pending_clip = clip
	_pending_kind = "paste"
	_pending_changed = false
	_pending_id += 1
	_reset_highlight()
	call_deferred("_update_hover")

# MOVE mode: grab the current selection at `grab` and start dragging it.
func _begin_move(grab: Vector2i) -> void:
	var cells := _selection_cells()
	if cells.is_empty():
		return
	var minc := Vector2i(1 << 30, 1 << 30)
	for c in cells:
		minc.x = mini(minc.x, c.x); minc.y = mini(minc.y, c.y)
	# built from the live map, NOT from the clipboard: a move must never clobber what the user copied
	_pending_clip = MapClipboard.build_clip(MapIO.serialize(), cells)
	_pending_kind = "move"
	_pending_changed = false
	_pending_id += 1
	_move_src = cells
	_move_origin = minc
	_move_grab = grab
	call_deferred("_update_hover")

# rotate/flip the armed clip in place (R / H / Shift+H), keeping the gesture going.
func _transform_pending(clip: Dictionary) -> void:
	if clip.is_empty():
		return
	_pending_clip = clip
	_pending_changed = true # so a move that only rotates still counts as an edit
	_pending_id += 1
	call_deferred("_update_hover")

# where the armed clip's top-left cell currently sits: a PASTE centres the block on the cursor (so
# hovering reads as carrying it), a MOVE keeps the offset from the cell the drag grabbed.
func _pending_origin() -> Vector2i:
	if _ghost_origin_pin != INVALID_CELL:
		return _ghost_origin_pin # pinned by the capture harness; never set in normal play
	var local := get_local_mouse_position()
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if _pending_kind == "move":
		return _move_origin + (cell - _move_grab)
	return cell - Vector2i(int(_pending_clip.get("w", 1)) / 2, int(_pending_clip.get("h", 1)) / 2)

# drop the armed clip: stamp a paste, or complete a move (clear the source + stamp), one undo entry.
# The landed region becomes the selection, so it can be moved again or filled straight away.
func _drop_pending() -> void:
	var origin := _pending_origin()
	var stamped := {}
	if _pending_kind == "move":
		if origin != _move_origin or _pending_changed:
			stamped = MapEdit.move_clip(_move_src, _pending_clip, origin)
		else:
			stamped = _move_src # dropped where it started: no edit, keep the selection put
	else:
		stamped = MapEdit.stamp_clip(_pending_clip, origin)
	_cancel_pending()
	if not stamped.is_empty():
		_select_cells(stamped)
	_reset_highlight()
	call_deferred("_update_hover")

# make `cells` the current selection (every quarter of each), used after a paste/move so the landed
# region is immediately actionable.
func _select_cells(cells: Dictionary) -> void:
	_sel_kind = "floor"
	_sel_cells = {}
	_sel_level = 0
	_sel_quads = {}
	for c in cells:
		for q in _cell_quads(c):
			_sel_quads[q] = true
	_refresh_selection_overlay()

# drop the armed paste / abort the move drag without editing the map
func _cancel_pending() -> void:
	_pending_clip = {}
	_pending_kind = ""
	_pending_changed = false
	_move_src = {}
	_clip_ghost.hide_clip()

func _fill_floor_selection(mat: String) -> void:
	var valid := mat != "" and textures.has(mat)
	for q in _sel_quads:
		if valid:
			_quad_mat[q] = mat
			_stamp_bank(q, mat)
		else:
			_quad_mat.erase(q)
			_quad_no_bank.erase(q)
	_rebuild()

# world-space quarter rects of the current floor selection, EXCLUDING quarters under a wall/door (the
# selection's under-structure ring), so the shape-drop animation lands on visible floor only and does
# not draw a lifted tile over a wall. Used to animate a selection fill (see play_shape_drop).
func _selection_drop_rects() -> Array:
	var obs = get_node_or_null("../Obstacles")
	var out: Array = []
	for q in _sel_quads:
		var cell := Vector2i(floori(q.x / 2.0), floori(q.y / 2.0)) # 2 quarters per 32px cell axis
		if obs != null and obs.has_structure(cell):
			continue
		out.append(Rect2(q.x * HALF, q.y * HALF, HALF, HALF))
	return out

func _fill_wall_selection(color: Color) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs != null:
		obs._color_cells(_sel_cells, color)

func _fill_wall_material_selection(material: String) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs != null:
		obs._material_cells(_sel_cells, material)

# hide every highlight so a fresh edit reads clearly; they return on the next mouse move
func _reset_highlight() -> void:
	_hover_cell = INVALID_CELL
	_wall_hover = INVALID_CELL
	_whole_hover_key = ""
	_mask.hide_floor()
	_cursor.hide_cursor()
	_preview.hide_preview()
	if _bridge_preview != null:
		_bridge_preview.visible = false
	_hide_wall_ghost()
	_hide_door_ghost()
	if _clip_ghost != null:
		_clip_ghost.hide_clip() # an armed clip re-shows it on the next hover; off-window/over-UI it goes

# --- reference grid toggle ---

func set_grid(on: bool) -> void:
	if _grid_on == on:
		return
	_grid_on = on
	_redraw_floor_layers()

func grid_on() -> bool:
	return _grid_on

func grid_color() -> Color:
	return GRID_COLOR

# --- hover highlight ---

# the highlight tracks the active scope and tool: Whole outlines the one thing under the cursor
# (that building's walls over a wall, that room's floor over a floor); a wall tool at Cell/Line
# outlines the wall geometry; a floor tool at Cell/Quarter shows the plain square paint cursor.
func _update_hover() -> void:
	if _menu.visible:
		return # keep the highlight put while the menu is open
	if not _mouse_inside:
		return # cursor is off the game window; highlights were cleared on exit
	var local := get_local_mouse_position()
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	# an armed paste / an in-flight move owns the hover surface: the clip ghost replaces every other
	# cursor, so what is about to land is the only thing previewed.
	if not _pending_clip.is_empty():
		_clear_room_hover()
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		_clip_ghost.show_clip(_pending_clip, _pending_origin(), _pending_id)
		return
	_clip_ghost.hide_clip()
	if _mode == Mode.MOVE:
		# MOVE with nothing grabbed: the marching ants already mark what a drag would pick up, so no
		# extra cursor (a paint cursor here would read as "this cell will be edited", which it will not)
		_clear_room_hover()
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		return
	# Wand: preview the ONE thing a click would select (building walls over a wall, room floor over
	# a floor). The committed selection is drawn separately by the marching-ants overlay.
	if _mode == Mode.WAND:
		_update_whole_hover(cell)
		return
	if _mode == Mode.BOX:
		# box-select draws its rectangle during the drag (marching-ants overlay); no paint cursor/preview
		_clear_room_hover()
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		return
	# Bridge: a green target cell + the actual deck art lifted above it, oriented to the water run
	if _mode == Mode.BRIDGE:
		_update_bridge_hover(cell)
		return
	# Wall / Door placement and Select: a green cell cursor marks the target cell
	if _mode == Mode.WALL or _mode == Mode.DOOR or _mode == Mode.SELECT:
		_update_structure_placement_hover(cell)
		return
	# after a wall colour or material is picked, outline the single wall under the cursor
	if _tool_kind == "wall" or _tool_kind == "wall_mat":
		_update_wall_hover(cell)
		return
	# Cell / Fine / Erase: the square paint cursor over paintable ground, and any obstacle over that
	# cell dimmed so the ground under it stays visible while painting
	_clear_room_hover()
	if not _paintable(cell):
		_cursor.hide_cursor()
		_preview.hide_preview()
		_restore_faded()
		return
	_fade_obstacles_at(cell)
	# terrain paint is a ground edit (orange); erase is destructive (red)
	_cursor.set_role(PaintCursor.Role.ERASE if _mode == Mode.ERASE else PaintCursor.Role.GROUND)
	if _mode == Mode.FINE:
		var q := Vector2i(floori(local.x / HALF), floori(local.y / HALF))
		var r := Rect2(q.x * HALF, q.y * HALF, HALF, HALF)
		_cursor.show_rect(r)
		_show_preview(r)
	else: # Cell or Erase -> the whole cell
		var r := Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
		_cursor.show_rect(r)
		_show_preview(r)

# arm the lifted drop-preview over `rect` when a real material is armed in a placement mode; Erase
# (removal) and the grass eraser show only the square cursor, no floating tile.
func _show_preview(rect: Rect2) -> void:
	# the floor-colour and pattern tools re-texture/tint an existing floor, so they show only the
	# square cursor, no lifted tile (there is nothing being dropped). Same for Erase, the grass eraser,
	# and an un-armed Cell/Fine (no material picked yet).
	if _mode == Mode.ERASE or _tool_kind == "floor_color" or _tool_kind == "pattern" or not _armed or not textures.has(_brush):
		_preview.hide_preview()
		return
	_preview.arm(_mat_tex(_brush, 0), _floor_color)
	_preview.show_at(rect)

# clear the mask highlight and reset the dedupe cells so a later hover recomputes cleanly
func _clear_room_hover() -> void:
	if _hover_cell == INVALID_CELL:
		return
	_hover_cell = INVALID_CELL
	_mask.hide_floor()

# Whole scope (either tool): outline the ONE thing under the cursor. Over a wall's STONE it outlines
# that building's walls; over a room floor (incl. the floor part of a wall cell, where the ring wood
# shows) it outlines that room's floor. Never both at once. Sub-cell aware: hovering the exposed
# floor of a wall cell highlights the room, not the wall (per user request).
func _update_whole_hover(cell: Vector2i) -> void:
	var local := get_local_mouse_position()
	var obs = get_node_or_null("../Obstacles")
	var on_stone: bool = obs != null and _over_wall(cell, local)
	# which room to highlight when not over stone: this cell if it is a room floor, else the adjacent
	# room whose ring wood the cursor is sitting on (the floor part of a wall/door cell).
	var room_seed := INVALID_CELL
	if not on_stone:
		if room_light.is_enclosed_floor(cell):
			room_seed = cell
		else:
			room_seed = _adjacent_room_cell(cell, local)
	var key := ("w:" + str(cell)) if on_stone else (("r:" + str(room_seed)) if room_seed != INVALID_CELL else "")
	if key == _whole_hover_key:
		return
	_whole_hover_key = key
	_cursor.hide_cursor()
	_restore_faded()
	_hover_cell = INVALID_CELL
	_wall_hover = INVALID_CELL
	if on_stone:
		_mask.show_walls(obs.wall_piece_rects(obs.building_cells(cell)))
	elif room_seed != INVALID_CELL:
		var room_cells: Dictionary = room_light.room_floor_cells(room_seed)
		_mask.show_floor(room_cells, room_light.wall_ring_quads(room_cells))
	else:
		_mask.hide_floor()

# wall tool: outline the wall the cursor is over via the mask (no ground, no shadows). Only lights up
# when the cursor is over the actual STONE geometry, not the exposed floor part of a wall cell.
func _update_wall_hover(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs == null or not _over_wall(cell, get_local_mouse_position()):
		if _wall_hover != INVALID_CELL:
			_wall_hover = INVALID_CELL
			_mask.hide_floor()
		return
	if cell == _wall_hover:
		return # already outlining this wall
	_wall_hover = cell
	_cursor.hide_cursor()
	_clear_room_hover()
	_restore_faded()
	_mask.show_walls(obs.wall_piece_rects({cell: true}))

# true only when `local` (World-space) sits on the actual wall STONE of `cell` (its cap/face rects),
# not the exposed floor part of a wall cell. Used so hovering the visible floor of a wall cell does
# not light up the wall.
func _over_wall(cell: Vector2i, local: Vector2) -> bool:
	var obs = get_node_or_null("../Obstacles")
	if obs == null or not obs.is_blocked(cell):
		return false
	for r in obs.wall_piece_rects({cell: true}):
		if r.has_point(local):
			return true
	return false

# the enclosed-floor room cell nearest `local` among `cell`'s orthogonal neighbours, or INVALID_CELL
# if none: the room whose ring wood the cursor is over when hovering the floor part of a wall/door.
func _adjacent_room_cell(cell: Vector2i, local: Vector2) -> Vector2i:
	var best := INVALID_CELL
	var best_d := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cell + d
		if room_light.is_enclosed_floor(n):
			var c := Vector2(n.x * CELL + CELL / 2.0, n.y * CELL + CELL / 2.0)
			var dist := local.distance_squared_to(c)
			if dist < best_d:
				best_d = dist
				best = n
	return best

# --- floor styles ---

# the four quarters a cell owns: cell c owns 2c, 2c+(1,0), 2c+(0,1), 2c+(1,1).
func _cell_quads(c: Vector2i) -> Array:
	return [Vector2i(c.x * 2, c.y * 2), Vector2i(c.x * 2 + 1, c.y * 2),
			Vector2i(c.x * 2, c.y * 2 + 1), Vector2i(c.x * 2 + 1, c.y * 2 + 1)]

# --- painting (the authoring surface over the quarter store) ---

# apply the active tool at the active scope, at World-space local position `local`.
# `drop` (set on a fresh click, not on drag-moves) plays the terrain drop animation when a real
# material lands, so a single placement gets the falling-tile effect without spamming it per cell
# as a drag sweeps across the map.
func _paint(local: Vector2, drop := false) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	# Wall mode drag: draw a wall line (routed here via the shared _painting drag path)
	if _mode == Mode.WALL:
		_place_wall_at(local)
		return
	# after a wall colour was picked, a drag colours the walls it passes over
	if _tool_kind == "wall":
		_paint_wall(cell)
		return
	# after a wall material was picked, a drag applies it to the walls it passes over
	if _tool_kind == "wall_mat":
		_paint_wall_material(cell)
		return
	# after a floor colour was picked, a drag tints the cells/quarters it passes over
	if _tool_kind == "floor_color":
		_paint_floor_color(local)
		return
	# after a floor pattern was picked, a drag re-patterns the cells/quarters it passes over
	if _tool_kind == "pattern":
		_paint_floor_pattern(local)
		return
	if not _paintable(cell):
		return
	# Cell/Fine place nothing until a material is armed (picked from the menu); Erase is always active.
	if _mode != Mode.ERASE and not _armed:
		return
	# Erase writes grass ("") over the cell; Cell/Fine write the active brush.
	var mat := "" if _mode == Mode.ERASE else _brush
	# the floor brush is COMBINED: a paint lays the armed material AND the armed colour into the same
	# quarter (material and tint are independent axes, stored in _quad_mat / _quad_tint). Natural/white
	# tint clears any prior tint; erasing clears the tint too so the cell returns to plain grass.
	var tint := Color.WHITE if _mode == Mode.ERASE else _floor_color
	var changed := false
	var rect := Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
	if _mode == Mode.FINE:
		var q := Vector2i(floori(local.x / HALF), floori(local.y / HALF))
		rect = Rect2(q.x * HALF, q.y * HALF, HALF, HALF)
		changed = _write_quad(q, mat)
		changed = _write_tint(q, tint) or changed
	else: # Cell or Erase -> the whole cell
		for q in _cell_quads(cell):
			changed = _write_quad(q, mat) or changed
			changed = _write_tint(q, tint) or changed
	if changed:
		_rebuild()
		if drop and mat != "" and textures.has(mat):
			_preview.play_drop(rect) # falling-tile effect for this placement

# wall tool drag: colour the single wall segment under the cursor. No-op off a wall. Whole-building
# colouring is done from the menu path (Wand mode) or a wall selection, not by dragging.
func _paint_wall(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs == null or not obs.is_blocked(cell):
		return
	obs.set_wall_color(cell, _wall_color)

# wall-material tool drag: apply the active _wall_mat to the single wall segment under the cursor.
# No-op off a wall. Whole-building materialling is done from the menu (Wand mode) or a selection.
func _paint_wall_material(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs == null or not obs.is_blocked(cell):
		return
	obs.set_wall_material(cell, _wall_mat)

# floor-colour tool drag: tint the cell (Cell mode) or quarter (Fine mode) under the cursor with
# the active _floor_color. No-op off the map. Whole-room / selection tinting is done from the menu.
func _paint_floor_color(local: Vector2) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if not _paintable(cell):
		return
	var changed := false
	if _mode == Mode.FINE:
		changed = _write_tint(Vector2i(floori(local.x / HALF), floori(local.y / HALF)), _floor_color)
	else: # Cell (or any non-Fine grain) -> the whole cell
		changed = _tint_cell(cell, _floor_color)
	if changed:
		_rebuild()

# pattern-tool drag: apply the active _pattern to the cell (Cell mode) or quarter (Fine mode) under
# the cursor. No-op off the map or over a quarter with no material (_write_pattern guards that).
func _paint_floor_pattern(local: Vector2) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if not _paintable(cell):
		return
	var changed := false
	if _mode == Mode.FINE:
		changed = _write_pattern(Vector2i(floori(local.x / HALF), floori(local.y / HALF)), _pattern)
	else: # Cell (or any non-Fine grain) -> the whole cell
		changed = _pattern_cell(cell, _pattern)
	if changed:
		_rebuild()

# set one quarter's tint (Natural/white erases the entry, so the floor reads its plain material).
# Returns whether anything changed, so a drag inside one quarter doesn't trigger a redundant rebuild.
func _write_tint(q: Vector2i, color: Color) -> bool:
	if color == Color.WHITE:
		if not _quad_tint.has(q):
			return false
		_quad_tint.erase(q)
		return true
	if _quad_tint.get(q) == color:
		return false
	_quad_tint[q] = color
	return true

# tint all four quarters of a cell; returns true if any changed.
func _tint_cell(cell: Vector2i, color: Color) -> bool:
	var changed := false
	for q in _cell_quads(cell):
		changed = _write_tint(q, color) or changed
	return changed

# tint a whole room: interior floor quarters plus the room-facing wall/door ring, matching how a
# room material fill reaches under the walls (_write_room). No-op (returns false) outside a room.
func _tint_room(cell: Vector2i, color: Color) -> bool:
	var cells: Dictionary = room_light.room_floor_cells(cell)
	if cells.is_empty():
		return false
	var changed := false
	for c in cells:
		for q in _cell_quads(c):
			changed = _write_tint(q, color) or changed
	for rect in room_light.wall_ring_quads(cells):
		var q := Vector2i(floori(rect.position.x / HALF), floori(rect.position.y / HALF))
		changed = _write_tint(q, color) or changed
	return changed

# tint every quarter of the active floor selection (the Magic Wand marching-ants set).
func _tint_selection(color: Color) -> bool:
	var changed := false
	for q in _sel_quads:
		changed = _write_tint(q, color) or changed
	return changed

# --- floor patterns: the same grain dispatch as tints, over _quad_pattern instead of _quad_tint.
# _write_pattern is a no-op on a quarter with no material, so grass quarters are skipped automatically.

func _pattern_cell(cell: Vector2i, idx: int) -> bool:
	var changed := false
	for q in _cell_quads(cell):
		changed = _write_pattern(q, idx) or changed
	return changed

func _pattern_room(cell: Vector2i, idx: int) -> bool:
	var cells: Dictionary = room_light.room_floor_cells(cell)
	if cells.is_empty():
		return false
	var changed := false
	for c in cells:
		for q in _cell_quads(c):
			changed = _write_pattern(q, idx) or changed
	for rect in room_light.wall_ring_quads(cells):
		var q := Vector2i(floori(rect.position.x / HALF), floori(rect.position.y / HALF))
		changed = _write_pattern(q, idx) or changed
	return changed

func _pattern_selection(idx: int) -> bool:
	var changed := false
	for q in _sel_quads:
		changed = _write_pattern(q, idx) or changed
	return changed

# apply pattern `idx` to the right-clicked target at the current grain (mirrors _apply_floor_tint):
# a floor selection, else Wand -> whole room, Fine -> the quarter, Cell -> the whole cell.
func _apply_floor_pattern(idx: int) -> bool:
	var cell := Vector2i(floori(_pending.x / CELL), floori(_pending.y / CELL))
	if _sel_kind == "floor" and _selection.has_selection():
		return _pattern_selection(idx)
	elif _mode == Mode.WAND:
		return _pattern_room(cell, idx)
	elif _mode == Mode.FINE:
		return _write_pattern(Vector2i(floori(_pending.x / HALF), floori(_pending.y / HALF)), idx)
	else: # Cell / Erase -> the whole cell
		return _pattern_cell(cell, idx)

# Erase mode: remove the wall or door on the clicked cell (the structure layer, topmost after any
# object). Rebuilds the level through the same MapIO path load/resize use, so lighting, floors and
# shadows recompute consistently after a wall opens a room up. Returns true if a structure was
# removed, so the caller leaves the terrain for a follow-up click and skips the paint drag. One
# click = one removal = one undo entry (ROADMAP "Erase mode").
func _erase_structure_at(local: Vector2) -> bool:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if not _in_bounds(cell):
		return false
	var obs = get_node_or_null("../Obstacles")
	if obs == null:
		return false
	# topmost-first: a wall/door goes before a bridge (they never coexist, but keep the order explicit),
	# and both go before the floor beneath. remove_bridge is only tried when no wall/door was removed.
	if obs.remove_structure(cell) == "" and not obs.remove_bridge(cell):
		return false
	_restore_faded() # the erased wall/door/bridge was dimmed under the cursor; drop the stale node ref
	MapIO.apply_serialized(MapIO.serialize(), true) # rebuild nodes + lighting + floors + shadows
	EditHistory.commit("erase")
	_reset_highlight()
	call_deferred("_update_hover") # re-detect the hover now the structure is gone
	return true

# Wall mode: add a wall on the clicked/dragged cell. add_wall no-ops on a cell that already holds a
# structure, so a drag over existing walls (or a repeat within one cell) triggers no rebuild.
func _place_wall_at(local: Vector2) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if not _in_bounds(cell):
		return
	var obs = get_node_or_null("../Obstacles")
	if obs == null or not obs.add_wall(cell):
		return
	# stamp the armed wall brush onto the new wall (set the source-of-truth dicts BEFORE the rebuild so
	# serialize carries them). Natural white / stone leave the wall plain. Same _wall_color / _wall_mat the
	# Brush panel and the Build Wall configurator arm, so what you picked is what you build.
	if _wall_color != Color.WHITE:
		obs.wall_colors[cell] = _wall_color
	if _wall_mat != "stone":
		obs.wall_materials[cell] = _wall_mat
	_walls_dirty = true # rebuild once in _process (coalesces a fast drag's many cells into one rebuild/frame)

# --- Build Wall configurator (right-click "Build Wall" submenu) ---

# reflect the current wall brush (_wall_color / _wall_mat) as the checked radio items
func _sync_build_wall_checks() -> void:
	if _build_wall_sub == null:
		return
	for i in WALL_COLORS.size():
		_build_wall_sub.set_item_checked(_build_wall_sub.get_item_index(i), WALL_COLORS[i][1] == _wall_color)
	for j in WALL_MATERIALS.size():
		_build_wall_sub.set_item_checked(_build_wall_sub.get_item_index(100 + j), WALL_MATERIALS[j][1] == _wall_mat)

func _on_build_wall_id(id: int) -> void:
	if id == 999:
		_arm_wall_build() # done configuring: enter Wall mode with the brush, close the menu
		return
	if id >= 100:
		_wall_mat = WALL_MATERIALS[id - 100][1]
	else:
		_wall_color = WALL_COLORS[id][1]
	brush_changed.emit() # keep the left Brush panel's Wall section in sync with the configurator
	_sync_build_wall_checks() # update the ticks in place (the menu stays open for more options)

# arm the draggable wall brush: switch to Wall mode (so a drag draws a wall line carrying the brush),
# light the strip's Wall radio to match, and close the menu so the user can drop tiles in place.
func _arm_wall_build() -> void:
	set_mode(Mode.WALL)
	var ts = get_tree().get_first_node_in_group("tool_strip")
	if ts != null and ts.has_method("reflect_mode"):
		ts.reflect_mode(Mode.WALL)
	_menu.hide()

# Door mode: add a door on the clicked cell, orienting it to the wall run it bridges (falling back to
# the R-toggled default in open space). A wall on the cell becomes a doorway. One click = one undo.
func _place_door_at(local: Vector2) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if not _in_bounds(cell):
		return
	var obs = get_node_or_null("../Obstacles")
	if obs == null:
		return
	var orient: String = obs.wall_run_orientation(cell)
	if orient == "":
		orient = _door_orient
	if not obs.add_door(cell, orient):
		return
	_reapply_map()
	EditHistory.commit("door")

# BRIDGE tool: drop a crossable deck on the clicked cell, auto-oriented to the water run it spans.
# A horizontal river (water to the left/right) is crossed north-south, so the bridge is "vertical";
# a vertical river (water above/below) gets a "horizontal" bridge. When the run is ambiguous (water on
# both axes, or none) fall back to _bridge_orient (R flips it), mirroring the door open-space default.
func _place_bridge_at(local: Vector2) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if not _in_bounds(cell):
		return
	var obs = get_node_or_null("../Obstacles")
	if obs == null:
		return
	if _cell_liquid(cell) == "lava":
		return # wooden bridges burn: they can only be built over WATER, not lava
	var orient := _bridge_river_orientation(cell)
	if orient == "":
		orient = _bridge_orient
	if not obs.add_bridge(cell, orient):
		return
	_reapply_map()
	EditHistory.commit("bridge")

# the majority liquid material at `cell` ("water"/"lava"/""), using the same >=2-of-4-quarters rule as
# is_cell_impassable. Lets bridges tell water (crossable) from lava (never bridgeable).
func _cell_liquid(cell: Vector2i) -> String:
	var water := 0
	var lava := 0
	for dx in 2:
		for dy in 2:
			match _quad_mat.get(Vector2i(cell.x * 2 + dx, cell.y * 2 + dy), ""):
				"water": water += 1
				"lava": lava += 1
	if water >= 2:
		return "water"
	if lava >= 2:
		return "lava"
	return ""

# the bridge orientation the WATER around `cell` implies, or "" if ambiguous. A horizontal river
# (water left/right) -> "vertical" bridge; a vertical river (water above/below) -> "horizontal". Lava is
# NOT counted here, so a bridge never orients to (or bridges) lava.
func _bridge_river_orientation(cell: Vector2i) -> String:
	var horiz_river := _cell_liquid(cell + Vector2i(1, 0)) == "water" or _cell_liquid(cell + Vector2i(-1, 0)) == "water"
	var vert_river := _cell_liquid(cell + Vector2i(0, 1)) == "water" or _cell_liquid(cell + Vector2i(0, -1)) == "water"
	if horiz_river and not vert_river:
		return "vertical"
	if vert_river and not horiz_river:
		return "horizontal"
	return ""

# Select tool: load the door or wall on the clicked cell into the properties inspector (a door wins
# if somehow both are present, matching the topmost-structure model). An empty cell clears it.
func _select_at(local: Vector2) -> void:
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	var inspector = get_tree().get_first_node_in_group("inspector")
	if inspector == null:
		return
	var obs = get_node_or_null("../Obstacles")
	if obs != null and not obs.door_at(cell).is_empty():
		inspector.inspect_door(cell)
	elif obs != null and obs.is_blocked(cell):
		inspector.inspect_wall(cell)
	else:
		inspector.clear()

# rebuild the level after a structure was added, through the same MapIO path erase/resize/load use,
# so lighting, floors and shadows recompute together (a newly enclosed room turns indoors). Undo is
# committed by the caller (per-gesture for walls, per-click for doors), not here.
func _reapply_map() -> void:
	_restore_faded()
	MapIO.apply_serialized(MapIO.serialize(), true)
	call_deferred("_update_hover")

# --- right-click menu: Door edits (mirror the inspector, one undo each) ---
func _edit_door(cell: Vector2i, id: int) -> void:
	var obs = get_node_or_null("../Obstacles")
	var d: Dictionary = obs.door_at(cell) if obs != null else {}
	if d.is_empty():
		return
	if id == DOOR_FLIP_ID:
		var flipped := "vertical" if d["orientation"] == "horizontal" else "horizontal"
		obs.set_door_orientation(cell, flipped)
		MapIO.apply_serialized(MapIO.serialize(), true) # structural: respawn the gate
		EditHistory.commit("door orientation")
	elif id == DOOR_OPEN_ID:
		obs.set_door_open(cell, not bool(d.get("open", false)))
		EditHistory.commit("door open")
	elif id == DOOR_SWING_ID:
		obs.set_door_swing(cell, not bool(d.get("swing", false)))
		EditHistory.commit("door swing")

# --- right-click menu / Delete key: Erase ---
# Erase acts on the current selection when there is one, else on the clicked target. Delete (see
# _unhandled_key_input) is the selection-only entry point. See ROADMAP "Editor UX revisions" -> Erase.
func _menu_erase(cell: Vector2i) -> void:
	if _selection.has_selection():
		_erase_selection()
	else:
		_erase_single(cell)

# erase the whole active selection: floor quarters back to grass (clearing material/pattern/tint), or
# every wall in a wall selection. One undo entry; the selection is cleared afterwards.
func _erase_selection() -> void:
	if _sel_kind == "floor":
		for q in _sel_quads:
			_quad_mat.erase(q)
			_quad_pattern.erase(q)
			_quad_tint.erase(q)
		_rebuild()
		EditHistory.commit("erase")
	elif _sel_kind == "wall":
		var obs = get_node_or_null("../Obstacles")
		var any := false
		if obs != null:
			for c in _sel_cells:
				if obs.remove_structure(c) != "":
					any = true
		if any:
			_restore_faded()
			MapIO.apply_serialized(MapIO.serialize(), true)
			EditHistory.commit("erase")
	_clear_selection()
	_reset_highlight()
	call_deferred("_update_hover")

# erase the single clicked target: remove a wall/door if one is there, else clear the cell's ground.
func _erase_single(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs != null and obs.has_structure(cell):
		obs.remove_structure(cell)
		_restore_faded()
		MapIO.apply_serialized(MapIO.serialize(), true)
		EditHistory.commit("erase")
		_reset_highlight()
		call_deferred("_update_hover")
		return
	# a bridge is the next layer down (over the water floor): erase it before the ground beneath
	if obs != null and obs.is_bridge(cell):
		obs.remove_bridge(cell)
		_restore_faded()
		MapIO.apply_serialized(MapIO.serialize(), true)
		EditHistory.commit("erase")
		_reset_highlight()
		call_deferred("_update_hover")
		return
	var changed := false
	for q in _cell_quads(cell):
		if _quad_mat.has(q) or _quad_pattern.has(q) or _quad_tint.has(q):
			_quad_mat.erase(q)
			_quad_pattern.erase(q)
			_quad_tint.erase(q)
			changed = true
	if changed:
		_rebuild()
		EditHistory.commit("erase")
	_reset_highlight()

# Wall/Door placement hover: a plain green cell cursor over any in-bounds cell showing where the next
# wall or door lands. No drop-preview sprite yet (walls/doors have no lifted tile art), just the cell.
func _update_structure_placement_hover(cell: Vector2i) -> void:
	_clear_room_hover()
	_restore_faded()
	_preview.hide_preview()
	if not _in_bounds(cell):
		_cursor.hide_cursor()
		_hide_wall_ghost()
		_hide_door_ghost()
		return
	_cursor.set_role(PaintCursor.Role.ADD) # green: placing a wall/door is additive
	_cursor.show_rect(Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL))
	# Also float the REAL thing a click would place, like the bridge deck preview. WALL: the wall shape
	# (horizontal/vertical/corner/T/cross) in the armed colour+material, over an empty cell. DOOR: the
	# closed door, auto-oriented to the wall run it would bridge.
	var obs = get_node_or_null("../Obstacles")
	if _mode == Mode.WALL and obs != null and not obs.is_blocked(cell):
		_show_wall_ghost(cell)
		_hide_door_ghost()
	elif _mode == Mode.DOOR and obs != null:
		_hide_wall_ghost()
		_show_door_ghost(cell, obs)
	else:
		_hide_wall_ghost()
		_hide_door_ghost()

# configure + show the door ghost for `cell`: auto-orient exactly like _place_door_at (the wall run it
# bridges, else the R-flippable default), positioned at the cell centre, drawn closed + translucent.
func _show_door_ghost(cell: Vector2i, obs) -> void:
	if _door_preview == null:
		return
	var orient: String = obs.wall_run_orientation(cell)
	if orient == "":
		orient = _door_orient
	var key := "%s|%s" % [cell, orient]
	if key == _door_ghost_key and _door_preview.visible:
		return
	_door_ghost_key = key
	_door_preview.set_preview_orientation(orient)
	_door_preview.position = Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0)
	_door_preview.visible = true

func _hide_door_ghost() -> void:
	if _door_preview == null or not _door_preview.visible:
		return
	_door_ghost_key = ""
	_door_preview.visible = false

# configure + show the wall placement ghost for `cell`: obstacles computes the piece config(s) the cell
# would get (same shaping as build_world), which we apply to the reused preview wall_segments, carrying
# the armed wall colour+material so the ghost previews exactly what a click builds.
func _show_wall_ghost(cell: Vector2i) -> void:
	var obs = get_node_or_null("../Obstacles")
	if obs == null:
		return
	var configs: Array = obs.preview_wall_configs(cell)
	var key := "%s|%s|%s|%d" % [cell, _wall_color, _wall_mat, configs.size()]
	if key == _wall_ghost_key:
		return # nothing changed (same cell + brush + shape): leave the ghost as-is
	_wall_ghost_key = key
	var center := Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0)
	for i in _wall_ghost.size():
		var wp = _wall_ghost[i]
		if i < configs.size():
			var cfg: Dictionary = configs[i]
			wp.run_length = int(cfg["run_length"])
			wp.align_offset_x = float(cfg["align"])
			wp.seg_x_start = float(cfg["x_start"])
			wp.seg_width = float(cfg["width"])
			wp.cell_colors = [_wall_color]
			wp.cell_materials = [_wall_mat]
			wp.position = center
			wp.visible = true
			wp.queue_redraw()
		else:
			wp.visible = false

func _hide_wall_ghost() -> void:
	if _wall_ghost_key == "":
		return
	_wall_ghost_key = ""
	for wp in _wall_ghost:
		wp.visible = false

# Bridge placement hover: a green ADD cell cursor (like wall/door) PLUS the real deck art lifted a few
# px above the cell, oriented to the water run the click would span (or the R-flippable default). Shows
# the bridge that will land instead of the last floor material's drop-preview.
const _BRIDGE_PREVIEW_LIFT := 6.0
func _update_bridge_hover(cell: Vector2i) -> void:
	_clear_room_hover()
	_restore_faded()
	_preview.hide_preview() # never show the leftover floor-material drop-preview in BRIDGE mode
	if not _in_bounds(cell):
		_cursor.hide_cursor()
		_bridge_preview.visible = false
		return
	# lava can't be bridged (wooden bridges burn): mark it invalid (red cursor, no deck preview)
	if _cell_liquid(cell) == "lava":
		_cursor.set_role(PaintCursor.Role.ERASE)
		_cursor.show_rect(Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL))
		_bridge_preview.visible = false
		return
	_cursor.set_role(PaintCursor.Role.ADD)
	_cursor.show_rect(Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL))
	var orient := _bridge_river_orientation(cell)
	if orient == "":
		orient = _bridge_orient
	_bridge_preview.orientation = orient
	_bridge_preview.position = Vector2(cell.x * CELL + CELL / 2.0, cell.y * CELL + CELL / 2.0 - _BRIDGE_PREVIEW_LIFT)
	_bridge_preview.visible = true
	_bridge_preview.queue_redraw()

# set one quarter's material ("" erases it back to grass). Returns whether anything changed,
# so a drag that stays inside the same quarter doesn't trigger a redundant rebuild.
func _write_quad(q: Vector2i, mat: String) -> bool:
	if mat != "" and textures.has(mat):
		# a change is the material OR the bank flag flipping (re-painting a liquid with the switch toggled)
		var want_no_bank: bool = LIQUID_SHORE.has(mat) and not _bank_on
		var changed: bool = _quad_mat.get(q) != mat or _quad_no_bank.has(q) != want_no_bank
		_quad_mat[q] = mat
		_stamp_bank(q, mat)
		return changed
	if not _quad_mat.has(q):
		return _quad_no_bank.erase(q) # erasing already-grass: only a change if it cleared a stray flag
	_quad_mat.erase(q)
	_quad_pattern.erase(q) # grass carries no pattern; drop the orphaned index
	_quad_no_bank.erase(q)
	return true

# record the river-bank switch for a freshly-painted quarter: a LIQUID quarter laid with the switch OFF
# goes into _quad_no_bank (so it grows no bank); anything else clears any stale flag.
func _stamp_bank(q: Vector2i, mat: String) -> void:
	if LIQUID_SHORE.has(mat) and not _bank_on:
		_quad_no_bank[q] = true
	else:
		_quad_no_bank.erase(q)

# the Brush-panel river-bank switch (set BEFORE laying a liquid): on = new liquid grows a brown bank,
# off = none. Only affects quarters painted while it is on/off (stored per-quarter in _quad_no_bank).
func set_bank_on(on: bool) -> void:
	_bank_on = on
	brush_changed.emit()

func bank_on() -> bool:
	return _bank_on

# cells you may paint on: any cell inside the grid, walls included (the ground under a wall or
# door is editable; the obstacle over it fades to 30% while you paint, see _fade_obstacles_at)
func _paintable(cell: Vector2i) -> bool:
	return _in_bounds(cell)

# dim any wall/door standing on `cell` to 30% so its ground shows through while it is edited.
func _fade_obstacles_at(cell: Vector2i) -> void:
	if cell == _faded_cell:
		return # already dimmed for this cell
	_restore_faded()
	_faded_cell = cell
	# skip nodes already queued for deletion: an Erase rebuild frees the old wall/gate nodes but
	# they linger in their group for the rest of the frame, and fading one would leave a freed
	# reference in _faded that _restore_faded would later touch (use-after-free).
	for w in get_tree().get_nodes_in_group("walls"):
		if not w.is_queued_for_deletion() and w.has_method("covers_cell") and w.covers_cell(cell):
			_fade(w)
	for g in get_tree().get_nodes_in_group("gates"):
		if not g.is_queued_for_deletion() and g.cell == cell:
			_fade(g)
			if g.back_layer and not g.back_layer.is_queued_for_deletion():
				_fade(g.back_layer) # vertical gate's behind-player post + door

func _fade(node: CanvasItem) -> void:
	_faded.append([node, node.modulate])
	node.modulate.a = 0.3

# put every dimmed obstacle back to full opacity. Guards is_instance_valid because an Erase rebuild
# can free a faded wall/gate between fading and restoring, and touching a freed node throws.
func _restore_faded() -> void:
	for e in _faded:
		if is_instance_valid(e[0]):
			e[0].modulate = e[1]
	_faded.clear()
	_faded_cell = Vector2i(-9999, -9999)

func _in_bounds(cell: Vector2i) -> bool:
	var gb = get_node_or_null("../GridBackground")
	if gb == null:
		return true
	return cell.x >= 0 and cell.y >= 0 and cell.x < gb.grid_width and cell.y < gb.grid_height

# give the room containing `cell` a floor style ("" resets it to grass). A room fill is a
# convenience over the quarter store: it writes all four quarters of every cell in the room.
func set_room_style(cell: Vector2i, style: String) -> void:
	var cells: Dictionary = room_light.room_floor_cells(cell)
	if cells.is_empty():
		return
	_write_room(cells, style)
	_rebuild()

# fill a whole room with `style` ("" erases it to grass): every interior floor quarter AND the
# room-facing wall/door ring quarters, so the floor genuinely reaches under the walls and stays
# there as real data. Cell/Quarter painting deliberately never touches the ring, so laying a tile
# does not change the ground already stored under the walls.
func _write_room(cells: Dictionary, style: String) -> void:
	var valid := style != "" and textures.has(style)
	var quads: Array = []
	for c in cells:
		for q in _cell_quads(c):
			quads.append(q)
	for rect in room_light.wall_ring_quads(cells):
		quads.append(Vector2i(floori(rect.position.x / HALF), floori(rect.position.y / HALF)))
	for q in quads:
		if valid:
			_quad_mat[q] = style
			_stamp_bank(q, style)
		else:
			_quad_mat.erase(q)
			_quad_pattern.erase(q) # grass carries no pattern
			_quad_no_bank.erase(q)

# replace all floors from a v1 per-room style list (used by the MapIO v1->v2 load migration).
# Must run AFTER RoomLight has rebuilt, since the room a style fills is found by flood fill.
func apply_floors(list: Array) -> void:
	_quad_mat.clear()
	for f in list:
		var style: String = f["style"]
		if style == "" or not textures.has(style):
			continue
		_write_room(room_light.room_floor_cells(f["cell"]), style)
	_rebuild()

# replace all floors from a v2 quarter list [[qx, qy, material], ...] (used by MapIO on load).
func apply_quads(list: Array) -> void:
	_quad_mat.clear()
	_quad_no_bank.clear() # repopulated by apply_no_bank (MapIO calls it before the final rebuild)
	for a in list:
		var mat: String = a[2]
		if not textures.has(mat):
			continue
		_quad_mat[Vector2i(int(a[0]), int(a[1]))] = mat
	_rebuild()

# load the LIQUID river-bank OFF flags (MapIO v9+). No rebuild here (apply_tints does the final one),
# mirroring apply_patterns. A pre-v9 load passes [] so every liquid keeps its default bank.
func apply_no_bank(list: Array) -> void:
	_quad_no_bank.clear()
	for a in list:
		_quad_no_bank[Vector2i(int(a[0]), int(a[1]))] = true

# replace all floor patterns from a saved list [[qx, qy, index], ...] (used by MapIO on load). Only
# meaningful over quarters that also carry a material; a stale index is clamped at draw. Does NOT
# rebuild: apply_quads/apply_tints (which run around it) do, and the caller ends with a rebuild.
func apply_patterns(list: Array) -> void:
	_quad_pattern.clear()
	for a in list:
		var idx := int(a[2])
		if idx != 0:
			_quad_pattern[Vector2i(int(a[0]), int(a[1]))] = idx

# set one quarter's pattern index (0 erases the entry back to the default pattern). Returns whether
# anything changed. A no-op if the quarter has no material (pattern only means something over one).
func _write_pattern(q: Vector2i, idx: int) -> bool:
	if not _quad_mat.has(q):
		return false
	var cur: int = _quad_pattern.get(q, 0)
	if cur == idx:
		return false
	if idx == 0:
		_quad_pattern.erase(q)
	else:
		_quad_pattern[q] = idx
	return true

# the pattern index at 16px quarter `q` (0 = default). Read by the shadow restamp so a door-open
# relight redraws the same pattern the base_fills use.
func floor_pattern_at_quad(q: Vector2i) -> int:
	return _quad_pattern.get(q, 0)

# replace all floor tints from a v5 list [[qx, qy, r, g, b], ...] (used by MapIO on load). An
# empty list (a pre-v5 map) simply clears any tints. Must run AFTER apply_quads so the rebuild
# draws tints over the materials just restored.
func apply_tints(list: Array) -> void:
	_quad_tint.clear()
	for a in list:
		_quad_tint[Vector2i(int(a[0]), int(a[1]))] = Color(float(a[2]), float(a[3]), float(a[4]))
	_rebuild()

# _quad_mat is the whole floor (interior + under-wall quarters written by room fills), so the
# render is a straight one-rect-per-quarter pass. No room/uniformity derivation: laying a tile
# changes only that quarter and never disturbs the under-wall ground already stored.
# the texture for material `mat` at pattern index `pattern`, clamped to the material's variant range
# (so a stale pattern index left over from a different material never indexes out of bounds).
func _mat_tex(mat: String, pattern: int) -> Texture2D:
	var variants: Array = textures[mat]
	return variants[clampi(pattern, 0, variants.size() - 1)]

func _rebuild() -> void:
	_base_fills = []
	_has_water = false
	for q in _quad_mat:
		var rect := Rect2(q.x * HALF, q.y * HALF, HALF, HALF)
		var mat: String = _quad_mat[q]
		var tint: Color = _quad_tint.get(q, Color.WHITE)
		if LIQUID_SHORE.has(mat):
			# Liquids (water/lava): a feathered shore where they meet a different material, over a bank
			# underlay UNLESS the bank switch was off for this quarter (then the feather reveals grass).
			# Fills carry a 5th `true` so grid_background shimmers them; the bank underlay stays static.
			# mask 0 (open liquid) draws the flat, seamless, world-tiled tile, also animated.
			_has_water = true
			var mask := _liquid_edge_mask(q, mat)
			if mask != 0:
				if not _quad_no_bank.has(q):
					_base_fills.append([rect, RIVER_BANK, Color.WHITE]) # bank the feather reveals
				_base_fills.append([rect, LIQUID_SHORE[mat], tint, _shore_src(mask), true]) # feathered liquid
			else:
				_base_fills.append([rect, _mat_tex(mat, 0), tint, GridBackground.tiled_src(rect), true])
			continue
		elif EDGE_ATLAS.has(mat):
			# Auto-match: a natural terrain feathers over its lower-precedence orthogonal neighbours.
			var mask := _terrain_edge_mask(q, mat)
			if mask != 0:
				var under: String = _edge_underlay_mat(q, mat)
				if under != "": # reveal a non-base lower terrain (e.g. sand under snow) through the feather
					_base_fills.append([rect, _mat_tex(under, 0), Color.WHITE])
				_base_fills.append([rect, EDGE_ATLAS[mat], tint, _shore_src(mask)])
				continue
			# mask 0 (bordered only by same/higher terrain): fall through to the flat, seamless tile
		elif mat == "grass":
			# grass is the base: Plain (pattern 0) draws NOTHING so the ground grass shows through with no
			# patch seam (a tint still shows, matching the tint-only branch); Wild/Tuft draw an alpha blade
			# overlay over the base. Never falls through to the opaque generic tile.
			var gp: int = _quad_pattern.get(q, 0)
			if gp != 0:
				_base_fills.append([rect, _mat_tex("grass", gp), tint, GridBackground.tiled_src(rect)])
			elif tint != Color.WHITE:
				_base_fills.append([rect, GRASS, tint])
			continue
		_base_fills.append([rect, _mat_tex(mat, _quad_pattern.get(q, 0)), tint])
	# a quarter carrying a tint but NO material is a tinted patch of grass: draw the grass base
	# under the tint so the recolour shows (an unpainted quarter isn't in _quad_mat above).
	for q in _quad_tint:
		if _quad_mat.has(q):
			continue
		_base_fills.append([Rect2(q.x * HALF, q.y * HALF, HALF, HALF), GRASS, _quad_tint[q]])
	# River-bank auto-edge: every non-water quarter touching water (8-neighbour, in-bounds) draws the
	# brown bank on TOP of whatever is there. Appended last so it renders over the underlying fill;
	# untinted (native brown). Derived only, so it is neither saved nor blocking (see RIVER_BANK).
	for bq in _bank_quads():
		_base_fills.append([Rect2(bq.x * HALF, bq.y * HALF, HALF, HALF), RIVER_BANK, Color.WHITE])
	_redraw_floor_layers()

# the set of 16px quarter coords that render as river bank: any in-bounds quarter that is NOT a
# BANK_AROUND material but is 8-neighbour-adjacent to one. Returned as a dict (used as a set) so a
# quarter shared by several water quarters is emitted once. Purely derived from _quad_mat.
func _bank_quads() -> Dictionary:
	var bank := {}
	for q in _quad_mat:
		if not BANK_AROUND.has(_quad_mat[q]):
			continue
		if _quad_no_bank.has(q):
			continue # this liquid quarter was laid with the bank switch OFF
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n := Vector2i(q.x + dx, q.y + dy)
				if BANK_AROUND.has(_quad_mat.get(n, "")):
					continue # a neighbouring water quarter is not bank
				if not _in_bounds(Vector2i(floori(n.x / 2.0), floori(n.y / 2.0))):
					continue # keep bank inside the map grid, not out in the void
				bank[n] = true
	return bank

# the 4-bit LAND mask for a water quarter's ORTHOGONAL neighbours (N=1 E=2 S=4 W=8), used to pick the
# shoreline autotile variant. A side is "land" when its neighbour quarter is in-bounds and not water;
# out-of-map neighbours are NOT land, so water never feathers toward the map edge (it just clips there).
func _liquid_edge_mask(q: Vector2i, mat: String) -> int:
	var m := 0
	if _liquid_edge(q + Vector2i(0, -1), mat): m |= 1 # N
	if _liquid_edge(q + Vector2i(1, 0), mat):  m |= 2 # E
	if _liquid_edge(q + Vector2i(0, 1), mat):  m |= 4 # S
	if _liquid_edge(q + Vector2i(-1, 0), mat): m |= 8 # W
	return m

# a liquid `mat` quarter feathers toward neighbour `nq` when it is in-bounds and a DIFFERENT material (land,
# or the other liquid); out-of-map neighbours are not, so a liquid clips at the map edge instead of feathering.
func _liquid_edge(nq: Vector2i, mat: String) -> bool:
	if not _in_bounds(Vector2i(floori(nq.x / 2.0), floori(nq.y / 2.0))):
		return false
	return _quad_mat.get(nq, "") != mat

# the 4-bit edge mask for an auto-matching terrain quarter `mat` at `q` (N=1 E=2 S=4 W=8): a side is set
# when its orthogonal neighbour is an IN-BOUNDS natural terrain of STRICTLY LOWER precedence (so `mat`
# feathers over it). Out-of-map, same-rank, higher-rank (incl. water), and non-natural (indoor) neighbours
# never set a bit, so terrain never feathers toward the void, a peer, water, or a constructed floor.
func _terrain_edge_mask(q: Vector2i, mat: String) -> int:
	var r: int = TERRAIN_RANK.get(mat, 0)
	var m := 0
	if _lower_terrain(q + Vector2i(0, -1), r): m |= 1 # N
	if _lower_terrain(q + Vector2i(1, 0), r):  m |= 2 # E
	if _lower_terrain(q + Vector2i(0, 1), r):  m |= 4 # S
	if _lower_terrain(q + Vector2i(-1, 0), r): m |= 8 # W
	return m

# is neighbour quarter `nq` an in-bounds natural terrain ranked below `r`?
func _lower_terrain(nq: Vector2i, r: int) -> bool:
	if not _in_bounds(Vector2i(floori(nq.x / 2.0), floori(nq.y / 2.0))):
		return false
	var nmat: String = _quad_mat.get(nq, "")
	return TERRAIN_RANK.has(nmat) and TERRAIN_RANK[nmat] < r

# the material to lay UNDER a feathered edge quarter so the feather reveals the right lower terrain: the
# HIGHEST-ranked lower natural among the orthogonal neighbours. Returns "" (no underlay) when that is the
# grass base (rank 0), since the whole map already draws grass beneath every quarter.
func _edge_underlay_mat(q: Vector2i, mat: String) -> String:
	var r: int = TERRAIN_RANK.get(mat, 0)
	var best := ""
	var best_rank := 0
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var nq: Vector2i = q + d
		if not _in_bounds(Vector2i(floori(nq.x / 2.0), floori(nq.y / 2.0))):
			continue
		var nmat: String = _quad_mat.get(nq, "")
		if TERRAIN_RANK.has(nmat) and TERRAIN_RANK[nmat] < r and TERRAIN_RANK[nmat] > best_rank:
			best_rank = TERRAIN_RANK[nmat]
			best = nmat
	return best

# the atlas source rect for shoreline mask `m`: the 4x4 grid of 32px cells, indexed m%4 across, m/4 down.
func _shore_src(m: int) -> Rect2:
	return Rect2((m % 4) * SHORE_TILE, (m / 4) * SHORE_TILE, SHORE_TILE, SHORE_TILE)

func _redraw_floor_layers() -> void:
	var gb = get_node_or_null("../GridBackground")
	if gb:
		gb.queue_redraw()
	var sg = get_node_or_null("../ShadowGroup")
	if sg:
		sg.refresh()

# --- read by grid_background and shadow_manager ---

func base_fills() -> Array:
	return _base_fills

# any water on the map this rebuild, so grid_background runs the shimmer redraw loop only when needed
# (zero cost on a dry map). Set in _rebuild whenever a water quarter emits a fill.
func has_animated_water() -> bool:
	return _has_water

# the floor texture that renders at 16px quarter `q`, or null for the grass base. The single
# source of truth the door-open shadow pass restamps from, so it matches the indoor base_fills
# exactly (every painted quarter, interior or under a wall/door).
func floor_tex_at_quad(q: Vector2i):
	return _mat_tex(_quad_mat[q], _quad_pattern.get(q, 0)) if _quad_mat.has(q) else null

# the multiply tint at 16px quarter `q` (white = none), so the door-open shadow restamp tints the
# floor the same way base_fills does (see shadow_manager._stamp_floor).
func floor_tint_at_quad(q: Vector2i) -> Color:
	return _quad_tint.get(q, Color.WHITE)

# does the FLOOR at 32px cell `cell` block movement? Cell-level granularity (matches the 32px move
# grid): a cell holds 2x2 quarters, and it blocks when a MAJORITY (>=2 of 4) carry an IMPASSABLE
# material. Majority (not "any") keeps a lone stray quarter - e.g. a future shoreline/bank quarter -
# from sealing an otherwise-walkable cell; a full-water cell has all four, so it always blocks.
# Consulted by the player alongside obstacles.is_blocked (walls); see the IMPASSABLE note above.
func is_cell_impassable(cell: Vector2i) -> bool:
	var count := 0
	for dx in 2:
		for dy in 2:
			var q := Vector2i(cell.x * 2 + dx, cell.y * 2 + dy)
			if IMPASSABLE.has(_quad_mat.get(q, "")):
				count += 1
	return count >= 2
