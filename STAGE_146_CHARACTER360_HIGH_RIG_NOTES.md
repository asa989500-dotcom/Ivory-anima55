# STAGE 146 — Character 360 High Rig Upgrade

Implemented on top of `IVORY_stage145_SMARTBONE_DEFORM_25D.zip`.

## Core fixes

1. **Multi-disc blending**
   - Character 360 now stores optional turn drawings (`turn_discs`).
   - The native `IvoryCharacter360Rig` calculates circular angle weights.
   - `RigSkin` draws all loaded discs through the same live mesh; no per-frame
     SubViewport bake/readback.
   - The builder exposes six optional turn-disc slots around the front view.

2. **Secondary motion**
   - Existing `BoneSolver.settle` path remains connected to `AnimPlayer`.
   - Native Character 360 controller also contains a bounded second-order settle
     primitive for controllers that need native-only integration.

3. **Lip sync**
   - Character 360 now accepts mouth/viseme data from a companion mouth layer in
     the same Character 360 group and deforms the live skin rather than baking
     the character.

4. **Pose onion skin**
   - Character 360 gets previous/next *rig poses* as mesh ghosts.
   - This is separate from raster onion skin, so the ghosts follow actual bone
     positions.

5. **Live deformation**
   - Character 360 keeps using `MeshInstance2D` live skinning.
   - Disc textures share the current mesh and are blended by GPU alpha.
   - No per-frame SubViewport bake/readback was added.

6. **Pin types**
   - Native controller supports: fixed, bone, rotation, stretch, attribute.
   - Type is explicit in saved/controller state.

7. **Rig undo/redo**
   - Native operation-level snapshot ring (64 states) for rig points, weights and
     turns. It is not sampled per touch event.

## Professional rigging additions

- IK/FK controller path.
- Angular limits, spring damping and look-at target constraints.
- Normalized paintable per-vertex bone weights with brush/radius.
- Independent FFD lattice path, separate from bone deformation.
- Bounded/cycle-safe native math suitable for Android.
- Diagnostics for discs, pins, constraints, weights, FFD and history.

## Compatibility

The native controller is optional. If `IvoryCharacter360Rig` is not present,
the existing GDScript rig continues to work and Character 360 falls back to the
single front texture.

## Important build note

The uploaded project did not contain its `godot-cpp` checkout or prebuilt
native library in the archive, so this archive contains the source changes and
registration but cannot truthfully claim a newly compiled Android `.so`.
Build `native/ivory` with the project's normal SCons/godot-cpp toolchain before
shipping.
