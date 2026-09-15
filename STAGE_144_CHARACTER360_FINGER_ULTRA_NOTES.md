# IVORY Stage 144 — Character 360 Finger/Rig Ultra

## Delivered
- Character 360 builder now prefers the native IvoryRig360 as the source of truth when the extension is present.
- Each generated hand receives 5 digits × 3 phalanges = 15 finger bones, with constrained joints.
- Added low-latency constrained CCD IK (`solve_ik`) and touch convenience (`drag_to`) to IvoryRig360.
- Added an explicit `character 360 motion` controller-only layer in the native rig export.
- Character 360 state records rig version, finger rig presence/count, and motion-controller layer identity.
- The normal BoneRig row dictionary remains the interchange format, so existing skin/timeline code is preserved.
- Non-native fallback remains available; it keeps the base rig functional.

## Verification
- Native legacy rig tests: 110 checks / 0 failures.
- Character 360 Finger/Rig Ultra: 70 checks / 0 failures.
- Character360 Python tests: 12 / 12 checks.
- 2.5D Ultra regression: 24 / 24 checks.
- GDScript indentation/identifier/return static checks: 0 problems.

## Important engineering boundary
The new finger rig is a deterministic procedural skeleton attached to the generated hand anchors. It does not claim to infer every individual finger pixel from arbitrary artwork. Existing skinning carries drawing with the bones; per-pixel finger segmentation would be a separate vision/reconstruction feature.
