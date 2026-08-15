# Grid Quest Roadmap

**North star (still being scoped):** Grid Quest is aiming to be a **creature-collector RPG** with
character progression and stats, collectible items, and monsters you fight, capture, keep in
paddocks, and eventually raise as companions that fight for you. World and editor features are
being built first; the creature/battle/capture/progression pillar is not yet specced below. Use
this direction to sanity-check features (e.g. paddocks = pens for captured monsters).

Living backlog of planned features. Items land here from `My Notes/Notes` (the drop-box the
notes describe) and from in-session requests. Nothing here is built until picked up. Where a
note revises an earlier plan, the newest intent wins.

## Development order (set 2026-08-13)
Priority sequence agreed with the user. Ordered by dependency: the ground layer and the
right-click menu are co-dependent hubs (build storage first, then the menu against it), and
inventory/pickups gate locked doors. Numbers are sequence, not strict phases; polish items are
deferrable.
0. **Architecture review (do first, see Architecture review section).** A read pass over the
   whole codebase to set the data-model and coordinate conventions before the ground-layer
   refactor bakes them in. Best done immediately before step 1, since step 1 is the biggest
   structural change anyway; worth a light revisit after step 1 lands. Token-heavy (needs broad
   reading), so run it in a fresh window with budget, one subsystem at a time.
1. **Ground layer: storage + hard-edge render + save v2 migration. DONE 2026-08-15.** Biggest
   architectural risk and cheapest to migrate now while few maps exist. Headless-testable via
   save/load, no UI needed yet. Foundation for 2 to 4. See "Ground layer" section for the
   as-built notes.
2. **Right-click menu (Block/Ground modes).** The authoring surface for the ground layer,
   colours, and later lock authoring. Block mode only means something once per-block ground
   from step 1 exists, so it follows the storage work.
3. **Coloured floors (tinting, presets then picker).** Small high-visibility win; plugs into
   the menu's Colour options and needs the layer plus menu to target where colour lands.
4. **Ground layer phase 2: auto-matching + better edging.** Polish on the working layer; hard
   16px seams are acceptable until then.
5. **Character save (position, facing, inventory) + whole-game saves.** Reuses the MapIO
   atomic-write path. Inventory must persist before keys can.
6. **Item / pickup system.** Prerequisite for keys (keys are editor-placed pickups); see the
   Items and pickups section.
7. **Locked doors and keys.** Terminal dependency: needs the door menu (2), inventory (5), and
   pickups (6).

## Architecture review (step 0, scope set 2026-08-13, not yet run)
A grounded read pass to decide how the code should be structured now that the mechanics are
clearer (ground layer, menu hub, items/inventory, character save, locked doors). The explicit
goal is to **optimise the systems for loading and for future features**: faster and simpler
save/load, and structure that new mechanics plug into cheaply instead of being retrofitted. Not
yet run, because a real pass needs to read broadly and is token-heavy; the agenda below is
front-loaded so the pass itself is targeted. Run one subsystem at a time in a fresh window. The
questions to answer, roughly in dependency order:

1. **Shared tile-entity model?** Floor/ground quarters, walls, doors, obstacles, and future items
   are currently separate ad-hoc stores (`floor_manager._styles`/`_cell_tex`/`_room_quads`,
   `obstacles`, `gate`, `wall_segment`). Should they share one cell-or-quarter-addressed entity
   model, or stay separate with a common coordinate convention only? This decision shapes step 1.
   **Finding (2026-08-15, from reading the code): keep them separate; do NOT build one unified
   entity model.** Today's pattern is already clean: `Obstacles` owns walls
   (`blocked_cells: Array[Vector2i]`) and doors (`gate_cells: Array[{cell, orientation}]`) as plain
   cell data; `FloorManager` owns per-room floor styles (`_styles: {rep_cell -> style}`); `MapIO`
   serializes just these and recomputes everything derived (wall/gate nodes, lighting, shadows,
   floor fills). All already share ONE coordinate convention (Vector2i cells, CELL=32,
   `floori(pos/CELL)`). Two categories emerge and should stay distinct rather than merged: (a)
   AREA/TERRAIN layers = grids of `coord -> material` (floors now, ground quarters in step 1, water
   later); (b) PLACED OBJECTS = records with a cell + type + optional id + per-type fields (walls,
   doors, items, creatures). The grain also differs (floors go to 16px quarters in step 1 while
   walls/doors stay 32px cells), another reason not to force one model. So step 1's ground layer is
   an AREA layer that should copy the floors pattern (own store, a MapIO save provider per Q4,
   recompute derived). Small evolutions as features land: doors gain an `id` field (Q3); walls
   should grow from a bare `Array[Vector2i]` into records with type+colour when the wall roster
   arrives.
2. **Is `room_light` (334 lines, the largest file) doing too much?** It owns room topology
   (`room_floor_cells` flood fill, `wall_ring_quads`) as well as lighting. Should room
   topology/identity be its own service that lighting, floors, and the menu all consume, rather
   than living inside the light node?
   **Finding (2026-08-15, from reading the code): yes, it does too much; extract room topology.**
   `room_light.gd` bundles three jobs: (1) room topology / flood-fill (`_build_exterior`,
   `room_floor_cells`, `enclosed_floor_cells`, `is_enclosed_floor`, `is_indoor`, `wall_ring_quads`,
   the `_box` bounding box), (2) lighting (`lit_cells` / `_compute_lit` / `exterior_lit` /
   `_open_doors`), and (3) rendering the dim overlay (`_draw` / `_process`). The topology half is a
   GENERAL service already consumed widely: `FloorManager` calls `room_floor_cells` and
   `wall_ring_quads` for floor geometry; `ShadowManager` calls `exterior_lit`, `lit_cells`,
   `enclosed_floor_cells`, `lit_wall_stamps`, `is_enclosed_floor`. Recommend extracting a standalone
   RoomTopology / RoomModel service (walls+doors dicts, exterior flood, the room queries, wall-ring
   quads, bounding box), leaving RoomLight to consume it plus do the lit-flood and dim render.
   Payoff: the many future features that need topology (paddock outdoor-override, roofs, minimap
   indoor/outdoor, base-defense, water bodies) plug into the service, not the light node. Not a
   blocker for step 1 (floors would just consume the extracted service instead of RoomLight), but do
   the extraction BEFORE piling roofs/minimap/paddock-override on top, to avoid churn. Connects to
   Q1: the genuinely shared foundation worth centralizing is coordinate + room topology, NOT entity
   storage.
3. **Stable identity scheme.** Locked doors bind a key to a door id, and items/pickups need
   persistent ids too. Is there a durable identity for placed objects today, or does everything
   key off cell position (which breaks when objects move or rebuild)? Decide the id scheme before
   locked doors or items.
   **Fleshed out and confirmed by the user 2026-08-13 (grounded read: today everything keys off
   cell position, e.g. `gate.cell`, floor `rep_cell`). All three decisions confirmed as
   recommended:**
   - **Do not id everything.** Most objects should stay position-keyed, because position *is*
     their identity: floor material per quarter, walls, terrain carry no state that must follow
     them, and save stores them positionally. Leave these unchanged.
   - **Durable id only for referenceable entities:** objects that carry surviving state *and* are
     referenced by other things independent of position. That is **doors** (a Unique key
     references one) and **item pickups** (save tracks which specific one was collected), plus
     future actors/containers. Recommended scope: doors + pickups only.
   - **Mechanism: a monotonic `int` counter.** `MapIO` holds `next_id`; each referenceable entity
     gets an id at creation, stored in its record; `next_id` persists in the save so reloads never
     recycle ids. Compact and trivial to resolve on load. Rejected: UUID strings (bulky, overkill
     for a single-map editor) and position/content hashes (not durable, break on move).
   - **The "rebuild = new id" behaviour is a feature:** it makes the locked-door rule fall out for
     free. Rebuilding a door orphans its key's `door_id`, load fails to resolve it, the key is
     flagged for the warn/remove flow. Recommended: a genuine editor *move* keeps the id (so a
     locked door can be repositioned without killing its key), but delete-then-rebuild gets a new
     id; this needs the future editor to treat move and delete+place as distinct ops.
   - **Cross-link to Q4:** the id is the bridge between save sections. The door lives in map data
     (owns the id); the Unique key lives in character/inventory data (references it). Concrete
     reason the map-data vs character-data split matters.
