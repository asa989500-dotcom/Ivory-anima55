# IVORY — Stage 137

Seven new native classes, three new brush families, a colour merge tool, and a
test harness that runs.

Everything new is C++ in `native/ivory/src`, registered in
`register_types.cpp` and reached through `scripts/native.gd`. As with the
eleven classes already there, **none of it is required**: a checkout with no
`bin/` runs, and every caller falls back to the GDScript that was already
doing the job.

---

## 1. The error device, and what it found

`native/stub` used to be a *syntax* stub. `Dictionary::operator[]` returned a
reference to one shared static `Variant` holding nothing, so code that filled
a dictionary compiled, code that read one compiled, and neither did anything.
That catches a missing semicolon and nothing else.

`Variant`, `Dictionary` and `Array` are now real there — a tagged union with
shared storage for the two containers, matching Godot's reference semantics.
The consequence is that **the native tests execute**, off-engine, in about a
second, on any machine with a compiler:

```
tools/run_native_tests.sh
```

`tools/check_native_compile.py` went from three files to all eighteen.

The first widened run found three things that had been sitting in the dark:

* **`ivory_warp.cpp:189`** — `std::max(near_.size() / 2, 16)` compares a
  `size_t` against an `int`. `std::max` cannot deduce one type from two, so
  this **stops the build outright** on a toolchain where they differ, which
  includes every 32-bit target — meaning the `arm32` Android library in
  `ivory.gdextension` could not have been produced. Both sides are `size_t`
  now.
* `ivory_bone.cpp` — an unused parameter in `fabrik`, named and discarded.
* The stub had no `Image`, so `ivory_skin.cpp` was never being checked at all.

## 2. Knitting — `IvoryWrap`

**The pin is a barrier.** A taut thread past round obstacles has a closed
form: straight segments tangent to the circles, joined by arcs. Both ways
round each pin are computed and the shorter kept — taut *means* shortest, so
that is the definition evaluated rather than a rule that can be got wrong.

The guarantee is exact, not approximate. Arc samples are placed on a circle
of radius `r / cos(half a step)`, so the **chords between them are tangent to
the barrier rather than secant to it**. Sampling on the barrier itself puts
every sample on the edge and every chord a sagitta inside it — the guarantee
failing in the one place it is being made. This was found by the test, not by
reading the code.

**Two turns fastens.** Accumulated unwrapped angle, not proximity. Half a turn
out and back sweeps zero and does not fasten. One turn is not enough. Either
direction works. Steps over half a turn in a frame are refused as lifts, and
the finger must stay inside a band around the pin, so circling the whole board
fastens nothing.

**Many threads on one pin, tidy.** Each gets a slot from a fan of twelve, then
layers outward. The caller passes the slots already taken and stores the code
it gets back — the same design as `IvoryKnit::guard_cut_point`, and for the
same reason: derived from a count, two threads arriving from nearly the same
side compute the same slot, and a board reopened tomorrow can shuffle itself.

**Smoothing** is centripetal Catmull-Rom, which cannot cusp or loop when two
control points are close — and on this board they are close whenever a thread
grazes a pin.

## 3. Brushes — `IvoryBrush`

**Web** (شبكة). Worley cells. The borders are where `F2 − F1 ≈ 0`, which *is*
the Voronoi edge, so the network comes out closed and connected with no ends
hanging, for free. Junction swelling is driven by `F3 − F1`. The venom variant
has strands so thin they nearly vanish and pool heavily at junctions, so it
reads as something flowing into its junctions rather than wires crossing at
them.

**Hair halo** (هالات شعرية). Gaussian rings combined by **screening**,
`1 − (1 − a)(1 − b)`. Adding saturates every crossing to solid white and the
crossings are the entire texture; taking the larger makes them invisible.

**Chalk** (طباشير). A threshold that **rises towards the edges**, so the
middle keeps the grain and the edges keep only its peaks. A flat threshold
gives a stripe with holes in it, which reads as a broken brush.

Five variants each, verified genuinely different.

**The knife.** Jitter is bounded by `a ≤ (d − 2r − g) / 2`, which makes
overlap *arithmetically impossible* rather than unlikely. The test then found
that a local check fails on a stroke crossing its own earlier dots, so every
placed dot goes into a uniform spatial grid and is checked against all of
them. The seed is a quantised **canvas** position, so forty redraws during a
pan or pinch give byte-identical dots.

## 4. Colour merge — `IvoryBlend`

Built in **OKLab**. Averaging sRGB bytes is wrong twice: 128 is not half of
255 but about 21% of the light, and averaging linear light is not appearance
either. Red into green gives a real olive rather than mud; blue to white stays
blue instead of passing through purple; gradient steps come out evenly spaced.

Five modes — mix, gradient, smudge, average, snap. It carries **every brush
shape**: the same stamp is read as *how much mixing happens where*. Alpha is
weighted premultiplied, which is what removes the dark fringe along every
edge. sRGB decoding is a 256-entry table.

Put through **seven rounds** — the colour space, the shape of a merge, the
kernel, every mode, transparency, strength and convergence, and abuse. Two
hundred passes settle exactly on the target colour and do not go past it.

## 5. Bones — `IvoryPose`

**Locking what is above.** A frozen bone is treated as a *root*: chain
collection stops there and the solver is handed a shorter chain. The
arithmetic above the freeze never runs, rather than running and being undone —
undoing it leaves joints a rounding error apart, and a rig whose joints are a
rounding error apart visibly opens gaps when moved quickly.

**The cascade.** Two taps on the same circle within the window freeze
everything and open below that bone. A third releases. Tapping a different
bone *moves* the opening rather than adding a second one.

