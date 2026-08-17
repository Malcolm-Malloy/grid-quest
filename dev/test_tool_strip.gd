extends Node

# Dev-only headless test for the tool-strip ACCORDION (ROADMAP "Editor UX revisions" -> accordion left
# menu + Map Size -> Advanced). Checks the strip builds two collapsible sections ("Tools" expanded,
# "Advanced" collapsed), that the Map Size edge controls live inside the collapsed Advanced section, and
# that toggling a section header shows/hides its content. Also that all seven mode buttons still exist.
# Text-only, no render.
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

	# 7 mode buttons on the strip; only ERASE (3) is omitted (it lives in the right-click menu + Delete
	# key). Wall/Door stay on the strip AS WELL as the menu because their drag-to-draw-a-line gesture
	# needs a reachable mode. All 8 modes keep a keyboard shortcut (MODES intact).
	_check("7 mode buttons on the strip (only Erase omitted)", ts._mode_buttons.size() == 7)
	_check("Erase has no strip button", not ts._mode_buttons.has(3))
	_check("Wall/Door/Select/Box have strip buttons", ts._mode_buttons.has(4) and ts._mode_buttons.has(5) and ts._mode_buttons.has(6) and ts._mode_buttons.has(7))
	_check("all 8 modes keep a keyboard shortcut (MODES intact)", ts.MODES.size() == 8)

	# two accordion sections
	_check("'Tools' section exists", ts._sections.has("Tools"))
	_check("'Advanced' section exists", ts._sections.has("Advanced"))

	var tools = ts._sections["Tools"]
	var adv = ts._sections["Advanced"]
	_check("Tools starts expanded (content visible)", tools["content"].visible)
	_check("Advanced starts collapsed (content hidden)", not adv["content"].visible)

	# the mode buttons live under Tools, not loose in the panel
	_check("mode buttons are children of the Tools content", ts._mode_buttons[0].get_parent() == tools["content"])

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
