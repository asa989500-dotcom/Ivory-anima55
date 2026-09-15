# IVORY Stage 173 — Stretchy Studio Error Fix

Fixed in `scripts/stretchy_studio_standalone.gd`:

1. `_export_model3()` declared `result_native` but incorrectly passed the undeclared `result` to `_report_export()`.
   - Before: `_report_export(result)`
   - After: `_report_export(result_native)`
2. This also removes the `UNUSED_VARIABLE` warning for `result_native` (with warnings treated as errors).

The dialog branch already uses its local `result` correctly, so it was left unchanged.

No 2.5D files or Stretchy Studio systems were removed or altered by this fix.
