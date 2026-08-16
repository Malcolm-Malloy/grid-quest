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
	# tests drive loading explicitly via GQ_LOAD, so auto-reload is off unless GQ_AUTOLOAD=1
	MapIO.auto_load = OS.get_environment("GQ_AUTOLOAD") == "1"
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

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

	# GQ_HOVER="x,y" previews the floor-hover highlight on a room (mouse motion can't fire
	# headlessly). Set after GQ_FLOOR so both can be tested together.
	var hover := OS.get_environment("GQ_HOVER")
	if hover != "":
		var hp := hover.split(",")
		if hp.size() == 2:
			var fmh := main.get_node_or_null("World/FloorManager")
			if fmh:
				fmh._set_hover(Vector2i(int(hp[0]), int(hp[1])))

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
					fmw._wand_click(Vector2(float(wp[0]), float(wp[1])))
			print("GQ_WAND kind=", fmw._sel_kind, " quads=", fmw._sel_quads.size(),
				" cells=", fmw._sel_cells.size(), " level=", fmw._sel_level,
				" overlay=", fmw._selection.has_selection())
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
				fmp._brush = pp[2]
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
							fms._place_wall_at(wc)
						elif sp[0] == "door":
							fms.set_mode(5) # Mode.DOOR
							fms._place_door_at(wc)
			await get_tree().process_frame
			if OS.get_environment("GQ_STRUCT_NOFIT") != "1":
				var cams := main.get_node_or_null("Camera2D")
				if cams and cams.has_method("fit_map"):
					cams.fit_map()

	# GQ_SAVE="name" writes the current level to user://maps/name.json (after the setup above)
	var save_name := OS.get_environment("GQ_SAVE")
	if save_name != "":
		MapIO.save_map(save_name)
		print("GQ_SAVE wrote: ", JSON.stringify(MapIO.serialize()))

	# GQ_HOLD presses a movement action (e.g. "ui_down") so the player actually walks,
	# which is needed to reproduce transitions that only happen while moving.
	var hold := OS.get_environment("GQ_HOLD")
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
