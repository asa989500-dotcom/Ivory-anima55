# STAGE 143 — Character 360 Two-View Reconstruction

## Scope
The 2.5D entry in the B-Spline room now opens a dedicated two-view builder.
The new workflow is front PNG + side PNG -> normalized silhouette reconciliation ->
measured depth profile -> smooth 2.5D relief -> automatic Character 360 rig.
No drawing-on-top workflow and no ivory-point placement are used by this builder.

## Native core
`IvoryCharacter360` is a native C++ RefCounted class. It accepts RGBA buffers,
normalizes the two views by occupied rows, derives maximum depth from the side
silhouette, creates a rounded relief from the front silhouette, smooths it inside
alpha, reports symmetry/silhouette/distortion diagnostics, and exposes bounded
2.5D projection plus batch projection and view rendering.

Depth strength is clamped to 0.25..3.0; supported yaw/pitch/roll are bounded to
avoid unstable extrapolation. Projection is a single rigid rotation followed by
weak perspective, not an average of separately rotated positions.

## Layers
A generated `character 360` layer receives the front artwork, the reconstructed
state, and an automatic rest skeleton. A separate `Character 360 Motion` layer is
created as a controller-only, motion-only layer and carries the same rig metadata.
The layer stack treats these as non-drawable once rigged, and the state is persisted
through Vault. Front/side PNG buffers are written beside the project manifest rather
than bloating JSON/undo snapshots.

## Bone setup
The automatic rig is a stable spine/head plus four limb chains. Existing BoneRig
forward kinematics, joint closure, length preservation, limits and smart-bone logic
remain the single source of truth for touch posing.

## Validation
- 10 dedicated test suites.
- 29 deterministic checks.
- 0 failures.
- Static Character 360 integration checks: 14/14 pass.
- Existing project checker reached zero reported problems before its global timeout;
  the final long-running aggregate step is environment-limited, not a failed check.
- Android/GDExtension compilation was not claimed because `godot-cpp` is not vendored
  in the supplied archive.
