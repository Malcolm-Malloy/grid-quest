extends Node

# Dev-only screenshot harness. Runs the real game (main.tscn), optionally drops the
# player on a given cell/pixel, waits for it to settle, grabs one frame, saves it,
# and quits. main.tscn is never touched, so normal play is unaffected: this only
# runs when you launch capture.tscn on purpose, e.g.
#
#   GQ_POS="272,368" GQ_OUT="res://_shot.png" \
#     /Applications/Godot.app/Contents/MacOS/Godot --path . res://dev/capture.tscn
#
# GQ_POS is the player position in world pixels ("x,y"); omit it to use the normal
# spawn. GQ_OUT is where the PNG lands; defaults to res://_shot.png.

func _ready() -> void:
	# Drop the game's fullscreen launch default (project.godot window/size/mode=3) to a normal WINDOW for
	# captures, so a grab doesn't take over the user's screen. (The window keeps the screen SIZE on macOS -
	# window_set_size won't shrink a just-unfullscreened window here - so shots come out at the screen
	# resolution, which is fine for eyeballing.) Harmless in headless (DisplayServer window ops no-op).
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# tests drive loading explicitly via GQ_LOAD, so auto-reload is off unless GQ_AUTOLOAD=1
	MapIO.auto_load = OS.get_environment("GQ_AUTOLOAD") == "1"
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	# GQ_ROOFS=1 turns Show Roofs on (roofs are off in EDIT by default); GQ_PLAY=1 enters PLAY instead
	if OS.get_environment("GQ_ROOFS") == "1":
		main.get_node("World/Roofs").show_in_edit = true
	# GQ_CREATURE="x,y,id" places a spawn-point creature (before GQ_PLAY, so it hatches alive)
	var gqc := OS.get_environment("GQ_CREATURE").split(",")
	if gqc.size() == 3:
		main.get_node("World/Creatures").add_creature(Vector2i(int(gqc[0]), int(gqc[1])), gqc[2])
		main.get_node("World/Creatures").rebuild()
	if OS.get_environment("GQ_PLAY") == "1":
		EditorMode.set_mode(EditorMode.Mode.PLAY)

	# GQ_LOAD="name" loads a saved map before anything else, so GQ_POS/GQ_FLOOR below act on it
	var load_name := OS.get_environment("GQ_LOAD")
	if load_name != "":
		MapIO.load_map(load_name)

	# GQ_RESIZE runs edge resizes on the loaded/default map before the grab, e.g.
	# GQ_RESIZE="grow:left;grow:top;shrink:right" (semicolon-separated "op:edge" pairs).
	# Lets the row/column edge editing be verified headlessly (no tool strip yet).
	var resize := OS.get_environment("GQ_RESIZE")
	if resize != "":
		for op in resize.split(";", false):
			var parts := op.split(":")
			if parts.size() == 2:
				if parts[0] == "grow":
					MapEdit.grow(parts[1])
				elif parts[0] == "shrink":
					MapEdit.shrink(parts[1])
		await get_tree().process_frame

	# GQ_CELLEDIT="add:x,y;remove:x,y;..." drives MapEdit's single-cell edge editing (jagged maps) so the
	# cell-existence model can be seen: add makes a spur/fills a hole, remove punches a hole. Runs after
	# GQ_RESIZE. Frames the whole map unless GQ_CELLEDIT_NOFIT=1.
	var celledit := OS.get_environment("GQ_CELLEDIT")
	if celledit != "":
		for op in celledit.split(";", false):
			var parts := op.split(":")
			if parts.size() == 2:
				var xy := parts[1].split(",")
				if xy.size() == 2:
					var c := Vector2i(int(xy[0]), int(xy[1]))
					if parts[0] == "add":
						MapEdit.add_cell(c)
					elif parts[0] == "remove":
						MapEdit.remove_cell(c)
		await get_tree().process_frame
		if OS.get_environment("GQ_CELLEDIT_NOFIT") != "1":
			var camce := main.get_node_or_null("Camera2D")
			if camce and camce.has_method("fit_map"):
				camce.fit_map()

	# GQ_SIZEHOVER="x,y" shows the single-cell edge-add GREEN highlight on cell (x,y): puts the editor in
	# Cell mode, turns the Map Size tool on, and draws the highlight the tool shows on hover. It calls
	# EdgeHighlight.show_cell directly (not via a mouse warp, which is unreliable in this windowed capture)
	# so the highlight lands DETERMINISTICALLY on the requested perimeter/hole cell. Frames whole map unless
	# GQ_SIZEHOVER_NOFIT=1. Verifies show_cell's geometry; the mouse-driven path itself is covered by tests.
	var sizehover := OS.get_environment("GQ_SIZEHOVER")
	if sizehover != "":
		var sh := sizehover.split(",")
		if sh.size() == 2:
			var fmsh := main.get_node_or_null("World/FloorManager")
			var mst := main.get_node_or_null("World/MapSizeTool")
			var eh := main.get_node_or_null("World/EdgeHighlight")
			var camsh := main.get_node_or_null("Camera2D")
			if fmsh and mst and eh:
				fmsh.set_mode(1) # Mode.CELL -> single-cell grain
				mst.active = false # stop _process from clearing/overwriting our explicit highlight each frame
				if OS.get_environment("GQ_SIZEHOVER_NOFIT") != "1" and camsh and camsh.has_method("fit_map"):
					camsh.fit_map()
				await get_tree().process_frame
				eh.show_cell(Vector2i(int(sh[0]), int(sh[1])), "add")
				await get_tree().process_frame

	var pos := OS.get_environment("GQ_POS")
	if pos != "":
		var parts := pos.split(",")
		if parts.size() == 2:
			var player := main.get_node_or_null("World/Player")
			if player:
				var p := Vector2(float(parts[0]), float(parts[1]))
				player.position = p
				player.target_position = p
				player.is_moving = false

	# GQ_FLOOR="x,y,style" sets a room's floor (the right-click menu can't fire headlessly)
	var floor := OS.get_environment("GQ_FLOOR")
	if floor != "":
		var fp := floor.split(",")
		if fp.size() == 3:
			var fm := main.get_node_or_null("World/FloorManager")
			if fm:
				fm.set_room_style(Vector2i(int(fp[0]), int(fp[1])), fp[2])

	# GQ_BANK="0" turns the river-bank switch OFF before any liquid is painted below, so GQ_WATER /
	# GQ_TERRAIN lay water/lava with no brown bank (default is on).
	if OS.get_environment("GQ_BANK") == "0":
		var fmbk := main.get_node_or_null("World/FloorManager")
		if fmbk:
			fmbk.set_bank_on(false)

	# GQ_WATER="x,y;x,y;..." paints FULL-CELL water at each listed cell (all four quarters), then
	# rebuilds, so the derived river-bank auto-edge can be seen (a brown walkable ring around the water).
	# Frames the whole map unless GQ_WATER_NOFIT=1. e.g. GQ_WATER="20,10;21,10;22,10" draws a short river.
	var water := OS.get_environment("GQ_WATER")
	if water != "":
		var fmwa := main.get_node_or_null("World/FloorManager")
		if fmwa:
			for op in water.split(";", false):
				var wc := op.split(",")
				if wc.size() == 2:
					var c := Vector2i(int(wc[0]), int(wc[1]))
					for dx in 2:
						for dy in 2:
							fmwa.write_quad(Vector2i(c.x * 2 + dx, c.y * 2 + dy), "water")
			fmwa.rebuild()
			await get_tree().process_frame
			if OS.get_environment("GQ_WATER_NOFIT") != "1":
				var camwa := main.get_node_or_null("Camera2D")
				if camwa and camwa.has_method("fit_map"):
					camwa.fit_map()

	# GQ_TERRAIN="x,y,material;..." paints FULL-CELL of any floor material at each cell, then rebuilds,
	# so the generalised auto-matching edges can be seen (e.g. sand feathering into grass, snow over
	# sand). Material is the literal name ("grass" is now a real patternable material; use "base" for the
	# bare "" ground). e.g. GQ_TERRAIN="20,10,sand;21,10,grass". Pair with GQ_PATTERN to set a variant.
	# Frames the whole map unless GQ_TERRAIN_NOFIT=1. Runs after GQ_WATER so the two can be combined.
	var terrain := OS.get_environment("GQ_TERRAIN")
	if terrain != "":
		var fmt := main.get_node_or_null("World/FloorManager")
		if fmt:
			for op in terrain.split(";", false):
				var tc := op.split(",")
				if tc.size() == 3:
					var c := Vector2i(int(tc[0]), int(tc[1]))
					var mat: String = "" if tc[2] == "base" else tc[2]
					for dx in 2:
						for dy in 2:
							fmt.write_quad(Vector2i(c.x * 2 + dx, c.y * 2 + dy), mat)
			fmt.rebuild()
			await get_tree().process_frame
			if OS.get_environment("GQ_TERRAIN_NOFIT") != "1":
				var camt := main.get_node_or_null("Camera2D")
				if camt and camt.has_method("fit_map"):
					camt.fit_map()

	# GQ_BRUSH="mat" arms a floor material through the real panel path (arm_floor_material) so the
	# persistent Brush panel's preview swatch reflects it. "grass" = the empty grass material.
	# GQ_SECTION="Brush" expands one tool-strip accordion section, so its panel can be eyeballed
	# (the strip's accordion is exclusive, so only the named one stays open).
	var sect := OS.get_environment("GQ_SECTION")
	if sect != "":
		var tsn := get_tree().get_first_node_in_group("tool_strip")
		if tsn and tsn.has_method("_set_section"):
			tsn._set_section(sect, true)
			await get_tree().process_frame

	var brush_env := OS.get_environment("GQ_BRUSH")
	if brush_env != "":
		var fmb := main.get_node_or_null("World/FloorManager")
		if fmb:
			fmb.arm_floor_material("" if brush_env == "grass" else brush_env) # grass is the empty material
			await get_tree().process_frame

	# GQ_TINT="x,y,rrggbb;..." tints a floor cell (the Floor Colours menu can't fire headlessly), so
	# the colour system and the "a floor selection reads lit + un-washed" fix can be seen. Pair with
	# GQ_FLOOR to lay a material first, e.g. GQ_FLOOR="8,9,wood" GQ_TINT="8,9,cc3322".
	var tint := OS.get_environment("GQ_TINT")
	if tint != "":
		var fmt := main.get_node_or_null("World/FloorManager")
		if fmt:
			for op in tint.split(";", false):
				var f := op.split(",")
				if f.size() == 3:
					fmt.tint_cell(Vector2i(int(f[0]), int(f[1])), Color.html(f[2]))
			fmt.rebuild()
			await get_tree().process_frame

	# GQ_GRID="1" turns the reference grid on (normally toggled via the right-click menu)
	if OS.get_environment("GQ_GRID") == "1":
		var fmg := main.get_node_or_null("World/FloorManager")
		if fmg:
			fmg.set_grid(true)

	# GQ_EDGEBAND="edge:mode" previews the Map Size tool's band (edge top/bottom/left/right,
	# mode add/remove) and frames the whole map, so the tool-strip highlight can be seen headlessly.
	var band := OS.get_environment("GQ_EDGEBAND")
	if band != "":
		var bp := band.split(":")
		if bp.size() == 2:
			var eh := main.get_node_or_null("World/EdgeHighlight")
			if eh:
				eh.show_band(bp[0], bp[1])
			var cam := main.get_node_or_null("Camera2D")
			if cam and cam.has_method("fit_map"):
				cam.fit_map()

	# GQ_WAND="x,y" (optionally "x,y;x,y;..." for repeat clicks that grow the selection) drives the
	# Magic Wand headlessly so the marching-ants selection overlay can be verified. Sets WAND mode,
	# clicks each world-pixel point in order, then frames the whole map. Pair with GQ_FLOOR to lay a
	# patch first (e.g. GQ_FLOOR="8,9,wood" GQ_WAND="272,304").
	var wand := OS.get_environment("GQ_WAND")
	if wand != "":
		var fmw := main.get_node_or_null("World/FloorManager")
		if fmw:
			fmw.set_mode(0) # Mode.WAND
			for pt in wand.split(";", false):
				var wp := pt.split(",")
				if wp.size() == 2:
					fmw.selection.wand_click(Vector2(float(wp[0]), float(wp[1])))
			print("GQ_WAND kind=", EditorState.sel_kind, " quads=", EditorState.sel_quads.size(),
				" cells=", EditorState.sel_cells.size(), " level=", EditorState.sel_level,
				" overlay=", fmw.selection.overlay.has_selection())
			# frame the whole map by default; GQ_WAND_NOFIT=1 keeps the GQ_POS-centred view instead
			if OS.get_environment("GQ_WAND_NOFIT") != "1":
				var camw := main.get_node_or_null("Camera2D")
				if camw and camw.has_method("fit_map"):
					camw.fit_map()

	# GQ_PREVIEW="x,y,material" shows the lifted terrain drop-preview over a cell in Cell mode. Arms
	# the brush and warps the OS mouse over the cell so the real hover path (_update_hover) shows the
	# floating tile + contact shadow, exactly as a live session would. See ROADMAP "Terrain placement
	# UX". Warp rather than calling _show_preview directly, because set_mode defers an _update_hover
	# that would otherwise clobber a direct call from the off-cell headless mouse.
	var preview := OS.get_environment("GQ_PREVIEW")
	if preview != "":
		var pp := preview.split(",")
		if pp.size() == 3:
			var fmp := main.get_node_or_null("World/FloorManager")
			var camp := main.get_node_or_null("Camera2D")
			if fmp and camp:
				fmp.set_mode(1) # Mode.CELL
				EditorState.brush = pp[2]
				await get_tree().process_frame # let the camera settle onto the player first
				var wc := Vector2(int(pp[0]) * 32 + 16, int(pp[1]) * 32 + 16)
				var screen: Vector2 = (wc - camp.global_position) * camp.zoom \
					+ get_viewport().get_visible_rect().size / 2.0
				Input.warp_mouse(screen)

	# GQ_STRUCT drives the Wall/Door placement tools headlessly (the tool strip can't click here):
	# "wall:x,y;door:x,y;..." places a wall or door on each cell in order, through the real
	# _place_wall_at/_place_door_at paths (mode set + world-pixel click), so lighting/shadow rebuilds
	# are exercised. A door auto-orients to its wall run. Frames the whole map unless GQ_STRUCT_NOFIT=1.
	var struct := OS.get_environment("GQ_STRUCT")
	if struct != "":
		var fms := main.get_node_or_null("World/FloorManager")
		if fms:
			for op in struct.split(";", false):
				var sp := op.split(":")
				if sp.size() == 2:
					var xy := sp[1].split(",")
					if xy.size() == 2:
						var wc := Vector2(int(xy[0]) * 32 + 16, int(xy[1]) * 32 + 16)
						if sp[0] == "wall":
							fms.set_mode(4) # Mode.WALL
							fms.place_wall_at(wc)
						elif sp[0] == "door":
							fms.set_mode(5) # Mode.DOOR
							fms.place_door_at(wc)
			await get_tree().process_frame
			if OS.get_environment("GQ_STRUCT_NOFIT") != "1":
				var cams := main.get_node_or_null("Camera2D")
				if cams and cams.has_method("fit_map"):
					cams.fit_map()

	# GQ_WALLHOVER="x,y[,material[,rrggbb]]" shows the WALL-mode placement GHOST over cell x,y (the real
	# shape a click would place, from the surrounding walls), optionally in a material/colour, so the
	# hover-drop preview can be verified. Pair with GQ_STRUCT to build the neighbouring walls first, e.g.
	# GQ_STRUCT="wall:20,19;wall:19,20" GQ_WALLHOVER="20,20,brick,cc3322". Frames whole map unless _NOFIT=1.
	var wallhover := OS.get_environment("GQ_WALLHOVER")
	if wallhover != "":
		var fmwh := main.get_node_or_null("World/FloorManager")
		var camwh := main.get_node_or_null("Camera2D")
		if fmwh and camwh:
			var p := wallhover.split(",")
			if p.size() >= 2:
				var cell := Vector2i(int(p[0]), int(p[1]))
				fmwh.set_mode(4) # Mode.WALL
				if p.size() >= 3 and p[2] != "":
					fmwh.arm_wall_material(p[2])
				if p.size() >= 4 and p[3] != "":
					fmwh.arm_wall_color(Color.html(p[3]))
				if OS.get_environment("GQ_WALLHOVER_NOFIT") != "1" and camwh.has_method("fit_map"):
					camwh.fit_map()
				await get_tree().process_frame
				# freeze the per-frame hover (as if the cursor left the window) so it can't clobber this
				# explicit ghost with the real mouse position, then show the ghost for the requested cell
				fmwh._mouse_inside = false
				fmwh._update_structure_placement_hover(cell)
				await get_tree().process_frame

	# GQ_DOORHOVER="x,y" shows the DOOR-mode placement GHOST over cell x,y (the closed door auto-oriented
	# to the wall run it would bridge), so the door hover-drop can be verified. Pair with GQ_STRUCT to
	# build the surrounding walls first. Frames whole map unless GQ_DOORHOVER_NOFIT=1.
	var doorhover := OS.get_environment("GQ_DOORHOVER")
	if doorhover != "":
		var fmdh := main.get_node_or_null("World/FloorManager")
		var camdh := main.get_node_or_null("Camera2D")
		if fmdh and camdh:
			var dp := doorhover.split(",")
			if dp.size() >= 2:
				var cell := Vector2i(int(dp[0]), int(dp[1]))
				fmdh.set_mode(5) # Mode.DOOR
				if OS.get_environment("GQ_DOORHOVER_NOFIT") != "1" and camdh.has_method("fit_map"):
					camdh.fit_map()
				await get_tree().process_frame
				# freeze the per-frame hover (as if the cursor left the window) so it can't clobber this
				# explicit ghost with the real mouse position, then show the ghost for the requested cell
				fmdh._mouse_inside = false
				fmdh._update_structure_placement_hover(cell)
				await get_tree().process_frame

	# GQ_BRIDGE="x,y;x,y;..." drops a crossable bridge on each cell via the real _place_bridge_at path
	# (mode set + world-pixel click), so the deck render + water auto-orient can be verified. Pair with
	# GQ_WATER to lay a river first, e.g. GQ_WATER="20,10;20,11;20,12" GQ_BRIDGE="20,11". Frames the
	# whole map unless GQ_BRIDGE_NOFIT=1.
	var bridge := OS.get_environment("GQ_BRIDGE")
	if bridge != "":
		var fmb2 := main.get_node_or_null("World/FloorManager")
		if fmb2:
			fmb2.set_mode(8) # Mode.BRIDGE
			for op in bridge.split(";", false):
				var bp := op.split(",")
				if bp.size() == 2:
					fmb2.place_bridge_at(Vector2(int(bp[0]) * 32 + 16, int(bp[1]) * 32 + 16))
			await get_tree().process_frame
			if OS.get_environment("GQ_BRIDGE_NOFIT") != "1":
				var camb := main.get_node_or_null("Camera2D")
				if camb and camb.has_method("fit_map"):
					camb.fit_map()

	# GQ_BRIDGEHOVER="x,y" sets BRIDGE mode and shows the lifted deck HOVER preview over that cell (the
	# floating bridge image the tool shows before clicking), oriented to the water run there. Pair with
	# GQ_WATER to lay a river first. Calls _update_bridge_hover directly after the set_mode deferred
	# hover settles, so the preview is present at grab time. Frames whole map unless GQ_BRIDGE_NOFIT=1.
	var bhover := OS.get_environment("GQ_BRIDGEHOVER")
	if bhover != "":
		var fmh2 := main.get_node_or_null("World/FloorManager")
		var camh := main.get_node_or_null("Camera2D")
		if fmh2 and camh:
			var hp := bhover.split(",")
			if hp.size() == 2:
				fmh2.set_mode(8) # Mode.BRIDGE
				if OS.get_environment("GQ_BRIDGE_NOFIT") != "1" and camh.has_method("fit_map"):
					camh.fit_map()
				await get_tree().process_frame # let the camera settle before mapping world->screen
				# warp the OS mouse over the cell so _process's per-frame _update_hover shows the deck
				# preview there (a direct call would be clobbered next frame by the real-mouse hover)
				var wc := Vector2(int(hp[0]) * 32 + 16, int(hp[1]) * 32 + 16)
				var screen: Vector2 = (wc - camh.global_position) * camh.zoom \
					+ get_viewport().get_visible_rect().size / 2.0
				Input.warp_mouse(screen)

	# GQ_DOORSTATE="x,y,open,swing;..." sets a door's AUTHORED open/swing (0/1) via the same obstacles
	# edit methods the properties inspector uses, so persistence + EDIT-mode rendering can be verified.
	var dstate := OS.get_environment("GQ_DOORSTATE")
	if dstate != "":
		var obsd := main.get_node_or_null("World/Obstacles")
		if obsd:
			for op in dstate.split(";", false):
				var f := op.split(",")
				if f.size() == 4:
					var dc := Vector2i(int(f[0]), int(f[1]))
					obsd.set_door_open(dc, f[2] == "1")
					obsd.set_door_swing(dc, f[3] == "1")

	# GQ_SELECT="x,y" drives the Select tool at a cell so the properties inspector shows that object
	# (door or wall), for verifying the inspector headlessly (the tool strip can't be clicked here).
	var sel := OS.get_environment("GQ_SELECT")
	if sel != "":
		var sp := sel.split(",")
		if sp.size() == 2:
			var fmsel := main.get_node_or_null("World/FloorManager")
			if fmsel:
				fmsel.set_mode(6) # Mode.SELECT
				fmsel.select_at(Vector2(int(sp[0]) * 32 + 16, int(sp[1]) * 32 + 16))

	# GQ_PATTERN="x,y,idx;..." sets a floor cell's pattern index (0=default) via the same grain helper
	# the Pattern menu uses, so the pattern variants can be verified headlessly. Pair with GQ_FLOOR/
	# GQ_TERRAIN to lay a material first (grass is now patternable too: 1=Wild, 2=Tuft), e.g.
	# GQ_TERRAIN="8,9,grass" GQ_PATTERN="8,9,1".
	var fpat := OS.get_environment("GQ_PATTERN")
	if fpat != "":
		var fmpt := main.get_node_or_null("World/FloorManager")
		if fmpt:
			for op in fpat.split(";", false):
				var f := op.split(",")
				if f.size() == 3:
					fmpt.pattern_cell(Vector2i(int(f[0]), int(f[1])), int(f[2]))
			fmpt.rebuild()
			await get_tree().process_frame

	# GQ_WALLMAT="x,y,material;..." sets a wall cell's material (stone/wood/slate) via the same
	# obstacles method the right-click menu + inspector use, so the material textures can be verified
	# headlessly. Pair with GQ_POS to frame the wall.
	var wmat := OS.get_environment("GQ_WALLMAT")
	if wmat != "":
		var obsm := main.get_node_or_null("World/Obstacles")
		if obsm:
			for op in wmat.split(";", false):
				var f := op.split(",")
				if f.size() == 3:
					obsm.set_wall_material(Vector2i(int(f[0]), int(f[1])), f[2])
			await get_tree().process_frame

	# GQ_CLIP="sx,sy,w,h:px,py[:r[:drop]]" exercises copy/paste: box-select the CELL rectangle
	# (sx,sy,w,h), copy it to the clipboard, arm it as a paste, and put the cursor where the block's
	# top-left lands on cell (px,py) -- optionally rotated `r` quarter-turns clockwise first -- so the
	# PASTE GHOST renders through the real hover path. Add ":drop" as a 4th field to stamp it for real
	# instead of only previewing. e.g. GQ_CLIP="7,8,4,4:20,16:1" ghosts a 4x4 block rotated once.
	# Frames the whole map unless GQ_CLIP_NOFIT=1.
	var clipenv := OS.get_environment("GQ_CLIP")
	if clipenv != "":
		var parts := clipenv.split(":", false)
		var fmc := main.get_node_or_null("World/FloorManager")
		if fmc and parts.size() >= 2:
			var r := parts[0].split(",")
			var at := parts[1].split(",")
			var turns := int(parts[2]) if parts.size() > 2 else 0
			var drop := parts.size() > 3 and parts[3] == "drop"
			var cells := {}
			for cy in range(int(r[3])):
				for cx in range(int(r[2])):
					cells[Vector2i(int(r[0]) + cx, int(r[1]) + cy)] = true
			fmc.selection.select_cells(cells)
			fmc.copy_selection()
			var cl: Dictionary = MapClipboard.clip()
			for _t in turns:
				cl = MapClipboard.rotate_cw(cl)
			var origin := Vector2i(int(at[0]), int(at[1]))
			var camc := main.get_node_or_null("Camera2D")
			if OS.get_environment("GQ_CLIP_NOFIT") != "1" and camc and camc.has_method("fit_map"):
				camc.fit_map()
				await get_tree().process_frame
			if drop:
				MapEdit.stamp_clip(cl, origin)
				await get_tree().process_frame
			else:
				# the ghost normally follows the CURSOR (a paste centres the block on it); a capture run
				# cannot place the OS cursor, so pin the origin and let the real hover path draw it
				fmc.ghost_origin_pin = origin
				fmc.arm_paste(cl)
				await get_tree().process_frame
				await get_tree().process_frame
			print("GQ_CLIP cells=", cells.size(), " box=", cl.get("w", 0), "x", cl.get("h", 0),
				" origin=", origin, " drop=", drop, " ghost_origin=", fmc._pending_origin())
			await get_tree().process_frame

	# GQ_SPAWN="x,y" moves the authored player spawn to cell (x,y) through the real Set Spawn tool, so
	# the marker's art can be eyeballed where you want it. The marker only draws in EDIT (it is editor
	# chrome), so do not pair this with GQ_PLAY. Frames the whole map unless GQ_SPAWN_NOFIT=1.
	var spawnenv := OS.get_environment("GQ_SPAWN")
	if spawnenv != "":
		var sp2 := spawnenv.split(",")
		var fmsp := main.get_node_or_null("World/FloorManager")
		if fmsp and sp2.size() == 2:
			var scell := Vector2i(int(sp2[0]), int(sp2[1]))
			fmsp.set_mode(11) # Mode.SPAWN
			print("GQ_SPAWN set=", fmsp.set_spawn_at(Vector2(scell.x * 32 + 16, scell.y * 32 + 16)),
				" cell=", scell)
			var camsp := main.get_node_or_null("Camera2D")
			if OS.get_environment("GQ_SPAWN_NOFIT") != "1" and camsp and camsp.has_method("fit_map"):
				camsp.fit_map()
			await get_tree().process_frame

	# GQ_ITEMS="x,y,item;..." places item pickups through the real Item tool, so the rarity outlines
	# and item glyphs can be eyeballed (e.g. GQ_ITEMS="20,12,coin;21,12,gem;22,12,key"). Frames the
	# whole map unless GQ_ITEMS_NOFIT=1.
	var itemsenv := OS.get_environment("GQ_ITEMS")
	if itemsenv != "":
		var fmit := main.get_node_or_null("World/FloorManager")
		if fmit:
			fmit.set_mode(12) # Mode.ITEM
			for op in itemsenv.split(";", false):
				var f := op.split(",")
				if f.size() == 3:
					fmit.arm_item(f[2])
					fmit.place_item_at(Vector2(int(f[0]) * 32 + 16, int(f[1]) * 32 + 16))
			await get_tree().process_frame
			var camit := main.get_node_or_null("Camera2D")
			if OS.get_environment("GQ_ITEMS_NOFIT") != "1" and camit and camit.has_method("fit_map"):
				camit.fit_map()
			await get_tree().process_frame

	# GQ_CREATURES="x,y,creature[,kind];..." places creatures through the real Creature tool, so the
	# procedural bodies, the rarity rings and the spawn-point marker ring can be eyeballed. `kind` is
	# "spawn" (default) or "instance", e.g. GQ_CREATURES="20,12,frost_frog;22,12,fire_horse,instance".
	# Frames the whole map unless GQ_CREATURES_NOFIT=1.
	var crenv := OS.get_environment("GQ_CREATURES")
	if crenv != "":
		var fmcr := main.get_node_or_null("World/FloorManager")
		if fmcr:
			fmcr.set_mode(13) # Mode.CREATURE
			for op in crenv.split(";", false):
				var f := op.split(",")
				if f.size() >= 3:
					fmcr.arm_creature(f[2])
					fmcr.arm_creature_kind(f[3] if f.size() > 3 else Bestiary.SPAWN_POINT)
					fmcr.place_creature_at(Vector2(int(f[0]) * 32 + 16, int(f[1]) * 32 + 16))
			await get_tree().process_frame
			var camcr := main.get_node_or_null("Camera2D")
			if OS.get_environment("GQ_CREATURES_NOFIT") != "1" and camcr and camcr.has_method("fit_map"):
				camcr.fit_map()
			await get_tree().process_frame

	# GQ_ZONES="x,y,w,h,creature;..." drags out spawn zones through the real Creature tool, so the
	# zone overlay (wash, dashed border, label) can be eyeballed, e.g. GQ_ZONES="18,18,8,6,frost_frog".
	# Pair with GQ_PLAY=1 to watch them fill. Frames the whole map unless GQ_ZONES_NOFIT=1.
	var zoneenv := OS.get_environment("GQ_ZONES")
	if zoneenv != "":
		var fmz := main.get_node_or_null("World/FloorManager")
		if fmz:
			fmz.set_mode(13) # Mode.CREATURE
			fmz.arm_creature_kind(Bestiary.ZONE)
			for op in zoneenv.split(";", false):
				var f := op.split(",")
				if f.size() >= 5:
					fmz.arm_creature(f[4])
					fmz._zone_active = true
					fmz._zone_start = Vector2i(int(f[0]), int(f[1]))
					fmz._zone_active = false
					fmz.commit_zone(Vector2i(int(f[0]) + int(f[2]) - 1, int(f[1]) + int(f[3]) - 1))
			await get_tree().process_frame
			var camz := main.get_node_or_null("Camera2D")
			if OS.get_environment("GQ_ZONES_NOFIT") != "1" and camz and camz.has_method("fit_map"):
				camz.fit_map()
			await get_tree().process_frame

	# GQ_LOCK="x,y,kind[,colour];..." authors a door's lock so the lock art can be eyeballed:
	# kind is "colour" (with a LOCK_COLORS name) or "unique" (metal, and it stays on an OPEN door).
	# e.g. GQ_LOCK="8,11,colour,red;10,5,unique". Pair with GQ_DOORSTATE to see an open unique lock.
	var lockenv := OS.get_environment("GQ_LOCK")
	if lockenv != "":
		var obsl := main.get_node_or_null("World/Obstacles")
		if obsl:
			for op in lockenv.split(";", false):
				var f := op.split(",")
				if f.size() >= 3:
					obsl.set_door_lock(Vector2i(int(f[0]), int(f[1])), f[2],
						f[3] if f.size() > 3 else "red", "Malcolm's Door Key")
			await get_tree().process_frame

	# GQ_SAVE="name" writes the current level to user://maps/name.json (after the setup above)
	var save_name := OS.get_environment("GQ_SAVE")
	if save_name != "":
		MapIO.save_map(save_name)
		print("GQ_SAVE wrote: ", JSON.stringify(MapIO.serialize()))

	# GQ_PLAY=1 switches to PLAY mode (the game default is EDIT now, see EditorMode): the player
	# moves and doors react to proximity, and the editor UI hides. Editor-visual shots leave it unset.
	# GQ_HOLD implies PLAY, since a frozen EDIT-mode player can't walk.
	var hold := OS.get_environment("GQ_HOLD")
	if OS.get_environment("GQ_PLAY") == "1" or hold != "":
		EditorMode.set_mode(EditorMode.Mode.PLAY)
		await get_tree().process_frame # let consumers react (camera follow, gate logic, UI hide)

	# GQ_HOLD presses a movement action (e.g. "ui_down") so the player actually walks,
	# which is needed to reproduce transitions that only happen while moving.
	if hold != "":
		Input.action_press(hold)

	# let movement settle, the camera catch up, and gates react before the grab.
	# GQ_DELAY overrides the settle time (e.g. a few ms to catch a transition frame).
	var delay := float(OS.get_environment("GQ_DELAY"))
	if delay <= 0.0:
		delay = 0.8
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw

	var out := OS.get_environment("GQ_OUT")
	if out == "":
		out = "res://_shot.png"
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
