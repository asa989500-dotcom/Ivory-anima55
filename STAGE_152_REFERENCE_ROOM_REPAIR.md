# Stage 152 — the Character 360 room, repaired at the root

You reported one error, on line 285 of `character360_builder.gd`. That line was
real, and it is fixed. But it was the only fault in the room that Godot was
capable of telling you about, and it was not the worst one. This is what the
investigation found and what was done about it.

---

## Part 1 — What was actually wrong

### 1. The build failure you saw, and its four siblings

```gdscript
var guard := ClassDB.instantiate("IvoryPoseGuard30") if Native.has_guard() else null
```

GDScript gives a ternary no static type. With `:=` the variable becomes
`Variant`, and with warnings-as-errors that is a build failure, not a warning.
There were **five** of these in the file — lines 226, 233, 234, 262 and 285 —
and the editor reported the last one it reached.

Every declaration in the rewritten file now carries its type explicitly, which
is what you have asked for since stage 90 and which is now also enforced by
`tools/check_inference.py` on every file in the project.

### 2. The project's own gate was failing, and had been shipped anyway

Running `python3 tools/check_all.py` on the zip you sent reported:

```
FAILED: check_scope.py, check_continuations.py, check_inference.py
```

`check_continuations.py` was not even failing on your code — it crashed with
`IndexError` the moment it was run without a path argument, which is exactly
how the build gate runs it. It had never once reported on this project.

### 3. Five real C++ compile errors — half the native side never built

| File | Error |
|---|---|
| `ivory_pose_guard30.cpp` | referenced `angles`; the parameter is named `a` |
| `ivory_text_tool.cpp` | `box.end` is GDScript-only; godot-cpp needs `get_end()` |
| `ivory_character360_rig.cpp` | `Vector2::RIGHT` does not exist in C++ |
| `ivory_character360_rig.cpp` | `std::clamp` called on mixed types |
| `ivory_character360.cpp` | `std::max(double, float)` |

The reason nobody noticed: `tools/check_native_compile.py` held a hand-written
list of eighteen files, and all five of these were absent from it. It reported
success because it never looked at them.

### 4. The safety guard could never have passed

`IvoryPoseGuard30` checks 28 and 29 demand `reference_blend` and
`joint_falloff` from the report `IvoryPoseAtlas::analyze()` returns. `analyze()`
never published either key. The guard read its own empty defaults and would
have refused **every rig** with "Reference safety guard blocked this rig" — had
it compiled, which it did not.

Check 21 was worse: it tested `abs(sum) <= 1e30` on a variable that was
initialised to zero and never written to. It could not fail. Above it sat an
empty loop that computed a `PackedFloat32Array` and threw it away.

### 5. Degrees were being fed into a radian engine

The room sent 15, 30, 45 — degrees — straight into `IvoryPoseAtlas`, which
wraps its input as radians. A fifteen-degree reference was filed at about
**139°**. Nothing crashed, nothing warned, and the blend between neighbouring
drawings had never once been between the drawings you meant.

### 6. The spacing was arithmetic nonsense

Twenty poses at a fixed 15° each reached **300°** on one side. That is not a
side of a character; and the opposite side of the turn had no drawing within
reach at all.

### 7. The skeleton ignored the drawing

`_make_rig()` placed ten bones at fixed fractions of the artwork's bounding
box — neck at 30% down, shoulders 18% out. Those numbers describe one imaginary
figure and no real one. Against a wide character, a crouching one, or one drawn
off-centre in its canvas, every joint landed in empty space and you had to drag
all ten by hand before the rig was worth anything.

### 8. Smaller faults in the room

- **No delete button.** A mis-imported pose was permanent until the room was
  closed, which lost everything.
- **Leaking file dialogs.** A new `FileDialog` was built on every press and
  freed only on the success path. Cancel it, or pick a broken file, and it
  stayed in the tree with its signal connected. Twenty poses meant twenty live
  dialogs.
- **The sixteen native C++ tests had never run.** The test stub's
  `PackedByteArray` had no initializer-list constructor, so `PackedByteArray{1,2,3}`
  — which most of them use — did not compile.

---

## Part 2 — The C++ infrastructure built for it