4. **Save architecture as it scales.** Everything funnels through `MapIO.serialize`/`_apply`
   today. As character save, inventory, items, and locked doors land, does one monolithic
   serializer hold, or should each subsystem register its own save section/schema so MapIO
   orchestrates rather than knows every field? Also settle map-data vs character-data split.
   **Sketched 2026-08-13 (from known MapIO facts, no read; recommended, revisit against the real
   code in the review):**
   - **Save-provider registry.** MapIO stops knowing fields and becomes an orchestrator. Each
     subsystem implements `save_key()` (unique section name), `save_data()` (its source-of-truth
     Dictionary), and `load_data(dict)`, and registers. MapIO owns only file layout, versioning,
     and atomic write; it iterates providers to build the file and dispatches sections back on
     load. Adding a feature becomes adding a provider, with no MapIO edits. The existing
     serialize-only-source-of-truth, recompute-derived-on-load principle stays per provider.
   - **Two save scopes, split by file and mutability.** **Map data** (`user://maps/<name>.json`):
     the authored level (grid, spawn, walls, doors + ids, floor quarters, placed pickups as
     type+cell+id, `next_id`); static during play. **Character/game data** (separate file, e.g.
     `user://saves/<slot>.json`): the playthrough (player position/facing, inventory, collected
     pickup ids, door open/unlock state); mutable per session. The Q3 id is the bridge: character
     data references map data by id, which is why collected state lives in game-save (items
     decision 3), not map data.
   - **Two-phase load.** Sections have dependencies (a Unique key cannot resolve `door_id` until
     doors exist). Load in two passes: (1) restore, each provider rebuilds its own data; (2)
     resolve, a cross-reference pass wires links (key to door). An unresolved `door_id` is an
     orphaned key, so the locked-door warn/remove flow falls out here naturally.
   - **Per-section versioning** over one global number, so e.g. the ground layer v1 to v2 quarter
     migration is the floor provider's concern, not a global bump. MapIO tolerates missing or
     unknown sections for forward and backward compatibility.
5. **Menu dispatch data flow.** The right-click menu (step 2) will be the authoring hub for
   nearly every subsystem. Design now how a menu action targets a block/quarter/room and
   dispatches to the owning subsystem, so it is not retrofitted per feature.
6. **Rendering/z-sort convention.** With locks, items, and more sprites coming, confirm one shared
   convention for orientation, front/back layers, and y-sort depth
   ([[grid-quest-asset-perspective-model]], [[grid-quest-floor-highlight-mask]]) rather than
   per-object ad hoc handling. See the silhouette-projected shadows idea in Other logged ideas.
