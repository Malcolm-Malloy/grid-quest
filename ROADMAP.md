# Grid Quest Roadmap

**North star (still being scoped):** Grid Quest is aiming to be a **creature-collector RPG** with
character progression and stats, collectible items, and monsters you fight, capture, keep in
paddocks, and eventually raise as companions that fight for you. World and editor features are
being built first; the creature/battle/capture/progression pillar is not yet specced below. Use
this direction to sanity-check features (e.g. paddocks = pens for captured monsters).

Living backlog of planned features. Items land here from `My Notes/Notes` (the drop-box the
notes describe) and from in-session requests. Nothing here is built until picked up. Where a
note revises an earlier plan, the newest intent wins.

## Development order (editor-first, re-sequenced 2026-08-16)
Re-prioritised with the user around one goal: **make the editor able to build real maps as soon as
possible, so level design can start now.** Everything the user needs to lay out and shape a map
comes first (Phase A); persistence and the game pillar follow once maps can be authored. Numbers are
sequence within a phase, not strict gates; polish items are deferrable. The 2026-08-13 dependency
order (ground storage, then menu, then floors, then saves, then items, then locked doors) is
preserved inside the phases, just re-grouped so map-authoring surfaces lead.

**Phase A: make maps buildable (editor authoring, do first).**
*Foundation (build early, before piling on tools):* **undo/redo history** (full multi-step, see the
"Undo / redo" section) and the **left tool strip** the modes live on. Every authoring tool below
wraps its edits in an undo entry as it is added, so history is never retrofitted.
0. **Architecture review (do first, see Architecture review section).** Read pass to set data-model
   and coordinate conventions before more is baked in. Steps 1 to 8 partly done (see findings
   inline); revisit the room-topology extraction (Q2) before roofs, minimap, and paddock-override
   pile on. Run in a fresh window, one subsystem at a time (token-heavy).
1. **Ground layer storage plus save v2. DONE 2026-08-15.** Foundation for everything below; see
   "Ground layer" and the As-built notes.
2. **Show the map edge (hide out-of-range ground) and a bigger default map. DONE 2026-08-16.** The
   runtime edge-editing tool (add/remove cells) is still item 3. Ground now draws clipped to the grid
   rect and beyond it is an inactive-cell void (grey tiles with a subtle "+", not black), the default
   map is 48x32, and grid dims are unified onto GridBackground. See the As-built note under "Map
   extent and edge editing".
3. **Add and remove cells at the map edge. ROW/COLUMN grain DONE 2026-08-16; single-cell + green
   highlight pending.** The whole-row/column grain is built (`MapEdit.grow/shrink`, see the As-built
   note under "Map extent and edge editing"). The single-cell grain and the green "will-be-added"
   highlight are deferred: a lone jagged cell needs a per-cell existence model the rectangular map
   lacks (tie to Architecture review Q1/Q2). Live UX (the tool strip that triggers grow/shrink, plus
   the green highlight) is still the next step; interim control is IJKL keys + the GQ_RESIZE hook.
4. **Right-click menu (renamed modes plus coloured highlights). Tool strip modes DONE 2026-08-16.**
   The persistent left tool strip has the Map Size (edge grow/shrink) control, the green/red edge
   band, and now the **Tools radio group**: Magic Wand / Cell Selector / Fine Details / Erase, with
   W/C/F/E shortcuts (recenter moved off F to **Home** so F is Fine Details). The **Magic Wand**
   click-to-grow selection (floor patch -> whole room; wall run -> whole building) with a **marching-
   ants** overlay and **selection-fill** (pick a material/colour to fill the whole selection) are
   built. The editor camera (pan/zoom/fit, Home to recenter) is DONE. Still to do: the *contextual*
   terrain/wall/door material menus and the rest of the coloured-highlight palette (orange/purple/
   blue/yellow). See "Authoring surface", "Right-click menu overhaul" and "Coloured highlight
   system" as-built notes.
5. **Terrain placement UX (select, then hover-preview, then click-to-drop).** Selecting a terrain
   no longer auto-places; it arms a brush that shows a lifted preview sprite over the hovered cell
   and drops with an animation on click. Highlights clear when the cursor leaves the screen. See
   "Terrain placement UX".
6. **Add and remove walls in Cell Mode, plus wall-removal outside reclassification.** Editing
   perimeter walls reclassifies an opened room as outdoors (lighting, shadows including the player
   shadow, later creature reactions); ground is untouched. See "Wall editing and outside
   reclassification".
7. **Coloured floors plus terrain and wall pattern and material options.** Tinting (presets, then
   picker) plus pattern variants (carpet, grass, tile, wood patterns) and wall/fence materials
   (wood, slate, stone). See "Coloured floors", "Terrain patterns and material variants".
8. **Ground layer phase 2: auto-matching plus better edging.** Polish; hard 16px seams acceptable
   until then.

**Phase B: persistence (needed to save the maps you build, then to play them).**
9. **Character save (position, facing, inventory) plus whole-game saves.** Reuses the MapIO
   atomic-write path. Inventory must persist before keys can.
10. **Item and pickup system.** Prerequisite for keys (keys are editor-placed pickups); see "Items
    and pickups".
11. **Locked doors and keys.** Terminal dependency: needs the door menu (4), inventory (9), and
    pickups (10).

**Phase C: game pillar (creature-collector RPG).** Not gated on Phase A or B but authored against
them: creatures, capture, absorb, domesticate, resource-gated building (same system as the editor),
builds, karma, and so on. See the creature and gameplay sections. Build after the editor can produce
the maps these systems play in.

### Phase A, consolidated (all 2026-08-16 editor decisions in build order)
The many editor decisions logged 2026-08-16 group into a coherent Phase A. Rough dependency order:
1. **Foundations first:** the **Play/Edit toggle** (mode flag driving camera+input+UI), the
   **free editor camera** (pan clamped to map+margin, wheel zoom), **undo/redo** (deep-but-capped,
   one-entry-per-gesture), and the **left tool strip** (grouped: Select / Paint / Objects / Edit).
   Every tool below records undo as it is added.
2. **Make the map readable and sizable:** show the **map edge** (void/black), **remove unwalkable
   ground**, bump default to **48x32** (unify the duplicated grid dims), then **edge-cell add/remove**
   (delete-contents-with-cell, copy-neighbour fill, green highlight).
3. **Core authoring tools:** **Cell Selector / Fine Details** paint with the **terrain drop-preview
   UX**, the **coloured highlight palette** (orange ground / red erase / purple walls / green add /
   blue doors / yellow shadow), the **Erase** tool (topmost-first, per the **cell-occupancy** and
   **passability** models), the **Eyedropper**, and **directional placement** (auto + R).
4. **Selection + power tools:** **Magic Wand** (click-to-grow, marching-ants) and **Box-select**,
   with **add/subtract** modifiers and **selection-fill**; then **Move** (keeps id), **copy/paste**
   (cross-map clipboard, rotate+flip), the **properties inspector**, the **status bar**, and
   **wall/door authoring** (roster + door authored state).
5. **Persistence + library:** **autosave+warn**, **New Map** flow, **map thumbnails**, **folders/
   categories**, and **export/import** for sharing.
6. **Multi-tile object footprints** and **coloured floors / patterns / material variants** slot in as
   the object and material rosters grow.
This is a re-grouping for coherence, not new scope; each item has its own section with the full
decision and build notes.

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
  - **Recolour to orange (decided 2026-08-16).** This terrain highlight moves from red to **orange**,
    because red is being reassigned to erase/destructive actions (see Coloured highlight system).
    Only the output colour in `floor_outline.gdshader` changes; the mask mechanism stays. The system
    name "Red highlight system" is now just a code label, not the on-screen colour.
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

**Modes + Magic Wand as-built (2026-08-16): DONE.** The scope system was replaced by a `Mode` enum
(`WAND`, `CELL`, `FINE`, `ERASE`) driven by the tool strip's Tools radio group, not the popup:
- **Cell Selector / Fine Details** paint one cell / one quarter on click and drag (the old Cell /
  Quarter scopes). **Erase** writes grass over the cell on click and drag.
- **Magic Wand** is a click-to-grow *selection*, stored as `_sel_kind`/`_sel_quads`/`_sel_cells`/
  `_sel_level`. A floor click floods the connected same-material quarters bounded to the room
  (`_patch_quads`, level 1); a repeat click inside grows to the whole room including its wall ring
  (`_room_quads`, level 2). A wall click selects the run (`obs.line_cells`, level 1); a repeat grows
  to the whole building (`obs.building_cells`, level 2). Esc or clicking a new spot resets.
- **Marching-ants overlay** (`floors/selection_overlay.gd`, a Node2D child of FloorManager at
  z 1000): a translucent wash over the selected quarters/walls plus an animated dashed boundary,
  keyed to world coords so dashes stay continuous. Verified via the new `GQ_WAND` capture hook (a
  hollow dashed ring around the room; the engine reports patch = 36 quads growing to room = 64
  quads; wall run = 9 cells growing to building = 40 cells).
- **Selection-fill**: with a selection active, picking a floor material or wall colour from the
  popup fills the *whole selection* (`_fill_floor_selection` / `_fill_wall_selection`) as one undo
  entry. With no selection, a floor material fills the clicked room and a wall colour the clicked
  building (Wand mode), or paints/colours the clicked cell (Cell/Fine). The selection persists
  across mode switches and after a fill, so it is a reusable target.
