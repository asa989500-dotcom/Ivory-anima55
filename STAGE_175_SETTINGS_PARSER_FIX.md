# IVORY Stage 175 — SettingsPanels parser fix

## Fixed

The previous Stage 174 project contained two invalid GDScript C-style ternary expressions in `scripts/ui/settings_panels.gd`:

- `Lang.current == Lang.L.AR ? ... : ...`
- the equivalent expression for the description

Godot GDScript 4 does not use the C/C++ `? :` ternary syntax. Those expressions caused the parser to fail while loading `SettingsPanels`, which then cascaded into the `main.gd` errors saying the `SettingsPanels` class could not be resolved.

## Correction

The expressions were replaced with normal GDScript `if` guards while preserving the exact English/Arabic fallback behavior:

1. Start with the default English title/description.
2. When the current language is Arabic, replace them with the Arabic values when available.

## Integrity

No Stretchy Studio code, project-flow logic, canvas presets, native C++ launcher, export/track code, or 2.5D-removal work was removed or altered by this repair.

## Validation performed

- Verified the two invalid `? :` expressions are gone from `settings_panels.gd`.
- Verified no remaining C-style ternary expressions exist in the project's GDScript source (the only match is inside a comment explaining that GDScript has no `cond ? a : b`).
- Verified all `SettingsPanels` call sites remain intact.
- Verified the `IvoryAnimationLauncher` C++ source/header remain present and registered.

A Godot executable is not available in this build environment, so an actual Godot editor parse/reload could not be executed here. The source-level parser issue shown in the provided screenshot has nevertheless been removed directly at its cause.
