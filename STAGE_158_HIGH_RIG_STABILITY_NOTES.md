# IVORY Stage 158 — High Rig Stability / Character 360 / Warp

- Added native `IvoryStability`: deadband, critically-damped point following, finite-speed/acceleration caps, hard chain-length sanitization and diagnostics.
- `IvoryBonePose` now exposes stability configuration/reporting and guards large target jumps while preserving exact bone-length relaxation.
- Character 360 member layers now carry explicit `master_rig` + `local_rig_enabled` metadata and the bone handle propagates the master pose to every raster member in the same Character 360 group without copying/baking pixels.
- Character 360 remains PNG/reference-driven; its motion layer remains controller-only.
- Character 360 bone display palette changed to navy-blue shades.
- Existing native Puppet Warp already enforces drawing bounds and foldover prevention; this stage leaves those safeguards intact rather than adding a competing solver.
- Added native registration and GDScript discovery for `IvoryStability`.