- **Caveats and still-deferred items (each its own roadmap section):** Erase only clears *floor*
  material for now; wall/object removal (the topmost-first cell-occupancy model) is not built. The
  wand's ants trace wall *cells* (32px), not per-wall-piece geometry. Outdoors (no enclosed room) a
  floor patch is just the clicked cell. Whole-map (a 3rd grow level), additive/subtractive Shift/Alt
  modifiers, box-select, and copy/paste are not built. The popup lost its Scope radios but is not
  yet *contextually* filtered (floor-only vs wall-only submenus). Selection-fill is verified by code
  inspection (the popup can't fire headlessly); the wand engine and ants are verified headlessly.
- **Rename and expand the scopes (decided 2026-08-16, apply at build).** The scope system becomes
  three modes, ordered coarse to fine. The old "Selector Mode" and "Room Mode" ideas are merged into
  a single **Magic Wand**, on the user's call, because the two behaviours are the same tool at
  different scopes and one click usually does the obvious thing:
  - **Magic Wand (merges the earlier Selector + Room ideas, decided 2026-08-16).** A single
    click-to-grow selection tool:
    - **1st click on a floor quarter:** selects the **connected same-material patch** (e.g. just the
      touching carpet quarters).
    - **2nd click on that same selection:** grows to the **whole room floor** (all materials,
      wall-bounded). Optional 3rd step: whole connected map, only if it proves useful.
    - **On a wall:** 1st click selects that wall run; 2nd click selects the **whole building's
      connected walls**.
    - **Seamless because:** in a room of one material the same-material patch already equals the
      whole room, so one click grabs the floor as expected; the grow-on-repeat only matters in a
      genuinely mixed room. The selection outline visibly grows each click so the scope is always
      shown. Esc / right-click / clicking a new spot resets.
    - **Why click-to-grow over a Photoshop-style Contiguous checkbox:** a hidden toggle is not
      discoverable; repeated-click growth shows the scope and needs no chrome. Materials are discrete
      so no tolerance slider is needed ("same material" is an exact match).
    - **Build note:** step 1 (patch) is a connected-component flood over `_quad_mat` seeded at the
      clicked quarter, matching the seed material, bounded to the room's cells. Step 2 (whole room)
      unions the room's cells regardless of material via the room-topology flood
      (`room_light.room_floor_cells`). The wall version floods connected wall segments
      (`wall_segment.covers_cell` / run adjacency). Track a small "current selection + scope level"
      state so a repeat click knows to grow.
  - **Cell Selector** (was Cell Mode / Cell scope): a single 32px cell.
  - **Fine Details** (was Fine Detail Mode / Quarter scope): a single 16px quarter.
  The internal `_scope` enum: replace Room/Whole with a Magic-Wand selection state (holding the
  current selection and its grow level); keep Cell and Quarter. Labels the user sees: **Magic Wand**,
  **Cell Selector**, **Fine Details**.
- **Move the mode picker out of the right-click menu into a persistent editor toolbar (decided
  2026-08-16).** The three modes stop living in the right-click popup and become an always-visible
  radio group of icon buttons on a dedicated tool strip; the active tool is highlighted. This frees
  the right-click menu to be purely contextual (act on the thing under the cursor) while the strip
  owns mode selection, the split standard editors use. Ties directly to "Optimise the right menu and
  UI practices". Icon direction (confirmed with the user 2026-08-16):
  - **Magic Wand:** the classic diagonal wand with a sparkle/star at the tip (Photoshop-style
    smart-select icon).
  - **Cell Selector:** a **fully filled square, the same outer size as the Fine Details 2x2 block**
    (i.e. a solid whole cell). Refined with the user 2026-08-16: it is filled, not an outline, and
    sized to match the four-quarter block so the pair compares directly.
  - **Fine Details:** the **same-size square divided into 2x2 quarters with one quarter filled**,
    literally showing "edit one quarter of a cell". Because Cell Selector is the same-size square
    filled whole, the two icons read as a matched pair at identical footprint: **whole cell filled
    vs one quarter filled**, a clear granularity comparison. Chosen over a paintbrush because a
    paintbrush reads as generic "paint" and conveys no granularity. Reserve a paintbrush icon for a
    possible future freehand-paint tool.
  - The three share one monochrome style and equal size; only the active button is highlighted.
  - Future tools join the same strip (edge-cell add/remove, wall, door, erase). Edge-cell tool icon
    idea: a square with a green "+" on its outer edge, matching the green "will-be-added" highlight.
  - **Placement decided 2026-08-16: a LEFT vertical tool strip**, with the material/colour palette
    staying on the right. This is the classic image/tilemap-editor split (Photoshop, Aseprite,
    Tiled): tools left, palette right, canvas in the middle, so neither side crowds. See the
    toolbar-layout note under "Optimise the right menu and UI practices".
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
- **Interaction: split by item type (refined 2026-08-16, supersedes the blanket button-press
  decision).** Pickup trigger now depends on the item:
  - **Stackable items auto-collect on step.** Walk onto the cell and the item is picked up
    automatically (coins, collectibles, consumables, and other stackables). No button press; this
    keeps looting fast and Diablo-like for the common case.
  - **Key / unique items require a deliberate interaction, clicking on the item.** These are not
    grabbed by walking over them; the player clicks the item to take it. This prevents accidental
    pickup of important, one-of-a-kind objects and reads as "this matters".
  - Earlier this section recorded a single general interact button for all pickups; that is now
    reserved for the key/unique case (and still shared later with doors, NPCs, chests, switches),
    while stackables need no input at all. Open question for build time: whether the key/unique
    "click" is a mouse click on the sprite or the same general interact button while standing on
    the cell. Resolve when the interact input is built.
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

### Item rarity and rarity highlight (logged 2026-08-16)
Items carry a **rarity tier**, shown as a coloured **outline around the item with no fill** (an
outer line only, Diablo-style item colour coding). The line reads the rarity at a glance while the
item is on the ground and, later, in the inventory. The rarity ramp goes low to high.

- **User's original ramp (as first given):** white (common), then green, blue, purple, gold. This
  is the familiar WoW / modern-ARPG ramp (common, uncommon, rare, epic, legendary). Now extended by
  the decided ramp below.
- **Same system for minion rarity.** The user wants the same colour coding reused for minion /
  creature rarity, so build the rarity tier as one shared enum + palette that both items and
  creatures reference, not two parallel systems. Ties into [[grid-quest-game-vision]] (creature
  collection) and the Creature Diary collection log.

**Decided ramp (user adopted all suggestions 2026-08-16):** six tiers, low to high, monotonic in
"specialness", each visually distinct:
1. **Grey** (junk / poor)
2. **White** (common)
3. **Green** (uncommon)
4. **Blue** (rare)
5. **Purple** (epic)
6. **Orange-gold** (legendary)

Rationale and render rules, all adopted:
- **Grey junk tier added below white.** Useful once there is vendor-trash or low-value loot: grey
  lets the eye skip it instantly. Defined in the shared enum from the start.
- **Top tier is orange-gold, not pure gold.** A thin pure-gold/yellow outline goes muddy and washes
  out on light or sandy floors. Push it warm and bright (orange-gold) so "legendary" reads clearly
  and stays punchy on more backgrounds.
- **Contrast guarantee on any floor (render requirement).** Because the highlight is a fill-less
  outline, white and gold can disappear over pale Coloured-floor tiles (see the Coloured floors
  section). Every rarity outline gets a subtle dark inner edge or 1px drop-shadow so the colour
  stays legible on any ground colour. This is a render detail layered on top of the palette, not a
  palette change.
- **Accessibility second cue (required).** Green / blue / purple are the classic red-green and
  blue-purple confusion zone for colourblind players, so rarity must never be colour-only. Pair each
  tier with a non-colour cue: outline **thickness** stepping up with rarity, and/or a small rarity
  pip/gem on the item. Plan this into the outline shader / item render from the start.

**Distinct from the editor highlight palette.** This rarity outline is a *gameplay* render on the
item/creature itself and must not be confused with the editor action-highlight colours (red=erase,
orange=ground, green=add, and so on) under the Coloured highlight system; they share some hue names
but serve unrelated purposes.

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
  Starts as presets, with a full colour picker later.

### Colour palette: 16 swatches, half material-aware (decided 2026-08-16)
The preset palette is **16 swatches in two groups of 8**:
- **8 realistic, material-aware swatches** that **change based on the material/terrain being
  coloured**, so they always make sense for it (use common sense per material):
  - **Wood:** a range of wood tones (light oak, pine, walnut, dark stain, etc.).
  - **Metal:** steel, silver, gold, bronze, platinum (plus e.g. iron, copper).
  - **Grass:** natural greens and yellows (fresh green through olive to dry yellow).
  - **Stone/slate:** a grey palette (light grey through slate to near-black).
  - ...and sensible sets for other materials (carpet, sand, snow, etc.).
- **8 arbitrary "fun" swatches** that are **fixed regardless of material**: the current colour set
  (red, orange, yellow, green, blue, purple) rounded out to 8 (e.g. + brown, grey/black or
  pink/cyan). These are the non-realistic recolours.
- The two groups sit together (e.g. a realistic row + a fun row). The **full colour picker** still
  comes later for anything specific.
- Build note: the realistic group is driven by a **per-material swatch table** (material -> its 8
  contextual colours); selecting a material/terrain swaps that row. The fun group is a constant. This
  pairs with "Terrain patterns and material variants" (pattern axis) and the material tiers.

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

**Tool strip as-built (2026-08-16): modes DONE.** The persistent left tool strip
(`ui/tool_strip.gd`, a CanvasLayer added to `main.tscn`) now holds two sections. The **Tools** radio
group (Magic Wand / Cell Selector / Fine Details / Erase, W/C/F/E shortcuts) owns mode selection,
which has moved off the right-click popup; it calls `FloorManager.set_mode`. The **Map Size**
control below it is a Top/Bottom/Left/Right row each with a `+` (grow) and `−` (shrink) button wired
to `MapEdit.grow/shrink`, plus a "Recenter (Home)" button (recenter moved off F so F is Fine
Details). Hovering a Map Size button previews the affected row/column via `EdgeHighlight` (green for
add, red for remove). The material/colour *menus* are still the right-click popup (Floor materials +
Wall colours + Grid), not yet on the strip and not yet contextually filtered. Explicit per-edge
buttons were used (not mouse-to-edge) so edge editing works before the pointer-driven UX, and they
stay useful for off-screen edges even with the new editor camera. See the Coloured highlight system
as-built note for the green/red band and the Authoring surface note for the modes and Magic Wand.

The menu gains a **Block / Ground** mode toggle (bottom option) that decides which options
are shown. The Grid Lines toggle stays near the bottom, default **OFF** (confirmed 2026-08-16). The
grid is **hidden in Play mode regardless** of the toggle (it is editor UI; see the Play / Edit
toggle). Note: with the tool strip, mode selection has moved out of this menu; the Grid toggle can
live on the toolbar/top bar rather than the right-click popup.

- **Block mode** (ON by default): the red highlight covers the single block under the
  cursor, so the user edits just that one block. A block edit overrides any colour set by
  Ground mode.
- **Ground mode**: the red highlight outlines the whole floor (current room-shape
  behaviour) and edits the whole room's floor. It also lets the user select the outdoor area.

**Contextual right-click menu (HIGH PRIORITY, spec clarified 2026-08-16).** The menu must show
**only the sections relevant to what was clicked**, not every section at once:
- **Right-click a floor cell → floor sections only, as TWO separate sections (confirmed
  2026-08-16):** a **Floor Colours** submenu and a **Floor Textures** submenu (the existing floor
  materials: Grass / Wood / Concrete / Tile / Carpet), kept distinct rather than merged into one
  "Floor" list. "Floor Colours" is the tint from the unbuilt **Coloured floors** feature, so it
  ships when tinting does.
- **Right-click a wall (or door) cell → wall sections only:** **Wall Colours** (existing tint), and
  wall materials later (wood / slate / stone, per "Terrain patterns and material variants").
- Scope and Grid stay available regardless (they are tool settings, not target sections).
- **Implementation sketch:** at right-click, detect whether the cell is a wall/door (`obs`
  blocked/gate sets) or floor, then build/enable only that target's submenus. Today the menu is
  built once in `_ready` with both "Floor" and "Wall Colour" submenus always shown; move to
  building (or enabling/hiding) submenus per click. **Do NOT static-rename** the submenus to bare
  object names, a first attempt did ("Wall Colour" → "Wall") and the user rejected it; the section
  headings stay descriptive ("Wall Colour", "Floor Colour", "Floor Textures"), they just appear only
  when relevant. Larger job with a verify cycle: best done in a fresh session, and "Floor Colours"
  wants the Coloured-floors tint built alongside it. More broadly, menu/option names should reflect the current target so nothing
reads as the wrong object. The user calls this **renaming pass high priority**. Depends on a notion
of the selected target (Block vs Ground / floor vs wall), which the Block/Ground toggle above and the
tool strip provide; wire the submenu label (and any other target-named options) to that. Note floor
*colour tinting* itself is the unbuilt "Coloured floors" feature, so the near-term rename fix can
start by making the existing label context-correct even before floor tinting ships.

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
                Type:   Hedge, Wood Fence, Slate Wall, Stone Wall, Brick Wall, Metal Bars, Chainlink
                        (canonical roster, decided 2026-08-16; see Resource costs and material tiers)
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
- **Resource costs and material tiers (logged 2026-08-16, roster settled 2026-08-16).** Each
  wall/fence and eventually each ground type has strengths and weaknesses, so the player must gather
  the right material and build a containment area suited to a given minion. The **canonical wall
  roster is the superset** (user chose to keep Brick and Metal Bars from the old menu alongside the
  material-tier list), ordered roughly weak to strong:
  - **Hedge:** 5 Seeds = 1 Hedge. Weakest; can burn.
  - **Wood Fence:** 5 Wood = 1 Wood Fence.
  - **Slate Wall:** 5 River Slate = 1 Slate Wall (stacked slate; tougher than wood, easier to knock
    down than stone).
  - **Stone Wall:** 5 Quarry Stone = 1 Stone Wall.
  - **Brick Wall:** 5 Clay = 1 Brick Wall (decided 2026-08-16). **Clay** is a gatherable resource
    (e.g. dug from riverbanks/pits). Strength **~Stone tier**: a strong wall that is a cosmetic /
    side-grade peer of Stone rather than exceeding it; fits the house/town look.
  - **Metal Bars:** 5 Iron = 1 Metal Bars (decided 2026-08-16). **Iron** is mined ore. Strength
    **above Stone**, the toughest of the normal (non-industrial) ladder. Trait: **see-through**, so
    it is ideal for cages/paddocks where you want to watch the contained beast.
  - **Chainlink:** industrial/"Tradie" tier (see build below), paired with a concrete floor. Future:
    chainlink can be magically electrified, so an electric attack on the fence does half damage to
    anyone on adjacent blocks; a steel floor conducts electricity the same way.
- **Full strength ladder (decided 2026-08-16):** Hedge < Wood Fence < Slate Wall < Brick Wall approx=
  Stone Wall < Metal Bars, with Chainlink as the separate industrial/Tradie tier. Materials: Seeds
  (Hedge), Wood (Wood Fence), River Slate (Slate), Clay (Brick), Quarry Stone (Stone), Iron (Metal
  Bars). All base costs are 5 units = 1 structure (before Builder Bear discounts). Ground types will
  later get their own strengths/weaknesses too (logged, not yet specced).
- **Builder Bear minion (logged 2026-08-16, building-cost buff).** A minion that reduces build
  costs as it levels, and (special ability) can be ordered to build:
  - L1: 4 of each material per structure. L2: 3. L3: 2. L4: 1 (1 Wood = 1 Wooden Fence, etc.).
  - **Special ability (level 5, see the level-5 loyalty rule below):** 1 material = 2 structures.
  - **Ordered building:** the user marks target cells; the minion walks to a free adjacent cell,
    faces the target, and places the obstacle with the same hovering drop effect as editor placement
    (see "Terrain placement UX"). Needs a pathing/planning system that (a) detects a cell that cannot
    be built because it has no free adjacent stand-from cell, and (b) when building several adjacent
    obstacles (e.g. a wall in a line), builds the ones that could get boxed in first: if placing A
    would block the minion from reaching a stand-from cell for B, build B first.
  - Absorbing Builder Bear's power gives the **player** the same build ability first-hand.
- **Level-5 "loyalty" ability rule (logged 2026-08-16).** Every minion has a special ability that
  unlocks like a level 5. It can only be levelled to when the **character is level 4** and the minion
  is set as the player's companion; lore-wise the minion offers its most prized ability to show
  undying loyalty. Intended pacing: the early game is deliberately hard (scarce resources, building
  containment for starter minions); later, a Builder Bear or absorbing its power feels like an earned
  quality-of-life upgrade.
- **Minion rarity tiers gate power level (logged 2026-08-16).** Minions of the same type come in
  tiers that cap how high they upgrade: Basic = L1, Uncommon = L2, Rare = L3, Legendary = L4,
  Mythical = L5 (special ability). When the player absorbs a power it starts at level 1 and can only
  reach the level of the minion it was absorbed from, so rarer absorbed minions unlock higher
  self-power. Ties to the absorb-vs-domesticate fork and materia-style leveling.
- **"Tradie" build (logged 2026-08-16, playstyle).** A Minecraft-like build where the player wants
  all-building buffs; the world morphs toward skyscrapers and a construction-site look. Minions
  unique to this style need industrial barriers (concrete + chainlink) to contain them. Ties to
  World-morphing maps and Playstyle builds; add there as a candidate build alongside the existing
  six.

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
- **Hide the out-of-range ground texture so the map edge is visible. DONE 2026-08-16.** Ground now
  draws clipped to the grid rect (`grid_background._draw` uses `draw_texture_rect(..., tile=true)`
  over `grid_width*CELL_SIZE` by `grid_height*CELL_SIZE`) and the clear color is black, so beyond the
  edge is void. Resolved the open "walkable range" question: walkable range IS the grid bounds (the
  player already clamps to grid dims and `floor_manager.in_bounds` checks the same), so there is no
  separate per-map movement extent. See the As-built note under "Map extent and edge editing".
- **Fix the way wall caps are made.** (User-requested 2026-08-16.) Revisit how the wall cap is
  constructed in `wall_segment._draw`: today the cap is a thin continuous top surface and a front
  face is drawn only on a run's bottom cell. Surfaced during the coloured-walls work (the cap is now
  drawn as per-cell slices), which put the cap model under scrutiny. Exact desired change to be
  defined at build time.