7. **Coordinate naming.** Confirm cell vs quarter vs world coords are named and converted
   consistently across files, since the ground layer introduces the quarter grain everywhere.
   **Finding (2026-08-15): convention is consistent, one naming wart to fix.** Every file uses the
   same model: cells are `Vector2i`, world space is pixels, cell = `floori(pos / <const>)`, a cell
   is 32px. But the constant is named inconsistently: `floor_manager` and `room_light` use `CELL`,
   while `obstacles`, `wall_segment`, and `gate` use `CELL_SIZE` (both 32). Unify on one name (a
   shared constant or small autoload) to prevent drift. For step 1, fix the quarter naming up front:
   quarter = 16px (`HALF`), quarter-coord = `Vector2i(floori(pos/16))`, named distinctly (e.g.
   `qcell`) so cell vs quarter is never ambiguous. Keep `rep_cell` (a room's canonical cell) clearly
   named as a third coordinate role.
8. **Loading performance and cost.** With the goal of optimising loading, review the load path:
   what is recomputed on load (shadows, lighting, meshes, floor fills) versus what could be
   cached, and whether the quarter-grain ground layer makes load heavier. Aim for load that
   scales with map size gracefully as maps and object counts grow.
   **Finding (2026-08-15): recompute-on-load is clean and cheap now; the scaling risks are flood
   area and step-1 quarter storage.** Load order (`MapIO._apply`): grid size, then `obs.apply_map`
   (frees + respawns a node per wall run / gate / backlayer and recomputes wall runs plus the merged
   structure shadow), then `rl.rebuild` (exterior flood), then `fm.apply_floors` (re-floods each
   styled room), then spawn. Cost scaling: the flood fills (`_build_exterior`,
   `enclosed_floor_cells`) iterate the whole wall bounding box = O(width x height); `apply_floors`
   re-floods per styled room; node count = one per wall segment / gate. All fine at current sizes.
   Watch as maps grow: (a) BIGGEST lever for step 1: serialize ground quarters SPARSELY (store only
   non-default / painted quarters, or run-length encode) so save size and load cost scale with
   painted area, not 4x total map area; (b) the box flood fills are O(area), revisit only if maps
   get large; (c) node-per-segment is fine now, batch later if object counts explode. Net: no change
   needed now, but make step 1's quarter store sparse from day one.

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

### As built (step 1, 2026-08-15)
Storage refactor landed exactly per the execution spec below. What changed:
- `FloorManager._quad_mat` (`{quarter-coord -> material}`, 16px grid) is now the only stored floor
  state and the sole source of truth MapIO saves. It is sparse (only painted quarters are stored),
  per the Q8 finding. The old `_styles` (rep_cell to style) dict is gone.
- Everything else in `FloorManager` is derived in `_rebuild`: `_base_fills` (one 16px rect per
  painted quarter, plus the wall-ring quads), `_cell_tex` (a per-cell texture only when all four
  quarters agree, otherwise grass, because the shadow interior stamp is whole-cell), and a derived
  `_rooms`/`_room_quads` styled-room index (found by flood-filling from fully-painted cells) that
  drives the lit wall-ring restamp. `set_room_style` is now a convenience that writes all four
  quarters of every room cell, so nothing on the old per-room model broke.
- Consumers audited, none needed grain changes: `grid_background.base_fills()` draws arbitrary
  rects (quarter-safe); `shadow_manager.cell_texture()` and `lit_quad_fills()` behave identically
  in phase 1 because room-fill writes uniformly.
- MapIO v2: floors serialize as a flat `"quads": [[qx,qy,material],...]` list, and `VERSION` is 2.
  `apply_quads` loads v2; `apply_floors` is retained as the v1-to-v2 migration (it flood-fills each
  old per-room style into quarters). Existing v1 maps on disk auto-migrate on next load and are not
  rewritten until re-saved.
- Verified headless (save round-trip, no render): the real v1 `Malcolm's First Map` migrates to 72
  correct quarters, and a v2 load then save is idempotent (quads, walls, doors, grid, spawn all
  identical).
### Authoring surface (quarter painting, 2026-08-15)
The step-2 editing surface over the quarter store is now built in `FloorManager`, so floors can be
painted at room, cell or quarter grain:
- **Active brush + scope.** `_brush` (material, `""` = grass eraser) and `_scope` (`Room` / `Cell` /
  `Quarter`, an enum). Scope defaults to `Room`, so the pre-existing right-click-fill behaviour is
  unchanged.
- **Right-click popup** gained a "Scope" radio group (Room/Cell/Quarter) alongside the material
  items and the Grid toggle. Picking a material sets `_brush` AND paints the right-clicked target at
  the current scope, so "right-click a room, pick Wood" still fills the room at Room scope.
- **Left-click and left-drag paint** with the active brush at the active scope (`_paint` →
  `_write_quad`). The player moves by keyboard, so the left button was free. `_write_quad` returns
  whether it changed anything, so a drag inside one quarter doesn't trigger a redundant `_rebuild`.
- **Constraint:** painting is limited to in-bounds cells (`GridBackground.grid_width/height`).
  Walls, doors and outdoor ground are all paintable (the ground under an obstacle is editable);
  Room-scope fills still no-op outside a room.
- **Scope highlight:** Room uses the mask (traces the visible room floor, occluded by walls and
  the player); Cell/Quarter use a plain square cursor (`paint_cursor.gd`, high z_index, not
  occluded) showing exactly the 32px cell or 16px quarter the next paint writes.
- **Obstacle fade:** while the Cell/Quarter cursor is over a cell carrying a wall or door, that
  obstacle dims to 30% opacity (`node.modulate.a`) so the ground under it stays visible while
  editing. `wall_segment.covers_cell` maps a cell to its wall run (fading a whole run when any of
  its cells is hovered); gates fade with their back layer. Restored on move-away / Room scope.
- **Under-wall ground is stored data, not derived (final model).** Earlier attempts derived a
  room's wall-ring fill from room uniformity, which meant laying a single carpet tile in a wood room
  broke uniformity and reverted the ground under the walls to grass. Now a room-fill (`set_room_style`
  via `_write_room`) writes both the interior floor quarters AND the room-facing wall/door RING
  quarters straight into `_quad_mat`, so the floor genuinely reaches under the walls as real data.
  Cell/Quarter painting only writes its target quarters and never the ring, so laying a tile changes
  only that quarter and leaves the stored under-wall ground untouched. Rendering is now a plain
  one-rect-per-quarter pass in `_rebuild` with NO room/uniformity/`_cell_tex` derivation, and both
  the indoor (`base_fills`) and door-open (`shadow_manager` per-quarter via
  `FloorManager.floor_tex_at_quad`) paths read the same `_quad_mat`, so they always match. The old
  `cell_texture()` / `lit_quad_fills()` / `_cell_tex` / `_wall_quad_tex` / `_rooms` / `_room_quads`
  and the uniformity gate are all gone. The "does not flow through an open door" property is kept:
  the ring uses `room_light.wall_ring_quads`, which only returns quarters facing the room's own cells.
- **MapIO impact:** the serialized `quads` list now includes the under-wall ring quarters (still
  sparse, only painted quarters). v1->v2 migration (`apply_floors` -> `_write_room`) fills the ring
  too, so a migrated map matches a freshly room-filled one.
- Verified: headless `--check-only` parse passes on all touched scripts. Not visually captured this
  session (needs an open-door state, so it wants a live run).

Still deferred to ground-layer phase 2: auto-matching and better edging (transition/corner sprites
instead of the hard 16px seam).

## Ground layer (quarter-tile, decided 2026-08-13, step 1 built 2026-08-15)
Decouple the ground/floor into its own layer, independent of rooms and obstacles, and store
material per 16px quarter (a cell is four independently-set quarters). The engine already works
at this grain (`room_light.wall_ring_quads`, highlight `HALF = 16`), so it is a natural fit.
Decided design:
- **Storage:** `FloorManager` moves from per-room `_styles` (rep_cell to style) to a per-quarter
  grid (16px quarter coord to material). Room-fill stays as a convenience (set every quarter in a
  flooded room), so nothing built so far breaks.
- **Rendering (hard edges for now):** each quarter draws its material sampled by world position
  via `GridBackground.tiled_src`; `grid_background` and `shadow_manager` already draw quarter
  fills for the wall ring, so this extends that.
- **Editing:** the Ground menu paints material at room, cell, or quarter level.
- **Save:** `MapIO` bumps to version 2 with a migration that reads v1 per-room styles into
  quarters.
- **Future phases:** (a) auto-matching, so placing a material next to another auto-forms the
  boundary quarters; (b) "better edging", transition/corner sprites derived from neighbour
  quarters instead of the hard 16px seam.

### Step 1 execution spec (front-loaded 2026-08-13, so the build session is execution only)
Resolved conventions and an ordered checklist for step 1, grounded in the current
`floor_manager.gd`. Decide nothing new at build time; just implement this.

Resolved conventions:
- **Quarter coordinate:** a quarter is 16px (`HALF`), a cell is `CELL = 32`. Quarter coord is
  `Vector2i(floori(world.x / 16), floori(world.y / 16))`. Cell `c` owns the four quarters
  `2*c`, `2*c+(1,0)`, `2*c+(0,1)`, `2*c+(1,1)`.
- **Storage:** replace `_styles` (rep_cell to style) with `_quad_mat := {}` (quarter coord to
  material name). Keep `_rebuild` regenerating `_base_fills` and `_cell_tex` from it, but at
  quarter grain: `_base_fills` entries become `[Rect2(qx*16, qy*16, 16, 16), tex]`.
- **Texture sampling stays continuous:** each quarter still samples `GridBackground.tiled_src`
  by world position, so adjacent same-material quarters are seamless and different materials meet
  at a hard 16px seam (phase-1 accepted). Do not reset UV per quarter.
- **Default/unset quarter is the grass base** (current outdoor fill), so an unpainted map renders
  identically to today.
- **Room-fill is a convenience, not the storage model:** `set_room_style(cell, style)` sets all
  four quarters of every cell the room flood-fill returns. Nothing built so far breaks.

Ordered checklist:
1. Add `_quad_mat` plus quarter helpers; keep `set_room_style` writing through to it.
2. Repoint `_rebuild` to iterate quarters and emit quarter-sized `_base_fills`.
3. **Audit consumers before changing signatures:** `base_fills()`, `cell_texture(cell)`, and
   `lit_quad_fills(lit)` (and their callers in `grid_background.gd`, `shadow_manager.gd`, and
   `floor_highlight_mask.gd`). Decide per consumer whether it needs quarter grain or a cell-level
   convenience wrapper; `cell_texture` likely becomes "material if all four quarters agree, else
   the base". Do this read-audit first, it is where the render regressions hide.
4. `MapIO` to version 2: serialize `_quad_mat` as a flat list of `[qx, qy, material]`. Migration
   reads a v1 `styles` list, flood-fills each room, and writes all four quarters per cell.
5. Verify headless by save round-trip only (save a v1 map, load under v2, re-serialize, diff),
   with no frame render this session. Hold the visual/capture pass for a separate window.

## Items and pickups (fleshed and confirmed by the user 2026-08-13; all decisions as recommended except pickup trigger, which the user changed to button-press)
A general item/pickup system: items placed in the level editor that the player can walk onto and
collect into an inventory. Surfaced because Locked doors and keys assumes it (keys are the first
concrete item) but it was never its own roadmap item. Ties into character save, since the
inventory needs to persist. Proposed design:
- **Definition vs instance.** An **item definition** is the reusable type (key, later coins and
  so on), with no world position. A **pickup instance** is a definition placed at a cell with a
  durable id (per Architecture review Q3) and a collected flag. Keys are just the first item; keep
  the system general so more types slot in without rework.
- **Planned item types (keys first, but design for all).** The user intends keys first, then
  collectibles/coins, consumables, quest/unique objects, and more over time. So the model must
  support beyond keys from the start: stackable non-key items with a shown count, and consumables
  with a use-action/effect. Build only keys now, but do not bake in key-only assumptions.
- **Interaction: button-press pickup (user choice, changed from the auto-pickup default).** The
  player stands on the pickup's cell and presses an action key to collect it; one pickup per cell.
  This pulls in a new dependency not present today: a player interact/action input, and likely a
  small prompt shown while standing on a collectable. Confirmed this is **one general interact
  button** (context decides the target), reused later for doors, NPCs, chests, and switches, so
  plan the input and prompt as a shared convention, not a pickup-only key.
- **Inventory model (the real structural call).** Keys force two entry kinds, so inventory
  supports both: **stackable** (Coloured keys as `{colour: count}`, carry several, consume one per
  lock) and **unique instances** (each Unique key its own entry carrying `name` + `door_id`, never
  stacked). Recommended: support both from the start; capacity unlimited for now.
- **Where collected state lives (important save call).** Recommended: the collected flag lives in
  **character/game-save data, not map data**. The map definition always keeps its pickups (the key
  is present when the map is opened in the editor); a saved game remembers it was taken so it does
  not respawn on load. Concrete instance of the Q4 map-data vs character-data split; depends on
  whole-game saves (see Saving).
- **Editor placement.** Place = pick a cell + item type; a Unique key also binds to a door (pick
  the door, store its `door_id` per Q3). Recommended: a new "Items" menu option; exact wiring
  deferred to the menu step (step 2), reserving the slot now.
- **Rendering.** The pickup sprite sits on a floor, so per the standing convention it sets
  `visibility_layer |= FloorHighlightMask.MASK_BIT` and y-sorts like other ground objects
  ([[grid-quest-floor-highlight-mask]], [[grid-quest-asset-perspective-model]]).

## Locked doors and keys (decided 2026-08-13, not built yet)
A lock renders on the **front layer of a closed door, in every orientation** (exact pixel offsets
deferred to art time). The door keeps its own independent colour, and
the lock has its own colour, set from a new **lock colour** option added to the Edit Door menu.
Two lock types:
- **Coloured (Single use).** A coloured key (red, blue, orange, and so on). A red key opens
  *all* red locks, matched by colour only. On first open the lock is removed from the door and
  the key is consumed from inventory. Because the lock is always gone by the time the door is
  open, it never needs to appear on the open-door sprite, so no open-state art is required.
- **Unique.** A metal key bound to **one specific door** (stores that door's id). It has a
  player-facing custom name, for example "Malcolm's Door Key". The key persists in inventory,
  and the door will not open unless the key is present. The metal lock **stays on the door** and
  is visible on the open-door sprite too, so this type needs new lock art across every door
  type/orientation open state. If the bound door is deleted in the editor the key is removed
  too, and this **must show a popup warning** first.

Open scope this pulls in:
- **Menu:** Edit Door (Block mode) gains lock authoring: pick Coloured (Single use) plus a
  colour, or Unique plus a name.
- **Keys:** placed as pickups in the level editor, depending on the not-yet-built item/pickup
  and inventory systems (see Saving, character save).
- **Art:** Unique locks need open-door art per door type and orientation
  ([[grid-quest-modify-all-asset-states]], [[grid-quest-asset-perspective-model]]). Coloured
  locks only need the closed-door state.

## Coloured floors
- Per-texture colour tinting of the floor textures (for example, recolour the tiles orange).
  Starts as a few presets, with a full colour picker later.

## Coloured walls (per-cell wall colouring) BUILT 2026-08-16 (spec below, as executed)
Recolour individual wall pieces (a tint over the stone). Built exactly per the spec below in a fresh
`/clear`ed session. Touched: `wall_segment.gd` (per-cell sliced-cap render + `cells()`/`piece_rects()`),
`obstacles.gd` (`wall_colors` store, `building_cells` with door-bridging, `wall_piece_rects`,
`_apply_wall_colors`/`apply_wall_colors`, deferred apply after `build_world`), `floor_manager.gd`
(Room->Whole, unified tool `_tool_kind` + `WALL_COLORS` menu, `_paint_wall`, `_update_wall_hover`),
`floor_highlight_mask.gd` (`_wall_key` at z=60 + `show_walls`, mutual-exclusion with the floor key),
`map_io.gd` (VERSION 3, `wall_colors` list). All five parse clean (`--check-only`) and the project
boots headless with no runtime errors. NOT yet visually verified in a live run (handed to the user).
v1 caveats as planned: wall highlight is not player-occluded; Quarter maps to Cell for walls; doors
are not coloured (walls only). The spec below is retained as the as-built reference.

Follow-ups (2026-08-16, from live testing):
- **Menu was too long** (flat list overflowed the screen): floor materials and wall colours moved
  into submenus ("Floor", "Wall Colour") via `add_submenu_item`, so the top menu is short.
- **Added a "Line" scope** (wall-only): `obstacles.line_cells` colours the connected straight wall
  run(s) through the clicked cell (horizontal + vertical arms, stopping at gaps), so the central
  cross can be coloured without touching the frame. Scope order is now Whole / Line / Cell / Quarter.
  Line is wall-only and routes to the wall highlight/paint REGARDLESS of the active tool (its
  `line_cells`/`wall_piece_rects` backend was verified via a headless functional test returning the
  correct run cells + rects). This matters because the tool-independent Whole change let the user
  hover with a floor tool active; without this, Line fell through to the floor branch and showed a
  single-cell cursor instead of the run outline.
- **Whole scope highlights ONE thing under the cursor, tool-independent** (over a wall -> that
  building's walls; over a room floor -> that room's floor). `_update_whole_hover` picks by what the
  cursor is on and uses the mutually-exclusive `show_walls`/`show_floor`, so moving between wall and
  floor swaps the highlight instead of merging. (An earlier attempt merged both via a `show_combined`
  that populated both mask keys at once; the user wanted one at a time, so that was removed.)
  Cell/Line/Quarter highlights stay single-purpose.

### Decisions (confirmed with the user)
- **Unified tool list.** The right-click menu lists floor materials AND wall colours together.
  Whichever you pick becomes the active tool; left-click applies it. A floor material paints floor
  (including under walls, with the existing obstacle-fade); a wall colour colours the wall under the
  cursor. Scope is shared between both.
- **Rename scope Room to Whole.** One label: whole-room floor for floor tools, whole-building walls
  for wall tools. Quarter stays floor-only; a wall tool treats Quarter like Cell.
- **Building = orthogonally-connected wall cells, doors bridge.** A one-cell door/gate gap in a wall
  line still joins the walls on either side.
- **Highlight = mask style, walls only.** Reuse the FloorHighlightMask shader to draw a red
  fill+outline traced around the wall geometry only (no ground, no shadows). Cell scope highlights
  the one segment; Whole scope highlights the whole building. Player-occlusion is NOT required for
  v1 (the wall key is drawn above the walls); note it as a possible later refinement.
- **Palette** (match the menu-overhaul plan): Natural (reset to no tint) plus Red, Green, Blue,
  Yellow, Orange, Purple. Colours are multiply tints over the stone texture; Natural = white.

### Findings (verified this session, trust these)
- Textures: `stone_cap.png` is 32x64, `stone_face.png` is 32x24.
- `ShadowGroup` and `RoomLight` have NO `MASK_BIT`, so they never render in the mask viewport: the
  wall highlight excludes ground and shadows for free.
- Horizontal and corner walls are already one node per cell (`obstacles.spawn_segment(cell,1)` /
  `spawn_corner`), so colouring them is easy. **Vertical walls are one node per RUN**
  (`obstacles.gd` vertical pass, `spawn_segment(cell, run_length)`), which is the structural work:
  the run node must become colour-aware and draw its cap in per-cell slices (chosen over splitting
  runs, to keep the seamless render and the per-run shadow cast, which is built independently from
  `blocked_cells` in `spawn_shadows` and is unaffected either way).
- The floor highlight is a mask + `floor_outline.gdshader` that outlines whatever magenta survives.
  Reuse it for the wall outline via a SECOND key node drawn above the walls.

### Per-file plan (build in this order)
1. **`world/wall_segment.gd`** (per-cell colour render + geometry):
   - `_ready`: add `texture_repeat = TEXTURE_REPEAT_ENABLED`.
   - add `var cell_colors: Array = []` (one Color per covered cell, top to bottom; missing/short
     entries default to `Color.WHITE` = natural).
   - add `cells() -> Array` (covered cells top to bottom) and `_cell_index(cell) -> int` (0 = top),
     reconstructed like the existing `covers_cell`: `col = round((position.x-16)/32)`,
     `bottom_row = round((position.y-16)/32)`, cell i is `Vector2i(col, bottom_row-run_length+1+i)`.
   - rewrite `_draw` to draw per-cell: cap slice per cell + a face on the bottom cell only, each
     tinted by its cell colour. Geometry (local, node origin = bottom-cell centre): `bottom_edge=16`,
     `face_height=28`, `top_edge=16-run*32`, `cap_top=top_edge-7` (WALL_HEIGHT), `cap_bottom=-12`.
     Cell i spans local y `[top_edge+i*32, top_edge+(i+1)*32]`. Cap slice i: top = `i==0 ? cap_top :
     top_edge+i*32`, bottom = `i==run-1 ? cap_bottom : top_edge+(i+1)*32`. Face only on `i==run-1`:
     `Rect2(x_start, cap_bottom, width, face_height)`, colour = cell_color * 0.62 (existing shade).
   - use a region-sample helper `_stamp(tex, dst_local, origin, color)` with
     `src = Rect2(fposmod(dst.pos.x-origin.x, tw), fposmod(dst.pos.y-origin.y, th), dst.size)` and
     `draw_texture_rect_region(tex, dst, src, color)`. Origins: cap = `(x_start, cap_top)`, face =
     `(x_start, cap_bottom)`. This makes the slices tile continuously AND match the ORIGINAL phase,
     so an uncoloured (white) wall looks identical to today. Needs the texture_repeat above.
   - add `piece_rects(cell) -> Array`: that cell's cap-slice plus (if bottom) face rect in
     WORLD-LOCAL coords (`position + local`), for the highlight key.
2. **`world/obstacles.gd`** (colour store + building + geometry accessors):
   - `var wall_colors := {}` (cell -> Color; store only non-white).
   - `get_wall_color(cell)` (default `Color.WHITE`); `set_wall_color(cell, color)` (white erases,
     else set, then `_apply_wall_colors()`); `color_building(cell, color)` (over `building_cells`).
   - `building_cells(start) -> Dictionary`: BFS over `blocked_cells`, orthogonal; bridge a gate cell
     (if neighbour n is a gate cell and `n+dir` is a wall, connect to `n+dir`). Returns wall cells.
   - `wall_piece_rects(cells) -> Array`: for each node in group "walls", for each of its `cells()`
     in `cells`, append `node.piece_rects(c)`.
   - `_apply_wall_colors()`: for each wall node, set `cell_colors = [get_wall_color(c) for c in
     node.cells()]`, `queue_redraw()`. `apply_wall_colors(list)`: clear + load (for MapIO) + apply.
   - `build_world`: after the deferred wall spawn, `call_deferred("_apply_wall_colors")` so reloaded
     and freshly built walls pick up their colours.
3. **`floors/floor_manager.gd`** (unified tool + Whole rename + hover):
   - `enum Scope { WHOLE, CELL, QUARTER }`, `SCOPE_LABELS = ["Whole","Cell","Quarter"]`, replace all
     `Scope.ROOM` with `Scope.WHOLE`.
   - tool state: `var _tool_kind := "floor"` ("floor"/"wall"), keep `_brush`, add
     `var _wall_color := Color.WHITE`.
   - menu: `const WALL_BASE_ID := 300`, `const WALL_COLORS := [["Natural", Color.WHITE], ["Red",...],
     ...]`. Build order: floor materials, separator "Wall colour", wall colours, separator "Scope",
     scope radios, separator, Grid.
   - `_on_menu_id`: dispatch GRID / `id>=WALL_BASE_ID` (wall: set `_tool_kind="wall"`, `_wall_color`,
     then `_paint(_pending)`) / `id>=SCOPE_BASE_ID` (scope) / else floor material (set
     `_tool_kind="floor"`, `_brush`, then `_paint(_pending)`).
   - `_paint`: branch on `_tool_kind`. floor = existing. wall: `cell` under cursor; if not
     `obstacles.is_blocked(cell)` return; Whole -> `obstacles.color_building(cell,_wall_color)`; else
     `obstacles.set_wall_color(cell,_wall_color)`.
   - `_update_hover`: branch on `_tool_kind`. wall: hide cursor, `_clear_room_hover`, `_restore_faded`;
     if not a wall cell -> `_mask.hide_floor()` and return; else `cells = Whole ?
     obstacles.building_cells(cell) : {cell:true}`; `_mask.show_walls(obstacles.wall_piece_rects(cells))`.
     floor branch unchanged.
4. **`floors/floor_highlight_mask.gd`** (wall key + show_walls):
   - add `_wall_key` in `_ready`: `Node2D` with `floor_mask_key.gd` script (it draws cells+quads in
     magenta; pass wall rects as the quads arg), `visibility_layer = MASK_BIT`, `z_index = 60` (above
     vertical gates at z=1), added to World deferred like `_key`.
   - `show_walls(rects)`: if `_wall_key` not in tree, `call_deferred`; else `_wall_key.set_shape({},
     rects)`, clear the floor `_key` (`set_shape({},[])`), then activate (as `show_floor` does).
   - `show_floor` and `hide_floor`: also clear `_wall_key` so floor and wall highlights stay mutually
     exclusive.
5. **`systems/map_io.gd`** (persist): bump `VERSION` to 3. `serialize` adds `"wall_colors"` as
   `[[cx,cy,r,g,b],...]` from `obs.wall_colors`. `_apply` (after `apply_map`, walls exist) calls
   `obs.apply_wall_colors(...)`. Additive: v2 maps load with no wall colours.

### Verify + v1 caveats
- Parse-check every touched script headless (`--check-only`), then hand to the user for a live test:
  uncoloured walls look identical to today; Cell scope colours one segment; Whole colours the whole
  connected building; the highlight outlines wall geometry only (no ground, no shadows).
- v1 caveats to note when done: wall highlight is not player-occluded; Quarter maps to Cell for
  walls; doors themselves are not coloured (walls only, doors get their own colour later per the menu
  overhaul).

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

## Creature and gameplay systems (game pillar, specced with the user 2026-08-14, not built)
The core game loop, folded in from a Notes batch and resolved with the user. This is the
creature-collector RPG pillar the north star describes; infrastructure (dev-order steps 1 to 7)
still comes first. See [[grid-quest-game-vision]].

### Beast states and lifecycle
- **States:** **Wild** (roaming, hostile), **Subdued** (beaten, during a capture attempt),
  **Entranced** (captured; occupies a carry slot), **Paddocked** (stored in a paddock, frees the
  carry slot; "not entranced or wild"). **Companion** = an entranced beast currently set to walk
  with the player.
- **Domestication** is a **0 to 100% progress value on any owned beast**, built by walking and
  fighting together as a companion. At 100% the beast **stays paddocked even if the fences are
  broken**. (Gradual, not a discrete state.)

### Capture (trance magic)
- Beat the monster in a fight, then attempt to put it in a **trance**. Success chance varies by
  monster difficulty (harder monsters resist).
- **On a failed trance, a weighted branch** (weights per monster, set by difficulty): the monster
  may **run** (encounter ends), **stay subdued** (another attempt possible), or **get up** (back to
  full fight, beat it down again to retry).

### Carry and ability slots (two separate systems)
- **Trance / companion carry:** **2 beasts to start** (so one companion plus room for one more),
  expandable later through the game.
- **Absorbed-ability slots:** **3 to start**, expandable later. These are distinct from carry
  capacity.

### Absorb vs domesticate (core playstyle trade-off)
The player can play many ways; the central sacrifice is per beast:
- **Domesticate:** keep it as a **companion that fights beside you and obeys commands** (e.g. a
  Breaker Monkey breaks walls on instruction). Companions are powerful but **vulnerable: they can
  die permanently in battle**.
- **Absorb:** take the beast's power **into yourself**. The beast instantly becomes a normal
  (powerless) version and is **set free automatically** (future: a release animation and goodbye
  message). Absorb only works on your **walking companions** (one or both). **The absorbed power
  starts at level 1** (note this to the player at absorb time).
- The fork: keep a strong-but-mortal companion, or sacrifice it for a permanent self-power that
  begins weak (level 1) and must be levelled.

### Magic and progression (Final Fantasy 7 materia style)
- The character has the usual **RPG stats** and **levels up absorbed powers** materia-style.
- Beasts have their own **RPG companion stats**, upgradeable along with their magic, so they get
  powerful but stay vulnerable.
- **Ability scaling example (Breaker Monkey):** level 1 breaks wood fences, level 2 slate walls,
  level 3 stone walls, and so on.

### Base building (Minecraft style, SAME system as the level editor)
- The player builds on their **Block of land**. This is the **same building system as the level
  editor / right-click build menu**, with one difference: in **play mode the build tools are gated
  behind gathered resources**, while the editor authors freely. Reuses all the menu, terrain, and
  wall work; ties to play mode vs editor mode.
- **Resource gathering:** cut trees for wood, mine stone, mine slate from rivers, and other
  resources.

### Base defense (wild-monster threat loop)
- Wild monsters can **roam into the player's land and damage structures and fences**. A wild
  **Breaker Monkey breaks wood fences**, freeing **undomesticated** paddocked beasts.
- **Domesticated beasts stay** even if fences break. So **fence upkeep, stronger walls, and
  domestication all matter** as a base-defense dimension.

### Initial monsters (build these three first; one ability each for now, bosses get multiple later)
- **Frost Frog:** blue, icy-looking frog that shoots a ball of ice at the player.
- **Fire Fly:** a dragonfly that shoots fire.
- **Breaker Monkey:** a monkey that knocks down wood fences (and higher-tier walls as its ability
  levels, per the scaling example above).

## Future terrain and world objects (logged 2026-08-13, not specced)
Future additions the user wants at some point. Not built until asked; captured with light notes on
where each lands. Universal rule: **every graphic follows the top/front perspective**
([[grid-quest-asset-perspective-model]]), so it is not repeated per item below.
- **Water terrain (impassable).** A terrain type for rivers the player cannot cross. Slots into
  the Outdoor terrain roster (alongside Grass, Sand, Snow) but introduces a genuinely **new
  mechanic: impassable terrain**. Today walls and obstacles block movement; terrain does not, so
  water needs a per-terrain passability flag and the player collision to respect it. First terrain
  that blocks.
- **Bridges (cross a river, both directions).** A crossable overlay over water, in **north-south
  and east-west** orientations. Introduces passable-over-impassable: the bridge re-enables
  crossing on cells that water blocks. Directional asset like gates (per orientation art), see
  [[grid-quest-asset-perspective-model]].
- **Trees.** World object, likely a movement-blocking obstacle with height; y-sort and front/back
  layering per [[grid-quest-asset-perspective-model]] and casts a shadow.
- **Bushes.** World object, smaller than trees; decide at build time whether it blocks or is
  passable decor. Same rendering conventions.
- **Windows.** A wall feature, like doors are wall features: placed on a wall segment. Ties into
  the wall/door authoring in the menu (Build submenu) and needs art per wall type/orientation.
- **Tables (multi-tile).** Furniture that can **span multiple tiles**. Introduces a new concept:
  a **multi-tile object footprint**, where one object occupies and is authored across several
  cells. Most objects today are single-cell, so this needs footprint storage, placement, and
  collision that understand a multi-cell object. Same [[grid-quest-asset-perspective-model]]
  rendering.
- **Chairs.** Single-tile furniture; may later pair with a sit interaction on the general interact
  button. Standard perspective/y-sort conventions.
- **Hills.** Terrain elevation rendered **in the same top/front perspective style**
  ([[grid-quest-asset-perspective-model]]). Introduces **elevation/height** within the camera
  model, which likely touches y-sort, shadows, and possibly passability. Larger than a flat
  terrain type; distant.
- **Stairs to a second floor (eventually).** Stairs that **load a map of the second floor**.
  Introduces **multi-floor maps and map-to-map transitions**: linked maps, a transition trigger,
  and carrying character/game data across the load. Bigger mechanic that leans on the Q4 save
  split (map data per floor, character data persists across the transition) and play mode. Distant.
- **Roofs.** A roof that **dynamically shapes to cover the whole structure** and is **only visible
  while the player is outside** (it hides to reveal the interior once the player is inside). It
  **must follow the top/front user perspective system** ([[grid-quest-asset-perspective-model]]).
  Different styles, but rendered as **one single large asset on its own z-axis layer** above
  everything. Strong reuse of existing systems: the **inside/outside detection already exists**
  (`room_light` exterior/enclosed tests and the `shadow_manager` indoor/outdoor split drive the
  show/hide), and **dynamic shaping to the structure** parallels how a floor fills a whole room and
  how shadows cover a structure (footprint from room cells plus walls, see
  [[grid-quest-shadows-in-room-scope]], [[grid-quest-floors-fill-whole-room]]). New work is the
  roof z-layer and generating the roof shape per style from the building footprint.
- **Outdoor canopy reveal (walk under large tree foliage).** The same visual goal as roofs, seeing
  the player underneath a large cover, but **outdoors**, which is the key difference: it **cannot
  reuse the inside/outside detection** roofs rely on, since the player is outside the whole time.
  Instead it triggers on the **player being under the canopy footprint** (overlap/occlusion test),
  fading or hiding the foliage so the player is visible beneath, then restoring it on exit. Keep it
  outside: no room/enclosed test applies. Pairs with the Trees entry (large trees) and follows the
  top/front perspective system ([[grid-quest-asset-perspective-model]]).
- **Weather layers (logged 2026-08-14).** Outdoor ambient layers (cloud, rain, and so on) shown
  **only while the player is outside**, so it ties into the same inside/outside detection roofs use
  (inactive/hidden indoors). Its own overlay layer. **First version: just randomly change the
  weather every ~5 minutes** on a timer; richer weather (types, transitions) comes later. Distant.
  - **Weather-driven shadows (linkage).** Cheap first step compatible with today's code: weather
    modulates a **single global shadow-strength value** (the `shadow_manager` `ALPHA`, currently a
    fixed `0.55`), moved in lockstep with the room lighting so indoor/outdoor stays coherent.
    Overcast/rain weakens or removes shadows (diffuse light), clear/sunny strengthens them, clouds
    passing animate the value. Richer step wants **soft/variable-edge shadows**, which the current
    hard-edged polygon union does awkwardly but the silhouette-projected raster rewrite makes
    nearly free (blur + alpha on a buffer), so weather shadows and that rewrite reinforce each
    other (see Silhouette-projected shadows in Other logged ideas). Do NOT do weather-driven shadow
    **direction** early: today's shadows are a fixed 45-degree smear, and making direction dynamic
    is a much bigger change not needed for cloud/rain mood.

## Other logged ideas
- **Play mode vs editor mode (distant future, logged 2026-08-13).** A distinct play mode and
  editor mode. Not for now, flagged so it is not lost. Note it aligns cleanly with the Q4 save
  split already sketched: editor mode authors **map data**, play mode runs against it and mutates
  **character/game data**. The general interact button (items decision) belongs to play mode; the
  right-click authoring menu belongs to editor mode. No design owed yet.
- **Silhouette-projected shadows (idea, analysed 2026-08-13, ties to Architecture review Q6).**
  Reuse the *principle* behind the red highlight (render a thing's true silhouette into an
  offscreen buffer) to build shadows whose right and bottom edges match the caster's real shape
  dynamically, instead of approximate shapes, and with no per-asset shadow art. Analysis notes:
  it is the mask-buffer half that transfers, not the outline shader (a shadow is a filled region,
  not a crisp line, and often wants soft edges). New work the highlight does not provide: a
  projection transform (offset/skew by light direction) and a static-vs-dynamic caster split
  (bake walls/gates once, redraw the character per frame). The character shadow already welds to
  its silhouette, so the real target is object shadows (gates, walls). Occlusion (shadows clipped
  by walls) is the one place the SubViewport masking could genuinely help, at added cost. Decide
  it as a rendering convention in the architecture review, not as a standalone build.
  **Deferred read done 2026-08-13, verdict: this is a change (partial rewrite), not an addition.**
  Today's shadows are a CPU **polygon** pipeline: `gate_shadow._rects()` hand-builds
  `[left,right,top,bottom]` rectangles per state (with magic offsets) smeared 45 degrees into
  hexagons, and `shadow_manager` merges all polygons into a disjoint union (`_merge_all` via
  `Geometry2D.merge_polygons`) so darkness never stacks, tests the player with
  `is_point_in_polygon`, and carves room interiors by stamping clean ground back. The
  hand-authored rects are exactly the approximate right/bottom edges this idea wants to fix. A
  raster silhouette/mask approach replaces all of that: `_merge_all`, the point-in-polygon test,
  and interior stamping all go. Upside: masking makes anti-double-darkening *simpler* (render
  every silhouette into one buffer, overlaps overwrite rather than add, composite once at
  `ALPHA = 0.55`), deleting the `_merge_all` union machinery; the player-tint test becomes a
  buffer sample. New work: the projection transform per caster, a raster player-in-shadow test,
  and re-expressing the indoor/outdoor one-darkness-layer coordination in raster terms. Reuses the
  existing static-vs-dynamic split (bake wall silhouettes like `static_union`, redraw only
  gates/character). Synergy: soft/variable-edge shadows come nearly free in the raster approach
  (blur + alpha on a buffer), which is exactly what weather-driven shadows want, so this rewrite
  unlocks weather shadows cheaply (see Weather layers in Future terrain and world objects).
- **Level editor: right-click a room to set it indoor or outdoor.** For walled enclosures
  like farm paddocks that should still light like the outdoors. Largely folded into the
  Shadows Indoor/Outdoor toggle above; kept as its own item until the editor exists.
  ### Execution spec (front-loaded 2026-08-14, interface-level; confirm room_light internals at build)
  Grounded in the lighting interface `shadow_manager` already consumes (`exterior_lit()`,
  `lit_cells()`, `enclosed_floor_cells()`, `is_enclosed_floor()`, `lit_wall_stamps()`,
  `room_floor_cells()`, `wall_ring_quads()`). Not yet read: `room_light.gd` internals, so the
  function names below are the known interface; verify the exact flow at build.
  - **The core idea: override lighting classification, not geometry.** "Enclosed" is used for two
    things: geometry (is this cell inside walls, for collision/walls) and lighting (apply the
    indoor model). A paddock must stay enclosed for geometry but be lit as outdoor. So do NOT
    overload `is_enclosed_floor`; add a separate per-room outdoor flag that only the lighting and
    shadow decisions consult.
  - **Storage.** `room_light` holds a set of outdoor-flagged rooms keyed by `rep_cell` (the same
    canonical-cell convention floors use). Authored later by right-click (editor); can be hardcoded
    now for a single paddock. Persisted in map data via `MapIO` (ideally the floor/room save
    provider owns it, per Q4).
  - **Classification override (the substance).** Where the lighting split decides indoor-dim vs
    outdoor-bright per room, consult the flag so a flagged room joins the exterior/bright set. Two
    consumers must honour the same flag or lighting and shadows disagree: (1) `room_light` applies
    outdoor lighting to the flagged room instead of the indoor model and counts it toward
    `exterior_lit()`; (2) `shadow_manager`'s interior-carve loop (`enclosed_floor_cells()`) must
    **skip flagged rooms** so they keep wall shadows like the outdoors instead of the flat interior
    shade it stamps. Consistency across these two is the main correctness risk.
  - **Unchanged:** walls, collision, and the room flood-fill stay as-is; only lighting/shadow
    classification is overridden.
  - **Verify at build:** the exact `room_light` functions that apply the indoor vs outdoor model
    and compute `exterior_lit()` / `lit_cells()`, so the flag is injected at the right point.
  - **Placing a paddock before the editor exists** means hand-authoring the enclosure walls in the
    scene or a saved map JSON, which is throwaway once the editor lands; prefer waiting for the
    editor unless a paddock is needed sooner for testing.

## Near-term fixes (logged 2026-08-15)
- **Hide the out-of-range ground texture so the map edge is visible.** Right now the ground fills
  past the walkable area (cells outside movement range still draw terrain), so the player cannot
  see where the map ends. Stop drawing (or visibly differentiate, e.g. void/darken) ground on cells
  outside the walkable/movement range so the edge reads clearly. Small, high-visibility. Touches the
  floor/ground fill (`floor_manager` / `grid_background`) and the notion of "walkable range";
  confirm at build whether that range is the grid bounds or a per-map movement extent. The user
  phrased this as "firstly", so it is the first thing to pick up when returning to hands-on work.
- **Fix the way wall caps are made.** (User-requested 2026-08-16.) Revisit how the wall cap is
  constructed in `wall_segment._draw`: today the cap is a thin continuous top surface and a front
  face is drawn only on a run's bottom cell. Surfaced during the coloured-walls work (the cap is now
  drawn as per-cell slices), which put the cap model under scrutiny. Exact desired change to be
  defined at build time.

## Creature, animal, and ownership terminology (glossary, set 2026-08-15)
Consolidated naming the user fixed in the notes, so every later section and the code use one
vocabulary. The dividing line is **magic**: creatures with magic are *monsters/minions* and can be
entranced; creatures without magic are *animals* and cannot. Extends the 2026-08-14 beast lifecycle
([[grid-quest-game-vision]]).
- **Wild Monsters** are wild, magical, hostile creatures roaming the world (the 08-14 "Wild" state).
- **Entranced Monster** is a Wild Monster the player has captured via trance. **Entrance only works
  on creatures/characters that have magic.** Occupies a carry slot (08-14 carry/companion system).
- **Loyal Minion** is a minion (entranced monster) taken to **max Domestication**. Once loyal it
  **never turns on the player** and **no longer needs to be entranced to be controlled**, because the
  loyalty replaces the trance. (Refines the 08-14 domestication 0-100% mechanic: 100% equals loyal.)
- **Wild Animals** are wild *and released* non-magical animals. **Can be killed without affecting
  karma**, and **cannot be entranced** (no magic). Killable for meat (see Meat and cooking).
- **Loyal Animal** is a domesticated (max-domestication) animal. Non-magical.
- **Loyal Companion** is a Loyal Animal placed into one of the player's minion slots. It has **no
  powers**, but can still be useful through **inherent abilities** (e.g. a domesticated horse the
  character can ride for speed). Compensation idea under consideration: **grant the character one
  extra spell slot per animal companion**, to offset the companion's lack of magic.
- **Naming (resolved 2026-08-15):** **"Companion"** is the walking-with-you *role*, which either a
  minion or an animal can fill. Always qualify: **"Minion Companion"** (magical, an entranced beast
  set to walk with you) and **"Loyal Companion"** (non-magical, a Loyal Animal in a slot). The bare
  word "Companion" refers to the role in general. This supersedes the 08-14 unqualified "Companion".

### Absorbing a minion's power (revert-to-animal behaviour, 2026-08-15)
Extends the 08-14 absorb-vs-domesticate fork. When the player **Absorbs a minion's power**
("Absorbing its power"), the creature **visually changes back into a normal, powerless version of
that animal** (e.g. a Bridge Lizard becomes a plain lizard). Instead of disappearing it **reacts
based on its Domestication level**:
- **Max Domestication:** it does **not** run, and stays in the paddock even with the gate open. The
  player can then **set it free at any time**; once freed it moves peacefully around the home map and
  surrounding maps (becoming a Wild/released Animal that fills the world, see Karma).
- **Lower domestication:** it reacts less tamely (flees / wanders off). Exact per-level behaviour
  deferred; the principle is "reaction scales with domestication."
- Consistent with the 08-14 rule that absorb sets the beast free and the self-power starts at
  level 1.

## Karma / morality system (Fable-style, logged 2026-08-15)
A **Fable-style morality system** that changes how the game plays and how NPCs react: positive,
negative, or afraid. Karma is a spine that ties creatures, world appearance, and playstyle together
rather than a standalone meter.
- **What moves karma (from the notes):**
  - *Positive:* releasing animals into the wild, so that over time the world **fills with Wild
    Animals and grows more beautiful**, granting positive karma. Playing nature-positive (Druid-like).
  - *Negative:* **killing a Loyal Animal** is a **betrayal of its loyalty** and adds bad karma.
    Playing as a dark lord brings evil to the land (see World-morphing maps).
  - *Neutral:* killing **Wild Animals** does **not** affect karma (they can still be killed for
    meat). Choosing vegetables over meat is a Druid-flavoured positive lean.
- **Effects:** NPC interactions shift (friendly / hostile / fearful), and, the big linkage,
  **karma/playstyle reshapes the world itself** (see World-morphing maps). Distant; logged as a
  design spine, not yet specced mechanically. Reference inspiration: Fable ([[grid-quest-game-vision]]).

## Minimap (logged 2026-08-15)
A minimap that shows **boundaries and nearby life**, not everything. Ties directly into the existing
**indoor/outdoor detection** (`room_light` exterior/enclosed tests, `shadow_manager` split), the
same system roofs and weather reuse.
- **Shows:** map boundaries only (walls, rivers), the player's current location, and the locations
  of **all creature/minion types within a radius** of the player. **Different colours per creature
  type** (Wild Monster / Entranced / Loyal Minion / Wild Animal / Loyal Animal, etc.).
- **Outdoor vs indoor switching (the core behaviour):**
  - *Outdoors:* a building shows as a **solid colour block**, with no interior walls or obstacles.
  - *Indoors:* the minimap shows **only the indoor space**; the outdoor area **greys out**.
  - This maps cleanly onto the existing inside/outside test, so the minimap consumes that service
    rather than re-deriving topology (aligns with Architecture review Q2: extract room topology as a
    shared service; the minimap is another consumer).
- Radius-based creature rendering needs a spatial query of nearby creatures; distant.

## Map-to-map travel (reach the edge, logged 2026-08-15)
The world is **multiple linked maps**: reaching the **right edge** of the home map (e.g. following a
path to the edge) moves the character to an **adjacent map** (e.g. a forest map to the right). This
is the horizontal sibling of the already-logged **"Stairs to a second floor"** transition idea, the
same underlying mechanic: **linked maps + a transition trigger + carrying character/game data across
the load**, leaning on the Q4 map-data-vs-character-data save split (each map is its own map-data
file; the character data persists across the transition). Which maps a player reaches, and the
creatures/items there, is influenced by **playstyle** (see World-morphing maps).

## World-morphing maps (playstyle reshapes the world, logged 2026-08-15, potential "big idea")
Playstyle/karma **changes the maps, creatures, and collectibles over time**. Two related directions
the user is weighing:
- **World appearance shifts with playstyle** (visual/atmosphere layer over the terrain + weather +
  shadow systems already planned):
  - *Dark Lord path:* brings evil to the land, giving darker, dirtier, more violent maps, stronger
    Wild Monsters, offensive powers; long enough play can **turn rivers to lava, trees dead, fire-
    and-brimstone weather**.
  - *Druid path:* maps slowly get **greener and more natural** (autumn leaves, restored nature),
    fitting the returning-animals loop and positive karma.
  - *Monk path:* the world stays **much the same** (balance).
  - Strong reuse: this rides the planned terrain recolour/tinting, weather layers, and shadow-
    strength systems rather than needing new tech per map.
- **Playstyle gates collectibles, forcing style-switching (a progression idea):** items, creatures,
  and unlockable abilities are **only available on the maps a given playstyle produces**. One route:
  play a natural (Druid) style until you have everything its maps offer, then the game **pushes you
  to switch to a Dark Lord** style to transform the world and collect the dark/toxic set. This makes
  **build-switching intended** (see Playstyle builds, which implies builds are switchable, not locked
  classes).

## Playstyle builds (buffs + balance analysis, logged 2026-08-15)
The user is jotting build ideas and **explicitly wants opinion on balance** and invites new build
types, so this is a discussion draft, not a locked spec. Core principle from the notes: *"people
can play whatever way they want, but different ways of playing lead to different builds,"* and **each
build gets a balancing Buff** that compensates for what it sacrifices.

**Build model (resolved 2026-08-15): emergent and switchable.** Builds are **not chosen classes**.
A build equals your *current dominant playstyle*; its Buff is active while you meet its conditions,
and switching playstyle **swaps the Buff** (no class pick, no respec gate). This ties builds to the
karma/world-morph spine and supports the intended "exhaust one style's maps, then switch" progression.
Open build-detection question deferred to build time: what thresholds decide which build is "dominant"
and when a Buff turns on/off.

The builds, each with the user's proposed buff and my balance read (five from the notes plus the
confirmed Beastlord):
- **Sorcerer:** no Loyal Minions, no Loyal Companions; pure power. *Buff:* 3 extra character magic
  slots plus attack magic gains an extra unlockable power level. *Balance read:* glass cannon, since
  it trades **all** creature help (no bodies to tank/soak/utility) for raw offense. Self-balances if
  enemies can **punish having no frontline** (rushers, swarms that force the solo caster to kite).
  Risk: strong ranged magic plus no bodies to protect could be *too* safe; lean on melee-rush threats
  and resource (mana) pressure to keep it honest.
