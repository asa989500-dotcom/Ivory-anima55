#!/usr/bin/env python3
"""Find local variables redeclared inside one function, or covering a method.

GDScript does not allow a local to shadow another local anywhere inside the
same function — nested blocks and loop variables included. It is an error, not
a warning, and it stops the parser: the class never builds, and every file that
mentions that class reports an error of its own. Two such lines once produced
thirteen errors in one file that had nothing wrong with it.

The scoping has to be right or this is worse than useless. Two rules, and the
difference between them is where a first attempt at this went wrong:

* A `var` lives from where it is declared to the end of the block containing
  it. Two `var x` in sibling `if` branches are fine.
* A `for` variable lives only inside the loop body. Two sequential
  `for i in ...` loops at the same level are fine, and extremely common — a
  checker that flags those is one nobody will read, and a checker nobody
  reads catches nothing.

## And a local covering a method of the same class

Added after `comic_panels.gd` came back from Godot with three of these:

    Line 102 (SHADOWED_VARIABLE): the local variable "at" is shadowing an
    already-declared function at line 156 in the current class.

A warning rather than an error, and that is the trap. The file builds, so
nothing forces the issue — but the name inside that function no longer means
the method, and the day somebody adds a call to `at(...)` in a function that
happens to have a local called `at`, it resolves to the local and fails with
a message about calling a non-callable. The fix costs one rename now and an
afternoon later, so it is caught now.

Only methods of the same class are counted, and only where the file itself
declares them — a local named `size` or `min` is not shadowing anything of
this file's.
"""
import re
import sys
import pathlib

VAR = re.compile(r'^(\s*)var\s+([A-Za-z_]\w*)')
PARAMS = re.compile(r'^\s*(?:static\s+)?func\s+[A-Za-z_]\w*\s*\(([^)]*)\)')
FOR = re.compile(r'^(\s*)for\s+([A-Za-z_]\w*)\s+in\b')
FUNC = re.compile(r'^(\s*)(static\s+)?func\s+([A-Za-z_]\w*)')
CLASS = re.compile(r'^(\s*)class\s+([A-Za-z_]\w*)')


def bracket_delta(text):
    """How much this line opens or closes, ignoring quotes and comments."""
    depth = 0
    quote = None
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == '\\':
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
        elif ch == '#':
            break
        elif ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        i += 1
    return depth


def joined(lines):
    """The file with every wrapped line folded onto the one it continues.

    A signature that does not fit on one line is written across two:

        static func _crosses(box: Rect2, from: Vector2, to: Vector2,
                upright: bool, at: float) -> bool:

    and `PARAMS` — anchored at `func` and stopping at the first `)` — sees
    the first line only, so `upright` and `at` were invisible. Godot named
    that exact parameter and this checker did not, which is the one failure a
    checker cannot afford: it was read, it said clean, and it was wrong.

    Two kinds of wrap, and only counting one was the whole of the miss. A
    trailing `\\` is the obvious kind. The other is a line that simply ends
    with a bracket still open — which needs no marker at all, and is how
    every wrapped signature in this project is actually written.

    The fold keeps the original line number of the line a fragment started
    on, so every complaint still points where a person can act on it. Text
    inside quotes is skipped when counting brackets, so a string holding a
    lone `(` cannot swallow the rest of the file.
    """
    out = []
    carry = None
    start = 0
    depth = 0
    for i, line in enumerate(lines, 1):
        text = line.rstrip('\n')
        if carry is not None:
            # A continuation's leading tabs are layout, not structure.
            carry += ' ' + text.strip()
        else:
            carry, start, depth = text, i, 0
        depth = max(0, depth + bracket_delta(text))
        if depth > 0 or carry.rstrip().endswith('\\'):
            if carry.rstrip().endswith('\\'):
                carry = carry.rstrip()[:-1]
            continue
        out.append((start, carry))
        carry = None
    if carry is not None:
        out.append((start, carry))
    return out


def indent_of(line: str) -> int:
    n = 0
    for ch in line:
        if ch in '\t ':
            n += 1
        else:
            break
    return n


def methods_of(lines):
    """Every function this file declares, by name, with its line.

    Indentation is deliberately ignored: an inner class's method is still a
    name in scope for the code inside that class, and Godot's own warning
    does not distinguish either. Overreach here is a rename, and a rename is
    cheap; the miss is what costs.
    """
    found = {}
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith('#'):
            continue
        m = FUNC.match(line)
        if m:
            found.setdefault(m.group(3), i)
    return found


def scan(path):
    out = []
    raw = path.read_text(encoding='utf-8').split('\n')
    here_methods = methods_of(raw)
    live = []
    func_indent = None
    func_name = None
    for i, line in joined(raw):
        if not line.strip() or line.strip().startswith('#'):
            continue
        here = indent_of(line)

        m = FUNC.match(line)
        if m:
            # A function's parameters are locals from its first line.
            #
            # They were not being counted, and that is exactly the hole a real
            # build fell through: `tools/lift_module.py` gave a moved function
            # a new first parameter named `p`, the body already declared
            # `var p: ProjectManager.Project`, and GDScript refused the file
            # with "There is already a parameter named p in this scope". Every
            # class that mentioned the broken one then reported an error of
            # its own — eight errors from one collision, in files with nothing
            # wrong with them. This checker read all four files and said they
            # were clean, because it began looking only after the signature.
            live = []
            params = PARAMS.match(line)
            if params:
                for part in params.group(1).split(','):
                    word = part.split(':')[0].split('=')[0].strip()
                    if re.fullmatch(r'[A-Za-z_]\w*', word or ''):
                        live.append((here + 1, word, i, 'parameter'))
                        if word in here_methods and word != m.group(3):
                            out.append((i, word, here_methods[word],
                                'method', m.group(3)))
            func_indent = here
            func_name = m.group(3)
            continue
        if CLASS.match(line):
            live = []
            func_indent = None
            continue
        if func_indent is None:
            continue
        if here <= func_indent:
            live = []
            func_indent = None
            continue

        # Retire names whose block has closed. A `for` variable dies as soon
        # as the indentation returns to the `for` itself; a `var` survives
        # until the block *containing* it closes.
        live = [x for x in live
                if (here > x[0] if x[3] == 'for' else here >= x[0])]

        for rx, kind in ((VAR, 'var'), (FOR, 'for')):
            m = rx.match(line)
            if not m:
                continue
            name = m.group(2)
            hit = False
            for (_, other, at, other_kind) in live:
                if other == name:
                    out.append((i, name, at, other_kind, func_name))
                    hit = True
                    break
            # A local may also cover a method of this same class. Reported
            # only when the local is not already being reported for a clash
            # with another local, so one line raises one complaint.
            if not hit and name in here_methods and name != func_name:
                out.append((i, name, here_methods[name], 'method', func_name))
            live.append((here, name, i, kind))
            break
    return out


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'scripts')
    total = 0
    for p in sorted(root.rglob('*.gd')):
        for (line, name, at, kind, fn) in scan(p):
            total += 1
            print(f'{p}:{line}: "{name}" clashes with the {kind} '
                  f'at line {at} (in {fn})')
    print(f'--- {total} redeclarations ---')
    return 1 if total else 0


sys.exit(main())
