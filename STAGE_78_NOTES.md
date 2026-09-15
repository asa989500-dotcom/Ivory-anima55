# Stage 78 — autosave made safe

Autosave already existed, so "ultra" here does not mean adding it. It means the
three things that decide whether an autosave is a feature or a liability.

## 1. The manifest is written atomically

**This is the important one.**

The document was opened for writing *at its own path*. Opening a file for
writing empties it first and fills it afterwards — so between those two
moments, the project on disk is garbage.

That window is short and it is **not rare**. This app saves by itself, and
Android kills backgrounded apps as a matter of routine. Being killed inside
that window is a normal Tuesday, not bad luck.

It is now written to `project.json.writing` and **renamed** over the real file.
A rename is atomic on every filesystem this will run on: it either happened or
it did not, so the manifest is only ever wholly the old document or wholly the
new one. There is no half-written state to recover from.

The `.bak` copy stays — but it is no longer the *first* line of defence, which
is what it had been doing.

**And the temp file is checked before it is trusted.** A disk that filled up
mid-write returns no error from `store_string` and leaves a short file.
Renaming *that* over a good document destroys the good one — so the length is
read back first, and a suspiciously short file is deleted and the save
reported as failed, leaving the project dirty for the next attempt.

## 2. It never saves in the middle of a stroke

A save is tens of milliseconds of disk work. Doing it while a line is being
drawn puts a visible hitch in that line — and the timer is *most* likely to
come round exactly then, because drawing is what makes a document dirty in the
first place.

The save now waits for the hand to lift, and retries in three quarters of a
second. A second's delay costs nothing; a stuttering stroke costs the drawing.

**Every gesture that a pause would spoil is covered**, not only drawing: a pin
being pulled, a selection being dragged, a shape being stretched, the writing
being turned, a symmetry axis being moved, the dropper being aimed. All of them
move under the finger and all of them show a hitch the same way.

## 3. One project per turn, and an earlier moment to save

Three dirty projects written in one frame is three times the hitch, in one
place, for no reason. One is written per turn of the timer, and when others are
waiting the timer comes back in two seconds instead of the full interval.

Saving now also happens on **focus-out**, not only on pause. On Android the
pause notification is the last thing an app reliably gets, and by then there
may be very little time left. Focus-out arrives earlier — when the notification
shade comes down, or the task switcher opens — and most of the time that is the
real moment the user stopped drawing.

---

## Two mistakes caught before shipping

Worth recording, because both would have been crashes rather than glitches:

- I called `view.is_drawing()`, which **did not exist**. It does now, and it
  covers every gesture rather than only the brush.
- I called `_sel_grab`, which does not exist either — the floating selection is
  tracked by `sel_active`. Checked against the real field list rather than
  assumed.

I also removed a loop I had written to re-mark the remaining projects dirty:
`take_dirty` only *reports*, it never clears — deliberately, so a failed write
stays dirty and is retried instead of being quietly declared saved. The
re-marking was redundant, and redundant code in a save path is code that will
one day be read as load-bearing.

## Files touched

`vault.gd` (atomic write, length check) · `main.gd` (stroke-aware timer, one
per turn, focus-out) · `canvas_view.gd` (`is_drawing`)

Static analysis clean throughout; every identifier the new code touches was
checked to exist.
