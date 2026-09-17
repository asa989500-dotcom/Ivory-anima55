class_name CelTrack
extends RefCounted
## The drawings of one layer, one per frame, held in memory.
##
## This is the thing that was wrong before. Adding a frame used to add a
## layer, so a ten second scene meant two hundred and forty layers and a
## panel nobody could read. A frame is not a layer — it is the same layer at
## another moment, and it belongs here.
##
## Each cel is kept as a compressed image with the corner it sits at, so an
## empty frame costs almost nothing and a full one costs what its ink costs
## rather than the whole page. The layer keeps exactly one live surface; the
## playhead swaps what is in it.
##
## A cel holds until the next one. Draw on frame one and nothing else, and
## the whole clip shows that drawing — which is what a held pose is.

## Frame -> {"png": PackedByteArray, "at": Vector2i, "size": Vector2i}
var cels: Dictionary = {}
var _sorted_frames: Array[int] = []
var _frames_dirty: bool = true

## Which cel the live surface is currently holding, so it can be written
## back before another is loaded.
var loaded: int = -1

func _ensure_sorted() -> void:
	if not _frames_dirty:
		return
	_sorted_frames.clear()
	for key in cels.keys():
		_sorted_frames.append(int(key))
	_sorted_frames.sort()
	_frames_dirty = false

func frames() -> Array:
	_ensure_sorted()
	# Read-only by convention; callers only iterate this list. Avoiding a
	# duplicate here matters because the timeline asks for it every redraw.
	return _sorted_frames

## The furthest frame this layer has a drawing on, or -1 for none.
##
## The list is already kept in order, so this is the last item rather than a
## walk. It matters because the clip now asks every layer where it ends on
## every rendered frame of playback — an endless band has to work out where
## the scene really stops, and it must not cost a loop over every drawing in
## the scene to find out.
func last_frame() -> int:
	_ensure_sorted()
	if _sorted_frames.is_empty():
		return -1
	return _sorted_frames[_sorted_frames.size() - 1]

func has_frame(frame: int) -> bool:
	return cels.has(frame)

func is_empty() -> bool:
	return cels.is_empty()

## The cel showing at this moment: the latest one at or before it.
func frame_showing(at: int) -> int:
	_ensure_sorted()
	if _sorted_frames.is_empty():
		return -1
	# Binary search for the last key <= at. This keeps scrubbing/playback
	# effectively O(log n) even on long clips with hundreds of cels.
	var lo: int = 0
	var hi: int = _sorted_frames.size() - 1
	var best: int = -1
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		var value: int = _sorted_frames[mid]
		if value <= at:
			best = value
			lo = mid + 1
		else:
			hi = mid - 1
	return best

## How long a cel is held — to the next one, or to the end of the clip.
##
## Was a walk from the start of the list for every call, and the timeline
## called it once per drawing while drawing every drawing: a row of six
## hundred cels cost three hundred and sixty thousand comparisons per redraw,
## per layer, sixty times a second. That is where the band's slowness lived.
## The list is already sorted, so this is a binary search.
func hold_length(frame: int, clip_end: int) -> int:
	_ensure_sorted()
	var at: int = index_after(frame)
	if at < _sorted_frames.size():
		return maxi(_sorted_frames[at] - frame, 1)
	return maxi(clip_end - frame, 1)

## The position in `frames()` of the first drawing strictly after `frame`.
## `frames().size()` when there is none.
func index_after(frame: int) -> int:
	_ensure_sorted()
	var lo: int = 0
	var hi: int = _sorted_frames.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if _sorted_frames[mid] <= frame:
			lo = mid + 1
		else:
			hi = mid
	return lo

## The position in `frames()` of the first drawing at or after `frame`, so a
## reader that only cares about what is on screen can start there instead of
## walking the whole clip to reach it.
func index_at_or_after(frame: int) -> int:
	_ensure_sorted()
	var lo: int = 0
	var hi: int = _sorted_frames.size()
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if _sorted_frames[mid] < frame:
			lo = mid + 1
		else:
			hi = mid
	return lo

# ------------------------------------------------------------- the surface