Three new engines, in `native/ivory/src/`, registered like every other native
service and optional in exactly the same way.

### `IvoryImageIntake` — the door every drawing comes through

Measures before it admits. Thirteen numbered refusal reasons, so the room can
say *why* rather than "the image was refused":

`ACCEPTED · EMPTY_BUFFER · BAD_DIMENSIONS · BUFFER_TOO_SHORT · FULLY_TRANSPARENT ·
TOO_LARGE · DUPLICATE_IMAGE · DUPLICATE_ANGLE · TOO_MANY_REFERENCES ·
ANGLE_NOT_FINITE · ANGLE_OUT_OF_RANGE · SHAPE_MISMATCH · MEMORY_BUDGET`

For the **image import** you asked to have improved:

- **A truncated PNG is refused** rather than handed to the atlas to read past
  the end of.
- **A duplicate drawing is caught** by a 64-bit 8×8 silhouette hash, so the
  same art cannot be filed at two angles and make the blend weights meaningless.
- **A wrong drawing is caught** by a 32-sample radial signature, each normalised
  by its own mean radius so it compares *proportion* rather than size. A genuine
  three-quarter turn gets in; a background plate imported by mistake does not.
- **`normalize()`** trims to the subject and rescales every drawing to a common
  height using premultiplied area-average resampling — nearest-neighbour would
  alias a line drawing into a dotted one, and bilinear would soften the outline
  the atlas measures. **It returns a new image and never touches the source.**
- **`degrees_to_atlas()`** is the single degrees→radians conversion point in the
  entire project. Fault 5 above cannot recur, because there is now exactly one
  place where it could.

### `IvoryRigFit` — the bone import you asked for

Builds a horizontal run profile from the alpha channel — for every row, the
leftmost and rightmost opaque pixel, the total width, and how many separate runs
there are — and reads the joints off it:

- **neck** — narrowest row in the top third, *only if* genuinely narrower than
  the head above it, so a character with no visible neck does not get a joint in
  the middle of its skull;
- **shoulders** — widest row just below the neck;
- **hip** — narrowest row between 42% and 72% down;
- **legs** — the first row that splits into two runs; a robe or a skirt never
  splits, so it gets **one** lower-body chain rather than two legs that would
  tear the drawing the first time it was posed;
- **arms** — traced *down the silhouette's outer edge*. An earlier version of
  this walked outward from the shoulder and put the hands in mid-air beside the
  character; the test caught it, which is the point of having the test.

When the silhouette says nothing useful — a solid blob, a logo, a texture
swatch — it **says so**. `method` comes back as `"silhouette"` or
`"proportional"`, never a guess dressed up as a measurement, and the room tells
you which one you got.

### `IvoryInspector14` — the fourteen inspection devices

| # | Device | Looks for |
|---|---|---|
| 1 | CONTRACT | required report keys present, with the values they promise |
| 2 | UNITS | degrees fed into a radian API |
| 3 | REFERENCES | count, ordering, base-first, uniqueness |
| 4 | WEIGHTS | finite, non-negative, summing to one |
| 5 | BUFFERS | pixel buffer length against width × height × 4 |
| 6 | MEMORY | per-image and total, against a stated budget |
| 7 | JOINTS | bone scale and rotation inside safe limits |
| 8 | TOPOLOGY | parent indices, cycles, zero-length bones |
| 9 | FINITE | every float crossing the boundary |
| 10 | STRIDE | parallel arrays agreeing on length |
| 11 | IMMUTABLE | the base drawing unchanged from intake to commit |
| 12 | DUPLICATE | the same drawing admitted twice |
| 13 | COVERAGE | angular gaps the blend cannot cross smoothly |
| 14 | UI | every control wired and labelled in both languages |

Why fourteen separate devices instead of one big guard: `IvoryPoseGuard30` was a
single function with thirty checks and a pass/fail at the end, and there was no
way to ask *which kind of wrong*. Each device here reports its own `checks`,
`failures` and issue list with **stable numeric codes**, so the room can
translate a specific complaint into Arabic and a test can assert on it.

One rule worth stating: **a device with no evidence reports `checks: 0, ok: true`
and does not count as a pass.** "Not measured" and "measured and sound" are
different answers, and the room shows a different message for each.

