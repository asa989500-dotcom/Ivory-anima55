# IVORY Stage 163 — Puppet Warp core upgrade

## Changes made

1. **The active Forge path now uses `IvoryWarp` directly.**
   Stage 162 forged the mesh with `IvoryMeshForge`, then routed deformation through
   a separate `IvoryArapSolver`. That bypassed the project's complete native warp
   engine (`IvoryWarp`), including its affine/similarity modes, turn handling,
   bounds and native fold-over protection. The Forge path now hands the forged
   mesh to the per-instance `IvoryWarp` solver instead.

2. **Removed global native solver state from `PuppetWarpForge`.**
   A static solver could be reused by different PuppetWarp nodes when their mesh
   stamps collided or a second warp was opened. The native solver is now the
   `PuppetWarp._fast` instance belonging to that warp, so mesh and pose state
   cannot leak between documents/layers.

3. **Mesh handoff happens immediately after a forged mesh is built.**
   The C++ solver receives the exact forged topology once per rebuild, while pin
   positions continue to be updated without rebuilding the mesh or distance field.

4. **Multi-pin hold is now a union instead of `max()`.**
   At overlapping pin regions, the strongest pin no longer completely erases the
   protection supplied by the other pins. The union `1 - product(1-h_i)` keeps
   both controls contributing to the protected ARAP region. The GDScript fallback
   was changed to match the native behavior.

5. **Native smoothing follows the real triangle topology.**
   The old native smoothing pass used the four raster neighbours. It now uses the
   actual forged triangle-edge graph and cotangent weights, while preserving the
   outline rule. This removes a horizontal/vertical bias and makes smoothing work
   correctly on irregular/adaptive mesh valence.

## Expected result

- More coherent deformation when several pins influence the same joint.
- No cross-instance native solver contamination.
- Affine/similarity/rigid modes and pin turns are handled by the same native warp
  engine used by the rest of the Puppet Warp implementation.
- Better smoothing on the actual forged topology.
- Fold-over and bounds protection remain inside the native solver.

## Validation

The ZIP was unpacked and the relevant Puppet Warp GDScript/C++ sources were
inspected after modification. A Godot native build could not be executed in this
runtime because the checkout does not contain a built `godot-cpp` dependency and
no network dependency fetch is available here. The resulting source therefore
needs the project's normal native `scons` build/test on the target Godot setup
before shipping.