## Writes whatever is on the surface into the cel it belongs to.
##
## Stored compressed rather than as raw pixels: a page of line art packs to
## a fraction of its size, and a scene is hundreds of these.
func commit(surface: PaintSurface) -> void:
	if surface == null or loaded < 0:
		return
	# Pending GPU stamps must be folded into the CPU mirror before the cel is
	# serialized; otherwise a very recent dab can disappear during a seek.
	surface.flush()
	var box: Rect2i = surface.content_bounds()
	if box.size.x <= 0 or box.size.y <= 0:
		_forget(loaded)
		cels[loaded] = {"png": PackedByteArray(), "at": Vector2i.ZERO,
			"size": Vector2i.ZERO}
		_frames_dirty = true
		return
	var img: Image = surface.read_region(box)
	if img == null:
		return
	_forget(loaded)
	cels[loaded] = {"png": img.save_png_to_buffer(), "at": box.position,
		"size": box.size}
	_forget_cache(loaded)
	_frames_dirty = true

## The last image handed out, so scrubbing back and forth over the same few
## drawings does not decompress them again each time. Small on purpose: the
## point is the handful of frames a hand moves between, not the whole clip.
const CACHE: int = 6
var _cache: Dictionary = {}
var _cache_order: Array = []

func _cached(frame: int) -> Image:
	if _cache.has(frame):
		return _cache[frame]
	var img: Image = image_of(frame)
	if img == null:
		return null
	_cache[frame] = img
	_cache_order.append(frame)
	while _cache_order.size() > CACHE:
		_cache.erase(_cache_order.pop_front())
	return img

func _forget_cache(frame: int) -> void:
	_cache.erase(frame)
	_cache_order.erase(frame)

## Releases decompressed cel Images that are no longer useful. The PNG bytes
## remain authoritative, so pruning trades RAM for a future decode only.
func prune_cache(keep_frames: Array = []) -> void:
	var keep: Dictionary = {}
	for f in keep_frames:
		keep[int(f)] = true
	var i: int = 0
	while i < _cache_order.size():
		var frame: int = int(_cache_order[i])
		if keep.has(frame):
			i += 1
			continue
		_cache.erase(frame)
		_cache_order.remove_at(i)

func cache_bytes_estimate() -> int:
	var total: int = 0
	for frame in _cache.keys():
		var img: Image = _cache[frame]
		if img != null:
			total += img.get_width() * img.get_height() * 4
	return total

## Puts a cel onto the surface, replacing what was there.
func capture_surface(surface: PaintSurface, frame: int) -> void:
	if surface == null:
		return
	surface.flush()
	var box: Rect2i = surface.content_bounds()
	if box.size.x <= 0 or box.size.y <= 0:
		_forget(frame)
		cels[frame] = {"png": PackedByteArray(), "at": Vector2i.ZERO,
			"size": Vector2i.ZERO}
	else:
		var img: Image = surface.read_region(box)
		if img == null:
			return
		_forget(frame)
		cels[frame] = {"png": img.save_png_to_buffer(), "at": box.position,
			"size": box.size}
	_frames_dirty = true
	loaded = frame

func load_into(surface: PaintSurface, frame: int) -> void:
	if surface == null:
		return
	surface.clear_all()
	loaded = frame
	if not cels.has(frame):
		return
	_page_in(frame)
	var cel: Dictionary = cels[frame]
	if (cel["png"] as PackedByteArray).is_empty():
		return
	# Through the cache: flipping back and forth across a few drawings is
	# what an animator does constantly, and decompressing the same PNG on
	# every flip is what makes that feel sticky.
	var img: Image = _cached(frame)
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Written premultiplied, read back premultiplied, copied not blended —
	# so a frame looks the same however often it is swapped in and out.
	surface.blit_image(img, Vector2(cel["at"] as Vector2i), true)

## Moves the surface to the cel that should be showing, writing back first.
## Returns true when anything actually changed.
func show_frame(surface: PaintSurface, at: int, write_back: bool = true) -> bool:
	# A layer that has never entered animation must keep its ordinary static
	# drawing. The timeline should not erase it merely because the playhead
	# exists. Once the first cel is created, cels take ownership of the layer.
	if cels.is_empty():
		return false
	var want: int = frame_showing(at)
	if want < 0:
		if loaded == -1:
			return false
		if write_back:
			commit(surface)
		surface.clear_all()
		loaded = -1
		return true
	if want == loaded:
		return false
	if write_back:
		commit(surface)
	load_into(surface, want)
	return true

