import os, sys

# A structural check on GDScript indentation.
#
# Not a parser. It looks for the two mistakes that actually happen when a file
# is edited by hand or by patch, and it has to understand one thing to avoid
# drowning in false alarms: a *logical* line can span several physical ones,
# and only the first of them carries the indentation that means anything.
# A wrapped signature is indented deeper than its own body and that is normal.

def strip_strings(line):
    out, i, q, triple = [], 0, None, False
    while i < len(line):
        c = line[i]
        if q:
            if not triple and c == '\\':
                i += 2; continue
            if triple and line[i:i+3] == q:
                q = None; triple = False; i += 3; continue
            if not triple and c == q:
                q = None
            i += 1; continue
        if line[i:i+3] in ('"""', "'''"):
            q = line[i:i+3]; triple = True; i += 3; continue
        if c in '"\'':
            q = c; i += 1; continue
        if c == '#':
            break
        out.append(c); i += 1
    return ''.join(out)

def check(path):
    bad = []
    lines = open(path, encoding='utf-8').read().split('\n')
    legal = {0}
    depth = 0
    slash = False
    stmt_indent = 0
    opened_at = None       # indent of a statement that just opened a block
    for n, raw in enumerate(lines, 1):
        if not raw.strip():
            continue
        stripped = raw.lstrip('\t')
        if stripped.startswith(' ') and not stripped.startswith(' '):
            pass
        ind = len(raw) - len(stripped)
        code = strip_strings(raw)
        body = code.strip()
        joined = depth > 0 or slash

        if not joined:
            # Inside brackets, indentation carries no meaning and spaces are
            # ordinary alignment. Only the first line of a statement counts.
            if stripped[:1] == ' ':
                bad.append((n, 'space used for indentation'))
            stmt_indent = ind
            if opened_at is not None:
                if ind <= opened_at:
                    bad.append((n, 'previous line opened a block that nothing is inside'))
                else:
                    legal.add(ind)
                opened_at = None
            if ind not in legal:
                near = max(x for x in legal if x < ind) if any(x < ind for x in legal) else 0
                bad.append((n, 'indented to %d with nothing opening a block there (nearest legal %d)' % (ind, near)))
                legal.add(ind)
            else:
                legal = {x for x in legal if x <= ind}

        depth += code.count('(') - code.count(')')
        depth += code.count('[') - code.count(']')
        depth += code.count('{') - code.count('}')
        if depth < 0:
            depth = 0
        slash = body.endswith('\\')

        if depth == 0 and not slash and body.endswith(':'):
            opened_at = stmt_indent
    if opened_at is not None:
        bad.append((len(lines), 'file ends on a line that opened a block'))
    if depth != 0:
        bad.append((len(lines), 'file ends with %d bracket(s) still open' % depth))
    return bad

root = sys.argv[1] if len(sys.argv) > 1 else 'scripts'
total = 0
for base, dirs, files in os.walk(root):
    for f in sorted(files):
        if not f.endswith('.gd'):
            continue
        p = os.path.join(base, f)
        for n, why in check(p):
            print('%s:%d  %s' % (p, n, why))
            total += 1
print('--- %d suspicious lines' % total)
