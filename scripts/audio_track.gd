class_name AudioTrack
extends RefCounted
## The sounds a scene carries, and where each of them sits in time.
##
## This is music and effects, not a mouth. A sound here is a thing that plays
## at a frame — a score under the whole scene, a door closing on frame 214,
## eight takes of footsteps on eight different layers. Nothing here shapes a
## drawing, and nothing here is read for speech.
##
## Clips are tagged with the layer they were added from, because that is
## where they are managed: press a layer in the timeline and you see that
## layer's sounds. But they mix as one scene, which is what an export is —
## every clip that is not muted, laid over every other, at its own frame.
##
## Nothing here holds samples. A clip is a path, a frame and a volume; the
## samples are read from the disk by `AudioMix` while the export runs.

## As many sounds as the scene can hold at once.
##
## Not a limit anybody will reach by working — it is a limit on what a
## damaged save file can ask the mixer to open at once.
const CEILING: int = 512

class Clip:
	## Where the sound came from. Kept as the original path, never a copy:
	## the file on the device is the file, and the app's cache is rebuilt
	## from it whenever it is needed.
	var path: String = ""
	## What to call it in the panel. The file's own name, unless renamed.
	var title: String = ""
	## Which layer's list this belongs to, by layer id.
	var layer_id: int = 0
	## The frame it starts on.
	var start_frame: int = 0
	## How far into the sound to begin, in seconds. A trim, not a fade.
	var skip: float = 0.0
	## How much of the sound to use, in seconds. Zero means all of it.
	var span: float = 0.0
	## Loudness, where one is the sound as recorded. Above one is allowed
	## and clamped at the mix, because a quiet recording is a real problem
	## and refusing to raise it is not a kindness.
	var gain: float = 1.0
	## Silenced without being removed.
	var muted: bool = false
	## Seconds of fade at each end, so a clip cut mid-waveform does not
	## click. Both default to a hair rather than nothing: a hard cut on a
	## sustained note is audible on every phone speaker made.
	var fade_in: float = 0.01
	var fade_out: float = 0.02
	## How long the file runs, in seconds, as far as is known. Zero means
	## it has not been measured yet — a compressed file's length is only
	## certain once it has been decoded.
	var seconds: float = 0.0

	func duplicate_clip() -> Clip:
		var copy: Clip = Clip.new()
		copy.path = path
		copy.title = title
		copy.layer_id = layer_id
		copy.start_frame = start_frame
		copy.skip = skip
		copy.span = span
		copy.gain = gain
		copy.muted = muted
		copy.fade_in = fade_in
		copy.fade_out = fade_out
		copy.seconds = seconds
		return copy

	## How long this clip plays for, in seconds.
	func length() -> float:
		var whole: float = maxf(seconds - skip, 0.0)
		if span > 0.0:
			return minf(span, whole) if whole > 0.0 else span
		return whole

	func missing() -> bool:
		return path == "" or not FileAccess.file_exists(path)

var clips: Array = []

# ------------------------------------------------------------------ adding

## Adds a sound, and answers with the clip so the caller can place it.
##
## Nothing is decoded here. Adding twelve tracks at once should take as long
## as adding one, which means the expensive part cannot happen on the way in.
func add(path: String, layer_id: int, at_frame: int) -> Clip:
	if clips.size() >= CEILING:
		return null
	var one: Clip = Clip.new()
	one.path = path
	one.title = path.get_file().get_basename()
	one.layer_id = layer_id
	one.start_frame = maxi(at_frame, 0)
	var told: Dictionary = AudioBank.describe(path)
	one.seconds = float(told.get("seconds", 0.0))
	clips.append(one)
	return one

func remove(one: Clip) -> void:
	clips.erase(one)

## Every clip belonging to one layer, in the order they start.
func for_layer(layer_id: int) -> Array:
	var found: Array = []
	for c in clips:
		var one: Clip = c as Clip
		if one.layer_id == layer_id:
			found.append(one)
	found.sort_custom(func(a: Clip, b: Clip) -> bool:
		return a.start_frame < b.start_frame)
	return found

func drop_layer(layer_id: int) -> void:
	var kept: Array = []
	for c in clips:
		var one: Clip = c as Clip
		if one.layer_id != layer_id:
			kept.append(one)
	clips = kept

## Whether anything at all would be heard.
##
## Muted clips do not count, and neither do clips whose file has been moved
## or deleted since it was added — an export should not open a silent AAC
## stream to carry nothing.
func anything_to_hear() -> bool:
	for c in clips:
		var one: Clip = c as Clip
		if not one.muted and not one.missing():
			return true
	return false

func live_clips() -> Array:
	var found: Array = []
	for c in clips:
		var one: Clip = c as Clip
		if not one.muted and not one.missing() and one.gain > 0.0:
			found.append(one)
	return found

## The last moment any sound is still playing, in seconds, given how the
## timeline turns frames into time.
##
## Used so an export can offer to run on to the end of the music rather than
## stopping dead on the last drawing.
func last_second(clip: Object) -> float:
	var latest: float = 0.0
	for c in clips:
		var one: Clip = c as Clip
		if one.muted or one.missing():
			continue
		var begins: float = 0.0
		if clip != null and clip.has_method("time_of"):
			begins = float(clip.call("time_of", one.start_frame))
		latest = maxf(latest, begins + one.length())
	return latest

# ------------------------------------------------------------------ saving

static func to_dict(track: AudioTrack) -> Dictionary:
	var rows: Array = []
	if track != null:
		for c in track.clips:
			var one: Clip = c as Clip
			rows.append({"path": one.path, "title": one.title,
				"layer": one.layer_id, "start": one.start_frame,
				"skip": one.skip, "span": one.span, "gain": one.gain,
				"muted": one.muted, "fade_in": one.fade_in,
				"fade_out": one.fade_out, "seconds": one.seconds})
	return {"clips": rows}

static func from_dict(doc: Dictionary) -> AudioTrack:
	var track: AudioTrack = AudioTrack.new()
	for row in doc.get("clips", []):
		if track.clips.size() >= CEILING:
			break
		var one: Clip = Clip.new()
		one.path = String(row.get("path", ""))
		if one.path == "":
			continue
		one.title = String(row.get("title", one.path.get_file().get_basename()))
		one.layer_id = int(row.get("layer", 0))
		one.start_frame = maxi(int(row.get("start", 0)), 0)
		one.skip = maxf(float(row.get("skip", 0.0)), 0.0)
		one.span = maxf(float(row.get("span", 0.0)), 0.0)
		one.gain = clampf(float(row.get("gain", 1.0)), 0.0, 4.0)
		one.muted = bool(row.get("muted", false))
		one.fade_in = clampf(float(row.get("fade_in", 0.01)), 0.0, 30.0)
		one.fade_out = clampf(float(row.get("fade_out", 0.02)), 0.0, 30.0)
		one.seconds = maxf(float(row.get("seconds", 0.0)), 0.0)
		track.clips.append(one)
	return track
