#!/usr/bin/env python3
"""Checks that every line sits at an indentation level that exists.

Why this exists
---------------
A build reached a tablet in which `bspline_room.gd` looked like this:

        @warning_ignore("integer_division")
        var ay: int = at / cols          <- one tab, inside a three-tab block

Godot said `Expected statement, found "Indent" instead`, refused the file,
and then reported four more errors in `main.gd` for a class that had nothing
wrong with it. All six checkers had read that file and called it clean,
because not one of them looked at the shape of the code — they read names,
returns, continuations, scopes, cross-file references and file lengths, and
indentation is none of those.

In a language where indentation *is* the block structure, that was a hole the
size of the language.

How it reads a file
-------------------
Only lines that begin a statement are checked. A line inside an unclosed
bracket, or after one ending in a backslash, is a continuation and may be
indented however it reads best — this codebase wraps arguments constantly and
a checker that argued about those would be turned off within a day.

For a statement line, three things must hold:

* it is indented with tabs, never spaces
* if the statement before it opened a block — it ended in a colon — this one
  is exactly one level deeper
* otherwise it sits at a level that is currently open: the same as the
  previous statement, or back out to one the file has already established

That is the whole of GDScript's block rule, and it is enough to catch
everything that produces `Expected statement, found "Indent"` or
`Unindent doesn't match the previous indentation level`.

Usage:  python3 tools/check_indent.py [project_dir]
"""

import re
import sys
import pathlib

OPENERS = "([{"
CLOSERS = ")]}"


def gd_files(root):
    out = []
    for folder in ("scripts", "tests"):
        base = pathlib.Path(root, folder)
        if base.exists():
            out.extend(sorted(base.rglob("*.gd")))
    return out


def code_of(line):
    """The line with strings and the trailing comment removed.

    Both have to go before brackets are counted, or a `#` inside a string ends
    the line early and a `(` inside one is counted as an opener that never
    closes — after which every following line looks like a continuation and
    the checker goes quiet for the rest of the file.
    """
    out = []
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            out.append('"')
            i += 1
            continue
        if ch == "#":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def indent_of(line):
    """`(levels, ok)` — the tab count, and whether spaces were used."""
    n = 0
    for ch in line:
        if ch == "\t":
            n += 1
        elif ch == " ":
            return (n, False)
        else:
            break
    return (n, True)


def logical_lines(lines):
    """The file as statements rather than as lines.

    A statement can run over several lines — this codebase wraps long
    argument lists constantly — and the two facts needed about it live at
    opposite ends: the indentation is on its *first* line and the colon that
    opens a block is on its *last*. Reading line by line gets the second one
    wrong for every wrapped `func` signature in the project, which is what a
    first attempt at this did: two hundred and fifty complaints, all of them
    the checker's fault.

    Yields `(line_number, raw_first_line, opens_a_block)`; comment-only and
    blank lines are left out.
    """
    depth = 0
    continued = False
    first_no = 0
    first_raw = ""
    tail = ""
    holding = False

    for n, raw in enumerate(lines, 1):
        if raw.strip() == "" and not holding:
            continue
        code = code_of(raw)
        if not holding:
            if raw.strip().startswith("#"):
                continue
            first_no = n
            first_raw = raw
            holding = True
        tail = code

        opens = sum(code.count(c) for c in OPENERS)
        closes = sum(code.count(c) for c in CLOSERS)
        depth = max(depth + opens - closes, 0)
        continued = code.rstrip().endswith("\\")

        if depth > 0 or continued:
            continue
        yield (first_no, first_raw, tail.rstrip().endswith(":"))
        holding = False

    if holding:
        yield (first_no, first_raw, tail.rstrip().endswith(":"))


def scan(path):
    problems = []
    lines = path.read_text(encoding="utf-8").split("\n")

    open_levels = [0]
    expect_deeper = False
    last_indent = 0
    started = False

    for (n, raw, opens_block) in logical_lines(lines):
        here, tabs_only = indent_of(raw)
        if not tabs_only:
            problems.append((n, raw, "indented with spaces, not tabs"))
            continue

        if not started:
            started = True
            last_indent = here
            open_levels = [here]
            expect_deeper = opens_block
            continue

        if expect_deeper:
            if here != last_indent + 1:
                problems.append((n, raw,
                    "should be one level deeper than the line above "
                    "(expected %d tab(s), found %d)"
                    % (last_indent + 1, here)))
            open_levels.append(here)
        elif here > last_indent:
            problems.append((n, raw,
                "indented deeper with no block opened above it"))
            open_levels.append(here)
        elif here < last_indent:
            if here not in open_levels:
                problems.append((n, raw,
                    "unindent does not match any open level %s"
                    % sorted(set(open_levels))))
            while len(open_levels) > 1 and open_levels[-1] > here:
                open_levels.pop()

        last_indent = here
        expect_deeper = opens_block

    return problems


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    total = 0
    for path in gd_files(root):
        for (n, text, why) in scan(path):
            total += 1
            print("%s:%d  %s\n    %s" % (path, n, why, text.rstrip()[:78]))
    print("--- %d indentation problems ---" % total)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
