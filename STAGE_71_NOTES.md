# Stage 71 — the faults you found by running it

Running the APK found things no amount of static analysis would have. Here is
each one, what it actually was, and what I did.

## 1. The selection tools "did nothing" — because they did nothing

Not a broken button. **The marquee was never turned into a selection.**

A box could be dragged out, it drew correctly on screen, and on release the
points were simply thrown away. Every shape worked; none of them ever produced
anything to move. From the outside those two situations look identical, which
is why it read as dead buttons.

On release the mark now becomes a floating selection. Points are cleared only
*after* the lift, and only if the lift refused — a mark too small to have been
meant leaves no trace rather than a stray outline.

## 2. The symmetry handles could not be grabbed — they were drawn in one place and hit-tested in another

The rotation handle was **drawn 44 screen pixels** from the centre and
**hit-tested 70 canvas units** from it. Those are the same place at exactly one
zoom level and nowhere else, so at any other zoom you were aiming at a handle
that could only be caught somewhere off to the side.

There is now one constant used by both. The grab radius went from 24 to 38
screen pixels as well — 24 is about three millimetres on a tablet, under half
what a fingertip actually covers.

**And the guide now shows a line per pair of repeats.** Six-way symmetry is
three lines through the centre, like a snowflake — which is what the drawing
was already doing and what the guide should have been showing. An odd count
has no opposite for its last arm, so it draws spokes instead of full lines.

## 3. No way out of the rooms

The exit was there all along and nobody could find it: a grey icon of a door
on a grey plate, in a room whose whole point is that everything else has been
taken away. It is now **white, and says "Exit"**, in both the B-Spline room and
Character 360. The way out of a room you cannot otherwise leave is the one
control that must never need looking for.

## 4. Godot's file browser instead of the phone's

A game engine's debug tool: it shows a filesystem where every other app on the
device shows a photo library. The turnaround import now asks for the platform's
own picker, as the image import already did, and the new sound picker does too.

## 5. Timeline: a second tap on a layer opens its settings

As you asked, and **only on the name strip** — a tap on the frames is
scrubbing and stays scrubbing. A sheet opening under a thumb that meant to move
the playhead is the kind of interruption that makes a timeline feel unsafe to
touch.

First tap chooses the layer, because that tap already has a job: deciding which
layer the frame buttons act on.

**Link a sound** is in there, and it is now wired end to end:

- the platform picker opens on the music folder
- the sound is read and turned into one mouth per frame
- **the mesh is fitted automatically** from the ink on that layer — nobody
  draws a ring
- during playback the mouth bends to the sound, blending between the shape at
  this frame and the next, because a mouth in speech is always travelling and
  snapping between shapes is what makes cheap lip sync look like chattering
  teeth

## 6. The text box vanished when you chose another layer

It was pinned to a single layer id, so choosing anything else made it vanish —
and choosing the text layer again did **not** bring it back. The writing was
still there and had quietly become unmovable, with nothing on screen to say why.

It now follows the active layer: the box is on screen whenever a text layer is,
and gone whenever one is not. That is the rule every other handle in the app
already follows.

---

## What I found but did not fix, and why

**The B-Spline bones not reaching the project.** I traced it properly. `_pose`
does apply bones, `_bind_bones` is called after a bone is laid, and both
loading paths call `_rebind`. So the weights are being built — which means the
fault is further along, in what `Apply` bakes, and I could not tell which
without running it. **Guessing at a bake path is how a working room stops
working.** If you can tell me one thing: does the *preview inside the room*
bend when you drag a bone, or is it only the project that stays flat? Those are
two completely different bugs and that one answer separates them.

**Live move without pressing Apply.** The room's preview already updates live
on every drag. What you are asking for is the *project* updating live, and that
means the bake running per drag — a viewport render and a pixel readback per
frame. `RigSkin` from last stage is exactly the machinery that makes this
possible without the bake, and connecting the room to it is the right next
piece of work rather than something to bolt on at the end of a long stage.

**Bones tangling when dragged from the end point**, and the 90°/free joint
choice. Real, understood, and a design change rather than a repair — it needs
the joint to become a thing with a type, which is its own stage.

**Text box smoothness.** I did not touch the drag path. It is almost certainly
re-rendering the whole text layer on every move event, and the fix is the same
debounce already used while typing — but I would rather do it with the drag
path in front of me than pattern-match it.

## Files touched

`canvas_view.gd` (selection lift, symmetry handle and guide, text box) ·
`timeline_panel.gd` (layer settings sheet, `sound_wanted`) · `main.gd` (sound
picker, analysis, mesh fit) · `anim_player.gd` (`_shape_mouths`) ·
`layer_stack.gd` (`mouths`) · `bspline_room.gd` and `room360.gd` (exit button,
native picker)

Static analysis clean throughout.
