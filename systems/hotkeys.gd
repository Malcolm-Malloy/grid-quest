extends Node

# Autoload singleton: the ONE table of editor shortcuts, and the tooltip text built from it.
#
# ROADMAP "Tooltips on menu and tool options" asks for tooltips that "also show the option's keyboard
# shortcut", read "from the same hotkey map ... so tooltip and binding never drift". That last clause
# is the whole reason this file exists: a tooltip that hardcodes "(W)" is a second copy of the
# binding, and the day a key moves, one of the two copies starts lying. Here, `tip()` composes the
# label from the same entry the UI is bound to, so a rebind updates every tooltip for free -- which is
# also what the future rebindable-hotkeys idea needs to be cheap.
#
# It does NOT dispatch input. The tools keep their own handlers (tool_strip's SHORTCUTS table,
# floor_manager's key handling); this is the table those describe themselves FROM. Making it the
# dispatcher too would be the right end state and a much bigger change than the tooltips warrant.

# action id -> {key: display string, what: what it does}. The `what` is the tooltip's first line, so
# every tooltip says what the thing does and not merely which key does it.
const KEYS := {
	# tools (the four merged tools plus the two that keep no button)
	"select": {"key": "S", "what": "Click to grow a selection, drag to box one, click a thing to inspect it"},
	"paint": {"key": "C", "what": "Lay the armed terrain"},
	"paint_fine": {"key": "F", "what": "Paint at quarter-cell grain instead of whole cells"},
	"place": {"key": "L", "what": "Drop the chosen thing"},
	"move": {"key": "V", "what": "Drag the current selection somewhere else"},
	"erase": {"key": "E", "what": "Remove the topmost thing on a cell"},
	"eyedrop": {"key": "I", "what": "Pick up the material and colour under the cursor"},
	# what Place drops
	"place_wall": {"key": "L", "what": "Drag to draw a wall"},
	"place_door": {"key": "D", "what": "Place a door; it orients itself to the wall run"},
	"place_bridge": {"key": "G", "what": "Deck over water so it can be crossed"},
	"place_item": {"key": "T", "what": "Place a pickup"},
	"place_creature": {"key": "A", "what": "Place a creature, or drag out a spawn zone"},
	"place_spawn": {"key": "P", "what": "Move where the player starts on this map"},
	# actions
	"undo": {"key": "Ctrl+Z", "what": "Undo the last edit"},
	"redo": {"key": "Ctrl+Y", "what": "Redo the last undone edit"},
	"copy": {"key": "Ctrl+C", "what": "Copy the selection"},
	"paste": {"key": "Ctrl+V", "what": "Paste; click to drop it"},
	"duplicate": {"key": "Ctrl+D", "what": "Copy the selection and arm it to drop"},
	"rotate": {"key": "R", "what": "Rotate what is armed"},
	"flip_h": {"key": "H", "what": "Flip what is armed horizontally"},
	"flip_v": {"key": "Shift+H", "what": "Flip what is armed vertically"},
	"cancel": {"key": "Esc", "what": "Clear the selection, or cancel what is armed"},
	"recenter": {"key": "Home", "what": "Recentre the view on the player"},
	"show_roofs": {"key": "O", "what": "Show the roofs while editing (they always show in play)"},
	"maps": {"key": "M", "what": "Open the Maps menu: save, load, new, and the saved game"},
	"play_toggle": {"key": "Tab", "what": "Switch between editing the map and playing it"},
	"fullscreen": {"key": "F11", "what": "Toggle fullscreen"},
}

func has(action: String) -> bool:
	return KEYS.has(action)

# the display key for `action` ("" if it has none), e.g. "Ctrl+Z"
func key(action: String) -> String:
	return String(KEYS.get(action, {}).get("key", ""))

func what(action: String) -> String:
	return String(KEYS.get(action, {}).get("what", ""))

# The tooltip for `action`: what it does, then its shortcut on its own line. `extra` appends a
# context line for a thing the table cannot know (a swatch's colour name, a creature's ability).
# An unknown action still yields a usable tooltip from `extra` alone rather than an empty box.
func tip(action: String, extra := "") -> String:
	var parts: Array = []
	var w := what(action)
	if w != "":
		parts.append(w)
	if extra != "":
		parts.append(extra)
	var k := key(action)
	if k != "":
		parts.append("Shortcut: " + k)
	return "\n".join(parts)

# a short label for a button that wants the key inline, e.g. "Select (S)"
func labelled(text: String, action: String) -> String:
	var k := key(action)
	return "%s (%s)" % [text, k] if k != "" else text
