#!/usr/bin/env python3
"""Builds and runs every native test, at -O2.

There were sixteen C++ test files in this project and not one of them had ever
run. They could not: the stub `PackedByteArray` had no initializer-list
constructor, so `PackedByteArray{1,2,3}` — which most of them use — did not
compile. Sixteen files of careful checks sat in the repository proving nothing,
and five genuine compile errors sat in the sources they were meant to cover.

That is what this script is for. It finds the tests, works out which sources
each one needs, builds them, runs them, and returns non-zero if any check
fails, so it can go in front of a build and mean something.

Optimisation matters more than it looks: `test_deform` runs 427 checks over a
real mesh and takes about a minute at -O0 and about a second at -O2. A suite
that takes a minute is a suite people stop running.

    python3 tools/run_native_tests.py           # build and run everything
    python3 tools/run_native_tests.py intake    # only tests matching 'intake'
"""

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# Both spellings appear in this tree: some tests write "../src/x.h" and some
# write "x.h" and rely on the include path. Matching only the first spelling
# left three tests linking against nothing, which showed up as a wall of
# undefined references rather than as anything to do with this script.
INCLUDE = re.compile(r'^\s*#include\s+"(?:\.\./src/)?([\w]+)\.h"', re.M)


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    tests_dir = root / "native" / "ivory" / "tests"
    src_dir = root / "native" / "ivory" / "src"
    stub = root / "native" / "stub"

    if not tests_dir.is_dir():
        print("--- native tests skipped: no test directory ---")
        return 0

    compiler = shutil.which("g++") or shutil.which("clang++")
    if compiler is None:
        print("--- native tests skipped: no C++ compiler ---")
        return 0

    wanted = sys.argv[1] if len(sys.argv) > 1 else ""
    tests = sorted(p for p in tests_dir.glob("test_*.cpp") if wanted in p.name)
    if not tests:
        print(f"no native tests match {wanted!r}")
        return 1

    total_checks = 0
    failed = 0
    broken = []

    print("")
    print("IVORY — native tests")
    print("")

    with tempfile.TemporaryDirectory() as tmp:
        out_dir = pathlib.Path(tmp)
        for test in tests:
            text = test.read_text(encoding="utf-8", errors="replace")
            # A test includes the headers it needs; the matching .cpp files are
            # what it has to be linked against. Working it out from the
            # includes means a new test needs no entry in any list here.
            needed = [src_dir / f"{stem}.cpp" for stem in INCLUDE.findall(text)]
            needed = [p for p in needed if p.exists()]

            binary = out_dir / test.stem
            build = subprocess.run(
                [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra",
                 f"-I{stub}", f"-I{src_dir}", str(test), *[str(p) for p in needed],
                 "-o", str(binary)],
                capture_output=True, text=True,
            )
            if build.returncode != 0:
                print(f"  BUILD FAIL  {test.name}")
                for line in build.stderr.strip().splitlines()[:12]:
                    print(f"              {line}")
                failed += 1
                broken.append(test.name)
                continue

            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=600)
            tail = run.stdout.strip().splitlines()
            summary = tail[-1] if tail else "(no output)"
            checks = 0
            hit = re.search(r"(\d+)\s+checks", summary)
            if hit:
                checks = int(hit.group(1))
            total_checks += checks

            if run.returncode == 0:
                print(f"  ok    {test.stem:<20} {checks:5d} checks")
            else:
                print(f"  FAIL  {test.stem:<20} {checks:5d} checks")
                for line in tail:
                    if line.startswith("FAIL"):
                        print(f"          {line}")
                        broken.append(f"{test.stem}: {line}")
                failed += 1

    print("")
    print(f"{len(tests)} native tests, {total_checks} checks")
    if failed == 0:
        print("everything passed.")
        return 0
    print(f"{failed} test files failed:")
    for one in broken:
        print(f"  {one}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
