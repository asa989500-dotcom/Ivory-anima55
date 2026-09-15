#!/usr/bin/env bash
# Check, test, build. In that order, and it stops at the first failure.
#
# There is no way to run some of this and ship on the rest, which is the whole
# point: every check in here exists because a specific mistake reached a user,
# and the ones that get skipped are the ones that stop working.
#
#   bash tools/build.sh            checks and tests only
#   bash tools/build.sh --apk      and exports a debug APK
#   bash tools/build.sh --release  and exports a signed release APK
#
# GODOT can be set to the binary to use; it defaults to `godot`.

set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

echo "== code inspector"
python3 tools/code_inspector.py . --json build/code_inspector_report.json

echo "== static checks"
python3 tools/check_all.py .

# The native half. Nineteen C++ test files, and before stage 152 not one of
# them had ever run — the stub they build against would not compile them, so
# they sat in the repository proving nothing while five real compile errors sat
# in the sources they covered. They run here, at -O2, in about ten seconds.
echo
echo "== native tests"
python3 tools/run_native_tests.py

echo
echo "== tests"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "   !! no Godot on the path, so nothing was actually run."
	echo "      Set GODOT=/path/to/godot. The static checks above passed,"
	echo "      and they are the half that cannot catch a logic error."
	exit 1
fi

# The first pass registers every `class_name` in the project. Without it a
# fresh clone has no global class table and every test fails on a name it
# should know.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script tests/run_tests.gd

if [ "${1:-}" = "--apk" ]; then
	echo
	echo "== debug APK"
	mkdir -p build
	"$GODOT" --headless --path . --export-debug "Android" build/IVORY-debug.apk
	echo "   build/IVORY-debug.apk"
elif [ "${1:-}" = "--release" ]; then
	echo
	echo "== release APK"
	mkdir -p build
	"$GODOT" --headless --path . --export-release "Android" build/IVORY.apk
	echo "   build/IVORY.apk"
fi

echo
echo "done."