- **Druid:** uses slots for Loyal Companions so the character carries **extra spells**; nature-
  positive, releases animals, avoids meat (eats vegetables, which heal less). *Buff:* an extra spell
  slot per companion. *Balance read:* overlaps Sorcerer's "extra slots", so **differentiate
  clearly**: Sorcerer's slots are raw *attack* magic with no bodies; Druid's spells come **bundled
  with a companion animal's body plus inherent ability** (mount speed, gathering), skewing
  **utility/support/mobility** over raw damage. Plus positive-karma world/NPC benefits. Good contrast
  if kept distinct.
- **Dark Lord:** focuses on Loyal Minions and max powers; **splits** focus across maxing *both*
  character and minion powers; slowly builds a **paddock army**. *Buff:* (unstated; suggest an
  **army-scaling** buff, e.g. bonuses that grow with paddock/minion count). *Balance read:* the split
  focus means **slower to max either track**, so weak/spread-thin early, strong late, a legitimate
  power-curve tradeoff. Negative karma leads to a **harder, hostile world** (fits the evil-maps
  morph), which is itself a built-in difficulty cost. Anchor the buff to army size so it self-balances.
- **Incubus:** focuses on a **single** Loyal Minion; using only one unlocks a **more powerful
  attack unique to each minion**. *Balance (resolved 2026-08-15): keep the high risk, but make the
  single minion tankier.* Permadeath stays real (a lost minion is a genuine, brutal setback, which is
  the build's identity), but as a **Companion the minion gains stronger defense and/or a magic-armor
  buff** so the player who commits everything to one creature can better protect it. This keeps the
  hardcore feel while making the all-in bet survivable enough to be viable. Also scale the unique
  attack with that minion's level/domestication so the single-minion investment is rewarded. (The
  defense/armor buff is a natural fit for the Incubus-only condition: it activates while exactly one
  Companion is out.)
