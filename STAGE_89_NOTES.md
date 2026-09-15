# Stage 89 — a road between two projects, and an honestly even stroke

Four things were asked for. All four are here.

---

## 1. Transfer of the decree

The icon from `assets89` is installed as `assets/icons/transfer.png`, and the
original is kept beside it in `assets/transfer_supplied/`.

### Where it lives

Inside a project, the gear shows that project's own settings. The new row sits
there, and it is built behind `DrawTransfer.offered_by`, which answers true for
a drawing project and false for everything else. So the row is **absent** in an
animation and **absent** in a comic — not greyed out. A button that can never be
pressed is a question the user has to answer every time they read the list.

### The three screens

Exactly as you described them, one question each.

**Which layers.** The layers of the current page, top of the picture first — the
same order the layers panel shows them in, so the two lists cannot disagree.
Each row is the layer's own drawing beside its name, and the picture is a second
way to press the same switch: a list of drawings where the drawings are not what
you touch is a list of names with decoration next to it. Empty and hidden layers
are listed and marked rather than quietly dropped. **Select all** is the tick box
at the top, and the count under it says how many are going.

**Which project.** Every other project in the workspace, animations and comics
first because those are what this exists to feed. Each board carries its kind
and its paper size under its name — two projects called *Drawing 2* and
*Drawing 3* tell you nothing, and their sizes tell you which one you meant.
Other drawings are on the list beneath them: a character sheet gathering figures
drawn on separate pages is exactly that, and refusing it would be a rule with
nobody behind it.

**How it lands.** *One layer* or *Several layers*. With more than one layer
chosen it always asks. With exactly one chosen it does not, because one layer
landing as one layer and one layer landing as several are the same act, and a
screen whose two buttons do the identical thing teaches the user that the
question was never real.

### Three rules the code is built on

**It copies. It never cuts.** The source project is read and not written to by a
single line in `transfer.gd`. A transfer that emptied the drawing it came from
would be one gesture away from losing hours of work *across a boundary undo
cannot reach* — undo belongs to a project, and there are two projects here with
two histories. Copying makes the worst case "a layer I did not want", which is
one undo away in the project that received it.

**What lands is one undo.** Not one per layer. The target's history is unhooked
while the layers go in and a single entry is filed afterwards, holding the
arrangement as it was before any of them arrived. Six transferred layers are one
press of undo, because the user made one decision, not six.

**Where it lands is worked out, not guessed.** One scale factor for both axes,
never two: `k = min(dstW/srcW, dstH/srcH)`. Two factors would fit the page
exactly and stretch the figure doing it — a face is a face at one ratio and
nobody's face at another. The whole source page fits inside the target with its
proportions untouched, what is left over becomes an even margin, and every
layer keeps its place relative to the page. When the two pages are the same
size the factor comes out exactly one, and the resample is skipped altogether:
a same-size transfer is pixel for pixel what was drawn.

### The merge, and why it is written by hand

Godot's `Image.blend_rect` cannot be used to flatten these layers. It reads both
sides as straight alpha, and these canvases are premultiplied — so over a
destination that already has something on it, the source is weighted by its own
alpha twice. I measured it against exact premultiplied compositing over 400,000
random pixel pairs:

| | worst channel error |
|---|---|
| `Image.blend_rect` | **68.3 of 255** |
| `DrawTransfer._over` | **0.5 of 255** |

It is exact where the top pixel is solid or the bottom one empty, and wrong
along every anti-aliased edge — which on a drawing means wrong along every line
in it. So the composite is `out = over + under·(1 − over.a)`, written out, with
rounding carried so that stacking merges cannot drift a channel downward one
unit at a time. Measured 24 layers deep the drift settles at 1.4 of 255 and
stops climbing.

It is affordable because the loop is built around the two cases that are nearly
all of a drawing: a transparent pixel costs one comparison and is skipped, a
solid one costs a four-byte copy. Only the thin rim of the strokes reaches the
arithmetic.

Merging happens at **source** resolution and the result is resampled once. The
other way round — resample each layer, then add — puts every layer through a
filter and lands all of their softness on the same line wherever two layers
share an edge.

### Small things that would have been bugs

- Layers are gathered **bottom first**, which is both the order a merge must be
  summed in and the order they must be added to the target in. One order serves
  both, so there is no second place to get it wrong.
- `flush_all` and `settle_all` run before anything is read. A stroke lives on
  the graphics card until it is folded down, and reading without this returns
  the drawing as it was a moment ago — missing the part the user is most sure
  they drew.
- Content is clipped to the source page. Ink that ran off the edge is not part
  of the drawing and must not be what decides how large the transfer is.
- A layer carried across at forty per cent arrives **as a layer at forty per
  cent**, not as pixels baked to forty per cent, so it can be turned back up.
  Only the merge bakes, because a merge has nowhere else to put it.
- If every chosen layer turns out to be hidden, nothing lands and it says so,
  rather than putting an empty layer in the target and calling it a success.
- The target goes straight back to sleep afterwards unless it is the project on
  screen — its tiles compressed, its graphics memory handed back. Without it,
  transferring into six projects would leave six projects awake.
- Transferred layers are born at frame zero. A drawing brought in from outside
  has no opinion about time, and the only honest answer is that it has always
  been there.

---

## 2. The stroke, walked properly

`_walk_curve` said in its own comment that it walked by arc length. It did not.
It measured the piece in twenty straight chops and then stepped `t` in
proportion to distance — which *reads* like arc length and is a different thing.
On a Bézier the point runs fast through the straight part and slows through the
bend, so an even step in `t` crowds the dabs into exactly the place a brush
would space them furthest apart.

