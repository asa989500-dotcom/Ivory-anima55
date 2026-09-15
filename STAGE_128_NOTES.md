# Stage 128 — a native half, beside the one we have

## The rule

Nothing added here is required. Every piece of C++ has a GDScript twin that was
already doing the job and still does when the library is not built — which is
every checkout before somebody runs `scons`, and every platform nobody has got
round to yet. `scripts/native.gd` is the only place in the app that asks
whether the extension exists; everything else asks it.

Godot logs one line when a `.gdextension` names a missing library and carries
on. So a partial build works: Android done, desktop not, both run.

## What went native

**`native/ivory/src/ivory_warp.cpp`** — rigid MLS over the pins, then ARAP over
the mesh. Same two solvers as `puppet_warp.gd`.

**`native/ivory/src/ivory_skin.cpp`** — island reading and bone skinning. Same
weighting as `RigSkin.bone_rule`.

**`native/ivory/src/ivory_touch.cpp`** — the one-euro filter with a forward
lead, for pins and joints.

## Three things that are better in method, not only in speed

These are the reason this was worth doing rather than just profiling GDScript.

**Walked distance is now exact.** `PuppetWarp._rebuild_reach` measures distance
through the mesh by relaxation: every vertex offers its neighbours a route
through itself, sweeps repeat until nothing improves, and it stops when it is
close. How close depends on how many sweeps were affordable. The C++ uses
Dijkstra with a binary heap — each vertex settled once, in order of distance,
and the distance it settles on is final. Faster *and* exact, which is not a
trade that comes up often.

**The ARAP global step is over-relaxed.** Gauss-Seidel on `L p = b` converges
at a rate set by the mesh's spectral radius: information travels one vertex per
sweep. Successive over-relaxation takes the same step and then some — omega
about 1.62 — which is the textbook accelerator for this class of system and
reaches the same fixed point in roughly a third of the sweeps. It changes how
fast the iteration arrives, not where.

**MLS sums accumulate in double.** The weights are `1/(d² + s²)^k`, which
within a single vertex span several orders of magnitude between a pin under the
finger and one across the drawing. In single precision, adding the far pin to
the near one discards it outright — and a pin contributing nothing is a pin
whose share of the rotation silently went to its neighbours.

## Touch

`scripts/touch_lead.gd` and its C++ twin: the one-euro filter (Casiez, Roussel
and Vogel, 2012), whose cutoff rises with pointer speed —

    cutoff = min_cutoff + beta × speed

— so a still finger is steady and a fast one is not lagged, which no
fixed-cutoff filter manages at both ends. The lag that remains is systematic
rather than random, so it is subtracted rather than filtered: the position is
carried forward along the filtered velocity by twelve milliseconds, about a
frame's worth, held small because prediction buys responsiveness with overshoot
and the trade turns bad quickly.

Applied to **warp pins and bone joints only**. Those are controls being aimed,
and one pin's worth of jitter is thousands of vertices' worth of shimmer across
the mesh. It is deliberately not applied to ink: a brush stroke is a record of
where the hand went, and a stroke that ran ahead of the finger would be ink
that was never drawn. Strokes keep `stroke_smoother.gd`.

## The boundary

Kept narrow, because crossing it is the one cost C++ does not remove.

* The mesh crosses **once per rebuild**.
* The pin *set* crosses when a pin is added, removed or anchored — that is what
  makes the walked distances stale.
* Pin *positions and turns* cross every frame of a drag: a few dozen floats.

Sending the mesh on every solve would spend more than the solve saves.

## Building

See `native/ivory/README.md`. Short version:

    cd native/ivory
    git clone -b 4.4 https://github.com/godotengine/godot-cpp
    cd godot-cpp && git submodule update --init && cd ..
    scons platform=android arch=arm64 target=template_release

Libraries land in `bin/`, where `ivory.gdextension` already points. Nothing in
the project needs editing afterwards.