- **Monk:** mix of Minions and Companions, **balance of good and evil creatures**, fights alongside
  them. *Buff:* yin/yang-themed. *Balance read:* make the buff **scale with maintaining balance**,
  e.g. an aura (or twin good-heal / evil-damage effects) that **peaks when the party is evenly good/
  evil** and fades as it skews. That makes the "balance" fantasy mechanically real and self-limiting.
  Neutral karma leaves the world the same (the stable/"much the same" world-morph path).
- **Beastlord / Tamer (added 2026-08-15, sixth build).** Owns the **non-magical animal** path that
  no other build covered (Dark Lord owns magical minions/army; Druid uses animals for spell slots;
  this build makes the animals themselves the point). Maxes **Loyal Animals and Companions** (mounts,
  gatherers, inherent abilities) with **little or no absorbed magic**, the pure Stardew/companion-and-
  mount fantasy, **karma-positive**. *Buff (suggested):* scales with number of Loyal Animals/Companions
  and their inherent abilities (faster mounts, more/richer gathering, an animal-army presence). Keep
  it distinct from Druid (Druid is *character* spellcasting bundled with companions; Beastlord is
  *the animals* doing the work) and from Dark Lord (magical vs non-magical creatures).

**My cross-cutting suggestions (for discussion):**
1. **Anchor every Buff to the sacrifice so builds self-balance:** Sorcerer power scales with empty
   creature slots; Dark Lord with paddock count; Monk with party balance; Incubus with the single
   minion's level; Druid with companion count. Each buff grows exactly as its tradeoff deepens.
