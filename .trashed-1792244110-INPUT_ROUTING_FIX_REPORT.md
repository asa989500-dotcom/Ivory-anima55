# IVORY — Canvas Input Routing Fix

## Root cause
The main-room floating-panel dismiss shade was a full-screen `Control` using
`MOUSE_FILTER_STOP`. When a tool panel was open, a touch on the drawing area
hit the shade first. The shade closed the panel, but the original touch event
was consumed instead of reaching `CanvasView`, so brush, fill, selection and
other canvas tools appeared unresponsive.

## Fix
- The main-room shade is now `MOUSE_FILTER_IGNORE`; it is visual state only.
- `MainRoom._input()` checks whether a press is outside the active panel and
  closes the panel before normal GUI routing.
- The same input event is therefore still available to `CanvasView`.
- Touches inside the panel remain owned by the panel.
- No brush engine, fill algorithm, selection engine, layer model, rig solver,
  or paint-surface code was changed.

## Regression coverage
- `tools/check_input_routing.py` — source-level routing guard.
- `tests/test_input_routing.gd` — Godot-side regression test registered in
  `tests/run_tests.gd`.
- Manual event-routing simulation — outside-panel press closes panel and
  continues to canvas; inside-panel press remains with the panel.

## Validation in this runtime
Passed:
- input-routing regression guard
- Python syntax compilation of the new checker
- check_indent
- check_const
- check_identifiers
- check_scope
- check_self_calls
- check_warnings
- check_returns
- check_continuations
- check_shadow
- check_lambda_capture
- check_inference
- check_native_names
- check_references
- check_room_buttons
- check_structure
- check_json_safe
- check_lang
- ivory_20_guard

The full Godot runtime test suite could not be executed because this runtime
has no `godot` executable. `check_size.py` also reports a pre-existing project
ledger violation: `scripts/puppet_warp.gd` is 1203 lines, three over its 1200
line limit; this is unrelated to the input-routing patch.
