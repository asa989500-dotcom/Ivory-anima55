# Stage 72 — reshape, trim, and the marker that was hiding underneath

## 1. The colour marker was drawn *beneath* the colours

You were exactly right, and the cause is a one-line fact about Godot: **a child
node draws after its parent.**

The wheel is a child `ColorRect` running a shader. The two markers were drawn
in the parent's own `_draw` — so everything painted was painted over by the
very thing it was meant to sit on top of. A marker you cannot see on a colour
picker is not cosmetic: it is the only thing telling you which colour you have.

They now live on their own node **added after** the wheel. Sibling order is the
whole mechanism — no z-index needed and none used.

## 2. Reshape — five distortions, on their own branch

Not more buttons in the same list. Move, turn and resize keep a shape **the
same shape**; everything below the new line changes what the shape *is*. Mixed
into one column they read as ten equal buttons and the difference has to be
learnt. Separated under `↳ Reshape what is marked`, it is visible before
anything is pressed.

| | what it does | what it is for |
|---|---|---|
| **Lean** | slides the top sideways past the bottom | italics, a figure leaning into a run |
| **Arch** | bends along a curve, ends fixed | a banner, text on a hill, a bent limb |
| **Swell** | fattens the middle, pinches the ends | a bicep, a bottle, weight and squash |
| **Twist** | turns the middle further than the ends | wringing, a ribbon |
| **Pinch** | pulls toward or pushes from the centre | a fisheye, a dent, a bulge |

**Chosen so no two can be made out of each other.** Lean is the only
straight-line transform; arch bends along one axis, swell scales across it,
twist rotates by depth, pinch works radially. A sixth built from two of these
would be a longer menu, not a more capable one.

Every one is a **rule**, exactly like `RigSkin`'s mouth and bone rules — so
the same five serve the live preview and the final commit without being
written twice. Amount runs −1 to 1, zero is unchanged, and the two sides are
opposites, so anything done here can be undone by hand.

Nothing touches the layer until the selection is put down. Every amount tried
costs one reshaped mesh and nothing else.

### A real bug the tests caught

**Pinch folded through itself at full push.** Writing the map as
`r' = r − t·k·(r − r³)`, it stays monotonic only while `|t·k| < 0.5`. At
`k = 0.75` a full push sent a point nine tenths of the way out **past** the
boundary, which is held fixed — the shape turning inside out against its own
edge. It is `0.45` now, and the fold is not merely unobserved but
arithmetically impossible.

Two other "failures" were my tests being wrong, not the code: **Arch** is
supposed to move its centre — that is what bending is — and **Twist** rotates,
so `+a` and `−a` mirror rather than negate.

**Verified: 26 checks.** Zero is identity for all five; the centre is fixed for
the four that should hold it; no two do the same thing; no rows reverse; arch's
ends stay put; pinch never moves the boundary; the cutter's inside/outside test
is right for both shapes.

## 3. Trim

Choose a square or a circle, place it over the marked part, and cut. **Both
directions**: *Cut the shape away* and *Keep only the shape* — the same loop,
and a trim that could only do one makes the other a matter of cutting three
times.

Built on the lift's own bounds, snapshot and undo path rather than a second set
of nearly-identical helpers. A trim that recorded undo its own way would be a
trim that undoes differently from everything else.

## 4. Enlarging a selection no longer softens it

The transform handed the whole job to the GPU, which stretches bilinearly — a
blur with a good name. A small selection scaled up and committed came back
looking photographed through a window, and the damage is permanent because by
then it is pixels.

Anything growing by more than a fifth is now resampled through **Lanczos** at
its final size first, and the transform is left with only the turning and
placing. Shrinking goes through the **area** filter instead — Lanczos rings on
the way down, putting a bright halo along every dark edge.

Below a fifth, nothing happens: at that ratio the filter and the resample agree
to within less than the eye can see, and a resample is neither free nor
lossless.

## 5. Timeline rows are a finger tall

Thirty pixels was a mouse's row height — under four millimetres on a tablet,
less than half a fingertip. Choosing a layer meant aiming, and aiming wrong
meant the frame buttons then acted on a layer nobody had chosen. Forty-two is a
comfortable target and still fits eight rows without scrolling.

---

## Not done this stage, and named rather than glossed

**Selection linked to Character 360** — the quality half is in (that is item 4,
and it is the part that was actually losing anything). Wiring the marquee to
the turnaround's own rooms is a separate connection.

**Strengthening the two rooms**, the **animation layer for B-Spline bones**,
faster layer adding, and the brushes. These are each a stage rather than a
paragraph, and I would rather do one of them properly than four of them
partly — the last two stages both found real bugs in maths I would otherwise
have called finished.

**And the question from last stage still stands**, because it is worth more
than anything I could guess: when you drag a bone in the B-Spline room, does
the **preview inside the room** bend, or is it only the project that stays
flat? Those are two completely different bugs.

## Files touched

new `distort.gd` · `color_wheel_control.gd` (marks layer) · `tool_panels.gd`
(reshape and trim branch) · `canvas_view.gd` (`set_distort`, `trim_selection`,
Lanczos commit) · `timeline_panel.gd` (row height)

Static analysis clean throughout.
