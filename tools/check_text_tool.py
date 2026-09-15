#!/usr/bin/env python3
"""Static guardrails for IVORY's text-object interaction path."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
cv = (root / "scripts/canvas_view.gd").read_text(encoding="utf-8")
nt = (root / "scripts/native.gd").read_text(encoding="utf-8")
reg = (root / "native/ivory/src/register_types.cpp").read_text(encoding="utf-8")
cpp = (root / "native/ivory/src/ivory_text_tool.cpp").read_text(encoding="utf-8")
tr = (root / "scripts/text_render.gd").read_text(encoding="utf-8")

checks = {
    "native class registered": 'GDREGISTER_CLASS(IvoryTextTool);' in reg,
    "native factory present": '"IvoryTextTool"' in nt and 'func text_tool()' in nt,
    "native preview transform": 'preview_transform' in cpp,
    "native anchored resize": 'const Vector2 carried = to + (grabbed - from);' in cpp,
    "text hold avoids tile bounds": 'var box: Rect2i = l.surface.content_bounds()' not in cv,
    "live surface preview": 'l.surface.position = tr["position"]' in cv,
    "live surface scale": 'l.surface.scale = Vector2.ONE * float(tr["scale"])' in cv,
    "live surface rotation": 'l.surface.rotation = float(tr["rotation"])' in cv,
    "single render wait": tr.count('await RenderingServer.frame_post_draw') == 1,
    "seven-test case": 'test_text_tool.gd' in (root / 'tests/run_tests.gd').read_text(encoding='utf-8'),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + '  ' + name)
if failed:
    raise SystemExit(1)
print(f"PASS  {len(checks)}/{len(checks)} text guardrails")