- **BUG: colour menu mislabelled "Wall Colour" for a floor (logged 2026-08-16).** Floor styling sat
  under "Floor" while wall styling sat under "Wall Colour", so colouring a floor felt miscalled. The
  correct fix is the **contextual right-click menu** under "Right-click menu overhaul" (only the
  clicked target's sections show), not a static relabel. (A first attempt renamed the submenu to
  "Wall"; the user rejected that and it was reverted to "Wall Colour".)
- **BUG: growing the map north stretches a building's shadow upward (logged 2026-08-16, screenshot
  taken).** Adding rows of new terrain to the north (`MapEdit.grow("top")`) makes a building's cast
  shadow extend up into the new rows, which is unwanted. Likely cause: after the top-grow shifts
  every store +1 in y and rebuilds, `shadow_manager` re-projects the wall/building shadow onto the
  freshly added northern floor cells (they are now valid ground above the building) instead of
  keeping the shadow's original length. Investigate the shadow cast length / clipping in
  `shadow_manager` against the resize path; confirm against the user's screenshot in `Screenshots/`.

## Map extent and edge editing (logged 2026-08-16, Phase A priority)
The user wants to start designing levels now, so map size and edges become editable in the editor.

**As-built (2026-08-16): default size, edge visibility, and dim unification DONE.** The runtime
edge add/remove tool below is NOT built yet (still the next item). What was done:
- `GridBackground` is now the single source of grid size (`grid_width`/`grid_height`, default 48x32).
  It exposes `min_walkable_position()` / `max_walkable_position()`. `player.gd` lost its duplicate
  `GRID_WIDTH`/`GRID_HEIGHT`/`MIN_POSITION`/`MAX_POSITION` and reads bounds from GridBackground via a
  new `../GridBackground` ref, so a loaded or resized map moves the walkable edge automatically.
  `map_io` and `floor_manager` already read from GridBackground, so no change was needed there.
