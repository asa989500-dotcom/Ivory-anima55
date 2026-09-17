# IVORY — Stage 138

The B-spline room's engine rebuilt in C++, a 2.5D study for it, and the
Character 360 rig.

Three new native classes — `IvorySpline`, `IvoryDepth`, `IvoryRig360` —
registered in `register_types.cpp` and reached through `scripts/native.gd`.
Optional in the same way as everything else: a checkout with no `bin/` runs on
the GDScript that was already there.

```
tools/run_native_tests.sh     1152 checks across 13 suites, 0 failures
```

---

## 1. The curve — `IvorySpline`

### "Moving a point drags other points, and drags the outline outside it"

Two complaints with two different causes.

**The curve does not go where the finger goes.** A B-spline is pulled towards
its control points, never through them — about two thirds of the way at the
strongest. So dragging a control point onto a place moves the curve most of the
way there, and the natural next move is to drag further, overshoot, and drag
back. The curve chases the finger and never arrives.

The fix is to stop dragging control points. Let the person drag **the curve**
and solve for the points. Since `S(t) = Σ N_j(t) P_j`, moving only `P_i` moves
`S(t)` by `N_i(t)·dP_i`, so

```
dP_i = (target − S(t)) / N_i(t)
```

lands the curve on the target **exactly, first time**. Picking the `i` with the
largest `N_i(t)` makes the move smallest and the division best-conditioned.

**Nothing outside stirs.** A cubic control point's basis is *identically zero*
outside four knot spans — zero, not small. `test_spline.cpp` asserts this on the
raw floats: after a pull, every other control point is byte-identical, and so is
the curve everywhere outside the support, including both far ends. A drag at the
waist cannot move a hand.

Three modes: `MODE_ONE` (one point moves — strictest), `MODE_SPREAD` (the
minimum-norm correction over the four active points — rounder), `MODE_STIFF`
(spread, then a bending-energy relaxation — for a spine or a limb).

Also: Boehm knot insertion that provably does not change the shape, corners in
an otherwise silk curve, and arc length by **five-point Gauss–Legendre** rather
than chord summing — a chord always under-reads its arc, which is what makes
bound ink creep towards the start every time the table is rebuilt.

## 2. The 2.5D study — `IvoryDepth`

You asked me to study this three times. The three passes are written out in
full at the top of `ivory_depth.h`; in short:

**One — what 2.5D is.** Not 3D. Turning a head means the features slide across
each other *by the right relative amounts*: the nose a long way, the ears
hardly at all. Get those right and a flat drawing reads as solid. Get them
uniform and you have a cardboard cut-out, which is what every naive attempt
produces. The amounts come from one number per part: how far forward it is.

