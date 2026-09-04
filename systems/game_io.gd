extends Node

# Autoload singleton: a WHOLE-GAME save (ROADMAP Phase B item 9, "a whole-game save can bundle the
# character file + the current map name"). The final piece of Phase B.
#
# THE SPLIT IT COMPLETES. Three files, each owning one thing, so none of them can overwrite another's
# concerns:
#   user://maps/<name>.json  the authored MAP           (MapIO)        -- level design
#   user://character.json    the live CHARACTER          (CharacterIO)  -- position, inventory, what
#                                                                          it has collected/unlocked
#   user://game.json         a SAVED GAME               (here)         -- which map that character is
#                                                                          in, plus a copy of it
# A game save deliberately carries a COPY of the character rather than pointing at character.json:
# a save is a moment you can come back to, and one that changed under you every time the live
# character file was rewritten would not be a save at all.
#
# It references the map BY NAME, not by copying it. The map is authored content that outlives any
# playthrough -- editing a level should be reflected next time you load a game in it, exactly as a
# patched game world is. The consequence, which the UI states rather than hides: a game save is only
# as good as the saved map it names, so saving a game while the map has unsaved edits would reference
# something different from what you were playing. The menu makes you save the map first.

const VERSION := 1
const PATH := "user://game.json"

signal saved(map_name: String)
signal loaded(map_name: String)

func _player() -> Node:
	return get_tree().get_first_node_in_group("player")

# --- save ---

# Bundle the current map's NAME with a copy of the live character. Refused for an unnamed map: a game
# save is a pointer to a map on disk, and a never-saved map is not on disk to point at.
func save_game() -> bool:
	var map_name := MapIO.current()
	if map_name == "":
		return false
	var payload := {
		"version": VERSION,
		"map": map_name,
		"at": int(Time.get_unix_time_from_system()),
		"character": CharacterIO.serialize(),
	}
	if not _write(payload):
		return false
	saved.emit(map_name)
	return true

# --- load ---

# Put the player back: load the map this save names, then apply the character into it. Order matters
# -- the map load moves the player to the map's AUTHORED spawn, so applying the character afterwards
# is what puts them back where they actually were.
func load_game() -> bool:
	var data := read()
	if data.is_empty():
		return false
	var map_name := String(data.get("map", ""))
	if map_name == "" or not MapIO.has_map(map_name):
		return false # the map this save lived in is gone; nothing to come back to
	if not MapIO.load_map(map_name):
		return false
	CharacterIO.apply(data.get("character", {}))
	loaded.emit(map_name)
	return true

# --- the slot ---

func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var raw = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw

func has_save() -> bool:
	return not read().is_empty()

# what the save points at, for the menu's "Continue: <map>" label ("" when there is no save)
func saved_map() -> String:
	return String(read().get("map", ""))

func saved_at() -> int:
	return int(read().get("at", 0))

func delete_game() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)

# same atomic temp-then-rename every other writer here uses: a crash mid-write must not leave a
# half-written save that fails to parse when it is the thing you were relying on
func _write(payload: Dictionary) -> bool:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("GameIO: cannot open %s for writing" % tmp)
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	DirAccess.rename_absolute(tmp, PATH)
	return true
