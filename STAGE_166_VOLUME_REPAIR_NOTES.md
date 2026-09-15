# Stage 166 — Closing the seam between two bones (volume repair)

## Where this sits

Stage 145 gave the bone skin (`RigSkin.bone_rule`, mirrored in
`native/ivory/src/ivory_skin.cpp::IvorySkin::deform`) a rotation-preserving
blend instead of the naive average-the-positions-each-bone-wants one. That
fixed the famous fault: averaging *positions* is a straight line between
them, and a straight line between two points on a circle passes inside it, so
flesh at a joint got dragged toward the joint as it bent, collapsing outright
past about 150°. Rotating one offset by one averaged angle cannot shorten it,
full stop, and that fault is gone. It is documented at length in
`scripts/rig_skin.gd`, with measured numbers on a test ring.

That fix is exact for a point dominated by one bone. It says nothing about a
point that is influenced by *two* bones at once, which is every point near a
joint — the whole reason a joint needs more than one bone. This stage closes
that second, smaller gap.

## The fault this stage fixes

Where two bones' influence overlaps, a point's anchor is a weighted average
of two moving anchors. Two things converging on average can close faster
than either one alone moved — the same reason the midpoint between two
people walking toward each other closes faster than either person's own
stride. The flesh keeps its *exact* offset from that anchor (that part is
still exact — see above), but the anchor itself has been pulled in, so the
flesh is carried in with it. The result is a local thinning right at the
seam between two bones, worst exactly where a joint is bent hardest — a
squeeze at the elbow or knee crease rather than the collapse-to-a-point
stage 145 already removed. Smaller, and still visible, and still real: it
shows up as a mild "pinch" a puppeteer would call unrealistic even once the
gross candy-wrapper fault is gone.

## What was added

`IvorySkin::preserve_volume` (`native/ivory/src/ivory_skin.cpp`), called
from `RigSkin.pose_bones` in `scripts/rig_skin.gd` immediately after
`deform`, when the native skin is present.

It measures, once, how far each point's own little patch of mesh has moved
from its rest area — a third of every incident triangle's rest area versus
the same triangles' current area, the standard mixed-Voronoi stand-in for a
per-vertex area that a roughly-regular grid makes exact enough to skip
anything fancier. That gives a per-point target linear scale (area scales as
the square of a linear expansion, so the correction takes a square root).

It then runs a small, fixed number of **Jacobi passes** — read every point's
old position, write a fresh array, swap — pulling each point toward or away
from the current centroid of its own direct mesh neighbours by its target
scale. This is deliberately *not* a solve run to convergence, unlike the
puppet warp's full ARAP solve in `ivory_arap.h`. The puppet warp re-solves on
a drag, a user action with slack for a few milliseconds of linear algebra.
This runs every frame a pose plays, so it is priced like the rest of
`deform`: a fixed, small, bounded amount of arithmetic, not an iterative
solve to a tolerance.

Islands are respected exactly as they are in `deform`: a point's mesh
neighbours are filtered to its own island before the centroid is taken, so
this pass can no more pull one drawing toward another than a bone can move
flesh across the boundary `read_islands` found.

### Tuning knobs

Two constants in `RigSkin`:

- `VOLUME_REPAIR_STRENGTH` (0.55) — how much of the computed correction is
  actually applied, from 0 (off) to 1 (fully restore local area). Left below
  1 deliberately: at 1.0 a lightly-bent pose where nothing is actually wrong
  gets nudged anyway by whatever noise is in the area measurement, and the
  repair should be felt at a hard bend and unnoticeable at a gentle one, not
  a constant background hum.
- `VOLUME_REPAIR_PASSES` (2) — Jacobi passes per pose. More lets a
  correction reach further across the mesh per frame; two was enough in
  testing to visibly close a two-bone seam without the cost approaching the
  main deform pass.

Both are read every `pose_bones` call, so a future settings panel can expose
either without touching this file again.

### No GDScript fallback, by design

Every other native routine in this codebase (`deform`, `read_islands`, the
smart-bone dials, and so on) has a GDScript equivalent that a build without
the compiled library falls back to — see the comment at the top of
`RigSkin._read_islands` and `Native.skin()`. `preserve_volume` does not. A
Jacobi correction pass over roughly a thousand points, run two or more times
a pose, several times a second, is precisely the per-point-per-frame
GDScript cost the native half of this file exists to avoid; adding a
GDScript version would reintroduce the exact problem stage 145's own doc
comment describes for `deform` itself. Its absence is safe: without it, a
pose is exactly what `deform` alone already produced — correct for one bone,
mildly thin at a seam between two, which is what every build had before this
stage.

## Validation

`native/ivory/tests/test_skin.cpp`, new this stage (the bone skin previously
had no dedicated native test — `deform` was exercised only indirectly through
higher-level tests). Registered in `tools/run_native_tests.sh`.

- **`test_single_bone_bend_matches_documented_numbers`** — reproduces the
  measurement quoted in `RigSkin.bone_rule`'s own doc comment (a ring drawn
  twenty units from a joint, bent 30°/90°/150°/179°) as a regression: the
  ring's minimum radius must stay above a floor at each bend, so a future
  change cannot silently reintroduce the collapse stage 145 fixed.
- **`test_rigid_whole_skin_move_is_exact`** — a bone translated with no
  rotation must translate the whole skin exactly; a rigid motion has zero
  excuse to distort anything.
- **`test_preserve_volume_closes_the_seam`** — a two-bone strip bent 120° at
  the shared joint; asserts the seam is measurably compressed before the
  repair (so the test is actually exercising the fault) and measurably
  closer to an area ratio of 1.0 after it.
- **`test_preserve_volume_leaves_an_unbent_skin_alone`** — a mesh already at
  its rest shape must not be moved by the repair; a correction that fires on
  nothing wrong is its own bug.
- **`test_preserve_volume_respects_islands`** — compressing one island must
  not move a point on a different island.

Full suite: `bash tools/run_native_tests.sh` — 19 translation units, all
passing, `test_skin` included (15 checks, 0 failures; whole suite unaffected
and still green). Compiled against the local stub headers
(`native/stub/godot_cpp`) with `g++ -std=c++17 -Wall -Wextra`, no warnings
from the new code beyond one unused parameter in an unrelated test helper
left over for a future bend-angle-varying elbow test. As with stage 165, a
full compile against real `godot-cpp` headers is not something this archive
can claim, since those headers are not vendored here; what is claimed is a
clean compile and a passing run against the stub the rest of this test suite
already relies on.

## What this does not claim to fix

This is a local, per-frame *repair*, not a physically simulated material —
it is closer in spirit to the puppet warp's ARAP energy than to `deform`'s
exact single-bone rotation, but far cheaper and therefore approximate. It
will not perfectly preserve area under an extreme, whole-limb-folded pose the
way a full iterative solve would; `VOLUME_REPAIR_STRENGTH` and
`VOLUME_REPAIR_PASSES` trade cost for how far it reaches. For anything beyond
a bone rig's ordinary range of motion, the puppet warp room (backed by the
full ARAP solve) remains the tool for a deliberately extreme pose.
