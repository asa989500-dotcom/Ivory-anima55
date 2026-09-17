# Stage 89l — the candy wrapper, and the flesh at a bend

Your two sheets say one thing twice: **bone is hard, flesh is soft.** The rig
was getting the first half wrong in a way that made the second half impossible.

## What was wrong

`_pose_now` pushed each vertex through every bone's transform and averaged the
**answers** by weight. That is linear blend skinning, and it has one famous
failure — the one your reference sheets are drawn to correct.

Average two *positions* and you land on the straight line between them. Bend an
elbow ninety degrees and the two answers sit either side of the joint; halfway
between them is nearer the bone than either. So the arm does not bend, it
**pinches** — the flesh collapses toward the axis and the limb narrows to a
waist. Animators call it the candy wrapper.

Measured, on a point 40 px out from a joint weighted half to each bone:

| bend | linear blend | rotation blend | lost |
|---|---|---|---|
| 30° | 38.64 | 40.00 | 3.4% |
| 60° | 34.64 | 40.00 | 13.4% |
| **90°** | **28.28** | **40.00** | **29.3%** |
| 120° | 20.00 | 40.00 | 50.0% |
| 179° | 0.35 | 40.00 | 99.1% |

At a right angle the flesh was being pulled almost a third of the way into the
bone. That is the opposite of the purple bands in your second sheet, where the
flesh at a bend stays thick and the *shape* is what gives.

## The fix: average the turn, not the position

Each bone has turned by some angle from where it was drawn. Those angles are
now averaged **as directions** — the sum of their unit vectors, then the angle
of that sum — and the result is applied as one rotation about a blended pivot.

Two things follow. A rotation cannot shorten anything, so a point a given
distance from the joint is that same distance after the bend, wherever between
the two bones its weight falls: **40.00 px at every angle in the table**. And
summing directions rather than numbers means the mean of 170° and −170° is 180°
and not zero — averaging the numbers themselves would snap a limb straight
every time a bend crossed the half turn.

This is the two-dimensional form of what film rigs use dual quaternions for,
and in two dimensions it is four lines of arithmetic rather than an algebra.

## And then the flesh

A rigid turn alone gives your first sheet's *bone: hard, rigid*. The other half
is that at a bend the outside stretches and the inside gathers.

So the offset from the joint is split along the bone and across it, and the
across part is opened on the outside of the turn and closed on the inside — by
an amount proportional to how far the joint is bent, and fading out along the
bone, because a knee has no business thickening the middle of a thigh.

The inside gives by rather less than the outside opens (0.6 of it). Flesh
gathers before it folds, and matching them exactly would let the two sides of a
hard bend cross through each other.

That is the C, J and S of your first sheet: a chain of bones each turning a
little, with the flesh opening on the outside of every curve in the chain.

## What this does not yet do

**The 360 ring as a driver.** Your first point — the circle that turns the
figure — is the one piece I have not built. The rings exist, they are saved,
they are drawn on the canvas now; what is missing is turning one and having the
turnaround interpolate between its eight poses in response. That is a real
feature and it wants its own build.

**The AI model.** There is no learned model in IVORY to improve — the carving,
the binding and the posing are all explicit geometry. If what you mean is that
the *posing* should feel more like the sheets, that is what this build is; if
you mean something else by it, tell me what it should do and I will say
honestly whether it is buildable.

## Checks

`python3 tools/check_all.py .` — all four pass, from inside the unpacked zip.
