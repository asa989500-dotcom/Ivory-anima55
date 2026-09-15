class_name AudioBank
extends RefCounted
## Everything between a sound file on the device and samples the app can use.
##
## Two jobs, kept apart on purpose because they want opposite things.
##
## **Playing** wants the file left compressed. Godot decodes MP3 and Ogg as
## they play, so a forty-minute track costs the size of the MP3 and nothing
## more. Loading it as raw samples to hear it would cost four hundred
## megabytes for no gain at all.
##
## **Exporting** wants the opposite: exact samples, in order, at a known rate,
## readable a slice at a time from a known byte offset while a video is being
## written. Nothing decodes fast enough to be asked mid-encode, and nothing
## fits in memory at feature length. So the first export of a file writes a
## plain PCM16 WAV beside it in the cache, and every export after that reads
## that file straight off the disk.
##
## Importing is therefore instant. Nothing is decoded when a sound is added —
## the name, the length and the rate are all that is read, and the expensive
## part happens once, later, and is then never repeated.

## The formats worth offering in the picker.
##
## Two lists, because they are answers to two different questions. `PLAYABLE`
## is what Godot itself can decode, so those play in the app straight away.
## `DECODABLE` is everything the native media layer can turn into samples,
## which is nearly everything a phone will ever hold — those import and export
## correctly, and simply have no live preview until they are exported once.
const PLAYABLE: Array = ["wav", "wave", "mp3", "ogg", "oga", "opus"]
const DECODABLE: Array = [
	"wav", "wave", "wv", "mp3", "ogg", "oga", "opus", "m4a", "m4b", "mp4",
	"aac", "adts", "flac", "alac", "aiff", "aif", "aifc", "wma", "asf",
	"ac3", "eac3", "amr", "3gp", "3ga", "caf", "au", "snd", "mka", "mkv",
	"webm", "mov", "ape", "tta", "dts", "mp2", "mpga", "oma", "voc", "w64",
	"rf64", "spx", "gsm", "ra", "shn", "mpc"]

## How many bytes of cache are kept before the oldest are let go.
const CACHE_CEILING: int = 700 * 1024 * 1024

# ------------------------------------------------------------- the picker

## Filters for the file dialog.
##
## Every extension in both casings. A filter is a plain string match, and a
## file named `TRACK.MP3` — which is how a great many downloads arrive — is
## invisible to a filter written in lower case.
static func filters() -> PackedStringArray:
	var common: String = ""
	for ext in ["mp3", "wav", "m4a", "aac", "flac", "ogg", "opus", "wma",
			"aiff", "mp4", "amr", "caf"]:
		common += "*.%s, *.%s, " % [ext, String(ext).to_upper()]
	var rest: String = ""
	for ext in DECODABLE:
		rest += "*.%s, *.%s, " % [ext, String(ext).to_upper()]
	return PackedStringArray([
		common.trim_suffix(", ") + " ; " + UiKit.label_for(
			"Common audio", "الصيغ الشائعة"),
		rest.trim_suffix(", ") + " ; " + UiKit.label_for(
			"Every audio format", "كل صيغ الصوت"),
		"* ; " + UiKit.label_for("Every file", "كل الملفات")])

static func supported(path: String) -> bool:
	return DECODABLE.has(path.get_extension().to_lower())

static func playable(path: String) -> bool:
	return PLAYABLE.has(path.get_extension().to_lower())

# --------------------------------------------------------------- the cache

static func cache_dir() -> String:
	var where: String = "user://audio_cache"
	if not DirAccess.dir_exists_absolute(where):
		DirAccess.make_dir_recursive_absolute(where)
	return where

## A name that changes when the file does.
##
## Path, length and modification time together: the same track re-recorded
## under the same name gets a new cache rather than the old one silently.
static func _key(path: String) -> String:
	var size: int = 0
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	var when: int = int(FileAccess.get_modified_time(path))
	return "%s/%s_%d_%d.wav" % [cache_dir(),
		String.num_uint64(abs(path.hash()), 16), size, when]

