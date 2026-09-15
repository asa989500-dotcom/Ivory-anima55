class_name AudioMix
extends RefCounted
## Lays every sound in a scene over every other, a slice at a time.
##
## This is what an export asks for sound. It is built once at the start of an
## export and torn down at the end, and in between it answers one question
## over and over: *what does this scene sound like from sample A to sample B?*
##
## Everything about it is shaped by the length of the thing it has to survive.
##
## **Files stay open.** The exporter used to open the sound file, seek, read a
## fortieth of a second, and close it again — for every frame. Ten minutes of
## video is fourteen thousand opens. They are opened once here and closed at
## the end, and that alone is most of the reason a long export is now quick.
##
## **Nothing is held whole.** A slice is read from the disk, mixed, and let
## go. Twenty tracks over an hour cost the same memory as one track over a
## second, which is a few kilobytes.
##
## **Mixing is done in 32 bits and clipped once at the end.** Adding two loud
## tracks in 16-bit arithmetic wraps a peak round to the opposite sign, which
## is heard as a crack. Held wide and clamped at the last step, a peak is only
## ever a peak.
##
## **Rates are converted properly.** A 44.1 kHz song in a 48 kHz export is
## resampled with interpolation, not by dropping samples. Dropped samples are
## the gritty, slightly metallic sound that tells you an app did it cheaply.

## What the mixer hands to the encoder. 48 kHz stereo, always, whatever went
## in: it is what AAC is happiest with, it is what every phone plays back at,
## and one fixed rate means the encoder is opened once and never reconfigured.
const RATE: int = 48000
const CHANNELS: int = 2

## How loud the mix may get before it is held back.
##
## Slightly under full scale, so a sum that lands exactly on the ceiling still
## has somewhere to go and does not sit flat against it for a whole note.
const HEADROOM: float = 0.985

class Voice:
	var reader: FileAccess = null
	var at: int = 0
	var block: int = 0
	var rate: int = 44100
	var channels: int = 2
	var frames: int = 0
	## Where this voice begins in the finished mix, in output samples.
	var begins: int = 0
	## Where it stops, in output samples.
	var ends: int = 0
	## The first source sample to use, from the clip's trim.
	var skip: int = 0
	var gain: float = 1.0
	var fade_in: int = 0
	var fade_out: int = 0

	func close() -> void:
		if reader != null:
			reader.close()
			reader = null

var voices: Array = []
var trouble: String = ""

# ----------------------------------------------------------------- opening

## Opens every clip that will be heard, and works out where each one lands.
##
## `time_of` is passed in rather than the timeline itself, because the frame
## a clip starts on is not the same as the second it starts on: a scene with
## frame-rate units in it stretches time in place, and a sound placed on
## frame 200 has to arrive when frame 200 arrives, not two hundred
## twenty-fourths of a second in.
static func open(track: AudioTrack, time_of: Callable, from_frame: int,
		to_frame: int, seconds: float) -> AudioMix:
	var mix: AudioMix = AudioMix.new()
	if track == null:
		return mix
	var start_at: float = 0.0
	if time_of.is_valid():
		start_at = float(time_of.call(from_frame))
	var total: int = maxi(int(round(seconds * float(RATE))), 0)
	for c in track.live_clips():
		var one: AudioTrack.Clip = c as AudioTrack.Clip
		if one.start_frame > to_frame:
			continue
		var source: Dictionary = AudioBank.source_for(one.path)
		if not bool(source.get("ok", false)):
			# One unreadable file is not a reason to export in silence. It is
			# noted, the rest of the scene is mixed, and the exporter says so.
			mix.trouble = AudioBank.trouble_words(String(source.get("why", "")))
			continue
		var voice: Voice = Voice.new()
		voice.reader = FileAccess.open(String(source["pcm"]), FileAccess.READ)
		if voice.reader == null:
			continue
		voice.at = int(source["at"])
		voice.block = int(source["block"])
		voice.rate = maxi(int(source["rate"]), 1)
		voice.channels = clampi(int(source["channels"]), 1, 2)
		voice.frames = int(source["frames"])
		voice.gain = clampf(one.gain, 0.0, 4.0)
		voice.skip = clampi(int(round(one.skip * float(voice.rate))), 0,
			voice.frames)

		var begins_at: float = 0.0
		if time_of.is_valid():
			begins_at = float(time_of.call(one.start_frame)) - start_at
		voice.begins = int(round(begins_at * float(RATE)))
		var runs: float = float(voice.frames - voice.skip) / float(voice.rate)
		if one.span > 0.0:
			runs = minf(runs, one.span)
		voice.ends = voice.begins + int(round(runs * float(RATE)))
		if total > 0:
			voice.ends = mini(voice.ends, total)
		if voice.ends <= 0 or (total > 0 and voice.begins >= total):
			voice.close()
			continue
		voice.fade_in = maxi(int(round(one.fade_in * float(RATE))), 0)
		voice.fade_out = maxi(int(round(one.fade_out * float(RATE))), 0)
		mix.voices.append(voice)
	return mix

