#!/usr/bin/env python3
"""A lambda that assigns to a variable declared outside it.

GDScript captures locals **by value**. A lambda that writes to one is writing
to its own copy; the outer variable never changes, and nothing fails — the
function just quietly returns whatever the variable was initialised to.

the retired reference-room inspector was written this way:

    var checks: int = 0
    var take := func(r: Dictionary) -> void:
        checks += int(r.get("checks", 0))     # updates a copy

so the fourteen devices ran, found problems, and the summary reported
`checks: 0, failures: 0` — a clean bill of health for a broken room, which is
worse than having no check at all. Godot prints

    Reassigning lambda capture does not modify the outer local variable

at parse time, but it is a warning in a list of hundreds and it scrolls past.

What is allowed, and deliberately so: **mutating** a captured object. Appending
to a captured Array or setting a key on a captured Dictionary works exactly as
it reads, because the reference is what was copied. Only rebinding the name is
wrong.

Run with no arguments from the project root.
"""

import pathlib
import re
import sys

LAMBDA = re.compile(r"^(\s*)var\s+(\w+)\s*:?=\s*func\s*\(")
DECLARE = re.compile(r"^\s*(?:var|const)\s+(\w+)\b")
PARAMS = re.compile(r"func\s*\(([^)]*)\)")
ASSIGN = re.compile(r"^\s*(\w+)\s*(?:\+|-|\*|/|\|\||&&)?=(?!=)")


def check_file(path: pathlib.Path) -> int:
    lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    problems = 0

    for i, raw in enumerate(lines):
        opened = LAMBDA.match(raw)
        if not opened:
            continue
        indent = len(opened.group(1).expandtabs(4))

        # Names the lambda owns: its parameters and anything it declares
        # inside itself. Assigning to those is fine.
        own = {p.split(":")[0].strip() for p in
               (PARAMS.search(raw).group(1) if PARAMS.search(raw) else "").split(",")}
        own.discard("")

        j = i + 1
        while j < len(lines):
            line = lines[j]
            if line.strip() and len(line[:len(line) - len(line.lstrip())].expandtabs(4)) <= indent:
                break
            body = re.sub(r"#.*$", "", line)
            declared = DECLARE.match(body)
            if declared:
                own.add(declared.group(1))
                j += 1
                continue
            hit = ASSIGN.match(body)
            if hit and hit.group(1) not in own:
                name = hit.group(1)
                # `self` and a member of this class are properties, not
                # locals, and are not captured by value.
                if name not in ("self",):
                    print(f"{path.as_posix()}:{j + 1}  the lambda '{opened.group(2)}' "
                          f"assigns to '{name}', which is captured by value — "
                          f"the outer variable will not change")
                    print(f"    {line.strip()}")
                    problems += 1
            j += 1

    return problems


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    problems = 0
    files = 0
    for folder in ("scripts", "tests"):
        for path in sorted((root / folder).rglob("*.gd")):
            files += 1
            problems += check_file(path)
    print(f"--- {problems} lambdas writing to a captured local, in {files} files ---")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
