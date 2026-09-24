extends "res://dev/test_case.gd"

# Dev-only headless test for WHOLE-GAME SAVES (ROADMAP Phase B item 9), the last piece of Phase B.
# Covers the bundle (map name + a copy of the character), the refusals, the load order that puts the
# character back where they were rather than on the map's authored spawn, and the three-file split
# staying separate. Text-only, no render.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_game_io.tscn

func _ready() -> void:
	var main: Node = await boot_main()
	var player = main.get_node("World/Player")
	GameIO.delete_game()
	EditorMode.set_mode(EditorMode.Mode.EDIT)

	_check("no saved game to begin with", not GameIO.has_save())
	_check("saved_map is empty with no save", GameIO.saved_map() == "")

	# --- an UNNAMED map cannot be saved into a game: a game save points at a map on disk ---
	MapIO.new_map()
	_check("saving a game in an unnamed map is refused", not GameIO.save_game())

	# --- the bundle: the map's NAME plus a COPY of the character ---
	var map_name := "zz_game_test"
	MapIO.save_map(map_name)
	player.position = Vector2(21 * 32 + 16, 13 * 32 + 16)
	player.facing = "left"
	CharacterIO.mark_collected(map_name, "abc123")
	_check("saving a game in a named map works", GameIO.save_game())
	_check("...and there is now a save", GameIO.has_save())
	_check("...pointing at the map by NAME", GameIO.saved_map() == map_name)
	var raw: Dictionary = GameIO.read()
	_check("...carrying a copy of the character, not a pointer to the file", raw.has("character"))
	_check("...with the character's position", int(raw["character"]["position"]["x"]) == 21 * 32 + 16)
	_check("...their facing", String(raw["character"]["facing"]) == "left")
	_check("...and what they had collected", raw["character"]["collected"].has(map_name))
	_check("...stamped with a time", int(raw["at"]) > 0)

	# the map itself is NOT copied into the save: it is authored content that outlives a playthrough
	_check("the map is referenced, not copied", not raw.has("walls") and not raw.has("quads"))

	# --- the saved copy is frozen: it must not change when the live character does ---
	player.position = Vector2(5 * 32 + 16, 5 * 32 + 16)
	CharacterIO.save_character()
	_check("changing the live character does not change the saved game",
		int(GameIO.read()["character"]["position"]["x"]) == 21 * 32 + 16)

	# --- loading puts the character BACK, not on the map's authored spawn ---
	MapIO.new_map()
	_check("setup: a new map moved the player off", int(player.position.x) != 21 * 32 + 16)
	_check("loading the game works", GameIO.load_game())
	_check("...it loaded the map the save named", MapIO.current() == map_name)
	_check("...and put the character back where they were", int(player.position.x) == 21 * 32 + 16)
	_check("...facing as they were", player.facing == "left")
	_check("...remembering what they had collected", CharacterIO.is_collected(map_name, "abc123"))

	# --- a save whose map has been deleted cannot be loaded, and says so rather than half-loading ---
	MapIO.delete_map(map_name)
	_check("the map is gone", not MapIO.has_map(map_name))
	_check("loading a game whose map is gone is refused", not GameIO.load_game())
	_check("...and the save is still there to be seen", GameIO.has_save())

	GameIO.delete_game()
	_check("deleting the save clears it", not GameIO.has_save())
	_check("...and loading then does nothing", not GameIO.load_game())

	CharacterIO.clear_collected()
	finish()