# ------------------------------------------------------------------- edits

## A new cel at this frame. `copy_previous` starts it from the drawing
## before it, which is what tracing a movement wants; otherwise it is blank,
## which is what starting a fresh pose wants.
func add_frame(surface: PaintSurface, frame: int, copy_previous: bool) -> void:
	commit(surface)
	if copy_previous:
		var from: int = frame_showing(frame - 1)
		if from >= 0 and cels.has(from):
			cels[frame] = (cels[from] as Dictionary).duplicate(true)
			_frames_dirty = true
		else:
			cels[frame] = {"png": PackedByteArray(), "at": Vector2i.ZERO,
				"size": Vector2i.ZERO}
	else:
		cels[frame] = {"png": PackedByteArray(), "at": Vector2i.ZERO,
			"size": Vector2i.ZERO}
	_frames_dirty = true
	load_into(surface, frame)

## Inserts a blank cel immediately after `frame`. Any existing cels at or
## after that position slide one frame to the right, preserving the exact
## drawing order and holds.
func insert_blank_after(surface: PaintSurface, frame: int) -> void:
	if surface != null:
		commit(surface)
	var insert_at: int = maxi(frame + 1, 0)
	var order: Array = frames().duplicate()
	order.reverse()
	for key in order:
		var old_frame: int = int(key)
		if old_frame < insert_at:
			continue
		var cel: Variant = cels[old_frame]
		cels.erase(old_frame)
		cels[old_frame + 1] = cel
		_forget_cache(old_frame)
		_frames_dirty = true
		if loaded == old_frame:
			loaded = old_frame + 1
	cels[insert_at] = {"png": PackedByteArray(), "at": Vector2i.ZERO,
		"size": Vector2i.ZERO}
	_frames_dirty = true
	loaded = insert_at
	if surface != null:
		surface.clear_all()

func remove_frame(frame: int) -> void:
	cels.erase(frame)
	_forget_cache(frame)
	_frames_dirty = true
	if loaded == frame:
		loaded = -1

## Slides a cel to another frame, and everything after it along with it when
## a hold is being lengthened.
func move_frame(from: int, to: int) -> void:
	if from == to or not cels.has(from):
		return
	var cel: Variant = cels[from]
	cels.erase(from)
	cels[to] = cel
	_forget_cache(from)
	_forget_cache(to)
	_frames_dirty = true
	if loaded == from:
		loaded = to

## Slides everything after a frame along, which is what lengthening a hold
## does to the drawings that follow it.
##
## The list is copied first. `frames()` hands back the track's own sorted
## cache rather than a copy — reversing it in place left that cache in the
## wrong order while the cels were being moved underneath it, and a frame
## could land on top of another one.
func shift_after(frame: int, by: int) -> void:
	if by == 0:
		return
	var order: Array = frames().duplicate()
	if by > 0:
		order.reverse()
	for f in order:
		var one: int = int(f)
		if one <= frame:
			continue
		var cel: Variant = cels[one]
		var to: int = maxi(one + by, frame + 1)
		if to == one:
			continue
		cels.erase(one)
		cels[to] = cel
		_forget_cache(one)
		_forget_cache(to)
		if loaded == one:
			loaded = to
		_frames_dirty = true

# --------------------------------------------------------------- paging out

## Where cels that are far from the playhead are kept while they wait.
##
## A cel is already a compressed PNG in memory rather than a raw image, so a
## drawing costs what its ink costs and not what its page costs. That is why
## this is a refinement and not a rescue — but a six-hundred frame scene with
## eight layers is still four and a half thousand of them, and at a few hundred
## kilobytes each that is more than a tablet will give one application.
##
## So the ones nowhere near the playhead go to disk. They come back the moment
## anything asks for them, and nothing outside this file needs to know it
## happened: every reader below goes through `_page_in` first.
const SPILL_ROOT: String = "user://cels"