---

## Part 3 — The room, rebuilt

`scripts/ui/character360_builder.gd` was rewritten. It now talks to one class,
`ReferenceEngine`, which uses the C++ when it is compiled in and runs full
GDScript equivalents when it is not — so the room behaves identically either
way. (The old room skipped the safety check entirely when the extension was
absent, and that was the path nobody ever tested.)

### New and changed controls

| Control | Status |
|---|---|
| **Remove** on every pose slot | **new** — fault 8 |
| **Turn** slider (15–180°, default 90) | **new** — fault 6; re-spaces every pose on add, remove and drag |
| **Check** button | **new** — runs all fourteen devices on demand, without committing anything |
| Depth slider | now has a numeric readout; it had none |
| Import / Add LEFT / Add RIGHT | one reused `FileDialog` instead of one per press |
| Build 2.5D Rig | runs fourteen devices first and names the one that failed |

### Other changes in the room

- Angles are **derived from the set** on every change, so removing a pose cannot
  leave a hole and no angle can exceed the span.
- Commit stores **both** `angle_deg` and `angle_rad`, plus an explicit
  `angle_units` key. Fault 5 came from a number travelling between two pieces of
  code with nothing saying which unit it was in.
- `control_manifest()` lists every control with its wired state and both labels.
  Device 14 reads it, the headless test reads it, and
  `tools/check_room_buttons.py` reads the source that builds it.
- The rig is rejected outright if it fails `validate_rig()` — a parent cycle
  hangs the pose solver rather than merely looking wrong.
- State format bumped to `ivory.character25d.reference.v3`, `rig_version` 5.

---

## Part 4 — The tests you asked for

### Native (C++) — `python3 tools/run_native_tests.py`

```
19 native tests, 3806 checks
everything passed.
```

The sixteen that existed now compile and run for the first time (the stub was
fixed: `initializer_list` constructor, `Rect2::get_end()`, `DEFVAL`). Three are
new:

- `test_intake.cpp` — 63 checks
- `test_rigfit.cpp` — 38 checks, including one that asserts **every bone
  midpoint lands on opaque pixels**
- `test_inspector.cpp` — 100 checks; every device is shown **failing on purpose**
  as well as passing, because a checker that never fails is decoration

### The room — `tests/test_character360_room.gd`

Builds the room and presses its controls in the order a person would. It
asserts that:

- all nine controls are wired and carry both labels;
- the base drawing's bytes are byte-for-byte identical after loading;
- twenty poses a side land inside the turn instead of reaching 300°;
- every stored radian angle is the conversion of its degree angle;
- moving the Turn slider re-spaces what is already loaded;
- a pose can be deleted and the rest close the gap;
- a blank PNG and a duplicate drawing are refused, with a message;
- all fourteen devices pass on a correctly filled room;
- **every bone midpoint lands on the drawing**, and the skeleton has no cycles.

### New static checks

- `tools/check_registration.py` — 29 native classes, all registered. Catches a
  C++ class that is written, compiles, and is never handed to Godot (the symptom
  is silent: `Native.has_x()` returns false and the slower GDScript path runs
  forever).
- `tools/check_room_buttons.py` — catches a button built and never connected, a
  connection to a method that does not exist, and a control missing from the
  manifest. All three were verified by breaking the room on purpose and
  confirming the tool reports each one.
- `tools/check_native_compile.py` now **walks the source directory** instead of
  reading a hand-written list, so a file added tomorrow is checked tomorrow.
- `tools/check_continuations.py` no longer crashes when run without an argument.
- `tools/build.sh` runs the native tests as a hard gate.

### Where it all stands

```
All 18 checks passed.          (tools/check_all.py)
19 native tests, 3806 checks.  everything passed.
```

---

## What to look at first when you open it

1. Open the Character 360 room and press **Check** before importing anything.
   It should report that the devices ran but had nothing to measure — not that
   everything is fine.
2. Import a base drawing, add a few poses, and watch the strip captions. The
   angles spread across ±90° and re-spread when you drag the **Turn** slider.
3. Press **Remove** on a middle pose. The remaining angles close the gap.
4. Try importing the same PNG twice. The second is refused, with a sentence
   saying why.
