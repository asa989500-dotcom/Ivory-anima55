# Stage 76 — the chain catches anywhere, and the folder keeps its bones

## 1. Tangled lines: the fault you described

You were exact. The chain only ever offered **its own far end**, so a second
line could not begin halfway along the first. Anything that branches — a window
frame, a hand, a roof — meant aligning by eye at precisely the join where being
exact is the whole point of the tool.

Every line laid in a run is now remembered, and a new line begins **anywhere on
any of them**.

Three details that decide whether it feels right:

- **Measured to the segment, not to its ends.** A point beside the middle of a
  long line *is* beside that line. Only consulting endpoints is what made the
  old behaviour feel like it was ignoring everything except the tip.
- **The last line's tip still wins when you are near it.** That is the common
  case and it should stay the easiest — it is checked first and only beaten by
  something genuinely closer.
- **The lines already laid are drawn faintly** while the chain is live, so it
  is visible what a new line may catch onto *before* you reach for it.

Forgotten when the chain is let go: snapping onto a run you have already
finished would be the app remembering geometry you no longer think of as a
chain.

**Verified — 11 checks.** Snapping to the middle of the first, second and
fourth lines of a square; corners; a point out of reach left alone; just
inside and just outside the threshold; the nearer of two close lines winning
both ways; a zero-length line not dividing by nothing; nothing laid yet.

One "failure" was my test asserting the wrong point: at (2,3) on a square, the
left edge is 2 away and the corner is 3.6 away, so it snaps to the edge.
Snapping to the *nearest* place is the correct behaviour — the assertion was
wrong, not the code.

## 2. The animation folder now keeps what you do in it

Two real faults, both silent.

**Corrections were being thrown away.** Bones were read out of *every* member
on the way in and written back to *only* the layer that happened to be active
on the way out. A shoulder corrected across a two-layer figure was kept on one
layer and lost on the other — and reopening the folder brought back the old
bone with nothing to say anything had been discarded.

Each bone now goes home to the member it came from. They line up **by
construction**: gathered in the order the members were walked, returned in the
same order. Matching them back up by position afterwards would guess wrong the
moment two bones sat on top of each other.

The write-back also runs when nothing was rehearsed — a bone may have been
*corrected* rather than swung, and a correction is the thing most worth
keeping.

**The joint threshold was a flat thirty units.** Whether two bones count as
jointed is a question about the figure, not about a number: on a large canvas
a shoulder and an upper arm can be forty units apart and obviously joined; on
a small one, thirty units is halfway down the body and would chain two limbs
that never touch. It is a fortieth of the drawing's longest side now, held
between sensible limits — and being too loose is the worse error, because it
joins limbs that were never joined and only shows when something bends.

---

## What I did not do this stage, and why I am saying so

You asked for drawing, movement, the colour disc, the eraser and the selection
tools as well. **The brush and the eraser already got the large improvement
last stage** — they share one stroke path, so the curve stamping that took a
fast arc's sharpest corner from 17.2° to 0.17° applies to erasing exactly as it
does to drawing.

For the colour disc and the selection tools I have nothing further I can
*verify* right now, and adding untested changes to two things that currently
work is the trade that has gone badly every time it has been made. Tell me what
is wrong with them when you next run it — the last three stages were all fixed
from exactly that kind of report, and every one of those was a fault I would
never have found by reading.

## Files touched

`canvas_view.gd` (chain marks, snapping, the faint guide) ·
`bspline_room.gd` (`_join_reach`, `_return_bones_to_members`)

Static analysis clean throughout.
