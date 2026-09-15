# IVORY Stage 174 — Stretchy-first Animation Project Flow

## What changed

Pressing **New project → Animation** now opens a first-class animation workspace choice before any animation project settings:

1. **Ivory** → opens the existing Ivory animation creation form unchanged.
2. **Stretchy Studio** → opens a dedicated canvas-only chooser.

Choosing a Stretchy canvas immediately creates an Animation project, marks its workspace as `stretchy`, and opens the existing standalone Stretchy Studio room.

## Stretchy creation screen

Only the starting canvas is exposed here. FPS, frame count, paper colour, export controls and other authoring settings are not duplicated in the creation screen; the intent is for those settings to live inside Stretchy Studio.

The starting canvas list is supplied by the native C++ class `IvoryAnimationLauncher`.

## Native C++ core

Added:

- `native/ivory/src/ivory_animation_launcher.h`
- `native/ivory/src/ivory_animation_launcher.cpp`

Registered as `IvoryAnimationLauncher` and exposed through `scripts/native.gd`.

Native responsibilities:

- define the two valid animation workspaces (`ivory`, `stretchy`)
- provide the Stretchy starting canvas presets
- validate workspace ids
- provide the default FPS used at hand-off

GDScript is only the UI/bridge layer.

## Existing Stretchy Studio preserved

The existing `StretchyStudioStandalone` implementation, native Stretchy export/track classes, and the rest of IVORY's animation/rig systems were not removed.
