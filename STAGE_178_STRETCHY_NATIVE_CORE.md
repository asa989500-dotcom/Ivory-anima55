# Stage 178 — Stretchy Native C++ Core

The active Stretchy path now uses two registered native C++ services:

- `IvoryStretchyDocument` owns the default standalone document schema and the mesh, layer, armature, and parameter mutations.
- `IvoryStretchyExport` owns export-target selection and text/bytes file writing.

`stretchy_studio_standalone.gd` remains only the Godot Control/view bridge. It creates the native document when the extension is available, synchronizes the document after edits, and delegates export-target policy to the native exporter. `stretchy_export_target.gd` is now a compatibility bridge with no export policy of its own.

The existing `stretchy_studio_module.gd` and `stretchy_studio_room.gd` were not changed because they are legacy compatibility paths and are not used by the current `open_stretchy_studio()` entry point. The Stretchy extension boundary and project format remain unchanged.

A full native build cannot be claimed in this checkout because `godot-cpp`, Godot, and the native compiler are not vendored or installed. The project’s SCons file uses `Glob("src/*.cpp")`, so the new sources are included automatically when the extension is built in the target environment.