2. **Map builds onto the karma axis** (Druid equals good, Dark Lord equals evil, Monk equals neutral,
   Sorcerer / Incubus flexible). This is elegant: **choosing a build literally reshapes the world**
   and its collectibles (the World-morphing progression), so build, karma, and world are one system.
3. **Beastlord confirmed (2026-08-15)** as the sixth build (see its entry above); gives the
   domesticated-animal systems a first-class playstyle.
4. **Resolve Druid vs Sorcerer slot overlap** (see Druid above) before both ship, or they'll feel
   like the same build. (Still open.)

## Creature Diary (collection log, logged 2026-08-15)
A Pokedex-style **collection log** of every creature *type*, tracking unlock status across all
states, **including just "encountered"** (shown with unknown details/stats until further progress).
Per creature type it counts:
- Wild Monster encounters
- Minions that ran (failed trance run branch, per 08-14 capture spec)
- Minions successfully **enchanted/entranced**
- **Loyal Minion** of this type unlocked
- **Loyal Animal** of this type unlocked
- Animals **released into the wild**

Reads directly off the beast-lifecycle events already specced (08-14) plus the terminology above;
mostly a persistent tally plus UI. Ties to character/game-save data (Q4). Distant.

## Multi-character system (the "big twist", logged 2026-08-15, vision-level)
The user's candidate **unique twist**: the player controls **multiple characters living in the same
universe**, separated by **many maps** that must be explored to find each other (leans hard on
Map-to-map travel). Character count TBD; new characters likely **unlock after significant playtime**.
Each has their own home, minions, companions, and playstyle, so meeting another character lets the
player combine assets across builds. **When two of the player's characters meet, a choice system:**
1. **Team up.** One character becomes an AI **"Fighter"** that follows and fights for you (the
   Fighter carries **no** Minions/Companions while in your party, and **does not** take a minion/
   companion slot). Ending it is a **"Split Up"**, after which both are independently playable again
   with their own minions/companions restored.
