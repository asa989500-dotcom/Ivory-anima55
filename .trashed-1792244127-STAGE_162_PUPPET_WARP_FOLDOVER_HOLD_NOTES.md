# IVORY Stage 162 — Puppet Warp: hold the last good pose, don't reset to rest

## What was wrong

All three puppet-warp solvers — the GDScript fallback, the native `IvoryWarp`
fast path, and the native `IvoryArapSolver` forge path — guard against a
triangle turning inside-out during a hard drag (`prevent_foldover` /
`mesh_is_valid`). When a step could not be backed off because even its
*starting* point was already invalid, the guard's answer was to reset the
**entire mesh to its rest pose**, discarding every pin's work for a fault
that touched one triangle. On screen this reads as the drawing snapping back
to its undeformed shape in the middle of a drag — the tool visibly failing to
hold a pose the moment anything went wrong.

`IvoryArapSolver` — the primary solve path when the native extension is
built — had no fold-over guard at all. Nothing stopped a triangle inverting
under an aggressive drag; `test_nothing_turns_inside_out` explicitly tolerated
some triangles flipping ("what must not happen is the whole sheet turning
over").

## What changed

- Added a fold-over guard to `IvoryArapSolver`, mirroring `IvoryWarp`'s: rest
  triangle areas and a degeneracy floor computed once in `set_mesh`, a
  `mesh_is_valid()` check, and `prevent_foldover()` run after every
  Gauss-Seidel sweep in `solve()`.
- All three solvers now keep a `last_good_` / `_last_good_v` snapshot — the
  most recent pose verified sound — and fall back to *that* instead of rest
  when a step can't be salvaged. Falling back to rest is now reserved for the
  genuine "there is no other sound state" case (mesh just built, no pins).
- `set_positions` / `set_pose` (native) update the fallback snapshot too, so
  a warm-started pose is trusted only if it is actually valid.

## Verified

- `native/ivory/tests/test_arap.cpp`: `test_nothing_turns_inside_out` now
  asserts zero inverted triangles (was: fewer than a fifth). Added
  `test_foldover_holds_the_last_good_pose`, which checks a hard corner-swap
  drag leaves the mesh visibly bent rather than sitting at `rest`.
- Added `tests/test_puppet_warp_foldover.gd`, exercising the pure-GDScript
  path the same way, and registered it in `tests/run_tests.gd`.

Not verified here: this checkout has no `godot-cpp` vendored and no network
access to fetch it, so the native changes could not actually be compiled.
Run `scons` under `native/ivory` (see `BUILD_NATIVE_STAGE150.md`) and the two
test suites above before shipping.

## What is not here

Touch handling (tap to pin, drag, tap-twice to remove, hold to anchor, the
turn ring) was already fully wired in `canvas_view.gd` / `puppet_warp_pins.gd`
before this stage — nothing was added there. Photoshop's own Puppet Warp
implementation (Delaunay triangulation, a sparse Cholesky factorisation,
CUDA) was deliberately not ported: it is a different mesh representation and
a different toolchain than this project uses, and adopting it here would be
a regression, not a fix — this project's mesh already follows the ink itself
and measures distance by walking it rather than in a straight line, which is
strictly better for non-blob shapes than the bounding-box grid Photoshop's
description assumes.
