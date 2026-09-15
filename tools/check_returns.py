#!/usr/bin/env python3
"""Catches a `return` whose value cannot be the declared type.

Why this exists
---------------
A guard added to `save_sprite_sheet` said `return null` from a function
declared `-> String`. GDScript rejects that at parse time, so the *whole
project* stopped compiling — not just that export, everything. The memory
check the guard was making was correct; the way it gave up was not.

It is an easy mistake to make and an expensive one to ship, because the
symptom lands nowhere near the cause: the user opens the editor and sees a
red line in a file they were not working on.

The pattern is always the same. A function that returns a *thing* signals
failure with `null`; a function that returns a *path* signals failure with
`""`; a function that returns a *count* signals it with `0` or `-1`. Adding a
new failure path means picking the right kind of nothing, and this checks that
the one picked can actually be returned.

What it does not do
-------------------
It is deliberately narrow. It only flags pairs that are impossible — `null`
from a `-> String`, `""` from a `-> int` — and never guesses at anything
subtler. A checker that cries wolf is a checker people stop running.

Usage:  python3 tools/check_returns.py [project_dir]
"""

import re
import sys
import pathlib

# Types that cannot hold null. Everything else — Image, Dictionary, Array,
# Object, any class name — legitimately can, and is left alone.
NOT_NULLABLE = {
    "String", "StringName", "NodePath", "int", "float", "bool",
    "Vector2", "Vector2i", "Vector3", "Vector3i", "Rect2", "Rect2i",
    "Color", "Transform2D", "Transform3D", "Basis", "Quaternion",
    "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
    "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
    "PackedVector2Array", "PackedVector3Array", "PackedColorArray",
}

NUMERIC = {"int", "float"}
IMPOSSIBLE_EMPTY = {"int", "float", "bool", "Vector2", "Vector2i", "Color"}


def gd_files(root):
    """Every GDScript in the project: the app and the tests both.

    The tests were outside this net when they were written, which is exactly
    the wrong way round — a broken test file fails the build for a reason
    nobody can see, since the checkers said the project was clean.
    """
    out = []
    for folder in ("scripts", "tests"):
        base = pathlib.Path(root, folder)
        if base.exists():
            out.extend(sorted(base.rglob("*.gd")))
    return out

def declared_return(lines, i):
    """The return type of the function starting at line i, or None.

    Signatures wrap in this codebase, so the search runs on until it finds the
    arrow or gives up after a few lines.
    """
    joined = lines[i]
    k = i + 1
    while "->" not in joined and k < min(i + 5, len(lines)):
        joined += " " + lines[k].strip()
        k += 1
    m = re.search(r"->\s*([\w\.]+)\s*:", joined)
    return m.group(1) if m else None


def check(root):
    problems = []
    for path in sorted(gd_files(root)):
        lines = path.read_text(encoding="utf-8").split("\n")
        ret = None
        sig = ""
        for n, line in enumerate(lines):
            if re.match(r"^\s*(?:static\s+)?func\s+\w+\(", line):
                ret = declared_return(lines, n)
                sig = line.strip()
                continue
            if ret is None:
                continue
            m = re.match(r"^\s*return\s+(\S.*?)\s*$", line)
            if not m:
                continue
            value = m.group(1)
            why = None
            if value == "null" and ret in NOT_NULLABLE:
                why = "null"
            elif value in ('""', "''") and ret in IMPOSSIBLE_EMPTY:
                why = "an empty string"
            elif re.fullmatch(r"-?\d+(\.\d+)?", value) and ret == "String":
                why = "a number"
            elif value in ("true", "false") and (ret == "String" or ret in NUMERIC):
                why = "a boolean"
            if why:
                problems.append(
                    "%s:%d  returns %s, but gives back %s\n"
                    "    %s\n"
                    "    %s" % (path, n + 1, ret, why, sig, line.strip())
                )
    return problems


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    problems = check(root)
    for p in problems:
        print(p)
    print("--- %d impossible returns ---" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