2. **Enchant into a "Meat Golem."** Fight an AI version of the other character; on winning, they
   become one of your **Entranced Minions** (takes a minion slot) with **all that character's
   powers**. If released from enchantment or from a broken paddock fence they become a **wild, angry,
   max-power version** that tries to kill you, and can **never be domesticated**. (Implies non-magic
   fences won't hold a Meat Golem; may need stronger containment than an open wooden fence.)
3. **Meat Golem then Absorb one power.** As (2), then **Absorb** one of their powers: they turn
   human, and you gain that power at **level 1**. This grants **cross-build powers** your own
   playstyle could never reach. The drained character **loses all powers**, will **never** join as a
   Fighter later, stays playable but is now **stranded many maps from home with no powers** to get
   back (deliberately hard to recover from).
4. **Fight them and their creatures.** You may try to **entrance their minions**, but minions already
   **Loyal to the other character will never become loyal to you**; they'll attack you if freed.
5. **Trade items** between the two characters' inventories.

Vision-level; big open questions (character count, unlock cadence, how AI-driving the "other"
character works, save/data model for many characters). Logged whole, not specced.

## Water, rivers, and river banks (refines the earlier Water/Bridges entries, 2026-08-15)
Sharpens the definitions behind the already-logged **Water terrain (impassable)** and **Bridges**
entries in "Future terrain and world objects":
- **River equals a 1-tile-wide line of water terrain.** A **body of water** is anything wider (lake,
  pond, wide moat, etc.). Same water terrain, different width.
- **River-bank auto-edge (new, quarter-tile).** The **surrounding tile-quarters of all water**
  change to a **brown river-bank texture** that outlines every body of water, **regardless of the
  neighbouring terrain**. Purpose: it visually reads the water's edge *and* looks walkable (the bank
  is passable; the water is not). Implementation fit: this is **exactly the quarter-tile auto-matching
  the Ground layer already plans** (phase-2 auto-matching / better-edging), so river banks are an
  auto-formed boundary material driven by water neighbours, built as a case of that system, not
  bespoke. Follows [[grid-quest-floors-fill-whole-room]]-style whole-region fill at quarter grain.

