# IVORY — Stage 135

## Puppet Warp fold-over protection

The native and GDScript Puppet Warp solvers now preserve triangle winding and
keep every triangle above a small positive area floor. When an ARAP/smoothing
step would invert a triangle, the solver binary-searches the exact step and
keeps the largest feasible fraction. Pin projection uses the same guard, so a
pin stops at a geometric limit instead of flipping the mesh or snapping the
whole drawing back to rest.

The native solver retains the real triangle list and rest signed areas for the
constraint. The fallback implements the same feasibility test and line search.

## Code inspection device

Added `tools/code_inspector.py` and `tools/inspect_project.sh`. The inspector
checks delimiters, resource paths, obvious GDScript hazards, native class
registration/implementation consistency, and then runs the project's existing
static checker suite. It can emit `build/code_inspector_report.json`.

The inspector distinguishes correctness errors from the existing file-size
ledger debt. Warnings are visible and `--strict` can promote them to failure.
