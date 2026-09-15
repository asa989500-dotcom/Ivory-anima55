# Stretchy Studio -> IVORY C++ port status

This stage moves the verified small Live2D generators into the native C++ boundary and keeps the existing Stretchy UI/layout unchanged.

Ported from the reference source:
- model3json.js -> IvoryStretchyExport::model3_json
- cdi3json.js -> IvoryStretchyExport::cdi3_json
- motion3json.js -> IvoryStretchyExport::motion3_json, including segment encoding and mesh_verts index curves

The existing native jiggle and face-parallax classes remain available from the previous stage.

Not falsely replaced:
- moc3writer.js
- cmo3writer.js
- can3writer.js
- textureAtlas.js runtime image packing
- caffPacker.js as the binary container used by the full cmo3/can3 pipeline

Those reference writers are large binary-format implementations. This stage deliberately does not emit fake or guessed binaries.

The existing Export UI location is preserved. When the native exporter exists, the existing Export action writes the native JSON bundle; without the extension it falls back to the previous GDScript model3 exporter.

A full Godot/Android build is not claimed in this sandbox because the project's godot-cpp checkout/toolchain is not installed.
