# Stage 129 — bones, yarn, the warp, and canvas size

Four separate pieces of work. Each section says what was reported, what was
actually wrong, and what was done — in that order, because in three of the four
the reported symptom and the cause were not the same thing.

---

## 1. Bones

### "Bones cannot be moved after they are added, ever"

**What was wrong.** One line in `scripts/ui/bone_handle.gd`:

```gdscript
if view.layers.wear_skin(l, ...) == null:
    return false
```

A *skin* is a mesh carrying a picture of the layer, put in front of it so the
drawing can be seen bending while it is posed. Building one means reading the
layer's pixels back off its surface, and that fails for perfectly ordinary
reasons — the surface not yet mounted on the frame the finger landed on, a
layer whose art is still loading, a device that refused the texture.

In every one of those cases the *skeleton* was fine. The pose was refused
anyway. So the joints sat on the drawing looking exactly like controls and did
nothing when touched, which is precisely the report.

**What was done.** The skin is now wanted and not required. A missing skin
costs the live preview of the drawing bending; it does not cost the pose. The
bones move, the pose is written, and the picture catches up the moment a skin
can be built. Refusing the whole gesture to avoid a missing preview was trading
the feature for the animation of the feature.

### "Make the movement highly efficient"

A pose is not one calculation. It is one calculation per touch event — sixty to
a hundred and twenty a second — and each one walks the chain, solves it, walks
the descendants and re-hangs them. In GDScript every step of that is a bound
call returning a Variant, and past about a dozen bones the answer arrived after
the frame that wanted it. **A joint that answers late does not read as slow. It
reads as not moving**, because the finger has already gone somewhere else.

`native/ivory/src/ivory_bone.{h,cpp}` is new. Same methods, different language:

* **FABRIK** (Aristidou & Lasenby, 2011) for chains of three or more. Positions
  only — no angles, no Jacobian, no matrix — so it never produces the wild
  overshoot a Jacobian solver does near a singularity.
* **A closed-form triangle** for two bones, which is most of what anybody rigs:
  an upper arm and a forearm, a thigh and a shin. Exact, no iteration, nothing
  to tune, and it remembers which side the elbow was on so it cannot flip
  through the shoulder.
* **Rigid carry** for descendants. When a bone turns, everything hanging off it
  is carried by the same rotation about the same pivot — carried, not
  re-solved. The moment descendants are recomputed independently, floating
  point disagreement opens a gap at the joint, and a rig that opens gaps is a
  rig that visibly comes apart when moved quickly.

**One thing worth knowing about the read-back.** `Bone.a` and `Bone.b` are
*derived*: `BoneRig.solve` is the only thing allowed to write them, from `turn`
and `shift`, and everything that saves, loads, keys or interpolates a pose
reads those two. Writing the solved positions straight onto `a` and `b` would
look right on screen and vanish the next time anything called `solve` — which
is every frame of playback and every load from disk. So the solved positions
are converted back into turns and `solve` re-derives the rest. The native side
stays a calculator; it never becomes a second place a pose lives.

### "Everything must come back exactly as it was when I reopen the app"

**What was wrong.** Nothing in the save path. `vault.gd` has always written a
layer's rig, and `record_state` has always put the pose on the undo stack. Both
worked. But neither of them tells the *project* it has unsaved work in it, and
autosave only writes projects that say they have.

So a figure could be posed all afternoon, every pose correctly recorded in
memory, and none of it reached the file.

**What was done.** `view.projects.mark_dirty(...)` on release — on release
rather than on every drag event, because a drag is one thing the person did and
a hundred writes a second is not a save policy.

### "Adaptive bone sizing"

Every bone was drawn at the same width: a fraction of its own length, clamped
between four and fifteen. A bone down a forearm and a bone down a finger came
out alike, and the one in the finger was wider than the finger.

A bone is now measured against the artwork it was laid on. Eleven stations
along its length, rays cast both ways until the ink stops, and the **median**
half-width taken. The median and not the mean, because a limb usually overlaps
the body at one end and a mean would be dragged out to the width of the body by
the two or three stations that see it.

Measured once, when the bone is laid, and stored on the bone as `girth`. Not
measured on demand, because the measurement reads the layer's ink and the
canvas draws a rigged figure's skeleton without ever reading that layer back —
reading a surface back is the most expensive thing this app does per frame.

