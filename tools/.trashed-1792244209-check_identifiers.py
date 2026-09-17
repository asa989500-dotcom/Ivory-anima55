#!/usr/bin/env python3
"""Catches a `_name` that is used but never declared in its file.

Why this exists
---------------
I removed `var _mesh_node` from `bspline_room.gd` and left two lines that still
read it. GDScript rejects that at parse time, so the whole project stopped
compiling — again, and for the second time from the same shape of mistake:
deleting or renaming something and missing one of the places that used it.

`check_returns.py` could not see it; that one only looks at return types. This
one looks at names.

Why only underscore names
-------------------------
In this codebase a leading underscore always means "private to this file" — a
member variable, a local, a helper method. It is never a global class, never an
autoload, never a Godot built-in constant. That makes the rule exact rather
than approximate: if a `_name` is read here, it must have been declared here.

Anything without the underscore is left alone, because deciding whether a bare
name is a global class, an enum member, a signal parameter or a typo needs a
real parser, and a checker that guesses is a checker that gets switched off.

Declarations are collected across the whole file, inner classes included. That
is a *superset* of what is actually in scope at any one point, so this can miss
a real error but can never invent one — the safe direction for something meant
to run on every build.

Usage:  python3 tools/check_identifiers.py [project_dir]
"""

import re
import sys
import pathlib

# Godot calls these; a file may use them without declaring them.
ENGINE = {
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_gui_input", "_draw", "_notification", "_init",
    "_enter_tree", "_exit_tree", "_to_string", "_get", "_set",
    "_get_property_list", "_property_can_revert", "_property_get_revert",
    "_validate_property", "_can_drop_data", "_drop_data", "_get_drag_data",
    "_make_custom_tooltip", "_has_point", "_get_minimum_size",
    "_structured_text_parser", "_get_configuration_warnings",
}

DECL = [
    r"\bvar\s+(_\w+)",              # var _x  (member or local)
    r"\bconst\s+(_\w+)",            # const _X
    r"\bfunc\s+(_\w+)",             # func _x
    r"\bsignal\s+(_\w+)",           # signal _x
    r"\bclass\s+(_\w+)",            # class _X
    r"\benum\s+(_\w+)",             # enum _X
    r"\bfor\s+(_\w+)\s+in\b",       # for _x in
    r"\bstatic\s+var\s+(_\w+)",     # static var _x
]


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

def declared_in(text):
    names = set()
    for pattern in DECL:
        names.update(re.findall(pattern, text))
    # Parameters, of both named functions and lambdas.
    for params in re.findall(r"func\s*\w*\s*\(([^)]*)\)", text):
        for part in params.split(","):
            name = part.split(":")[0].split("=")[0].strip()
            if name.startswith("_"):
                names.add(name)
    # Enum members: enum X { _A, _B }
    for body in re.findall(r"\benum\s+\w*\s*\{([^}]*)\}", text):
        for part in body.split(","):
            name = part.split("=")[0].strip()
            if name.startswith("_"):
                names.add(name)
    return names


def used_in(lines):
    """Every `_name` read, with its line number, ignoring strings, comments
    and anything reached through a dot (that is another object's business)."""
    out = []
    for n, line in enumerate(lines, 1):
        code = re.sub(r'"[^"]*"|\'[^\']*\'', "", line)
        code = code.split("#")[0]
        for m in re.finditer(r"(?<![\w.$])(_\w+)", code):
            out.append((n, m.group(1), line.strip()))
    return out


def check(root):
    problems = []
    for path in sorted(gd_files(root)):
        text = path.read_text(encoding="utf-8")
        known = declared_in(text) | ENGINE
        for n, name, line in used_in(text.split("\n")):
            if name in known or name == "_":
                continue
            problems.append(
                "%s:%d  '%s' is used but never declared in this file\n    %s"
                % (path, n, name, line[:78])
            )
    return problems


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    problems = check(root)
    for p in problems:
        print(p)
    print("--- %d undeclared identifiers ---" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
