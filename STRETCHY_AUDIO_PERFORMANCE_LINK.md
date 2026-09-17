# Stretchy Audio Track + Performance Track

This stage adds the C++ track document used by Stretchy export.

- `audio_track`: source, time range, gain and enabled state.
- `performance_track`: frame timing metrics and dropped-frame accounting.
- `mp4_export`: explicit handoff metadata for the existing IVORY MP4 exporter: MP4/AAC, 48 kHz, stereo, and verification required.
- `IvoryStretchyExport::build_track_document()` exposes the document to Godot.
- `export_json_bundle()` writes `stretchy_tracks.json` beside the existing model/CDI/motion artifacts.

The performance track is diagnostic/export metadata; it is not encoded as fake video or audio content.
