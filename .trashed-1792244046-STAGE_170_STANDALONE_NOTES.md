# Stage 170 — Stretchy Studio, standalone

Stretchy Studio is now its own thing. `StretchyStudioStandalone`
(`scripts/stretchy_studio_standalone.gd`) owns its own document, its own
drawing surface, and its own touch handling — it never reads `view`, never
touches `CanvasView` or `LayerStack`. The compass icon in `main.gd` /
`tool_panels.gd` is the only place Ivory and Stretchy Studio still meet.

The previous `StretchyStudioRoom` (`scripts/stretchy_studio_room.gd`), which
shared the Ivory canvas on purpose (see its own header comment and
`STRETCHY_STUDIO_INTEGRATION.md`), is left in the repository untouched but
is no longer opened from anywhere. Nothing was deleted in case any of its
native-physics wiring (Stage 169) is wanted again in the Ivory-side rig
later; it's simply dormant.

## What's real in this stage

- **`stretchy_studio_standalone.gd`** — the room itself: toolbar (Mesh /
  Bones / Layers / Params / Export), a custom `_StretchyCanvas` with
  multi-touch pan (drag), pinch-zoom (two-finger drag, plus
  `InputEventMagnifyGesture`/`PanGesture` and mouse wheel on desktop), mesh
  point placement and dragging, manual triangle assignment (tap three
  points), a simple bone chain (drag to draw, drag a tip to rotate), a
  parameter slider list, and layer import via Godot's own `FileDialog`
  (native chrome on Windows/macOS/Linux, works with touch on Android/iOS).
- **`stretchy_export_target.gd`** — the cross-platform save decision:
  Android/iOS write straight to the app's Documents directory (no dialog to
  show); Windows/macOS/Linux get a starting directory and are expected to
  finish the save through a `FileDialog`, exactly what
  `_export_model3` above does; anything else falls back to `user://` and
  says so.
- **`stretchy_live2d_model3.gd`** — a full, faithful port of the reference's
  `model3json.js`. This is the one export format that's completely wired,
  end to end: build the document, press Export, get a real `.model3.json`
  in the right place for the OS it's running on.

## What's declared but not yet wired

The reference's export layer is, on its own, larger than everything else in
Stretchy Studio combined:

| File | Lines | Status |
|---|---|---|
| `motion3json.js` | 234 | not started |
| `moc3writer.js` | 921 | not started |
| `cmo3writer.js` | 4493 | not started |
| `can3writer.js` | 790 | not started |
| `textureAtlas.js` / `caffPacker.js` | 684 | not started |
| `bodyRig.js` / `deformerEmit.js` / `physics.js` / `faceParallax.js` | 1659 | math for the latter two already ported to C++ in Stage 169, not yet connected to an XML writer |

Each is its own multi-hundred-line binary or XML format with its own
correctness constraints; guessing at them without the reference's test
fixtures in front of me would produce files that open in nothing. They're
staged for the next rounds, in roughly that order (motion3 first — it's
JSON, same easy category as model3; moc3 next since cmo3 depends on
knowing its layout; cmo3 last because it's the biggest single piece).

## Validation

Checked for balanced parentheses/braces/brackets across all three new
files. `UiKit.slider_row`'s real signature (`min, max, value, step, suffix,
callback`) was checked against `ui/ui_kit.gd` rather than assumed. Nested
class (`_StretchyCanvas`) references to the outer class's enum and color
constants are fully qualified (`StretchyStudioStandalone.Tool.MESH`, etc.)
rather than left to GDScript's nested-class scoping, since that couldn't be
verified by actually running the engine here. No `godot-cpp`/Godot binary is
present in this sandbox, so — same as Stage 169 — none of this could be
compiled or run before delivery; it's been read through by hand instead.
