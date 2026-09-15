#!/usr/bin/env python3
"""Catches the GDScript warnings that the other checkers do not look for.

Why this exists
---------------
Thirteen warnings appeared in one run, and all eleven checkers passed on the
same code. They were four kinds, and none of the four is a matter of taste —
each one is the compiler saying a line does not mean what it looks like:

  - **Integer division.** `bits / 8` on two integers throws the remainder away.
    Nine times in ten that is a bug; the tenth time it is meant, and the way to
    say so is to divide as floats and floor it, which reads as deliberate.
  - **A name that is already a global function.** A variable called `load` or a
    parameter called `seed` means that for the whole of that scope, `load()`
    and `seed()` cannot be called. It compiles; it just quietly takes a tool
    away.
  - **A local shadowing a function in the same class.** Same shape: inside
    those lines, the function cannot be reached by its own name.
  - **A signal emitted only from another class.** A signal belongs to the class
    that declares it. One raised only from elsewhere cannot be found by reading
    the file that owns it, and the compiler reports it as unused.

Each is checked by a rule narrow enough not to guess. Anything ambiguous is
left alone, because a checker that cries wolf is a checker that gets switched
off.

Usage:  python3 tools/check_warnings.py [project_dir]
"""

import re
import sys
import pathlib

SKIP_DIRS = {"addons", "native", ".godot", "build"}

# GDScript's global functions. A variable, parameter or constant with one of
# these names shadows it. Only the ones somebody would plausibly reach for as
# a name are listed — `print` or `deg_to_rad` are not going to collide.
GLOBALS = {
    "load", "seed", "hash", "sign", "abs", "min", "max", "round", "floor",
    "ceil", "range", "len", "str", "int", "float", "bool", "char", "ord",
    "clamp", "lerp", "pow", "log", "exp", "sqrt", "sin", "cos", "tan",
    "step_decimals", "type_string", "typeof", "weakref", "instance_from_id",
    "remap", "ease", "smoothstep", "wrap", "snapped", "randi", "randf",
    "randomize", "assert", "preload",
}


def lines_of(text):
    """Line by line, with comments and string bodies blanked out."""
    for i, line in enumerate(text.split("\n"), 1):
        clean = re.sub(r'"[^"]*"', '""', line)
        clean = re.sub(r"'[^']*'", "''", clean)
        clean = re.sub(r"#.*$", "", clean)
        yield i, line, clean


def integer_division(path, text):
    """`a / b` where both sides are plainly whole numbers.

    Two passes. The first is the narrow, safe one: a bare name or literal
    divided by an integer literal. The second catches what the first missed
    for a year — `h.size() / 2`, `(top + neck) / 2` — which Godot warns about
    on every single reload. Five of those in one file is what a run of this
    project looked like before stage 152, and a warning that always fires is a
    warning the reader stops seeing.
    """
    out = []
    for i, raw, line in lines_of(text):
        # A literal with a decimal point on either side settles it as float
        # division, and so does an explicit float() or a float-returning call.
        for m in re.finditer(r"([\w\.\)\]]+)\s*/\s*([\w\.\(]+)", line):
            left, right = m.group(1), m.group(2)
            if "." in left.split("(")[-1] and not left.endswith("."):
                # `size.x / n` — the member could be a float, so leave it.
                continue
            if re.fullmatch(r"\d+\.\d*", right) or re.fullmatch(r"\d*\.\d+", right):
                continue
            if "float" in left or "float" in right:
                continue
            # Both sides must be an integer literal or a plain name, and at
            # least one an integer literal, or this is not worth calling.
            if not re.fullmatch(r"[A-Za-z_]\w*|\d+", left):
                continue
            if not re.fullmatch(r"[A-Za-z_]\w*|\d+", right):
                continue
            if not (re.fullmatch(r"\d+", right) or re.fullmatch(r"\d+", left)):
                continue
            if "." in left or "." in right:
                continue
            out.append(f"{path}:{i}  '{left} / {right}' divides two whole "
                       f"numbers and throws the remainder away\n    {raw.strip()}")

        # Second pass: anything divided by a bare integer literal, where the
        # left side is a count or a sum rather than a float. `size()` and
        # `len()` return integers; a parenthesised sum of integers is an
        # integer. A float literal, a float() call or a `.x`-style member is
        # left alone, because those are genuinely float division.
        for m in re.finditer(r"(\w+\(\)|\([^()]*\))\s*/\s*(\d+)(?![\d.])", line):
            left, right = m.group(1), m.group(2)
            if "float" in left or "." in left:
                continue
            if left.endswith("()") and not re.fullmatch(r"(size|len|count|length)\(\)", left):
                continue
            if left.startswith("(") and not re.fullmatch(r"\([\w\s+\-*]*\)", left):
                continue
            out.append(f"{path}:{i}  '{left} / {right}' divides two whole "
                       f"numbers and throws the remainder away\n    {raw.strip()}")
    return out


