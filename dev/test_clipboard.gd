extends "res://dev/test_case.gd"

# Dev-only headless test for copy / paste / duplicate / move (ROADMAP "Copy, paste, and duplicate",
# "Move tool"). Covers the clip format (MapClipboard.build_clip), the stamp transforms
# (MapEdit.stamp_clip / move_clip), edge clipping, the rotate/flip orientation remap, undo, the
# cross-map + on-disk clipboard, and FloorManager's selection -> clipboard path. Text-only.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://dev/test_clipboard.tscn

func _cells(list: Array) -> Dictionary:
	var out := {}
	for c in list:
		out[c] = true
	return out

func _has_wall(obs, c: Vector2i) -> bool:
	return obs.is_blocked(c)

func _door(obs, c: Vector2i) -> Dictionary:
	return obs.door_at(c)

# lay a known little scene: a 3-cell wall run with a door in it, and a wood floor cell below its left end
func _setup(fm) -> void:
	var d := {
		"version": 10,
		"grid": {"width": 16, "height": 10},
		"absent_cells": [],
		"walls": [[2, 2], [3, 2]],
		"doors": [{"cell": [4, 2], "orientation": "horizontal", "open": true, "swing": true}],
		"bridges": [],
		"quads": [[4, 6, "wood"], [5, 6, "wood"], [4, 7, "wood"], [5, 7, "wood"]], # the 4 quarters of cell (2,3)
		"wall_colors": [], "wall_materials": [[2, 2, "wood"]],
		"floor_tints": [], "floor_patterns": [], "floor_no_bank": [],
	}
	MapIO.apply_serialized(d, true)
	await get_tree().process_frame

