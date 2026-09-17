# IVORY Stage 121 — audio import, and an MP4 export that survives length

## What was actually wrong

The build would not compile. The project's own checkers found it in seconds:

- `_wav_pcm_for_samples` was **declared twice** in `exporters.gd`. GDScript
  rejects a file that declares the same function twice.
- `_find_export_sound` was **called and never written**.
- `GoZenMP4Encoder` was reached by name, so on any device without the native
  library compiled the file failed to parse and the app did not open.
- `p.export_range` was written to from the settings panel and did not exist on
  `Project`.

So MP4 export was not weak. It was broken, and had been since stage 120.

## Sound: a real track, not a mouth

"Link a sound" is gone. In its place, on the same second tap on a layer in
the timeline, is **Import audio** / **استيراد صوت**.

It is for music and effects. It does not touch the drawing, it does not build
a mouth mesh, and it does not analyse speech. Those two jobs used to share one
button, and a button that sometimes redraws your artwork is not a button
anybody presses twice.

**Formats.** Over forty, through the native media layer: MP3, M4A, M4B, AAC,
FLAC, ALAC, OGG, Opus, WMA, AIFF, AMR, CAF, AC3, MP2, WavPack, Musepack, and
WAV in every shape a recorder writes — 8, 16, 24 and 32-bit integer, 32 and
64-bit float, and WAVE_FORMAT_EXTENSIBLE.

**Several at once.** The picker takes a multiple selection. A scene is a score
and eleven effects, not one file eleven times.

**Import is instant.** Nothing is decoded when a sound is added — the name and
the length are read and that is all. Preparing the samples happens once, on
the first export, and the result is cached and never repeated.

Each clip carries a start frame, a volume, a mute, and a fade at each end so a
clip cut mid-waveform does not click. Clips are listed under the layer they
were added from, so eight characters' worth of footsteps stay eight lists —
and they all mix as one scene at export.

**Playing.** Sounds are heard while the timeline plays, through Godot's own
audio server. WAV, MP3 and Ogg play immediately. Everything else is silent in
preview until it has been exported once, after which the prepared copy is
used. Scrubbing deliberately makes no sound.

New files: `audio_bank.gd` (formats, decoding, cache), `audio_track.gd` (the
model), `audio_mix.gd` (the export mixer), `audio_preview.gd` (playback),
`ui/timeline_audio.gd` (one clip's row).

## MP4: written for length

`exporters.gd` was past the length anybody reads in one sitting, so the whole
pipeline moved into `mp4_export.gd`.

- **The screen is handed back on a clock, not every frame.** It used to wait a
  whole display frame after every single frame encoded. On a sixty-thousand
  frame scene that is sixteen minutes of doing nothing. Now it waits when
  fourteen milliseconds have passed, so thirty frames get encoded between
  turns and the interface still never misses a beat.
- **The audio file is opened once.** It used to be opened, sought, read for a
  fortieth of a second and closed again — per frame. Ten minutes of video was
  fourteen thousand opens and closes.
- **Three buffer slots instead of two**, so the renderer and the encoder are
  both busy instead of taking turns.
- **Sample boundaries are integers**, so 24 fps at 48 kHz is exactly 2000
  samples every frame and never drifts a sample a minute into a sync problem.
- **Nothing is held.** One frame and one fortieth of a second of sound at a
  time, whatever the length.

## Sound quality

- 48 kHz stereo out of the mixer, always.
- Mixing is done in 32-bit floating point and clipped once at the end. Summing
  two loud tracks in 16-bit arithmetic wraps a peak round to the opposite sign
  and it is heard as a crack.
- Rate conversion is interpolated, not decimated. Dropped samples are the
  gritty sound that tells you an app did it cheaply.
- AAC now runs to **320 kbps** at Maximum quality. It was fixed at 128, which
  is audible on music — a cymbal turns to gauze.

## Picture quality

- x264 preset is now chosen by the quality setting instead of always being
  `veryfast`. Same CRF, slower preset, smaller file, same picture.
- `tune=animation` and two B-frames on every profile above baseline.
- Frames are resized with Lanczos, and an odd edge is cropped rather than
  stretched — stretching by one pixel softens the whole frame.
- CRF ladder retuned: Draft 28, Good 21, High 17, Maximum 13.

## Verification, made fair

Post-export verification was deleting good files. AAC carries an encoder delay
of about a thousand samples and pads its last block, so its stream is reliably
a few hundredths of a second longer than the picture — and the old check
failed on a difference of one sample. It is now strict about the things that
make a file wrong (codec, size, missing frames) and forgiving about the things
that are never exact.

## Export settings, in their own panel

`ExportPanel` (`ui/export_panel.gd`). Range (all / play range / chosen frames,
where 0 for the last frame means run to the end), size including 480p,
quality, sound with its own bitrate, and the advanced numbers underneath. It
also says roughly how many megabytes the file will be *before* it is written.

The one-of-a-row controls now compare against a stored value rather than the
button's own text, which had silently stopped working in every language but
English: "عالٍ" is not "High".

## Native (C++)

- `GoZenAudio::decode_to_wav()` — new. Decodes anything FFmpeg reads straight
  to a PCM16 WAV file, a packet at a time. `get_audio_data()` returns the whole
  track as one array, which for an hour of stereo is roughly 600 MB and is not
  memory Android will hand over.
- `GoZenMP4Encoder::open()` takes `preset` and `audio_kbps`. Both are
  optional, and `capabilities()` reports `tuned` so a freshly written app still
  runs against a library compiled before this change — the worker asks rather
  than assumes.
- AAC bitrate is no longer hard-coded.

Rebuild the `.so` for MP3 and the other compressed formats to decode. Without
it the app opens, plays and exports normally; WAV, MP3 and Ogg still preview,
and anything else says so plainly instead of failing.

## Checkers

`check_scope.py` had a real bug: it read a parameter list with a regex that
stopped at the first `)`, so a default value that is a call —
`progress: Callable = Callable()` — hid every parameter after it and reported
correct code as undeclared. It now counts brackets. A checker that cries wolf
is a checker that gets commented out.

All ten checks pass.
