# IVORY native rig core upgrade

This stage adds `IvoryRigCore`, a C++ production kernel for the rig path.

Implemented in native C++:
- deterministic, finite-safe FK/IK solve
- cycle/invalid-parent sanitization
- zero-length-safe math
- two/broad-chain FABRIK-style IK with pole direction
- optional stretch and soft target handling
- optional angular limits
- IK/FK weight entry point
- fixed rest lengths
- World/Parent/Local/Bone transform spaces
- per-bone depth storage for the 2.5D layer
- normalized multi-bone weights and native skinning
- corrective offsets
- validation and deterministic stress testing

The existing native classes remain intact; the new core is registered as
`IvoryRigCore` and exposed through `Native.rigcore()`. UI code can migrate to
this kernel incrementally without making the extension mandatory.

Important: the solver is deliberately stateless between `solve()` calls. No
previous frame is used to influence the mathematical answer, which makes the
core deterministic and removes temporal jitter from the solver itself. Input
smoothing belongs at the interaction layer, not inside the mathematical solve.

The two-bone path uses the closed-form triangle solution; chains use bounded
FABRIK iterations. IK/FK is blended in wrapped angle space, avoiding matrix
candy-wrapper collapse.
