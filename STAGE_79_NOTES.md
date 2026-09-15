# Stage 79 — the thirteen errors, an endless band, and frame-rate units

## 1. The thirteen errors

All thirteen were one fault.

`scripts/ui/tool_panels.gd` declared `var row: HBoxContainer` at line 705 for
the copy-and-paste strip, and then reused `row` as the variable of two `for`
loops further down the same function (lines 748 and 777). GDScript forbids a
second local of the same name anywhere inside one function, loop variables
included, so the parser stopped there and the class `ToolPanels` never got
built. Every one of the thirteen messages in `main.gd` was the same class
failing to resolve, reported once per call site.

The two loops are now `kind_row` and `cut_row`.

The whole project — 49 scripts, some 27,000 lines — was then swept for the
same class of fault and for bare constants used without being declared (the
kind of thing that produced the `TAP_MS` error in an earlier stage). Nothing
else of either kind is left.

## 2. The band has no end

`clip.length` used to be both "how far the scene runs" and "how far you may
scroll", and the two are not the same question.

- Scrolling right is now unbounded. There is always one more screen ahead of
  wherever you are, and it keeps being true however far you go. A drag can
  only carry the grid as far as the finger travels, so it is impossible to be
  thrown somewhere distant by accident.
- Scrubbing past the last drawing takes the scene with it, so an empty stretch
  can be gone to and drawn on.
- What *plays* is worked out from the work in the scene — `Clip.reach()` — not
  from how far anybody has scrolled. Going to look at frame four hundred never
  adds four hundred frames of nothing to the film.
- A hold dragged out past the last drawing is now remembered explicitly
  (`Clip.tail_hold`). Nothing else in the file records it, so without this it
  would have been cut back to its starting drawing on reopening.
- `CelTrack.last_frame()` was added so measuring the scene costs one question
  per layer rather than one per drawing — it is asked on every rendered frame.

## 3. Where the band starts and stops

Two buttons on the head bar, carrying their own numbers: `◂ 1` and `0 ▸`.

Each opens a ten-key pad — not a text field, which on a phone means the system
keyboard covering the band the number is about. Nought in the second one means
no end at all, which is both what the button shows and what you type, so the
two never have to be learnt separately.

This is a *view* window. It changes what is on screen and nothing else: the
frames outside it are still there and still in the film. The play range, which
does change what is played, is where it was, in the timeline settings.

## 4. Dividing the frame rate into units

The supplied icon sits with the frame controls, because what it changes is the
timing of frames.

- **A tap** lays an ivory box down at the playhead, four frames wide. If the
  playhead is already inside a unit the new one begins where that one ends —
  never on top of it. Two rates over one frame cannot be played, so it cannot
  be made: `Clip.free_slot` walks forward rather than searching.
- **The box** is cream and translucent and spans every layer from the ruler to
  the foot of the band, because a unit is a stretch of *time* and everything
  passes through it at the same rate. It carries its own numbers: rate, frame
  count, and seconds.
- **The arrows** on its edges resize it. The left one is absent at the first
  frame of the band, since there is nothing there to give ground. Both are
  clamped against the neighbouring units, so boxes meet exactly edge to edge
  and never climb over one another however hard the drag is pushed.
- **Hold and drag** slides the whole box, keeping its length.
- **Two taps** open its rate: a slider from 2 to 60, the useful rates as chips,
  and a way back to the scene's own rate. It reads out the frames covered and
  what they come to in seconds while you move it.
- **Holding the button** lists every unit in the scene and goes to one — the
  only way to find a unit that has been scrolled far off an endless band.

Slowing a unit does not lengthen the band. Six frames at two a second are
three seconds where they stand, and everything after them simply happens three
seconds later than it otherwise would.

Two things had to follow from that:

- `AnimPlayer` no longer advances the playhead by one rate. A rendered frame
  can begin outside a unit and end inside it, so the slice of time is spent
  segment by segment at each segment's own rate. Multiplying the whole slice by
  one number would misplace the playhead at every boundary — a small error that
  accumulates until picture and sound no longer line up.
- The ruler no longer marks every frame divisible by the scene rate. It marks
  where a new whole second actually begins, asked of the clip. Inside a slowed
  unit the marks spread out and inside a quickened one they crowd together.

Units are saved with the scene, shift when a frame is inserted, and are read
back defensively — a file carrying overlapping units is repaired on load rather
than trusted.

## 5. Languages

Twenty-five new strings, in all seven languages.
