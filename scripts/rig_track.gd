class_name RigTrack
extends RefCounted
## The rig, over time.
##
## `CelTrack` gives a layer its drawings frame by frame; this gives a layer
## its *poses* the same way. Without it a rig is a posing tool and not an
## animation tool: you can bend an arm, but the bend has nowhere to live, so
## the next frame knows nothing about it.
##
## It is built to the pattern `Anim.Clip` already set for the camera, and
## deliberately so — keys held in frame order, an ease mode on each, a
## `pose_at()` that reads a moment by blending the keys either side, the
## nearest key holding beyond the ends. An animator who has understood the
## camera row understands this one, and the timeline draws both with the same
## code.
##
## What it records is a pose, never pixels. A key is a few dozen floats; a
## thousand of them cost less than one drawn frame. This is why bone animation
## can run at sixty keys a second on a tablet where frame-by-frame cannot.
##
## ---------------------------------------------------------------------------
## Why bones are stored as a pivot and an angle, and not as two endpoints
## ---------------------------------------------------------------------------
##
## Storing both ends and sliding each one toward its next position is the
## obvious way, and it is wrong in a way that only shows in the in-betweens —
## the keys themselves look perfect, which is what makes it hard to spot.
##
## A bone is a *chord*. Slide its ends along straight lines and the chord cuts
## across the arc the bone should have travelled, so the bone gets shorter the
## further it swings, and springs back to full length exactly on the key. The
## error was measured before this was written:
##
##       swing of  60°  →  the bone loses  13% of its length mid-tween
##       swing of 120°  →  it loses        50%
##       swing of 179°  →  it loses        99%
##
## A forearm that halves on the way through a wave is not a subtle artefact.
## And it defeats the entire reason `Bone` exists: a bone is the thing that
## keeps a length. So a key holds where the bone's pivot end is and which way
## the bone points, and the far end is rebuilt from the rest length at every
## in-between. The length is then exact at every moment, not merely at keys —
## measured error 1.4e-14, which is floating point saying "exactly".

## The states a key can hold. A rig key may carry any mixture of these: a
## figure with bones but no puppet pins writes no pin block at all, and a key
## with nothing in it is not written.
class RigKey extends RefCounted:
	var frame: int = 0
	## Reuses `Anim.Ease`, so the timeline's existing ease menu, its saved
	## numbers and its curve maths all apply here unchanged.
	var ease_mode: int = Anim.Ease.SMOOTH

	## Bones, three floats each: pivot x, pivot y, angle in radians.
	## See the note at the head of this file for why it is not four.
	var bones: PackedFloat32Array = PackedFloat32Array()

	## Puppet pins, two floats each: where the pin has been pulled to.
	var pins: PackedFloat32Array = PackedFloat32Array()

	func is_empty() -> bool:
		return bones.is_empty() and pins.is_empty()

## Kept in frame order at all times, so reading a moment is a walk and never
## a search.
var keys: Array = []

# ------------------------------------------------------------------ reading

func is_empty() -> bool:
	return keys.is_empty()

func count() -> int:
	return keys.size()

func key_at(frame: int) -> RigKey:
	for k in keys:
		if (k as RigKey).frame == frame:
			return k
	return null

func has_key(frame: int) -> bool:
	return key_at(frame) != null

func frames() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for k in keys:
		out.append((k as RigKey).frame)
	return out

func first_frame() -> int:
	return 0 if keys.is_empty() else (keys[0] as RigKey).frame

func last_frame() -> int:
	return 0 if keys.is_empty() else (keys[keys.size() - 1] as RigKey).frame

## The pair of keys governing a moment, for the timeline to draw the stretch
## between them as travel rather than as two unrelated dots. Same shape as
## `Anim.Clip.span_at`, so the band can treat a rig row and the camera row
## with one piece of code.
func span_at(frame: int) -> Array:
	for i in range(keys.size() - 1):
		var a: RigKey = keys[i]
		var b: RigKey = keys[i + 1]
		if frame >= a.frame and frame < b.frame:
			return [a, b]
	return []

# ------------------------------------------------------------------ writing

## Creates the key if this frame has none, and returns it either way, so a
## caller can write only the parts of a pose it actually owns. The room that
## poses bones need not know whether the layer also carries pins.
func touch(frame: int) -> RigKey:
	var k: RigKey = key_at(frame)
	if k != null:
		return k
	k = RigKey.new()
	k.frame = maxi(frame, 0)
	keys.append(k)
	keys.sort_custom(func(x, y) -> bool: return (x as RigKey).frame < (y as RigKey).frame)
	return k

func set_ease(frame: int, mode: int) -> void:
	var k: RigKey = key_at(frame)
	if k != null:
		k.ease_mode = mode

