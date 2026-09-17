# Stage 66 — the in-betweener stops faking it

## 1. What the "AI" was actually doing

It was a cross-dissolve wearing a costume.

`_draw_figure` drew both neighbouring poses on top of each other, handed over
between them on a steep opacity curve, and squeezed them horizontally to
suggest a rotation. That has one flaw and it is fatal:

> **For the whole middle of every turn there were two silhouettes on screen at
> once.**

The front view's shoulder is here; the side view's shoulder is there. No
opacity curve fixes that, because the eye is better at catching a doubled
outline than at almost anything else. It is exactly why fading turnarounds
always read as photographs fading rather than as a character turning.

## 2. What replaces it — `scripts/turn_morph.gd`

**It makes the two drawings agree on where the figure is before it blends them
at all.**

For each drawing it measures a *profile*: at forty-eight heights up the
figure, where the left edge is and where the right edge is. That is the
silhouette reduced to something two drawings can be compared on.

To build an in-between:

1. Blend the two profiles → a **target silhouette** for this exact moment.
2. Warp drawing A through a mesh so its own left edge lands on the target's
   left edge and its right on the target's right, everything between carried
   across in proportion.
3. Warp drawing B **backwards** by the same amount, so the two meet in the
   middle rather than one travelling the whole way.
4. *Only now* blend them.

Both are standing inside one outline, so the blend has nothing left to give
away: what crosses the screen is a single figure changing shape, not two
figures at unequal strength. Measured agreement between the two warped
silhouettes: **2.8e-17** — not approximately aligned, the same curve.

Verified before a line of GDScript was written: the mapping was ported to
Python and checked for silhouette agreement across 101 sample moments, order
preservation across every row (interior points never cross), and the
degenerate cases — a row of zero width, a row where B is wider than A.

**Three decisions worth defending:**

- **The horizontal squeeze is gone, and not by oversight.** It was a *guess* at
  how much narrower a turning figure gets. The profile now *measures* that.
  Keeping both would have narrowed the figure twice.
- **The hand-over curve is gentler now.** The steep one existed to spend as
  little time as possible showing two figures — because two figures was the
  failure. With that gone, an even blend is better: what crosses over now is
  the *texture* — the shading, the line weight, the eyes — and texture
  crossing evenly reads as a surface turning into the light.
- **Empty rows carry their neighbours' shape.** A row with no ink has no
  edges, and left alone it collapses to the centre line and pinches the figure
  at exactly the heights where it is thinnest: a neck, a wrist, the gap above
  the head. Tested against four gap cases; no row ever collapses.

**What it still refuses to do:** compute depth, build a volume, reconstruct a
third dimension. At t=0 you are looking at drawing A exactly as drawn; at t=1,
drawing B exactly as drawn. The machine's guess only ever lives in between,
which is the correct place for it.

Profiles are measured **once at import** — a crop, a resize and a scan of a
small grid per drawing. Nothing at import; everything at sixty frames a second.
And if a profile is missing, the old flat draw still runs, so a figure that
draws the old way beats a figure that does not draw.

## 3. Duplicate After now carries the bones

Both kinds — the flat 2-D bones bent in the B-Spline room and the turnaround's
own rig — live on the layer's `poses` track, so one join covers both.

This was the missing link between the two halves of the app. Duplicating a
frame moved the drawing forward and left the skeleton behind, so the next bend
keyed a pose with no previous key to travel from, and bones and frames looked
like two unrelated features.

**Carried, not blended.** Duplicate After means *the same thing, one frame
later, as a place to change something* — so the new key is an exact copy and
the tween is flat until you move something. It reads the pose **at** the frame
rather than the key at the frame, because the frame being duplicated may sit
between two keys, and what should carry forward is what was on screen.

A layer with no poses gets nothing. No empty key appears on the band to be
wondered at.

## 4. Onion skin comes on when you step a frame

Stepping to the next frame is the moment onion skin is *for*: you are there to
draw the frame after the one you just drew, and the one you just drew is what
you need to see.

Turned **on**, never toggled — stepping never turns it off, so if you switched
the ghosts off deliberately that stays done. Also forces a look-back of at
least one, because ghosts "on" showing nothing looks exactly like a broken
feature.

## 5. The settings panel

Its height cap was a flat number, so on the opening screen — where the menu is
longest — the panel grew past the bottom of the display and its last rows could
not be reached. It looked taller than its own button because it was. It now
takes the same screen-relative ceiling the tool panels were given in stage 62;
the settings pages had been left behind.

---

# You asked what is weak in the animation project. Here it is, worst first.

**1. A turnaround is not saved. At all.**
`vault.gd` writes `is_360` and `turn_360` and *never writes the character*.
Close the project and the eight drawings are gone; the layer comes back
flagged as a 360 layer with nothing inside it. This is the most serious thing
in the animation project and it is not a small fix — the eight images need
writing beside the cels, which means deciding whether they are re-encoded per
project or referenced. **I would do this next.**

**2. Poses never reach the canvas.**
`AnimPlayer` emits `rig_posed` correctly; nothing outside the B-Spline room
listens. So a rigged layer plays back its poses only while that room is open.
Everything under it is built and tested — what is missing is the listener that
takes a pose and re-skins the layer's mesh on the main canvas.

**3. There is no way to make the first key.**
`record_key`, `set_switch`, `step_switch` all exist and none has a button.
Duplicate After can now carry a pose forward, but you cannot yet *create* one
from the timeline. This is the smallest of the three and unblocks the most.

**4. No sound.** Lip sync with nothing to sync to. Switch folders are in and
correct, and a mouth chart with no waveform to step against is a chart you
step by counting. For a professional animation app this is a real hole.

**5. Onion skin shows drawings, not poses.**
A rigged layer's ghosts show the same drawing at every frame, because the pose
is not baked into the cel. Ghosts of a *bone* pose need the mesh solved per
ghost frame — cheap enough at two or three ghosts, and currently not done.

**6. `Character360.foreshorten` is now dead in the main path.** Harmless, kept
for the fallback, and worth deleting once profiles are known to be everywhere.

Say the word on **1**, and I will take the turnaround's persistence properly —
the same way `RigTrack` and this morph were taken: designed against the grain
that is already there, verified where verification is possible, and honest
about the rest.

## Files touched

new `turn_morph.gd` · `character360.gd` (profiles at import) · `room360.gd`
(morph draw) · `timeline_panel.gd` (`_carry_pose`, `_step_frame`) ·
`settings_panels.gd` (height ceiling)

Static analysis clean: use-before-declaration 0, brackets balanced, no
duplicate functions, no unused parameters, no shadowing, no new class cycles.
Geometry verified numerically in Python before it was written.
