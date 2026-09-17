# Stage 70 — the keystone, and the ring becomes automatic

## 1. The mesh is fitted, not drawn

You were right and it is a better design. Asking the artist to draw the ring
was one step too many and one decision too many: a ring drawn by hand can be
drawn badly, put in the wrong place, or forgotten — and it is information the
app can simply **read**, because the mouth is right there on the layer.

`MouthRing.fit()` measures it instead:

- The centre is the ink's **centre of mass**, weighted by how solid each pixel
  is — so a mouth with a heavy lower lip has its centre where the drawing's
  weight actually is, rather than in the middle of a rectangle.
- The radius at each of thirty-two angles is the distance to the furthest ink
  in that direction, so the ring hugs the mouth as drawn rather than being an
  approximation of it.
- Angles where no ink was found are filled from their neighbours — the gap
  between two lips does not put a notch in the ring.
- A little padding, so the ring sits just **outside** the drawing rather than
  through it: the outermost ink then moves with the ring instead of sitting
  exactly on the boundary where the falloff begins.

And it is a **regular mesh** — even squares, no adaptive subdivision, nothing
to place or tune. That is the right shape for this problem for the same reason
graph paper is: the deformation is smooth everywhere, so nowhere deserves more
points than anywhere else, and a grid of two densities meeting would show the
seam between them.

Every piece of maths verified in stage 68 is untouched — exact on the ring,
lets go before the cheeks, cannot fold through itself, closes to 3% whatever
the mouth. The only thing that changed is where the ring comes from.

## 2. `RigSkin` — the gap that was blocking everything

Everything built over the last several stages could pose a layer and **none of
it could show the pose**. `RigTrack` held the poses, `AnimPlayer` read them at
the right moment and emitted them, the B-Spline room could bend a figure, the
mouth ring could bend a mouth — and the canvas went on drawing the layer flat,
because a layer is a grid of tiled sprites and a grid of sprites cannot bend.

The B-Spline room got around it by **baking**: render the deformed mesh into a
`SubViewport`, read the pixels back, stamp them into the layer. That is right
for committing a pose and hopeless for playing one — a viewport render and a
texture readback per frame per layer is a cost of an entirely different order
from drawing a mesh.

`RigSkin` is a `MeshInstance2D` that stands where the layer's surface stands,
holds the layer's picture as one texture, and draws it through a mesh whose
points move. The surface is hidden behind it.

**Nothing is written to the layer.** That is the other half of why this is
right: *playing an animation must not modify the drawing*. When the skin goes
away the surface comes back exactly as it was, because it was never touched.

Three decisions worth naming:

- **The picture is captured once**, when posing begins — not per frame.
  Capturing means reading pixels back off the surface, which is precisely the
  thing that must not happen sixty times a second.
- **The rule is a Callable.** `RigSkin` holds the picture and the triangles and
  has no opinion about the bending, so one class serves the mouth ring, the
  bone rig and whatever comes next. A bone rig, a mouth ring and a puppet warp
  have completely different ideas about where a point should go, and none of
  them belongs inside the thing that draws.
- **Coarser on a slow device** — 16 cells instead of 32 when `Perf` says so.
  The pose is identical either way; only how finely the picture follows it
  changes. A slightly faceted bend running at speed beats a smooth one that
  stutters.

### The bone weighting

Each bone claims the points near its own line, and a point claimed by two is
**shared between them in proportion** — so a point on an elbow is half upper
arm and half forearm and bends as an elbow does, rather than snapping from one
bone's authority to the other's at some invisible boundary.

Distance is measured to the **segment**, not to the bone's ends. A point beside
the middle of a long bone belongs to it as firmly as one beside its tip, which
is simply not true if only the endpoints are consulted — and getting that wrong
is what makes long bones look like they only affect their own tips.

**Verified — twenty-four checks, all passing:**

- the mesh is well formed at 2, 8 and 32 cells: vertex, UV and index counts
  agree, every index is in range, and it covers its rectangle exactly
- no zero-area triangles, and all wound the same way — a flipped triangle is a
  hole in the drawing
- an unmoved bone moves nothing; a translated bone translates everything with it
- a point at a bone's tip follows a 90° turn exactly; so does one at its middle
- with two bones, the shared elbow **stays put**, the far tip follows the
  forearm, and the upper arm barely moves

## 3. The loop is closed

- `AnimPlayer` now **draws** the pose rather than only announcing it. `_show_pose`
  puts the skin on once and reshapes it after that.
- The B-Spline room writes `bones_rest` — the same skeleton said a second way,
  as two flat arrays and the lengths, because the skin weights a thousand
  points against every bone every frame, and unpacking a nested dictionary a
  thousand times a frame to find four numbers is work nobody needs done.
  Held in memory and never written to disk: derived state in a file is state
  that can come to disagree with what it came from.
- Leaving the room drops every skin. A skin outliving the thing that posed it
  is a drawing frozen in a pose nobody can now change.

---

## What this unblocks, and what is left

Now that poses reach the canvas, **onion skin showing poses** and **the mouth
ring bending the mouth on screen** are both reachable — they were waiting
behind exactly this.

Still to come: the buttons that let a finger reach all of it — recording a rig
key from the timeline, linking a sound to a layer, `stick`, and making a folder
a chart. The machinery beneath every one of them is in and tested.

I would rather you opened this one and told me what you see before I build the
controls on top of it. This is the stage where that matters most: it is the
first time a pose becomes something you can look at.

## Files touched

new `rig_skin.gd` · `mouth_ring.gd` (automatic fit, regular mesh) ·
`layer_stack.gd` (wear/shed skins) · `anim_player.gd` (`_show_pose`) ·
`bspline_room.gd` (`rest_skeleton`) · `main.gd` (shed on leaving)

Static analysis clean: use-before-declaration 0, brackets balanced, no
duplicate functions, no unused parameters, no shadowing, no global-name
collisions, no dead references.