func _ready() -> void:
	var main: Node = await boot_main()
	var obs = main.get_node("World/Obstacles")
	var fm = main.get_node("World/FloorManager")
	await _setup(fm)
	EditHistory.reset()

	var src := _cells([Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3)])
	var clip := MapClipboard.build_clip(MapIO.serialize(), src)

	# --- 1. the clip captures every layer, rebased to its bounding box ---
	_check("clip bounding box is 3x2", int(clip["w"]) == 3 and int(clip["h"]) == 2)
	_check("clip took both walls", clip["walls"].size() == 2)
	_check("clip took the door", clip["doors"].size() == 1)
	_check("clip rebased the door to (2,0)", clip["doors"][0]["cell"] == [2, 0])
	_check("clip took the wall material row", clip["wall_materials"].size() == 1)
	_check("clip took the 4 wood quarters", clip["quads"].size() == 4)
	_check("clip rebased quarters to the origin", clip["quads"][0][0] == 0 and clip["quads"][0][1] == 2)

	# --- 2. paste: the block lands intact somewhere else, the source is untouched ---
	var stamped := MapEdit.stamp_clip(clip, Vector2i(9, 5))
	await get_tree().process_frame
	_check("paste stamped 4 cells", stamped.size() == 4)
	_check("paste: walls landed", _has_wall(obs, Vector2i(9, 5)) and _has_wall(obs, Vector2i(10, 5)))
	_check("paste: door landed with its authored state", _door(obs, Vector2i(11, 5)).get("open", false) == true)
	_check("paste: floor landed", fm.floor_tex_at_quad(Vector2i(18, 12)) != null)
	_check("paste: source still there", _has_wall(obs, Vector2i(2, 2)) and not _door(obs, Vector2i(4, 2)).is_empty())

	# --- 3. undo puts the map back (one entry for the whole paste) ---
	EditHistory.undo()
	await get_tree().process_frame
	_check("undo removed the pasted walls", not _has_wall(obs, Vector2i(9, 5)))
	_check("undo kept the source", _has_wall(obs, Vector2i(2, 2)))
	EditHistory.redo()
	await get_tree().process_frame
	_check("redo re-stamped the paste", _has_wall(obs, Vector2i(9, 5)))
	EditHistory.undo()
	await get_tree().process_frame

	# --- 4. paste OVERWRITES within its footprint (no half-merge) ---
	MapEdit.stamp_clip(clip, Vector2i(2, 6)) # lands on empty ground
	await get_tree().process_frame
	var blank := {"w": 1, "h": 1, "cells": [[0, 0]], "walls": [], "wall_colors": [], "wall_materials": [],
		"doors": [], "bridges": [], "quads": [], "floor_tints": [], "floor_patterns": [], "floor_no_bank": []}
	MapEdit.stamp_clip(blank, Vector2i(2, 6))
	await get_tree().process_frame
	_check("paste overwrites: an empty clip cleared the cell it covered", not _has_wall(obs, Vector2i(2, 6)))
	_check("paste overwrites: cells outside the footprint survive", _has_wall(obs, Vector2i(3, 6)))

	# --- 5. clipping at the map edge: only the in-bounds part lands ---
	var clipped := MapEdit.stamp_clip(clip, Vector2i(14, 5)) # 3 wide starting at x=14 on a 16-wide map
	await get_tree().process_frame
	_check("edge paste clipped to the in-bounds cells", clipped.size() == 3)
	_check("edge paste: the in-bounds wall landed", _has_wall(obs, Vector2i(14, 5)))
	_check("edge paste: nothing landed off the map", _door(obs, Vector2i(16, 5)).is_empty())
	var nowhere := MapEdit.stamp_clip(clip, Vector2i(40, 40))
	_check("a wholly off-map paste does nothing (and commits nothing)", nowhere.is_empty())

	# --- 6. rotate / flip remap coordinates AND orientation ---
	var rot := MapClipboard.rotate_cw(clip)
	_check("rotate swaps the bounding box (3x2 -> 2x3)", int(rot["w"]) == 2 and int(rot["h"]) == 3)
	_check("rotate turns the horizontal door vertical", rot["doors"][0]["orientation"] == "vertical")
	_check("rotate maps door (2,0) -> (1,2)", rot["doors"][0]["cell"] == [1, 2])
	_check("rotate keeps a horizontal door's swing side (north -> east)", rot["doors"][0]["swing"] == true)
	var back := MapClipboard.rotate_cw(MapClipboard.rotate_cw(MapClipboard.rotate_cw(rot)))
	_check("four rotations return the original box", int(back["w"]) == 3 and int(back["h"]) == 2)
	_check("four rotations return the original door cell", back["doors"][0]["cell"] == [2, 0])
	_check("four rotations return the original orientation", back["doors"][0]["orientation"] == "horizontal")
	var fh := MapClipboard.flip_h(clip)
	_check("flip_h mirrors the door across the box", fh["doors"][0]["cell"] == [0, 0])
	_check("flip_h leaves a horizontal door's swing alone", fh["doors"][0]["swing"] == true)
	var fv := MapClipboard.flip_v(clip)
	_check("flip_v inverts a horizontal door's swing side", fv["doors"][0]["swing"] == false)
	MapEdit.stamp_clip(rot, Vector2i(6, 6))
	await get_tree().process_frame
	# rotating (x,y) -> (h-1-y, x) puts the run in the box's right column, so it lands one cell east
	_check("a rotated paste lands as a vertical run", _has_wall(obs, Vector2i(7, 6)) and _has_wall(obs, Vector2i(7, 7)))
	_check("the rotated door is vertical on the map", _door(obs, Vector2i(7, 8)).get("orientation", "") == "vertical")

	# --- 7. move: the region leaves its source and arrives whole, in ONE undo entry ---
	await _setup(fm)
	EditHistory.reset()
	var moved := MapEdit.move_clip(src, MapClipboard.build_clip(MapIO.serialize(), src), Vector2i(8, 6))
	await get_tree().process_frame
	_check("move stamped 4 cells", moved.size() == 4)
	_check("move: the source wall is gone", not _has_wall(obs, Vector2i(2, 2)))
	_check("move: the source door is gone", _door(obs, Vector2i(4, 2)).is_empty())
	_check("move: the wall arrived", _has_wall(obs, Vector2i(8, 6)))
	_check("move: the door arrived with its authored state (identity kept, not re-placed)",
		_door(obs, Vector2i(10, 6)).get("open", false) == true and _door(obs, Vector2i(10, 6)).get("swing", false) == true)
	_check("move: the floor came along", fm.floor_tex_at_quad(Vector2i(16, 14)) != null)
	EditHistory.undo()
	await get_tree().process_frame
	_check("one undo reverses the whole move", _has_wall(obs, Vector2i(2, 2)) and not _has_wall(obs, Vector2i(8, 6)))

	# --- 8. the clipboard: cross-map + on-disk ---
	MapClipboard.set_clip(clip)
	_check("clipboard holds the clip", MapClipboard.has_clip() and MapClipboard.clip_cell_count() == 4)
	_check("clipboard mirrored to disk", FileAccess.file_exists(MapClipboard.FILE))
	var reread = JSON.parse_string(FileAccess.open(MapClipboard.FILE, FileAccess.READ).get_as_text())
	_check("the on-disk clip round-trips", reread is Dictionary and reread["cells"].size() == 4)
	var handed := MapClipboard.clip()
	handed["cells"].clear() # editing what clip() returned must not reach the stored clipboard
	_check("clip() hands out a copy, not the stored clip", MapClipboard.clip_cell_count() == 4)

	# --- 9. FloorManager: a selection is what gets copied ---
	fm._select_cells(src)
	_check("selection -> footprint cells", fm._selection_cells().size() == 4)
	MapClipboard.clear()
	_check("Ctrl+C with a selection fills the clipboard", fm._copy_selection() and MapClipboard.has_clip())
	fm._clear_selection()
	_check("Ctrl+C with no selection copies nothing", not fm._copy_selection())
	fm._arm_paste(MapClipboard.clip())
	_check("Ctrl+V arms a paste", fm._pending_kind == "paste" and not fm._pending_clip.is_empty())
	var id_before: int = fm._pending_id
	fm._transform_pending(MapClipboard.rotate_cw(fm._pending_clip))
	_check("R rotates the armed clip (and bumps the ghost id)", int(fm._pending_clip["w"]) == 2 and fm._pending_id > id_before)
	fm._cancel_pending()
	_check("Esc / right-click drops the armed paste", fm._pending_clip.is_empty() and fm._pending_kind == "")
	_check("a stampable cell reads in-bounds, an off-map one does not",
		fm._in_bounds(Vector2i(3, 3)) and not fm._in_bounds(Vector2i(99, 3)))

	# --- 10. the FloorManager gestures end to end: a drag-move, then a paste click ---
	await _setup(fm)
	EditHistory.reset()
	fm._select_cells(src)
	fm._begin_move(Vector2i(2, 2)) # grab the run's left end
	_check("MOVE press inside the selection arms a move", fm._pending_kind == "move" and fm._move_src.size() == 4)
	fm._ghost_origin_pin = Vector2i(5, 6) # stands in for the cursor (see _pending_origin)
	fm._drop_pending()
	await get_tree().process_frame
	_check("the move drag landed the region", _has_wall(obs, Vector2i(5, 6)) and not _has_wall(obs, Vector2i(2, 2)))
	_check("the moved region stays selected (so it can be moved again)", fm._selection_cells().has(Vector2i(5, 6)))
	_check("the gesture cleared itself", fm._pending_clip.is_empty() and fm._move_src.is_empty())
	EditHistory.undo()
	await get_tree().process_frame
	_check("one undo reverses the whole drag-move", _has_wall(obs, Vector2i(2, 2)) and not _has_wall(obs, Vector2i(5, 6)))

	fm._select_cells(src)
	fm._copy_selection()
	fm._arm_paste(MapClipboard.clip())
	fm._ghost_origin_pin = Vector2i(6, 6)
	fm._drop_pending()
	await get_tree().process_frame
	_check("a paste click stamps at the ghost", _has_wall(obs, Vector2i(6, 6)) and _has_wall(obs, Vector2i(7, 6)))
	_check("the paste left the source alone", _has_wall(obs, Vector2i(2, 2)))
	_check("the pasted region becomes the selection", fm._selection_cells().size() == 4)
	fm._ghost_origin_pin = fm.INVALID_CELL

	# --- spawn zones through copy / rotate / paste (pure data, no world) ---
	var zd := {"creature_zones": [
		{"rect": [2, 2, 3, 1], "creature": "frost_frog", "rate": 7.5, "cap": 5, "id": "zin"},
		{"rect": [4, 3, 3, 3], "creature": "frost_frog", "rate": 4.0, "cap": 3, "id": "zpart"}]}
	var zcells := {}
	for x in range(1, 6):
		for y in range(1, 5):
			zcells[Vector2i(x, y)] = true
	var zclip := MapClipboard.build_clip(zd, zcells)
	var zs: Array = zclip["creature_zones"]
	_check("copy takes a zone fully inside the footprint, not one poking out",
		zs.size() == 1 and zs[0]["id"] == "zin" and zs[0]["rate"] == 7.5)
	_check("the copied zone is rebased to the clip origin", zs.size() == 1 and zs[0]["rect"] == [1, 1, 3, 1])
	var zrot := MapClipboard.rotate_cw(zclip)
	_check("rotate turns a wide zone tall, about the box", zrot["creature_zones"][0]["rect"] == [2, 1, 1, 3])
	var zmap := {"grid": {"width": 20, "height": 20}}
	MapEdit._apply_clip(zmap, zclip, Vector2i(10, 10), true)
	_check("a pasted zone lands at the origin with a fresh id",
		zmap["creature_zones"][0]["rect"] == [11, 11, 3, 1] and zmap["creature_zones"][0]["id"] != "zin")
	var zmap2 := {"grid": {"width": 20, "height": 20}}
	MapEdit._apply_clip(zmap2, zclip, Vector2i(18, 0), false)
	_check("a moved zone keeps its id and clips at the map edge",
		zmap2["creature_zones"][0]["id"] == "zin" and zmap2["creature_zones"][0]["rect"] == [19, 1, 1, 1])
	finish()
