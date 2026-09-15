# Stage 89i — the renderer, the tear, and the bones coming home

## The bone deformation — what was actually wrong

Your video showed the figure **shattering**, not drifting. That matters: they
have different causes and I would have fixed the wrong one.

`_bind_bones` gated every vertex on `_ink_between` — a walk from the vertex to
the nearest point on the bone, allowing about a fifth of its length to be blank
paper. That is right for an outlined drawing and **wrong for a drawn one**.
Your figure is a handful of strokes with air between them, so a vertex a hand's
width from a bone failed the walk while the vertex *beside it* passed. One
froze exactly where it was drawn; the other swung with the bone; the mesh
between them was pulled to pieces.

That is the shattering, and it tears along whatever line the ink happened to
break.

Three changes, in order of what they fix:

**A hard reach per bone.** The old weight was an inverse power of distance,
which never reaches zero — every bone had *some* say over every vertex, and the
shares were then normalised. A bone now reaches about its own length plus a
hand's width and no further. Past that it has no vote; not a small one, none.

**The ink test becomes a preference, not a gate.** The reach limit now does the
job the ink walk was really there for — two figures side by side are separated
by far more than a bone's length plus a hand, so the other drawing still cannot
be touched, while a gap *inside* one figure no longer freezes half of it. This
is what stops the tearing.

**Two influences per vertex, the two strongest.** A vertex belongs to a bone, or
sits at a joint and belongs to the two meeting there. Nothing on a figure is
genuinely governed by three, and letting a third in is how a knee acquires a
faint opinion about the elbow — small per bend, compounding over a pose.

The kernel is `t⁴(4t+1)`: smooth in the middle, exactly zero at the edge, with
no discontinuity where it meets it. That is why a bend now blends across a
joint instead of creasing at it.

**Grab radius: 30 px → 18 px.** Thirty was a fingertip and a half, so reaching
for one point moved its neighbour and the only way back was undo.

## The bones did come home — nothing was drawing them

`_apply` writes the skeleton to `layer.rig`. The vault saves it. `transform_rig`
moves it with the layer. Everything kept it and **nothing showed it**, so from
where you stand the bones simply did not come back from the room.

There was no bug in the transfer. There was no drawing code at the end of it.
The active layer's skeleton is now drawn over its artwork on the main canvas —
posed ends, not rest ends, sized in screen pixels so it stays the same weight
under the finger at any zoom, and with one marker where two bones meet.

## Renderer: Mobile → Compatibility

You were right. Mobile is Vulkan with a reduced feature set — it still builds
the whole Vulkan pipeline, and pays memory and startup time for capabilities
this project does not contain a single use of: no 3D node, no real-time light,
no post-process. Compatibility is OpenGL ES 3, which is what a 2D paint program
wants, and it behaves far better on mid-range devices.

## Closed projects stop being ticked

Their tiles were already asleep, but every node under them was still visited by
the engine sixty times a second to be told there was nothing to do. One closed
project is nothing; a workspace with twenty is twenty stacks of layers walked
every frame for no result. `close` now sets `PROCESS_MODE_DISABLED` and `_wake`
restores it — and I checked that neither `LayerStack` nor `PaintSurface` has a
`_process`, so disabling one cannot strand pending work.

## Your other four points — checked, and already right

I looked before changing anything, and reporting this honestly is worth more
than edits that only look like work:

- **No node per brush dab.** Strokes go through a tile-based `PaintSurface`
  that stamps into a SubViewport and folds the result down to an image. That is
  the architecture you described, already built.
- **The timeline draws in `_draw`,** not with a node per frame — so there is no
  pool to build. It is already culled to the visible frames *and* rows.
- **Nothing polls touch in `_process`.** Input arrives through `_input`; the
  eight `_process` functions in the project are timers and coalescers, and the
  timeline's switches itself off when no press is held.
- **`queue_free` is used on deletion**, and layers removed by undo are held
  deliberately — that is what makes redo possible, and history purges them.

The one item I have not done is paging distant frames out to disk. It is real
and it is worth doing, but it changes how the timeline reads every cel, and I
am not starting that in the same build as a rig rewrite.

## The logo

Replaced with the new mark. Measured the same way: the disc found from its
leftmost and lowest points, then the square sized from the **whole
composition** rather than the planet — this mark's rings run 582 px wide
against a 229 px disc, so sizing from the disc alone would have clipped both
tips. It fills 78% of the frame.

## Character 360 room

Now the same blue as the B-Spline room, for the same reason: a turnaround is
imported line work, usually dark, and dark ink on a near-black field is ink you
cannot see. Both rig rooms share it, so moving between them is not a change of
world.

## Checks

`python3 tools/check_all.py .` — all four pass. Cross-class symbols: 0
unresolved.
