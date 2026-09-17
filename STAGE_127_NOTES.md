# Stage 127 — the wool project becomes yarn

## 1. Yarn was a straight line, and here is exactly why

`Strand.rest` was set to `a.at.distance_to(b.at)` at the moment of laying. So
`load_of(span, rest)` was `1.0` for ever, so `sag` was `0.0`, so `KnitYarn.shape`
hit its `sag <= 0.01 and wobble <= 0.01` short circuit and returned a two-point
line — for every strand, permanently, unless a pin was later dragged closer.

Three changes, in `knit_yarn.gd`:

* **`SLACK`** — a run is laid with the give its own yarn has, from 0.5 % for
  ribbon to 4.8 % for roving. Every strand has a curve from the moment it exists.
* **Sag falls downwards.** It used to fall to whichever side the strand's id
  parity picked. Now it follows gravity: a horizontal run droops fully, a steep
  one barely bows, and a vertical one — with nowhere down to go — buckles
  sideways, which is what a compressed cord does.
* **`WANDER`** — always-on fibre stray, two waves of non-commensurate period,
  scaled to the yarn's own width. This is the difference between a drawn line
  and a piece of string, and it costs two sines per point.

Also: the profile is a **catenary**, not a sine; and `END_HOLD` gives the yarn
bending stiffness where it leaves a pin, so it comes off the wrap pointing the
way the wrap pointed instead of hinging.

## 2. The brush that was not there

`KnitRoom.press` deliberately answers *no* to a first tap on bare board, so a
single tap places nothing. `canvas_view._begin_input` read that as permission
and carried on down the list to `_begin_stroke` — so a plain drag on an empty
part of a knitting board **painted with the brush**, onto a layer with no panel,
no rail entry and no way to reach it.

The board now answers the press either way and nothing below it may have the
touch. Panning is unaffected: it is a two-finger gesture handled in
`_handle_touch`, before `_begin_input` is ever reached.

## 3. The pin now holds the yarn

A run is no longer a line between two centres. It is **arc, tangent, arc**:

* `KnitYarn.tangents` solves the common tangent of the two pin circles from
  `(A - B)·n = k`, with `k = rA - rB` for the outer tangent and `rA + rB` for the
  crossed one — one statement covering all four tangents.
* `Strand.hook_a` / `hook_b` say which side each pin was wound on, and are read
  off the **outside of the turn** (`KnitBoard._hook_for`) rather than guessed:
  yarn cannot pass through a pin, so the side is forced by the bend.
* A run continuing from a pin corrects the earlier run's own side at that pin,
  because both wraps are the same physical turn. Without this a chain visibly
  came apart at every pin it passed through.
* **Two turns tie off.** The second is drawn at a larger radius spiralling down
  onto the first — a visible double coil — and the pin is marked `tied`, which
  means `pull_pins` leaves it where it is. Circling the pin you set out from now
  counts, so a run can be finished without travelling to another pin first.

## 4. Pins are part of the board

The size floor was 3 px. Zoom out and the yarn kept shrinking while the pins
stopped, so they swelled against the work and their shadow and highlight — both
measured from that floored size — swung further from where the pin actually was.
The floor is now 1 px.

`KnitDraw.pin` is redrawn as a pin **in** a board: a tight contact ring where the
shaft enters, a short shadow, and a head lit from the board's one light
direction (`LIGHT`). Three kinds — round, tack, peg — differing in what they hold.

## 5. Light, shadow and the eight yarns

The shadow used to be one line offset square to the yarn, so every run was lit
from a different direction and a strand shadowed itself. It is now one pass over
the whole path, offset in a fixed direction, in three widening steps.

The eight spins were sharpened: grooves between plies, a lit edge per piece
(recomputed per segment so a bend does not roll over), ribbon roll, roving with
two hair lengths, bouclé loops in three sizes.

## 6. The rail

Moved to the middle of the left edge — exactly where the brush rail sits, laid
out by the same line in `main._layout`. Undo and redo removed: they were
covering for `CanvasView.undo` never reaching the board's own history, which is
now fixed at the source, so the two-finger and three-finger gestures work here.
The gear became the word **Other**, because what is under it is a reference
picture, the finishing, the export and the hand-off — four things whose only
shared property is that none of them is yarn, a colour or a pin.

## 7. The board is a surface

A knitting project has no paper, and that was being read as "nothing". Pins were
pushed into guide lines floating in space. There is now a cork surface over the
project's own page, with its grain placed in **board coordinates** so it moves
with the work rather than sitting behind it like a dirty pane of glass. It is a
surface, not a boundary — nothing is clipped to it.

## 8. Puppet warp — ARAP

Rigid MLS is exact at the pins and cheap, but it collapses the ground between
two pins pulling different ways. `_relax_area` patched that by restoring *area*
with no opinion about *shape*, so a square squashed into a thin diamond was
handed its area back as a fatter diamond.

Added **as-rigid-as-possible** (Igarashi/Moscovich/Hughes 2005; Sorkine/Alexa
2007) — the deformation behind Photoshop's Puppet Warp and Krita's cage
transform. Local step: the best rotation per vertex, closed form in 2D, no SVD
and no `atan2` (the normalised sums *are* the cosine and sine). Global step:
Gauss-Seidel on `L p = b` with alternating sweep direction, warm-started from
the MLS answer — a couple of sweeps where a cold start would need dozens. The
`_hold` field keeps the two solvers from arguing: MLS governs at the pins, ARAP
governs the ground between them.

The "Keep area" slider is now "Hold shape" and weighs the ARAP solve.
`_relax_area` is left in the file, uncalled, because its comment is still the
clearest statement of the problem it was written for.

## 9. Bones

`RigSkin._read_islands` was calling `Image.get_pixel` sixteen thousand times
before a single bone could appear — a bound engine call building a four-float
`Color` for one comparison on one of the four. It now reads `get_data()` once and
indexes bytes, and because that is affordable it walks **every** pixel of a cell
instead of a 4x4 sample: a cell wrongly called empty is a piece of drawing with
no mesh under it, which a bone cannot reach and a pose leaves standing still.

A layer with a rig in it is now move-only, not just the purpose-made bone layer
(`LayerStack.can_draw`, `canvas_view._begin_input`). Joints are tried before the
move box, so posing still beats the whole-object grab. Take the bones out and
the layer is ordinary again with no ceremony.
