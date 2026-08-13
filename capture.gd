extends Node

# Dev-only screenshot harness. Runs the real game (main.tscn), optionally drops the
# player on a given cell/pixel, waits for it to settle, grabs one frame, saves it,
# and quits. main.tscn is never touched, so normal play is unaffected: this only
# runs when you launch capture.tscn on purpose, e.g.
#
#   GQ_POS="272,368" GQ_OUT="res://_shot.png" \
#     /Applications/Godot.app/Contents/MacOS/Godot --path . res://capture.tscn
#
# GQ_POS is the player position in world pixels ("x,y"); omit it to use the normal
# spawn. GQ_OUT is where the PNG lands; defaults to res://_shot.png.

func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
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
