# Stage 89k — a bone moves the piece of drawing it was laid on. Nothing else.

## The rule

Two strokes side by side, a hair apart, not touching. Put a skeleton in one of
them and the other must not move — at any distance, by any amount, ever.

**Distance cannot express that**, and both of my previous attempts to make it
try failed in one of the two ways available:

- generous → the neighbouring stroke gets carried along
- strict, measured per vertex → half of the stroke it *is* meant to move
  freezes wherever a gap happens to fall. That is the tearing you filmed.

So the question is answered once, properly, and by **connectivity** rather than
by distance.

## How

`_label_pieces` runs while the occupancy grid is already in hand, and does two
sweeps:

**One — label the ink.** Breadth-first, eight-connected, so a diagonal stroke is
one piece rather than a dotted line of them. Each connected blob of ink gets a
number.

**Two — give every blank cell the label of the piece nearest to it.** A single
breadth-first sweep out of *all* the ink at once, so each blank cell is reached
from whichever piece is closest and the boundary between two strokes lands
exactly halfway between them. This is why nothing freezes: no vertex is ever
unlabelled.

Then: a bone belongs to the piece under it — sampled along its length and taken
by majority, because a bone laid across a joint may have its midpoint over
blank paper, and a majority cannot be flipped by nudging the bone a pixel. A
vertex belongs to the piece nearest it. **A bone moves a vertex only when the
two agree.**

Inside one piece there is nothing to tear, because every cell of it carries the
same label whatever gaps run through it. Between two pieces there is no
influence at all, at any distance.

## The order that makes it work

Labelling happens **before** the grow that fattens the ink by a cell. That grow
exists so the mesh has something to hold on to — and it would fuse two strokes
a cell apart into one piece. Labelling the ink as it was actually drawn keeps
them two. One line in the wrong place would have undone the whole rule silently.

## Points too

The same test on the B-Spline curve: the spine's piece is taken by majority
along its own length, and a vertex on another piece gets a pull of exactly
zero. A spine laid down one stroke governs that stroke, and a second stroke
beside it is not its business however close it runs.

## Verified

Simulated your exact case — two vertical strokes two cells apart:

```
separate pieces found: 2
ink cells the bone may move : 56
ink cells it may NOT move   : 56   <- the neighbouring stroke, untouched
blank cell at x=22 -> piece 0,  x=23 -> piece 1
```

The boundary lands exactly halfway between them.

## And the checker earned its keep

While writing this I used `_arc_total`, which does not exist — I wanted
`arc_length()`. `check_identifiers.py` refused the build:

```
scripts/ui/bspline_room.gd:1196  '_arc_total' is used but never declared
FAILED: check_identifiers.py
```

That is the third time this exact shape of mistake has been made and the first
time it did not reach you.

## Checks

`python3 tools/check_all.py .` — all four pass, from inside the unpacked zip.
