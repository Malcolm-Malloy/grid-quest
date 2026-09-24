#!/usr/bin/env bash
# Run every headless dev/test_*.tscn and report which failed. Exit status = number of failing suites.
#   dev/run_tests.sh              # all suites
#   dev/run_tests.sh undo erase   # only test_undo + test_erase
# A suite fails on a non-zero exit, any FAIL line, a SCRIPT ERROR, or a missing RESULT: OK line.
# Suites whose script has a "# WINDOWED" line need a real renderer and are skipped here.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TIMEOUT="${TIMEOUT:-60}" # seconds per suite
cd "$(dirname "$0")/.." || exit 99
# Suites save and load real maps, characters, games and the clipboard under user://, which is the SAME
# folder the editor and game use. Snapshot it and put it back afterwards (even on Ctrl-C), so a test run
# never clobbers your maps, your last-opened map, the clipboard or a recovery slot.
PROJECT_NAME=$(sed -n 's/^config\/name="\(.*\)"$/\1/p' project.godot)
USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/$PROJECT_NAME"
USER_BACKUP=$(mktemp -d)
[ -d "$USER_DIR" ] && rsync -a "$USER_DIR/" "$USER_BACKUP/"
restore_user_data() {
	[ -d "$USER_DIR" ] && rsync -a --delete --exclude logs --exclude shader_cache --exclude objectdb_snapshots \
		"$USER_BACKUP/" "$USER_DIR/"
	rm -rf "$USER_BACKUP"
}
trap restore_user_data EXIT
trap 'exit 130' INT TERM

# refresh the global class cache first, so a newly added class_name resolves in the suites
"$GODOT" --headless --path . --import >/dev/null 2>&1

if [ $# -gt 0 ]; then
	scenes=(); for n in "$@"; do scenes+=("dev/test_$n.tscn"); done
else
	scenes=(dev/test_*.tscn)
fi

failed=0; ran=0; skipped=0
for t in "${scenes[@]}"; do
	if grep -q '^# WINDOWED' "${t%.tscn}.gd" 2>/dev/null; then
		skipped=$((skipped + 1)); continue
	fi
	ran=$((ran + 1))
	# run under a watchdog: a script error stops a test before it quits, which would otherwise hang
	log=$(mktemp)
	"$GODOT" --headless --path . "res://$t" >"$log" 2>&1 &
	pid=$!
	for _ in $(seq $((TIMEOUT * 10))); do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
	if kill -0 $pid 2>/dev/null; then
		kill $pid; wait $pid 2>/dev/null; code=124; echo "TIMEOUT after ${TIMEOUT}s" >>"$log"
	else
		wait $pid; code=$?
	fi
	out=$(cat "$log"); rm -f "$log"
	if [ $code -ne 0 ] || echo "$out" | grep -q -e '^FAIL' -e 'SCRIPT ERROR' || ! echo "$out" | grep -q '^RESULT: OK'; then
		failed=$((failed + 1))
		echo "FAIL $t (exit $code)"
		echo "$out" | grep -e '^FAIL' -e 'SCRIPT ERROR' -e 'ERROR:' -e 'TIMEOUT' -A1 | head -8 | sed 's/^/    /'
	else
		echo "ok   $t ($(echo "$out" | grep -c '^PASS') checks)"
	fi
done
echo "---- $((ran - failed))/$ran suites passed, $skipped windowed skipped"
exit $failed
