class_name FloorMaterials
extends RefCounted

# The floor material catalogue: what each material looks like (its pattern variants, colour swatches)
# and the terrain rules the floor render and movement apply to it (which materials block, bank, feather
# into their neighbours). Pure data -- FloorManager owns the per-quarter stores that reference it, and the
# tool strip / inspector read the same lists, so the palette is defined once (like WallSegment's).

# each material maps to an ARRAY of pattern variants (index 0 = default, matches the pre-pattern
# single texture). The active pattern per quarter is stored in _quad_pattern (parallel to _quad_mat /
# _quad_tint), so pattern is an axis distinct from material and colour. A stale pattern index (e.g. a
# quarter that was herringbone wood, then painted concrete) is clamped to the material's range at draw.
const TEXTURES := {
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
# human names for each material's pattern variants, aligned by index with `TEXTURES`. Drives the
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

# the floor materials as [label, material], in menu / Brush-panel order
const MATERIAL_NAMES := [
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

# the fixed "fun" tints as [label, colour], parallel to WallSegment.COLORS (the values match where they
# overlap, so the two palettes read as one system). Natural = white = reset (erases the tint).
const COLORS := [
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

# The MATERIAL-AWARE half of the palette (ROADMAP "Colour palette: 16 swatches, half material-aware",
# decided 2026-08-16; the "fun" half above shipped 2026-08-16 and this was deferred). Eight realistic
# tints per material, so the swatches on offer always make sense for the thing being coloured: wood
# gets wood tones, stone gets greys, grass gets greens through to dry yellow. Selecting a material
# swaps this row; the fun row above never changes.
#
# These are TINTS multiplied over a greyscale base (see "Colour system cleanup": material = the grey
# pattern, colour = the tint), so they are chosen as multipliers, not as the final colour -- which is
# why they sit near white rather than at the saturations the names suggest.
const MATERIAL_COLORS := {
	"wood": [
		["Pine", Color(0.92, 0.78, 0.55)], ["Light Oak", Color(0.85, 0.66, 0.42)],
		["Oak", Color(0.72, 0.52, 0.32)], ["Cherry", Color(0.70, 0.40, 0.30)],
		["Walnut", Color(0.52, 0.36, 0.24)], ["Mahogany", Color(0.45, 0.26, 0.20)],
		["Dark Stain", Color(0.32, 0.23, 0.17)], ["Driftwood", Color(0.74, 0.72, 0.68)],
	],
	# concrete, tile and slate all read as constructed greys, so they share a stone ramp
	"concrete": [
		["Bone", Color(0.94, 0.92, 0.87)], ["Pale Grey", Color(0.84, 0.85, 0.86)],
		["Grey", Color(0.70, 0.71, 0.73)], ["Slate", Color(0.55, 0.58, 0.62)],
		["Steel", Color(0.46, 0.50, 0.56)], ["Charcoal", Color(0.34, 0.35, 0.38)],
		["Basalt", Color(0.24, 0.25, 0.28)], ["Sandstone", Color(0.88, 0.78, 0.60)],
	],
	"tile": [
		["White", Color(0.96, 0.96, 0.96)], ["Ivory", Color(0.93, 0.90, 0.80)],
		["Terracotta", Color(0.80, 0.45, 0.32)], ["Sage", Color(0.62, 0.74, 0.60)],
		["Sky", Color(0.62, 0.78, 0.90)], ["Cobalt", Color(0.36, 0.48, 0.78)],
		["Slate", Color(0.50, 0.54, 0.58)], ["Onyx", Color(0.28, 0.28, 0.32)],
	],
	"carpet": [
		["Cream", Color(0.93, 0.89, 0.80)], ["Sand", Color(0.85, 0.76, 0.60)],
		["Moss", Color(0.55, 0.65, 0.45)], ["Forest", Color(0.36, 0.50, 0.36)],
		["Navy", Color(0.34, 0.42, 0.62)], ["Burgundy", Color(0.55, 0.24, 0.28)],
		["Plum", Color(0.50, 0.36, 0.55)], ["Ash", Color(0.62, 0.62, 0.64)],
	],
	"grass": [
		["Fresh", Color(0.72, 1.00, 0.66)], ["Meadow", Color(0.86, 1.00, 0.74)],
		["Deep", Color(0.55, 0.80, 0.52)], ["Olive", Color(0.78, 0.82, 0.48)],
		["Dry", Color(0.92, 0.88, 0.52)], ["Straw", Color(0.95, 0.82, 0.48)],
		["Scorched", Color(0.72, 0.60, 0.40)], ["Frosted", Color(0.82, 0.94, 0.90)],
	],
	"sand": [
		["Pale", Color(0.98, 0.94, 0.80)], ["Dune", Color(0.93, 0.85, 0.65)],
		["Desert", Color(0.88, 0.75, 0.52)], ["Clay", Color(0.82, 0.62, 0.44)],
		["Red Sand", Color(0.80, 0.50, 0.36)], ["Ash Grey", Color(0.74, 0.72, 0.68)],
		["Black Sand", Color(0.42, 0.40, 0.40)], ["Shell", Color(0.95, 0.90, 0.88)],
	],
	"snow": [
		["Fresh", Color(1.00, 1.00, 1.00)], ["Moonlit", Color(0.88, 0.92, 1.00)],
		["Blue Shade", Color(0.78, 0.86, 0.98)], ["Glacier", Color(0.70, 0.86, 0.92)],
		["Slush", Color(0.78, 0.80, 0.80)], ["Trodden", Color(0.66, 0.68, 0.72)],
		["Dusk", Color(0.62, 0.64, 0.78)], ["Sunlit", Color(1.00, 0.96, 0.86)],
	],
	"water": [
		["Shallow", Color(0.72, 0.94, 0.98)], ["Lagoon", Color(0.55, 0.88, 0.92)],
		["Sea", Color(0.45, 0.72, 0.90)], ["Deep", Color(0.32, 0.52, 0.80)],
		["Ocean", Color(0.24, 0.38, 0.66)], ["Murky", Color(0.48, 0.58, 0.48)],
		["Swamp", Color(0.42, 0.50, 0.36)], ["Ink", Color(0.26, 0.30, 0.42)],
	],
	"lava": [
		["Molten", Color(1.00, 0.80, 0.40)], ["Fire", Color(1.00, 0.62, 0.28)],
		["Ember", Color(0.95, 0.42, 0.22)], ["Blood", Color(0.78, 0.24, 0.20)],
		["Cooling", Color(0.60, 0.28, 0.24)], ["Crust", Color(0.42, 0.28, 0.26)],
		["Sulphur", Color(0.92, 0.86, 0.42)], ["Cinder", Color(0.34, 0.30, 0.30)],
	],
}

# the eight realistic swatches for `material`, or [] when it has no table (nothing to show, so the
# panel hides the row rather than inventing colours that do not mean anything for it)
static func material_colors(material: String) -> Array:
	return MATERIAL_COLORS.get(material, [])

# the texture for `material` at pattern index `pattern`, clamped to the material's variant range (a stale
# index left over from a different material never indexes out of bounds)
static func texture(material: String, pattern: int) -> Texture2D:
	var variants: Array = TEXTURES[material]
	return variants[clampi(pattern, 0, variants.size() - 1)]
