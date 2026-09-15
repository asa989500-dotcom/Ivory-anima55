class_name LipSync
extends RefCounted
## Sound in, mouth shapes out.
##
## ## What this is, said plainly before anything else
##
## This is **not** speech recognition. Nothing here knows what word is being
## said, and nothing here could be taught to. It listens to how open the mouth
## must be and roughly where in the mouth the sound is being made, and picks
## the nearest of the nine shapes. That is what Papagayo's automatic mode does,
## and what every lip-sync tool did before machine transcription existed, and
## it is enough — because the animator is going to look at the result anyway,
## and correcting six frames in a sentence is a different job from keying two
## hundred by hand.
##
## Saying this out loud matters. A tool that claims to recognise speech and
## then produces a mouth that is merely *open at the right times* has lied to
## its user, who will spend an afternoon wondering what they did wrong. A tool
## that says "I heard loud and round here" is telling the truth, and the truth
## is genuinely useful.
##
## ## What it can actually hear
##
## Three things, and each maps onto something a mouth does:
##
## * **How loud** → how far open. Silence closes it. This is the single most
##   important signal and the most reliable: it is what makes speech look like
##   speech even when every shape is wrong.
## * **Where the energy sits in the spectrum** → open or round. A vowel made
##   at the front of the mouth with the lips spread — `ee` — puts its energy
##   high. One made at the back with the lips rounded — `oo` — puts it low.
##   That is the second formant doing exactly what it does, and it survives
##   this crude a measurement because the difference is enormous.
## * **How often the wave crosses zero** → hiss. `s`, `f`, `th` are noise
##   rather than tone, and noise crosses zero constantly while being quiet.
##   That combination is unmistakable and it is how consonants are found.
##
## ## What it cannot hear, and what happens instead
##
## `b`, `m` and `p` are *silence with the lips together*, and they are
## acoustically almost nothing — a tiny gap, then a burst. The gap is found;
## which of the three it was is not, and does not need to be, because all
## three are the same closed mouth. This is the one place where working on
## shapes instead of phonemes is an outright advantage.
##
## `l`, `r` and `k` are all mid-open and mid-spectrum and this will confuse
## them. They are the three the artist will correct, and they are also the
## three an audience is least likely to notice.
##
## ## Two things that were wrong, and are the reason this file was rewritten
##
## **It could not open the user's own files.** The reader asked
## `ResourceLoader` for the WAV. That works for a file sitting inside the
## project and for nothing else: a sound chosen from the phone's own music
## folder is not a resource, has never been imported, and comes back null. The
## error the user saw was "only WAV files can be read" — about a WAV file. The
## reader below opens the bytes with `FileAccess` and parses the RIFF itself,
## so any WAV anywhere on the device can be used, in every common form: eight,
## sixteen, twenty-four and thirty-two bit whole numbers, and thirty-two and
## sixty-four bit floating point, at any rate, in any number of channels.
##
## **It froze the app.** A three-minute take at twenty-four frames a second is
## four thousand three hundred frames, each of them wanting a dozen passes over
## a thousand samples. Done in one call that is the better part of a minute
## with the screen locked solid and no way to tell whether the app has died.
## The work is now a job that is stepped a few milliseconds at a time between
## drawn frames, with a number the user can watch.

## How much quieter than the loudest moment a frame has to be before it counts
## as silence. Chosen low: a held vowel at the end of a breath is much quieter
## than the middle of a shout, and closing the mouth on it would look like the
## character stopping mid-word.
const QUIET: float = 0.035

## Above this rate of zero crossings, and below `HISS_LOUD`, a frame is noise
## rather than tone — a hiss rather than a vowel.
const HISS_RATE: float = 0.22
const HISS_LOUD: float = 0.55

## The two regions the spectrum is measured in, in hertz.
##
## Not a full transform: an FFT per frame is dozens of times the work to tell
## us something we then round to one of nine answers. But not a handful of
## single frequencies either, and that distinction cost a rewrite.
##
## A Goertzel probe is *narrow*. Five lone probes left gaps between them wide
## enough for a whole formant to fall through — a vowel whose second formant
## sat at 2600 Hz, between probes at 2100 and 3100, registered as having
## almost no high energy at all and was classified as a rounded mouth. It is
## the opposite of what that vowel is.
##
## So each region is sampled at several nearby frequencies and summed, which
## makes it behave as a band rather than as a line. `LOW` covers where the
## first formant lives — how open the mouth is. `HIGH` covers the range the
## second formant moves through as the lips spread or round, sampled closely
## enough that nothing can fall between two probes.
const LOW_BAND: Array = [300.0, 450.0, 620.0, 820.0]
const HIGH_BAND: Array = [1350.0, 1700.0, 2050.0, 2400.0, 2750.0, 3150.0]