def shadows_global(path, text):
    out = []
    for i, raw, line in lines_of(text):
        for m in re.finditer(r"\bvar\s+(\w+)", line):
            if m.group(1) in GLOBALS:
                out.append(f"{path}:{i}  the variable \"{m.group(1)}\" has the "
                           f"same name as a built-in function\n    {raw.strip()}")
        # Parameters, in a signature or a lambda.
        for m in re.finditer(r"[\(,]\s*(\w+)\s*:", line):
            if m.group(1) in GLOBALS:
                out.append(f"{path}:{i}  the parameter \"{m.group(1)}\" has the "
                           f"same name as a built-in function\n    {raw.strip()}")
    return out


def shadows_func(path, text):
    """A local with the same name as a function declared in the same file.

    Only *locals* — a `var` written inside a function body. A member of an
    inner class may share a name with an outer method without shadowing
    anything, and complaining about that would be complaining about correct
    code, which is how a checker earns a reputation for being wrong.
    """
    funcs = set(re.findall(r"^\s*(?:static\s+)?func\s+(\w+)", text, re.M))
    out = []
    in_func = False
    for i, raw, line in lines_of(text):
        if re.match(r"^\s*(?:static\s+)?func\s+\w+", line):
            in_func = True
            continue
        if line.strip() and not line.startswith(("\t", " ")):
            in_func = False
        if not in_func:
            continue
        for m in re.finditer(r"\bvar\s+(\w+)", line):
            if m.group(1) in funcs:
                out.append(f"{path}:{i}  the local \"{m.group(1)}\" is "
                           f"shadowing a function of the same name in this "
                           f"class\n    {raw.strip()}")
    return out


def lonely_signals(root):
    """A signal declared in one file and only ever emitted from another."""
    files = [p for p in sorted(pathlib.Path(root).rglob("*.gd"))
             if not any(part in SKIP_DIRS for part in p.parts)]
    bodies = {p: p.read_text(encoding="utf-8") for p in files}
    out = []
    for home, text in bodies.items():
        for name in re.findall(r"^signal\s+(\w+)", text, re.M):
            if re.search(rf"\b{name}\.emit\b", text):
                continue
            elsewhere = [p for p, other in bodies.items()
                         if p != home and re.search(rf"\b{name}\.emit\b", other)]
            if elsewhere:
                out.append(
                    f"{home}  the signal \"{name}\" is declared here but only "
                    f"emitted in {elsewhere[0].name} — give this class a "
                    f"method that raises it")
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    trouble = []
    looked = 0
    for path in sorted(pathlib.Path(root).rglob("*.gd")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        looked += 1
        text = path.read_text(encoding="utf-8")
        trouble += integer_division(path, text)
        trouble += shadows_global(path, text)
        trouble += shadows_func(path, text)
    trouble += lonely_signals(root)
    for one in trouble:
        print(one)
    print(f"--- {len(trouble)} compiler warnings waiting to happen, "
          f"in {looked} files ---")
    return 1 if trouble else 0


if __name__ == "__main__":
    sys.exit(main())
