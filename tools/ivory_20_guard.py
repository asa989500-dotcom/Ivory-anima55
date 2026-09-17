#!/usr/bin/env python3
"""Twenty focused source/boundary guards for IVORY Stage 150.

This is deliberately independent of a running Godot editor. It catches the
same class of faults that caused the current crash: delegate signatures,
optional native classes, optional GDExtensions, native registration, and the
20 runtime integrity instruments exposed by IvoryGuard20.
"""
from __future__ import annotations
import pathlib, re, subprocess, shutil, sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
FAIL = []

def need(cond: bool, msg: str) -> None:
    if not cond:
        FAIL.append(msg)

cv = (ROOT / "scripts/canvas_view.gd").read_text()
vd = (ROOT / "scripts/canvas_view_draw.gd").read_text()
vp = (ROOT / "addons/gde_gozen/video_playback.gd").read_text()
pl = (ROOT / "addons/gde_gozen/plugin.gd").read_text()
native = (ROOT / "scripts/native.gd").read_text()
reg = (ROOT / "native/ivory/src/register_types.cpp").read_text()
h20 = (ROOT / "native/ivory/src/ivory_guard20.h").read_text()
c20 = (ROOT / "native/ivory/src/ivory_guard20.cpp").read_text()

checks = [
    ("delegate_argument", "CanvasViewDraw.draw_layer_rig(self)" in cv),
    ("delegate_signature", "static func draw_layer_rig(host: CanvasView)" in vd),
    ("gozen_untyped_video", "var video: Object = null" in vp and "GoZenVideo =" not in vp),
    ("gozen_dynamic_video", 'ClassDB.instantiate("GoZenVideo")' in vp),
    ("gozen_dynamic_audio", 'ClassDB.instantiate("AudioStreamFFmpeg")' in vp),
    ("gozen_plugin_gate", 'ClassDB.class_exists("GoZenVideo")' in pl),
    ("native_bridge_guard", '"IvoryGuard20"' in native and "_known" in native),
    ("native_bridge_factory", 'ClassDB.instantiate("IvoryGuard20")' in native),
    ("guard20_registered", "GDREGISTER_CLASS(IvoryGuard20);" in reg),
    ("guard20_header", "class IvoryGuard20" in h20),
    ("guard20_impl", "IvoryGuard20::aggregate" in c20),
    ("gde_disabled_main", not (ROOT / "ivory.gdextension").exists()),
    ("gde_disabled_gozen", not (ROOT / "addons/gde_gozen/gozen.gdextension").exists()),
    ("guard_count_20", len(re.findall(r'IvoryGuard20::', c20)) >= 20),
    ("guard_mesh", "mesh_topology" in h20 and "mesh_topology" in c20),
    ("guard_skin", "skin_weights" in h20 and "skin_weights" in c20),
    ("guard_bones", "bone_hierarchy" in h20 and "bone_hierarchy" in c20),
    ("guard_io", "pixel_buffer" in h20 and "export_settings" in c20),
    ("guard_touch_audio", "touch_stream" in h20 and "audio_sync" in c20),
    ("guard_memory", "memory_budget" in h20 and "memory_budget" in c20),
]
for name, ok in checks:
    need(ok, name)
    print(f"{'OK  ' if ok else 'FAIL'} {name}")

compiler = shutil.which("g++") or shutil.which("clang++")
if compiler:
    cmd = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Wpedantic", "-fsyntax-only",
           "-Inative/stub", "-Inative/ivory/src", "native/ivory/src/ivory_guard20.cpp"]
    p = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    need(p.returncode == 0, "guard20_cpp_syntax")
    print("OK  guard20_cpp_syntax" if p.returncode == 0 else "FAIL guard20_cpp_syntax")
else:
    print("SKIP guard20_cpp_syntax (no C++ compiler)")

print(f"--- {len(checks)} source guards, {len(FAIL)} failures ---")
if FAIL:
    print("FAILED: " + ", ".join(FAIL))
    raise SystemExit(1)
print("All 20 guard targets passed.")