## How much of each frame is actually listened to, in seconds.
##
## Twenty-three milliseconds, centred in the frame. Speech is analysed in
## windows of about this length everywhere it is analysed at all, for a good
## reason: shorter and a low voice does not complete a cycle inside it, longer
## and two different sounds get averaged into one that was never said. Reading
## the whole frame instead would be nearly twice the work to blur the answer.
const WINDOW_SECONDS: float = 0.023

## The lowest rate the spectrum may be measured at.
##
## The highest probe is at 3150 Hz, so a shade under nine thousand is already
## comfortably clear of it. The window is box-averaged down to about this rate
## before the probes run — a cheap low pass that both quarters the arithmetic
## and keeps the hiss above it from folding down into the vowel bands.
const PROBE_RATE: float = 9000.0

## The biggest file worth opening, in bytes. Four hundred megabytes of WAV is
## about forty minutes of stereo — far past any line of dialogue, and past the
## point where holding the bytes is kind to a phone.
const MAX_BYTES: int = 400 * 1024 * 1024

# ------------------------------------------------------------------ reading

## Opens a WAV and works out how to read it, without reading it yet.
##
## RIFF is a list of chunks, and the two that matter are `fmt ` and `data`.
## They are walked rather than assumed to be in a fixed place, because plenty
## of encoders write `LIST`, `fact` or a metadata chunk between them, and a
## reader that assumes the data begins at byte 44 mangles every file written
## by those encoders.
static func open_wav(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "why": "unreadable"}
	var size: int = f.get_length()
	if size < 44 or size > MAX_BYTES:
		f.close()
		return {"ok": false, "why": "empty" if size < 44 else "too_big"}
	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		f.close()
		return {"ok": false, "why": "not_wav"}
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		f.close()
		return {"ok": false, "why": "not_wav"}

	var kind: int = 0
	var channels: int = 0
	var rate: int = 0
	var bits: int = 0
	var block: int = 0
	var data_at: int = -1
	var data_len: int = 0

	while f.get_position() + 8 <= size:
		var tag: String = f.get_buffer(4).get_string_from_ascii()
		var length: int = f.get_32()
		if length < 0:
			break
		var body: int = f.get_position()
		if tag == "fmt ":
			kind = f.get_16()
			channels = f.get_16()
			rate = f.get_32()
			f.get_32()                      # bytes a second, which we can work out
			block = f.get_16()
			bits = f.get_16()
			# WAVE_FORMAT_EXTENSIBLE hides the real format in a GUID whose
			# first two bytes are the plain format number. Without this, every
			# file written by a modern recorder reads as "unsupported".
			if kind == 0xFFFE and length >= 40:
				f.seek(body + 24)
				kind = f.get_16()
		elif tag == "data":
			data_at = body
			data_len = mini(length, size - body)
		# Chunks are padded to an even length, and a reader that forgets it
		# ends up one byte out and reading rubbish for every later chunk.
		f.seek(body + length + (length & 1))
		if data_at >= 0 and channels > 0:
			break

	f.close()
	if data_at < 0 or channels < 1 or rate < 1 or bits < 8:
		return {"ok": false, "why": "not_wav"}
	if kind != 1 and kind != 3:
		return {"ok": false, "why": "compressed"}
	if kind == 3 and bits != 32 and bits != 64:
		return {"ok": false, "why": "unsupported_format"}
	if kind == 1 and bits != 8 and bits != 16 and bits != 24 and bits != 32:
		return {"ok": false, "why": "unsupported_format"}
	if block < 1:
		block = int(float(bits) / 8.0) * channels
	var frames: int = floori(float(data_len) / float(maxi(block, 1)))
	if frames < 1:
		return {"ok": false, "why": "empty"}
	return {"ok": true, "at": data_at, "bytes": data_len, "frames": frames,
		"channels": channels, "rate": rate, "bits": bits, "block": block,
		"float": kind == 3}

