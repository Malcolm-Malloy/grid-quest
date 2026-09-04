extends Node

# Dev-only headless test for the tool-strip ACCORDION (ROADMAP "Editor UX revisions" -> accordion left
# menu + Map Size -> Advanced). Checks the strip builds two collapsible sections ("Tools" expanded,
# "Advanced" collapsed), that the Map Size edge controls live inside the collapsed Advanced section, and
# that toggling a section header shows/hides its content, and that the body is wrapped in a ScrollContainer
# so a growing tool/material roster scrolls instead of overflowing the window. Counts tie to the strip's
# own constants so adding a mode does not break this. Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_tool_strip.tscn

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

func _ready() -> void:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var ts = get_tree().get_first_node_in_group("tool_strip")
	_check("tool strip exists (grouped)", ts != null)

	# FOUR tools, not one button per mode (merged 2026-09-05): Select / Paint / Place / Move. The modes
	# still exist underneath -- a tool switches between them -- but the sub-choice moved into the panel
	# (Paint's grain switch, Place's kind row), and Erase / Eyedropper keep no button by design.
	_check("the strip shows exactly four tools", ts._tool_buttons.size() == 4)
	_check("Select / Paint / Place / Move are the four",
		ts._tool_buttons.has(ts.T_SELECT) and ts._tool_buttons.has(ts.T_PAINT)
		and ts._tool_buttons.has(ts.T_PLACE) and ts._tool_buttons.has(ts.T_MOVE))
	_check("Paint carries the grain switch (the old Fine Details tool)", ts._fine_check != null)
	_check("Place carries the whole placeable roster", ts._place_buttons.size() == ts.PLACE_KINDS.size())

	# each tool resolves to a real FloorManager mode, and the sub-choices steer it
	var fmts = main.get_node("World/FloorManager")
	ts._apply_tool(ts.T_PAINT)
	_check("Paint means Cell mode by default", fmts.mode() == ts.M_CELL)
	ts._fine_check.button_pressed = true
	ts._apply_tool(ts.T_PAINT)
	_check("Paint with Fine on means Fine mode", fmts.mode() == ts.M_FINE)
	ts._fine_check.set_pressed_no_signal(false)
	ts._on_place_kind(1) # Door
	_check("picking a Place kind selects the Place tool", ts._current_tool() == ts.T_PLACE)
	_check("...and switches to that kind's mode", fmts.mode() == ts.M_DOOR)
	ts._apply_tool(ts.T_SELECT)
	_check("Select means Wand mode (click grows, drag boxes)", fmts.mode() == ts.M_WAND)

	# EVERY pre-merge shortcut still works, which is the point of the merge: fewer buttons, same muscle
	# memory. Each entry names the tool it now picks and the sub-choice it sets.
	for sc in ts.SHORTCUTS:
		var ev := InputEventKey.new()
		ev.keycode = sc[0]
		ev.pressed = true
		ts._unhandled_key_input(ev)
	_check("all 13 legacy shortcuts are still mapped", ts.SHORTCUTS.size() == 13)
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_F
	ev2.pressed = true
	ts._unhandled_key_input(ev2)
	_check("F still means fine-grain paint", fmts.mode() == ts.M_FINE and ts._current_tool() == ts.T_PAINT)
	ev2.keycode = KEY_G
	ts._unhandled_key_input(ev2)
	_check("G still means place a bridge", fmts.mode() == ts.M_BRIDGE and ts._current_tool() == ts.T_PLACE)
	ev2.keycode = KEY_W
	ts._unhandled_key_input(ev2)
	_check("W still means select", fmts.mode() == ts.M_WAND and ts._current_tool() == ts.T_SELECT)

	# the body is wrapped in a ScrollContainer so a growing roster scrolls instead of overflowing the
	# window; horizontal scroll is off so the strip width still hugs the widest button.
	_check("panel body scrolls (ScrollContainer present)", ts._scroll is ScrollContainer)
	_check("horizontal scroll disabled (width hugs content)",
		ts._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)

	# two accordion sections
	_check("'Tools' section exists", ts._sections.has("Tools"))
	_check("'Advanced' section exists", ts._sections.has("Advanced"))

	var tools = ts._sections["Tools"]
	var adv = ts._sections["Advanced"]
	_check("Tools starts expanded (content visible)", tools["content"].visible)
	_check("Advanced starts collapsed (content hidden)", not adv["content"].visible)

	# the accordion is EXCLUSIVE (2026-09-05): opening one section folds the rest, so the strip stays
	# one screen of controls. Exactly one section is open at any time (or none, if you fold that one).
	var open_now := 0
	for t in ts._sections:
		if ts._sections[t]["content"].visible:
			open_now += 1
	_check("exactly one section is open at startup", open_now == 1)
	ts._set_section("Brush", true)
	_check("opening Brush opened it", ts._sections["Brush"]["content"].visible)
	_check("...and folded Tools", not tools["content"].visible)
	var still_open := 0
	for t in ts._sections:
		if ts._sections[t]["content"].visible:
			still_open += 1
	_check("still exactly one open after switching", still_open == 1)
	ts._set_section("Brush", false)
	var none_open := 0
	for t in ts._sections:
		if ts._sections[t]["content"].visible:
			none_open += 1
	_check("folding the open one leaves them all shut", none_open == 0)
	ts._set_section("Tools", true) # restore for the checks below

	# the mode buttons live under Tools, not loose in the panel
	_check("tool buttons are children of the Tools content", ts._tool_buttons[ts.T_SELECT].get_parent() == tools["content"])

	# the Map Size edge controls live under the (collapsed) Advanced section: it has the Map Size label
	# plus the hover toggle and 4 edge rows
	var has_mapsize := false
	for c in adv["content"].get_children():
		if c is Label and c.text == "Map Size":
			has_mapsize = true
	_check("Advanced holds the 'Map Size' controls", has_mapsize)

	# toggling the Advanced header expands/collapses its content
	adv["header"].toggled.emit(true)
	_check("expanding Advanced shows its content", adv["content"].visible)
	_check("header arrow flips to open (▾)", adv["header"].text.begins_with("▾"))
	adv["header"].toggled.emit(false)
	_check("collapsing Advanced hides its content again", not adv["content"].visible)

	# --- Level dropdown: lists saved maps and reflects the current one ---
	var m1 := "zz_tooltest_a"
	var m2 := "zz_tooltest_b"
	MapIO.save_map(m1)
	MapIO.save_map(m2) # current() is now m2
	ts._refresh_levels()
	var texts := []
	for i in ts._level_dd.item_count:
		texts.append(ts._level_dd.get_item_text(i))
	_check("Level dropdown lists saved map A", m1 in texts)
	_check("Level dropdown lists saved map B", m2 in texts)
	_check("Level dropdown selects the current map", ts._level_dd.get_item_text(ts._level_dd.selected) == MapIO.current())
	MapIO.delete_map(m1)
	MapIO.delete_map(m2)

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