5. Build the rig, then look at where the bones landed. If your drawing has a
   clear silhouette they are on the figure; if it does not, the room tells you
   it used proportions instead of pretending it measured something.

---

# Stage 152a — the three faults that stopped it opening

You ran it and it would not start. Three separate things, and only one of them
was a warning.

## 1. `_fill_page: Invalid assignment ... 'motion_position' ... type 'String'` — fatal

The project file is written with `JSON.stringify`, and **JSON has no Vector2**.
`vault.gd` was writing `l.motion_position` straight into the document, so it was
stored as the *string* `"(0, 0)"`. On load, assigning that string to a typed
`Vector2` property throws — inside the loader — so the project never finished
loading and the app never opened.

The same class of fault was sitting in two more places, quietly:

- **`rig`** — bone endpoints are `Vector2`. They became strings too. Nothing
  threw, because `rig` is an untyped Dictionary, so **every rigged figure was
  reloading with its skeleton at the origin** and had been for some time.
- **`character360_state`** — my new `base_png` and forty `pose_references` are
  `PackedByteArray`. JSON stores those as arrays of several hundred thousand
  numbers each. The file would have been tens of megabytes and would have read
  back as `Array` where the code expects bytes. This one was mine.

**Fixed:** `_vec_to_doc` / `_vec_from_doc`, `_rig_to_doc` / `_rig_from_doc`, and
`_c360_to_doc` / `_c360_from_doc` in `vault.gd`. Every heavy buffer is written
beside the manifest as its own file and the manifest keeps only the name — the
rule is now general instead of a hand-written list of two keys.

**Your existing projects still open.** `_vec_from_doc` accepts all four shapes:
a real Vector2, a `[x, y]` array (what this build writes), an `{x, y}`
dictionary, and the old `"(12, 34)"` string.

## 2. `Reassigning lambda capture does not modify the outer local variable`

`Inspector14.run_all` added its totals inside a lambda. **GDScript captures
locals by value**, so the lambda was updating its own copies and `checks`,
`failures`, `ran` and `first_failure` all stayed at zero.

That is worse than a crash: the fourteen devices ran, found problems, and the
summary reported **`0 checks, 0 failures`** — a clean bill of health for a
broken room. Rewritten as a plain loop, which cannot have the problem.

(The C++ `IvoryInspector14` was never affected — C++ lambdas capture by
reference when you ask them to, and its 100 checks were passing all along.)

## 3. `Integer division. Decimal part will be discarded.` ×6

Five in `reference_engine.gd` (`h.size() / 2`, `(top + neck) / 2`, and three
more) and one in `bone_room.gd` that predates this stage. All fixed.

`tools/check_warnings.py` had a division rule that only understood
`name / literal` — it could not see `h.size() / 2` or `(a + b) / 2`, which is
why it reported zero while Godot reported six. Widened, and verified against
both forms.

## What was added so none of these can come back

| Checker | Catches |
|---|---|
| `tools/check_json_safe.py` | a `Layer` field written to the project file whose declared type JSON cannot carry — reads the types out of `layer_stack.gd` and checks each row in `vault.gd`. Verified by putting the exact bug back and confirming it names line 173. |
| `tools/check_lambda_capture.py` | a lambda assigning to a local it only captured a copy of. Allows mutation (`array.append`), which is legal; flags rebinding, which is not. |
| `tools/check_warnings.py` (widened) | `size() / 2` and `(a + b) / 2`, which it used to miss. |

Two new cases in `tests/test_character360_room.gd`:

- **`_the_summary_actually_counts()`** — asserts the summary equals the sum of
  the fourteen devices, and that a deliberately broken contract comes back as a
  failure naming device 1. This is the test that would have caught fault 2.
- **`_a_rig_survives_a_save_and_a_load()`** — runs a real rig through
  `JSON.stringify` and back and asserts every bone endpoint is still a `Vector2`
  in the same place, that motion positions round-trip, and that the **old string
  form still loads**. This is the test that would have caught fault 1.

```
All 20 checks passed.
19 native tests, 3806 checks — everything passed.
```

---

# Stage 153 — the puppet warp, the quick bones, the band, the frames