Files: `IvoryBone::span_across` in C++, `BoneRoom._girth_across` with a GDScript
fallback kept deliberately identical in method, so a bone laid on a machine
without the extension is the same size as one laid with it.

### "Bones for animation projects only"

`LayerRigRow.build` now returns early unless the project is an animation one.

A skeleton exists to be posed over time. On a knitting board there is nothing to
pose; on a plain drawing there is no timeline for a pose to be a key on, so the
feature collapses to "the drawing can be bent once and left bent" — which is a
distortion tool, and IVORY already has one of those.

Offered on the wrong kind of project it was worse than useless: accepting bones
locks the layer against every drawing tool, so somebody who tried it on a sketch
got a layer they could no longer draw on in exchange for a pose nothing would
ever play back.

**One exception, deliberately.** A layer that already carries a skeleton shows
the row wherever it is, so a rig that arrived on the wrong project can still be
taken off. Hiding the only way to remove something is how a layer becomes
permanently stuck.

---

## 2. Wool

### Pins: two explicit modes and a Confirm button

The board used to guess. A double tap on bare board made a pin, a drag from a
pin made yarn, and the board worked out which from the gesture. That is elegant
on paper and it fails in the hand for one reason: **the two gestures start
identically.** Both begin with a finger landing near a pin.

Now:

1. **Press the pin button.** The board is placing pins.
2. **One tap places one pin** — not two taps, not a tap and a drag. The mode has
   already been stated, so there is no ambiguity for a second tap to resolve,
   and asking for one is asking twice.
3. **Press Confirm.** Placing stops completely and the board switches to yarn.

Placing needs an explicit end because every rule for ending it by itself is
wrong for somebody. End after one pin and placing twenty is twenty round trips.
End when a pin is touched and the board can never be corrected. End on a timer
and it ends while somebody is thinking.

Both flags off is a third, resting state: the board takes no marks at all and
every touch pans the view.

### The sensor ring

A pin is sixteen units across; a fingertip covers about eight millimetres of
glass. Asking somebody to land inside the pin is asking them to hit a target
smaller than the thing they are aiming with.

Each pin now carries a ring forty percent wider than itself, invisible until a
finger is inside it, which is when it lights up. Forty percent and not more:
a sensor twice the pin swallows the gaps in dense work, and then a finger aimed
at bare board between two pins starts a run from whichever was marginally
nearer.

It is drawn only while a finger is down. A board covered in always-visible rings
is a board where the rings overlap into a mesh that hides the work, and the
question the ring answers — *is this the pin I am about to pull from?* — is only
ever asked mid-gesture.

### The live strand — why the yarn was a dead straight line

A finished strand's shape is *calculated* from its two ends and its rest length:
closed form, same answer every time, cheap enough for thousands. That is right
for a strand that is tied at both ends.

**A calculated shape has no memory**, and that is exactly the wrong property for
the one strand a finger is holding. Shake the finger and nothing happens,
because the path the finger took is not one of its inputs — only where it ended
up. No improvement to the formula could have fixed this.

So the *live* run, and only the live run, is now a real simulated strand:
position-based dynamics (Müller, Heidelberger, Hennix & Ratcliff, 2007), with
three constraints projected in order —

* **distance**, holding each pair of neighbouring points at its rest separation;
* **bending**, pulling each triple weakly towards straight (this is the discrete
  Laplacian, and pulling towards it *is* a straightening force). At zero the
  strand hangs like a necklace; near one it is wire. Yarn is near the bottom of
  that range and ribbon near the top, and this is where the visual difference
  between roving and ribbon actually comes from;
* **contact**, pushing points out of pins and letting them slide along the edge,
  because yarn dragged against a post slides round it rather than sticking.

PBD is unconditionally stable at any stiffness. Turning the numbers too far up
gives a slightly soft rope, not a drawing thrown off the screen — which is why
it and not a spring solver.

One strand at a time, for as long as a finger is down.

### Flexibility, doubled

* `SLACK` roughly doubled across all eight yarns.
* `WANDER` roughly doubled — how far the fibre strays from the curve it is
  nominally on. This is the difference between a line and a thread and costs two
  sines per point.
* `END_HOLD` reduced from 0.16 to 0.10, so the yarn starts falling sooner after
  it leaves the wrap.
