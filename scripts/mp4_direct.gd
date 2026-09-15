class_name MP4Direct
extends RefCounted
## The MP4 encoder when Android's own is available, which on a phone is
## always.
##
## ## Why this is not on a worker thread
##
## `MP4ExportWorker` exists because FFmpeg encodes in software and a software
## H.264 frame is tens of milliseconds — long enough that doing it on the main
## thread freezes the app. MediaCodec is not software. It hands the frame to
## the chip's encoder and returns, usually inside two milliseconds, and the
## export loop already gives the screen a turn on its own clock.
##
## So a thread here would buy nothing and cost the one thing that matters:
## JNI calls from a thread Godot did not make have to be attached to the Java
## VM by hand, and getting that subtly wrong is the kind of fault that appears
## on one make of phone, six months later, as a crash nobody can reproduce.
##
## ## Why it wears the worker's shape
##
## Same methods, same names, same meanings — `start`, `push_frame`, `cancel`,
## `finish`, `error_message`, `get_encoder_name`. `Mp4Export.save` picks one
## and never asks again which it got. Two encoders behind one door is a door;
## two encoders behind two doors is two export pipelines that drift apart.

const SINGLETON: String = "IvoryMP4"

var _box: Object = null
var _last_error: String = ""
var _encoder_name: String = ""
var _cancelled: bool = false

## Whether the phone can do this at all.
##
## The plugin is only present in an Android build, so everywhere else this is
## false and the FFmpeg worker is used instead — which is the right way round:
## a desktop has the power for software encoding and no MediaCodec, and a
## phone has the opposite.
static func available() -> bool:
	return Engine.has_singleton(SINGLETON)

static func store() -> Object:
	if Engine.has_singleton("IvoryStore"):
		return Engine.get_singleton("IvoryStore")
	return null

## Puts a finished video where the phone's gallery will find it.
##
## Returns the place it now lives, or an empty string if it could not be
## published — which the caller says out loud rather than swallowing, because
## a video the user cannot find is, to the user, an export that failed.
static func publish(path: String, name: String) -> String:
	var box: Object = store()
	if box == null:
		return ""
	return String(box.call("publish_video",
		ProjectSettings.globalize_path(path), name))

func start(output: String, width: int, height: int, fps: int, bitrate: int,
		_crf: int, _profile: String, audio: bool, audio_rate: int = 48000,
		audio_channels: int = 2, _preset: String = "fast",
		audio_kbps: int = 192, container: String = "mp4", codec: String = "h264") -> bool:
	_last_error = ""
	_cancelled = false
	if container != "mp4" or codec != "h264":
		_last_error = "Android hardware export currently supports MP4/H.264 only"
		return false
	if not available():
		_last_error = "The Android media encoder is not available"
		return false
	_box = Engine.get_singleton(SINGLETON)
	# CRF, preset and profile are deliberately dropped rather than
	# approximated. MediaCodec has no constant-quality mode at all — it takes
	# a bitrate and nothing else — so pretending to honour a CRF here would be
	# a control that looks like it works and does not. The caller turns
	# quality into a bitrate before it gets this far.
	if not bool(_box.call("open", output, width, height, fps, bitrate, audio,
			audio_rate, audio_channels, audio_kbps)):
		_last_error = String(_box.call("last_error"))
		if _last_error == "":
			_last_error = "The encoder would not start"
		_box = null
		return false
	_encoder_name = String(_box.call("encoder_name"))
	return true

func push_frame(data: PackedByteArray, audio_pcm: PackedByteArray = PackedByteArray(),
		audio_samples: int = 0) -> bool:
	if _box == null or _cancelled:
		return false
	if not bool(_box.call("add_frame", data)):
		_last_error = String(_box.call("last_error"))
		return false
	if audio_samples > 0 and not audio_pcm.is_empty():
		if not bool(_box.call("add_audio", audio_pcm, audio_samples)):
			_last_error = String(_box.call("last_error"))
			return false
	return true

func cancel() -> void:
	_cancelled = true
	if _box != null:
		_box.call("cancel_export")
		_box = null

func finish() -> int:
	if _box == null:
		return 0 if _cancelled else -1
	var result: int = int(_box.call("finish"))
	if result != 0:
		_last_error = String(_box.call("last_error"))
	_box = null
	return result

func error_message() -> String:
	return _last_error

func get_last_error() -> String:
	return _last_error

func get_encoder_name() -> String:
	return _encoder_name

func was_cancelled() -> bool:
	return _cancelled

## Whether the chip did the work, rather than a software encoder wearing
## MediaCodec's clothes. Worth knowing: the software ones are slower than
## FFmpeg, not faster.
static func is_hardware() -> bool:
	if not available():
		return false
	return bool(Engine.get_singleton(SINGLETON).call("is_hardware"))
