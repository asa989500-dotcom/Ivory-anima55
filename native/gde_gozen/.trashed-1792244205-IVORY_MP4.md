# IVORY MP4 export — H.264/AAC

Stage 118+ uses the GoZen/FFmpeg source as the native media layer. The exporter is streaming: one RGBA frame enters the encoder and is released before the next frame is rendered.

## Video
- H.264/AVC in an MP4 container.
- Android prefers `h264_mediacodec` (hardware MediaCodec); desktop builds may use `libx264` if present.
- CRF 10–40 is supported for x264; a positive bitrate overrides CRF.
- Resolution presets: Source, 720p, 1080p, 1440p and 4K.
- H.264 profiles: baseline, main, high.

## Audio
The scene now carries a real audio track (`AudioTrack`, on `Anim.Clip`), so the AAC stream is fed for real.

- `AudioMix` opens every unmuted clip once, keeps the file handles open for the whole export, and answers `read(first_sample, count)` with the mix of everything sounding at that moment.
- Mixing is 32-bit float, clipped once at the end; rate conversion is interpolated.
- Output is always 48 kHz stereo, and `open()` takes an AAC bitrate up to 512 kbps (192 by default, 320 at Maximum quality).
- `GoZenAudio::decode_to_wav(source, out, rate, channels)` decodes any FFmpeg-readable format straight to a PCM16 WAV file without holding the track in memory. This is what makes MP3/M4A/FLAC import possible at feature length on a phone.

`open()` gained two optional parameters, `preset` and `audio_kbps`. `capabilities()` reports `tuned = true` when they are present, and the GDScript worker checks that before using the wider call, so a newer app still runs against an older `.so`.

## Android FFmpeg build
The Android builder now enables JNI, MediaCodec, H.264 MediaCodec encoding, AAC encoding, the MP4 muxer and the file protocol. Build the GoZen submodules with the project's normal builder and copy the resulting Android `.so` into `addons/gde_gozen/bin/`.

## Cancellation/progress
The GDScript exporter uses a one-frame producer/consumer worker. Rendering remains on Godot's main thread (required by the existing canvas/timeline state), while native encoding runs on a dedicated thread. The UI gets a turn between frames, reports frame progress and can cancel; cancellation closes and removes the partial MP4.
