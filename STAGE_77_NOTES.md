# Stage 77 — the text box, and why it walked like a mountain

You reported this several stages ago and I deferred it, saying I wanted the
drag path in front of me before pattern-matching a fix. Here it is, and the
cause was worth waiting to see properly.

## The fault

`draw_text_box()` asked `text_bounds()` for the rectangle. `text_bounds()`
called `content_bounds()`. And `content_bounds()` **walks every tile the layer
owns** to work out its extent.

The overlay redraws on every move event. So dragging the writing re-walked the
whole layer — sixty times a second — to recompute a rectangle **that had not
changed.** A text box does not grow or shrink while it is being carried. It
only moves.

That is the whole of it: the most expensive question in the drag was being
asked constantly, and the answer was the same every time.

## The repair

The box is taken **once** when the grab begins and dropped when the finger
lifts.

Nothing is cached across gestures, and that is the part worth stating: the only
window it covers is the one in which the answer *provably* cannot change. A
cache that outlived the drag would be a stale rectangle waiting to be found,
and the drag is exactly as long as the guarantee is good for.

## And the grip was too small to catch

`26.0 / view_zoom` was correctly screen-sized, but it never scaled for the
device — twenty-six raw pixels is about three millimetres on a tablet, under
half what a fingertip covers. The turn grip was accurate to the eye and missed
by touch, which is the same fault the symmetry handles had.

It is `34.0 * App.ui_scale` now. With that, **every touch target in the app
follows one rule**: measured on the screen, scaled for the device, converted
to page units at the point of use. The symmetry handles, both rooms' grabs, the
chain snap and the text grip were each written separately and each got this
wrong in its own way; they now get it right in the same way.

---

## Where I have stopped, and it is not evasion

That was the last reported fault I had a clear, checkable cause for.

For the colour disc and the selection tools I still have nothing I can verify —
they work as far as I can tell by reading, and the honest position is that
reading is not enough. Every real improvement in the last several stages came
from one of two places: a number I could test in Python before writing it, or a
symptom you described from running the app. Neither is available for those two
right now.

So rather than adding untested changes to things that currently work, I would
rather have one sentence from you about what they do wrong. That has been worth
more than anything I have found by inspection — the selection tools that turned
out never to build a selection, the symmetry handle drawn in one place and
hit-tested in another, the marker painted underneath the colours, the two
meshes drawing one layer. Not one of those was findable by reading.

## Files touched

`canvas_view.gd` (`_hold_text_box`, the cached bounds, the finger-sized grip)

Static analysis clean throughout.
