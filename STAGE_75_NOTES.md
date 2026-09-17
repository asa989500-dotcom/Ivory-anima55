# Stage 75 — the rooms, the layers, and the brush

## 1. Adding a layer

Two pieces of waste, both real:

**Every layer was re-ordered in the scene tree on every structural change.**
`move_child` re-indexes children and marks the canvas dirty. Adding one layer
to a stack of twenty did twenty of them — nineteen of which moved a node to
exactly where it already was. It is guarded now: moved only where the order
actually differs.

**The panel was built twice per tap.** Adding a layer fires `changed` *and*
`active_changed`, and both rebuilt every row. One tap built the whole panel,
threw it away, and built it again before drawing anything.

They are coalesced into one rebuild at the end of the frame — deferred rather
than timed, so the panel is never a frame behind what it is showing; it simply
stops being built more than once for the same frame. That also fixes drags
between folders, which fire several signals at once.

## 2. The brush draws curves now, not chords

The path between two touch points is a **curve**, and this drew it straight.
On a slow stroke that is invisible. On a fast one the touch points arrive
thirty or more pixels apart and the mark comes out as a polygon — a visible
corner at every sample. That is what people mean when a brush engine feels
cheap.

Each new point is drawn as a quadratic curve: **from the midpoint of the last
pair, through the last point, to the midpoint of the new pair.**

Measured on a fast arc:

| | sharpest corner |
|---|---|
| straight chords | **17.19°** |
| the curve | **0.17°** |

A ninety-nine per cent reduction in the artefact.

**Why this shape and not a fitted spline** — three reasons, all tested:

- **It cannot overshoot.** A quadratic Bézier stays inside the triangle of its
  three points, always. Catmull-Rom fits better and bulges outside a sharp
  turn, which on a brush stroke means ink where the finger never went. Checked
  over every piece: never leaves its own hull.
- **The joins are exact.** Consecutive pieces share an endpoint by
  construction — the same midpoint — so there is no gap to seal. Measured gap:
  0.00e+00.
- **A straight stroke stays exactly straight.** Measured wobble on a ruled
  line: 2.8e-14. A smoother that ripples a straight line is worse than none.

**Walked by arc length, not by even steps in `t`.** Stepping `t` evenly bunches
stamps where the curve is tight and spreads them where it is straight — which
turns a brush's own spacing, the thing that makes ink look like ink, into
something that changes with how hard you turned. Measured gap variation along a
curve: under 1%.

**And the two ends are handled.** A new stroke carries no bend from the last
one, or every mark would begin with a hook toward wherever the previous stroke
finished. And the tail is run out straight when the finger lifts — the curve
deliberately leaves its last half-segment undrawn because the point that
decides its shape has not arrived yet, and at the end of a stroke it never
will. Without that, every mark stops a few pixels short of its own end, most
visibly on exactly the short flicks where it matters.

## 3. The B-Spline room now reaches as far as Character 360

The 360 room got this two stages ago and the B-Spline room was left behind:

- **Zoom ceiling 24× → 64×**, floor down to 0.02. A bone is placed at the scale
  of the *joint*, not the figure. At 24× a knuckle on a full figure is a few
  pixels across and a point lands on the finger beside it.
- **The grab is measured on the screen**, not in page units. Twenty-two page
  units was a hand's width when zoomed out and nothing at all when zoomed in —
  which is precisely when a point is being placed carefully. It is now a
  fingertip's width at every zoom, scaled for the device.
- One constant for both the pinch and the buttons, so they cannot drift apart.

---

## Still open

The **animation layer for B-Spline bones** is the one substantial thing left
from your list, and it is genuinely a stage: it needs the folder to become
something that holds a skeleton across several layers rather than a flag on
one. I would rather start it clean than begin it here.

## Files touched

`layer_stack.gd` (guarded reorder) · `layers_panel.gd` (coalesced rebuild) ·
`canvas_view.gd` (curve stamping, stroke ends) · `bspline_room.gd` (zoom range,
screen-sized grab)

Static analysis clean throughout; the curve maths verified in Python before it
was written, including the one test that corrected me — midpoint smoothing does
not reduce radial error, it removes corners, and the note in the code says so.
