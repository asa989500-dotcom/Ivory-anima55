#!/usr/bin/env python3
"""Find statements wrapped onto a second line without a backslash.

This is the fault that produced sixty-one errors across eleven files from two
broken lines. GDScript continues an expression across a line break while it is
inside an unclosed bracket, and does *not* continue a statement inside a lambda
body — so this reads perfectly and does not parse:

    units.sort_custom(func(a, b): return (a as Unit).from_frame
        < (b as Unit).from_frame)

The parser stops at the `<`, the class never builds, and every file that
mentions the class reports an error of its own. The real fault is two lines
long and the report is sixty-one lines long in files that are fine, which is
why it took a screenshot of the last page to find.

The rule checked: a line may not *begin* with a binary operator unless the
line before it ends with a backslash. That is legal GDScript in a few places
and bad style in all of them, so flagging it outright costs nothing and
catches the whole family.
"""
import re
import sys
import pathlib

# Operators that cannot legally begin a statement.
LEADING = re.compile(
    r'^\s*(<=|>=|==|!=|<|>|\+|\*|/|%|&&|\|\||\band\b|\bor\b|\bin\b|\bif\b\s|'
    r'\belse\b\s)'
)
# `-` is left out: a line may legitimately begin with a negative number in a
# continued list, and `->` is a return type. `if`/`else` are included only with
# trailing space, to catch a wrapped ternary without catching a plain block.
BLOCK_START = re.compile(r'^\s*(if|elif|else|for|while|match|func|class)\b')


def strip_strings(line: str) -> str:
    out = []
    i = 0
    quote = ''
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == '\\':
                i += 2
                continue
            if ch == quote:
                quote = ''
        else:
            if ch in '"\'':
                quote = ch
            elif ch == '#':
                break
            else:
                out.append(ch)
        i += 1
    return ''.join(out)


LAMBDA = re.compile(r'\bfunc\s*\(')


def scan(path):
    """Flag lines that begin with an operator and are not being continued.

    Two cases are legal and must not be reported, or the check becomes noise
    that gets ignored — which is the only way a checker ever fails:

    * The line before ends with a backslash. That is an explicit continuation
      and always works.
    * We are inside an unclosed bracket. An *expression* spanning several
      lines inside brackets continues implicitly, which is ordinary GDScript
      and is used all over this project.

    The case that is not legal, and is the one this exists for: inside an
    unclosed bracket where a **lambda body has been opened**. The body is a
    sequence of statements, and a statement does not continue across a line
    break just because there is an open bracket somewhere outside it. That is
    what parses as far as the operator and then stops.
    """
    bad = []
    lines = path.read_text(encoding='utf-8').split('\n')
    depth = 0
    # Where the outermost currently-open bracket was opened.
    opened_at = 0
    for i, line in enumerate(lines):
        code = strip_strings(line)
        starts_at_depth = depth
        started_from = opened_at

        # A block header is a new statement, not a continuation, wherever it
        # sits. `if` and `else` reach this check because a wrapped ternary
        # begins with them — and a ternary never ends in a colon, which is
        # what tells the two apart.
        tail = code.rstrip()
        # A line that is plainly unfinished — it ends with a backslash, an
        # open bracket, a comma or an operator — is the *start* of something
        # spanning several lines, not a stranded continuation. A multi-line
        # `if` header is exactly this, and reporting its first line would
        # bury the one real fault under fifty of them.
        # ...or if it opens more brackets than it closes, which is the other
        # way a header runs on: `if a and (b` continues on the next line
        # inside the bracket it just opened.
        opens = sum(1 for ch in code if ch in '([{') \
            - sum(1 for ch in code if ch in ')]}')
        unfinished = tail.endswith('\\') or opens > 0 \
            or (tail and tail[-1] in '([{,+-*/%<>=&|')
        header = bool(BLOCK_START.match(line)) \
            and (tail.endswith(':') or unfinished)

        if not header and line.strip() \
                and not line.strip().startswith('#') \
                and LEADING.match(line):
            prev = ''
            k = i - 1
            while k >= 0 and (not lines[k].strip()
                              or lines[k].strip().startswith('#')):
                k -= 1
            if k >= 0:
                prev = strip_strings(lines[k]).rstrip()
            if not prev.endswith('\\'):
                if starts_at_depth == 0:
                    bad.append((i + 1, line.strip()[:60], 'no continuation'))
                else:
                    # Inside brackets: legal for an expression, and not legal
                    # once a lambda body has been opened in there.
                    region = '\n'.join(lines[started_from:i])
                    if LAMBDA.search(strip_strings(region)):
                        bad.append((i + 1, line.strip()[:60],
                                    'statement inside a lambda body'))

        for ch in code:
            if ch in '([{':
                if depth == 0:
                    opened_at = i
                depth += 1
            elif ch in ')]}':
                depth = max(depth - 1, 0)
    return bad


def main():
    # Default to the working directory, the way every other checker here
    # does. Without this the tool raised IndexError the moment it was run
    # with no argument — which is exactly how the build gate runs it, so it
    # had never once reported on this project.
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    total = 0
    for p in sorted(root.rglob('*.gd')):
        for (line, text, why) in scan(p):
            total += 1
            print(f'{p}:{line}: {why} — {text}')
    print(f'--- {total} suspect continuations ---')
    return 1 if total else 0


sys.exit(main())