- `grid_background._draw` clips the ground to the grid rect and tiles it
  (`draw_texture_rect(ground_texture, Rect2(0,0,w,h), true)`, with `texture_repeat` enabled in
  `_ready` so grids bigger than the 1280x960 texture still fill). Beyond the grid draws nothing.
- `project.godot` sets `environment/defaults/default_clear_color=Color(0,0,0,1)` so the void beyond
  the edge is black. Verified via the capture harness: grass inside the grid, pure black outside.
- Not done here: "remove unwalkable ground" as a separate concept collapsed into the above, since
  walkable range equals the grid bounds (no per-map movement extent exists). Trimming a specific
  in-grid cell is the edge remove-cell tool (next item), not a separate unwalkable-ground pass.
- **Bigger default map now: 48x32 cells (decided 2026-08-16, up from 20x14).** Enlarge the starting
  map so there is room to design real levels before the edge-editing tools land. Quick win, but note
  a code detail: the dimensions live in **two places today** (`grid_background.gd` `grid_width/height`
  vars = 20/14, and `player.gd` `GRID_WIDTH/GRID_HEIGHT` consts = 20/14 that also drive
  `MAX_POSITION`). Unify these to a single source before/while bumping the size, otherwise the player
  movement bounds and the grid disagree. This same unification is a prerequisite for the edge-cell
  add/remove tool (which mutates the size at runtime).
- **Remove unwalkable ground (high priority, user-flagged).** Ground currently draws past the
  walkable area, hiding where the map ends. Stop drawing ground the character cannot walk on so the
  edge reads clearly. Overlaps the "hide out-of-range ground" near-term fix; treat them as one job.
  - **Beyond the edge = inactive-cell tiles (decided + BUILT 2026-08-16, supersedes the earlier
    "empty black" decision).** Pure black read as a jarring hole, so the void is now a field of
    **inactive cells**: grey tiles (`VOID_FILL` dark neutral grey, not `#000`), each with a faint
    cell border and a **subtle darker-grey "+"** in the middle, so the outside reads as "buildable
    void / not active yet" rather than a black cutoff. Built in `world/grid_background.gd`
    (`_draw_void`): tiled on the cell grid, clipped to the visible viewport via
    `_visible_local_rect` (maps the screen corners back to local), redrawn on camera pan/zoom
    (`_process` watches the canvas transform), skips in-grid cells (the ground covers them), and
    caps at `VOID_MAX_CELLS` so a far zoom-out can't stall. The "+" vertical arm is lengthened to
    offset World's 0.7 y-scale so it reads square. The green add-band still shows where the map can
    grow into this void.
    - **Later polish:** a themed out-of-bounds look (water / fog / clouds) remains a future option;
      the inactive-cell field is the shipped near-term look. Could also diverge by Play/Edit mode
      later (e.g. hide the tiles in Play), once the toggle lands.
- **Add and remove edge cells.** Its own edge tool with two grains (adding cells is not a selection
  of existing material, so it does not live under the Magic Wand):
  - **Single:** add or remove an individual cell on the edge of the map.
  - **Row / column:** add or remove an entire edge row or column at once.
  - The candidate cells to be added show a **green** highlight (green marks "will be added", per the
    coloured highlight system below).
  - **Removing a non-empty cell (decided 2026-08-16): delete its contents with it.** Removing a cell
    (or row/column) also removes whatever is on it (terrain paint, walls, doors, placed objects) in
    **one action**, no confirm prompt. Fast and predictable, and because it is a single undo entry,
    Ctrl+Z restores the cell and everything that was on it together (pairs with undo/redo).
  - **New cell terrain (decided 2026-08-16): copy the adjacent edge cell.** A freshly added cell
    inherits the terrain material of the cell it was added next to, so extending a grass field stays
    grass and a stone path stays stone with no repaint. For a whole row/column, each new cell copies
    its own neighbour along the edge. It copies terrain only, not walls/objects on the neighbour. Near
    a mixed edge this can inherit a surprising material, so the copied fill is just a starting point
    the user can repaint.
- Touches grid bounds (`GridBackground.grid_width/height`), the floor/ground store (sparse quad
  map already scales with painted area), and save (grid size is already serialized). Confirm whether
  "walkable range" is the grid bounds or a separate per-map movement extent at build.

**As-built (2026-08-16): ROW / COLUMN grain DONE. Single-cell grain deferred (needs a
cell-existence model).** New autoload `MapEdit` (`systems/map_edit.gd`) with `grow(edge)` /
`shrink(edge)` for edge in top/bottom/left/right.
- **Design: a resize is a pure transform on the `MapIO.serialize()` dict, re-applied through a new
  public `MapIO.apply_serialized(data)` (thin wrapper over `_apply`).** Reusing the load/rebuild
  path means every coordinate store moves in lockstep with one piece of code: walls, doors, wall
  colours, per-16px-quarter floors, the player spawn, and grid size. The before/after dicts also
  drop straight into undo/redo later.
- **Origin shift handled.** Growing at top/left shifts every store +1 cell along that axis (quarters
  +2, spawn +CELL px) so the new band takes index 0; bottom/right just extend, no shift. Verified:
  grow:left moved walls [6,3]->[7,3], spawn.x 272->304, grid 48->49, and grow:left then shrink:left
  round-trips byte-identical.
- **Remove deletes contents in the same action.** `_shift` clips every store to the new bounds, so
  the removed row/column and everything on it (paint, walls, doors) drop in the one pass. Verified:
  shrink:top x4 deleted the 9-cell top wall row and set height 32->28.
- **New band copies the neighbour's terrain (terrain only).** `_copy_edge_terrain` fills the fresh
  row/column's quarters from the cell one step inward; grass neighbours copy nothing (grass is the
  absence of a quarter). Verified: painting the left column wood then grow:left made the new column
  wood.
- **Player stays valid.** Spawn is clamped into the new walkable range after a shift, so removing the
  band the player stood on lands it on a real cell, not the void.
- **Single-cell grain deferred, and why (finding).** The map is a solid rectangle today
  (`grid_width x grid_height`, every cell present, ground drawn for the whole rect). A lone jagged
  edge cell has nowhere to live: there is no per-cell existence set. Adding one is the "shared
  tile-entity / cell-existence model" question in the Architecture review (Q1/Q2); do that first,
  then single-cell add/remove and the green will-be-added highlight are a small follow-on.
- **Interim control (scaffolding, replace with the tool strip + green highlight).** IJKL keys (Shift
  = grow that edge, Ctrl/Cmd = shrink that edge); capture-harness `GQ_RESIZE="grow:left;shrink:top"`
  for headless checks; and `dev/test_resize.tscn` (a fast headless logic tester, prints serialize
  before/after, has a `GQ_PAINTEDGE` hook). None of this is the real UX, which is still pending.

**Hover-to-add UX + non-square commitment (decided 2026-08-16).** The user chose hover-over-the-
target as the edge-add interaction instead of buttons (now feasible because the editor camera can
reach the edges), with the grain set by the active mode:
- **Magic Wand / Line mode: add a whole row/column.** Hover just outside an edge highlights that
  row/column green; click grows it.
- **Cell mode: add a single cell.** Hover one empty perimeter spot, highlight one cell, click adds
  just that cell. **This is what enables NON-SQUARE (jagged) maps, which the user has committed to.**
- **Non-square maps need a cell-existence model (the real work, not the highlight).** Today the map
  is a solid rectangle: `grid_background` draws ground as one filled rect, `player` walkability is
  "inside the rectangle", `MapEdit` keeps it rectangular, and rooms/shadows/save all assume the full
  rect. Plan (decided): store a sparse **`absent_cells` set** (holes), default empty. An empty set
  IS today's rectangle, so existing maps and the fast render path keep working and old saves load
  unchanged; a jagged map just lists its missing (or beyond-box) cells. Then ground rendering,
  walkability, save, and the room/shadow edges stop assuming a rectangle. Ties to Architecture
  review Q1/Q2 (shared tile-entity / cell-existence). This is the next dedicated task on this thread
  (do on a fresh session; it touches many files).

**As-built (2026-08-16): hover-add ROW/COLUMN UX DONE (rectangular).** `world/map_size_tool.gd`
(`MapSizeTool` under World), toggled by the tool strip's "Hover-add" check. When on, hovering the
BAND-deep (one cell) void strip just outside an edge shows the green add-band and a left-click calls
`MapEdit.grow(edge)`. Uses `_input` (not `_unhandled_input`) so the void-click beats `floor_manager`,
which consumes every left-click; tool-strip buttons are GUI input so they are handled earlier and
never mistaken for a map click. The edge pick is a pure `edge_at(point, gw, gh)` (corners match
nothing), unit-tested headlessly (GQ_TEST_EDGEAT). Single-cell grain + non-square deferred to the
cell-existence model above; the − buttons still handle remove for now.
- **Hover-add ON by default (decided 2026-08-16).** The "Hover-add" toggle now starts checked, so
  edge grow-on-hover is the default authoring behaviour rather than opt-in. The toggle stays but is
  slated to move into an **advanced options** section later, so most users never see it. Set via
  `hover.button_pressed = true` in `ui/tool_strip.gd`.
- **Green "+" in the middle of the add-band (built 2026-08-16).** The green add-band draws a small
  green "+" glyph at the **true centre** of the band (`edge_highlight.gd`, `_draw_plus`), with a
  dark backing stroke for legibility and the vertical arm lengthened to offset World's 0.7 y-scale
  so it looks square on screen. Only the add-band gets it; the red remove-band reads as delete on
  its own. (Note: an earlier attempt re-centred the "+" to the on-screen portion of the band; the
  user reverted that, so it sits at the true middle regardless of what is scrolled off-screen.)

## Undo / redo (editor history, decided 2026-08-16, Phase A foundation)