Measured on an ordinary hand-drawn arc at 8 px spacing:

| | narrowest gap | widest gap | spread |
|---|---|---|---|
| before | 6.27 px | 11.96 px | **1.91×** |
| after | 7.996 px | 8.000 px | **1.001×** |

Dark corners and pale straights, gone. `scripts/curve_walk.gd` does it with
three pieces of machinery:

- **The length is integrated, not chopped.** Speed along the curve is `|B′(t)|`,
  and `B′` of a quadratic is *linear* in `t` — so the integrand is the square
  root of a quadratic. Three-point Gauss–Legendre handles that to about one part
  in ten thousand million using three evaluations, where twenty chords use
  twenty and are far coarser.
- **The kink gets its own knot.** `|At + B|` has a corner where `At + B` passes
  closest to zero — a piece that nearly doubles back on itself. Nothing smooth
  integrates across a corner well, so the corner is found outright at
  `t = −(A·B)/(A·A)` and made a subinterval boundary. On the worst curve in a
  random sample of three hundred this one change took the error on a single step
  from **1.01 px to 0.006 px**.
- **The inversion is safeguarded.** Newton, because its derivative here is the
  exact speed and costs nothing — but kept inside a bracket that halves whenever
  Newton would step outside it. The worst case is bisection, which always
  converges; the usual case lands in one or two. On a ruled straight line the
  measured error is **4 × 10⁻¹⁴ px**.

Verified against brute-force references: 47,431 gaps across 3,000 random stroke
pieces at realistic scale, worst deviation from the requested step **0.001 px**.

**Curvature costs nothing.** For a quadratic Bézier `B′ × B″` does not depend on
`t` at all — `B″` is constant and the cross product drops its `t` term. So the
radius of the turn is one cube and one divide, checked against finite
differences to 10⁻⁹. That is what makes it affordable to ask *at every dab* how
tight the bend is, which buys the second fix: **a wide stamp swept round a tight
bend scallops its outer edge**, because the rim travels `(R + r)/R` times as far
as the centre. The spacing is tightened through the bend by exactly the ratio
that puts the rim back where the brush asked for it, and left alone everywhere
else. It is why a large brush now holds its shape round a corner. The same rule
is applied to shape outlines, so a wide circle comes out a wide clean circle.

**Two more internal corrections, both invisible as changes and visible as
quality:**

- `_speed` was pixels *per event*, which is not a speed. The same hand at the
  same rate reported twice the number on a 120 Hz screen as on a 60 Hz one, so
  every brush that thins with speed thinned about twice as eagerly on the fast
  screens people buy for drawing. It is now pixels per second, and the threshold
  was restated to match — a stroke on a 60 Hz device looks exactly as it did,
  and every other device now looks the same as that one.
- Pressure was read once per input report and applied to every dab in the piece
  after it. On a fast stroke that is thirty dabs at one width followed by thirty
  at another — a taper made of steps. Pressure is now read *across* the piece
  between the two reports that bound it, and lightly smoothed, since most
  digitizers report it in coarse jumps.

Two small efficiencies came with it: the spacing is read once per piece instead
of once per dab, in all three walkers.

---

## 3. Everything tied to selection, copy and paste, and to undo

- **Copy no longer destroys the marquee.** Lifting a selection empties the
  outline as part of turning it into a floating piece, so copying a shape and
  then cutting the same shape meant drawing the shape twice. Copy is the one
  operation here that changes nothing, and it now leaves the screen as it found
  it.
- **Cut is a real operation.** It existed only as "copy, then rub out by hand" —
  two gestures and two history entries for one intention. Every route through
  `cut_selection` now ends with **exactly one** entry on the stack, so one press
  of undo brings the pixels back whatever was marked. Ctrl+X, and a button in
  the selection panel.
- **Paste as new layer.** The ordinary paste lands on whatever layer is
  selected, which is right when assembling something and wrong when bringing a
  piece in from elsewhere — a figure copied out of another project has no
  business sharing a layer with the background it happened to arrive next to.
  It takes the name of the layer it was copied from, so the stack still reads as
  a list of things rather than of numbers. Ctrl+Shift+V.
- With nothing marked, Copy **and** Cut both take the whole layer. Same rule for
  both, which is what makes the pair predictable.
- The clipboard is global, so all of this crosses projects and frames.

---

## 4. Translations

Thirty-two new strings, every one written out in all seven languages — Arabic,
Spanish, German, Japanese, Chinese, Korean — not left to fall back to English.
The whole table is checked for duplicate keys, which GDScript rejects at parse
time; one collision was found and resolved (the timeline's easing *Cut* is now
*Hard cut*, which is the right word there anyway, freeing *Cut* for the
clipboard where everyone means it).

---

## Checks run

- Both repository linters (`check_continuations`, `check_shadow`): clean.
- All 52 scripts: tab-only indentation, balanced brackets, no CRLF, no illegal
  indent jumps.
- Every `Class.member` reference across the codebase resolved against what the
  classes actually declare — nothing unresolved.
- The curve mathematics ported and tested against brute-force references:
  length, spacing evenness, curvature, the straight-line degenerate case, and
  3,000 random stroke pieces.
- The compositor tested against exact premultiplied compositing over 400,000
  random pixel pairs and to 24 layers of depth.
- The page-fitting geometry tested for aspect preservation and for staying
  inside the target page on five page-size pairs.

## One thing worth deciding

The transfer **copies**; the source drawing stays exactly as it was. If you
would rather it *moved* — emptying the layers it took from the drawing project —
say so and I will add it, but I would want it to ask before it did.
