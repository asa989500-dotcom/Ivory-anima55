#!/usr/bin/env python3
"""Duplicate keys in the language table, and gaps in it.

Written after stage 138 shipped a `lang.gd` with three keys defined twice.
GDScript treats that as a parse error, `lang.gd` failed to load, every script
that touches `UiKit.label_for` failed with it, and the app came up **with no
text in it at all** — no tool names, no titles, no buttons. One repeated
dictionary key emptied the entire interface.

Nothing catches that on the way in. The key is legal on its own line, the file
looks right, and the only thing that notices is the engine, on the device, at
which point the person sees a blank rail and has no idea why.

So it is checked here, where it costs a second and is caught by whoever wrote
the line rather than by whoever opened the app. Three things:

  * **No key twice.** The failure above.
  * **Every row the same width.** A row short of a language reads as an empty
    string in that language, which shows as a blank button rather than an
    error — the worst kind of wrong, because it looks deliberate.
  * **No empty translation.** Same reason.
"""
import re
import sys
from pathlib import Path


def check(root: Path) -> int:
    path = root / "scripts" / "lang.gd"
    if not path.exists():
        print("no scripts/lang.gd")
        return 0

    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")

    # The declared number of languages, from the NAMES/CODES table, so this
    # keeps working when a language is added rather than needing an edit.
    width = 0
    for line in lines:
        m = re.match(r"const (CODES|NAMES)\b.*\[(.*)\]", line)
        if m:
            width = max(width, m.group(2).count(",") + 1)

    seen: dict[str, int] = {}
    problems = []
    row_at = None
    row_key = ""
    row_text = ""

    for i, line in enumerate(lines, 1):
        m = re.match(r'\t"((?:[^"\\]|\\.)*)":\s*\[', line)
        if m:
            if row_at is not None:
                problems.extend(_row(row_key, row_at, row_text, width))
            key = m.group(1)
            if key in seen:
                problems.append(
                    f"lang.gd:{i}  the key \"{key}\" is already defined at "
                    f"line {seen[key]} — GDScript refuses the whole file, and "
                    f"every label in the app goes blank")
            else:
                seen[key] = i
            row_at, row_key, row_text = i, key, line
            if line.rstrip().endswith("],"):
                problems.extend(_row(row_key, row_at, row_text, width))
                row_at = None
        elif row_at is not None:
            row_text += line
            if line.rstrip().endswith("],"):
                problems.extend(_row(row_key, row_at, row_text, width))
                row_at = None

    for p in problems:
        print(p)
    print(f"--- {len(problems)} language table problems, in {len(seen)} keys ---")
    return 1 if problems else 0


def _row(key: str, at: int, text: str, width: int) -> list:
    body = text[text.index("[") + 1:text.rindex("]")]
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
    out = []
    if width and len(parts) != width:
        out.append(
            f"lang.gd:{at}  \"{key}\" has {len(parts)} translations, not "
            f"{width} — the missing one shows as a blank button, which reads "
            f"as deliberate")
    for k, part in enumerate(parts):
        if not part.strip():
            out.append(f"lang.gd:{at}  \"{key}\" is empty in language {k}")
    return out


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