## One sample, whatever shape it is stored in, as -1 to 1.
static func _sample_at(raw: PackedByteArray, at: int, bits: int,
		is_float: bool) -> float:
	if at < 0 or at + int(float(bits) / 8.0) > raw.size():
		return 0.0
	if is_float:
		if bits == 64:
			return clampf(raw.decode_double(at), -1.0, 1.0)
		return clampf(raw.decode_float(at), -1.0, 1.0)
	match bits:
		8:
			# Eight-bit WAV is unsigned, and every other depth is signed. It
			# is the one genuine irregularity in the format.
			return (float(raw.decode_u8(at)) - 128.0) / 128.0
		16:
			return float(raw.decode_s16(at)) / 32768.0
		24:
			var lo: int = raw.decode_u8(at)
			var mid: int = raw.decode_u8(at + 1)
			var hi: int = raw.decode_u8(at + 2)
			var v: int = lo | (mid << 8) | (hi << 16)
			if v >= 0x800000:
				v -= 0x1000000
			return float(v) / 8388608.0
		32:
			return float(raw.decode_s32(at)) / 2147483648.0
	return 0.0

# ---------------------------------------------------------------- listening

## The strength of one frequency in one stretch of samples.
##
## Goertzel's method: one frequency at a time, in a loop with two multiplies
## and no memory. Asking a full transform for ten numbers and throwing away
## the other five hundred is the kind of waste that shows up as heat on a
## tablet, and this is the textbook answer to wanting a few bins rather than
## all of them.
static func _at_frequency(samples: PackedFloat32Array, freq: float,
		rate: float) -> float:
	var count: int = samples.size()
	if count < 4 or rate < 1.0:
		return 0.0
	var w: float = TAU * freq / rate
	var coeff: float = 2.0 * cos(w)
	var s1: float = 0.0
	var s2: float = 0.0
	for i in count:
		var s0: float = samples[i] + coeff * s1 - s2
		s2 = s1
		s1 = s0
	var power: float = s1 * s1 + s2 * s2 - coeff * s1 * s2
	return sqrt(maxf(power, 0.0)) / float(count)

# ----------------------------------------------------------------- deciding

## One frame of sound as one mouth.
##
## Two axes, and only two, because two is what this can honestly measure.
##
##   **how open**    from loudness — the most reliable signal there is
##   **how round**   from the balance between the two bands
##
## Every one of the nine falls somewhere on that grid, and the grid is walked
## rather than a list of special cases being checked. Being explicit about the
## two axes is also being explicit about the limits: `l`, `r` and `k` are all
## mid-open and mid-round, so this will confuse them. They are the three an
## artist corrects, and the three an audience is least likely to notice.
static func _shape_for(loud: float, cross: float, front: float) -> int:
	if loud < QUIET:
		return Viseme.Mouth.SHUT
	# Noise rather than tone: quiet, and crossing zero constantly. `s`, `f`,
	# `th` and their neighbours, all of which show the teeth.
	if cross > HISS_RATE and loud < HISS_LOUD:
		return Viseme.Mouth.T

	var rounded: bool = front < 0.30
	var spread: bool = front > 0.62
	if loud > 0.62:
		if rounded:
			return Viseme.Mouth.O
		if spread:
			return Viseme.Mouth.E
		return Viseme.Mouth.A
	if loud > 0.30:
		if rounded:
			return Viseme.Mouth.R
		if spread:
			return Viseme.Mouth.E
		return Viseme.Mouth.K
	if rounded:
		return Viseme.Mouth.W
	if spread:
		return Viseme.Mouth.T
	return Viseme.Mouth.L

# --------------------------------------------------------------- the job

enum Phase { READ, HEAR, DECIDE, DONE, FAILED }

