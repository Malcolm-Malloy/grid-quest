extends Node

# Shared base for the dev/test_*.gd headless tests: the PASS/FAIL checker, the main-scene boot, and the
# RESULT line + exit code that dev/run_tests.sh reads. A test does `extends "res://dev/test_case.gd"`, boots the world with
# `var main := await boot_main()`, calls _check(...) and ends with finish().

var _fails := 0

func _check(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		_fails += 1

# instance main.tscn under this node with the saved-map autoload off, and let it settle one frame
func boot_main() -> Node:
	MapIO.auto_load = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	return main

# print the RESULT line and exit with the failure count (0 = pass)
func finish() -> void:
	print("RESULT: %s (%d failures)" % ["OK" if _fails == 0 else "FAILURES", _fails])
	get_tree().quit(_fails)
