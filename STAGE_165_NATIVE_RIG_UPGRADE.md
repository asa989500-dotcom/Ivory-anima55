# Stage 165 — Native rig/animation hardening

This stage is an implementation upgrade on top of the existing C++ rig core,
not a parallel rig system.

## What changed

### 1. Pole-vector IK is now length-safe
`IvoryRigCore::chain_ik` now uses the correct `N bones -> N+1 joints`
representation and alternates FABRIK with a pole projection that rotates a
whole suffix around the pivot. This preserves every solved link length instead
of reflecting one joint after the fact.

### 2. Fixed long-chain geometry bug
The former implementation allocated only `N` joint positions for an `N`-bone
chain and overwrote the final bone head with the tip. Three-or-more-bone chains
could therefore solve against a malformed chain. The new implementation keeps
all heads plus the terminal tip.

### 3. IK/FK weight semantics are explicit
`set_ik_fk_blend(bone, 0)` now really means FK and `1` means full IK. New rigs
start at full IK, preserving the previous default behaviour while making an
explicit zero meaningful.

### 4. Removed the redundant second IK solve
The previous `solve()` ran the IK targets twice, with the second pass using the
already blended pose as its new FK reference. That could progressively bias
blends toward IK. The solver now snapshots the FK state once, solves once,
applies limits/length projection, then rebuilds the final FK pose.

### 5. Native animation kernel
`IvoryAnimation` adds deterministic shortest-path angle blending with smoothstep
settling plus frame-crossing animation events. It is registered through the
existing optional native bridge; project timeline data remains owned by
GDScript.

## Validation

Added `native/ivory/tests/test_rigcore_pole.cpp` and `native/ivory/tests/test_animation.cpp`. The rig test covers:
- four-link IK chain allocation;
- numerical validity after solve;
- exact adjacent-joint closure;
- rest-length preservation;
- pole-side changes.

The source was also checked for balanced C++ delimiters, local file structure,
and the new animation translation unit was compiled with Clang 17 against a
minimal Godot-header compatibility stub using `-Wall -Wextra -Wpedantic -Werror`.
The long-chain `chain_ik` body was separately compiled as a standalone mock and
its runtime regression reached the target with zero joint-gap and negligible
length error. A complete Godot C++ compilation cannot be truthfully claimed from
this source archive because the required `godot-cpp` checkout/headers are not
vendored in the project and are not present in this environment.
