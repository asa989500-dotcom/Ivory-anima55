# IVORY — Selection Tools / C++ Guard Fix

## Root cause found

The selection pipeline reached `scripts/canvas_marks.gd:141` and attempted:

`p._distort_base = img.duplicate()`

`CanvasView` did not declare `_distort_base`. Godot therefore treated the
assignment as an invalid property write on the `CanvasView` Control and stopped
the selection lift path. This is why the selection could be drawn but failed
when it was released/converted into a floating selection.

## Fixes

1. Declared `_distort_base: Image = null` in `CanvasView` as real selection
   state instead of a dynamic property.
2. `float_image()` now initializes `_distort_base` as well, so distortion is
   always based on the immutable source image.
3. `_distort_base` is cleared whenever the floating selection is dropped,
   preventing stale-image reuse between selections.
4. Added `IvorySelectionGuard` in C++ as a numerical safety boundary.
5. Added three protection layers:
   - C++ numerical guard: finite coordinates, finite transform values, valid
     area, safe scale, and maximum transformed bounds.
   - GDScript lifecycle guard: selection must have enough points, a live
     selection must own a texture, and non-finite touch coordinates are refused.
   - Existing raster/size guards remain in the actual lift/commit path, so the
     expensive image operations still have their own limits.
6. The native guard is optional and never prevents the app from running when
   the GDExtension is not built; the GDScript protections remain as fallback.
7. Added `native/ivory/tests/test_selection_guard.cpp` with 7 executable
   checks covering normal selections, NaN coordinates, oversized selections,
   invalid scale, and NaN rotation.

## Validation performed

- `check_indent.py`: 0 problems
- `check_identifiers.py`: 0 undeclared identifiers
- `check_scope.py`: 0 unresolved/dead-member problems
- `check_references.py`: 0 unresolved references
- `check_warnings.py`: 0 compiler-warning candidates
- `check_native_names.py`: 0 naming problems
- `check_registration.py`: 41 native classes, 0 registration problems
- Native selection guard test: **7 checks, 0 failures**

## Build note

The project checkout does not contain `native/ivory/godot-cpp` or a built
`bin/libivory...` library, and the root `ivory.gdextension` is intentionally
kept disabled in this checkout. Therefore the Android/Desktop GDExtension
binary itself was not fabricated. The new C++ guard is source-integrated and
its standalone native test compiles and passes; once the project's normal
Godot/godot-cpp build is run, `IvorySelectionGuard` is registered automatically.
