# Stage 150 native build

## Source-checkout mode
The active project intentionally has no `.gdextension` library manifests, so
Godot will not emit `dlopen ... .so not found` errors while the C++ artifacts
are absent. The original manifests are preserved as:

- `ivory.gdextension.disabled.sourcecheck`
- `addons/gde_gozen/gozen.gdextension.disabled`

## Release mode
After compiling the real ARM64 native libraries, restore the appropriate
manifest (`.disabled` -> `.gdextension`) and place the matching `.so` under the
paths named by that manifest.

Do not rename a source file to `.so`, and do not ship a placeholder binary:
Godot must load a genuine GDExtension built for the exact Godot ABI,
architecture, and build type.
