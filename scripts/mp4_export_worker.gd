class_name MP4ExportWorker
extends RefCounted

## One-slot producer/consumer bridge. The timeline is rendered on Godot's main
## thread because its canvas state is not thread-safe; FFmpeg encoding happens
## on this worker thread, so the UI is never held inside avcodec.
var _thread: Thread = Thread.new()
var _items: Semaphore = Semaphore.new()
var _slots: Semaphore = Semaphore.new()
var _free_slots: Semaphore = Semaphore.new()
var _frame_pool: Array = []
var _pool_indices: Array = []
var _frame_slot_index: int = -1
var _mutex: Mutex = Mutex.new()
var _frame: PackedByteArray = PackedByteArray()
var _audio_pcm: PackedByteArray = PackedByteArray()
var _audio_samples: int = 0
var _finish: bool = false
var _cancel: bool = false
var _error: int = 0
var _output: String = ""
var _width: int = 0
var _height: int = 0
var _encoder_name: String = ""
var _native_error: String = ""
var _fps: int = 24
var _bitrate: int = 0
var _crf: int = 20
var _profile: String = "high"
var _audio: bool = false
var _audio_rate: int = 48000
var _audio_channels: int = 2
## How hard the software encoder is allowed to think, and how much room the
## sound gets. Both are passed through to the native encoder when the
## library is new enough to take them, and quietly dropped when it is not —
## see `_run`, which asks the encoder what it understands rather than
## assuming.
var _preset: String = "fast"
var _audio_kbps: int = 192
var _last_error: String = ""
var _container: String = "mp4"
var _codec: String = "h264"

func start(output: String, width: int, height: int, fps: int, bitrate: int,
		crf: int, profile: String, audio: bool, audio_rate: int = 48000,
		audio_channels: int = 2, preset: String = "fast",
		audio_kbps: int = 192, container: String = "mp4", codec: String = "h264") -> bool:
	_output = output
	_width = width
	_height = height
	_fps = fps
	_container = container
	_codec = codec
	_mutex.lock()
	_native_error = ""
	_encoder_name = ""
	_error = 0
	_finish = false
	_cancel = false
	_mutex.unlock()
	_frame_pool.clear()
	_pool_indices.clear()
	_frame_slot_index = -1
	# Three slots rather than two. With two, the renderer stalls whenever the
	# encoder is mid-frame; a third lets one frame be encoded, one wait, and
	# one be filled, which is what keeps both threads busy on a long export.
	for i in 3:
		var slot: PackedByteArray = PackedByteArray()
		slot.resize(width * height * 4)
		_frame_pool.append(slot)
		_pool_indices.append(i)
		_free_slots.post()
	_bitrate = bitrate
	_crf = crf
	_profile = profile
	_audio = audio
	_audio_rate = audio_rate
	_audio_channels = audio_channels
	_preset = preset
	_audio_kbps = audio_kbps
	_slots.post()
	return _thread.start(_run) == OK

func push_frame(data: PackedByteArray, audio_pcm: PackedByteArray = PackedByteArray(), audio_samples: int = 0) -> bool:
	_mutex.lock()
	var cancelled := _cancel or _error != 0
	_mutex.unlock()
	if cancelled:
		return false
	_free_slots.wait()
	_mutex.lock()
	if _cancel or _error != 0:
		_mutex.unlock(); _free_slots.post(); return false
	var slot_index: int = int(_pool_indices.pop_back())
	# PackedByteArray has no copy_from() (that's an Image method); duplicate()
	# is the correct way to get an independent copy of the bytes into the
	# pooled slot without aliasing the caller's array.
	var slot: PackedByteArray = data.duplicate()
	_frame_pool[slot_index] = slot
	_frame = slot
	_frame_slot_index = slot_index
	_audio_pcm = audio_pcm
	_audio_samples = audio_samples
	_mutex.unlock()
	_items.post()
	return true

func cancel() -> void:
	_mutex.lock(); _cancel = true; _mutex.unlock()
	_items.post(); _free_slots.post()

func finish() -> int:
	_mutex.lock(); _finish = true; _mutex.unlock()
	_items.post()
	if _thread.is_started():
		_thread.wait_to_finish()
	return _error

func error_message() -> String:
	return _last_error

func get_last_error() -> String:
	_mutex.lock(); var x := _native_error; _mutex.unlock(); return x

func get_encoder_name() -> String:
	_mutex.lock(); var x := _encoder_name; _mutex.unlock(); return x

func was_cancelled() -> bool:
	_mutex.lock(); var x := _cancel; _mutex.unlock(); return x

func _run() -> void:
	var encoder: Object = null
	if not ClassDB.class_exists("GoZenMP4Encoder"):
		_mutex.lock(); _error = -100; _last_error = "H.264 encoder unavailable: GoZen native extension is missing"; _native_error = _last_error; _mutex.unlock(); return
	encoder = ClassDB.instantiate("GoZenMP4Encoder")
	if encoder == null:
		_mutex.lock(); _error = -101; _last_error = "H.264 encoder unavailable"; _native_error = _last_error; _mutex.unlock(); return
	# The native library grew two settings — the software encoder's preset and
	# the sound's bitrate — and a build made before that will not take them.
	# It is asked rather than assumed, so a freshly written app still runs on
	# a library that was compiled last month.
	var wide: bool = false
	if encoder.has_method("capabilities"):
		var caps: Dictionary = encoder.capabilities()
		wide = bool(caps.get("tuned", false))
	var open_result: int = 0
	if wide:
		open_result = int(encoder.open(_output, _width, _height, _fps,
			_bitrate, _crf, _profile, _audio, _audio_rate, _audio_channels,
			_preset, _audio_kbps, _container, _codec))
	else:
		open_result = int(encoder.open(_output, _width, _height, _fps,
			_bitrate, _crf, _profile, _audio, _audio_rate, _audio_channels))
	if open_result != 0:
		_mutex.lock(); _error = open_result; _last_error = str(encoder.get_last_error()); _native_error = _last_error; _mutex.unlock(); return

	while true:
		_items.wait()
		_mutex.lock()
		var done := _finish
		var cancelled := _cancel
		var data := _frame
		var audio_pcm := _audio_pcm
		var audio_samples := _audio_samples
		_frame = PackedByteArray(); _audio_pcm = PackedByteArray(); _audio_samples = 0
		_mutex.unlock()
		if cancelled:
			encoder.close()
			return
		if data.is_empty() and done:
			break
		if not data.is_empty():
			var r := int(encoder.add_frame(data))
			if r == 0 and _audio and audio_samples > 0 and not audio_pcm.is_empty():
				r = int(encoder.add_audio_s16(audio_pcm, audio_samples))
			_mutex.lock()
			if _frame_slot_index >= 0:
				_pool_indices.append(_frame_slot_index); _frame_slot_index = -1
			_mutex.unlock()
			_free_slots.post()
			if r != 0:
				_mutex.lock(); _error = r; _last_error = str(encoder.get_last_error()); _native_error = _last_error; _mutex.unlock(); encoder.close(); return
		if done:
			break

	var result := int(encoder.finish())
	_mutex.lock(); _error = result; _last_error = str(encoder.get_last_error()); _native_error = _last_error; _mutex.unlock()
