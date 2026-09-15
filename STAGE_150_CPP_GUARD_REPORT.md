# IVORY Stage 150 — CPP Guard / parser hardening

## Defects fixed in this pass

1. `scripts/canvas_view.gd:2886` now forwards `self` into
   `CanvasViewDraw.draw_layer_rig(self)`. This removes the exact parse error
   shown in the editor: `Too few arguments ... Expected at least 1`.
2. `addons/gde_gozen/video_playback.gd` no longer statically types optional
   `GoZenVideo` / `AudioStreamFFmpeg` classes. It resolves them through
   `ClassDB.instantiate()` and checks for absence before use.
3. `addons/gde_gozen/plugin.gd` only registers `VideoPlayback` when the native
   `GoZenVideo` class is really loaded.
4. The absent native `.so` manifests are no longer auto-loaded in a source
   checkout. The original manifests are preserved as `.disabled` files so a
   real native build can be enabled without reconstructing them by hand.

## C++ integrity layer

`native/ivory/src/ivory_guard20.{h,cpp}` adds 20 deterministic native guards:

1. mesh topology
2. finite geometry
3. triangle area / degeneracy
4. pose displacement
5. pin-to-vertex binding
6. pin finite values
7. bounds containment
8. skin-weight validity / normalization
9. bone hierarchy / cycle detection
10. transformed-point finiteness
11. symmetry settings
12. timeline frame indexes
13. frame-time budget
14. texture extent
15. pixel-buffer byte stride
16. touch-stream continuity
17. audio/video duration drift
18. export settings
19. native-memory budget
20. aggregate health

The class is registered in `register_types.cpp` and exposed to GDScript through
`scripts/native.gd` as `Native.guard20()`.

`scripts/ivory_guard.gd` provides a single sweep entry point that runs the 20
native instruments together.

## Verification performed in this environment

- Existing static project checker: **16/16 passed**.
- Native C++ syntax checker: **0 errors** on all existing native units.
- New `IvoryGuard20` C++ syntax check: **passed** with `-std=c++17 -Wall -Wextra -Wpedantic` against the project's native stub.
- New 20-target source guard: **20/20 passed**.

## Important release note

This archive does not fabricate Android `.so` binaries. The Android ARM64
GDExtension must still be compiled with the project's real Godot-C++ / Android
NDK toolchain before the C++ classes can execute on the device. Until then,
the application deliberately uses its existing GDScript fallbacks instead of
crashing because a library is missing.