## How many frames either side of the playhead stay resident.
##
## Generous on purpose. Flipping back and forth across a few drawings is what
## an animator does constantly, and a cel that has to come off disk to be seen
## is a cel that makes that flip stutter. Ninety-six either side covers four
## seconds at twenty-four in both directions — well past what a hand flips
## through — and everything beyond it is being scrubbed to, not flipped to.
const KEEP_NEAR: int = 96

## Not worth a file: the read back would cost more than the bytes save.
const SPILL_MIN: int = 8192

## The ceiling on how much of a device's storage this may hold at once.
##
## It had none. Every cel far from the playhead was written out, for as long
## as the session lasted, on a tablet whose free space nobody had asked about
## — and a full disk on Android does not report itself politely, it makes the
## next save fail. Past this figure the spilling simply stops and the cels
## stay in memory, which is the milder of the two failures: the app gets
## heavier, rather than the user losing a page.
##
## A static var rather than a const because the benchmark lowers it on a
## device that turned out to write slowly (see `perf_bench.gd`).
static var spill_budget: int = 192 * 1024 * 1024

## This run's own folder. Everything written goes inside it, which is what
## makes the crash cleanup below possible: a folder that is not this one
## belongs to a run that is over.
static var _session_dir: String = ""
static var _spill_seq: int = 0
static var _spilled_bytes: int = 0
## How many times the budget refused a write, so the report can say so.
static var _spill_refused: int = 0
static var _swept: bool = false

static func _ensure_spill() -> void:
	if _session_dir != "":
		return
	DirAccess.make_dir_recursive_absolute(SPILL_ROOT)
	# The process id is in the name so a second copy of the app — which only
	# happens on a desktop — cannot be mistaken for a dead one below.
	_session_dir = "%s/run_%d_%d" % [SPILL_ROOT, OS.get_process_id(),
		int(Time.get_unix_time_from_system())]
	DirAccess.make_dir_recursive_absolute(_session_dir)
	var mark: FileAccess = FileAccess.open(_session_dir + "/pid",
		FileAccess.WRITE)
	if mark != null:
		mark.store_string(str(OS.get_process_id()))
		mark.close()
	sweep_orphans()

## Removes everything left behind by a run that ended without tidying up.
##
## This is the fix for the real complaint: the app died mid-session and its
## cels stayed on the device for ever, because the only cleanup there was ran
## when a track was disposed of properly. A crash disposes of nothing.
##
## The rule is simple enough to be certain of. A folder under `user://cels`
## belongs to one run of the app. If it is not this run's folder, and the
## process it names is not running, then whoever wrote it is gone and the
## drawings inside it were already saved into the project file or were never
## going to be. It is removed.
##
## Loose files directly in the root are removed too. That is the layout every
## build up to this one used, so this is also what clears whatever has piled
## up on the device already.
##
## Returns how many files it deleted, so a test can assert on it.
static func sweep_orphans() -> int:
	if _swept:
		return 0
	_swept = true
	DirAccess.make_dir_recursive_absolute(SPILL_ROOT)
	var removed: int = 0
	var dir: DirAccess = DirAccess.open(SPILL_ROOT)
	if dir == null:
		return 0
	for name in dir.get_files():
		# The old flat layout, and any half-written `.part` file.
		if DirAccess.remove_absolute(SPILL_ROOT + "/" + name) == OK:
			removed += 1
	for name in dir.get_directories():
		var path: String = SPILL_ROOT + "/" + name
		if path == _session_dir:
			continue
		if _still_running(path):
			continue
		removed += _remove_tree(path)
	return removed

## Whether the run that owns this folder is still going.
##
## On Android the answer is always no — the system does not let a second copy
## of an app exist, so any folder that is not ours is by definition finished.
## The check earns its place on a desktop, where two editors can be open on
## the same project and neither should delete the other's working set.
static func _still_running(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path + "/pid", FileAccess.READ)
	if f == null:
		return false
	var pid: int = int(f.get_as_text().strip_edges())
	f.close()
	if pid <= 0 or pid == OS.get_process_id():
		return false
	return OS.is_process_running(pid)

static func _remove_tree(path: String) -> int:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return 0
	var removed: int = 0
	for name in dir.get_files():
		if DirAccess.remove_absolute(path + "/" + name) == OK:
			removed += 1
	for name in dir.get_directories():
		removed += _remove_tree(path + "/" + name)
	DirAccess.remove_absolute(path)
	return removed

