#!/usr/bin/env python3
"""Runs every checker, and fails if any of them does.

One command, so there is no way to run three of the four and ship on the
fourth. Each of these exists because a specific mistake reached the user:

  check_identifiers  — a name left behind after the thing it named was removed
  check_self_calls   — a call to a method of this class that does not exist
  check_warnings     — integer division, shadowed names, a signal nobody raises
  check_returns      — a failure path that gave up with the wrong kind of nothing
  check_continuations— a wrapped line that silently became two statements
  check_shadow       — a second local of a name already taken in the same scope
  check_lambda_capture— a lambda assigning to a local it only captured a copy of
  check_inference    — a `:=` the compiler cannot work out a type for
  check_native_names — a class named the same as one of Godot's own
  check_json_safe    — a value written to the project file that JSON cannot carry
  check_registration — a C++ class written but never handed to Godot
  check_room_buttons — a control built, or connected, but wired to nothing

Usage:  python3 tools/check_all.py [project_dir]
"""

import subprocess
import sys
import pathlib

CHECKS = [
    # First, because it is the only one that checks the *shape* of the file.
    # A file whose indentation is wrong does not parse at all, and every
    # other complaint from it — and from every file that mentions its class —
    # is noise standing in front of the one real fault.
    "check_indent.py",
    "check_const.py",
    "check_identifiers.py",
    "check_scope.py",
    # After check_scope, which resolves names, and before the reference
    # checkers: this one is about unqualified calls, which is the hole those
    # two leave between them.
    "check_self_calls.py",
    # The compiler's own warnings, caught before the compiler sees them.
    "check_warnings.py",
    "check_returns.py",
    "check_continuations.py",
    "check_shadow.py",
    # A lambda writing to a variable it captured by value. It fails silently:
    # the outer variable keeps its initial value and the function returns a
    # confident wrong answer.
    "check_lambda_capture.py",
    # New at stage 145, after an error that stopped the whole project
    # loading: `var x := <something with no type>`. See the file's own
    # header for the three shapes it catches.
    "check_inference.py",
    # Before check_references, because a class that hides a native name
    # poisons every type annotation that mentions it: the reference checker
    # would report a dozen mismatches downstream of one bad declaration.
    "check_native_names.py",
    "check_references.py",
    "check_native_compile.py",
    # After the compile check, because a class that does not compile cannot
    # meaningfully be said to be registered or not.
    "check_registration.py",
    # Rooms. A button that is built and never connected parses perfectly and
    # passes every check above it, which is exactly how the reference room
    # shipped without a delete button.
    "check_room_buttons.py",
    "check_input_routing.py",
    # A Vector2 or a byte buffer written into the project file. JSON cannot
    # carry either, and the Vector2 case stops the app opening.
    "check_json_safe.py",
    "check_lang.py",
    "check_stretchy_export.py",
    "check_size.py",
    "ivory_20_guard.py",
]


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    here = pathlib.Path(__file__).parent
    failed = []
    for name in CHECKS:
        script = here / name
        if not script.exists():
            print("MISSING CHECKER: %s" % name)
            failed.append(name)
            continue
        print("== %s" % name)
        result = subprocess.run(
            [sys.executable, str(script), root], capture_output=False
        )
        if result.returncode != 0:
            failed.append(name)
    print()
    if failed:
        print("FAILED: %s" % ", ".join(failed))
        return 1
    print("All %d checks passed." % len(CHECKS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
