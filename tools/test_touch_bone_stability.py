#!/usr/bin/env python3
"""Source-level regression checks for the Stage 168 input hardening."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOUCH_H = (ROOT / "native/ivory/src/ivory_touch.h").read_text()
TOUCH_CPP = (ROOT / "native/ivory/src/ivory_touch.cpp").read_text()
BONE = (ROOT / "scripts/ui/bone_handle.gd").read_text()
LEAD = (ROOT / "scripts/touch_lead.gd").read_text()
STROKE = (ROOT / "scripts/stroke_smoother.gd").read_text()
SKIN = (ROOT / "scripts/rig_skin.gd").read_text()
checks = 0
failures = []

def ok(name, condition):
    global checks
    checks += 1
    if not condition:
        failures.append(name)
        print("FAIL:", name)

ok("C++ deadband API", "deadband_px" in TOUCH_H and "set_deadband" in TOUCH_H)
ok("C++ deadband binding", '"set_deadband"' in TOUCH_CPP)
ok("deadband before derivative", "sample = value_" in TOUCH_CPP and ("raw_speed = (sample - raw_last_)" in TOUCH_CPP or "raw_delta = sample - raw_last_" in TOUCH_CPP))
ok("deadband is bounded", "std::min(std::max(pixels, 0.0), 8.0)" in TOUCH_CPP)
ok("legacy configure remains", "double lead_ms, double deadband_px" in TOUCH_H)
ok("bone deadband configured", "MOTION_EPS_PX)" in BONE)
ok("bone deadband is screen-space", "screen-space deadband" in BONE)
ok("TouchLead forwards deadband", "deadband_px)" in LEAD)
ok("drawing uses smaller quiet zone", "TOUCH_DEADBAND_PX: float = 0.25" in STROKE)
ok("drawing has native deadband", "TOUCH_DEADBAND_PX)" in STROKE)
ok("drawing has fallback deadband", "raw.distance_to(_prev) <= TOUCH_DEADBAND_PX" in STROKE)
ok("images bind through layer surface", "l.surface.content_bounds()" in SKIN and
   "l.surface.read_region(box)" in SKIN)
ok("skin is non-destructive", "surface is hidden while it is showing" in SKIN and
   "Nothing" in SKIN and "is written to the layer" in SKIN)

print(f"TOUCH/BONE STABILITY / {checks} CHECKS / {len(failures)} FAILURES")
if failures:
    raise SystemExit(1)
print("ALL TOUCH/BONE STABILITY CHECKS PASSED")
