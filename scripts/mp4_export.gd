class_name Mp4Export
extends RefCounted
## MP4 export: H.264 picture, AAC sound, written straight to a file.
##
## Lifted out of `exporters.gd`, which had grown past the length anybody
## reads in one sitting. It is also the right seam: every other export in
## this app is one function that returns a file, and this one is a pipeline
## with a worker thread, an audio mixer and a verification pass behind it.
##
# The pipeline, end to end:
#
#   timeline frame -> output frame -> rendered image -> worker thread
#                                  -> H.264 ------------------------\
#   scene sounds  -> AudioMix slice -> PCM16 -> AAC ----------------> MP4
#
# Everything here is written for length. A scene that runs for an hour is
# eighty-six thousand frames and three hundred megabytes of sound, and the
# only way to survive that is to never hold more than one frame and one
# fortieth of a second of audio at a time. Nothing in this section keeps a
# list of anything.

static var cancel_requested: bool = false
static var exporting: bool = false
static var last_error: String = ""
## Something worth saying that did not stop the export — a sound file that
## had been moved, say. The file is still written; the sentence is still owed.
static var last_note: String = ""
static var encoder_used: String = ""
static var last_report: Dictionary = {}

## How long the export may work before it hands the screen back, in
## milliseconds.
##
## It used to give a turn back after every single frame, which on a short
## scene is polite and on a long one is most of the export: sixty thousand
## waits, each one a whole display frame, is sixteen minutes of doing nothing
## at all. Fourteen milliseconds is under one frame of a sixty-hertz screen,
## so the interface still never misses a beat, and on a fast device thirty
## frames now get encoded between turns instead of one.
const BREATH_MS: int = 14

static func cancel() -> void:
	cancel_requested = true

## Whether this build can write an MP4 at all, by any route.
##
## Two routes, and they do not overlap: Android's own MediaCodec, which is on
## every phone and needs nothing bundled, and the FFmpeg library, which is
## what a desktop build uses. A phone has the first and not the second; a
## desktop has the second and not the first.
static func can_export() -> bool:
	return MP4Direct.available() or ClassDB.class_exists("GoZenMP4Encoder")

## Which of the two is going to do the work.
##
## MediaCodec first wherever it exists. It is the phone's own silicon: faster
## than software H.264 will ever be on a battery, and it costs the APK
## nothing, because it is already in the operating system.
static func backend() -> Object:
	if MP4Direct.available():
		return MP4Direct.new()
	return MP4ExportWorker.new()

static func backend_name() -> String:
	if MP4Direct.available():
		return "MediaCodec"
	if ClassDB.class_exists("GoZenMP4Encoder"):
		return "FFmpeg"
	return ""

## What to ask the encoder for, in bits a second.
##
## MediaCodec has no constant-quality mode — it takes a bitrate and nothing
## else. So when the caller has chosen a CRF rather than a rate, one is worked
## out here from the picture and the quality asked for, rather than the phone
## silently doing whatever it defaults to.
##
## Doubling for every six steps of CRF is the same curve x264 follows, which
## keeps Draft, Good, High and Maximum meaning roughly the same thing on both
## routes. That matters more than either number being exactly right: a person
## who exports at High on a phone and High on a desktop should get the same
## film.
static func rate_for(width: int, height: int, fps: int, crf: int,
		bitrate: int) -> int:
	if bitrate > 0:
		return bitrate
	var tall: int = height if height > 0 else int(round(float(width) * 9.0 / 16.0))
	var base: float = float(width) * float(tall) * float(fps) * 0.07
	base *= pow(2.0, float(21 - clampi(crf, 10, 40)) / 6.0)
	return clampi(int(base), 1200000, 80000000)

static func resolution_width(name: String, source_width: int,
		_source_height: int) -> int:
	match name:
		"480p": return 854
		"720p": return 1280
		"1080p": return 1920
		"1440p": return 2560
		"4K": return 3840
		_: return source_width

## What each named quality actually asks the encoder for.
##
## CRF is the honest control — it holds a *quality* and lets the size go
## where it must, which is what an animator wants: flat colour and clean
## line art cost almost nothing, and the one shot with a paint texture in it
## gets the bits it needs instead of being starved to hit an average.
##
## `preset` is how hard the encoder is allowed to think. It costs time and
## nothing else: the same CRF at a slower preset is the same picture in a
## smaller file. Draft is for checking timing, so it is fast; Maximum is for
## the finished piece, so it is not.
##
## `audio_kbps` rises with the preset for the same reason. 128 is the number
## everything defaults to and it is audible on music — a cymbal turns to
## gauze. 256 and 320 are not.

