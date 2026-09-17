# Stage 89j — frames to disk, and the rigs that were already arriving

## Apply and Export — I checked before changing anything

**Both buttons were already carrying everything.** I traced them end to end:

`_apply` (B-Spline) writes `layer.rig` — every bone, its rest ends, its posed
ends, its hinge and its parent.

`_take_360_character` (Character 360) sets `layer.character`, `layer.rig_360`,
`layer.turn_360` and `layer.is_360`.

And the vault writes **all** of it to disk and reads it back: `is_360`,
`turn_360`, `rig_360.to_dict()`, the turnaround's own document.

Nothing was being lost. The gap was the same one as the bones last stage, one
level along: **nothing on the canvas ever drew the turnaround's rig**, so from
where you stand the character arrived without it.

Now it does. The three kinds of control the room builds, in the room's own
colours — read from `Rig360`'s constants rather than typed again, so the rig on
the canvas cannot drift into being a second palette:

- bones as spindles with a grip at each end, riding their `carry` so they sit
  on the figure at whatever angle it is turned to
- joints in their three grades — green grandparent, red parent, amber child
- rings as the circles they are, flattened along the axis they turn about so
  which way one will spin is readable from its shape

Dead rings are not drawn. They are still holding — that is what marking one
dead is *for* — but a pin doing its job silently should not be in the way of
the drawing it is holding still.

## Frames to disk

You asked for this last time and I said I would not start it in the same build
as a rig rewrite. Here it is.

**First, an honest number.** A cel is already a compressed PNG in memory, not a
raw image, so a drawing costs what its ink costs and not what its page costs.
That makes this a refinement, not a rescue. But a six-hundred frame scene with
eight layers is four and a half thousand cels, and at a few hundred kilobytes
each that is still more than a tablet will give one application:

| | |
|---|---|
| every cel resident | 844 MB |
| 96 frames either side of the playhead | 271 MB |
| **freed to disk** | **572 MB (68%)** |

**The working set follows the playhead.** `page_around` runs from
`show_frame` — the one place that knows where *here* is — so the scene is only
ever expensive in the direction you have walked away from.

Ninety-six either side is generous on purpose. Flipping back and forth across a
few drawings is what an animator does constantly, and a cel that has to come off
disk to be seen is a cel that makes the flip stutter. Ninety-six covers four
seconds at twenty-four in both directions; past that you are scrubbing, not
flipping.

**Nothing outside `cel_track.gd` knows it happens.** Every reader calls
`_page_in` first, and I traced all eight places the bytes are touched to confirm
it — including `to_dict`, so a save always writes every cel and paging can never
cost you work.

**A settled scene costs reads and no writes.** A spilled cel keeps its file
until it is redrawn; `_forget` clears it at all four places a cel is rewritten.
Cels under 8 KB are never spilled at all — reading one back would cost more than
the bytes save.

**And the files go away.** `drop_spill` runs when a layer is finally purged —
one that redo can no longer reach, whose drawings are gone for good. Without it
the folder would grow by a file per cel per session and nothing would ever
remove them: the "clearing memory only frees it for a moment" complaint, one
level down, somewhere nobody would think to look.

## What I have not done

**Deeper animation quality in the two rooms.** Last stage's rig rewrite — the
hard reach per bone, the ink test demoted to a preference, two influences per
vertex — is the substance of that work, and it has not been in your hands for a
single test yet. Pose a figure with it and tell me what still bends wrongly.
That answer shapes the next change; guessing at a second rewrite on top of an
untested first is how the last two builds broke.

## Checks

`python3 tools/check_all.py .` — all four pass, run from inside the unpacked
zip as well as here.
