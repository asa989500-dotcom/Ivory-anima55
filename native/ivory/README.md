# The native half

`puppet_warp.gd`, `rig_skin.gd` and `touch_lead.gd` all work without this. That
is the point of it: everything here has a GDScript twin that runs when the
library has not been built, so a fresh checkout runs, and a partial build —
Android done, desktop not — runs too.

Godot logs one line when a `.gdextension` names a library file that is not
there, and carries on. `scripts/native.gd` then finds no `IvoryWarp` class and
the GDScript path is used.

## Building

```
cd native/ivory
git clone -b 4.4 https://github.com/godotengine/godot-cpp
cd godot-cpp && git submodule update --init && cd ..

scons platform=android arch=arm64 target=template_release
scons platform=android arch=arm32 target=template_release
```

The libraries land in `bin/` at the project root, where `ivory.gdextension`
already expects them. Nothing in the project needs editing after a build; the
next run picks the classes up.

For desktop testing: `scons platform=linuxbsd target=template_debug`, or
`platform=windows`, or `platform=macos`.

## What is in here

**`ivory_warp`** — rigid moving least squares over the pins, then
as-rigid-as-possible over the mesh. The same two solvers `puppet_warp.gd`
runs. Three things are better in method, not merely in speed:

* Walked distance through the mesh is **Dijkstra with a binary heap**, so each
  vertex is settled once and the answer is the true shortest path. The GDScript
  converges towards it with relaxation sweeps and stops when it is close.
* The ARAP global step is **over-relaxed** (`omega` about 1.62). Gauss-Seidel
  on a Laplace system converges at a rate set by the mesh; SOR is the textbook
  accelerator for exactly this and reaches the same fixed point in roughly a
  third of the sweeps. Same answer, sooner.
* The MLS sums are accumulated in **double**. The weights span several orders
  of magnitude within one vertex, and in single precision adding the far pin to
  the near one discards it — a pin contributing nothing is a pin whose share of
  the rotation quietly went to its neighbours.

**`ivory_skin`** — which separate drawing each part of a layer is on, and where
every point of the skin goes. The weighting is exactly `RigSkin.bone_rule`:
anchors averaged as positions, turns averaged as *directions*. Averaging the
positions each bone would put a point at is the famous mistake and it is what
collapses an elbow at a hundred and eighty degrees.

**`ivory_touch`** — the one-euro filter (Casiez, Roussel, Vogel 2012) with a
short forward lead. Used on warp pins and bone joints, which are controls being
aimed. Never on ink: predicting a brush stroke would be inventing ink that was
never drawn.

## The boundary

Kept narrow on purpose, because crossing it is the one cost C++ does not remove.

* The mesh crosses **once per rebuild** — several thousand vertices and four
  neighbours each.
* The pin *set* crosses when a pin is added, removed or anchored, because that
  is what makes the walked distances stale.
* Pin *positions* cross on every frame of a drag, which is a few dozen floats.

Sending the mesh every solve would spend more than the solve saves.