func close() -> void:
	for v in voices:
		(v as Voice).close()
	voices.clear()

func silent() -> bool:
	return voices.is_empty()

# ------------------------------------------------------------------ mixing

## The scene between two output samples, as interleaved PCM16.
##
## Always exactly `count` samples long, padded with silence wherever nothing
## is playing — a video whose audio stream is shorter than its picture is a
## video that some players will cut short, and every gap in a scene is a
## place where that would otherwise happen.
func read(first: int, count: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	if count <= 0:
		return out
	out.resize(count * CHANNELS * 2)
	if voices.is_empty():
		return out
	var last: int = first + count
	# Held wide while the sums are made. Sixteen bits is the shape of the
	# answer, not the shape of the working.
	var left: PackedFloat32Array = PackedFloat32Array()
	var right: PackedFloat32Array = PackedFloat32Array()
	left.resize(count)
	right.resize(count)

	for v in voices:
		var voice: Voice = v as Voice
		if voice.reader == null or voice.ends <= first or voice.begins >= last:
			continue
		_lay_in(voice, left, right, first, count)

	for i in count:
		var l: float = clampf(left[i], -HEADROOM, HEADROOM)
		var r: float = clampf(right[i], -HEADROOM, HEADROOM)
		out.encode_s16(i * 4, int(l * 32767.0))
		out.encode_s16(i * 4 + 2, int(r * 32767.0))
	return out

## One voice's share of one slice.
##
## The source is read as a single run of samples covering the whole slice,
## rather than a seek per sample: a seek per sample is a hundred thousand
## seeks a minute and it is the reason the old exporter crawled.
func _lay_in(voice: Voice, left: PackedFloat32Array,
		right: PackedFloat32Array, first: int, count: int) -> void:
	var step: float = float(voice.rate) / float(RATE)
	var lo: int = maxi(first, voice.begins)
	var hi: int = mini(first + count, voice.ends)
	if hi <= lo:
		return
	# Which source samples this slice needs, with one either side so the
	# interpolation at each edge has something to reach for.
	var from_source: int = voice.skip \
		+ int(floor(float(lo - voice.begins) * step))
	var to_source: int = voice.skip \
		+ int(ceil(float(hi - voice.begins) * step)) + 2
	from_source = clampi(from_source, 0, voice.frames)
	to_source = clampi(to_source, from_source, voice.frames)
	var want: int = to_source - from_source
	if want <= 0:
		return
	voice.reader.seek(voice.at + from_source * voice.block)
	var raw: PackedByteArray = voice.reader.get_buffer(want * voice.block)
	var got: int = floori(float(raw.size()) / float(maxi(voice.block, 1)))
	if got <= 0:
		return

	for i in range(lo, hi):
		var here: float = float(i - voice.begins) * step \
			+ float(voice.skip - from_source)
		var a: int = int(floor(here))
		if a < 0 or a >= got:
			continue
		var b: int = mini(a + 1, got - 1)
		var t: float = here - float(a)
		var loud: float = voice.gain * _fade(voice, i)
		if loud <= 0.0:
			continue
		var l0: float = float(raw.decode_s16(a * voice.block)) / 32768.0
		var l1: float = float(raw.decode_s16(b * voice.block)) / 32768.0
		var l: float = l0 + (l1 - l0) * t
		var r: float = l
		if voice.channels > 1:
			var r0: float = float(raw.decode_s16(a * voice.block + 2)) / 32768.0
			var r1: float = float(raw.decode_s16(b * voice.block + 2)) / 32768.0
			r = r0 + (r1 - r0) * t
		var at: int = i - first
		left[at] = left[at] + l * loud
		right[at] = right[at] + r * loud

## How loud this voice is at one output sample, counting both fades.
func _fade(voice: Voice, at: int) -> float:
	var loud: float = 1.0
	if voice.fade_in > 0:
		var into: int = at - voice.begins
		if into < voice.fade_in:
			loud *= clampf(float(into) / float(voice.fade_in), 0.0, 1.0)
	if voice.fade_out > 0:
		var left_of_it: int = voice.ends - at
		if left_of_it < voice.fade_out:
			loud *= clampf(float(left_of_it) / float(voice.fade_out), 0.0, 1.0)
	return loud
