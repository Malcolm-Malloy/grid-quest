extends Node

# EditorState (autoload): the authoring state every editor surface shares -- the active mode, the armed
# brush, the selection and the clip waiting to be dropped. FloorManager's tools, the right-click menu, the
# selection, the placement previews, the tool strip and the status bar all read and write it here rather
# than reaching into each other, and the two signals tell the panels when to refresh.
#
# It holds STATE only: the actions that change the map (painting, filling a selection, dropping a clip)
# stay with the tools that perform them. Editor-only and in-memory; nothing here is saved with a map.

# authoring modes, selected from the persistent tool strip (ui/tool_strip.gd):
#   WAND  - click-to-grow selection (floor patch -> whole room; wall run -> building); a drag boxes one.
#           Pick a material/colour from the right-click menu to fill the whole selection.
#   CELL  - paint one 32px cell.         FINE  - paint one 16px quarter.
#   ERASE - remove topmost-first: a click deletes the wall/door on the cell (structure layer) first,
#           then a further click erases the floor material of the cell back to grass.
#   WALL  - add a wall on the clicked cell; drag to draw a wall line.
#   DOOR  - add a door on the clicked cell (a wall there becomes a doorway). Orientation follows the
#           wall run it bridges; R flips the default used when placing in open space.
#   SELECT- click a door or wall to load it into the properties inspector (no map edit itself).
#   BRIDGE- add a crossable bridge deck on the clicked water cell, oriented across the water run.
#   BOX / MOVE / EYEDROP / SPAWN / ITEM / CREATURE - box select, move a selection, pick a brush from the
#           map, set the player spawn, place an item, place a creature (or drag out a spawn zone).
# See ROADMAP "Authoring surface", "Applying edits to a selection" and "Wall editing".
enum Mode { WAND, CELL, FINE, ERASE, WALL, DOOR, SELECT, BOX, BRIDGE, MOVE, EYEDROP, SPAWN, ITEM, CREATURE }
# what the armed brush applies on a paint click/drag: a floor material (+ colour), a wall colour, a wall
# material, a floor colour alone, or a floor pattern
enum Brush { FLOOR, WALL_COLOR, WALL_MATERIAL, FLOOR_COLOR, PATTERN }
enum SelKind { NONE, FLOOR, WALL }        # what the current selection holds
enum Pending { NONE, PASTE, MOVE }        # a clip waiting to be dropped, and how it got there
enum SelOp { REPLACE, ADD, SUBTRACT }     # how a new selection combines with the current one

# emitted whenever the armed brush changes (material, armed flag, brush kind, or colour), so the
# persistent left-panel Brush inspector (tool_strip.gd) can highlight the active material + colour live
signal brush_changed
# emitted whenever the selection changes (floor/wall/none), so the panel can surface the matching
# section (a wall selection opens the Wall section, a floor selection the Brush section). Fires even
# when the reflected brush values did not change, unlike brush_changed.
signal selection_changed

var mode: Mode = Mode.WAND # set through FloorManager.set_mode, which also resets the per-mode tool state

# --- the armed brush ---
var tool_kind: Brush = Brush.FLOOR # what a paint click/drag applies
var brush := "wood"              # active floor material ("" = grass eraser)
# Cell/Fine only: is a material armed to drop? Cleared on entering Cell/Fine so the mode never starts
# placeable; set when a material is picked. Until then Cell/Fine show no drop-preview and place nothing.
var armed := false
var floor_color := Color.WHITE   # active floor tint (white = natural / reset the tint)
var pattern := 0                 # active floor pattern index (for the pattern brush drag)
# river-bank switch: a LIQUID (water/lava) painted while this is on grows a brown bank ring. Set from the
# Brush panel BEFORE laying; stored per quarter, so it only affects quarters painted while on/off.
var bank_on := true
# The wall brush is UNIFIED: these are both the colour/material that recolour an existing wall (a
# selection, or a clicked wall) AND the ones Wall-mode placement stamps onto each NEW wall. White/stone
# = natural, so a plain wall stays plain.
var wall_color := Color.WHITE
var wall_mat := "stone"
var door_orient := "horizontal"   # DOOR mode: orientation used when the cell has no wall run (R flips)
var bridge_orient := "horizontal" # BRIDGE mode: orientation used when the water run is ambiguous (R flips)
var item := "coin"                # ITEM mode: which item definition a click places
var item_data := {}               # binding carried by the next placement: a Unique key's {door_id, name}
var creature := "frost_frog"      # CREATURE mode: which creature a click places...
# ...and as which kind: a spawn point (the default, per ROADMAP "the default, reliable-single-roamer
# tool"), a fixed instance, or a ZONE, which is dragged out rather than clicked
var creature_kind := Bestiary.SPAWN_POINT
var grid_on := false              # the reference grid overlay

# --- the selection (a repeat click on the same selection grows its scope) ---
var sel_kind: SelKind = SelKind.NONE # floor selections hold quarters, wall selections hold cells
# floor selection FILL set: quarter Vector2i -> true (incl. the under-wall ring for fills; the overlay
# subtracts wall sprites for display)
var sel_quads := {}
var sel_cells := {}              # wall selection: cell Vector2i -> true
var sel_level := 0               # grow level: floor 1=patch 2=room; wall 1=run 2=building

# --- copy / paste / move: the ARMED clip (ROADMAP "Copy, paste, and duplicate" + "Move tool"). One
# pending-clip state serves both, so the ghost, the rotate/flip keys and the drop share one code path.
var pending_clip := {}            # the clip about to land ({} = nothing armed)
var pending_kind: Pending = Pending.NONE # an armed paste (Ctrl+V, drops on click) or a move (MOVE drag)
var pending_id := 0               # bumped on every arm/rotate/flip so the ghost knows to redraw
var pending_changed := false      # the pending clip was rotated/flipped (so a zero-delta move still acts)
var move_src := {}                # MOVE: the source footprint cells, cleared when the move lands
var move_origin := Vector2i.ZERO  # MOVE: the source footprint's top-left cell
var move_grab := Vector2i.ZERO    # MOVE: the cell the drag started on, so the ghost follows the grab point
