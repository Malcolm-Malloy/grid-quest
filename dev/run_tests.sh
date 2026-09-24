#!/usr/bin/env bash
# Run every headless dev/test_*.tscn and report which failed. Exit status = number of failing suites.
#   dev/run_tests.sh              # all suites
#   dev/run_tests.sh undo erase   # only test_undo + test_erase
# A suite fails on a non-zero exit, any FAIL line, a SCRIPT ERROR, or a missing RESULT: OK line.
# Suites whose script has a "# WINDOWED" line need a real renderer and are skipped here.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TIMEOUT="${TIMEOUT:-60}" # seconds per suite
cd "$(dirname "$0")/.." || exit 99

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
