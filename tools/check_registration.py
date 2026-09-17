#!/usr/bin/env python3
"""Every C++ class that exists is registered, and every registration is real.

`register_types.cpp` cannot be compiled here — it includes
<gdextension_interface.h>, which only exists in a real godot-cpp checkout — so
`check_native_compile.py` skips it. That left a gap: a class could be written,
compile perfectly, and never be handed to Godot, and nothing would say so. The
symptom is quiet and confusing, because `scripts/native.gd` asks ClassDB
whether the class exists, gets no, and silently runs the GDScript fallback. The
C++ is simply never used and the app is slower for no visible reason.

Two directions are checked, because each catches a different mistake:

  * a class declared with GDCLASS in a header but never registered — the class
    was written and then forgotten;
  * a registration naming a class that no header declares — a rename or a
    deletion that left the registration behind, which fails at load time.

Run with no arguments from the project root.
"""

import pathlib
import re
import sys

GDCLASS = re.compile(r"^\s*GDCLASS\(\s*(\w+)\s*,", re.M)
REGISTER = re.compile(r"GDREGISTER_(?:ABSTRACT_)?CLASS\(\s*(\w+)\s*\)")
INCLUDE = re.compile(r'^\s*#include\s+"([\w./]+\.h)"', re.M)


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    src = root / "native" / "ivory" / "src"
    if not src.is_dir():
        print("--- registration checker skipped: no native sources ---")
        return 0

    reg_path = src / "register_types.cpp"
    if not reg_path.exists():
        print("ERROR: native/ivory/src/register_types.cpp is missing")
        return 1
    reg_text = reg_path.read_text(encoding="utf-8", errors="replace")

    declared: dict[str, str] = {}
    for header in sorted(src.glob("*.h")):
        for name in GDCLASS.findall(header.read_text(encoding="utf-8", errors="replace")):
            declared[name] = header.name

    registered = set(REGISTER.findall(reg_text))
    included = set(INCLUDE.findall(reg_text))

    problems = 0

    for name in sorted(declared):
        if name not in registered:
            print(f"ERROR: {name} is declared in {declared[name]} but never registered")
            problems += 1
            continue
        if declared[name] not in included:
            # It compiles today only because another header pulls it in. That
            # is the kind of thing that breaks on an unrelated cleanup.
            print(f"ERROR: {name} is registered but {declared[name]} is not included directly")
            problems += 1

    for name in sorted(registered):
        if name not in declared:
            print(f"ERROR: {name} is registered but no header declares it")
            problems += 1

    print(f"--- {len(declared)} native classes, {problems} registration problems ---")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