## Sets a track up to be read a piece at a time.
##
## Nothing heavy happens here: the header is parsed, the arithmetic is worked
## out, and the job is handed back for `advance` to grind through between
## drawn frames.
static func begin(path: String, fps: float) -> Dictionary:
	var head: Dictionary = open_wav(path)
	if not bool(head.get("ok", false)):
		return {"phase": Phase.FAILED, "why": String(head.get("why", "unreadable"))}
	if fps < 0.5:
		fps = 24.0

	var rate: int = int(head["rate"])
	var source_frames: int = int(head["frames"])
	var per_frame: float = float(rate) / fps
	var frames: int = maxi(int(ceil(float(source_frames) / per_frame)), 1)
	# The window is centred in each frame and never longer than the frame
	# itself — at two frames a second a frame is half a second long, and
	# listening to all of it would average a whole syllable into one answer.
	var window: int = clampi(int(round(float(rate) * WINDOW_SECONDS)), 32,
		maxi(int(per_frame), 32))
	# How many samples are folded into one before the probes run. Box
	# averaging is a crude low pass and exactly the right one here: it costs a
	# single addition per sample, and what it removes is the hiss that would
	# otherwise fold down into the bands the vowels are read from.
	var fold: int = maxi(int(floor(float(rate) / PROBE_RATE)), 1)

	return {
		"phase": Phase.READ,
		"path": path,
		"at": int(head["at"]),
		"bytes": int(head["bytes"]),
		"block": int(head["block"]),
		"channels": int(head["channels"]),
		"bits": int(head["bits"]),
		"float": bool(head["float"]),
		"rate": rate,
		"fps": fps,
		"source_frames": source_frames,
		"per_frame": per_frame,
		"window": window,
		"fold": fold,
		"frames": frames,
		"raw": PackedByteArray(),
		"read_at": 0,
		"heard_at": 0,
		"loud": PackedFloat32Array(),
		"cross": PackedFloat32Array(),
		"front": PackedFloat32Array(),
		"loudest": 0.0,
		"mouths": PackedInt32Array(),
		"power": PackedFloat32Array(),
		"why": "",
	}

## How far along, from 0 to 1.
static func progress(job: Dictionary) -> float:
	var phase: int = int(job.get("phase", Phase.FAILED))
	if phase == Phase.DONE:
		return 1.0
	if phase == Phase.READ:
		return 0.15 * float(job.get("read_at", 0)) \
			/ maxf(float(job.get("bytes", 1)), 1.0)
	if phase == Phase.HEAR:
		return 0.15 + 0.8 * float(job.get("heard_at", 0)) \
			/ maxf(float(job.get("frames", 1)), 1.0)
	return 0.97

## Does a slice of the work and comes back. True once there is nothing left.
##
## `budget_ms` is how long it may spend, and it is checked between whole units
## of work rather than inside them — a frame of sound half analysed is worse
## than useless, so the budget is a guide and never a guillotine.
static func advance(job: Dictionary, budget_ms: int = 8) -> bool:
	var phase: int = int(job.get("phase", Phase.FAILED))
	if phase == Phase.DONE or phase == Phase.FAILED:
		return true
	var until: int = Time.get_ticks_msec() + maxi(budget_ms, 1)

	if phase == Phase.READ:
		_read_slice(job, until)
		return false
	if phase == Phase.HEAR:
		_hear_slice(job, until)
		return false
	_decide(job)
	return true

## Pulls the sound off the disk in pieces.
##
## Held as raw bytes rather than decoded to floats. A minute of stereo at
## forty-four thousand is ten megabytes of WAV and twenty of floats, and the
## floats would be read exactly once — so the bytes are kept and each frame is
## decoded when it is listened to, which costs nothing extra and halves what
## the app is carrying.
static func _read_slice(job: Dictionary, until: int) -> void:
	var f: FileAccess = FileAccess.open(String(job["path"]), FileAccess.READ)
	if f == null:
		job["phase"] = Phase.FAILED
		job["why"] = "unreadable"
		return
	var raw: PackedByteArray = job["raw"]
	var read_at: int = int(job["read_at"])
	var total: int = int(job["bytes"])
	var chunk: int = 1 << 20
	f.seek(int(job["at"]) + read_at)
	while read_at < total:
		var want: int = mini(chunk, total - read_at)
		raw.append_array(f.get_buffer(want))
		read_at += want
		if Time.get_ticks_msec() >= until:
			break
	f.close()
	job["raw"] = raw
	job["read_at"] = read_at
	if read_at >= total:
		if raw.is_empty():
			job["phase"] = Phase.FAILED
			job["why"] = "empty"
			return
		job["phase"] = Phase.HEAR