**BUILT 2026-08-16 (foundation in place; new tools just call one commit()).** `EditHistory`
(`systems/edit_history.gd`, autoload after MapIO/MapEdit) is the choke point. It is **snapshot-based**,
riding the existing `MapIO.serialize()` / `apply_serialized()` rebuild path: it keeps a `_baseline`
snapshot of the current committed state, `commit()` pushes the pre-action baseline onto the undo
stack and adopts the new state, and `undo()` / `redo()` swap the baseline for a neighbouring snapshot
and re-apply it (same proven path load and resize use, so everything derived, walls/doors/floors/
lighting/shadows/colours, is reconstructed). Snapshots are cheap because the map dict is sparse; `CAP
= 200` bounds the stack. The public API is one call, `EditHistory.commit("name")` after a mutation,
so the diff-vs-snapshot representation can change internally later without touching call sites.
- **Integration surface (the whole point of building it first):** a tool mutates the live map, then
  calls `commit()`. Wired so far: **floor/quarter paint** (one stroke = one entry, committed on
  left-button release in `floor_manager.gd`), **right-click menu paints** (floor + wall colour), and
  **edge grow/shrink** (`MapEdit`). Every future tool (Magic Wand, Erase, wall/door, box-select,
  move, paste) adds its own `commit()` at the point it writes.
- **Keys:** Ctrl/Cmd+Z undo, Ctrl/Cmd+Shift+Z or Ctrl/Cmd+Y redo (`_unhandled_key_input`).
- **Baseline / reset:** `MapIO.load_map` calls `EditHistory.reset()` so a loaded map is a fresh
  baseline with empty history; startup captures the default world after two frames. A no-op commit
  (state unchanged) is skipped via snapshot-hash compare, so history never fills with empty steps. A
  fresh edit after undo clears the redo trail.
- **`changed(can_undo, can_redo)` signal** is emitted for a future toolbar to grey out the buttons;
  no UI consumes it yet.
- **Verified headlessly:** `dev/test_undo.tscn` paints + grows, then walks undo/redo and asserts the
  live map (width + quad positions) returns to the right state at each step, plus the no-op-skip and
  redo-clear rules.
- **Player is exempt from history (done 2026-08-16).** A snapshot still includes the player position
  (serialize stores it as spawn, needed for saving), but undo/redo re-applies with a new
  `keep_player` flag on `MapIO.apply_serialized`, so history never teleports the player: they stay
  where they stand. Verified in `dev/test_undo.tscn`.

Original spec (kept for context):
The user wants **full multi-step undo/redo** (Ctrl+Z / Ctrl+Y) across all editor edits: terrain
paint, object placement, erase, wall/door edits, and edge-cell add/remove. Build this **early**, as a
foundation, so every tool records its own history as it is added rather than being retrofitted after
many tools exist.
- **Mechanism.** Each editor action pushes a reversible entry (do + undo) onto a history stack; a
  redo stack holds undone actions until a new edit clears it. Godot ships an `UndoRedo` (or
  `EditorUndoRedoManager`-style) helper that fits this directly; evaluate using it vs a small custom
  stack at build.
- **Granularity.** One drag-paint stroke should be **one undo entry**, not one per quarter, so undo
  reverses a whole stroke. Group the changed quarters/cells of a single gesture into one action.
- **What to record.** Prefer recording the **minimal diff** (the quarters/cells changed and their
  before/after material, the placed/erased object record, the grid-size delta for edge ops) over full
  map snapshots, so history stays cheap. This aligns with the sparse `_quad_mat` store.
- **Scope.** Editor-only (authoring). Does not need to persist across save/load in v1; a fresh
  session starts with empty history. Revisit if persistent history is ever wanted.
- **Depth: deep but capped (decided 2026-08-16).** Keep a large history (target ~200 actions) so you
  can walk back a long way, but cap it so memory stays bounded in long sessions; oldest entries drop
  off past the cap. Minimal-diff entries keep each cheap. Cap tunable at build.
- **Slots into the tool strip era:** every tool (Magic Wand fills, Cell/Fine Details paint, Erase,
  wall/door, edge-cell) wraps its mutation in a history entry at the point it writes.

## Creature placement in the editor (decided 2026-08-16: all three)
The editor supports **three ways to author creatures (monsters/animals)**, each for a different design
need. Ties into the creature systems (Wild Monsters, capture/absorb, respawn) which are Phase C.
- **Spawn point:** marks a spot where a creature of a chosen type spawns on entering the map / play
  start, then roams per its AI. **Respawns on re-entry unless captured or absorbed** (per the
  creature lifecycle). The default, reliable-single-roamer tool.
- **Fixed instance:** one specific placed creature that stays exactly where authored until it acts.
  For **scripted / boss / unique / quest** creatures that must be exactly here, not randomised.
- **Spawn zone/region:** an **area (authored with box-select)** flagged to periodically spawn a
  chosen type within it, for **populating wild areas**. More complex; can land after points/instances.
- All three store a creature **type** plus placement data; the zone stores a region + spawn rules
  (rate, cap). Capture/absorb state and respawn tracking live in character/game data (the Q4 save
  split), not map data, so a captured creature does not respawn.
- Build order suggestion: fixed instance and spawn point first (single-cell records), spawn zone
  later (needs region storage + a spawn timer/cap).

## Door authored state (editor, decided 2026-08-16)
A placed door defaults to **closed** (the common enclosure case), and its **authored state is
settable per door: closed / open / locked.**
- The authored state is the door's state **on map load**.
- **Locked** ties into the keys system: a locked door needs its Unique key (Architecture Q3 id/key
  binding); authoring a door as locked is where a key gets bound.
- Lives in the contextual right-click menu for a door (Edit Door), alongside type/colour.
- Build note: doors already track open/closed at runtime; this adds a persisted **authored initial
  state** to the door record, plus the locked flag + key binding when locked doors land.

## Eyedropper (pick material, decided 2026-08-16)
An eyedropper that grabs an existing cell's terrain material/colour and sets it as the active brush,
so matching existing terrain needs no palette hunting.
- **Tool-strip button** for it, **plus an Alt+click shortcut while a paint brush is active** (Cell
  Selector / Fine Details) that picks the hovered cell's material and sets the brush.
- **Modifier note:** Alt already means "subtract from selection" during selection tools. No clash
  because the two are mutually exclusive by context: Alt = eyedropper only while a **paint** brush is
  active; Alt = subtract only while a **selection** tool (wand/box) is active. The active tool
  disambiguates. Document this clearly so the mental model stays simple.
- Picks material/colour only, not walls/objects (a wall eyedropper could come later).

## Map sharing: export / import (decided 2026-08-16)
Friends will build maps too, so maps share as **self-contained files**:
- **Export** a map to a shareable file (the existing `user://maps/<name>.json`, self-contained) to
  send to a friend by any file-transfer method. No server needed.
- **Import** drops a received map file into your library (into a chosen folder/category), with a
  name-collision check (rename or overwrite).
- Fits the current save format directly; the map JSON already holds everything (grid, terrain, walls,
  doors + ids, objects, spawn). Character/game data stays separate (Q4 split), so a shared map carries
  no personal save state.
- Later polish: a friendlier package (e.g. embedding a thumbnail) and versioning tolerance so a map
  from an older/newer build still imports (per-section versioning already planned).
- Rejected for now: a shared/cloud-sync folder (needs conflict handling + external setup) and
  files-only-no-UI (unfriendly for non-technical friends).

