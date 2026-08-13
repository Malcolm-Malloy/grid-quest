# Grid Quest Roadmap

Living backlog of planned features. Items land here from `My Notes/Notes` (the drop-box the
notes describe) and from in-session requests. Nothing here is built until picked up. Where a
note revises an earlier plan, the newest intent wins.

## In progress
- **Red highlight system (render-mask, done 2026-08-13).** The hover highlight is now a
  render mask, not geometry: `FloorHighlightMask` draws the hovered room's floor in a magenta
  key on a private visibility layer, a shared-world SubViewport renders only that layer so the
  real walls/doors/player occlude it, and `floor_outline.gdshader` turns the surviving magenta
  into the low-opacity fill plus a red edge line. It is pixel-exact and automatically correct
  under any occluder, at ~0.7ms/frame while hovering only. Convention: anything that can sit on
  a floor sets `visibility_layer |= FloorHighlightMask.MASK_BIT` in its `_ready`. Confirmed
  behaviour: the highlight rings the player too (carpet under the player is not visible), and
  the player stays tagged as an occluder like everything else.
- **Indoor character shadow.** Indoors the shadow's cast distance shrinks while its
  silhouette stays welded to the character, so it no longer detaches at the bottom-left and
  top-right corners. (Fixed 2026-08-13; eyeball live, and it can be made a more visible
  small blob if the tucked-under look is too subtle.)

## Saving
- **Map save/load (done 2026-08-13).** `MapIO` autoload serializes only the source of truth
  (grid size, spawn, walls, doors, per-room floor styles) to `user://maps/<name>.json`
  (versioned, atomic write); everything derived (shadows, lighting, wall/gate meshes, floor
  fills, highlight, door states) is recomputed on load. Loadable from a minimal in-game menu
  (M key: name field + Save, list of maps with Load/Delete). On launch the game auto-reloads
  the last saved/loaded map (`user://last_map.txt`); the capture harness disables this unless
  `GQ_AUTOLOAD=1`. To add a saveable property, edit `MapIO.serialize` + `_apply` in one place
  and bump `version` if the change is breaking.
- Character save (live position, facing, inventory) as a separate JSON section/file reusing
  the same MapIO atomic-write + versioning path.
- Whole-game saves, so the player can eventually collect items that persist.

## Coloured floors
- Per-texture colour tinting of the floor textures (for example, recolour the tiles orange).
  Starts as a few presets, with a full colour picker later.

## Right-click menu overhaul
The menu gains a **Block / Ground** mode toggle (bottom option) that decides which options
are shown. The Grid Lines toggle stays near the bottom, default **OFF**.

- **Block mode** (ON by default): the red highlight covers the single block under the
  cursor, so the user edits just that one block. A block edit overrides any colour set by
  Ground mode.
- **Ground mode**: the red highlight outlines the whole floor (current room-shape
  behaviour) and edits the whole room's floor. It also lets the user select the outdoor area.

Option behaviour:
- **Colour (Block).** Terrain colour of the single block. A few colours to start, colour
  picker later. Hovering a colour previews it live on the block; clicking commits it.
- **Colour (Ground).** Terrain colour of the whole room or outdoor floor. Same
  live-preview-on-hover, commit-on-click behaviour.
- **Shadows (Ground).** Toggle for how shadows behave in the selected area
  (Indoor or Outdoor). More shadow options later.
- **Build (Block).** Context create/edit options depending on whether a wall or door
  already exists on the block.

### Block menu layout
    Block
        Create Terrain
            Indoor:  Tiles, Wood, Cement, Carpet
            Outdoor: Grass, Sand, Snow
            Colour:  Red, Green, Blue, Yellow, Orange, Purple
        Build
            Create Wall / Edit Wall
                Type:   Stone Wall, Brick Wall, Wood Fence, Metal Bars
                Colour: Red, Green, Blue, Yellow, Orange, Purple
            Create Door / Edit Door
                Type:
                    House Door: Wood, Stone, Metal
                    Farm Gate:  Wood, Stone, Metal
                Colour: Red, Green, Blue, Yellow, Orange, Purple
            Erase
    Grid Lines (Toggle ON/OFF)
    Block/Ground (Toggle)

### Ground menu layout
    Ground
        Create Terrain
            Indoor:  Tiles, Wood, Cement, Carpet
            Outdoor: Grass, Sand, Snow
            Colour:  Red, Green, Blue, Yellow, Orange, Purple
        Shadows
            Indoor/Outdoor (Toggle)
    Grid Lines (Toggle ON/OFF)
    Block/Ground (Toggle)

## Other logged ideas
- **Level editor: right-click a room to set it indoor or outdoor.** For walled enclosures
  like farm paddocks that should still light like the outdoors. Largely folded into the
  Shadows Indoor/Outdoor toggle above; kept as its own item until the editor exists.
