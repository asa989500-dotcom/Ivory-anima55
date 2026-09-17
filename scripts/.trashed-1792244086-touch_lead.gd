class_name TouchLead
extends RefCounted
## What the finger meant, from what the screen reported.
##
## ## Two problems that pull opposite ways
##
## A touch panel reports a position that is **noisy** — a still finger jitters
## by a pixel or two — and it reports it **late**, because the panel scans, the
## system batches the events, and the frame is drawn after all of that.
##
## Smoothing fixes the first and makes the second worse: every filter that
## removes jitter does it by lagging behind. So a filter alone cannot be the
## answer, and turning the filter down to fix the lag hands the jitter back.
##
## ## The one-euro filter, and the lead
##
## Casiez, Roussel and Vogel (2012). An exponential filter whose cutoff rises
## with how fast the pointer is moving:
##
##     cutoff = min_cutoff + beta × speed
##
## Standing still the cutoff is low and the jitter is gone; moving fast the
## cutoff is high, the filter is nearly transparent, and there is nearly no
## lag. One line of insight, and it beats every fixed-cutoff filter at both
## ends at once.
##
## What lag is left is *systematic* rather than random, so it can be subtracted
## rather than filtered: the position is carried forward along the filtered
## velocity by a fixed few milliseconds. Small, because prediction buys
## responsiveness with overshoot at direction changes and the trade turns bad
## quickly.
##
## ## Where this is used, and where it must not be
##
## **Controls, never ink.** A pin being dragged and a joint being posed are
## controls being *aimed*, and a control that arrives where the thumb already
## is feels like the thumb is touching the drawing rather than shoving it. A
## brush stroke is a record of where the hand actually went, and predicting one
## would be inventing ink that was never drawn — `stroke_smoother.gd` is what a
## stroke uses and it deliberately does not lead.
##
## ## Why this class exists at all when the C++ has the same filter
##
## Because the C++ is optional. This is the same arithmetic in GDScript, used
## when the extension is not built, so a pin drags identically either way and
## no behaviour depends on a library being present. The native one is used when
## it is there because this runs on every touch event of every drag.

const TAU_SCALE: float = 6.283185307179586

var _native: Object = null
var _have: bool = false
var _last_ms: float = 0.0
var _value: Vector2 = Vector2.ZERO
var _speed: Vector2 = Vector2.ZERO
var _raw_last: Vector2 = Vector2.ZERO

## How still a still finger is held. Lower is steadier and laggier.
var min_cutoff: float = 1.2
## How quickly the filter opens as the hand speeds up.
var beta: float = 0.035
## The cutoff the speed estimate itself is filtered at. The derivative of a
## noisy signal is noisier than the signal, and an unfiltered speed would open
## the position filter wide on nothing but jitter.
var speed_cutoff: float = 1.0
## How far ahead the position is carried, in milliseconds.
var lead_ms: float = 12.0
## Screen-space quiet zone applied before velocity estimation.
var deadband_px: float = 0.0

func _init() -> void:
	_native = Native.warp_touch()
	_apply()

func _apply() -> void:
	if _native != null:
		_native.call("configure", min_cutoff, beta, speed_cutoff, lead_ms,
			deadband_px)

## New settings, for a caller that wants a steadier or a livelier hand.
func configure(cutoff: float, rise: float, speed: float,
		lead: float, deadband: float = 0.0) -> void:
	min_cutoff = maxf(cutoff, 0.01)
	beta = maxf(rise, 0.0)
	speed_cutoff = maxf(speed, 0.01)
	lead_ms = clampf(lead, 0.0, 40.0)
	deadband_px = clampf(deadband, 0.0, 8.0)
	_apply()

## A new gesture. Always called when a finger goes down: a filter carrying the
## velocity of the last drag would fling the first frame of the next one.
func reset() -> void:
	_have = false
	_speed = Vector2.ZERO
	if _native != null:
		_native.call("reset")

## Where the finger is judged to be, which is not quite where the screen said.
func at(raw: Vector2) -> Vector2:
	var now: float = float(Time.get_ticks_usec()) * 0.000001
	if _native != null:
		return _native.call("filter", raw, now)
	if not _have:
		_have = true
		_last_ms = now
		_value = raw
		_raw_last = raw
		_speed = Vector2.ZERO
		return raw
	# A frame that took no time reports an infinite speed, and one that took a
	# second is a dropped finger rather than a slow one. Both are clamped to
	# the band a touch screen actually reports in.
	var dt: float = clampf(now - _last_ms, 0.001, 0.2)
	_last_ms = now
	if deadband_px > 0.0 and raw.distance_to(_value) <= deadband_px:
		raw = _value
	var raw_speed: Vector2 = (raw - _raw_last) / dt
	_raw_last = raw
	_speed += (raw_speed - _speed) * _alpha(speed_cutoff, dt)
	var cutoff: float = min_cutoff + beta * _speed.length()
	_value += (raw - _value) * _alpha(cutoff, dt)
	if lead_ms <= 0.0:
		return _value
	return _value + _speed * (lead_ms * 0.001)

## The smoothing factor of a one-pole low pass at this cutoff over this
## interval. Derived rather than tuned: the time constant of a filter with
## cutoff `f` is `1 / 2πf`, and the factor that reaches it in `dt` is
## `dt / (τ + dt)`.
static func _alpha(cutoff: float, dt: float) -> float:
	var tau: float = 1.0 / (TAU_SCALE * maxf(cutoff, 0.01))
	return dt / (tau + dt)


## Diagnostics for a control gesture. The native implementation measures
## digitizer jitter/velocity/pressure without touching the artwork.
func metrics() -> Dictionary:
	if _native != null and _native.has_method("metrics"):
		return _native.call("metrics")
	return {"samples": 0, "jitter_rms_px": 0.0, "max_speed_px_s": 0.0,
		"deadband_hits": 0, "pressure": 1.0, "stable": true}

func sample_pressure(value: float) -> void:
	if _native != null and _native.has_method("sample_pressure"):
		_native.call("sample_pressure", clampf(value, 0.0, 1.0))
