#!/usr/bin/env python3
"""Constants that are not constant expressions.

GDScript's ``const`` takes a *constant expression*. A call is not one — it is
evaluated at run time — so ``const X = PackedStringArray([...])`` does not
warn, it fails to compile, and the whole script goes with it. One of these
shipped and the app would not open.

The parser catches it instantly; the point of this check is that it catches it
*here*, before a build goes out, rather than on somebody's tablet.

Literals of the built-in structs are fine: ``Vector2(1, 2)`` and its family are
constructed at parse time and GDScript accepts them in a ``const``.
"""
import os
import re
import sys

# Built-in value types GDScript folds at parse time.
FOLDED = {
    "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i",
    "Color", "Rect2", "Rect2i", "Quaternion", "Plane", "Basis",
    "Transform2D", "Transform3D", "AABB", "Projection",
}

CONST_CALL = re.compile(
    r"^\s*const\s+\w+(?:\s*:\s*[\w.]+)?\s*=\s*([A-Za-z_][\w.]*)\s*\(")


def scan(root):
    problems = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(base, name)
            with open(path, encoding="utf-8") as handle:
                for number, line in enumerate(handle, 1):
                    found = CONST_CALL.match(line)
                    if not found:
                        continue
                    if found.group(1) in FOLDED:
                        continue
                    problems.append((path, number, found.group(1),
                                     line.strip()))
    return problems


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    problems = scan(root)
    for path, number, called, line in problems:
        rel = os.path.relpath(path, root)
        print("%s:%d  const assigned a call to %s() — not a constant "
              "expression, this will not compile" % (rel, number, called))
        print("    %s" % line[:100])
    print("--- %d constants that are not constant ---" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
