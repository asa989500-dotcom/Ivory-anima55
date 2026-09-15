# IVORY Stage 178 — Stretchy Export Scope Fix

## Root cause
`scripts/stretchy_studio_standalone.gd` had the fallback `.model3.json` export setup indented inside the `for l in document["layers"]` loop.

That made these variables block-local to the loop in Godot's parser:
- `json_text`
- `filename`
- `plan_export_file`

The following statements were then outside that scope and produced the editor errors shown in the supplied screenshots, including:
- `Identifier "plan_export_file" not declared in the current scope`
- `Identifier "filename" not declared in the current scope`
- `Identifier "json_text" not declared in the current scope`

## Corrective change
The repaired `_export_model3()` now has this stable structure:

1. Build `texture_files` in the layer loop.
2. Exit the loop.
3. Build `json_text` at function scope.
4. Build `filename` at function scope.
5. Build `plan_export_file` at function scope.
6. Run the dialog/non-dialog export branches from that shared scope.

The variable declarations were also made explicitly typed for stronger compiler inference:
- `var json_text: String`
- `var filename: String`
- `var plan_export_file: Dictionary`

No unrelated Stretchy, bone, puppet-warp, canvas, or 2.5D systems were changed by this repair.

## Regression guard added
Added `tools/check_stretchy_export.py` and wired it into `tools/check_all.py`.
It verifies the export variables stay at function scope, the loop only owns texture collection, both save paths use the correct variables, and the stale bare `result` report call is absent.

Result: **12/12 checks passed**.

## Validation performed
The project inspection suite was run after the repair.

Passed static gates:
- indentation: 0 problems
- constants: 0 problems
- identifiers: 0 undeclared
- scope: 0 unresolved names
- self calls: 0 invalid calls
- warnings checker: 0 compiler-warning findings
- returns: 0 impossible returns
- continuations: 0 suspect continuations
- shadowing: 0 redeclarations
- lambda capture: 0 failures
- type inference: 0 uninferable declarations
- native-name guard: 0 collisions
- references: 0 unresolved references
- registration: 0 registration problems
- room buttons: 0 problems
- input routing: passed
- JSON safety: 0 unsafe fields
- language table: 0 problems
- Stretchy export regression guard: 12/12 passed
- code inspector: **0 errors**

The code inspector still reports pre-existing warnings for integer-division patterns elsewhere in the project and a project-size warning; these are unrelated to the reported Stretchy scope failure.

## Environment limitation
A full Godot runtime parser/build could not be executed in this container because the Godot executable is not installed.
The project's native compile checker also depends on the complete `godot-cpp` headers; this ZIP intentionally does not vendor them, so its local stub reports unrelated missing/incomplete Godot API pieces for some native Stretchy sources.

The supplied screenshots' GDScript scope fault itself is corrected and covered by a dedicated regression check.