## Drops the oldest caches once the folder is bigger than it should be.
##
## Called after a cache is written rather than on a timer, because that is
## the only moment the folder grows, and a sweep that runs when nothing has
## changed is a sweep that costs battery for nothing.
static func sweep() -> void:
	var dir: DirAccess = DirAccess.open(cache_dir())
	if dir == null:
		return
	var rows: Array = []
	var total: int = 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".wav"):
			var full: String = "%s/%s" % [cache_dir(), name]
			var f: FileAccess = FileAccess.open(full, FileAccess.READ)
			if f != null:
				var size: int = f.get_length()
				f.close()
				total += size
				rows.append({"path": full, "size": size,
					"when": int(FileAccess.get_modified_time(full))})
		name = dir.get_next()
	dir.list_dir_end()
	if total <= CACHE_CEILING:
		return
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["when"]) < int(b["when"]))
	for row in rows:
		if total <= CACHE_CEILING:
			return
		DirAccess.remove_absolute(String(row["path"]))
		total -= int(row["size"])

# ----------------------------------------------------------- reading a WAV

## What a WAV file is, without reading a single sample.
##
## Returns `at` and `block` so a reader can seek straight to any sample it
## wants rather than walking the file. Handles every shape a phone or a
## desktop recorder actually writes: 8, 16, 24 and 32-bit integer, 32 and
## 64-bit float, and WAVE_FORMAT_EXTENSIBLE, which hides the real format
## inside a GUID and which almost every modern recorder uses.
static func read_header(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "why": "unreadable"}
	var size: int = f.get_length()
	if size < 44:
		f.close()
		return {"ok": false, "why": "empty"}
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
			f.get_32()
			block = f.get_16()
			bits = f.get_16()
			if kind == 0xFFFE and length >= 40:
				f.seek(body + 24)
				kind = f.get_16()
		elif tag == "data":
			data_at = body
			data_len = mini(length, size - body)
		# Chunks are padded to an even length. A reader that forgets it ends
		# up one byte out and reads rubbish for every chunk after the first.
		f.seek(body + length + (length & 1))
		if data_at >= 0 and channels > 0:
			break

	f.close()
	if data_at < 0 or channels < 1 or rate < 1 or bits < 8:
		return {"ok": false, "why": "not_wav"}
	if kind != 1 and kind != 3:
		return {"ok": false, "why": "compressed"}
	if block < 1:
		block = channels * _bytes_per(bits)
	return {"ok": true, "kind": kind, "channels": channels, "rate": rate,
		"bits": bits, "block": block, "at": data_at,
		"frames": floori(float(data_len) / float(maxi(block, 1))),
		"seconds": float(data_len) / float(maxi(block * rate, 1))}

## How many bytes one sample of this width takes.
##
## Its own function so the division happens once, in a place where it can be
## said plainly that it is meant to be whole. GDScript warns about `bits / 8`
## on two integers — rightly, because nine times out of ten the decimal part
## being thrown away is a bug — and a warning that cannot be answered honestly
## is one everybody learns to scroll past.
static func _bytes_per(bits: int) -> int:
	return maxi(floori(float(bits) / 8.0), 1)

## Whether a WAV can be read for export exactly as it lies on the disk.
static func _is_plain_pcm16(head: Dictionary) -> bool:
	return bool(head.get("ok", false)) \
		and int(head.get("kind", 0)) == 1 \
		and int(head.get("bits", 0)) == 16 \
		and int(head.get("channels", 0)) <= 2

# ------------------------------------------------------------- writing PCM

static func _wav_header(rate: int, channels: int, bytes: int) -> PackedByteArray:
	var head: PackedByteArray = PackedByteArray()
	head.resize(44)
	head.encode_u8(0, 0x52); head.encode_u8(1, 0x49)
	head.encode_u8(2, 0x46); head.encode_u8(3, 0x46)       # RIFF
	head.encode_u32(4, 36 + bytes)
	head.encode_u8(8, 0x57); head.encode_u8(9, 0x41)
	head.encode_u8(10, 0x56); head.encode_u8(11, 0x45)     # WAVE
	head.encode_u8(12, 0x66); head.encode_u8(13, 0x6D)
	head.encode_u8(14, 0x74); head.encode_u8(15, 0x20)     # "fmt "
	head.encode_u32(16, 16)
	head.encode_u16(20, 1)
	head.encode_u16(22, channels)
	head.encode_u32(24, rate)
	head.encode_u32(28, rate * channels * 2)
	head.encode_u16(32, channels * 2)
	head.encode_u16(34, 16)
	head.encode_u8(36, 0x64); head.encode_u8(37, 0x61)
	head.encode_u8(38, 0x74); head.encode_u8(39, 0x61)     # data
	head.encode_u32(40, bytes)
	return head

static func _write_pcm16(out: String, pcm: PackedByteArray, rate: int,
		channels: int) -> bool:
	var f: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(_wav_header(rate, channels, pcm.size()))
	f.store_buffer(pcm)
	f.close()
	return true