static func format_settings(name: String) -> Dictionary:
	match name:
		"mp4_h264": return {"ext":"mp4", "container":"mp4", "codec":"h264", "label":"MP4 · H.264"}
		"mp4_hevc": return {"ext":"mp4", "container":"mp4", "codec":"hevc", "label":"MP4 · HEVC"}
		"mov_h264": return {"ext":"mov", "container":"mov", "codec":"h264", "label":"MOV · H.264"}
		"mkv_h264": return {"ext":"mkv", "container":"mkv", "codec":"h264", "label":"MKV · H.264"}
		"webm_vp9": return {"ext":"webm", "container":"webm", "codec":"vp9", "label":"WebM · VP9"}
		"webm_av1": return {"ext":"webm", "container":"webm", "codec":"av1", "label":"WebM · AV1"}
		_: return {"ext":"mp4", "container":"mp4", "codec":"h264", "label":"MP4 · H.264"}

static func is_hardware_format(name: String) -> bool:
	return name == "mp4_h264" and MP4Direct.available()

static func format_available(name: String) -> bool:
	if name == "mp4_h264" and MP4Direct.available():
		return true
	if not ClassDB.class_exists("GoZenMP4Encoder"):
		return false
	var probe: Object = ClassDB.instantiate("GoZenMP4Encoder")
	if probe == null or not probe.has_method("capabilities"):
		return false
	var caps: Dictionary = probe.capabilities()
	var fs: Dictionary = format_settings(name)
	match String(fs["codec"]):
		"h264": return bool(caps.get("h264", false))
		"hevc": return bool(caps.get("hevc", false))
		"vp9": return bool(caps.get("vp9", false))
		"av1": return bool(caps.get("av1", false))
	return false

static func quality_settings(name: String, source_width: int,
		fps: int) -> Dictionary:
	match name:
		"Draft":
			return {"crf": 28, "bitrate": maxi(1200000,
				int(source_width * source_width * fps * 0.05)),
				"preset": "veryfast", "audio_kbps": 128}
		"High":
			return {"crf": 17, "bitrate": 0, "preset": "medium",
				"audio_kbps": 256}
		"Maximum":
			return {"crf": 13, "bitrate": 0, "preset": "slow",
				"audio_kbps": 320}
		_:
			return {"crf": 21, "bitrate": 0, "preset": "fast",
				"audio_kbps": 192}

static func error_text(code: int, native_error: String = "") -> String:
	if native_error != "":
		return native_error
	match code:
		-1: return "Unsupported resolution"
		-2: return "Unsupported FPS"
		-4: return "H.264 encoder unavailable"
		-6, -8, -12: return "AAC initialization failed"
		-16: return "Disk space insufficient or output path is not writable"
		-30: return "Insufficient memory"
		_: return "MP4 export failed (error %d)" % code

## Which stretch of the scene to export.
##
## Three answers, in the order they win: an explicit range asked for by the
## caller, the project's own remembered choice, and failing both, everything.
static func _export_span(p: ProjectManager.Project, range_from: int = -1,
		range_to: int = -1) -> Vector2i:
	if p == null or p.clip == null:
		return Vector2i(0, 0)
	var last: int = maxi(p.clip.reach(p.stack), maxi(p.clip.length - 1, 0))
	if range_from >= 0 or range_to >= 0:
		var a: int = clampi(0 if range_from < 0 else range_from, 0, last)
		var b: int = clampi(last if range_to < 0 else range_to, 0, last)
		return Vector2i(mini(a, b), maxi(a, b))
	if p.export_range == "Playback":
		var span: Vector2i = p.clip.play_span(p.stack)
		return Vector2i(clampi(span.x, 0, last), clampi(span.y, 0, last))
	if p.export_range == "Custom":
		var c0: int = clampi(p.export_from, 0, last)
		var c1: int = clampi(p.export_to if p.export_to > 0 else last, 0, last)
		return Vector2i(mini(c0, c1), maxi(c0, c1))
	return Vector2i(0, last)