* `LIVE_SLACK` (new, 2.4×): yarn coming off a pin *towards a hand* is not under
  tension — the hand is carrying it, not pulling it. Making the live run as taut
  as a finished one is what made it read as a rubber band stretched between two
  points.
* `LIVE_BEND` and `LIVE_SAG` (new): the live strand's own material. Heavier yarn
  falls faster, which is not how gravity works and is exactly how yarn behaves —
  a chunky cord has more mass per unit of air resistance than a fine thread.

### Pins as barriers

Pushing points out of pins keeps a *settled* strand outside them. It does not
stop one being dragged **through** a pin between two frames: a finger crossing
eighty pixels in a frame carries the end of the run to the far side, and every
point is then pushed out the short way — whichever side it happens to be nearer.
The strand has passed through and nothing in the simulation can tell.

So the crossing is caught before it happens, by a swept-circle test along the
segment the finger just travelled: `|from + t·span − centre|² = r²`, solved as a
quadratic in `t`, smaller root. The run is held at the point of contact, the
yarn piles against the pin, and an arc is drawn on the near side — an arc rather
than a ring, because a ring would say "this pin is selected" and an arc facing
the yarn says "this is what stopped you".

**Letting go against a barrier ties the run onto it.** Somebody dragging yarn
until it will go no further and then lifting is somebody tying it to the thing
that stopped them. The alternative reading — that they meant nothing — throws
away the gesture and makes the barrier feel like a wall rather than a fixture.

`IvoryYarn::blocked_at`, with an identical GDScript fallback.

### Pins glued into the canvas

The old bedding was three discs: a wide faint one, a tighter dark one, and a
drop shadow offset away from the light at nearly the head's own radius.

Every one of those is a correct thing to draw, and together they said the wrong
thing. **A large, soft, offset shadow is the strongest cue the eye has for
height above a surface.** The further a shadow sits from an object and the
softer its edge, the higher the brain places it. Drawing a good soft shadow was
actively making the pin hover.

What says "in contact" is the opposite: a shadow that is tight, dark and almost
concentric, tucked under the object's own edge so only a crescent shows — an
ambient-occlusion shadow rather than a cast one.

And a pin is not resting on the board, it has been pushed through it, so there
is a hole and a lip of material the shaft pushed up on its way in — lit on the
side facing the light, in shadow opposite. That lip is what makes it look
*driven in* rather than merely touching. Three arcs.

### The image selection box

**What was wrong.** `HandleBox.sized` measured the scale from where the *finger*
landed: `(to − anchor) / (from − anchor)`. A corner has a reach of thirty screen
pixels, so a finger routinely lands well short of the corner it is grabbing, and
the ratio of two distances that both start at the anchor is not one when the
numerator starts closer in. **The box resized to match the finger's own distance
the instant the drag began**, and the corner leapt to meet the thumb before it
had moved at all.

Worse near a corner's own axis: when a finger lands nearly level with the anchor
on one axis, `was.x` is a very small number, and dividing by it magnifies every
later movement without limit. That is the box behaving wildly along one
direction and sensibly along the other — exactly the "unstable" report.

**What was done.** The offset between the finger and the corner it caught is
measured once and carried for the whole drag, so the corner follows the finger
with that offset held constant. Grabbing anywhere inside the reach now behaves
identically to grabbing the corner exactly.

### Centring an imported picture

It was sized against the width of the *screen* and placed at the middle of
whatever happened to be on screen. Both are the wrong reference: the knitting
board **is** the project's page — every coordinate on it is clamped to the page
— so a picture measured against the viewport arrived at a different size
depending on the zoom, and one placed at the middle of the viewport arrived off
the page entirely whenever the view was looking at a corner.

Now fitted to the page (whichever direction runs out first, so a tall photograph
fits too), centred on it, rounded to whole units so the box's grips are drawn
where they are tested, and its rotation reset.

### The IM button

The cells existed and were three taps deep: Other → find the reference section →
the cell. Which meant a picture brought in and then unwanted was, in practice,
permanent — nobody looks three panels down for a delete.

`IM` is now on the rail. It opens a floating panel with one row per picture:
**Move** and **Delete**. Pressing Move on the one already chosen puts it down —
a control that can only turn something on is a control that needs a second one
beside it to turn it off.

