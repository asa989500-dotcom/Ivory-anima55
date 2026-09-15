# Stage 80 — units by number, a real iris, and an autosave that keeps the last stroke

Three of the nine things asked for. The other six are each a stage of their
own and are listed at the foot of this file in the order they were asked for.

## 1. Frame-rate units, without the dragging

The arrows on the band are still there and still the quickest way to find the
right frames by eye. What was missing was the other way of working: a unit that
has to land exactly on frames 41 to 47 should not have to be *aimed* at them
with a thumb over a grid seven points wide.

Two taps on a unit now open, alongside its rate:

- **First frame** and **Last frame**, each with a step either way and the
  number itself tappable to type it outright on the ten-key pad.
- **Begin at the playhead** and **End at the playhead**, for the common case
  where you are already standing on the frame you mean.

Every one of these goes through `_set_unit_edge`, which is the same clamping
the drag arrows use. There is one rule about where a unit may reach and it
cannot be got round by typing what could not be dragged: both ends still stop
dead where the neighbouring unit begins.

## 2. Depth of field: an aperture, not an average

The old blur was a flat disc of samples with bright pixels weighted a little
heavier. That is a good blur. It is not a lens.

`lens_blur.gdshader` was rewritten around three things a lens actually does:

- **The iris has blades.** A real aperture is a polygon of five to nine
  leaves, and out-of-focus highlights come out as that polygon — hexagons
  behind a portrait, not circles. The blade count is chosen per focus line:
  round, six, seven or nine. It lives on the focus line rather than on the
  layer because one camera is looking at the whole scene, and two layers
  softened through two different irises would be two cameras.
- **Only highlights bloom.** The old weighting lifted every bright pixel,
  which washes a picture out. There is now a knee: mid tones weigh exactly
  one, and genuine highlights climb far above it and swell into their
  neighbours the way defocused light does. Light is judged on the *straight*
  colour, so a sample sitting on empty paper is not mistaken for a dark pixel.
- **Distance hazes.** Blacks lift very slightly as the softness deepens, and
  only in proportion to it — multiplied back by the pixel's own alpha, so the
  paper around the drawing stays paper. It is a small number and it is the
  difference between a background that sits *behind* the subject and one that
  sits under it.

The sample count now follows both the radius and the device: a wide blur with
too few samples is a ring of ghosts, and a narrow one with fifty samples is
fifty reads of nearly the same pixel. On a slow device the ceiling comes down
rather than the effect being switched off — a grainier wash looks like film, a
dropped frame looks like a fault.

## 3. Autosave

**The bug.** A stroke lives in three places on its way to disk: dabs queued on
the GPU, the CPU mirror of the surface, and the compressed cel the frame keeps.
`Vault.save` called neither `flush_all` nor `commit_all_cels`, so a save landing
shortly after the hand lifted wrote the layer *without the last dabs of the
stroke*, and wrote a cel dictionary still holding whatever was there at the last
frame change — which on a timeline is every drawing except the one being worked
on. Both calls now happen before a single byte is written. Both are cheap when
there is nothing pending, which is the usual case.

**The timing.** Autosave counted down twenty-five seconds and wrote whatever
was dirty. It now asks a question every second, and writes when all three of
these are true: something is waiting, it has been waiting six seconds, and the
hand is not down. Ten seconds is the least that may pass between two writes, so
a busy hand cannot turn this into constant disk work.

**The order.** `mark_dirty` records when a project *first* became dirty rather
than the latest change — a clock restarted by every dab would never run out for
exactly the project with the most to lose — and `take_dirty` now returns the
longest-waiting project first. Before, with two dirty projects, the same one was
written every time and the other could sit unsaved indefinitely.

Saving on close, pause and focus-out was already right and is untouched.

## Still to come, in the order asked

4. **Lip sync** — a stable audio path, opening the device's own files, and the
   nine mouth shapes made to bend properly on a circular ring.
5. **Character 360** — a better build from the eight photographs, orbit camera,
   a `character 360` layer that can only be drawn *on* the character and turns
   with it, support for houses, cars and anything with clear dimensions, and
   automatic trimming of a photograph taller than its fellows.
6. **B-Spline** — points, bones and bending, and keeping a bone's own drawing
   from catching hold of any other drawing inside or outside its layer.
7. **Frame by frame** — making straight-ahead drawing as smooth as the app can
   make it.
8. **Selection tools** joined to the Character 360 and B-Spline layers: scaling
   without loss, copy and paste that carries the bones, and layers added or
   removed on one frame leaving the frames before it alone.
