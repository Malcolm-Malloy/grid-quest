extends Node

# EditHistory (autoload): editor undo/redo for every authoring edit.
#
# THE FOUNDATION (ROADMAP "Undo / redo"). Built early and on purpose so every tool records
# its own history at the moment it writes, rather than history being retrofitted after many
# tools exist. A tool's whole job is: mutate the live map, then call EditHistory.commit().
# That single call is the only integration point a new tool ever needs.
#
# MECHANISM: snapshot-based, riding the MapIO.serialize() / apply_serialized() rebuild path
# that already re-applies a full map dict onto the live level (the same path load and resize
# use, so it is proven to reconstruct everything derived: walls, doors, floors, lighting,
# shadows, wall colours). We keep a `_baseline` snapshot of the current committed state; a
# commit pushes the pre-action baseline onto the undo stack and adopts the new state as the
# baseline. Undo/redo just swap the baseline for a neighbouring snapshot and re-apply it.
#
# WHY SNAPSHOTS, NOT MINIMAL DIFFS (ROADMAP prefers diffs for cheapness): the map serializes
# to a small sparse dict (only painted quarters / placed objects are stored, not whole-map
# grids), so a snapshot is a few KB, and CAP bounds the stack. This keeps the public API
# dead simple (one commit() call, no per-tool before/after bookkeeping). If snapshots ever
# get heavy, the internal representation can switch to diffs WITHOUT changing a single call
# site, because tools only ever see commit()/undo()/redo().
#
# GRANULARITY: one gesture is one entry. A drag-paint stroke commits once, on button release
# (FloorManager), not once per quarter; a menu paint or a resize commits once at its end.
#
# SCOPE: editor-only, in-memory. History does not persist across save/load; loading a map (or
# starting fresh) calls reset() to make that map the new baseline with an empty stack.
#
# V1 CAVEAT: a snapshot includes the player's position (serialize() stores it as spawn), so
# undo/redo also restores where the player stood at that step. Harmless in the editor; revisit
# if player position should be exempt from history.

const CAP := 200 # deep-but-capped (ROADMAP): keep a long trail, drop oldest past this.

signal changed(can_undo: bool, can_redo: bool)

var _undo: Array = []       # past states, oldest at front, newest at back
var _redo: Array = []       # undone states, most-recently-undone at back
var _baseline: Dictionary = {} # snapshot of the current live committed state
var _applying := false      # guard: don't let an undo/redo re-apply look like a new edit

func _ready() -> void:
	# Establish the baseline once the world (and any MapIO auto-load) has settled. If a map
	# auto-loaded, load_map() already called reset() and this guard leaves it alone; otherwise
	# we capture the default freshly-built world as the baseline.
	await get_tree().process_frame
	await get_tree().process_frame
	if _baseline.is_empty():
		reset()

# --- public API (the whole integration surface for tools) ---

# Record the just-performed edit as one undo step. Call AFTER mutating the live map.
# A no-op edit (state unchanged) is silently skipped so history stays meaningful.
func commit(_action: String = "") -> void:
	if _applying:
		return
	var after := MapIO.serialize()
	if _baseline.is_empty():
		_baseline = after # first commit before any reset: adopt as baseline, nothing to undo to
		return
	if after.hash() == _baseline.hash():
		return # nothing actually changed; don't push an empty step
	_undo.append(_baseline)
	if _undo.size() > CAP:
		_undo.pop_front() # bound memory: oldest step falls off
	_baseline = after
	_redo.clear() # a fresh edit invalidates the redo trail
	_emit()

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(_baseline)
	_baseline = _undo.pop_back()
	_reapply(_baseline)
	_emit()
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(_baseline)
	_baseline = _redo.pop_back()
	_reapply(_baseline)
	_emit()
	return true

# Make the current live map the baseline and clear all history. Call on load / new map.
func reset() -> void:
	_baseline = MapIO.serialize()
	_undo.clear()
	_redo.clear()
	_emit()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

# --- internals ---

func _reapply(snapshot: Dictionary) -> void:
	_applying = true
	MapIO.apply_serialized(snapshot, true) # keep_player: undo/redo never teleports the player
	_applying = false

func _emit() -> void:
	changed.emit(can_undo(), can_redo())

# --- keyboard: Ctrl/Cmd+Z undo, Ctrl/Cmd+Shift+Z or Ctrl/Cmd+Y redo ---

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var mod: bool = event.ctrl_pressed or event.meta_pressed
	if not mod:
		return
	match event.keycode:
		KEY_Z:
			if event.shift_pressed:
				redo()
			else:
				undo()
			get_viewport().set_input_as_handled()
		KEY_Y:
			redo()
			get_viewport().set_input_as_handled()