Five new C++ engines, five test suites, and the coordinate bug that put the
comic frames beside the page.

```
All 20 checks passed.
23 native tests, 5583 checks — everything passed.
```

## 1. The puppet warp dragged. Here is why, and what replaced it

### The mesh — `IvoryMeshForge`

The old mesh is an axis-aligned grid over the artwork's bounding box with
cells dropped where an ink map says there is nothing. Three consequences, all
visible when you use it:

- **The boundary was a staircase.** Every vertex sat on a grid line, so the
  outline of the mesh was steps one cell tall. Pull an arm and its edge moves
  in blocks.
- **A hairline was a coin toss.** The ink map **averaged**. One opaque pixel
  averaged over a cell of a hundred is an alpha of 0.001 — under any floor — so
  the cell came back empty, the stroke fell out of the mesh, and what is not in
  the mesh is not drawn. That is the tearing.
- **The grid had no idea where the detail was.**

The forge fixes exactly those. Occupancy by **maximum** alpha, never the mean.
A **four-way** skirt, not eight — eight puts the rim two cells out at every
corner and the snap cannot close it. Rim vertices walked toward the **nearest
ink**, in eight increments with the interior relaxing between them, so nothing
ever crosses anything. Snaps that would still invert a triangle are **backed
off halfway**, not undone — undoing them threw away nine tenths of the fit.

Measured on a 60 px disc at cell 10: the rim sits **9.4 px** outside the
outline with a spread of **11.5 px**, and **every ink pixel** — hairlines,
single isolated pixels — is inside a triangle.

### The deformation — `IvoryArapSolver`

The old solve places every vertex by rigid moving-least-squares from the pins,
then runs a few ARAP rounds to repair it. **The first half is the fault.** MLS
is scattered-data interpolation: it knows about pins and distances and nothing
about the drawing being made of material. Nothing in it says a triangle would
rather keep its shape — so a pin pulled sideways translates its whole
neighbourhood sideways. That is what dragging *is*. The ARAP rounds afterwards
were then fighting the field just imposed on them.

Replaced by solving the ARAP energy directly from rest, with cotangent weights
and pins as **hard** constraints — a pinned vertex is removed from the system,
not weighted heavily.

Measured: pulling a bar to 1.5× spreads the stretch across **60 of 60
triangles**, range 1.49–1.51. Compressing it shrinks **every** triangle's area.
Twelve pins fighting each other: worst drift **0.00e+00 px** — that is the
"pins come loose once there are several" report, gone. Two identical solves
agree to 1e-6, which is what stops a held pin shivering between frames.

**What I deliberately did not do:** make the bar narrow as it stretches. That
is a Poisson effect — a property of rubber — and the ARAP energy has none.
Narrowing would mean every edge across the bar deviating *further* from its
rest length, the opposite of what the energy asks for. A solver that narrowed
would fight you every time you wanted a limb to keep its thickness. This is
written into the test rather than left as a surprise.

Both are wired into the room through `PuppetWarpForge`, ahead of the older
native path, with the GDScript still there for a checkout with no `bin/`.

## 2. The quick bones — `IvoryBonePose`

**The joint that shivered.** A fixed pass count over a fixed order: whichever
joint the sweep reached last inherited the leftover error, and its sign changed
between frames. Replaced with **reaching** — forward and backward along the
chain, so each pass walks the whole chain instead of one bone. A twenty-joint
chain went from **0.4989 px** of length error to **0.0000**, and re-dragging to
the same point moves the pose by 6.6e-05 px, which is the single-precision
floor and not the solver.

**Double-tap to freeze.** A pinned joint is never written to. Exact.

**The Saturn ring.** `rotate_about` turns a joint's **descendants only** — the
elbow moves the forearm and the hand and never the shoulder. A pinned joint
blocks the turn and everything below it — **except an end bone**, which may
still swing about its own pin, because pinning a wrist to turn the hand about
it is the commonest reason to pin anything. Exactly as you specified.

## 3. The comic frames were beside the page

`canvas_origin()` is `p.origin + p.page_offset(active_page)`.
`page_rect(i).position` is `origin + page_offset(i)`. **The same expression
written in two files.** So a point through `screen_to_canvas` is already
page-local, and the overlay is already positioned at that origin — and
`comic_board.gd` subtracted it a second time and added it back a second time.

