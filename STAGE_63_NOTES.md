# Stage 63 — the rig gains a timeline, and folders learn to switch

You asked for six systems and gave the order to build them in. That order was
right, and this is the first three of it — built *into* the architecture rather
than beside it. What follows says exactly what is finished, exactly what is
next, and one place where I did not build what you asked for because measuring
it showed the design would have broken limbs.

---

## The finding that changed the design

You wrote that blending between two rig poses "is simply a lerp on `along`".
For `Rig360` joints that is exactly right and it is what this does. For
**bones** it is not, and the reason is worth a paragraph because it is
invisible until it is on screen.

A bone is a *chord*. Store both its ends and slide each toward its next
position and the chord cuts across the arc the bone should have swung
through — so the bone gets shorter the further it travels, and springs back to
full length precisely on the key, which is where you would be looking. I
measured it before writing a line:

| swing between two keys | length lost mid-tween |
|---|---|
| 60° | **13%** |
| 120° | **50%** |
| 179° | **99%** |

A forearm that halves on the way through a wave. And it defeats the entire
reason `Bone` exists in the first place — a bone is *the thing that keeps a
length*.

So a key stores **where the pivot end is and which way the bone points**, and
the far end is rebuilt from the bone's own rest length at every in-between.
Measured error across 1,200 sampled in-betweens: `2.8e-14` — floating point
for "exactly". Three floats per bone instead of four, and correct instead of
nearly correct.

---

## 1. `RigTrack` — the rig's own timeline  *(scripts/rig_track.gd, new)*

Beside `CelTrack`, and shaped deliberately like `Anim.Clip`'s camera row: keys
in frame order, an ease mode on each, `pose_at()` blending the keys either
side, the nearest key holding beyond the ends. It reuses `Anim.Ease` rather
than inventing its own modes, so a rig key eased SMOOTH and a camera key eased
SMOOTH travel on the same curve, and the timeline can draw both rows with one
piece of code.

A key holds any mixture of: `along` per joint (a whole Character 360 pose, one
float each), bones as pivot+angle, puppet pins, and the turn of a turnaround.
Blocks that were never recorded are never written, so a bone-only track carries
no empty pin arrays.

Three decisions worth naming:

- **Only `along` is stored for Rig360.** Everything else about that pose —
  where each joint ended up, where the bones were carried — is *derived* by
  `_settle()`. Storing derived state is how a file comes to disagree with
  itself.
- **Mismatched key lengths are handled deliberately.** Add a bone halfway
  through a scene and the earlier keys are shorter. The short block is treated
  as ending where it ends and the longer one's value holds — so a new limb
  appears in place rather than flying in from the top-left corner, which is
  what blending against an absent zero would have done.
- **A turnaround blends the short way round the ring.** 0.95 → 0.05 travels
  through 1.0, not backwards through 0.5.

`insert_frame_after` shifts rig keys exactly as `Clip` shifts camera keys and
`CelTrack` shifts drawings — otherwise pushing one frame into the top of a
scene would slide every pose out from under its drawing, silently and
permanently.

## 2. Switch folders — the one you called most important, and I agree

`Group.is_switch` and `Group.switch_index`. A switch folder shows exactly one
member at a time: twelve mouth shapes in one folder, and the folder shows the
one the dialogue needs.

What it is *not* is as important as what it is. It is **not a new layer type**,
and it moves and merges nothing. It is an ordinary folder that answers one
extra question inside `_apply_looks` — the single place in the stack where
visibility is decided. Turn it off and every layer comes back exactly as it
was, because nothing was ever taken away: the layers kept their own `visible`
flags the whole time and the stack simply stopped asking about them. A mouth
chart that has to be dismantled to be edited is a mouth chart nobody edits.

The *timing* lives in `Anim.Clip` beside the camera keys, as `Swap`, because
timing belongs to the scene rather than to the folder — copy a mouth chart
into another project and it arrives without the dialogue it was mouthing,
which is right.

**`Swap` has no ease mode, and that is finished rather than unfinished.** A
mouth is open or closed; there is no frame on which it is thirty per cent of
the way to an F. Every other key in this project blends; this one steps,
because the thing it describes steps.

## 3. Two-bone IK  *(bspline_room `_reach_to`)*

Closed form, on the `Bone` you already had. Drag the far end of a bone that
hangs from another and the hand goes where your finger goes while the elbow
works itself out. Anything else — a lone bone, or the near end of any bone —
swings exactly as before, so a rig built last week poses the way its author
expects.

Verified over 400,000 random configurations:

```
upper length error   1.1e-13
lower length error   3.0e-12
target miss          0.0e+00   (for targets in reach)
```

No iteration, no convergence, nothing to tune — which matters twice on a
tablet, because this runs on every drag event of every frame. Out of reach, the
arm straightens toward the target and stops. Too close to fold, the elbow opens
to its tightest angle rather than inverting through the shoulder. Which way the
elbow bends is read from the pose the limb is already in, so it cannot flip
sides as the hand crosses the shoulder line.

## 4. Adapting to the device

You asked that the new work scale with the hardware. It does, and the split is
the point:

**Reading a pose runs on every frame on every device.** It is a handful of
floats. So the *timing* of an animation is identical everywhere — a scene
checked on your tablet plays at the same speed on a cheap phone.

**Pushing that pose through the mesh is rationed.** Every vertex re-weighted
and re-uploaded is the expensive half, and `Perf.rig_solve_stride()` emits it
every frame on HIGH, every second on MEDIUM, every third on LOW.

The result is an animation that **holds a pose for a frame at a time rather
than one that plays slowly.** That is the right way round: a viewer forgives a
held pose and does not forgive a scene running at half speed.

Switching is never rationed — it is one integer compare and a visibility flag,
and a mouth that changes a frame late is a mouth out of sync.

`Perf` also gained `wants_dynamics()`, `dynamics_budget()` and
`wants_tween_preview()`, ready for items 5 and 6.

## Saving

Pose tracks and switch folders round-trip through `vault.gd`, written **only
when non-empty** and read back with defaults. A project made before any of this
existed loads unchanged, and undo states captured by an older build no longer
risk a crash on a missing key.

---

## What is *not* here, stated plainly

**The buttons.** Everything above is data, playback and solver. To reach it
from a finger you still need: an *Add rig key* button in the timeline, a rig
row drawn in the band, and a *Make this a chart* toggle in the folder settings.
`BSplineRoom.record_key()`, `take_pose()` and `pose_at()` are in and waiting
for them; `LayerStack.set_switch()` and `step_switch()` likewise.

I stopped here on purpose, and it is the same reason you gave me: there is no
Godot in this environment, so every line of UI wiring I write blind is a line I
cannot check. The data layer I *can* check, and did — the interpolation,
switching and IK were ported to Python and run against fifteen tests plus
400,000 random IK configurations before any GDScript was written. All pass.
Wiring nine files of buttons on top of untested foundations is how a stage
lands broken.

**Items 5 and 6** (depth from bone angle, and jiggle) are not started. Your
ordering was right to put them last: dynamic depth wants the rig timeline
underneath it, and secondary motion wants both.

## Files touched

new: `rig_track.gd` · `anim.gd` (Swap, ease_shape) · `layer_stack.gd`
(poses, switch folders, `_apply_looks`) · `anim_player.gd` (`_pose_rigs`,
`rig_posed`) · `rig360.gd` (public `settle`) · `perf.gd` (rig tiers) ·
`bspline_room.gd` (IK, rig keys) · `vault.gd` (persistence)

## Caveat, unchanged

Static analysis and numeric testing, not a compile. Open the project and
confirm the error counter before building on this.