## Which timeline frame is being shown at a moment, found by halving rather
## than walking — a scene with frame-rate units in it does not run at one
## constant rate, so the frame at a second cannot be worked out by division.
static func _timeline_frame_at_time(p: ProjectManager.Project, t: float,
		from_frame: int, to_frame: int) -> int:
	if p == null or p.clip == null:
		return from_frame
	var lo: int = from_frame
	var hi: int = maxi(to_frame, from_frame)
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if p.clip.time_of(mid) <= t:
			lo = mid
		else:
			hi = mid - 1
	return clampi(lo, from_frame, to_frame)

## Roughly how big the file will be, in megabytes, so a two-hour export at
## maximum quality is a decision rather than a surprise.
static func estimate_mb(p: ProjectManager.Project, width: int,
		bitrate: int, crf: int, audio_kbps: int) -> float:
	if p == null or p.clip == null:
		return 0.0
	var span: Vector2i = _export_span(p)
	var seconds: float = maxf(p.clip.time_of(span.y + 1)
		- p.clip.time_of(span.x), 0.0)
	var bits: float = float(bitrate)
	if bits <= 0.0:
		# CRF has no fixed rate, so this is only ever an order of magnitude.
		# Line art at CRF 21 lands far under it, which is the safe direction
		# for a warning to be wrong in.
		var tall: float = float(width) * 9.0 / 16.0
		bits = float(width) * tall * float(p.fps) * 0.07
		bits *= pow(2.0, float(21 - crf) / 6.0)
	bits += float(maxi(audio_kbps, 0)) * 1000.0
	return (bits * seconds) / 8.0 / 1048576.0