**Whole parts, never distortion.** One rotation about one pivot carried over
the whole subtree. The test asserts it directly: every pairwise distance
inside a moved subtree is unchanged, no bone changes length, no joint opens.

**It stopped shuddering** because of a Schmitt trigger on the intent to move —
two thresholds, not one. One threshold puts a decision boundary somewhere, the
hand sits on it, and the answer flickers several times a second. The keep
threshold is *forced* below the start threshold rather than trusted.

**One layer, three kinds of motion.** `TRACK_DRAW | TRACK_RIG | TRACK_WARP`
is a union, so adding one never displaces another. Order is fixed: draw, then
rig, then warp — warping before posing moves the pins away from the ink they
were placed on. A frame is built, and the onion skin and dot appear, when the
pose has actually moved past a threshold, measured as the furthest joint
rather than the average.

## 6. One tool at a time — `IvoryArbiter`

One owner for the rule, in C++, because it has to be the same answer on the
drawing screen, the animation screen, the comic board and the knitting board.
A rule kept in four places is four rules.

Tools are `KIND_MODE` — exactly one live, choosing another ends it — or
`KIND_STANDING` — structure like the bone rig, which is part of the layer the
way the ink is. **That is the "ones built like bones do not count" exemption,
written down rather than remembered.**

**Four fingers cancel**, and it is a tap: four down *together*, none of them
*travelled*, and *briefly*. Three fingers is within reach of a hand resting on
a phone. Five is a palm. A four-finger drag is a pan — and dropping that one
test alone would make every pan cancel the tool underneath it.

## 7. The endless canvas — `IvoryField`

Addressed rather than allocated: tiles on an integer lattice, existing only
once drawn on. The round trip is done in **double** — far from the origin,
`screen − pan` is a small number made by subtracting two large ones, which is
where single precision loses its digits and where the shiver came from. Tested
by pushing an anchored mark through a hundred pan and zoom states: it does not
move. Eviction never touches tiles on screen or in the ring around them,
because discarding a tile that is wanted a frame later is how a pan starts to
flicker.

## 8. Knitting export — `IvoryKnitExport`

Eleven writers: `svg`, `chart`, `instructions`, `order`, `pin_map`, `gauge`,
`tiles`, `json`, `csv`, `stitches`, `summary`. A picture loses everything
except the picture — which pin, which way round, how many turns, in what
order — and all of that is what somebody needs to make the piece again.

Every measurement is in real millimetres through one scale. Written formats
come out in Arabic or English. Escaping is done properly: a colour called
"Red & Gold" produces an SVG that opens, and a comma in a name does not shift
every CSV column after it.

## 9. Comics

`begin_cutting` / `finish_cutting` / `abandon_cutting`. There was no way out
of the cut mode that was not leaving by accident; now there is a button that
says so, it reports what was made, and one press abandons the whole session
rather than as many undo steps as there were cuts.

`tidy` clears slivers on finishing. Thinness is measured by compactness —
`4πA / P²` — not area, because a panel four hundred long and two wide passes
any area floor worth setting and nobody can draw in it. Tidying refuses to
clear the last panel: a page with no panels is not tidier, it is lost.

**Renamed**: `Comic` and `Comics` are now **قصص مصورة** in Arabic, in
`lang.gd`, in all seven languages, and the rail no longer shows the
transliteration "الكوميكس". Thirty-odd new strings for this stage were added
in all seven.

---

## Validation

```
tools/run_native_tests.sh      814 checks across 10 suites, 0 failures
tools/check_all.py             all checkers clean except check_size.py
```

| suite | checks |
|---|---|
| `test_comic` | 89 |
| `test_store` | 36 |
| `test_lang` | 66 |
| `test_wrap` | 71 |
| `test_brush` | 202 |
| `test_blend` | 57 |
| `test_pose` | 73 |
| `test_arbiter` | 63 |
| `test_field` | 94 |

Bugs the tests found and that were fixed before this stage closed: the arc
chord cutting through the pin it routed round; the fastening epsilon (two
turns summed from a hundred and sixty steps lands a ten-millionth short of
`4π`); slot collisions at a fan boundary; the knife's local-only overlap check
on a self-crossing stroke; and a mistake in `test_arbiter.cpp` itself, where
calling `choose` twice in a row silently toggled the tool off and made three
checks pass for the wrong reason.

### `check_size.py`

Still failing, as it was before this stage — the ledger records 5992 lines of
debt and the project carries 7078. The three brush families were lifted into
`scripts/brush_extra.gd` to pay for the growth, which brought
`brush_library.gd` back from +117 to +12. That +12 is the honest remaining
cost of this stage; the other 1086 is pre-existing, chiefly `puppet_warp.gd`
at 621 over.

## Not built

The native half is complete and tested. The GDScript that *drives* it is
wired at the seams — `native.gd`, `brush_library.gd`, `lang.gd`,
`tool_panels.gd`, `register_types.cpp` — but the following still need
interface work in GDScript before a person can reach them:

* the blend tool's button under the brush, and its settings panel
* the "finish splitting" button on the comic cut screen
* routing every existing tool button through `IvoryArbiter`, and feeding it
  touch events for the four-finger gesture
* the knitting board calling `IvoryWrap` instead of the current yarn path,
  and the export sheet listing the eleven formats
* `bone_room.gd` calling `IvoryPose.tap` on the joint circle

Each of those is a call site, not a design question — the behaviour is
decided, tested, and waiting.

## Building the native half

Unchanged:

```
cd native/ivory
git clone -b 4.4 https://github.com/godotengine/godot-cpp
cd godot-cpp && git submodule update --init && cd ..
scons platform=android arch=arm64 target=template_release
scons platform=android arch=arm32 target=template_release
```

The `arm32` build should now actually complete — see the `ivory_warp.cpp`
fix above.