## Called on the way out, so an ordinary exit leaves nothing behind and the
## sweep above has nothing to do next time.
static func close_session() -> void:
	if _session_dir == "":
		return
	_remove_tree(_session_dir)
	_spilled_bytes = 0
	_session_dir = ""

## What the spill is costing, for the diagnostics sheet and for the tests.
static func spill_report() -> Dictionary:
	return {
		"dir": _session_dir,
		"bytes": _spilled_bytes,
		"budget": spill_budget,
		"refused": _spill_refused,
	}

## A track that is being collected takes its files with it.
##
## `drop_spill` was only ever called from one place in `layer_stack`, so a
## track dropped any other way — a project closed, an undo that replaced a
## layer, a load that threw the old stack away — left its files behind for the
## rest of the session. This closes that hole without every caller having to
## remember.
##
## The cleanup is written out here rather than as a call to `drop_spill()`.
## By the time NOTIFICATION_PREDELETE reaches a RefCounted, its script
## binding is already coming apart, and dispatching a *further* method call
## on `self` at that exact moment is what Godot was reporting as "drop_spill
## in base 'null instance'" — the instance the call needed was already gone,
## even though the object sending the notification was still very much here.
## Every animation project built one of these per layer, so the moment a
## layer was replaced — an undo, a load, a copy — this fired, threw that
## error, and cut the rest of the surrounding call short: layer setup that
## still had steps to run after freeing the old track never finished them,
## which is why the brush went quiet in Animation and nowhere else. Running
## the same loop directly in this frame, instead of asking `self` to run it,
## needs nothing from the script instance that is being torn down.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	for key in cels.keys():
		var cel: Dictionary = cels[key]
		var path: String = String(cel.get("spill", ""))
		if path != "":
			DirAccess.remove_absolute(path)
			_spilled_bytes = maxi(
				_spilled_bytes - int(cel.get("spill_bytes", 0)), 0)
			cel["spill"] = ""
			cel["spill_bytes"] = 0

## Brings a cel back from disk if that is where it is.
##
## Called by every reader before it touches `png`. Cheap when the cel is
## resident, which is the overwhelming majority of calls — one dictionary
## lookup and a branch.
func _page_in(frame: int) -> void:
	if not cels.has(frame):
		return
	var cel: Dictionary = cels[frame]
	var path: String = String(cel.get("spill", ""))
	if path == "" or not (cel["png"] as PackedByteArray).is_empty():
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		# The file is gone — a cleared cache, a wiped user folder. An empty
		# cel is the honest answer and it is what the frame will look like;
		# inventing pixels would be worse, and crashing far worse than that.
		_spilled_bytes = maxi(_spilled_bytes - int(cel.get("spill_bytes", 0)), 0)
		cel["spill"] = ""
		cel["spill_bytes"] = 0
		return
	cel["png"] = f.get_buffer(f.get_length())
	f.close()
	# The path is kept. If this cel is paged out again unchanged, the bytes
	# are already on disk and there is nothing to write.

## Sends everything far from `frame` to disk.
##
## Called from the playhead, so the working set follows the animator around the
## clip. Cels are written once and only rewritten when they change — `_forget`
## clears the path whenever a cel is replaced — so scrubbing back and forth
## over a settled scene costs reads and no writes at all.
func page_around(frame: int, radius: int = KEEP_NEAR) -> void:
	if cels.size() <= 8:
		return
	_ensure_spill()
	for key in cels.keys():
		var f: int = int(key)
		if absi(f - frame) <= radius or f == loaded:
			continue
		var cel: Dictionary = cels[f]
		var png: PackedByteArray = cel["png"]
		if png.is_empty():
			continue
		if png.size() < SPILL_MIN:
			continue
		var path: String = String(cel.get("spill", ""))
		if path == "":
			if _spilled_bytes + png.size() > spill_budget:
				# Over the ceiling. The cel stays in memory: heavier, and
				# still the user's drawing.
				_spill_refused += 1
				continue
			path = _write_spill(png)
			if path == "":
				continue
			cel["spill"] = path
			cel["spill_bytes"] = png.size()
			_spilled_bytes += png.size()
		cel["png"] = PackedByteArray()