## Listens to as many frames as the budget allows.
static func _hear_slice(job: Dictionary, until: int) -> void:
	var raw: PackedByteArray = job["raw"]
	var frames: int = int(job["frames"])
	var at: int = int(job["heard_at"])
	var block: int = int(job["block"])
	var channels: int = maxi(int(job["channels"]), 1)
	var bits: int = int(job["bits"])
	var is_float: bool = bool(job["float"])
	var rate: float = float(job["rate"])
	var per_frame: float = float(job["per_frame"])
	var window: int = int(job["window"])
	var fold: int = maxi(int(job["fold"]), 1)
	var source_frames: int = int(job["source_frames"])
	var step: int = int(float(bits) / 8.0)

	var loud: PackedFloat32Array = job["loud"]
	var cross: PackedFloat32Array = job["cross"]
	var front: PackedFloat32Array = job["front"]
	if loud.size() != frames:
		loud.resize(frames)
		cross.resize(frames)
		front.resize(frames)
	var loudest: float = float(job["loudest"])

	var window_buf: PackedFloat32Array = PackedFloat32Array()
	window_buf.resize(window)
	var folded: PackedFloat32Array = PackedFloat32Array()
	folded.resize(maxi(int(float(window) / float(fold)), 4))

	while at < frames:
		# Centred in the frame rather than started at it, so a sound is judged
		# by its middle instead of by the moment it begins — which on a
		# consonant is silence.
		var middle: int = int((float(at) + 0.5) * per_frame)
		var start: int = clampi(middle - int(float(window) / 2.0), 0,
			maxi(source_frames - window, 0))
		var have: int = mini(window, maxi(source_frames - start, 0))

		var sum_sq: float = 0.0
		var crossings: int = 0
		var was: float = 0.0
		for i in have:
			var base: int = (start + i) * block
			var total: float = 0.0
			for c in channels:
				total += _sample_at(raw, base + c * step, bits, is_float)
			var v: float = total / float(channels)
			window_buf[i] = v
			sum_sq += v * v
			if i > 0 and (v >= 0.0) != (was >= 0.0):
				crossings += 1
			was = v

		if have < 8:
			loud[at] = 0.0
			cross[at] = 0.0
			front[at] = 0.5
			at += 1
			continue

		# Folded down before the probes, which is both the low pass and the
		# reason this finishes in seconds rather than in a minute.
		var groups: int = maxi(int(float(have) / float(fold)), 4)
		if folded.size() != groups:
			folded.resize(groups)
		for g in groups:
			var total_g: float = 0.0
			for k in fold:
				var index: int = g * fold + k
				total_g += window_buf[index] if index < have else 0.0
			folded[g] = total_g / float(fold)
		var probe_rate: float = rate / float(fold)

		var low: float = 0.0
		for hz in LOW_BAND:
			low += _at_frequency(folded, float(hz), probe_rate)
		low = maxf(low / float(LOW_BAND.size()), 0.000001)
		var high: float = 0.0
		for hz in HIGH_BAND:
			high += _at_frequency(folded, float(hz), probe_rate)
		high = maxf(high / float(HIGH_BAND.size()), 0.000001)

		var here: float = sqrt(sum_sq / float(have))
		loud[at] = here
		loudest = maxf(loudest, here)
		cross[at] = float(crossings) / float(have)
		# Measured as a *log* ratio between the bands, not a plain fraction.
		#
		# A plain fraction looked reasonable and was useless: across a set of
		# test vowels it produced 0.013 for a rounded one and 0.055 for a
		# spread one — a real fourfold difference squeezed into four
		# hundredths, where no threshold can separate them without also
		# separating things that are the same. Formant relationships are
		# ratios of frequencies and behave logarithmically; measuring them
		# that way turns those same four vowels into 0.05, 0.38, 0.70 and
		# 0.87, which is a scale a threshold can live on.
		front[at] = clampf((log(high / low) + 4.6) / 4.6, 0.0, 1.0)

		at += 1
		if Time.get_ticks_msec() >= until:
			break

	job["heard_at"] = at
	job["loud"] = loud
	job["cross"] = cross
	job["front"] = front
	job["loudest"] = loudest
	if at >= frames:
		job["phase"] = Phase.DECIDE

