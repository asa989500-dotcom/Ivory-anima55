# IVORY Stage 176 — Fixed Animation Workspace Choice

- The first screen after `New Project -> Animation` is now a fixed, non-scrollable `PanelContainer`.
- It renders exactly two vertically stacked choices, in this order: `Ivory`, `Stretchy Studio`.
- Descriptions and the inherited scrolling settings-column were removed from this decision screen so the two buttons cannot fall below the viewport.
- The C++ `IvoryAnimationLauncher` remains the source of truth and now exposes `workspace_mode_count()`; the GDScript UI validates both the native count and the native IDs before rendering.
- Stretchy creation still forwards to `open_stretchy_project_canvas_choice()`; Ivory still forwards to `new_animation_ivory`.
- No Stretchy Studio, canvas presets, export, audio, performance, bone, puppet-warp, or Character360 code was removed.

## Validation performed

1. Confirmed the animation-choice block contains no `ScrollContainer`/`UiKit.scroller` usage.
2. Confirmed the native workspace order is `ivory`, then `stretchy`.
3. Confirmed both buttons are created from the native launcher data and are vertically stacked in one `VBoxContainer`.
4. Confirmed native C++ workspace count is explicitly fixed at 2.
5. Confirmed the previous navigation targets remain unchanged.

Godot itself is not installed in this execution environment, so an editor/runtime parser reload could not be run here.