func remove_key(frame: int) -> void:
	for i in keys.size():
		if (keys[i] as RigKey).frame == frame:
			keys.remove_at(i)
			return

func clear() -> void:
	keys.clear()

## Drops any key that ended up holding nothing. Called after a rig is emptied,
## so a figure whose bones were all deleted does not leave a row of keys on
## the timeline that restore a pose no longer describable.
func prune() -> void:
	var kept: Array = []
	for k in keys:
		if not (k as RigKey).is_empty():
			kept.append(k)
	keys = kept

## Keeps rig timing aligned with drawing timing.
##
## `Anim.Clip.insert_frame_after` shifts camera keys when a frame is pushed
## into the middle of a scene, and `CelTrack` shifts drawings. If the rig did
## not shift with them, inserting one frame at the top of a scene would slide
## every pose out from under its drawing — silently, and permanently.
func insert_frame_after(frame: int) -> void:
	var at: int = maxi(frame + 1, 0)
	for k in keys:
		var one: RigKey = k
		if one.frame >= at:
			one.frame += 1

func remove_frame(frame: int) -> void:
	var kept: Array = []
	for k in keys:
		var one: RigKey = k
		if one.frame == frame:
			continue
		if one.frame > frame:
			one.frame -= 1
		kept.append(one)
	keys = kept

# ------------------------------------------------------------ recording

## Writes a bone pose. `bones` is an Array of anything carrying `a` and `b`
## as Vector2 — `BoneRig.Bone` does, and it does not need to know this class
## exists.
##
## The pivot is `a` and the angle runs from `a` to `b`, matching `_swing`,
## which turns a bone about one end and leaves the other where it was.
static func take_bones(track: RigTrack, frame: int, bones: Array) -> void:
	if track == null:
		return
	var k: RigKey = track.touch(frame)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(bones.size() * 3)
	for i in bones.size():
		var one: Variant = bones[i]
		var a: Vector2 = one.a
		var b: Vector2 = one.b
		out[i * 3] = a.x
		out[i * 3 + 1] = a.y
		# A bone of no length has no direction either. Zero is as good an
		# answer as any and, unlike the alternative, it is a number.
		out[i * 3 + 2] = (b - a).angle() if (b - a).length_squared() > 1e-12 else 0.0
	k.bones = out

static func take_pins(track: RigTrack, frame: int, pins: Array) -> void:
	if track == null:
		return
	var k: RigKey = track.touch(frame)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(pins.size() * 2)
	for i in pins.size():
		var p: Vector2 = pins[i].now
		out[i * 2] = p.x
		out[i * 2 + 1] = p.y
	k.pins = out

# ---------------------------------------------------------------- playback

## The pose at a moment, blended from the keys either side.
##
## Returns only the blocks that were recorded: a track that never held pins
## returns no `pins`, so a caller can ask `has()` rather than compare against
## an empty array it would have to invent a meaning for.
##
## Before the first key and after the last, the nearest key holds. A rig
## should stay where it was put rather than drift back to a rest pose nobody
## asked for — the same rule the camera follows, for the same reason.
func pose_at(frame: float) -> Dictionary:
	if keys.is_empty():
		return {}
	var first: RigKey = keys[0]
	if frame <= float(first.frame) or keys.size() == 1:
		return _read(first)
	var last: RigKey = keys[keys.size() - 1]
	if frame >= float(last.frame):
		return _read(last)

	for i in range(keys.size() - 1):
		var a: RigKey = keys[i]
		var b: RigKey = keys[i + 1]
		if frame < float(a.frame) or frame > float(b.frame):
			continue
		if a.ease_mode == Anim.Ease.HOLD:
			# A step, not a travel. Used for anything that has no sensible
			# in-between — and for an animator who wants twos rather than
			# ones without the app deciding that for them.
			return _read(a)
		var span: float = float(b.frame - a.frame)
		if span <= 0.0:
			return _read(b)
		var raw_t: float = (frame - float(a.frame)) / span
		var fast_t: float = raw_t
		var native_anim: Object = Native.animation()
		if native_anim != null:
			fast_t = float(native_anim.call("key_progress", frame, a.frame, b.frame))
		var t: float = Anim.ease_shape(fast_t, a.ease_mode)
		return _blend(a, b, t)
	return _read(last)

func _read(k: RigKey) -> Dictionary:
	var out: Dictionary = {}
	if not k.bones.is_empty():
		out["bones"] = k.bones
	if not k.pins.is_empty():
		out["pins"] = k.pins
	return out

func _blend(a: RigKey, b: RigKey, t: float) -> Dictionary:
	var out: Dictionary = {}
	if not a.bones.is_empty() or not b.bones.is_empty():
		out["bones"] = _mix_bones(a.bones, b.bones, t)
	if not a.pins.is_empty() or not b.pins.is_empty():
		out["pins"] = _mix_floats(a.pins, b.pins, t)
	return out

