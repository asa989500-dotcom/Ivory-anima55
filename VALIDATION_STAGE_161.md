# Stage 161 validation report

## Implemented

- A shared image-loader path (`ImageImport.load_path`) now fronts both ordinary image import and the 2.5D PNG intake.
- Native C++ `IvoryImageIntake::load_file()` performs header-first dimension probing, rejects decoded sizes above the safety ceiling before image decode, decodes once, converts to RGBA8 once, and downsizes to a 4096-pixel side maximum.
- Import remains centered on the active project page through the existing floating-image path.
- The Compass label is now `2.5D` and opens `Character360Builder` directly.
- The old blue B-Spline grid room is no longer used for the user-facing 2.5D action.
- The old B-Spline control bar no longer constructs Pose / Rest pose / Clear rig / Application controls.
- Added a Godot test case covering the shared loader, RGBA8 output, timing evidence, the 2.5D direct-entry contract, and retirement of the old buttons.

## Safety boundary

The C++ loader probes only a small file header before decoding. Known PNG/JPEG/WebP/BMP/TGA raster headers are dimension-checked first. A probed raster larger than 32 megapixels is refused before `Image.load()` can allocate the decoded frame. The native decoded result is capped to 4096 pixels per side.

## Verification status

The source changes and project wiring were statically inspected in the supplied project. A Godot/Android runtime build could not be executed in this environment because the supplied project does not contain its compiled `bin/libivory*` extension and the Godot executable/toolchain are not installed here. The ZIP therefore contains the source-level fix and tests, not a newly compiled Android binary.
