class_name PerfBench
extends RefCounted
## Measures this device, once, so `Perf` stops guessing.
##
## The honest account of what was here before: every number in `Perf` was
## written from a sense of what felt reasonable. Six tiles woken per frame on
## a middling device, nine hundred dabs before folding, ninety-six megapixels
## for a picture. None of them had ever been timed on anything. They may have
## been close; nobody could say, and a number nobody can defend is a number
## that quietly decides how the app behaves on every device it will ever run
## on.
##
## What this does instead is time the four operations the app actually spends
## its frames inside — allocating a picture, decoding a cel, compositing one
## picture onto another, and writing to storage — and hand `Perf` real
## microseconds. The budgets are then arithmetic rather than opinion: if a
## tile takes 4 ms to decode and the frame may spend 3 ms decoding tiles, the
## answer is one tile, and it is one tile because that is what the numbers
## say.
##
## It runs once per device per app version, takes well under a tenth of a
## second, and writes what it found to `user://perf_profile.json` so the
## second launch is free. `Perf.report()` prints the lot, which means a
## problem on a device I will never hold can be described to me in figures.

const PROFILE_PATH: String = "user://perf_profile.json"
## Bumped whenever the measurements or their meaning change, so an old
## profile is re-measured rather than misread.
const PROFILE_VERSION: int = 1

## The sizes are the app's real ones, not round numbers: a tile is what the
## canvas is made of, and a cel is what a frame of animation weighs.
const TILE: int = 256
const PAGE: int = 512

## What a measurement of this device looks like. Times are microseconds.
##
##   alloc_us    create + clear one page-sized RGBA image
##   encode_us   compress one tile as PNG — what committing a cel costs
##   decode_us   decompress one tile — what waking a sleeping tile costs
##   blit_us     composite one tile onto a page — the layer flatten inner loop
##   disk_us     write and read back 256 KB of user:// — what a spill costs
##   loop_us     a fixed arithmetic loop — how fast this device runs script
static func run() -> Dictionary:
	var out: Dictionary = {
		"v": PROFILE_VERSION,
		"model": OS.get_model_name(),
		"os": OS.get_name(),
		"processors": OS.get_processor_count(),
		"when": int(Time.get_unix_time_from_system()),
	}
	out["alloc_us"] = _time_alloc()
	var codec: Dictionary = _time_codec()
	out["encode_us"] = codec["encode"]
	out["decode_us"] = codec["decode"]
	out["blit_us"] = _time_blit()
	out["disk_us"] = _time_disk()
	out["loop_us"] = _time_loop()
	out["memory_mb"] = _physical_memory_mb()
	return out

static func _time_alloc() -> int:
	var start: int = Time.get_ticks_usec()
	for _i in range(4):
		var img: Image = Image.create_empty(PAGE, PAGE, false,
			Image.FORMAT_RGBA8)
		img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return int(float(Time.get_ticks_usec() - start) / 4.0)

## Encode and decode a tile that looks like drawing rather than like noise
## or like flat colour, because PNG's cost depends entirely on that: a blank
## tile compresses to nothing and would time as free, and random pixels
## compress to nothing at all and would time as a disaster. Neither is a cel.
static func _time_codec() -> Dictionary:
	var img: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(0, TILE, 7):
		for x in range(TILE):
			img.set_pixel(x, y, Color(0.06, 0.06, 0.08, 1.0))
	for x in range(0, TILE, 11):
		for y in range(TILE):
			img.set_pixel(x, y, Color(0.85, 0.80, 0.70, 0.9))

	var start: int = Time.get_ticks_usec()
	var png: PackedByteArray = img.save_png_to_buffer()
	var encode: int = Time.get_ticks_usec() - start

	start = Time.get_ticks_usec()
	var back: Image = Image.new()
	back.load_png_from_buffer(png)
	var decode: int = Time.get_ticks_usec() - start

	return {"encode": encode, "decode": decode, "bytes": png.size()}