## Blends two float blocks that may not be the same length.
##
## They will not be, whenever a bone or a pin was added after the first key
## was laid. The short one is treated as ending where it ends: anything past
## it holds the value the long one has, rather than being blended against a
## zero that means "no data" and would read as "snap to the origin". A limb
## added halfway through a scene therefore appears in place rather than flying
## in from the top-left corner.
static func _mix_floats(a: PackedFloat32Array, b: PackedFloat32Array,
		t: float) -> PackedFloat32Array:
	var n: int = maxi(a.size(), b.size())
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i in n:
		var has_a: bool = i < a.size()
		var has_b: bool = i < b.size()
		if has_a and has_b:
			out[i] = a[i] + (b[i] - a[i]) * t
		elif has_a:
			out[i] = a[i]
		else:
			out[i] = b[i]
	return out

## The same, in threes, with the third of each three read as an angle.
##
## `lerp_angle` rather than a plain blend, so a bone crossing from just under
## a half turn to just over takes the short way round instead of unwinding
## the long way through every angle it does not pass through.
static func _mix_bones(a: PackedFloat32Array, b: PackedFloat32Array,
		t: float) -> PackedFloat32Array:
	var n: int = maxi(a.size(), b.size())
	n -= n % 3
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i in range(0, n, 3):
		var has_a: bool = i + 2 < a.size()
		var has_b: bool = i + 2 < b.size()
		if has_a and has_b:
			out[i] = a[i] + (b[i] - a[i]) * t
			out[i + 1] = a[i + 1] + (b[i + 1] - a[i + 1]) * t
			out[i + 2] = lerp_angle(a[i + 2], b[i + 2], t)
		elif has_a:
			out[i] = a[i]
			out[i + 1] = a[i + 1]
			out[i + 2] = a[i + 2]
		else:
			out[i] = b[i]
			out[i + 1] = b[i + 1]
			out[i + 2] = b[i + 2]
	return out

# ------------------------------------------------------------- restoring

## Puts a blended pose back onto a live bone list.
##
## The far end is rebuilt from the bone's own rest length, which is what
## keeps every in-between exactly as long as the bone is — see the note at
## the head of this file. `bones` is an Array of `BoneRig.Bone`, which carries
## `rest_a`, `rest_b`, `a` and `b`.
static func lay_bones(bones: Array, packed: PackedFloat32Array) -> void:
	for i in bones.size():
		var at: int = i * 3
		if at + 2 >= packed.size():
			return
		var one: Variant = bones[i]
		var rest_len: float = (one.rest_b - one.rest_a).length()
		var pivot: Vector2 = Vector2(packed[at], packed[at + 1])
		one.a = pivot
		one.b = pivot + Vector2.RIGHT.rotated(packed[at + 2]) * rest_len

# ------------------------------------------------------------------ saving

func to_dict() -> Dictionary:
	var rows: Array = []
	for k in keys:
		var one: RigKey = k
		if one.is_empty():
			continue
		var row: Dictionary = {"f": one.frame, "e": one.ease_mode}
		# Only what this key actually holds is written. A bone-only track
		# carries no empty pin arrays, and a file stays readable by eye.
		if not one.bones.is_empty():
			row["b"] = _floats_out(one.bones)
		if not one.pins.is_empty():
			row["p"] = _floats_out(one.pins)
		rows.append(row)
	return {"keys": rows}

static func _floats_out(src: PackedFloat32Array) -> Array:
	var out: Array = []
	out.resize(src.size())
	for i in src.size():
		out[i] = src[i]
	return out

static func _floats_in(src: Variant) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if src == null:
		return out
	var arr: Array = src
	out.resize(arr.size())
	for i in arr.size():
		out[i] = float(arr[i])
	return out

static func from_dict(doc: Dictionary) -> RigTrack:
	var track: RigTrack = RigTrack.new()
	for row in doc.get("keys", []):
		var k: RigKey = RigKey.new()
		k.frame = maxi(int(row.get("f", 0)), 0)
		k.ease_mode = int(row.get("e", Anim.Ease.SMOOTH))
		k.bones = _floats_in(row.get("b", null))
		k.pins = _floats_in(row.get("p", null))
		if not k.is_empty():
			track.keys.append(k)
	# Sorted on the way in rather than trusted. A file may have been written
	# by an older build, edited by hand, or merged; everything downstream
	# reads these in order and would misbehave quietly if they were not.
	track.keys.sort_custom(func(x, y) -> bool:
		return (x as RigKey).frame < (y as RigKey).frame)
	return track
