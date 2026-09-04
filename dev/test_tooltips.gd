extends Node

# Dev-only headless test for the TOOLTIP sweep (ROADMAP "Tooltips on menu and tool options"). The
# point of that entry is not that tooltips exist -- it is that they read their shortcut from the SAME
# hotkey map the binding uses, "so tooltip and binding never drift". So this test mostly checks the
# no-drift property: every shortcut the strip dispatches has a Hotkeys entry, and the visible labels
# and tooltips are composed from it rather than spelling the key out a second time.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_tooltips.tscn

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
	EditorMode.set_mode(EditorMode.Mode.EDIT)

	# --- the table itself ---
	var incomplete := []
	for a in Hotkeys.KEYS:
		if Hotkeys.key(a) == "" or Hotkeys.what(a) == "":
			incomplete.append(a)
	_check("every entry has a key and a description", incomplete.is_empty())
	_check("a tooltip states what it does AND its shortcut",
		"Undo" in Hotkeys.tip("undo") and "Ctrl+Z" in Hotkeys.tip("undo"))
	_check("extra context is included when given", "a red one" in Hotkeys.tip("erase", "a red one"))
	_check("an unknown action still yields the extra rather than an empty box",
		Hotkeys.tip("no_such_action", "still useful") == "still useful")
	_check("labelled() appends the key", Hotkeys.labelled("Select", "select") == "Select (S)")
	_check("...and leaves an unbound label alone", Hotkeys.labelled("Thing", "nope") == "Thing")

	# --- NO DRIFT: the strip's own dispatch table and the tooltip table must agree ---
	# every tool the strip shows names a Hotkeys action, and the key that action reports is a key the
	# strip actually dispatches for it. This is the check that fails if someone moves a binding.
	for t in ts.TOOLS:
		_check("tool '%s' names a hotkey action" % t[0], Hotkeys.has(t[2]))
		var want: String = Hotkeys.key(t[2])
		var dispatched := false
		for sc in ts.SHORTCUTS:
			if OS.get_keycode_string(sc[0]) == want and sc[1] == t[1]:
				dispatched = true
		_check("...and %s really selects it" % want, dispatched)
	for pk in ts.PLACE_KINDS:
		_check("place kind '%s' names a hotkey action" % pk[0], Hotkeys.has(pk[3]))
		_check("...whose key matches the one it dispatches" ,
			Hotkeys.key(pk[3]) == OS.get_keycode_string(pk[2]))

	# --- the labels and tooltips are actually composed from it ---
	var sel_btn: Button = ts._tool_buttons[ts.T_SELECT]
	_check("a tool button's LABEL carries its key", sel_btn.text == "Select (S)")
	_check("...and its tooltip does too", "Shortcut: S" in sel_btn.tooltip_text)
	_check("...and says what the tool does", Hotkeys.what("select") in sel_btn.tooltip_text)
	_check("the Place kinds are tipped", "Shortcut: D" in ts._place_buttons[1].tooltip_text)
	_check("the grain switch is tipped", "Shortcut: F" in ts._fine_check.tooltip_text)

	# the Play/Edit toggle, which lives outside the strip
	var mt = main.get_node("ModeToggle")
	_check("the Play/Edit toggle is labelled with its key", "(Tab)" in mt._button.text)
	_check("...and tipped from the same table", "Shortcut: Tab" in mt._button.tooltip_text)

	# right-click menu entries, which the spec names explicitly alongside the strip
	var fm = main.get_node("World/FloorManager")
	fm._apply_menu_context(Vector2i(20, 20))
	var erase_idx: int = fm._menu.get_item_index(fm.ERASE_ID)
	_check("the right-click Erase entry is tipped", "Shortcut: E" in fm._menu.get_item_tooltip(erase_idx))

	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