static func _time_blit() -> int:
	var page: Image = Image.create_empty(PAGE, PAGE, false, Image.FORMAT_RGBA8)
	page.fill(Color(0.0, 0.0, 0.0, 0.0))
	var tile: Image = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	tile.fill(Color(0.5, 0.4, 0.3, 0.5))
	var box: Rect2i = Rect2i(0, 0, TILE, TILE)
	var start: int = Time.get_ticks_usec()
	for i in range(4):
		# Four tiles in a two-by-two square: the column is i modulo two and
		# the row is i halved, whole. Written as a float divide and floored so
		# the intent is on the page rather than in a warning.
		var column: int = i % 2
		var row: int = int(float(i) / 2.0)
		page.blend_rect(tile, box, Vector2i(column * TILE, row * TILE))
	return int(float(Time.get_ticks_usec() - start) / 4.0)

## Writing is what the cel spill does, and it is the one measurement that can
## come back catastrophically slow — external storage on an old device, or a
## disk with nothing left on it. If it does, `Perf` lowers the spill ceiling
## and the app carries its cels in memory instead.
static func _time_disk() -> int:
	var payload: PackedByteArray = PackedByteArray()
	payload.resize(256 * 1024)
	payload.fill(0x42)
	var path: String = "user://.perf_probe"
	var start: int = Time.get_ticks_usec()
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return -1
	out.store_buffer(payload)
	out.close()
	var back: FileAccess = FileAccess.open(path, FileAccess.READ)
	if back == null:
		return -1
	var read: PackedByteArray = back.get_buffer(back.get_length())
	back.close()
	var spent: int = Time.get_ticks_usec() - start
	DirAccess.remove_absolute(path)
	if read.size() != payload.size():
		return -1
	return spent

static func _time_loop() -> int:
	var start: int = Time.get_ticks_usec()
	var total: float = 0.0
	for i in range(20000):
		total += sqrt(float(i)) * 0.5
	# Used, so no optimiser anywhere can decide the loop did not happen.
	if total < 0.0:
		return -1
	return Time.get_ticks_usec() - start

static func _physical_memory_mb() -> int:
	var info: Dictionary = OS.get_memory_info()
	var physical: int = int(info.get("physical", -1))
	if physical <= 0:
		return -1
	return int(float(physical) / 1048576.0)

# ------------------------------------------------------------------ storage

static func load_profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var f: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = parsed
	if int(doc.get("v", 0)) != PROFILE_VERSION:
		return {}
	return doc

static func save_profile(doc: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(doc, "  "))
	f.close()

## Wipes the stored profile, so the next launch measures again. Offered in
## the diagnostics sheet, because a device that was hot and throttling when
## it was first measured deserves a second opinion.
static func forget_profile() -> void:
	DirAccess.remove_absolute(PROFILE_PATH)

## The measurement, from storage if it is there and by measuring if it is not.
static func obtain(force: bool = false) -> Dictionary:
	if not force:
		var stored: Dictionary = load_profile()
		if not stored.is_empty():
			return stored
	var fresh: Dictionary = run()
	save_profile(fresh)
	return fresh

## The measurement as a few lines a person can read out to someone else.
static func describe(doc: Dictionary) -> String:
	if doc.is_empty():
		return "not measured"
	var lines: Array = []
	lines.append("device   %s (%s, %d cores, %d MB)" % [
		String(doc.get("model", "?")), String(doc.get("os", "?")),
		int(doc.get("processors", 0)), int(doc.get("memory_mb", -1))])
	lines.append("alloc    %.2f ms   a %dx%d page created and cleared"
		% [float(doc.get("alloc_us", 0)) / 1000.0, PAGE, PAGE])
	lines.append("decode   %.2f ms   one %d px tile off PNG"
		% [float(doc.get("decode_us", 0)) / 1000.0, TILE])
	lines.append("encode   %.2f ms   one %d px tile into PNG"
		% [float(doc.get("encode_us", 0)) / 1000.0, TILE])
	lines.append("blit     %.2f ms   one tile composited onto a page"
		% [float(doc.get("blit_us", 0)) / 1000.0])
	lines.append("disk     %.2f ms   256 KB written and read back"
		% [float(doc.get("disk_us", 0)) / 1000.0])
	lines.append("script   %.2f ms   20,000 arithmetic steps"
		% [float(doc.get("loop_us", 0)) / 1000.0])
	return "\n".join(lines)