## Map library organization (decided 2026-08-16: folders / categories)
As many maps accumulate (yours plus friends' maps), the flat name list in the M-key menu grows into
**folders / categories**:
- Maps are grouped into folders or categories (e.g. by area, by author, by project) in the load/save
  UI.
- **Storage options (settle at build):** either real subdirectories under `user://maps/<folder>/`,
  or a flat store with a `folder`/`category`/`tags` field per map that the UI groups by. The tag/field
  approach is more flexible (a map can carry tags without moving files); subdirectories are simpler
  on disk. Recommend a category field over hard directories so maps can be re-filed without moving
  files.
- Pairs well with a search/sort and per-map thumbnails for recognition (decided below).

### Map thumbnails (decided 2026-08-16: auto on save)
Each saved map stores a **small top-down snapshot captured on save**:
- Shown in the load list and library folders; **travels with exported maps** so friends recognize an
  imported map at a glance.
- Cheap: render the map small once per save (reuse the capture path,
  [[grid-quest-capture-harness]]). Store alongside the map (embedded or a sibling file).
- Rejected: generate-on-demand (more work each list open, needs the map partially loaded) and no
  thumbnails (harder to recognize maps as the library grows).
- Accepted the extra UI overhead (folder management) over the simpler flat-list-with-search, per the
  user's choice, because the map collection is expected to get large (multi-map game + shared maps).

## New Map flow (decided 2026-08-16)
**New Map always starts as a blank 48x32 grass canvas** (the default size), no size prompt and no
templates. The edge-cell tools handle any resizing afterward, so there is nothing to decide up front.
- Keeps map creation one click; consistency over configurability.
- A blank map = 48x32 grass, no walls/objects, spawn marker at a sensible default cell (e.g. centre)
  the user can move.
- Templates (empty / walled room / small house) were considered and deferred: they need authoring
  first and are not needed for the first pass.

## Play / Edit toggle (decided 2026-08-16)
A **toggle (button + hotkey)** flips the editor between two modes, a concrete lightweight first
version of the logged play-mode vs editor-mode split (see Other logged ideas):
- **Edit mode:** the tool strip and menus are live, the camera is free (pan/zoom), left-click
  paints/places, the character does not walk. Authoring state.
- **Play mode:** the editor UI hides, the camera follows the player, you **walk the character from
  the spawn marker** to test the map. Play does not mutate map data (matches the Q4 map-data vs
  character-data split: play would only touch character/game data).
  - **Playtest start (decided 2026-08-16): spawn marker by default, plus "test from here".** Normal
    Play starts the character at the spawn marker (true to real load). A **"playtest from here"**
    option (a modifier on Play, or right-click a cell) drops the character at a chosen cell so a far
    corner can be tested without walking there. Best of both.
- **Flip back any time** to keep editing; fast iteration is the point (avoids a save-then-launch
  round trip).
- Resolves the conflict where a free camera and "left-click paints" cannot coexist with walking the
  character; the mode decides which input scheme is active.
- Build note: this formalises today's always-walkable behaviour into an explicit mode flag the
  camera, input, and UI all read.

## Naming: rooms, paddocks, and creature nicknames (logged 2026-08-16)
Two related naming features from the notes:
- **Rooms and paddocks can be named (editor).** A room/paddock (an enclosed region) can carry a
  user-given **name**. Fits the room-topology service (Architecture Q2) as a per-room field keyed by
  `rep_cell`, authored via the Floor/room right-click menu or the inspector, saved in map data.
  Useful for labelling ("Frost Frog paddock"), future minimap labels, and paddock/base management.
- **Loyal minions and animals can be nicknamed (gameplay).** Once a creature is **loyal** (max
  domestication; a Loyal Minion or Loyal Animal, see the terminology glossary), the player can give
  it a **nickname**. Nickname is character/game data (Q4 split), not map data. Ties to the Creature
  Diary (nickname shown there) and companion UI. Deferred to the creature pillar (Phase C); logged so
  it is not lost.

## Player spawn marker (editor, decided 2026-08-16)
Setting where the player starts on a map uses a **placeable spawn marker**, not the character's
saved position:
- A **"Set Spawn" tool** drops a spawn marker on a cell; drag it to move (like any placed object).
  **One per map.**
- **Visible in the editor, hidden in play.** On load the player starts on the marker's cell.
- Decouples spawn from having to walk the character there, and works cleanly with the free editor
  camera (you are not moving the player to author).
- Build note: `MapIO` already serializes a spawn; this gives it an explicit editor affordance and a
  visible marker rather than implicitly using the player's position.

## Move tool (drag-move, keeps identity, decided 2026-08-16)
Reposition an already-placed thing without delete-and-replace. **Magic-Wand-select** it (or a
region), then **drag it to a new cell**; the hover/drop-preview shows the destination before release.
- **A move keeps the object's durable id.** Moving a locked door keeps its `door_id`, so its Unique
  key still resolves (per Architecture Q3). This is the "genuine editor move keeps the id" case the
  save design already relies on.
- **Contrast with delete-then-place**, which mints a **new** id, orphaning any key that referenced
  the old one. That is the intended "rebuild = new id" behaviour, and it is why move must be a
  distinct operation, not sugar over cut/paste.
- Moving a **region** (multiple cells/objects) moves terrain + walls + objects together, each object
  keeping its id. One undo entry per move.
- Reuses the selection, drop-preview, and undo systems already specced; the new piece is the "move
  op preserves id" path that the copy/paste and erase paths deliberately do not.

## Editor camera: pan and zoom (decided 2026-08-16, Phase A)
The 48x32 default map is larger than the screen, so the editor needs its own camera, **decoupled
from the player while editing**:
- **Pan:** middle-mouse drag (or hold Space and drag) moves the view around the map, independent of
  the character.
- **Zoom:** scroll wheel zooms in (for quarter-level Fine Details work) and out (to see the whole
  level for layout). Clamp min/max zoom at build.
- **Pan bounds (decided 2026-08-16): clamp to map + a small margin** of surrounding void, so you can
  see and work at the edges (needed for the green add-cell tool into the void) but cannot drift into
  infinite emptiness. Recenters gracefully. Margin size tunable at build.
- **Decoupling:** in play the camera follows the player; in the editor it is free. This is a small
  concrete instance of the future play-mode vs editor-mode split (see Other logged ideas): editing
  uses a free camera, play uses the follow camera.
- Build note: today the camera follows the player (`MAX_POSITION` / player-centered). Add an editor
  camera state that takes over during authoring; confirm the current camera setup at build.

**As-built (2026-08-16): DONE.** `camera_follow.gd` now has FOLLOW / FREE modes. Middle-mouse drag
pans, the wheel zooms toward the cursor (clamped 0.4 to 5.0), and the centre is clamped to the map
rect plus a 160px margin so the edges and the green add-band stay reachable but you cannot drift
into the void. Any pan/zoom drops into FREE; **F or Home recentres on the player and returns to
FOLLOW** (also a "Recenter (F)" button on the tool strip). A `fit_map()` frames the whole map (used
by the capture harness). Space+drag not wired (middle-mouse only) since it collides with nothing;
add later if wanted. This is the concrete free-vs-follow split the Play/Edit toggle will formalise.

## Placing directional objects (orientation control, decided 2026-08-16)
How the editor sets facing/run direction for directional things (doors, wall runs, future furniture
per [[grid-quest-asset-perspective-model]]): **auto from context, with an R key to override.**
- **Auto default.** The editor infers the obvious orientation from surroundings: a **wall run
  follows the drag direction** (horizontal drag = E-W run, vertical = N-S), a **door faces through
  the wall segment it is placed on**, furniture takes a sensible default facing. Covers the common
  case with no extra input.
- **Manual override: R cycles orientation** (N/E/S/W or the object's valid set) before/while
  placing, for when the inferred facing is not what is wanted. Shown live in the hover preview so the
  chosen facing is visible before the drop.
- Ties into the existing orientation/front-back/y-sort conventions
  ([[grid-quest-asset-perspective-model]]); the preview must render the currently chosen orientation.
- Build note: gates already carry an orientation and walls already build as runs, so auto-inference
  has existing data to read; R-override adds a per-placement orientation state to the armed brush.

## Unsaved-work protection (decided 2026-08-16: autosave + warn)
Both safety nets, since the user wants maximum protection:
- **Dirty-flag warning.** Track whether the map has unsaved edits; on **load another map / new map /
  quit** with unsaved changes, prompt **Save / Discard / Cancel**. Only appears when actually dirty.
- **Autosave to a recovery file.** Write a **separate recovery file**, distinct from the real
  `user://maps/<name>.json`, so a crash/close can be recovered without silently overwriting the
  user's saved map. On next launch, if a recovery file is newer than the saved map, offer to restore
  it. **Cadence (decided 2026-08-16): a short idle timer** (debounced, e.g. ~3s after you stop
  editing) **plus a periodic fallback** (~2 min), so work is captured almost immediately without
  writing on every paint/drag. Cheap on the atomic-write path.
- **Keep the two concepts distinct to avoid confusion:** autosave protects against crashes into a
  recovery slot; explicit Save (M menu) writes the real map file; the dirty warning guards explicit
  navigation. Pairs with undo/redo for in-session recovery.
- Build note: reuses the existing `MapIO` atomic-write path; adds a dirty flag (set on any edit,
  cleared on explicit save) and a recovery-file slot + newer-than check on launch.

## Box-select (rectangular area selection, decided 2026-08-16)
A second selection tool alongside the Magic Wand: **drag a rectangle to select every cell inside it,
regardless of material or room boundaries.**
- **Wand = select by material/room** (connected same-material patch, whole room, wall structure);
  **box = select by area** (an arbitrary rectangle of mixed contents). Two complementary ways to
  build a selection.
- Feeds the **same** downstream tools: copy/paste, move, and any edit applied to a selection. A
  selection is a set of cells/quarters + the objects on them, however it was made.
- Uses the marching-ants outline like the wand.
- Lives as its own tool button on the left strip. Build note: a box selection is just a filled
  rectangle of cells, simpler than the wand's floods; both produce the same selection object.

### Applying edits to a selection (decided 2026-08-16)
**With a selection active, picking a terrain/colour/material from the right palette fills the entire
selection at once.** Wand-select a room, click Wood, and the whole room becomes wood; box-select a
region, pick a colour, and it all recolours. This makes wand/box + palette act as a powerful **area
bucket-fill**, the main payoff of having selections.
- A selection is a **reusable target** for any edit: paint, colour, material swap, erase, plus
  copy/move.
- One fill = one undo entry over the whole selection.
- If **no** selection is active, picking a material just arms the brush for the current mode
  (Cell Selector / Fine Details), per the normal Terrain placement UX. Selection-fill is the override
  when a selection exists.

### Additive / subtractive selection (decided 2026-08-16)
Selections compose with standard modifiers, working for **both** the Magic Wand and box-select:
- **Plain click/drag:** replace the selection (new selection).
- **Shift + click/drag:** **add** the new region to the current selection.
- **Alt + click/drag:** **subtract** the region from the current selection.
- You can mix tools within one selection (e.g. wand the carpet, Shift-box a corner, Alt-click out a
  door). The result is one selection object fed to copy/paste/move/edit.
- Build note: the selection is a mutable set of cells/quarters; add/subtract are set union/difference
  over the tool's produced region. Marching-ants redraws on each change.

## Copy, paste, and duplicate (editor, decided 2026-08-16)
The user wants copy/paste and duplicate to speed up level design. It builds directly on two things
already specced, so it is a natural fast-follow rather than new machinery:
- **Select** a region or room with the **Magic Wand** (patch, whole room, or a wall structure), then
  **Ctrl+C** copies the selection's contents: terrain quarters, walls, doors, and placed objects,
  captured relative to the selection's origin.
- **Ctrl+V / duplicate** arms a **paste brush** that shows the copied block as a **hover preview**
  (reuse the Terrain placement UX drop-preview) and stamps it on click, with the drop animation.
- Each paste is **one undo entry** (reuse undo/redo).
- **Rotate + flip on paste/move (decided 2026-08-16): supported from the start.** A pasted or moved
  region can be rotated (90-degree steps) and flipped (horizontal/vertical) before it drops. This is
  a deliberate commitment that raises a real dependency:
  - **Directional assets must re-orient correctly, not spin naively.** In the top/front perspective,
    a wall run, a door facing, and angled furniture each have orientation-specific art. Rotating a
    region must **remap each directional piece to its correct rotated/mirrored art** (a N-S wall
    becomes E-W; a door facing east becomes facing south; etc.), via an **orientation-remap table**,
    not an image rotation. Non-directional terrain quarters just move/rotate as data.
  - **Therefore this depends on every asset having all its orientations** (see
    [[grid-quest-modify-all-asset-states]], [[grid-quest-asset-perspective-model]]). Where a rotated
    orientation's art is missing, that asset cannot be rotated yet. Practically: rotation lights up
    per-asset as its full orientation set exists; terrain-only regions rotate immediately.
  - Flip is often cheaper than rotate (many assets mirror cleanly), but still needs the mirrored
    facing to be a real, correct state.
  - Build the orientation-remap table as the single source for "orientation X rotated/flipped ->
    orientation Y", reused by rotate, flip, and the R-key placement override.
- **Also settle at build:** paste anchor/alignment to the grid, whether paste overwrites or merges
  with what is already there (recommend overwrite within the pasted footprint), and pasting near/over
  the map edge (clip, or auto-extend via the edge-cell logic).
- **Cross-map clipboard (decided 2026-08-16).** The copied selection lives on a clipboard that
  **survives loading another map**, so you can build a room/structure once and reuse it across
  levels (a big win for a multi-map game). The clipboard **optionally persists to disk** so it can
  even survive a restart. Pasting into a different map remaps/mints ids as needed (a pasted locked
  door gets a fresh id, like any new placement) and clips or auto-extends at that map's edges.
- **Timing:** after the core Phase A tools (needs the Magic Wand selection, placement drop-preview,
  and undo all working first); a Phase A fast-follow, not the first pass.

## Coloured highlight system (logged 2026-08-16, Phase A)

**Partial as-built (2026-08-16): GREEN (add) and RED (remove) done for the Map Size tool.**
`world/edge_highlight.gd` (an `EdgeHighlight` Node2D under World, drawn over the ground) fills the
affected edge row/column: **green** for the will-be-added band (drawn just outside the edge, in the
void) and **red** for the will-be-removed edge band. The tool strip drives it on button hover.
Verified via the capture harness `GQ_EDGEBAND="left:add"` on a fitted map. **Marching-ants for the
Magic Wand is now DONE** (`floors/selection_overlay.gd`; see the Authoring surface as-built note).
Still to do: orange (ground recolour of the existing floor mask), purple (walls), blue/cyan (doors),
and yellow (shadow). This edge band and the ants are plain `_draw`; the room/wall *hover* highlights
stay on the FloorHighlightMask shader path, whose colour becomes a per-action parameter.

Replace the single red hover highlight with a **colour-coded highlight** that tells the user what
kind of action they are about to take. Final palette (all confirmed with the user 2026-08-16):
- **Red: erase / remove** (destructive). Red now means "delete", the universal danger convention.
  Drives the Erase mode below.
- **Orange: ground / terrain edits.** The current red floor highlight is **recoloured to orange**
  (the user swapped red onto erase, since red = destructive reads more naturally). Implementation:
  change the highlight colour in `floor_outline.gdshader` / the FloorHighlightMask path (see the
  "Red highlight system" note under In progress); the mask mechanism is unchanged, only the colour.
- **Purple: walls.**
- **Green: additive placement** (placing items, adding monsters, adding animals, adding non-wall
  obstacles, and adding edge cells). Green means "adding something new". Confirmed 2026-08-16: **one
  green for all adding**, not split per object type; the active tool/mode already says what is being
  added, so the colour only needs to signal "add".
- **Blue / cyan: doors** (a wall feature but a distinct action from a plain wall, so a distinct
  colour reads better than reusing purple).
- **Yellow: shadow / lighting toggle** (indoor vs outdoor), since it reads as "light".
- **Build-time contrast check:** orange (ground) and yellow (shadow toggle) are adjacent hues;
  verify they are distinguishable in-game, and nudge one if not.

### Erase mode (tool, logged 2026-08-16)
A dedicated **Erase mode** that deletes placed things: obstacles, monsters, items, and (per the wall
editing work) walls and doors. Lives as a tool button on the left tool strip alongside Magic Wand /
Cell Selector / Fine Details; its hover highlight is **red**.
- **Click removes the topmost object only (decided 2026-08-16).** One click deletes the single top
  thing on the hovered cell (e.g. a monster), the next click the thing under it (e.g. the wall), and
  so on; **terrain paint is removed last, only when no placed object remains** on the cell. Precise
  and predictable, click-again to keep clearing. The stacking order comes from the cell-occupancy
  model below. Each removal is one undo entry.

### Cell occupancy model (decided 2026-08-16)
Defines what can share one cell, and therefore placement rules and the erase order. **Three layers,
at most one of each per cell:**
- **Terrain** (always present): the ground/quarter layer.
- **Structure** (optional): one **wall OR one door** (a cell cannot hold both a wall and a door).
- **Object** (optional): one placed item, monster, animal, or non-wall obstacle.
- **Erase (topmost-first) order:** object -> structure -> terrain.
- **Placement rule:** placing into an occupied layer replaces (or is blocked for) that layer's
  current occupant; the other layers are untouched (e.g. dropping an item onto a floor cell that has
  a wall is allowed, item + wall + terrain coexist). Exact replace-vs-block per layer settled at
  build.
- Rejected: free multi-object stacking (complicates collision/erase/save) and one-thing-per-cell
  (too restrictive, could not put a monster on a floor). This clean layering also keeps the save
  compact: terrain in the quad store, structures in the walls/doors records, objects in an objects
  record, all cell-keyed.

### Passability (decided 2026-08-16)
Whether something blocks the player is a **per-type default with a per-object override**:
- **Type defaults:** obstacle / table = **blocks**; item pickup / small decor = **passable**;
  monster = **blocks while alive**; wall = blocks; door = blocks when closed, passable when open;
  terrain = passable (except future impassable terrain like water).
- **Per-object override:** any individual placed object can have its **"blocks movement" flag toggled**
  in the editor, for level-specific exceptions (a one-off passable prop, a decorative monster).
- Good defaults mean the flag is rarely touched; the override exists for the exceptions. Stored as a
  per-object bool defaulting from type. Ties to the future impassable-terrain work (Water) which adds
  a per-terrain passability flag on the terrain layer.

### Multi-tile objects (footprint, decided 2026-08-16)
Objects that span several cells (tables, large furniture) are **one object with a footprint of
cells**, preserving the one-object-per-cell rule:
- The object is a single record with a **footprint** (its set of covered cells + an anchor). **Each
  covered cell's object-layer references that same object**, so a cell still holds at most one
  object.
- **Placement** checks every footprint cell's object-layer is free (structures/terrain per their own
  layers) before allowing the drop; the hover preview shows the whole footprint and is blocked/red if
  any cell is occupied.
- **Erase / move / select** act on the **whole object** from any of its cells (one undo entry).
  Passability applies **per covered cell** (a table blocks all its cells).
- Rotation/flip of a multi-tile object rotates its footprint too (ties to the orientation-remap
  work). Save stores the object once with its footprint, not once per cell.
- This resolves the "one object per cell" model with the roadmap's multi-tile Tables entry;
  single-cell objects are just a 1-cell footprint.
- **Magic Wand selection outline (decided 2026-08-16): marching ants.** An animated dashed outline
  (Photoshop/GIMP convention) around the current wand selection, distinct from the six solid action
  colours because it reads as motion + dashes, not a fill. Works on the growing selection (patch,
  then whole room, then walls). Colour of the dashes can be tuned at build for contrast.
- Implementation note: today's highlight is a render-mask driven by `floor_outline.gdshader` (the
  "Red highlight system"); the colour is a shader/mask parameter, so colour-per-action is a small
  extension of that system rather than new geometry.

