# IVORY Stage 123 — MediaCodec, and no FFmpeg on the phone

You were right, and this is now the main road. FFmpeg is still there for
desktop builds; on Android it is no longer needed for anything.

```
Godot  →  JNI  →  MediaCodec  →  MediaMuxer  →  MP4  →  MediaStore
```

## What this replaces

The FFmpeg route needed the NDK, five git submodules, a cross-compile per ABI,
and ended with several megabytes of encoder riding inside every APK — to do a
job the phone already has silicon for. Every Android device since 2014 has a
hardware H.264 encoder behind MediaCodec, and it is faster than libx264 will
ever be on a battery, because it is not software.

The new build needs the Android SDK and a JDK. Nothing else. No NDK, no
submodules, no cross-compiled C.

    export ANDROID_HOME=/path/to/Android/Sdk
    # In Godot: Project ▸ Install Android Build Template
    tools/build_android_plugin.sh

`export_presets.cfg` now has `use_gradle_build=true` and `plugins/IvoryMedia=true`,
so the export picks the plugin up on its own.

## Three plugins, in `android/plugin_src/`

**`IvoryMP4`** — H.264 and AAC. Frames go in as RGBA and come out muxed.

The awkward part, handled: MediaMuxer will not accept a track after it has
started, and a codec does not report its output format until it has encoded
something. With both video and audio there is a moment where one track is
producing packets and the other has not declared itself yet. Those packets are
held and written the instant the muxer starts — a handful of frames at most.
The alternatives were dropping the start of the sound or refusing audio.

Colour conversion uses `getInputImage()`, which hands back the planes in
whatever layout the particular chip wants — I420 on some, NV12 on others — with
strides filled in. That is the only way to feed a flexible colour format
without guessing per device. Chroma is sampled from one pixel per 2×2 block
rather than averaged over four: on photographic video that would show, on drawn
animation where a 2×2 block is nearly always one flat colour it does not, and it
is four times less arithmetic in a loop that runs for every pixel of every frame.

**`IvoryAudio`** — this is the part that surprised me in a good way. Android
already ships decoders for MP3, AAC, M4A, FLAC, Ogg Vorbis, Opus, AMR and WAV.
**So FFmpeg is not needed for audio import either.** Decoding is written
straight to the PCM cache as it goes, so an hour of stereo costs the same
memory as a second.

**`IvoryStore`** — MediaStore. An app's private folder is not somewhere a
person can reach: a video saved there plays inside IVORY and is invisible to
the gallery, the share sheet and every other app, which for somebody who has
just spent an evening on it is indistinguishable from the export having failed.
On Android 10+ MediaStore is also the only route, and it is why IVORY still
does not ask for `MANAGE_EXTERNAL_STORAGE` — the permission Play reviews by
hand and refuses to apps that do not need it. The file is marked pending while
it copies, so a half-written video never appears as a broken thumbnail.

## On the GDScript side

`MP4Direct` wears exactly the same shape as `MP4ExportWorker` — same methods,
same meanings — so `Mp4Export.save` picks one and never asks again which it
got. Two encoders behind one door is a door; two behind two doors is two export
pipelines that drift apart.

It is deliberately **not** on a worker thread. The thread exists for FFmpeg
because a software H.264 frame is tens of milliseconds. MediaCodec returns in
about two. A thread would buy nothing and cost the one thing that matters: JNI
from a thread Godot did not create must be attached to the Java VM by hand, and
getting that subtly wrong is the kind of fault that shows up on one make of
phone, six months later, as a crash nobody can reproduce.

**CRF is dropped rather than approximated.** MediaCodec has no constant-quality
mode — it takes a bitrate and nothing else. `Mp4Export.rate_for()` turns the
chosen CRF into a rate, doubling every six steps, which is the curve x264
follows. So Draft / Good / High / Maximum mean roughly the same film on a phone
as on a desktop, which matters more than either number being exactly right.

**Verification learned the difference between *not checked* and *failed*.** The
inspector is FFmpeg's, and an Android build no longer has one. `readable` is
now separate from `ok`: with nobody able to look, the file is checked for
existence and size and then trusted. Deleting a good film because nothing was
available to inspect it would be the worst possible outcome of a safety check.

## The panel says which one will run

Because it changes what to expect — the phone's own chip is several times
faster and does not warm the device — and because "no encoder in this build" is
something to learn before pressing export rather than after.

All ten checkers pass.