## Bridge Lizard (first river-crossing creature, spec logged 2026-08-15)
A concrete minion whose ability is **crossing water**, with per-level scaling for both the minion and
the absorbed player-power (extends the 08-14 initial-monster + ability-scaling model). Diablo-feel
art per the asset rule below.
- **Minion levels (while owned as a minion):**
  - *Lvl 1:* the minion itself can **cross rivers**, collect **one item**, and bring it back to the
    player.
  - *Lvl 2:* on **river tiles only**, the minion **becomes a wooden raft/bridge platform** the player
    and other controlled creatures can walk across to cross the river.
  - *Lvl 3:* the raft can be placed at the edge of **bigger bodies of water**; when the player steps
    on, it **ferries them in a straight line to the far side**.
- **Player levels (after Absorbing its power, which starts at level 1 per the absorb rule):**
  - *Lvl 1:* the player can **send any chosen minion across a river**.
  - *Lvl 2:* the player can **walk over rivers** themselves.
- Ties into Water/river-bank terrain (needs passable-over-impassable, like Bridges) and the beast
  ability-leveling system.

## Meat, cooking, and kitchens (logged 2026-08-15)
- **Meat** is a **health item**, obtained by killing **Wild Animals** (no karma cost, see Karma).
  Later, meat becomes an **ingredient** for better health foods.
- **Cooking system** for a **kitchen in the home**, with **stone ovens** to fit the intended
  **medieval** feel. Vegetables are a lower-heal alternative (the Druid-flavoured choice). Distant;
  ties to base building (the home) and the item system.

## Diablo-feel asset convention (standing rule, logged 2026-08-15)
**With each new asset generated, discuss ways to give it a Diablo / Diablo 2 world feel.** Treat this
as a standing step in asset creation (alongside the top/front perspective rule
[[grid-quest-asset-perspective-model]] and updating all states [[grid-quest-modify-all-asset-states]]):
before generating art, propose how to lean the piece toward the dark, gritty, moody Diablo look. The
art north star is **Diablo / Diablo 2**.

## Inspirations (reference list, logged 2026-08-15)
The user's stated touchstones, per system, to steer design/art decisions:
- **Art / world feel:** Diablo, Diablo 2.
- **Magic leveling:** Final Fantasy 7 (materia, already reflected in the 08-14 progression spec).
- **Ability absorption:** Sylar from *Heroes* (TV series), taking a creature's power into yourself.
- **Creature collection:** Pokemon (Creature Diary, capture).
- **Home building + resource collection:** Stardew Valley / Minecraft (base building equals the level
  editor, resource-gated in play mode, per 08-14).
- **Karma system:** Fable (morality reshapes play, NPCs, and, here, the world).
