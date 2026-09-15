# Stage 89g — the bones move the drawing, and why the room was heavy

You were right that it is not your device. It was work being done and thrown
away between frames nobody ever saw.

## 1. "The bones move and the drawing does not"

**The posed drawing was never drawn. Not once.**

Everything before the last step was already correct. `_pose` computes the
deformed vertex positions into `_now` on every drag. `_push_mesh` builds a mesh
from them. But `_push_mesh` opens with:

```gdscript
if _mesh_node == null or _now.is_empty():
    return
```

and **`_mesh_node` was never assigned anywhere in the file.** Declared on line
88, read in two places, and never given a value. So every posed vertex was
computed correctly and thrown away, and `_draw_art` painted the flat rest
texture over the top.

The bones were moving. The mathematics was right. There was simply nothing on
screen showing the result.

Now the mesh is drawn directly, which is better than resurrecting that node:
the vertices are in page coordinates and the page-to-screen map is a pure scale
and offset, so one `Transform2D` carries them. No second node to keep in step
with the pan, the zoom and the board's redraws — and the rig can never be a
frame behind the finger.

## 2. Why it felt heavy

A finger reports 120–240 times a second. The screen redraws 60. `_pose` was
running on **every input event**, doing the same nine thousand vertices three
or four times over between one frame and the next, and all but the last was
discarded before anyone could see it.

`_pose` now raises a flag; `_process` does the work once a frame. Same result
on screen, a third to a quarter of the arithmetic.

`_settle_pose` exists for the one case that must not wait: Apply reads the
vertices rather than showing them, so a deferred pose would mean stamping the
figure as it stood one frame ago.

## 3. Two bones, one elbow

A chained bone starts exactly where its parent ends, so drawing each bone whole
put two markers on the same spot — reading as two joints where the skeleton has
one.

Bodies and joints are now drawn separately: the spindles are laid down, then
every joint is gathered, coincident ones folded together, and each place marked
once. Coincidence is measured **on screen**, not on the page — a gap the eye
cannot resolve should read as one joint however far the room is zoomed.

A shared joint is a hinge if *either* bone meeting there says so; the constraint
belongs to the joint, not to whichever bone happened to be drawn first.

And taking hold of one takes hold of the chain. `_joint_at` prefers the end that
has a parent, as a strict preference rather than a distance comparison — the two
ends sit at the same place, so comparing distances between them decides nothing,
and decides it differently every time the rig is nudged.

## 4. The way out

Enlarged, and gold on dark ink instead of grey on grey. It was drawn in the
rail's own colours, which are made to sit *quietly* behind a drawing — the
opposite of what the only exit from a full-screen room should be. It is now the
one gold thing at the top of the room and the only control up there.

Its position is also measured from its own width rather than a number typed
twice; the two had drifted apart the moment the button changed size.

(The off-screen anchor bug from last stage is fixed and still fixed. The
hardware Back button steps out of the room too.)

## 5. The room's colour

`ROOM_BLUE` — `#2A6D80`, taken from the mark on the application.

It was very nearly black, and on a near-black field a dark drawing is a drawing
you cannot see. In a room built for placing points on artwork precisely, that is
the one thing the background must never do.

The teal is light enough that dark ink reads against it and still dark enough
that ivory and gold read against *it* — so the grid, the gold page frame, the
canvas box and the bone colours all stayed exactly as they were. Only the grid
lines were re-tinted into the same family, and the curve's dark halo, which had
been tuned for a black field.

---

## The timeline — what I found, and what I did not do

I read it before touching it, and **the obvious suspects were already handled**:

- Drawing is culled to the visible frames *and* the visible rows — a
  six-hundred frame clip does not cost six hundred circles a redraw.
- `_process` shuts itself off (`set_process(false)`) the moment no press is
  being held.
- `reach()` is one question per layer, not one per drawing, and `last_frame()`
  reads a sorted cache.

So the cheap wins are already spent, and I am not going to invent an expensive
one from reading. **Reporting that honestly is worth more than a change I cannot
justify** — I shipped a guard two stages ago that broke the whole build, and
that is what guessing at code I have not measured produces.

What would settle it in one message: open the timeline on your tablet, let it be
slow, then send the **Profiler** tab sorted by *Self* time. The top five lines
name the real cost. If it is `_draw_body`, the fix is one shape; if it is
`_layout_rows`, it is a completely different one — and right now nothing in the
code tells me which.

## Checks

All four linters clean: 0 impossible returns, 0 suspect continuations,
0 redeclarations, 0 unresolved symbols across 52 scripts.
