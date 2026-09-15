#!/usr/bin/env python3
"""Finds `var x := ...` that Godot cannot infer a type for.

This checker exists because of one specific error that reached the user and
stopped the whole project from parsing:

    Error at (198, 18): Cannot infer the type of "state" variable
    because the value doesn't have a set type.

`:=` asks the compiler to work the type out. It can only do that when the
right-hand side already has one. Three shapes never do:

  1. a call on a value typed `Object`, `Variant` or `RefCounted` — the compiler
     does not know which class it is, so it does not know what the method
     returns;
  2. a ternary, `a if c else b` — even when both sides are typed, GDScript
     gives the expression no static type;
  3. a subscript of an untyped container, `d["k"]` or `arr[i]`.

Every one of these parses fine in isolation and fails at load time, which is
the worst way to find out: the editor reports it, the whole script fails, and
every class that mentions it fails after it.

The fix is always the same and always cheap — write the type down:

    var state: Dictionary = model.export_state()

which is what the project asks for anyway.

Usage:  python3 tools/check_inference.py [project_dir]
Exit:   0 clean, 1 if anything was found.
"""

import pathlib
import re
import sys

# Types whose methods the compiler cannot resolve.
OPAQUE = {"Object", "Variant", "RefCounted", "Node", "Resource"}

# `var name := rest`
DECL = re.compile(r"^(\s*)var\s+([A-Za-z_]\w*)\s*:=\s*(.+?)\s*$")
# `var name: Type = ...`  /  `func f(name: Type ...)`
TYPED = re.compile(r"\b([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)")
# a bare ternary at the top level of an expression
TERNARY = re.compile(r"\bif\b.+\belse\b")
# `receiver.method(` at the very start of the value
CALL = re.compile(r"^([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)\s*\(")
# `name[` at the very start of the value
INDEX = re.compile(r"^([A-Za-z_]\w*)\s*\[")


def top_level(text: str) -> bool:
    """True when the expression has no unclosed bracket — i.e. it is complete."""
    depth = 0
    quote = None
    escaped = False
    for ch in text:
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
    return depth == 0


def declared_types(lines, upto):
    """Map local/parameter name -> written type, for everything above `upto`.

    Deliberately whole-file rather than per-scope. A name that is a Dictionary
    in one function and an Object in another is a different problem, and this
    checker erring towards reporting is the right way round.
    """
    found = {}
    for ln in lines[:upto]:
        stripped = ln.split("#")[0]
        if "var " not in stripped and "func " not in stripped:
            continue
        for name, kind in TYPED.findall(stripped):
            found.setdefault(name, kind)
    return found


def scan(path: pathlib.Path):
    lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
    hits = []
    for i, raw in enumerate(lines):
        line = raw.split("#")[0]
        m = DECL.match(line)
        if not m:
            continue
        name, value = m.group(2), m.group(3).rstrip()

        # A wrapped line: join the continuation so the ternary is visible.
        joined = value
        k = i
        while (joined.endswith("\\") or not top_level(joined)) and k + 1 < len(lines):
            k += 1
            joined = joined.rstrip("\\") + " " + lines[k].split("#")[0].strip()

        if TERNARY.search(joined) and top_level(joined):
            hits.append((i + 1, name, "a ternary has no static type"))
            continue

        call = CALL.match(joined)
        if call:
            kinds = declared_types(lines, i)
            kind = kinds.get(call.group(1))
            if kind in OPAQUE:
                hits.append((i + 1, name,
                             f"`{call.group(1)}` is {kind}; "
                             f"`{call.group(2)}()` has no known return type"))
                continue

        index = INDEX.match(joined)
        if index:
            kinds = declared_types(lines, i)
            kind = kinds.get(index.group(1))
            if kind in ("Dictionary", "Array", None) and index.group(1) not in ("range",):
                hits.append((i + 1, name,
                             f"`{index.group(1)}[...]` yields Variant"))
    return hits


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    total = 0
    for path in sorted(root.rglob("*.gd")):
        if ".godot" in path.parts:
            continue
        for line_no, name, why in scan(path):
            rel = path.relative_to(root)
            print(f"{rel}:{line_no}  `var {name} :=` — {why}."
                  f"  Write the type: `var {name}: <Type> = ...`")
            total += 1
    print(f"--- {total} uninferable declarations ---")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
