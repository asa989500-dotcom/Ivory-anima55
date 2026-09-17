# IVORY Stage 132 patch

Implemented in this patch:
- Removed the GDScript warning caused by the local `sign` name.
- Removed the unused `host` warning from the canvas-size popup.
- Enlarged floating settings/tool panels and increased their safe viewport height.
- Enlarged the canvas-size chooser so dimensions and presets are readable.
- Added a precise canvas colour picker to project creation using the existing square/ring colour control, with HEX input and HSV readout.
- Added a C++ canvas technical profile for tile size, estimated working memory, undo recommendation and safe dimensions.
- Fixed comic panel overlay coordinates so panels stay locked to the active page/canvas through zoom, pan and page offsets instead of appearing to float.
- Made bone dragging steadier by using a more stable native one-euro touch profile for joint controls.
- Kept the existing GDScript behaviour as fallback when the C++ extension is not built.

Validation:
- tools/check_warnings.py: 0 warnings
- tools/check_shadow.py: 0 redeclarations

Note:
- The Android/Linux/Windows native library is not rebuilt here because this archive does not contain the godot-cpp dependency or a compiler toolchain. The C++ source is updated and remains optional through ivory.gdextension.