## Terrain placement UX (select, hover-preview, drop, logged 2026-08-16, Phase A)
How laying terrain should feel in the editor (the user calls this "Terrain Mode"):
- **Select does not auto-place.** Choosing a terrain and colour from the right menu arms a brush; it
  waits for the user to click the target cell. (Supersedes the current "picking a material paints
  immediately" behaviour for this mode.)
- **Hover preview.** Over a hovered cell, on top of the highlight and lifted a few pixels on the z
  axis, show a **sprite of the chosen terrain** (the example given is a concrete tile) so the user
  previews exactly what will land.
- **Click to drop.** Clicking "Fill" / "Lay" plays a short **drop animation**: the hovering piece
  falls into the cell from slightly above and settles. Applies to editor placement and, later, to a
  Builder minion placing obstacles (same drop effect, see Builder Bear).
- **Cursor leaves the screen: clear all highlights.** When the cursor moves off screen, every
  highlight disappears.

## Wall editing and outside reclassification (logged 2026-08-16, Phase A + analysis)
The user wants to add and remove wall pieces in Cell Mode. Removing a perimeter wall that exposes a
room to the outside makes that room "become outside". **Analysis of what this affects (good news:
mostly automatic given the current architecture).**
- **Room topology / flood fill (automatic).** Indoor vs outdoor is already computed by the exterior
  flood fill in `room_light` (`_build_exterior`, `enclosed_floor_cells`). Removing a perimeter wall
  opens the enclosure, so on recompute the exterior flood reaches those cells and they become
  exterior with no new classification logic. The main new work is re-running the flood on a wall
  edit in the editor (it already re-runs on load via MapIO).
- **Lighting (automatic).** The room stops being dimmed, so it "is no longer greyed out", exactly as
  the user wants, falling straight out of the exterior reclassification.
- **Shadows including the player shadow (automatic if keyed off exterior).** `shadow_manager`'s
  indoor/outdoor split drives shadow behaviour; once the room is exterior, wall and player shadows
  behave as outdoors. Verify the player-shadow indoor/outdoor switch reads the same exterior test.
- **Ground tiles: unaffected (by design).** Floors are an independent AREA layer, so removing walls
  does not change the ground, exactly as the user specified and consistent with
  [[grid-quest-floors-fill-whole-room]]. No work needed.
- **Creatures (future).** Creatures inside are alerted when the room opens and react by loyalty.
  Logged for when creatures exist; ties to the creature sections.
- **Roofs / paddock outdoor-override (future linkage).** This is the natural inverse of the paddock
  outdoor-flag idea (a walled room forced outdoor). A roof only shows outside, so an opened room
  should drop its roof. Both consume the same inside/outside service, so extracting room topology
  (Architecture Q2) before these land is worth it.
- Net: because indoor/outdoor is derived, not stored, "remove wall = becomes outside" is largely
  free; the build work is recompute-on-wall-edit plus confirming the player-shadow switch.

## Terrain patterns and material variants (logged 2026-08-16)
Beyond colour, some terrain types get **pattern options that are separate from colour changes**.
- **Terrain patterns:** e.g. different carpet patterns, short vs long grass, multiple tile and wood
  styles to pick from. A pattern axis distinct from the colour axis.
- **Wall and fence material variants:** the same style-swap idea applied to structures, switching a
  wall or fence between **wood, slate, and rock/stone**.
- **Splits later into two modes:** in **game mode** these are built from gathered resources; in
  **level editor mode** (what we are building) they are placed freely. Ties to the resource-gated
  building already noted under base building.
- Menu impact: the right menu gains a pattern/material selector alongside colour. See "Optimise the
  right menu" for keeping this from bloating the menu.

## Optimise the right menu and UI practices (logged 2026-08-16)
The user asked to analyse the right menu for optimisation and to research good UI practices as the
menu grows (modes, colour, pattern, material, walls, doors, items, creatures). Working suggestions
(to flesh out at build):
- **Separate the axes.** Action (terrain / wall / door / erase), style (type/material), and colour
  are independent choices. Presenting them as one deep nested tree bloats fast. Prefer a small
  persistent toolbar for the current action + mode, and a properties strip for style/colour of the
  armed brush, over ever-deeper submenus.
- **Recently-used / favourites.** Surface the last few used terrains/materials so common placements
  are one click, not a menu dive.
- **Live preview everywhere** (already the pattern): hover previews on the cell, click commits.
- **Keep destructive actions distinct** (erase colour-coded orange/hatched, not adjacent to Fill).
- **Consistency:** one place for mode toggles (Object/Cell/Fine Detail), one for Grid lines, stable
  positions so muscle memory forms.
- Revisit against real UI references at build time; logged as a design task, not yet decided.

### Tooltips on menu and tool options (logged 2026-08-16)
The user wants **tooltips on menu options**, and each tooltip should **also show the option's
keyboard shortcut**. Applies across the editor: tool-strip buttons (e.g. "Magic Wand (W)"), palette
swatches, right-click menu entries, and toolbar actions ("Undo (Ctrl+Z)"). Reads the shortcut from
the same hotkey map (see Editor hotkeys), so tooltip and binding never drift. Good UI practice and
cheap; pairs with the rebindable-hotkeys idea (a rebind updates the tooltip automatically).

### Editor hotkeys (decided 2026-08-16: letter mnemonics)
Tool selection and actions get memorable letter shortcuts in Edit mode (the player does not move
while editing, so letter keys are free):
- **Tools:** W = Magic Wand, B = Box-select, C = Cell Selector, F = Fine Details, E = Erase,
  I = Eyedropper, M = Move, D = Door, plus a key each for Wall and Set Spawn (assign at build).
- **Actions:** Ctrl+Z / Ctrl+Y = undo / redo, Ctrl+C / Ctrl+V = copy / paste, R = rotate (Shift+R or
  a flip key for flip), Esc = clear selection / cancel.
- **Modifiers (already decided):** Shift = add to selection, Alt = subtract (or eyedropper while a
  paint brush is active), Space+drag / MMB = pan, wheel = zoom.
- Final letter assignments tunable at build; the scheme is mnemonic-first. Consider making them
  rebindable later.

### Editor layout (decided 2026-08-16)
The editor moves to a standard three-zone layout, resolving the "move modes out of the right-click
menu" work:
- **Left: vertical tool strip.** A radio group of icon buttons for the selection modes (Magic Wand,
  Cell Selector, Fine Details), the active tool highlighted. Future tools join here (edge-cell
  add/remove, wall, door, erase). Icons per the mode-icon spec in the Authoring surface section.
- **Right: material/colour palette + properties inspector.** The existing terrain/colour panel
  (later gaining pattern and material selectors for the armed brush), plus a **properties/inspector
  panel** (decided 2026-08-16) that shows the selected/edited object's settings and updates live:
  a door's type/colour/state, a wall's type/colour, an object's blocks-movement toggle, a spawn
  zone's type/rate/cap, a spawn point's type. Simple objects show a couple of fields, complex ones
  (spawn zones) show more. The context-menu "Edit" action focuses the object here rather than deep
  submenus. Docked on the right near the palette (share/stack the right column).
- **Centre: the map canvas.**
- **A thin status bar (decided 2026-08-16, bottom or top).** Shows live editing info: hovered cell
  x,y, active tool, current selection size, map dimensions (WxH), and zoom %. Cheap and genuinely
  helps precise placement and resizing on the 48x32 grid. Updates on hover/selection/zoom change.
- **Right-click menu becomes purely contextual (contents decided 2026-08-16):** a short menu of
  actions for the specific thing hovered, no mode-switching. By target:
  - **Door:** Edit Door (type / colour / state closed-open-locked), Delete.
  - **Wall:** Edit Wall (type / colour), Delete.
  - **Creature (spawn point / instance / zone):** Edit (type, spawn settings), Delete.
  - **Object (item / furniture / obstacle):** Edit (type, blocks-movement toggle), Delete.
  - **Floor / room:** Set material / colour, Set Indoor / Outdoor (the paddock outdoor-override).
  - **Empty cell:** minimal (e.g. quick-place recents), or nothing.
  Kept short and target-specific; deeper editing still uses the tool strip + palette. Rejected a
  Delete+Properties-only menu (too many trips to a separate panel) and dropping the menu entirely
  (loses quick per-object actions).
- **Top (later):** document actions (save/load, grid toggle, undo/redo) can live in a top bar as
  they arrive; not required for the first pass.
- **Tool strip is grouped with dividers (decided 2026-08-16).** As the strip has grown to ~10 tools,
  cluster them into labelled groups separated by thin dividers, related tools together:
  - **Select:** Magic Wand, Box-select.
  - **Paint:** Cell Selector, Fine Details, Eyedropper.
  - **Objects:** Build (wall / door), Set Spawn.
  - **Edit:** Move, Erase, Edge-cell add/remove.
  Scannable and extensible (new tools join the right group). Flat list and Photoshop-style flyouts
  were considered and rejected (flat gets unscannable, flyouts bury tools a click deeper). Group
  membership can be tuned at build; the grouping principle is the decision.

## Instruction manual PDF (logged 2026-08-16, deliverable, not editor code)
The user wants a **PDF instruction manual** describing all assets and mechanics, to share with
friends so they can build maps, and to explain planned future features. A documentation deliverable
(not part of the editor build); produce it once the editor feature set is stable enough to document.
Good candidate for an Artifact/print-ready page when the time comes.

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

## AI asset generation: prompt pack + style bible (QUEUED 2026-08-16, deliverable, not editor code)
Produce written instructions so the game's art can be AI-generated consistently. Two outputs: a
**style bible** (a fixed prompt prefix + rules every asset shares) and a **per-asset prompt pack**
(one prompt each for the concrete asset list). This is a writing/deliverable task, best done in a
fresh `/clear` session.

- **Tooling: the user plans to run their OWN local AI (Stable Diffusion), and it can run slowly.**
  This is the best fit: local SD is fully free, gives the most control, and is the ONLY option that
  does **seamless tileable textures** (SD tiling mode) for the 128px floors. Favour a pixel-art
  model/LoRA under ComfyUI or Fooocus. Slow generation is fine for a solo asset pipeline. Free
  cloud fallbacks if ever needed: **PixelLab.ai** (transparent-background sprites + walk/idle
  animation frames, the two things general AI is worst at), **Leonardo.ai** (texture generation),
  ImageFX / DALL·E-3 for concepts only.
- **Hard constraints the prompts must bake in:**
  - **Perspective:** the documented top/front hybrid with front/back layers and y-sort depth
    ([[grid-quest-asset-perspective-model]]); AI will not nail this, so expect hand fixup.
  - **All states:** every orientation/state of an object gets made together
    ([[grid-quest-modify-all-asset-states]]).
  - **Diablo / Diablo 2 feel** on every piece (the standing rule above): dark, gritty, moody,
    muted palette.
  - **Dimensions/grid:** floors are seamless-tileable 128px; cells are 32px, quarters 16px. AI
    output gets downscaled + cleaned in Aseprite / free Photopea and aligned to the grid.
  - **Transparency:** sprites (creatures, items) need transparent backgrounds; use PixelLab (native)
    or free bg-removal (rembg / Photopea / Clipdrop). Item art stays plain, the rarity outline
    (grey/white/green/blue/purple/orange-gold) is drawn in CODE, not the art.
- **Reusable style prefix (draft, refine in the build session):** "dark fantasy, Diablo-inspired,
  top-down grid RPG, pixel-art, limited muted palette, even lighting, clean silhouettes, game asset".
- **Asset list to write prompts for (first pass):** the 3 starter monsters (one ability each), the
  Bridge Lizard, floor material variants (grass/wood/concrete/tile/carpet + more), wall materials
  (wood/slate/stone), and item icons (keys first, then coins/consumables).
- **Workflow per asset:** generate (local SD) -> remove/verify background -> downscale + clean in an
  editor -> align to the 32px grid -> drop into the matching `res://` folder and wire it up.
- **Honest expectation:** AI gets ~60-80% on textures and concepts, less on animated character
  sprites (consistency across frames/orientations is the hard part). It is a starting point, not a
  finished pipeline; budget hand-cleanup time.

## Inspirations (reference list, logged 2026-08-15)
The user's stated touchstones, per system, to steer design/art decisions:
- **Art / world feel:** Diablo, Diablo 2.
- **Magic leveling:** Final Fantasy 7 (materia, already reflected in the 08-14 progression spec).
- **Ability absorption:** Sylar from *Heroes* (TV series), taking a creature's power into yourself.
- **Creature collection:** Pokemon (Creature Diary, capture).
- **Home building + resource collection:** Stardew Valley / Minecraft (base building equals the level
  editor, resource-gated in play mode, per 08-14).
- **Karma system:** Fable (morality reshapes play, NPCs, and, here, the world).