Every frame was drawn one page origin away from the page, and every hit test
asked about a point one page origin away from the finger — so a stroke inside a
visible panel was refused. Both offsets are **zero** on page one of a project at
the workspace origin, which is what anyone checks by hand. That is how it
survived. The test works on a moved project's third page.

## 4. Drawing stopped responding after a selection — same rule you described

The gate was `not active.rig.is_empty()`: **any layer with a skeleton refused
the brush, for ever.** And a rig arrives on a layer in more ways than that rule
allowed for — quick bones tried on a figure, a whole layer lifted and put down
again (the skeleton travels with it), a return from the Character 360 room.
Nothing said so; the brush simply stopped.

Now only three kinds of layer refuse a brush, and each holds no paintable
pixels: a bone layer, a Character 360 reference layer, and its motion layer —
which is the rule you gave me. A finger on a joint is still caught first and
still means "move this bone".

## 5. The timeline

`CelTrack` was not slow — sorted lists, binary searches, a windowed walk. The
cost was asking it **once per layer, from GDScript, every redraw**, and
`Clip.last_event` walks every layer on every rendered frame of playback.

`IvoryTimelineIndex` answers for all layers in one call, compressed-sparse-row.
Measured: a second of scrubbing a **200-layer** scene costs **11.4 ms**, and
twenty times the layers costs 22.6 times the time — linear, not quadratic.
`TimelineIndex` caches it and rebuilds only on `LayerStack.changed`.

## 6. The smaller ones

- **Keyframe dwell.** The pose reaches the figure and the layer instantly, but
  the **mark** appears only after a second of stillness. Adjusting the same
  pose inside that second restarts the clock, so a minute of work leaves one
  key instead of forty. Written at once if the playhead moves or the layer
  changes — the delay reduces clutter, it must never risk work.
- **Onion skin with the bones.** It never worked, and the reason is precise:
  `_ghost_at` skips a layer when the cel showing at that frame is the same one
  as now. A rigged figure is drawn **once** and every pose after that is a key
  over that same cel — so the test fired on every layer and the feature
  silently did nothing. The skeleton is what changed, so the skeleton is what
  is ghosted, in the onion colours already chosen and the same fade.
- **`Dismiss.watch()`** — one line gives any floating panel tap-outside-to-
  close, with press *and* release both outside, so a finger that scrolls a list
  and drifts past the edge does not make the panel vanish under it.
- **2.5D import** now opens the **device's own picker**, and starts at the last
  folder used, then the camera roll, then downloads.

## Files lifted to pay for the growth

The size ledger's rule is that a long file may grow only if it is paid for out
of another. `TimelineFocusMenu` and `PuppetWarpFoldover` were lifted out
unchanged, along real seams. Total debt went **down**, from 5889 to 5833.

---

# Stage 154 — the drawing tools, the panel, the wheel, the text

## 1. Nothing could be drawn. The cause was my own incomplete fix

The rule "a layer with a skeleton refuses every drawing tool" is written in
**two** places — `CanvasView._brush_layer_allowed` and `LayerStack.can_draw` —
and at stage 153 I fixed only the first.

That made things **worse than before**. The canvas said yes and offered the
brush; the stack said no and swallowed every stroke. The tool looked alive and
did nothing — brushes, the fill, all of it.

Both hold the same rule now: only a bone layer, a Character 360 reference layer
and its motion layer refuse, because those are the three that hold no paintable
pixels. `tests/test_drawing_gates.gd` runs six layer states through **both**
gates and fails on any disagreement, so they cannot drift apart again.

**A correction I owe you.** I first blamed a line continuation before an `if`,
and built a checker for it. Then I found **32 of the same construct** already
shipping in files that work. My theory was wrong; the checker went in the bin
and the false claims came out of the comments rather than being left to mislead
whoever reads next.

## 2. The comic panels now bound the drawing, exactly as specified

New `ComicConfine`:

- **The panel the mark began in** is the boundary — not the one last tapped. A
  cut page confines whether or not anyone has chosen a frame, which is what
  cutting a page means. Cut again and there are four boundaries.
