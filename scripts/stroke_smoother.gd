class_name StrokeSmoother
extends RefCounted
## Takes the shake out of a stroke without letting it trail the finger.
##
## A plain averaging filter has one dial, and that dial trades one fault for
## the other: smooth enough to kill the jitter of a slow line is also slow
## enough to lag a fast one. Which is exactly what "the line does not sit
## under my finger" feels like.
##
## The one-euro filter fixes that by making the smoothing depend on speed.
## Move slowly — where jitter is visible and lag is not — and it smooths
## hard. Move quickly — where lag is glaring and jitter invisible — and it
## almost stops filtering. The result follows the finger and still draws a
## clean line, instead of choosing between the two.

const MIN_CUTOFF: float = 1.4    # Hz — smoothing when the hand is still
const BETA: float = 0.028        # how fast speed loosens the filter
const D_CUTOFF: float = 1.0      # smoothing applied to the speed estimate
## A tiny quiet zone removes digitizer quantisation without changing the
## artist's intended stroke. Bone controls use a larger value in BoneHandle.
const TOUCH_DEADBAND_PX: float = 0.25

## How hard the line is pulled straight, nought to one.
##
## ## Why a second stage, when there is already a filter here
##
## The One Euro filter below removes *jitter* — the small shake in a hand that
## is otherwise going where it means to. That is not what an artist means by
## stabilisation, and it is not what a fast stroke on a touchscreen suffers
## from. A finger swept quickly across glass does not shake; it **wobbles**,
## in long shallow curves, and a jitter filter passes those straight through
## because to it they look exactly like a hand deliberately drawing a curve.
##
## What removes them is lag: the nib is not put where the finger is, it is
## dragged along behind it on a short leash. Sweep quickly and the leash pulls
## taut and the nib cuts the corner off every wobble. This is the stabiliser
## every drawing package has, and it is a different mechanism from the filter,
## not a stronger setting of it — which is why it is a second stage rather
## than a bigger number in the first.
##
## The cost is honest and worth naming: the line ends slightly behind the
## finger, and at full strength that lag is visible. That is the trade every
## stabiliser makes, and it is why this is a dial rather than a default.
var strength: float = 0.0

var _ready_yet: bool = false
var _prev: Vector2 = Vector2.ZERO
var _speed: Vector2 = Vector2.ZERO
var _last_ms: int = 0
## Native C++ one-euro filter. Lead is deliberately zero for painting: a
## brush records where the hand went and must never invent ink ahead of it.
var _native_touch: Object = null
## Where the nib is, trailing behind where the hand is.
var _nib: Vector2 = Vector2.ZERO

func reset(at: Vector2) -> void:
	_native_touch = Native.brush_touch() if Native.has_touch() else null
	if _native_touch != null:
		_native_touch.configure(MIN_CUTOFF, BETA, D_CUTOFF, 0.0,
			TOUCH_DEADBAND_PX)
		_native_touch.reset()
	_ready_yet = true
	_prev = at
	_nib = at
	_speed = Vector2.ZERO
	_last_ms = Time.get_ticks_msec()

func filter(raw: Vector2) -> Vector2:
	if not _ready_yet:
		reset(raw)
		return raw

	var now: int = Time.get_ticks_msec()
	var dt: float = float(now - _last_ms) / 1000.0
	_last_ms = now
	# A stalled or duplicated event must not divide by nothing.
	dt = clampf(dt, 1.0 / 240.0, 1.0 / 20.0)
	if _native_touch == null \
			and raw.distance_to(_prev) <= TOUCH_DEADBAND_PX:
		raw = _prev

	if _native_touch != null:
		_prev = raw
		_nib = _native_touch.filter(raw, float(now) / 1000.0)
		return _nib

	var raw_speed: Vector2 = (raw - _prev) / dt
	_speed = _lerp_to(_speed, raw_speed, _alpha(D_CUTOFF, dt))

	var pace: float = _speed.length()
	var cutoff: float = MIN_CUTOFF + BETA * pace
	_prev = _lerp_to(_prev, raw, _alpha(cutoff, dt))

	var pull: float = clampf(strength, 0.0, 1.0)
	if pull <= 0.001:
		_nib = _prev
		return _prev
	# The leash. At nought the nib is exactly where the filtered hand is; at
	# one it catches up by a twentieth of the distance per report, which is a
	# long, heavy line that ignores everything but the direction of travel.
	#
	# Weighted by the time step rather than applied per event, so a device
	# reporting at 240Hz and one reporting at 60Hz give the same line. Without
	# that, the same setting is four times heavier on the better tablet, which
	# is the wrong way round and impossible to explain.
	var catch_up: float = lerpf(1.0, 0.05, pull)

	# The leash lets go when the hand slows down.
	#
	# Without this the lag is constant, and constant lag is what makes a
	# stabiliser infuriating rather than helpful: you stop the finger on the
	# spot you were aiming at, and the line stops short of it. Every slow,
	# careful, aimed stroke — the ones that need precision most — ends in the
	# wrong place, and the tool is worst exactly where it should be quietest.
	#
	# A fast sweep is where wobble lives and where lag is invisible, so the
	# leash is tight there and slack when the hand is barely moving. `pace`
	# is already measured for the filter above, so this costs one comparison.
	var haste: float = clampf(_speed.length() / 900.0, 0.0, 1.0)
	catch_up = lerpf(1.0, catch_up, haste)

	_nib = _lerp_to(_nib, _prev,
		clampf(catch_up * dt * 60.0, 0.0, 1.0))
	return _nib

## Where the nib is now, so the end of a stroke can be walked up to the hand.
##
## The leash means the line stops short of where the finger lifted, by up to a
## few pixels at full strength. Left there, every stroke ends a little before
## it was meant to and two strokes meant to meet never quite do — which is the
## one thing line art cannot forgive.
##
## The canvas walks the last short run when the finger lifts, so the mark ends
## where the hand ended. See `CanvasView._end_stroke`.
func hand() -> Vector2:
	return _prev

func nib() -> Vector2:
	return _nib

## Turns a cutoff frequency and a time step into a blend weight.
func _alpha(cutoff: float, dt: float) -> float:
	var tau: float = 1.0 / (TAU * maxf(cutoff, 0.001))
	return clampf(1.0 / (1.0 + tau / dt), 0.0, 1.0)

func _lerp_to(from: Vector2, to: Vector2, a: float) -> Vector2:
	return from + (to - from) * a
