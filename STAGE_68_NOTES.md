# Stage 68 — the ring, corrected

## I had it wrong, and the correction improved the design

I asked you for nine mouth drawings. That was the wrong shape of answer, and
wrong in the way that matters most: it hands the artist a form to fill in.
Nine drawings, in nine shapes the app chose, and the character's mouth is no
longer the character's — it is the app's specification wearing your line.

**The ring is the right idea and it is now what is built.** One black line,
drawn by hand around whatever mouth was drawn. The ring bends; what is inside
bends with it. Every key is a way of *bending*, never a picture.

## Why `b`, `m`, `p` close whatever is in there

This is the part that only works because of the correction.

Closing is not "show the closed drawing". There is no closed drawing and
nothing to match against. Closing is **the ring flattening onto its own middle
line**, and anything inside a flat ring is flat.

Measured, on five deliberately different rings:

| the ring drawn | vertical opening | after SHUT |
|---|---|---|
| a lumpy hand-drawn circle | 43.1 | **1.29** (3.0%) |
| a wide letterbox | 41.5 | **1.24** (3.0%) |
| a tall oval | 46.0 | **1.38** (3.0%) |
| deliberately crooked | 48.0 | **1.44** (3.0%) |
| tiny | 6.9 | **0.21** (3.0%) |

Three per cent every time, because closing is a scale on the ring's own height
and the ring is the artist's. A round mouth, a wide mouth, a crooked one drawn
by somebody who draws crooked mouths — all shut, and each in its own way.

## The five numbers behind each key

Not drawings. Five things a jaw and a pair of lips actually do:

```
wide   how far the corners go out       1 = as you drew it
tall   how far the ring opens           1 = as you drew it
purse  corners in and forward           w, oo
drop   the whole ring carried down      the jaw, not the lips
shut   collapse onto the middle line    1 = closed
```

Multipliers on **your** ring, never absolute sizes — so a small mouth and a
wide one both read `A` as "open a good deal wider than you drew it", which is
the only reading of `A` that survives more than one character.

## What the maths had to get right, and what it got wrong first

**Two real bugs were caught by testing before they shipped.**

**First:** I squashed the *radius* by a sine term. `SHUT` only closed to
**26%** — a mouth that will not quite shut. The reason is arithmetic: the
function `x(1−0.97x)` peaks in the middle, not at the top, so the widest part
of the ring survived the squash. Closing has to happen in Cartesian height,
not in radius.

**Second:** after fixing that by resampling the bent ring onto an even grid of
angles, closure reached only **8.7%** — because a squashed ring crowds all its
points near the horizontal, leaving the vertical angles interpolated between
distant neighbours. The resampling had to go entirely. The bend is now
analytic along each ray, and closure is exactly the 3% the numbers say.

**Third, and the subtlest:** the falloff outside the ring could **fold the
mesh through itself** for any key that opens the ring more than about 1.75× —
which `A` does, at 1.85×. An eased decay is prettier on paper and folds. The
decay is linear now, and that is load-bearing rather than lazy: with a linear
decay the map is *provably* monotonic along every ray for any bend up to 2.5×,
so a fold is not merely unobserved but impossible. Verified over ~53,000
sampled points.

## Verified, fifteen checks, all passing

- exact on the ring — error **1.2e-13**, across all nine keys and five ring shapes
- **nothing past 2.5 radii ever moves** — the chin and cheeks are not dragged
  around, which is the one thing that makes a warped face look like rubber
- the centre is a fixed point — the mouth cannot drift off the face over a long take
- `A` is the tallest, `E` the widest, `W` the narrowest, `T` shorter than rest,
  `K` near rest, `O` tall and narrow
- no fold-over along any ray, for any key, on any ring

## Also in

- The ring is a layer's own, beside its rig, and is **saved** — thirty-two
  numbers and a centre. Drawn once by hand; not worth drawing twice.
- `from_stroke` accepts the line as drawn: it does not have to be round, close
  cleanly, or be drawn in any direction. Gaps where a finger lifted are filled
  from the neighbours. A stroke covering less than three quarters of the circle
  is **refused** — that is an arc, not a ring, and accepting it would produce a
  mouth that bends in a way nobody asked for.
- `Viseme.blend` interpolates the five numbers between two keys, because lip
  sync is not a slideshow: a mouth is always travelling, and the frames in
  between are most of what the eye sees.

---

## What is still owed, stated plainly

**The audio half.** Loading a file, reading the waveform, and turning sound
into the run of mouths this now knows how to bend. The chart and the ring had
to be right first — a wrong ring driven by perfect audio is still a wrong
mouth.

**The canvas pose path**, which also unblocks onion skin showing poses. I
looked at it properly last stage: layers are drawn as tiled `Sprite2D`s and the
B-Spline room deforms via a `SubViewport` bake — far too heavy per frame. It
needs a `MeshInstance2D` that draws the layer's art through the rig's vertices.
That is a stage of its own and it is the largest thing left.

**Stick**, and the ring following the mouth as the head turns.

I did not wire buttons for the ring this time, and that is deliberate: two real
bugs surfaced in the maths of a thing I would otherwise have called finished,
and both were the kind that survive a demo and ruin a production. Untested
geometry under tested buttons is the wrong order.

## Files touched

new `mouth_ring.gd` · `viseme.gd` (keys rewritten as bends) ·
`layer_stack.gd` (the ring on the layer) · `vault.gd` (saved)

Static analysis clean: use-before-declaration 0, brackets balanced, no
duplicate functions, no unused parameters, no shadowing, no global-name
collisions, no dead references.
