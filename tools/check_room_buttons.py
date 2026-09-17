#!/usr/bin/env python3
"""Every control a room builds is named, connected, and listed in its manifest.

The reference room had a button that could not be pressed because it was never
added, a strip with no delete button at all, and no way for anyone to find out
except by opening the room and looking. This reads the source instead.

Three faults are caught, and each of them shipped at least once:

  * a control created and added to the tree but never `.connect`ed — it looks
    right, it highlights when you touch it, and nothing happens;
  * a control connected to a method that does not exist on the class — Godot
    reports this at connect time, deep in a stack trace, if the code path runs
    at all;
  * a control missing from `control_manifest()` — the room's own device 14
    then reports a clean bill of health for a room with a dead button in it,
    which is worse than having no check.

Only files that define a `control_manifest()` are examined, so this costs
nothing until a room opts in by writing one.

Run with no arguments from the project root.
"""

import pathlib
import re
import sys

BUTTON = re.compile(r"^\s*(?:var\s+)?(\w+)(?:\s*:\s*\w+)?\s*=\s*UiKit\.make_text_button\(", re.M)
NAMED = re.compile(r"^\s*(\w+)\.name\s*=\s*\"([^\"]+)\"", re.M)
CONNECT = re.compile(r"^\s*(\w+)\.(\w+)\.connect\(\s*(\w+)", re.M)
FUNCS = re.compile(r"^func\s+(\w+)\s*\(", re.M)


def manifest_body(text: str) -> str:
    """The text of control_manifest(), so entries can be looked for inside it.

    Parsing the argument list properly is not worth it — `find_child("X", true,
    false)` has commas inside it and a naive split gets the wrong field. What
    matters is only whether the control is referred to at all, by its node name
    or by the member variable holding it, so the body is searched as text.
    """
    at = text.find("func control_manifest")
    if at < 0:
        return ""
    end = text.find("\nfunc ", at + 1)
    return text[at:end if end > 0 else len(text)]


def check_file(path: pathlib.Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace")
    if "func control_manifest" not in text:
        return 0

    rel = path.as_posix()
    problems = 0

    made = set(BUTTON.findall(text))
    named = dict(NAMED.findall(text))
    connected = {}
    for var, signal, handler in CONNECT.findall(text):
        connected.setdefault(var, []).append((signal, handler))
    methods = set(FUNCS.findall(text))

    # 1. A button that exists but is wired to nothing.
    for var in sorted(made):
        if var not in connected:
            line = _line_of(text, f"{var} = UiKit.make_text_button")
            print(f"{rel}:{line}  the button '{var}' is never connected to anything")
            problems += 1

    # 2. A handler that is not a method on this class. Lambdas and bound
    # callables are skipped; only a bare identifier is checked, because that
    # is the form that fails silently at connect time.
    for var, pairs in sorted(connected.items()):
        for signal, handler in pairs:
            if handler.startswith("func") or handler in ("self",):
                continue
            if handler not in methods:
                line = _line_of(text, f"{var}.{signal}.connect({handler}")
                print(f"{rel}:{line}  '{var}' connects to '{handler}', which is not a method here")
                problems += 1

    # 3. An interactive control absent from the manifest device 14 reads.
    # Only controls that are connected to something are required: a strip
    # container or a read-only count label is not a control anyone can press,
    # and demanding a manifest row for it would teach the reader to pad the
    # manifest rather than to keep it honest.
    body = manifest_body(text)
    for var, control_name in sorted(named.items()):
        if var not in connected:
            continue
        if control_name.startswith("Remove_"):
            # The strip's delete buttons are created per pose and named with
            # their index; they are covered by the room's own test rather than
            # by a fixed manifest entry.
            continue
        if f'"{control_name}"' not in body and not re.search(rf"\b{re.escape(var)}\b", body):
            line = _line_of(text, f'{var}.name = "{control_name}"')
            print(f"{rel}:{line}  the control '{control_name}' is not in control_manifest()")
            problems += 1

    return problems


def _line_of(text: str, needle: str) -> int:
    at = text.find(needle)
    if at < 0:
        return 0
    return text.count("\n", 0, at) + 1


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    problems = 0
    rooms = 0
    for path in sorted((root / "scripts").rglob("*.gd")):
        text = path.read_text(encoding="utf-8", errors="replace")
        if "func control_manifest" in text:
            rooms += 1
        problems += check_file(path)
    print(f"--- {rooms} rooms with a control manifest, {problems} problems ---")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
