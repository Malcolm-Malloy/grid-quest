extends Node

# WINDOWED
# Dev-only WINDOWED probe (GUI hover only works with a real renderer, not --headless) for the
# "editing stands down over the menu" guard. Injects a mouse-motion over the tool strip panel and over
# open map, and prints what get_viewport().gui_get_hovered_control() returns in each case, so we can be
# sure the guard blocks the menu but NOT the map.
#   /Applications/Godot.app/Contents/MacOS/Godot --path . res://dev/test_ui_guard.tscn

func _ready() -> void:
	MapIO.auto_load = false
	CharacterIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var strip := main.get_node_or_null("ToolStrip")
	var panel: Control = null
	if strip:
		for c in strip.get_children():
			if c is Control:
				panel = c
				break

	var over_panel := Vector2(20, 200) # inside the left tool strip (panel is at ~(8,8))
	if panel:
		over_panel = panel.get_global_rect().get_center()
	var over_map := get_viewport().get_visible_rect().size * Vector2(0.75, 0.5) # right-centre, off the panel

	print("PANEL rect: ", panel.get_global_rect() if panel else "no panel")

	_hover_at(over_panel)
	await get_tree().process_frame
	var h1 := get_viewport().gui_get_hovered_control()
	print("HOVER over panel -> ", h1, " (expect NON-null)")

	_hover_at(over_map)
	await get_tree().process_frame
	var h2 := get_viewport().gui_get_hovered_control()
	print("HOVER over map -> ", h2, " (expect null)")

	var ok := h1 != null and h2 == null
	print("RESULT: %s" % ("OK" if ok else "FAILURE"))
	get_tree().quit(0 if ok else 1)

func _hover_at(screen_pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen_pos
	ev.global_position = screen_pos
	get_viewport().push_input(ev)
