# STAGE 140 — Text Object Interaction Kernel

This stage focuses only on the text tool.

## Changes

- Added `IvoryTextTool` in native C++ for the hot interaction path.
- Text hit testing, move delta, anchored proportional resize, rotation delta,
  scale clamping and non-destructive preview transforms are native.
- Text no longer freezes visually while its handle box moves: the existing
  text surface receives a temporary Node2D transform during the finger drag.
- The preview transform is removed on release and the text is re-rendered from
  its source words, preserving crisp output.
- The held text box is taken from the measured text-object rectangle rather
  than tiled `content_bounds()`, removing the old 256px/512px inflation.
- Rotated re-renders are centred on the logical text object, so rotation does
  not make the caption walk away from its handle box.
- Added clear rotation controls: snap rotation and configurable snap step.
- Text creation waits for one render frame instead of two.
- Duplicating a text layer now preserves its text metadata and transform.

## Verification

Dedicated static guardrails: 10/10 PASS.

Seven focused native-interaction tests:

1. Tight object bounds — PASS
2. Exact finger translation — PASS
3. Opposite-corner resize — PASS
4. Rotation without first-frame snap — PASS
5. Centre-preserving preview transform — PASS
6. Scale clamp — PASS
7. 100,000 hot-path preview transforms — PASS

A standalone arithmetic benchmark for the same interaction formulas completed
100,000 preview operations in under 100 ms in the build environment.

## Runtime note

The uploaded environment does not contain Godot or the generated platform
`libivory` binaries, so an Android/Godot runtime build was not falsely claimed.
The project-side GDScript static checks and the native interaction arithmetic
were verified here; the native `.so` must still be built with the project's
existing `native/ivory/SConstruct` before Android runtime testing.