**Two — where the depth comes from.** The silhouette. **Inflation** (Igarashi,
Matsuoka, Tanaka — *Teddy*, SIGGRAPH 1999): height set by distance to the
nearest edge. Raw distance gives a **tent** with a ridge and creases where the
medial axis branches — and a crease becomes a visible fold the moment the head
moves. So the height is `sqrt` of the normalised distance (a cylinder's
cross-section, not a roof's), then Laplacian-smoothed. The smoothing passes are
the honestly slow part, which is why the loading bar is not a lie.

**Three — why one global depth is not enough.** A drawing is not one object.
The ivory points carry *how far forward* and *how much this part joins in*, and
their influence falls off by **distance through the ink, not across the page**.
A point on the left cheek is close to the right cheek as the crow flies and a
long way round the face; measured the wrong way, moving one drags the other.
One multi-source Dijkstra per point. Weights normalise to a partition of unity,
so nothing is left behind or moved twice.

**And the mistake that would still have been there.** Having the weights, the
obvious step is to rotate by each point's transform and average the results.
That is the candy-wrapper — the same error `ivory_skin.h` names for bones — and
on a head it shows as the face shrinking and pinching as it turns. What is
averaged here is the **amount of turn**; one rotation is then built and applied
once. The test checks it: a hard turn with six points changes the form's height
by under 2%.

**The centre line** is found by mirroring the silhouette about each candidate
axis and keeping the best overlap — a figure with one arm raised has its box
centre out in the armpit, and every turn is measured from this line.

**The loading is real.** Five named stages — measuring the outline, rounding
the form, finding the centre line, learning what each point reaches, placing the
bones — with monotone progress, a name to show, and `cancel_study` that throws
the partial result away rather than keeping it. A half-built depth field is not
a worse field, it is a wrong one.

One thing the tests found and I changed: the default reach was derived from the
size of the *drawing*, which gave a head point a fifth of a share of the hips —
so an artist who had set the hips to stay put watched them move anyway. It now
defaults to **half the way to the nearest other point**, which is where a
point's natural region actually ends.

## 3. The rig — `IvoryRig360`

**Rest coordinates, held firmly.** A bone has the pose it was drawn in and the
pose it is in now. Everything bound to it is stored against the first and
displayed through the second, and the rest pose is written once and never
touched by posing. Ten thousand poses and back to rest returns to *exactly* the
starting coordinates — checked on the raw floats, because composing from the
last pose instead is what makes a sleeve creep down an arm over a session.

**Drawing on a posed figure.** Ink is bound at the pose it was drawn in: each
stroke is turned into a bone's rest frame by the exact inverse of the live
transform. So a lock of hair drawn on a tilted head does not jump upright when
the head is straightened, and it returns to exactly where it was put when the
pose comes back.

A finding worth naming: binding **each point** to its own nearest bone tears a
stroke that lies across a joint — the two halves are carried by two rotations
and separate by however far the joint bent. There is no setting that fixes it;
the discontinuity is in the assignment. So `bind_stroke` binds the whole stroke
to the bone that owns most of it (length-weighted), and it is carried rigidly
and cannot tear. `bind_stroke_spread` is there for a robe across several parts,
and carries the tearing with it, which is why it is not the default.

**Smart bones**, as in Moho: a bone's angle drives others, recorded at angles
and interpolated between. **Catmull-Rom, not linear** — a linear blend has a
corner at every recorded angle, and a corner in the correction shows as the limb
ticking as it passes. Past the last recording it holds rather than extrapolating,
because an extrapolated spline is how a limb suddenly folds when somebody drags
further than they ever recorded.

**Character 360 layers.** The first is `character 360`; an ordinary "add a
layer" in that file makes `character 360 (2)`, `(3)`, bound to the same rig.
Names are chosen against the layers that exist rather than by counting — counting
is how two layers end up both called `(3)` after a delete, and the test checks
that the freed number is reused instead.

**Export** carries rest *and* pose, the parent list, the parts, the bound ink in
rest coordinates, the smart actions and the layer names. Both poses, because a
file with only the pose cannot be re-posed and one with only the rest cannot
show what was on screen when the button was pressed.

**Cancel at every step**, as asked. `undo_last` reverses exactly the last
operation — an angle, a bone, a stroke, a layer, an action — and each record
holds only what that operation touched rather than a snapshot of the rig.

---

## Validation

| suite | checks |
|---|---|
| `test_spline` | 93 |
| `test_depth` | 305 |
| `test_rig360` | 103 |
| (stage 137 suites) | 651 |

`tools/check_all.py` is clean except `check_size.py`, which was already failing
before stage 137 and is unchanged by this stage — the three new classes are C++
and the only GDScript touched was `lang.gd` and `native.gd`.

## Not built

The room's **interface** is still GDScript, and deliberately: `bspline_room.gd`
is a `Control`, and this project's shape is GDScript for what is on screen and
C++ for what is being computed. What is finished and tested is the whole of the
computation. What still needs call sites in `scripts/ui/bspline_room.gd`:

* dragging the curve through `IvorySpline.pull_nearest` instead of moving
  control points
* the ivory 2.5D point tool, and its Apply button calling `begin_study` /
  `study_step` from `_process` with the progress panel and its cancel
* the head/hand/finger sliders driving `IvoryDepth.set_turn`
* `IvoryRig360.suggest_from` on the study's features, and touch on the bones
* the layer panel calling `next_layer_name`, and the export button calling
  `to_project`

Every one of those is a call site. The behaviour is decided, tested, and waiting.
