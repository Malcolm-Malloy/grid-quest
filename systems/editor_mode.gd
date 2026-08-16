extends Node

# Autoload singleton: the one global Play/Edit flag that separates authoring from gameplay.
#
#   EDIT (default, editor-first): the map is static so it can be authored. The player is frozen
#   (no movement input), doors hold their authored/spawned state instead of reacting to the player,
#   the camera is the free editor camera (pan/zoom), and the editor UI (tool strip, save/load) shows.
#
#   PLAY: the map comes alive. The player moves, doors open/close and swing from player proximity
#   (see player.update_gate_state), the camera follows the player, and the editor UI hides.
#
# Consumers read is_edit()/is_play() each frame where cheap, and react to `changed` for one-shot
# transitions (e.g. the player closing every door on entering EDIT). This is the foundation the
# door open/swing authoring builds on: authored door state is only meaningful once EDIT stops the
# proximity logic from overwriting it every frame.
enum Mode { EDIT, PLAY }

signal changed(mode: int)

var mode: int = Mode.EDIT

func is_edit() -> bool:
	return mode == Mode.EDIT

func is_play() -> bool:
	return mode == Mode.PLAY

func set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	changed.emit(mode)

func toggle() -> void:
	set_mode(Mode.PLAY if mode == Mode.EDIT else Mode.EDIT)
