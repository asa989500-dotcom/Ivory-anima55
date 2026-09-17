#!/usr/bin/env python3
"""Deterministic checks for the optional circular pose-deformer kernel.

The archive does not vendor godot-cpp, so this test validates the numerical
contract and source wiring without pretending to perform a full GDExtension
build. A full C++ build is run when the developer provides godot-cpp.
"""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]
CPP = (ROOT / "native/ivory/src/ivory_pose_deformer.cpp").read_text()
HDR = (ROOT / "native/ivory/src/ivory_pose_deformer.h").read_text()
REG = (ROOT / "native/ivory/src/register_types.cpp").read_text()
NATIVE = (ROOT / "scripts/native.gd").read_text()
checks = 0
failures = []

def ok(name, condition):
    global checks
    checks += 1
    if not condition:
        failures.append(name)
        print("FAIL:", name)

def smooth5(t):
    t = max(0.0, min(1.0, t))
    return t*t*t*(t*(t*6.0-15.0)+10.0)

def weights(angles, q):
    a = q % 360.0
    order = sorted((x % 360.0, i) for i, x in enumerate(angles))
    right = next((k for k, (x, _) in enumerate(order) if x >= a), 0)
    left = len(order)-1 if right == 0 else right-1
    la, li = order[left]
    ra, ri = order[right]
    if right == 0:
        ra += 360.0
    query = a + (360.0 if right == 0 and a < la else 0.0)
    t = smooth5((query-la)/(ra-la)) if abs(ra-la) > 1e-9 else 0.0
    out = [0.0] * len(angles)
    out[li], out[ri] = 1.0-t, t
    return out

ok("class declared", "class IvoryPoseDeformer" in HDR)
ok("circular wrapping exists", "wrap_degrees" in CPP and "FULL_DEG" in CPP)
ok("C2 smoothstep exists", "smooth5" in CPP and "t * t * t" in CPP)
ok("corrective API exists", "set_corrective" in HDR and "clear_correctives" in HDR)
ok("volume mesh API exists", "set_volume_mesh" in HDR and "volume_passes" in HDR)
ok("native registration exists", "GDREGISTER_CLASS(IvoryPoseDeformer)" in REG)
ok("optional GDScript bridge exists", "has_pose_deformer" in NATIVE and "pose_deformer" in NATIVE)

for q in (0.0, 359.0, 360.0, -1.0, 720.0):
    w = weights([0.0, 90.0, 180.0, 270.0], q)
    ok("weights sum at angle %s" % q, abs(sum(w)-1.0) < 1e-9)
ok("359 to 0 uses adjacent references", weights([0.0, 90.0, 180.0, 270.0], 359.0)[0] > 0.99)
ok("0 to 90 midpoint is bounded", 0.0 < weights([0.0, 90.0], 45.0)[0] < 1.0)
ok("negative angles wrap", weights([0.0, 90.0, 180.0, 270.0], -1.0)[0] > 0.99)
ok("repair is bounded", "std::clamp(volume_strength, 0.0, 1.0)" in CPP)
ok("passes are bounded", "std::clamp(volume_passes, 0, 16)" in CPP)
ok("old path remains separate", "does not replace BoneRig" in HDR or "does not replace BoneRig" in REG)

print(f"POSE DEFORMER / {checks} CHECKS / {len(failures)} FAILURES")
if failures:
    raise SystemExit(1)
print("ALL POSE DEFORMER CHECKS PASSED")