# ---------------------------------------------------------------- decoding

## Turns any WAV shape into plain PCM16, a slice at a time.
##
## In slices because a long take at 32-bit float is four times the size of
## what comes out of it, and holding both at once on a phone is how an
## import becomes a crash.
static func _convert_wav(path: String, head: Dictionary, out: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var channels: int = mini(int(head["channels"]), 2)
	var block: int = int(head["block"])
	var bits: int = int(head["bits"])
	var kind: int = int(head["kind"])
	var frames: int = int(head["frames"])
	var step_bytes: int = _bytes_per(bits)
	var w: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	if w == null:
		f.close()
		return false
	w.store_buffer(_wav_header(int(head["rate"]), channels, frames * channels * 2))
	f.seek(int(head["at"]))
	var step: int = 65536
	var done: int = 0
	while done < frames:
		var take: int = mini(step, frames - done)
		var raw: PackedByteArray = f.get_buffer(take * block)
		var got: int = floori(float(raw.size()) / float(maxi(block, 1)))
		if got < 1:
			break
		var slice: PackedByteArray = PackedByteArray()
		slice.resize(got * channels * 2)
		for i in got:
			for c in channels:
				var at: int = i * block + c * step_bytes
				var value: int = 0
				if at + step_bytes <= raw.size():
					value = _one_sample(raw, at, bits, kind)
				slice.encode_s16((i * channels + c) * 2, value)
		w.store_buffer(slice)
		done += got
	f.close()
	w.close()
	return done > 0

## One sample, whatever shape it was written in, as signed 16-bit.
static func _one_sample(raw: PackedByteArray, at: int, bits: int,
		kind: int) -> int:
	if kind == 3:
		var value: float = 0.0
		if bits == 64:
			value = raw.decode_double(at)
		else:
			value = raw.decode_float(at)
		return clampi(int(round(clampf(value, -1.0, 1.0) * 32767.0)),
			-32768, 32767)
	match bits:
		8:
			# Eight-bit WAV is unsigned, with 128 as silence.
			return clampi((raw.decode_u8(at) - 128) * 256, -32768, 32767)
		16:
			return raw.decode_s16(at)
		24:
			var low: int = raw.decode_u8(at)
			var mid: int = raw.decode_u8(at + 1)
			var high: int = raw.decode_u8(at + 2)
			var whole: int = low | (mid << 8) | (high << 16)
			if whole >= 0x800000:
				whole -= 0x1000000
			return clampi(whole >> 8, -32768, 32767)
		32:
			return clampi(raw.decode_s32(at) >> 16, -32768, 32767)
	return 0

## Everything else, through the native media layer.
##
## Reached by name rather than written into the code, so a build without the
## native library still opens, still plays WAV and MP3, and says plainly what
## it cannot do instead of refusing to start.
static func _decode_native(path: String, out: String) -> Dictionary:
	# Android's own decoders first. They cover MP3, AAC, M4A, FLAC, Ogg
	# Vorbis, Opus, AMR and WAV — the same ones the phone's music player
	# uses — and they are already in the operating system, so nothing is
	# bundled and some of them run on hardware.
	if Engine.has_singleton("IvoryAudio"):
		var phone: Object = Engine.get_singleton("IvoryAudio")
		var told: Dictionary = phone.call("decode_to_wav",
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(out), 48000, 2)
		if bool(told.get("ok", false)):
			return {"ok": true, "rate": int(told.get("rate", 48000)),
				"channels": int(told.get("channels", 2))}
		# Not a dead end: a format Android will not take may still be one
		# FFmpeg will, if this build happens to have it.
	if not ClassDB.class_exists("GoZenAudio"):
		return {"ok": false, "why": "no_decoder"}
	var box: Object = ClassDB.instantiate("GoZenAudio")
	if box == null:
		return {"ok": false, "why": "no_decoder"}
	# The streaming path when the native library has it: decoding straight to
	# the cache file never holds the whole track in memory, so an hour-long
	# score costs no more than a ten-second one.
	if box.has_method("decode_to_wav"):
		var report: Dictionary = box.call("decode_to_wav",
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(out), 48000, 2)
		if bool(report.get("ok", false)):
			return {"ok": true, "rate": int(report.get("rate", 48000)),
				"channels": int(report.get("channels", 2))}
		return {"ok": false, "why": String(report.get("error", "decode_failed"))}
	# The older library decodes in one piece. It still works, and it is still
	# written out immediately so nothing but the export holds samples.
	var pcm: PackedByteArray = box.call("get_audio_data", path, -1, true)
	if pcm.is_empty():
		return {"ok": false, "why": "decode_failed"}
	var wrote: bool = _write_pcm16(out, pcm, 44100, 2)
	pcm = PackedByteArray()
	if not wrote:
		return {"ok": false, "why": "cache_unwritable"}
	return {"ok": true, "rate": 44100, "channels": 2}

# -------------------------------------------------------------- the answers

## What this file is, read cheaply enough to do while a finger is still on
## the button. Nothing is decoded here.
static func describe(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "why": "missing"}
	if not supported(path):
		return {"ok": false, "why": "unsupported"}
	var ext: String = path.get_extension().to_lower()
	if ext == "wav" or ext == "wave":
		var head: Dictionary = read_header(path)
		if bool(head.get("ok", false)):
			return {"ok": true, "seconds": float(head["seconds"]),
				"rate": int(head["rate"]),
				"channels": mini(int(head["channels"]), 2)}
	var stream: AudioStream = make_stream(path)
	if stream != null:
		return {"ok": true, "seconds": stream.get_length(), "rate": 0,
			"channels": 0}
	# The phone can read a duration out of the container without decoding a
	# single sample, which is what keeps importing twelve tracks instant.
	if Engine.has_singleton("IvoryAudio"):
		var seconds: float = float(Engine.get_singleton("IvoryAudio").call(
			"length_of", ProjectSettings.globalize_path(path)))
		if seconds > 0.0:
			return {"ok": true, "seconds": seconds, "rate": 0, "channels": 0}
	# Length unknown until it is decoded, which is not a reason to refuse the
	# import — it is measured the first time the sound is exported.
	return {"ok": true, "seconds": 0.0, "rate": 0, "channels": 0}

## A stream for hearing this sound in the app, or null if Godot cannot
## decode it without help.
static func make_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg", "oga", "opus":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav", "wave":
			return AudioStreamWAV.load_from_file(path)
	# Anything else can still be heard once it has been through the cache,
	# which the exporter builds. If it is there already, use it.
	var cached: String = _key(path)
	if FileAccess.file_exists(cached):
		return AudioStreamWAV.load_from_file(cached)
	return null

## Where to read this sound's samples from, building the cache if this is
## the first time it has been asked for.
##
## The returned dictionary is everything a reader needs and nothing it does
## not: which file, the byte the samples start at, how wide one frame of
## samples is, and how many there are.
static func source_for(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "why": "missing"}
	var head: Dictionary = read_header(path)
	if _is_plain_pcm16(head):
		return {"ok": true, "pcm": path, "at": int(head["at"]),
			"block": int(head["block"]), "rate": int(head["rate"]),
			"channels": int(head["channels"]), "frames": int(head["frames"])}
	var cached: String = _key(path)
	if not FileAccess.file_exists(cached):
		var built: bool = false
		if bool(head.get("ok", false)):
			built = _convert_wav(path, head, cached)
		else:
			var report: Dictionary = _decode_native(path, cached)
			built = bool(report.get("ok", false))
			if not built:
				return {"ok": false, "why": String(report.get("why", "decode_failed"))}
		if not built:
			return {"ok": false, "why": "decode_failed"}
		sweep()
	var made: Dictionary = read_header(cached)
	if not _is_plain_pcm16(made):
		DirAccess.remove_absolute(cached)
		return {"ok": false, "why": "decode_failed"}
	return {"ok": true, "pcm": cached, "at": int(made["at"]),
		"block": int(made["block"]), "rate": int(made["rate"]),
		"channels": int(made["channels"]), "frames": int(made["frames"])}

## Plain words for what went wrong, in both languages.
static func trouble_words(why: String) -> String:
	match why:
		"missing":
			return UiKit.label_for("That sound file is gone",
				"ملف الصوت لم يعد موجوداً")
		"unsupported":
			return UiKit.label_for("That format is not a sound file",
				"هذه الصيغة ليست ملفاً صوتياً")
		"no_decoder":
			return UiKit.label_for(
				"This build can only read WAV, MP3 and Ogg",
				"هذه النسخة تقرأ WAV وMP3 وOgg فقط")
		"decode_failed":
			return UiKit.label_for("The phone could not decode that sound",
				"تعذّر على الهاتف فكّ ترميز هذا الصوت")
		"cache_unwritable":
			return UiKit.label_for("No room left to prepare the sound",
				"لا توجد مساحة كافية لتحضير الصوت")
	return UiKit.label_for("That sound could not be read",
		"تعذّرت قراءة هذا الصوت")
