# Stretchy Studio Integration

The integration now has a dedicated room in `scripts/stretchy_studio_room.gd`. The room owns Stretchy document state, Smart Bone dials, angle keys, Catmull–Rom interpolation settings, layer metadata, brush settings, Stretchy timeline tracks, physics flags, and `.stretchy` project serialization.

The room is opened from the Compass for **animation projects only**. It is not the IVORY room and it does not mount the regular IVORY timeline or a second IVORY panel. `MainRoom` only owns the room lifetime and the narrow bridge to the existing canvas and Android-safe image importer.

| Responsibility | Owner |
|---|---|
| Stretchy armature, dials, angle keys, and settings | `StretchyStudioRoom` plus `IvorySmartBone` when the C++ extension is loaded |
| Stretchy layer metadata and selected source layer | `StretchyStudioRoom` |
| Stretchy timeline track data | `StretchyStudioRoom` |
| Drawing surface and touch routing | Existing `CanvasView` |
| Applying the selected layer to the canvas | Existing IVORY layer stack through the bridge |
| Android image selection and decoding | Existing `ImageImport` path, including Android permissions and content decoding |
| Final APK packaging | Existing Godot Android preset in `export_presets.cfg` |

The Smart Bone bridge rebuilds the native C++ dial object from the Stretchy room document. It preserves angle-keyed corrections, Catmull–Rom weights, overshoot control, bone turns, bone stretches, point offsets, and native project serialization. If the native GDExtension is not loaded, the room still records the dial data and the existing IVORY bone paths remain available; live native corrections require building the extension.

The **Import image** action delegates to IVORY’s `ImageImport.ask_for_image`. This is intentional on Android: the existing path handles the platform file picker, image decoding, premultiplication, size limits, and placement on the selected canvas layer. The room does not create a second image importer.

The **Export Android** action writes an Android-ready `.stretchy` project bundle into the app’s `user://stretchy_exports` directory. It does not build an APK from inside the running application. APK packaging continues to use the Godot Android preset:

```text
godot --headless --path . --export-release "Android" build/IVORY.apk
```

The supplied Stretchy Studio ZIP remains a separate React/JavaScript reference application. Its JavaScript canvas and timeline are not copied into the Godot runtime because that would create duplicate canvas, touch, and timeline owners. The Godot room is the native integration boundary, while the existing IVORY canvas and Android export pipeline remain the platform owners.

## Validation

The modified GDScript files were checked for balanced delimiters and the output archive was checked with `unzip -t`. A full Godot runtime or Android APK build cannot be claimed in this sandbox because the Godot executable and Android build toolchain are not installed here.
