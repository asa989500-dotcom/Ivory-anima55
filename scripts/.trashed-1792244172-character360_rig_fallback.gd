class_name Character360RigFallback
extends RefCounted
## Pure-GDScript stand-in for `IvoryCharacter360Rig`'s disc blending.
##
## The GDExtension is optional by design — `ivory.gdextension` says so, and a
## checkout with no `bin/` is expected to run. Without this file that promise
## did not hold for Character 360: `Native.character360_rig()` returned null,
## `AnimPlayer._character360_controller` returned null with it, and the whole
## turn-blend silently did nothing on any device where the library had not
## been built. So this is not a toy fallback; it is the feature on Android
## until the `.so` exists.
##
## The API is deliberately the same subset `AnimPlayer` calls, so the two are
## interchangeable and nothing above has to know which one it holds.

const TAU_F: float = 6.283185307179586
const EPSILON: float = 0.0000001

var _angles: PackedFloat32Array = PackedFloat32Array()
var _live: PackedByteArray = PackedByteArray()

static func wrap_angle(a: float) -> float:
	## Folds any angle into (-PI, PI]. Matches the native `wrap_angle` so a
	## project posed with the library reads identically without it.
	var x: float = fmod(a + PI, TAU_F)
	if x < 0.0:
		x += TAU_F
	return x - PI

func add_disc(angle: float) -> int:
	_angles.append(wrap_angle(angle))
	_live.append(1)
	return _angles.size() - 1

func set_disc_angle(index: int, angle: float) -> void:
	if index >= 0 and index < _angles.size():
		_angles[index] = wrap_angle(angle)

func disc_angle(index: int) -> float:
	if index < 0 or index >= _angles.size():
		return 0.0
	return _angles[index]

func set_disc_live(index: int, live: bool) -> void:
	if index >= 0 and index < _live.size():
		_live[index] = 1 if live else 0

func disc_count() -> int:
	return _angles.size()

func clear_discs() -> void:
	_angles.clear()
	_live.clear()

func disc_weights(angle: float) -> PackedFloat32Array:
	## Linear blend between the two discs the requested yaw sits between,
	## normalised so the drawing never brightens or fades as it turns.
	##
	## Each disc holds full weight at its own angle and falls to nought at
	## its neighbour — on *both* sides. The one-sided version of this loses
	## the figure between the last disc and the first, which is the seam a
	## turnaround crosses most: at 315 degrees on a four-disc rig it blends
	## back and left rather than left and front.
	var count: int = _angles.size()
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	out.fill(0.0)
	var live: Array[int] = []
	for i in range(count):
		if _live[i] != 0:
			live.append(i)
	if live.is_empty():
		return out
	if live.size() == 1:
		out[live[0]] = 1.0
		return out
	# Insertion sort by angle. The list is a handful of discs at most, and
	# writing it out avoids leaning on how a lambda captures `self`.
	for s in range(1, live.size()):
		var key: int = live[s]
		var t: int = s - 1
		while t >= 0 and _angles[live[t]] > _angles[key]:
			live[t + 1] = live[t]
			t -= 1
		live[t + 1] = key

	var a: float = wrap_angle(angle)
	var n: int = live.size()
	for k in range(n):
		var i: int = live[k]
		var before: int = live[(k + n - 1) % n]
		var after: int = live[(k + 1) % n]
		var left: float = wrap_angle(_angles[i] - _angles[before])
		var right: float = wrap_angle(_angles[after] - _angles[i])
		if left <= 0.0:
			left += TAU_F
		if right <= 0.0:
			right += TAU_F
		var x: float = wrap_angle(a - _angles[i])
		if x < 0.0:
			x += TAU_F
		var w: float = 0.0
		if x <= right:
			w = 1.0 - x / maxf(right, EPSILON)
		elif x >= TAU_F - left:
			w = 1.0 - (TAU_F - x) / maxf(left, EPSILON)
		out[i] = maxf(0.0, w)

	var sum: float = 0.0
	for i in range(count):
		sum += out[i]
	if sum > EPSILON:
		for i in range(count):
			out[i] = out[i] / sum
	return out