## Turns what was heard into mouths.
##
## The loudness scale is taken from **this recording**, not from an absolute
## level. A line recorded quietly should still open the mouth all the way on
## its loudest syllable; measuring against a fixed threshold would leave a
## soft performance mumbling and a loud one shouting throughout.
##
## The spectral balance is deliberately *not* scaled that way, and that
## distinction cost a rewrite. Scaling each band against its own maximum
## across the track looks symmetrical and is destructive: on a line spoken in
## one steady vowel both maxima come from that vowel, both ratios become one,
## and every frame reports a perfectly balanced spectrum. The classifier then
## answers `A` for the whole track — an open mouth flapping through a
## sentence, which is what this file exists to avoid. A ratio has no scale to
## normalise, and normalising it removes the only thing it was carrying.
static func _decide(job: Dictionary) -> void:
	var frames: int = int(job["frames"])
	var loud: PackedFloat32Array = job["loud"]
	var cross: PackedFloat32Array = job["cross"]
	var front: PackedFloat32Array = job["front"]
	var loudest: float = maxf(float(job["loudest"]), 0.000001)

	var mouths: PackedInt32Array = PackedInt32Array()
	var power: PackedFloat32Array = PackedFloat32Array()
	mouths.resize(frames)
	power.resize(frames)
	for f in frames:
		var level: float = clampf(loud[f] / loudest, 0.0, 1.0)
		mouths[f] = _shape_for(level, cross[f], front[f])
		# How hard the shape is held, kept alongside which shape it is.
		#
		# Nine poses played at full strength is a puppet: every `A` in a line
		# is the widest `A` the mouth can make, whether it is a shout or the
		# tail of a word. Carrying the level lets the same nine shapes be
		# spoken softly or firmly, which is most of the difference between
		# lip sync that reads as acting and lip sync that reads as machinery.
		#
		# The root rather than the level itself: loudness is measured as
		# energy and heard as something much flatter, so a syllable at a
		# quarter the energy is nothing like a quarter as open.
		power[f] = sqrt(level)

	mouths = Viseme.denoise(mouths)
	mouths = Viseme.settle(mouths)
	job["mouths"] = mouths
	job["power"] = power
	job["seconds"] = float(job["source_frames"]) / maxf(float(job["rate"]), 1.0)
	job["phase"] = Phase.DONE
	# The bytes are the largest thing here by far and nothing needs them once
	# the mouths exist. Dropped rather than left to sit in memory for as long
	# as somebody keeps the report.
	job["raw"] = PackedByteArray()

## The whole job in one call, for a short file or a test.
##
## Everything the app itself does goes through `begin` and `advance`; this is
## here because a function that cannot be called plainly is a function that
## cannot be checked plainly.
static func from_file(path: String, fps: float) -> Dictionary:
	var job: Dictionary = begin(path, fps)
	var guard: int = 0
	while not advance(job, 1000) and guard < 100000:
		guard += 1
	if int(job.get("phase", Phase.FAILED)) != Phase.DONE:
		return {"ok": false, "why": String(job.get("why", "unreadable"))}
	return {"ok": true, "mouths": job["mouths"], "power": job["power"],
		"frames": (job["mouths"] as PackedInt32Array).size(),
		"seconds": float(job.get("seconds", 0.0))}

## Why a file could not be used, in words the user can do something with.
static func trouble_words(why: String) -> String:
	match why:
		"not_wav":
			return UiKit.label_for(
				"That is not a WAV file. Convert the sound to WAV and try again.",
				"هذا ليس ملف WAV. حوّل الصوت إلى WAV وأعد المحاولة.")
		"compressed":
			return UiKit.label_for(
				"This WAV is compressed. Save it again as plain PCM WAV.",
				"ملف WAV هذا مضغوط. احفظه مرة أخرى كـ WAV عادي غير مضغوط.")
		"unsupported_format":
			return UiKit.label_for(
				"This WAV is stored in a way the app cannot read. Save it as 16-bit WAV.",
				"ملف WAV هذا مخزَّن بطريقة لا يقرؤها التطبيق. احفظه بصيغة WAV ١٦ بت.")
		"too_big":
			return UiKit.label_for("That sound file is too long.",
				"ملف الصوت هذا أطول من اللازم.")
		"unreadable":
			return UiKit.label_for(
				"That file could not be opened. It may be somewhere the app is not allowed to read.",
				"تعذّر فتح هذا الملف. قد يكون في مكان لا يُسمح للتطبيق بالقراءة منه.")
		"empty", "nothing_heard":
			return UiKit.label_for("There is no sound in that file.",
				"لا يوجد صوت في هذا الملف.")
		_:
			return UiKit.label_for("That file could not be read.",
				"تعذّرت قراءة هذا الملف.")