The underlying rule is unchanged and is the whole reason this works: **the
button is the handle, the picture is the work surface.** A picture is never
touched directly, so the board never has to guess whether a finger meant the
picture or the pin on top of it.

---

## 3. Puppet warp

### "It drags. It should stretch and squash."

**Why it dragged.** The fit was *rigid*: rotation and translation only, so every
distance in the drawing was preserved exactly.

Draw a straight line. Put a pin at each end and pull one towards the other. A
rigid fit is **not allowed** to shorten the line — the ends are closer and every
distance along it must stay what it was — so the material has to go somewhere,
and where it goes is sideways: the line bows out into an arc.

The drawing was dragged because it was **forbidden to shrink**. This was never a
tuning problem.

**What was done.** Three modes, Schaefer, McPhail & Warren (2006) section by
section. Everything else — the weights, the distances walked through the mesh,
the pins, the turns — is identical between them; only the fit differs.

| Mode | Fits | Behaviour |
|---|---|---|
| `RIGID` | rotation, translation | proportions exact; material slides aside |
| `SIMILARITY` | + one uniform scale | pins spread and the drawing grows, keeping shape |
| **`AFFINE`** (default) | full linear map: independent scale per axis, and shear | **pull a pin towards another and the material between them compresses**, while what is square to that line is left alone |

Affine is the exact weighted least-squares linear map,
`M = (Σ w pᵀp)⁻¹ (Σ w pᵀq)`, with the 2×2 inverse written out because at this
size a general solver is both slower and less accurate than the closed form.
When the system is rank deficient — one pin, or every pin on a single line —
it falls back to rigid rather than inverting a near-singular matrix: one pin
dragged should carry the drawing, not tear it.

**Two things had to be turned down with it**, and this matters:

* **ARAP** is by construction a force *against* scaling — it fits a rotation to
  every neighbourhood and pulls towards it, and a compressed neighbourhood is
  one no rotation explains. At full strength it undoes exactly what affine is
  for. It cannot simply be switched off (it is what stops the mesh folding
  through itself), so in the stretching modes it runs at 35%.
* **The area pass** hands a triangle back the area it lost. Right under a rigid
  fit; precisely backwards under affine, where a triangle *should* lose area
  when the drawing is compressed. It is skipped entirely outside `RIGID`.

Without those two, the drawing sprang back out sideways as fast as it was pushed
in — which would have looked like the affine fit not working.

### The mesh: ivory triangles

It was drawn from `_near`, the four-neighbour adjacency — which exists for a
different job entirely. `_near` is the graph *distances are walked along*, and
distances are walked between grid neighbours. Drawing every edge in it draws the
grid, and **the grid is not the mesh.** The mesh is `_tris`, and it has a
diagonal through every cell the wire never showed.

That mattered for more than looks: the diagonal is where a cell is actually
allowed to fold, and it alternates direction cell by cell precisely so the mesh
has no bias along one diagonal. Anyone reading the square grid to predict a pull
was reading a structure the solver does not use.

Now built from `_tris` into a deduplicated edge list — once, when the mesh is
built, because the mesh does not change while it is dragged, only its vertices
do. Deduplicating per frame would mean a set of several thousand keys rebuilt
sixty times a second for an answer that cannot change. Colour `#FCF5E1` at 62%
over a dark backing pass, since one colour cannot be seen against both white
paper and black ink.

The mesh already only covers cells the drawing reaches (`WarpMesh.ink_map`);
that is unchanged.

---

## 4. Canvas size

There was no choice. Every project of every kind was created at 1600 × 1200,
with a comment saying so on purpose. For an app whose output is video and
printed pages, that is not a missing setting — it is a missing capability:
IVORY could not make a Full HD frame or an A4 page, so everything it produced
had to be resampled by something else first.

**Twenty-six presets** in four bands — screen and video (8K down to SD, plus
vertical), print (A3/A4/A5 at 300 and 150, Letter, Tabloid, comic page), square,
and social. One table in two orders rather than two tables: animation and
knitting lead with the video standards, drawing and comics with print.

**A preview, drawn to scale.** Against the largest offered size, with that size
outlined faintly behind it. A preview stretched to fill its box every time would
make an 8K canvas and a thumbnail look identical — which is worse than no
preview, because it looks like information and is not. "3840 by 2160" is a pair
of numbers; a canvas is a shape, and the difference between 1080×1920 and
1920×1080 is invisible in the digits and unmissable in the outline.

