#!/usr/bin/env python3
"""Compile-check the native geometry files that have local stub support.

This is intentionally separate from the full godot-cpp build: it catches C++
syntax/type regressions in the knitting/touch path even on a machine without
the Android SDK or a downloaded godot-cpp checkout.
"""
import pathlib
import shutil
import subprocess
import sys

# Everything except `register_types.cpp`, which needs the real gdextension
# headers and has nothing in it to get wrong.
#
# It used to be three files. The stub could only check syntax then, so there
# was little point pointing it at more; now that `native/stub` carries a
# working Variant it type-checks the lot, and the first run of the widened
# list found a `size_t` against `int` in `ivory_warp.cpp` that would have
# stopped the build outright on a 32-bit toolchain.
# Every C++ source in the extension, found rather than listed.
#
# This used to be a hand-written list, and it had fallen eight files behind:
# `ivory_character360.cpp`, `ivory_character360_rig.cpp` and `ivory_text_tool.cpp`
# were once absent from it. The checker now walks every remaining source.
#
# A list you have to remember to update is a list that goes stale. This walks
# the directory instead, so a file added tomorrow is checked tomorrow.
# `register_types.cpp` is the one exception. It includes
# <gdextension_interface.h>, which only exists in a real godot-cpp checkout,
# so it cannot be compiled against the small stub in native/stub. Its content
# is checked instead by tools/check_registration.py, which reads the file and
# asserts that every class with a header is registered.
SKIP = {"register_types.cpp"}

def sources(root):
    src = root / "native" / "ivory" / "src"
    if not src.is_dir():
        return []
    return sorted(
        str(p.relative_to(root))
        for p in src.glob("*.cpp")
        if p.name not in SKIP
    )

def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    compiler = shutil.which("g++") or shutil.which("clang++")
    if compiler is None:
        print("--- native compile checker skipped: no C++ compiler ---")
        return 0

    failed = 0
    for rel in sources(root):
        path = root / rel
        if not path.exists():
            print(f"ERROR: missing native source {rel}")
            failed += 1
            continue
        cmd = [
            compiler, "-std=c++17", "-Wall", "-Wextra", "-Wpedantic",
            "-fsyntax-only", "-Inative/stub", "-Inative/ivory/src", str(path)
        ]
        result = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
        if result.returncode != 0:
            failed += 1
            print(f"FAIL: {rel}")
            print(result.stderr.rstrip())
        else:
            print(f"ok    {rel}")
    print(f"--- {failed} native compile errors ---")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
