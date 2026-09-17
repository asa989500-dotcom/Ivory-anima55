# Stage 156 — media/export/import/rig pass

## Video export
- `GoZenMP4Encoder` is now a capability-driven FFmpeg video writer rather than an MP4-only H.264 writer.
- Containers exposed to the project are MP4, MOV, MKV and WebM.
- Video codecs are H.264, HEVC, VP9 and AV1 when the linked FFmpeg build exposes them.
- AAC is used for MP4/MOV/MKV; Opus is used for WebM.
- MP4/H.264 keeps the Android MediaCodec path; other formats use the native FFmpeg worker and are refused before encoding when the codec is absent.
- The RGBA-to-YUV conversion uses `SWS_FAST_BILINEAR` for export throughput; quality is controlled by the encoder itself.
- Post-write stream inspection remains in place and now checks the requested codec.

## Image import
- `GoZenImageImport` decodes still-image input through FFmpeg on the CPU and returns bounded RGBA data.
- The GDScript import path prefers this native decoder and falls back to Godot's `Image.load`.
- Large source files are resized on CPU before `ImageTexture` creation, so the source image is not uploaded to the GPU at full size.
- Repeated imports of the same path are cached for the active app session.
- The normal image picker accepts a wider range of common raster formats; Character 360 / 2.5D reference plates remain PNG-only by design.

## Rig / puppet
- The existing `RigSkin` path remains the universal layer deformation path: layer pixels are raster data, so imported PNG/JPEG/WebP/etc. can be skinned without format-specific bone code.
- Puppet Warp continues to operate on the decoded `Image` and its mesh, so the same imported image classes can be warped.
- Character 360 remains PNG-only at its reference-plate boundary.

## Build note
- The repository's built-in C++/GDScript static checks pass.
- The supplied archive does not include `native/gde_gozen/godot_cpp`, so a full GoZen linker build could not be performed inside this checkout. The GoZen sources were kept source-compatible with the existing FFmpeg/Godot binding style, but a real platform build should still compile the extension before shipping.