- **Brush, eraser, shapes:** every point is asked; a refused point does not
  happen.
- **Fill:** refused if the seed is outside, and its result is then **clipped to
  the panel**. A flood is one decision, not a point at a time — a single gap in
  a line lets it into the next panel as a block of colour. Clipping also means
  the fill stops at the panel edge without a line being drawn there.
- **Text and imported images cross freely** — and that is structural, not a
  rule that can be forgotten: neither goes through the dab or the flood path at
  all. Picking, selecting and moving are also exempt, because they lay no ink.

## 3. A real colour wheel

The old panel was ten squares and nothing else. Good squares — a short palette
is why a set of drawings looks like a set, so they stay — but any colour that
was not one of the ten could not be reached at all. No half-tone for shading,
no wash, no matching a grey already in the drawing.

`ColorWheel`: hue around, saturation outward, brightness on a bar.

- The marker is **two rings**, dark under light. One ring always vanishes
  against half the wheel — and that is the half you are looking at when you
  need it.
- A drag keeps picking, including **past the rim**, where saturation clamps at
  full instead of the pick stopping dead.
- Live while the finger is down, recorded when it lifts. One sweep passes
  through dozens of colours; filing them all would fill the twelve recent slots
  with the path a thumb took.
- The wheel is an image built once at its drawn size, not a shader re-running
  every frame on a picture that never changes.

Plus an **eyedropper** in the panel itself — the wheel is for a colour you can
picture, the dropper for one you are looking at — a hex and HSV readout, and a
**recently used** row, which on a half-finished page is almost always what the
hand wants next.

## 4. The text tool

Three faults, all real:

- **It was soft.** Drawn at final size with `MSAA_4X` on. MSAA anti-aliases
  *polygon edges*; a glyph here is blended from a texture the font server has
  already anti-aliased, so the MSAA had nothing to sharpen and only softened
  what was already right — and left a grey rim on any halo. Now: supersampled
  at 2× and shrunk with Lanczos, so every glyph is rasterised with four times
  the detail. Curves and diagonals — most of Arabic — come back with real
  gradients instead of one-pixel steps.
- **It was sometimes blank or in pieces.** `UPDATE_ONCE` *schedules* the draw,
  and the first `frame_post_draw` can arrive before it has happened. A race —
  which is why it looked random. Two frames now.
- **Left-aligned text could lose its last letters.** `draw_string` uses its
  width argument both to align *and* to cut off. Left alignment needs no box,
  so passing one bought nothing and silently clipped any line measured a
  fraction wider than the sheet. Only given now when the alignment needs it.

## Files lifted to pay for the growth

`CanvasShapes` and `ColorPanel`, out whole and unchanged along real seams.
Total debt **5889 → 5730**.

```
All 20 checks passed.
23 native tests, 5583 checks — everything passed.
```

---

# Stage 155 — the 2.5D rig, built rather than described

Two new C++ engines, fifteen tests, thirteen devices.

```
All 20 checks passed.
25 native tests, 5804 checks — everything passed.
```

## `IvoryRig25D` — depth is the whole idea

Every bone carries a depth: how far in front of or behind the paper that part
of the body sits. A nose is in front of a face, an ear behind it. Turn the head
and the nose must travel **further across the face** than the ear, and the ear
must go behind the cheek. That is one multiplication per bone, and it is the
entire difference between a drawing that turns and one that slides.

Two angles, both applied in the bone's own frame:

- **turn** — widths foreshorten by cos, depth becomes sideways travel by sin
- **tilt** — heights foreshorten by cos, depth becomes vertical travel by sin

That is the thing you asked for in as many words: the bones move the face up
and down on the axis of the movement, at its angle — and the hand, and
everything else.

Measured: at 40° of turn the head moved **+14.6 px** and the hand **−23.6 px**.
Opposite directions. That is a turn; the same direction would be a slide.
Tilting, depth alone moved the face **−11.47 px up and +11.47 down** —
symmetric, because sine is.

## The tearing: I was wrong twice before I was right

A whole-body patch stretched to **18× its rest length** with a dozen triangles
inside out.