**Two free fields**, read on every keystroke rather than behind an Apply button
— an apply step is one more thing to forget, and forgetting it means creating a
project at a size you did not choose and can no longer change. Held between 64
and 8192, and never past thirty to one either way: a canvas thirty times longer
than it is wide is a mistyped number far more often than a panorama. Widened
rather than refused, so the intent is kept.

**The memory cost is stated.** A 4K animation with eight layers is a few hundred
megabytes of surface before a single stroke, and on a mid-range phone that is
the difference between an app and one killed on its third launch — discovered a
week into the work, when the only answer is to start again smaller. Said as a
number with a warning past the point where it matters, not as a refusal:
somebody on a tablet with memory to spare should be able to make an 8K canvas,
and refusing them because a phone could not is deciding for a device that is not
in the room.

**The panel floats over the creation sheet rather than replacing it.** The
obvious build is `_close_panel` then `_mount`, which is how every other panel in
the app opens. It is wrong here for a reason specific to this one: the sheet
underneath is a **form**, holding a name somebody typed, a frame rate they chose
and a paper colour they picked. Closing it throws all of that away, and they
come back to an empty sheet — punished for wanting a size other than the
default. So the chooser is a `top_level` child of its own row, and the form
underneath is untouched.

`IvoryCanvas` (C++) holds the table, the memory arithmetic, the aspect-ratio
reduction and the preview fit; `canvas_size.gd` holds an identical GDScript copy
of the table, because a creation sheet offering no sizes at all on a checkout
where nobody has built the extension yet would be a far larger failure than the
one it guards against.

---

## Building the native half

