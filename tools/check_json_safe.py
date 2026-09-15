#!/usr/bin/env python3
"""A value that JSON cannot carry, written into the project file.

`vault.gd` saves with `JSON.stringify`, and JSON has four types: string,
number, boolean, and containers of those. Everything else is converted on the
way out, whether the author meant it to be or not:

  * a **Vector2** becomes the string `"(12, 34)"`. Reading it back into a typed
    property throws —

        Invalid assignment of property or key 'motion_position' with value of
        type 'String' on a base object of type 'RefCounted (Layer)'

    — and because that happens inside the loader, the project does not open.
    That is exactly what stage 152 shipped, and it is why this checker exists.

  * a **PackedByteArray** survives as an array of several hundred thousand
    numbers. Nothing throws. The file is tens of megabytes, loading is slow,
    and the code that expected bytes gets an `Array`. Quieter and worse.

  * a **Color**, a **Vector2i**, a **PackedFloat32Array** — same story.

So this reads the declared type of every `Layer` field in `layer_stack.gd`, and
then checks each `"key": l.field` written into a row in `vault.gd`. A field of
a JSON-hostile type must go through a converter — `_vec_to_doc`, `_rig_to_doc`,
`_c360_to_doc` or another function — rather than straight into the document.

Run with no arguments from the project root.
"""

import pathlib
import re
import sys

# Godot types JSON cannot represent, and what each one turns into if it is
# written anyway.
HOSTILE = {
    "Vector2": 'the string "(x, y)"',
    "Vector2i": 'the string "(x, y)"',
    "Vector3": 'the string "(x, y, z)"',
    "Rect2": "a string",
    "Rect2i": "a string",
    "Color": "a string",
    "Transform2D": "a string",
    "PackedByteArray": "an array of every byte",
    "PackedInt32Array": "a plain Array",
    "PackedFloat32Array": "a plain Array",
    "PackedVector2Array": "a plain Array of strings",
    "PackedStringArray": "a plain Array",
}

FIELD = re.compile(r"^\s*var\s+(\w+)\s*:\s*(\w+)", re.M)
# `"key": l.field` or `row["key"] = l.field`, with nothing wrapped round it.
BARE_PAIR = re.compile(r'"(\w+)"\s*:\s*(\w+)\.(\w+)\s*[,}]')
BARE_SET = re.compile(r'^\s*\w+\[\s*"(\w+)"\s*\]\s*=\s*(\w+)\.(\w+)\s*$')


def layer_fields(root: pathlib.Path) -> dict:
    """Every `Layer` property and its declared type."""
    path = root / "scripts" / "layer_stack.gd"
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    # Only the inner Layer class, which is where the saved fields live.
    at = text.find("class Layer")
    if at < 0:
        at = 0
    end = text.find("\nclass ", at + 1)
    body = text[at:end if end > 0 else len(text)]
    return {m.group(1): m.group(2) for m in FIELD.finditer(body)}


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    fields = layer_fields(root)
    vault = root / "scripts" / "vault.gd"
    if not fields or not vault.exists():
        print("--- JSON safety checker skipped: nothing to read ---")
        return 0

    problems = 0
    for i, raw in enumerate(vault.read_text(encoding="utf-8", errors="replace").split("\n"), 1):
        line = re.sub(r"#.*$", "", raw)
        for pattern in (BARE_PAIR, BARE_SET):
            for m in pattern.finditer(line):
                key, obj, field = m.group(1), m.group(2), m.group(3)
                if obj not in ("l", "layer"):
                    continue
                kind = fields.get(field)
                if kind in HOSTILE:
                    print(f"{vault.as_posix()}:{i}  '{key}' writes {field}, which is a "
                          f"{kind}. JSON stores it as {HOSTILE[kind]}, and it will not "
                          f"read back. Convert it on the way out.")
                    print(f"    {raw.strip()}")
                    problems += 1

    print(f"--- {len(fields)} layer fields checked, {problems} that JSON cannot carry ---")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