**First wrong answer.** I tried the 2D dual-quaternion form — blending each
bone's rotation and its world-origin translation. It measured **35× stretch
against the current 3×**. The reason is exact: a translation measured from the
world origin is enormous compared with the drawing, so blending two of them
under different rotations leaves an error the size of the canvas. Real
dual-quaternion skinning avoids this by blending in a form that does not depend
on where the origin is; linearly blending the translation parts only *looks*
like that. Reverted, and the finding is written into the code so nobody repeats
it.

**Second wrong answer.** I added a hard cut — no influence from a bone more
than twice as far as the nearest. That is a step: two neighbouring points, one
just inside and one just outside, hold different bone sets and the triangle
between them turns over. Replaced with a smoothstep window, so influence fades
rather than stopping.

**What actually works** is blending rotations **on the circle** and turning the
point about the weighted mean joint. Averaging rotation *matrices* gives a
squash, not a rotation — that is the candy-wrapper collapse. Measured: the
elbow band is **22.0 px thick at rest and never drops below 20.7** at a 172°
bend. The pinch is gone.

**And the third thing was not a bug at all.** The remaining stretch was a grid
spanning the empty air between the arm and the leg. A sheet bridging two limbs
*must* stretch when they separate — it was doing exactly what it was told. My
test was wrong, not the engine. It is also why `IvoryMeshForge` exists: a real
skin follows the ink and has no material in the gap. Rewritten onto a
limb-following patch: **0 folds, worst stretch 2.10** across a full sweep.

## The trembling

A deadband in front of a critically damped follow. The deadband first, because
a filter cannot remove what it is still being told to track — a third of a
pixel of tremor filtered smoothly is a *smooth tremor*.

Measured: **0.905 px of tremor reaching the drawing raw, 0.000 px filtered.**
Held still for a second, the drawing moves **0.00e+00 px**. And it does not
turn into lag: it arrives in **11 frames with zero overshoot**, because
critically damped means as fast as possible without bouncing.

## The self-repair, and where I drew its line

`repair()` mends what the artist never chose and cannot see: weights that do
not sum to one, a negative or not-a-number weight, an infinite depth, a NaN
angle, a follow time long enough to lag. A point left holding *no* bone is
given to its nearest — a point held by nothing sits still while the drawing
round it moves, which is a hole torn in the middle of a figure.

It does **not** touch folds, tears, or a depth that merely looks wrong. Those
are decisions or consequences of decisions, and a repair that changes an
artist's drawing without saying so is worse than the fault.

## Thirteen devices, in their own class

`IvoryRigDoctor` is deliberately separate. A thing that judges itself only
checks what its author thought of, and a fault in the judging is invisible
because the same code made both the work and the verdict.

| # | Device | Catches |
|---|---|---|
| 1 | skeleton | parents in range, no cycles, no zero-length bones |
| 2 | weights | finite, non-negative, summing to one, nobody unheld |
| 3 | support | too many bones holding one point — a drawing that won't keep still |
| 4 | depth | not-a-number, or deeper than the figure is large |
| 5 | angles | a joint turned further than a joint can turn |
| 6 | kinematics | a bone that changed length while being posed |
| 7 | projection | turned so far the drawing has no width, or past what was drawn |
| 8 | tear | stretched further than bending accounts for |
| 9 | fold | triangles turned inside out |
| 10 | tremble | movement with nothing asking for it — and direction *reversals*, which is what separates shaking from settling |
| 11 | drift | a pose returning to rest and not coming back to the same place |
| 12 | budget | the size of the rig against what a frame can afford |
| 13 | contract | the report says everything a saved file needs |

Every device is shown **failing on purpose** as well as passing, and the last
test runs all thirteen on a rig that has actually been built, bound, posed and
measured — not on an invented bundle.

## Autosave: nothing is lost

A pose reaches the layer the instant a finger lifts; the *keyframe* waits a
second of stillness so a minute of adjusting leaves one key rather than forty.
Both save paths now flush that pending pose first:

- `_park()` — the app being closed, backgrounded or swiped away, and on Android
  possibly the last code that runs.
- `_maybe_save()` — the routine autosave, which would otherwise write a project
  whose figure is posed but whose band has no mark on it.

A project reopened from that file would not have been the one that was closed,
which is the one thing a save must never be.