## The whole export, from the first frame to a finished, verified file.
static func save(p: ProjectManager.Project, width: int = 0,
		bitrate: int = 0, crf: int = 20, profile: String = "high",
		audio: bool = true, progress: Callable = Callable(),
		range_from: int = -1, range_to: int = -1,
		preset: String = "fast", audio_kbps: int = 192,
		format_name: String = "mp4_h264") -> String:
	last_error = ""
	last_note = ""
	last_report = {}
	encoder_used = ""
	Exporters.last_short_by = 0
	if p == null or p.stack == null or p.clip == null:
		last_error = "Nothing to export yet"
		return ""
	if not can_export():
		last_error = "Video encoder unavailable"
		return ""

	if not format_available(format_name):
		last_error = "The selected video format is unavailable in this build"
		return ""

	var fs: Dictionary = format_settings(format_name)
	if ClassDB.class_exists("GoZenMP4Encoder") and not format_name == "mp4_h264" and not format_name == "mp4_hevc" and not format_name == "mov_h264" and not format_name == "mkv_h264" and not format_name == "webm_vp9" and not format_name == "webm_av1":
		format_name = "mp4_h264"
		fs = format_settings(format_name)
	var dir: String = Exporters.ensure_dir()
	var final_path: String = "%s/%s.%s" % [dir, Exporters.base_name(p), String(fs["ext"])]
	var native_final: String = ProjectSettings.globalize_path(final_path)
	var tmp_path: String = final_path + ".tmp"
	var native_tmp: String = ProjectSettings.globalize_path(tmp_path)
	if FileAccess.file_exists(native_tmp):
		DirAccess.remove_absolute(native_tmp)

	var span: Vector2i = _export_span(p, range_from, range_to)
	var from_frame: int = maxi(span.x, 0)
	var to_frame: int = maxi(span.y, from_frame)
	var rate: int = clampi(p.fps, 1, 120)
	var began_at: float = p.clip.time_of(from_frame)
	var total_duration: float = maxf(p.clip.time_of(to_frame + 1) - began_at,
		1.0 / float(rate))
	var total: int = maxi(int(round(total_duration * float(rate))), 1)

	# ------------------------------------------------------------- sound
	#
	# Opened before a single frame is rendered. Discovering on frame nine
	# thousand that a track cannot be read is nine thousand frames of the
	# user's evening spent on an answer that was knowable at the start.
	var mix: AudioMix = null
	if audio and p.clip.audio != null and p.clip.audio.anything_to_hear():
		mix = AudioMix.open(p.clip.audio,
			func(f: int) -> float: return p.clip.time_of(f),
			from_frame, to_frame, total_duration)
		if mix.trouble != "":
			last_note = mix.trouble
		if mix.silent():
			mix.close()
			mix = null
	var with_sound: bool = mix != null

	var use_direct: bool = format_name == "mp4_h264" and MP4Direct.available()
	var worker: Object
	if use_direct:
		worker = MP4Direct.new()
	else:
		worker = MP4ExportWorker.new()
	cancel_requested = false
	exporting = true
	var opened_size: Vector2i = Vector2i.ZERO
	var frame_no: int = 0
	var failed: bool = false
	var failure_text: String = ""
	var was: int = p.stack.shown_frame
	var breathed_at: int = Time.get_ticks_msec()

	for output_index in range(total):
		if cancel_requested:
			break
		# Integer sample boundaries, so twenty-four frames a second at forty-
		# eight thousand samples lands on exactly two thousand samples every
		# frame and never drifts a sample per minute into a lip-sync problem.
		var s0: int = int(floor(float(output_index) * float(AudioMix.RATE)
			/ float(rate)))
		var s1: int = int(floor(float(output_index + 1) * float(AudioMix.RATE)
			/ float(rate)))
		var f: int = _timeline_frame_at_time(p,
			began_at + float(output_index) / float(rate), from_frame, to_frame)
		p.stack.show_frame(f, false)
		var img: Image = Exporters.render_page(p, -1)
		if img == null:
			failed = true
			failure_text = "Frame renderer failed"
			break
		if width > 0 and img.get_width() != width:
			var scale: float = float(width) / float(img.get_width())
			img.resize(maxi(int(round(img.get_width() * scale)), 2),
				maxi(int(round(img.get_height() * scale)), 2),
				Image.INTERPOLATE_LANCZOS)
		# H.264 counts in pairs of pixels. An odd edge is trimmed rather than
		# stretched, because stretching by one pixel softens the whole frame.
		var ew: int = maxi(img.get_width() - (img.get_width() & 1), 2)
		var eh: int = maxi(img.get_height() - (img.get_height() & 1), 2)
		if ew != img.get_width() or eh != img.get_height():
			img.crop(ew, eh)

		if opened_size == Vector2i.ZERO:
			opened_size = img.get_size()
			# The bitrate is settled here rather than at the call site,
			# because only now is the real picture size known — a "Source"
			# export of a 900-pixel canvas should not be given a 1080p rate.
			var bits: int = rate_for(opened_size.x, opened_size.y, rate, crf,
				bitrate)
			if not worker.start(native_tmp, opened_size.x, opened_size.y,
					rate, bits, crf, profile, with_sound, AudioMix.RATE,
					AudioMix.CHANNELS, preset, audio_kbps, String(fs["container"]),
					String(fs["codec"])):
				failed = true
				failure_text = worker.error_message()
				break
			encoder_used = String(worker.get_encoder_name())

		var pcm: PackedByteArray = PackedByteArray()
		var samples: int = 0
		if with_sound:
			samples = maxi(s1 - s0, 0)
			pcm = mix.read(s0, samples)
		if not worker.push_frame(img.get_data(), pcm, samples):
			if not cancel_requested:
				failed = true
				failure_text = worker.error_message()
			break
		frame_no += 1
		if not progress.is_null():
			progress.call(frame_no, total, f, rate)
		# A turn for the screen, on a clock rather than on every frame.
		if Time.get_ticks_msec() - breathed_at >= BREATH_MS:
			breathed_at = Time.get_ticks_msec()
			await Engine.get_main_loop().process_frame

	p.stack.show_frame(was, false)
	if mix != null:
		mix.close()

	if cancel_requested:
		worker.cancel()
		worker.finish()
		last_error = "Export cancelled"
	elif failed:
		worker.cancel()
		worker.finish()
		last_error = failure_text if failure_text != "" \
			else "MP4 export failed"
	else:
		var wr: int = worker.finish()
		if wr != 0:
			last_error = worker.error_message()

	if last_error != "" or not FileAccess.file_exists(native_tmp):
		if FileAccess.file_exists(native_tmp):
			DirAccess.remove_absolute(native_tmp)
		exporting = false
		return ""

	var report: Dictionary = _inspect(native_tmp)
	var expected: float = float(total) / float(rate)
	var checked: Dictionary = {"ok": true, "why": ""}
	if bool(report.get("readable", false)):
		checked = _verdict(report, opened_size, total, expected, with_sound, String(fs["codec"]))
	if not bool(checked["ok"]):
		last_error = String(checked["why"]) if String(checked["why"]) != "" \
			else "The video came out empty"
		DirAccess.remove_absolute(native_tmp)
		exporting = false
		return ""

	if FileAccess.file_exists(native_final):
		DirAccess.remove_absolute(native_final)
	if DirAccess.rename_absolute(native_tmp, native_final) != OK:
		last_error = "Could not finalize MP4 safely"
		DirAccess.remove_absolute(native_tmp)
		exporting = false
		return ""

	# Into the gallery, where a person can actually reach it. An app's own
	# folder is invisible to every other app on the phone, which for somebody
	# who has just spent an evening on a film is the same as it not existing.
	var shared: String = MP4Direct.publish(final_path, final_path.get_file()) if String(fs["ext"]) == "mp4" else ""
	last_report = {"published": shared, "frames": total, "duration": expected,
		"format": String(fs["ext"]), "codec_requested": String(fs["codec"]),
		"video_duration": float(report.get("video_duration_us", 0)) / 1000000.0,
		"audio_duration": float(report.get("audio_duration_us", 0)) / 1000000.0,
		"encoder": encoder_used, "backend": backend_name(),
		"width": opened_size.x, "height": opened_size.y,
		"audio": with_sound, "verified": bool(report.get("readable", false))}
	exporting = false
	return final_path

