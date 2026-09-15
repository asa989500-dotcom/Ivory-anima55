class_name TimelineIndex
extends RefCounted
## Where every layer's drawings are, worked out once instead of per redraw.
##
## ## What was costing what
##
## Not what it looked like. `CelTrack` is already careful: its frame list is
## kept sorted, "which drawing is showing" is a binary search, and the band
## already begins its per-row walk at the first drawing the eye can reach. Each
## of those is fast, and none of them was the problem.
##
## The cost was asking them *once per layer, from GDScript, on every redraw*.
## `Clip.last_event` walks every layer to find where the scene ends, and it is
## called from `refresh` and again from `play_span` on every rendered frame. A
## two-hundred-layer scene playing at sixty frames a second makes twelve
## thousand bound calls a second before a single pixel is drawn, and the work
## inside each call is a handful of comparisons — the call costs more than the
## work.
##
## So this holds the answers and rebuilds them only when the drawings actually
## change. `IvoryTimelineIndex` does the arithmetic when the extension is
## built; the same answers are computed here in GDScript when it is not.
##
## ## What invalidates it
##
## A drawing added, removed or moved. Not a pose, not a selection, not a
## repaint — a cel's *position on the band* is the only thing any of these
## answers depend on. `LayerStack.changed` covers all of it and is already
## emitted for every one of those cases.

var _native: Object = null
var _frames: PackedInt32Array = PackedInt32Array()
var _starts: PackedInt32Array = PackedInt32Array()
var _end: int = -1
var _built: bool = false

func _init() -> void:
	_native = Native.timeline_index()

## True when the compiled engine is doing the arithmetic. For the diagnostics
## room only; nothing branches on it.
func native() -> bool:
	return _native != null

## Throws the answers away. Cheap — the rebuild is deferred to the next
## question, so a burst of changes costs one rebuild rather than one each.
func forget() -> void:
	_built = false

## Reads every layer's frame list into one flat block.
##
## Compressed sparse row: `_frames` holds every layer's sorted frame numbers
## end to end, and `_starts` says where each layer's run begins, with one extra
## entry so the last layer's length is a subtraction like everyone else's. No
## array of arrays and no allocation per layer.
func rebuild(stack: LayerStack) -> void:
	_frames = PackedInt32Array()
	_starts = PackedInt32Array()
	_starts.append(0)
	_end = -1
	if stack == null:
		_built = true
		return
	for l in stack.layers:
		if l.cels != null:
			for f in l.cels.frames():
				var frame: int = int(f)
				_frames.append(frame)
				if frame > _end:
					_end = frame
		_starts.append(_frames.size())
	if _native != null:
		# Refused rather than trusted: the engine checks that every layer's
		# list is ascending, because a binary search over an unsorted list does
		# not run slowly, it returns the wrong drawing.
		if not _native.set_tracks(_frames, _starts):
			_native = null
	_built = true

func _ensure(stack: LayerStack) -> void:
	if not _built:
		rebuild(stack)

## The last frame anything is drawn on, or -1 for an empty scene.
##
## This is the one `Clip.last_event` was walking every layer for, on every
## redraw and on every rendered frame of playback.
func scene_end(stack: LayerStack) -> int:
	_ensure(stack)
	if _native != null:
		return _native.scene_end()
	return _end

## Which drawing each layer is showing at this moment, one entry per layer, in
## layer order. -1 where a layer has nothing yet.
func showing_at(stack: LayerStack, at: int) -> PackedInt32Array:
	_ensure(stack)
	if _native != null:
		return _native.showing_at(at)
	var out: PackedInt32Array = PackedInt32Array()
	for l in range(_starts.size() - 1):
		var best: int = -1
		var lo: int = _starts[l]
		var hi: int = _starts[l + 1] - 1
		while lo <= hi:
			var mid: int = lo + int(float(hi - lo) / 2.0)
			if _frames[mid] <= at:
				best = _frames[mid]
				lo = mid + 1
			else:
				hi = mid - 1
		out.append(best)
	return out

## Which frames in a window have a drawing on any layer. What the ruler shades,
## and previously a walk over every layer for every column.
func occupied(stack: LayerStack, lo: int, hi: int) -> PackedInt32Array:
	_ensure(stack)
	if hi < lo:
		return PackedInt32Array()
	if _native != null:
		return _native.occupied(lo, hi)
	var seen: Dictionary = {}
	for f in _frames:
		var frame: int = int(f)
		if frame >= lo and frame <= hi:
			seen[frame] = true
	var out: PackedInt32Array = PackedInt32Array()
	var keys: Array = seen.keys()
	keys.sort()
	for k in keys:
		out.append(int(k))
	return out

## How many layers have a drawing exactly on this frame.
func count_on(stack: LayerStack, frame: int) -> int:
	_ensure(stack)
	if _native != null:
		return _native.count_on(frame)
	var n: int = 0
	for f in _frames:
		if int(f) == frame:
			n += 1
	return n