Nothing in IVORY requires the extension. Every native class is asked for through
`scripts/native.gd`, and the GDScript that was doing each job is still there and
still correct. A checkout with no library is a working checkout — it is only
slower, and in two places (the yarn's live strand) less capable.

```
cd native/ivory
git clone -b 4.4 https://github.com/godotengine/godot-cpp
cd godot-cpp && git submodule update --init
cd ..
scons platform=android arch=arm64 target=template_release
```

Six classes now cross the boundary: `IvoryWarp`, `IvorySkin`, `IvoryTouch`,
`IvoryYarn`, `IvoryBone`, `IvoryCanvas`.

---

# Stage 130 — comic frames

## Screentone, removed

`scripts/screentone.gd`, `assets/icons/screentone.png`, the four `tone_*`
fields on `CanvasView`, its settings panel, its compass entry and its branch of
the comic dispatcher. Nothing refers to it.

## The knife brush

A family of five in `brush_library.gd`: dot, fine dot, ring, square, diamond.

It is in the brush system rather than beside it because colour, size and
opacity already live there, and a dotted line that could not be recoloured
would be the one tool in the app with its own rules.

**Every number in its family row is chosen to make it regular**, which is
unusual — nine of the ten families above it spend their settings on making a
mark look handmade. Spacing 1.35 (more than one stamp width, so the dots are
separated rather than a chain; below about 1.15 they touch and it stops being
dots), and zero for scatter, angle jitter, size jitter and speed thinning. Zero
scatter is what "keeps to a single track" means: any at all and the row
visibly wanders. Zero speed thinning is what stops the row thinning where the
hand sped up.

The shapes are not `round_buffer` with a hard setting. A brush's soft edge is
what lets two dabs read as one stroke; a knife dot must read as a circle, so
the edge is a **one-pixel transition** — solid inside, nothing outside, one row
of in-between pixels for antialiasing and no more. The diamond is the square
turned, shrunk by its own diagonal so the stamp does not clip it to an octagon.

## Frames

### The border box

A comic page opens as one frame inset from the paper's edge, so the edge of the
paper and the edge of the artwork are two visible lines. It is drawn whenever a
comic page is on screen, not only while the tool is open.

### Panels are polygons, and the cuts are not stored

Two decisions worth defending.

**Polygons, not rectangles.** The first diagonal cut makes a rectangle a lie. A
system storing rectangles must either refuse the diagonal or store a rectangle
that is not where the panel is — and the second is worse, because the drawing
then clips against a boundary nobody can see.

**A flat list, not a split tree.** A tree remembers *how* the page was cut,
which sounds like more information and is a cage: moving one border means
re-deriving every cut after it, and a border that cannot be nudged is a layout
that must be restarted whenever it is nearly right. History belongs in the undo
stack.

### Cutting

Sutherland–Hodgman half-plane clipping. Fifteen lines, no special cases, and
**exact** — the crossing is solved for, not searched for, so two panels cut from
one share their border to the last bit rather than to within a tolerance.
Panels that *nearly* share a border leave hairlines that show in print and
nowhere else.

The cut line is infinite; the gesture is not. **A panel is cut when the drag
touches it** — either end inside it, or two crossings of its boundary. That is
the whole of "you need not cut all the way across": split the page down the
middle, then drag a short line inside the left half, and the right half is left
bit for bit as it was. The first attempt demanded the drag enter *and leave*,
which is what "divides this polygon" means literally and made the feature
useless — a drag that stops inside a panel is exactly the gesture meaning
"split this one here".

Five shapes: line, rectangle, square, circle, free. The line does the work,
because a page is divided and a division is a line. The other four take a bite
and become a frame. A shape landing mid-panel would leave a ring, and a ring
has a hole — not writable as one closed loop, and not something you can draw in
— so the remainder comes back as two or three rectangles instead.

The gutter is centred on the cut, so both frames give up the same amount.
Putting it all on one side makes the page visibly drift as it is subdivided.

### Confinement, bound at the choke point

`PaintSurface.stamp` is the one place in the app where paint is committed —
brushes, shapes, smudge, the fill's edges, the spline stroker, all of it. The
gate is there rather than at each caller, so a tool added next year cannot
quietly bypass it.

Checked **per dab**, not per stroke: a stroke starting inside a frame and
dragged out must stop at the border, and checking once at the start would let
the rest through. The eraser is gated too — it is a brush that paints nothing,
and letting it through would mean the one tool that reaches into a neighbouring
frame is the one that destroys what is there.

Also checked before the undo snapshot, because snapshotting a tile the stroke
may not touch puts an unchanged tile on the stack, and an undo press that
restores what was already there appears to do nothing.

The rule is phrased as a *refusal* rather than a permission. With no panels,
nothing chosen, or confinement off, the honest answer is "paint anywhere", and
a permission would have to remember to say yes three times. A drawing tool that
refuses to draw because a feature it knows nothing about is in an unexpected
state is the worst failure this could have.

**Draw over** lifts it entirely — for a figure breaking out of its frame, which
is half of what makes a comic page one. Two buttons rather than a toggle:
somebody reaches for this mid-stroke, having just been cut off at a border they
did not want, and at that moment they should not have to work out which state a
toggle is in.

### Bound to everything else

* **Undo/redo** — a cut is an ordinary `History` step (`"t": "frames"`),
  so one press takes back a cut exactly as it takes back a stroke. Two stacks
  would be a promise that the wrong one gets emptied. Stored as its dictionary,
  not the object, since the object keeps being cut after the entry is pushed.
* **Saving** — on the page, beside its layers, written only when present so
  older files read back unchanged. Read *before* the layer guard: a page cut
  into frames but not yet drawn on has no layer rows, and returning early would
  silently drop the layout.
* **Selection, move, bones** — untouched. Confinement is a gate on committing
  paint; nothing else in the app commits paint.
* After a cut the chosen frame is cleared rather than guessed at. The list has
  been rebuilt and index four is a different frame; a stale choice confines
  drawing to a frame nobody picked.

## The test bench

`native/ivory/tests/test_comic.cpp`, compiled standalone against a stub of
Godot's types:

```
g++ -std=c++17 -I<stub> -I../src test_comic.cpp ../src/ivory_comic.cpp -o test_comic
./test_comic
```

**68 checks, 0 failures.** It does not assert that a cut returns a particular
list of points — that is a change detector that fails whenever anything is
legitimately improved. It asserts the properties a correct cut must have:

* **Area is conserved**, minus exactly the gutter. One check that catches a bug
  in the clip, the inset, the winding or the crossing arithmetic.
* **Nothing escapes the page** — every vertex, always.
* **Panels do not overlap**, sampled on a grid.
* **A cut is local** — a short cut inside one panel leaves every other panel
  identical to the last decimal.
* **Nothing crashes** on an empty page, a zero-length cut, an absurd gutter or
  an out-of-range index.

It began at seven failures. Four were real:

1. **The inside-out test was wrong.** I checked the sign of the area, reasoning
   that a polygon folded through itself winds the other way. **False:** inset a
   100×100 square by 60 and you get a square from (60,60) to (40,40) — inverted
   on *both* axes, and inverting both preserves orientation exactly. Positive
   area for a square that does not exist, contained inside the original, and
   smaller than it — passing all three obvious tests. What actually happened is
   visible one level down: **every edge reversed direction.** One dot product
   per edge.
2. **Cuts demanded a full crossing**, described above.
3. **The clip side was inverted for shape cuts** — and it failed *silently*:
   the clip succeeded and returned the panel nearly unchanged. Caught only by
   comparing the resulting panel's *area* against the circle's.
4. **The remainder after a shape cut was a ring**, which cannot be stored.

---

# Stage 131 — storage, language, layout

Three new C++ classes, two bone/warp fixes, and a bench runner. Ten classes now
cross the boundary.

## Storage: `ivory_store`

### What is actually hard about saving

Not writing bytes — the vault already does that correctly. Three things
underneath it:

**A process can die at any instruction.** If that instruction is inside
`project.json`, the file on disk is half the old document and half the new one.
The answer is that every write goes to a temporary file, is flushed, and is
then **renamed** over the real one. A rename within a filesystem is atomic: a
reader sees the old file or the new one, never a mixture. **There is no window
in which the data is invalid.**

Two details people leave out. The old pack goes to `.bak` *before* the new one
takes its name, so a death between the two renames leaves the real name
pointing at a complete file. And the data is **flushed before the rename** — a
rename is atomic with respect to the directory entry and says nothing about
whether the contents reached the device, so without the flush a power cut can
leave the new name pointing at a file of zeros.

**Most of a project is unchanged.** Every record carries a 64-bit FNV-1a hash
of its own bytes; putting identical bytes twice compares the hash and returns.
That is what makes an autosave where one layer was touched cost one layer.

*An honest word on speed.* Sub-millisecond is achievable for deciding what to
write and for the metadata — the parts that run on every autosave tick. It is
not achievable for flushing twenty megabytes of new pixels to a phone's flash,
and no format makes that instant. What this does is make sure the twenty
megabytes are written only when twenty megabytes changed.

**Two saves can collide.** All records live in **one pack file**, so the atomic
rename covers the whole project. Forty separate files means forty renames and
forty chances to be killed between two of them, leaving a folder that is
internally inconsistent — which is exactly the tangling this prevents.

### The format

Header, payload, index, index CRC. The index is at the **end** so records can
be appended without rewriting what came before. Its CRC is checked before any
offset in it is used, and each record's CRC before that record is handed out —
so a bad block is detected as one rather than returned as data. A damaged
record fails the whole pack rather than being skipped: a project silently
missing one layer is worse than one that says it could not open, because the
first is discovered days later with the work gone.

## Language: `ivory_lang`

The table stays in GDScript. Three things were wrong underneath it.

**Arabic plurals.** `count_of` chose between two wordings and its own comment
admitted Arabic needs more and shrugged. Arabic has **six** categories:

| count | category | |
|---|---|---|
| 0 | zero | |
| 1 | one | |
| 2 | two | a real grammatical dual |
| 3–10 | few | and 103, 203… |
| 11–99 | many | and 111, 211… |
| 100+ | other | |

Choosing "many" for two is wrong the way "two frame" is wrong in English. The
rules are CLDR's, transcribed, and checked at every boundary the published rule
names — a transcription right for small numbers and wrong at 102 is the one
that ships, because nobody tests a panel with 102 of anything.

**Digits.** The GDScript converter appended to an immutable String per
character, which is quadratic. One pass into one buffer now.

**Bidirectional text — the one nobody sees until it is pointed out.** Drop a
Western number into an Arabic sentence and the bidirectional algorithm may pull
it out of place: two numbers in one sentence can swap, a trailing bracket can
jump to the wrong end. Each substituted value is now wrapped in U+2068/U+2069,
which makes the algorithm treat it as one unit placed where it sits.

`fill` also became a single pass, which is not only faster but **correct**: one
`replace` per argument means a value containing the text "{1}" gets reached
into by the next replace. A single pass never looks at what it has written.

`fault_of` checks a translation row mechanically: empty, untranslated,
mismatched placeholders, absurd length. A missing `{0}` prints nothing where a
number belongs; an extra `{2}` prints those characters to the user. Both are
silent unless somebody opens that panel in that language.

## Layout: `ivory_layout`

Controls in containers cannot overlap. The ones that collide are positioned by
arithmetic — floating panels under their buttons, rails that grow with the tool
count — and arithmetic right for one screen is wrong for a narrower one.

**The failure is nastier than it looks.** Two buttons overlapping by six pixels
look fine, and the top one takes every touch in the shared strip, so the bottom
one has a dead edge. Nobody reports "these overlap"; they report "sometimes
this button doesn't work".

Sweep and prune, with two rules that make the result predictable: **pinned
rectangles never move** (a panel anchored under its button must stay there), and
rectangles are pushed apart along their **smaller** overlap (two pixels
horizontally and forty vertically is a horizontal problem). Separation is
enforced with a gap, not to zero — two buttons exactly touching are still two a
fingertip cannot reliably choose between.

`touched` is not "the first rectangle containing the point": a touch in the gap
goes to the nearer control within slop, and a touch inside two goes to the one
whose centre is nearer rather than to whichever came first in the list.

## Bone: joints no longer flip

FABRIK solves positions and knows nothing about which side a joint bends to.
Two links were fine — the closed form keeps the elbow. Three or more had
nothing keeping it, so a long chain would flip a joint inside out partway
through a drag: a knee bending backwards for one frame and then staying there.

The fix is not to constrain the solve, which would fight it, but to notice
afterwards. A joint's bend has a sign — the cross product of its two links — and
a flipped sign is a joint that turned through straight. Reflecting it back
across the line joining its neighbours restores the side **without changing
either link's length or where the chain ends**, so the solve is preserved
exactly and only the choice between its two mirror answers is corrected.

## Warp: the shear taken out

A full affine fit is scale *and shear*, and shear is the part nobody wants:
pulling one pin slid the far side past the near side, so a rectangle became a
parallelogram and a face pulled by the chin came out leaning. It read as the
drawing sliding rather than compressing — the exact complaint affine mode was
brought in to answer.

The matrix is now decomposed by Gram-Schmidt and rebuilt without the skew: keep
the first column's direction, take the part of the second square to it, keep
each one's own length. What survives is a rotation and an independent scale per
axis, which is stretching and squashing and nothing else. Blended at three
quarters rather than replaced outright, because where several pins disagree
some shear genuinely is the least-wrong answer.

## The benches

```
cd native/ivory/tests && ./run_tests.sh <path-to-stub>
```

**170 checks across three benches, 0 failures.** They compile against a small
stub of Godot's types rather than godot-cpp, on purpose: a bench that needs the
engine present is a bench nobody runs.

They found four more real bugs this stage:

1. **The layout resolver never settled.** Sweep and prune depends on the list
   being sorted by left edge and on the early `break` being sound. Moving a
   rectangle mid-sweep invalidates both — the pass then reports itself settled
   while rectangles are still on top of each other. Displacements are now
   gathered and applied at the end of a pass.
2. **And then it oscillated.** The push used a percentage over half — 0.52 —
   to clear the margin rather than land on it. A four percent overshoot meant
   each pass pushed a pair slightly too far, the next pushed back, for ever. It
   looked like convergence failing; it was over-relaxation. A fixed absolute
   hair does the same job and cannot overshoot.
3. **`has_rtl` was wrong about digits, and this one is the good one.**
   It tested the whole 0x0590–0x08FF block, which reads like the right answer.
   **Arabic-Indic digits live inside that block**, at 0x0660–0x0669, and their
   bidi class is AN — *weak*, not a strong direction. So a number converted to
   Eastern digits was reported right-to-left and never isolated: **the
   isolation was off precisely where it was needed and on everywhere else.**
   Caught only because the bench asserts the *length* of a filled Arabic
   sentence, which counts the invisible marks. Nothing visible would have
   shown it.
4. Confirmed the CRC table against the published check value (0xCBF43926 for
   "123456789") rather than against itself — a table built wrong is still
   self-consistent and would pass every round-trip test.