## One cel written to disk, or "" if it could not be.
##
## Through a `.part` file and a rename, because a write that is interrupted
## half way — the app killed, the battery gone — otherwise leaves a truncated
## PNG that `_page_in` will happily read back as a corrupt drawing. A rename
## is atomic: the final name either exists complete or does not exist.
func _write_spill(png: PackedByteArray) -> String:
	_spill_seq += 1
	var final_path: String = "%s/cel_%d.png" % [_session_dir, _spill_seq]
	var part: String = final_path + ".part"
	var out: FileAccess = FileAccess.open(part, FileAccess.WRITE)
	if out == null:
		return ""
	out.store_buffer(png)
	out.close()
	if DirAccess.rename_absolute(part, final_path) != OK:
		DirAccess.remove_absolute(part)
		return ""
	return final_path

## A cel is about to be replaced, so whatever is on disk for it is stale.
func _forget(frame: int) -> void:
	if not cels.has(frame):
		return
	var cel: Dictionary = cels[frame]
	var path: String = String(cel.get("spill", ""))
	if path != "":
		DirAccess.remove_absolute(path)
		_spilled_bytes = maxi(_spilled_bytes - int(cel.get("spill_bytes", 0)), 0)
		cel["spill"] = ""
		cel["spill_bytes"] = 0

## Everything this track spilled, removed.
##
## Called when the track itself goes. Without it the folder grows by one file
## per cel per session and nothing ever takes them away — the exact "clearing
## memory only frees it temporarily" complaint, one level down.
func drop_spill() -> void:
	for key in cels.keys():
		var cel: Dictionary = cels[key]
		var path: String = String(cel.get("spill", ""))
		if path != "":
			DirAccess.remove_absolute(path)
			_spilled_bytes = maxi(
				_spilled_bytes - int(cel.get("spill_bytes", 0)), 0)
			cel["spill"] = ""
			cel["spill_bytes"] = 0

## A picture of one cel, for the timeline's row and for onion skins. Nothing
## is decompressed twice: the caller keeps what it is given.
func image_of(frame: int) -> Image:
	if not cels.has(frame):
		return null
	_page_in(frame)
	var cel: Dictionary = cels[frame]
	var png: PackedByteArray = cel["png"]
	if png.is_empty():
		return null
	var img: Image = Image.new()
	if img.load_png_from_buffer(png) != OK:
		return null
	return img

func origin_of(frame: int) -> Vector2i:
	if not cels.has(frame):
		return Vector2i.ZERO
	return (cels[frame] as Dictionary)["at"]

## Roughly what this track is costing, so the timeline can say so honestly.
## Only what is actually resident — a cel on disk is not costing memory, and
## reporting it as though it were would make the figure a lie in the one
## direction that matters.
func bytes() -> int:
	var total: int = 0
	for f in cels.keys():
		total += (cels[f]["png"] as PackedByteArray).size()
	return total

# ------------------------------------------------------------------ saving

func to_dict() -> Dictionary:
	var rows: Array = []
	for f in frames():
		_page_in(f)
		var cel: Dictionary = cels[f]
		# An empty cel has nothing to encode, and handing empty bytes to
		# Marshalls is what printed
		#     to_dict(): Condition "ret.is_empty()" is true
		# on every save. A frame with no pixels is a frame with no pixels;
		# it is written as a hole and read back as one.
		var raw: PackedByteArray = cel["png"]
		if raw.is_empty():
			continue
		rows.append({
			"f": int(f),
			"x": (cel["at"] as Vector2i).x,
			"y": (cel["at"] as Vector2i).y,
			"png": Marshalls.raw_to_base64(raw),
		})
	return {"cels": rows}

func from_dict(doc: Dictionary) -> void:
	cels.clear()
	_frames_dirty = true
	loaded = -1
	for row in doc.get("cels", []):
		cels[int(row.get("f", 0))] = {
			"png": Marshalls.base64_to_raw(String(row.get("png", ""))),
			"at": Vector2i(int(row.get("x", 0)), int(row.get("y", 0))),
			"size": Vector2i.ZERO,
		}
