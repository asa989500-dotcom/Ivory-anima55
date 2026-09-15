# Stage 73 — a rehearsal is a rehearsal, and one body means one body

## 1. Swinging a bone is a rehearsal now

Your answer settled the design, and it is the better one.

Swinging a bone exists to **try** a bend — does that shoulder reach, does the
elbow land where it should. It is not a pose being authored. Treating it as one
is how a rig comes to leave the room bent into whatever position it happened to
be in when your finger last lifted: nobody's intention, and very hard to notice
until a whole scene is wrong.

So the bones go back to rest before anything leaves the room. **What is
committed is the body the bones were built on** — the drawing as it was drawn.

Two details that make it trustworthy rather than merely correct:

- **The skeleton is kept; only the swing is thrown away.** Where the bones
  *are* is a rehearsal. Where they were *laid* is the rig, and that is saved
  exactly as before.
- **Leaving by Exit is as safe as leaving by Apply.** A safety that only works
  when you leave the tidy way is not a safety.

And it says so on screen, once, next to the mode buttons — because a rule this
important should not have to be discovered by noticing it did not happen.

## 2. The repeated bodies in the puppet warp

Found it, and it is a real fault with a specific cause: **two different things
were drawing the same layer.**

A layer can already be stood in for by a `RigSkin` — a mesh holding a picture
of it, put there by a pose or by a linked mouth. The puppet warp is a *second*
mesh holding the same picture. Neither knew about the other, so both drew: the
drawing appeared twice, sitting on top of each other, and drifting apart as
either one was touched. That is the "duplicate bodies" exactly.

Three fixes, each closing a separate way to get there:

- **The skin is shed before a warp begins.** There is now exactly one thing
  drawing a layer at any moment. That rule is what the whole design rests on
  and this was the one place it was not enforced.
- **A second warp ends the first.** Starting one while another was live left
  the first mesh on screen with nothing driving it — a body frozen mid-pull
  that no control could reach.
- **The surface is flushed before it is copied and erased.** An unflushed tile
  is a tile whose pixels are still on the way; erasing over it wipes the old
  ones while the new ones arrive afterwards, which reads as the drawing coming
  back from the dead a moment later.

You said it plainly: *give each thing a clear job, not stupid merges.* That is
what this is. The warp owns one layer, alone, for as long as it runs — and the
panel now says so, so it is a stated rule rather than one you have to infer
from the absence of a bug.

---

## Still open, and not padded out

**Strengthening the two rooms further**, the **animation layer for B-Spline
bones**, faster layer adding, and the brushes. Each is a stage. The last three
stages each turned up a real fault in something I would otherwise have called
finished — pinch folding through itself, the colour marker drawn underneath the
colours, two meshes drawing one layer — and every one of them was found by
looking closely at one thing rather than touching four.

Tell me which of those four you want next and I will take it the way `RigTrack`
and the morph were taken.

## Files touched

`bspline_room.gd` (rehearsal, reset on both exits, the on-screen note) ·
`canvas_view.gd` (shed the skin, end a live warp, flush before erasing) ·
`tool_panels.gd` (the warp's ownership note)

Static analysis clean throughout.