## Asks the native layer what it actually wrote.
##
## Reached through `ClassDB` rather than by name, so this file still parses
## and the whole app still opens on a build with no native library — which is
## every build made before the media layer is compiled for the device.
## Asks whatever is present what was actually written.
##
## `readable` is separate from `ok` on purpose. `ok` means "this file is
## wrong"; `readable` means "somebody was able to look". With no inspector at
## all — an Android build with no FFmpeg in it, which is the normal case now —
## nobody looked, and the difference between *not checked* and *failed* is the
## difference between handing over a good film and deleting it.
##
## The file is not taken on trust either way: it has to exist, and it has to
## be large enough to be a video rather than an empty container.
static func _inspect(path: String) -> Dictionary:
	if not ClassDB.class_exists("GoZenMP4Encoder"):
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		var size: int = 0
		if f != null:
			size = f.get_length()
			f.close()
		return {"ok": size > 1024, "readable": false, "bytes": size}
	var box: Object = ClassDB.instantiate("GoZenMP4Encoder")
	if box == null or not box.has_method("inspect_file"):
		return {"ok": true, "readable": false}
	var told: Dictionary = box.call("inspect_file", path)
	told["readable"] = true
	return told

## Whether what was written is what was asked for.
##
## Strict about the things that make a file wrong — the wrong codec, the
## wrong size, half the frames — and forgiving about the things that are
## never exact. AAC carries an encoder delay of about a thousand samples and
## pads the last block out to a full one, so its stream is reliably a few
## hundredths of a second longer than the picture. Failing on that would
## delete a perfectly good film for being correct.
static func _verdict(report: Dictionary, size: Vector2i, total: int,
		expected: float, with_sound: bool, expected_codec: String = "h264") -> Dictionary:
	if not bool(report.get("ok", false)):
		return {"ok": false, "why": "MP4 verification failed: the file could not be read back"}
	var actual_codec: String = String(report.get("video_codec", ""))
	var accepted: bool = actual_codec == expected_codec
	if expected_codec == "hevc":
		accepted = actual_codec in ["hevc", "h265"]
	if expected_codec == "vp9":
		accepted = actual_codec == "vp9"
	if expected_codec == "av1":
		accepted = actual_codec == "av1"
	if not accepted:
		return {"ok": false, "why": "Video verification failed: the requested codec was not written"}
	if int(report.get("width", 0)) != size.x or int(report.get("height", 0)) != size.y:
		return {"ok": false, "why": "MP4 verification failed: the picture is the wrong size"}
	var frames: int = int(report.get("frames", 0))
	if frames > 0 and absi(frames - total) > 1:
		return {"ok": false, "why": "MP4 verification failed: frames are missing"}
	var vd: float = float(report.get("video_duration_us", 0)) / 1000000.0
	if vd > 0.0 and absf(vd - expected) > maxf(expected * 0.02, 0.35):
		return {"ok": false, "why": "MP4 verification failed: the video is the wrong length"}
	if with_sound:
		var expected_audio: String = "opus" if expected_codec in ["vp9", "av1"] else "aac"
		if not bool(report.get("has_audio", false)) or String(report.get("audio_codec", "")) != expected_audio:
			return {"ok": false, "why": "Video verification failed: the sound was not written"}
		var ad: float = float(report.get("audio_duration_us", 0)) / 1000000.0
		if ad > 0.0 and absf(ad - expected) > maxf(expected * 0.02, 0.35):
			return {"ok": false, "why": "MP4 verification failed: the sound is the wrong length"}
	return {"ok": true, "why": ""}
