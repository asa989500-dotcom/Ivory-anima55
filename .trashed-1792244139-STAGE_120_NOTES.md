# IVORY Stage 120 — MP4 export pipeline hardening

The MP4 path now follows a layered pipeline:

Timeline -> frame selection -> render frame -> bounded worker bridge -> H.264/AAC -> MP4 muxer.

Key changes:
- Timeline time is converted to output-frame time using `time_of()` and binary search, avoiding per-cel rounding drift and preserving holds/twos.
- Audio sample boundaries are derived from exact output-frame time. Missing tail audio is padded with silence; extra source audio is trimmed.
- Native encoder tries Android `h264_mediacodec` first and automatically falls back to software H.264 if it cannot open.
- Native encoder exposes the selected encoder, capabilities and detailed errors.
- MP4 is written to `.tmp`, verified, then atomically renamed to `.mp4`.
- `+faststart` is requested from the MP4 muxer.
- Post-export verification checks H.264, dimensions, video duration and AAC/audio duration against the timeline.
- The worker uses a bounded one-frame producer/consumer bridge and reusable native AVFrame buffers; it never retains the animation's frame list.
- Quality presets Draft/Good/High/Maximum are available, with Advanced CRF/bitrate controls.
- Export range start/end is persisted per project.
- Cancel removes the temporary file and never presents it as a successful export.

Android note: hardware H.264 is used only when the FFmpeg build contains and successfully opens `h264_mediacodec`. Otherwise the software H.264 encoder is selected. A final Android `.so` still requires the project's Android NDK/FFmpeg build environment.
