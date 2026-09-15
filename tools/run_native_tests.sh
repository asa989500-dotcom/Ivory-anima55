#!/usr/bin/env bash
# Builds and runs every native test against the local stub.
#
# No godot-cpp, no Android SDK, no engine. A compiler and a second, which is
# the point: a check that is easy enough to run before every commit is a check
# that gets run.
set -u
cd "$(dirname "$0")/.."

CXX="${CXX:-g++}"
command -v "$CXX" >/dev/null 2>&1 || { echo "no C++ compiler; skipped"; exit 0; }

OUT="build/native_tests"
mkdir -p "$OUT"

# Each test, and the sources it needs beside it.
run() {
  local name="$1"; shift
  local srcs=""
  for s in "$@"; do srcs="$srcs native/ivory/src/$s.cpp"; done
  if ! $CXX -std=c++17 -Wall -Wextra -O2 -Inative/stub -Inative/ivory/src \
      -o "$OUT/$name" "native/ivory/tests/$name.cpp" $srcs 2>"$OUT/$name.log"; then
    echo "BUILD FAIL  $name"
    sed -n '1,20p' "$OUT/$name.log"
    return 1
  fi
  if "$OUT/$name" > "$OUT/$name.out" 2>&1; then
    echo "pass  $name  ($(grep -o '[0-9]* checks' "$OUT/$name.out" | tail -1))"
    return 0
  fi
  echo "FAIL  $name"
  cat "$OUT/$name.out"
  return 1
}

bad=0
run test_comic   ivory_comic                      || bad=1
run test_store   ivory_store                      || bad=1
run test_lang    ivory_lang ivory_layout          || bad=1
run test_brush   ivory_brush                      || bad=1
run test_blend   ivory_blend                      || bad=1
run test_pose    ivory_pose                       || bad=1
run test_arbiter ivory_arbiter                    || bad=1
run test_field   ivory_field                      || bad=1
run test_spline  ivory_spline                     || bad=1
run test_rig360  ivory_rig360                     || bad=1
run test_rigcore ivory_rigcore                     || bad=1
run test_rigcore_pole ivory_rigcore                 || bad=1
run test_animation ivory_animation                  || bad=1
run test_character360_ultra ivory_rig360 || bad=1
run test_smartbone ivory_smartbone               || bad=1
run test_skin    ivory_skin                      || bad=1
run test_mass_keeper ivory_mass_keeper                  || bad=1
run test_diagnostics ivory_diagnostics            || bad=1

echo
if [ "$bad" -eq 0 ]; then echo "--- all native tests passed ---"; else echo "--- native tests FAILED ---"; fi
exit "$bad"
