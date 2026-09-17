#!/usr/bin/env python3
"""Regression checks for the canvas input-routing fix.

The reported failure was global: brush, fill, selection and other canvas tools
all appeared dead. The common cause was a full-screen dismiss Control consuming
presses before CanvasView could see them. This checker guards the ownership
contract so the fix cannot silently regress during UI work.
"""
from pathlib import Path
import re
import sys


def fail(msg: str) -> None:
    print(f"FAIL: {msg}")
    raise SystemExit(1)


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    main_gd = (root / "scripts/main.gd").read_text(encoding="utf-8")
    canvas_gd = (root / "scripts/canvas_view.gd").read_text(encoding="utf-8")

    # 1) The full-screen shade must be non-interactive.
    shade = re.search(
        r'_shade\s*=\s*Control\.new\(\).*?(?=\n\t(?:_ai_wait|_build_rail|view\.|$))',
        main_gd, re.S,
    )
    if not shade:
        fail("could not locate shade setup")
    if "MOUSE_FILTER_STOP" in shade.group(0):
        fail("full-screen shade still stops mouse/touch input")
    if "MOUSE_FILTER_IGNORE" not in shade.group(0):
        fail("shade does not explicitly ignore input")

    # 2) Dismissal must happen in _input, not by swallowing CanvasView events.
    input_block = re.search(r'func _input\(event: InputEvent\) -> void:(.*?)(?=\nfunc |\Z)', main_gd, re.S)
    if not input_block:
        fail("MainRoom._input is missing")
    body = input_block.group(1)
    if "_close_panel()" not in body:
        fail("panel dismissal was not moved into _input")
    if "get_global_rect().has_point" not in body:
        fail("panel hit-test is missing")

    # 3) CanvasView must still own the real drawing event path.
    if "func _gui_input(event: InputEvent) -> void:" not in canvas_gd:
        fail("CanvasView GUI input path disappeared")
    for token in ("_handle_touch", "_handle_drag", "_begin_input", "_end_input"):
        if token not in canvas_gd:
            fail(f"CanvasView input path lost {token}")

    # 4) The critical tools still have explicit input branches. Brush reaches
    # the stroke path as the default after the special tools return.
    for token in ("Tool.FILL", "Tool.SHAPE", "Tool.SELECT", "Tool.PICK", "Tool.ERASER"):
        if token not in canvas_gd:
            fail(f"canvas tool route missing {token}")
    if "_begin_stroke(w)" not in canvas_gd or "_do_fill(w)" not in canvas_gd:
        fail("basic stroke/fill execution path is incomplete")

    print("PASS: input routing guard — shade cannot swallow canvas input")
    print("PASS: panel dismissal is pre-GUI and event-preserving")
    print("PASS: CanvasView touch/mouse paths and core tool routes are present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
