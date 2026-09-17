# IVORY — 2.5D removal report

This build removes the retired 2.5D/reference-room subsystem without removing the independent Character 360 rig, Puppet Warp, bone systems, Smart Bone, Stretchy Studio, audio/performance tracks, or MP4 export.

## Removed UI/code
- Retired 2.5D compass entry and its callback/lifecycle.
- `scripts/ui/character360_builder.gd`
- `scripts/reference_engine.gd`
- `scripts/inspector14.gd`
- 2.5D-only Character360Builder integration from `BSplineRoom`.
- Retired 2.5D compass icon `assets/icons/bspline.png`.

## Removed native 2.5D/reference classes
- IvoryDepth
- IvoryDeform
- IvoryPoseAtlas
- IvoryPoseGuard30
- IvoryImageIntake
- IvoryRigFit
- IvoryInspector14
- IvoryRig25D
- IvoryRigDoctor
- IvoryFaceParallax

Their headers, implementations, registrations, and dedicated tests were removed.

## Preserved
- Character 360 native rig and its touch/IK/FFD functionality.
- Shared stability kernel.
- Smart Bone and circular pose deformer.
- Puppet Warp and its depth ordering for pins/mesh.
- B-Spline animation-layer room.
- Stretchy Studio, audio/performance tracks, and MP4 export.
- General image import; it now uses the normal Godot decoder directly instead of the retired reference-room intake class.

## Validation
- GDScript static checks: 0 indentation problems, 0 undeclared identifiers, 0 unresolved names, 0 method-call problems, 0 uninferable declarations, 0 registration problems.
- Remaining native source registration count: 34 classes, all registered.
- Character 360 native test: 110 checks passed.
- Character 360 ultra test: 70 checks passed.
- Smart Bone test: 2003 checks passed.
- RigCore pole test: 6 checks passed.
- Animation test: 6 checks passed.
- Skin test: 15 checks passed.

A complete Godot/godot-cpp Android build was not available in this environment because the checkout does not contain the `godot-cpp` dependency. The native source checker therefore reports only the two pre-existing stub-header limitations (`math.hpp` and `utility_functions.hpp`), not errors introduced by the 2.5D removal.
