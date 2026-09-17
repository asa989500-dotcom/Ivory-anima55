class_name CanvasViewGesture
extends RefCounted
## Two-finger move, pinch and turn on the canvas.
##
## Lifted out of `canvas_view.gd` at stage 145 to bring that file back under
## the size the project allows. `CanvasView` keeps a one-line delegate for
## each, so nothing that called them changed.
##
## The reasoning that used to sit above `_apply_gesture` came with it and is
## the thing to read first: move, pinch and turn are one motion of two
## fingers and are applied as one transform, because doing them in sequence
## moved the pivot each next step was measured from and the accumulated error
## came back as the shake the user reported.

## Move, pinch and turn are one motion of two fingers, so they are applied
## as one transform rather than three in a row.
##
## Doing them in sequence — pan, then zoom about a point, then rotate about
## a point — meant each step moved the pivot the next step was measured
## from, and the error came back as the shake. Here the whole change is
## expressed once: the view is scaled and turned about the midpoint the
## fingers held a moment ago, then carried by however far that midpoint
## travelled. Exact, and with nothing left to accumulate.
static func apply_gesture(host: CanvasView, mid: Vector2, dist: float, turn: float) -> void:
	var factor: float = 1.0
	if host._g_last_dist > 4.0 and dist > 4.0:
		factor = dist / host._g_last_dist
	var target: float = clampf(host.view_zoom * factor, host.MIN_ZOOM, host.MAX_ZOOM)
	factor = target / maxf(host.view_zoom, 0.00001)

	var spin: float = 0.0
	# Below this spread the angle between two fingers is mostly noise, and a
	# sheet would tremble while being pinched.
	if host.can_rotate() and dist > 70.0 * App.ui_scale:
		spin = wrapf(turn - host._g_last_angle, -PI, PI)

	var pivot: Vector2 = host._g_last_mid
	host.view_offset = ((host.view_offset - pivot) * factor).rotated(spin) + pivot \
		+ (mid - pivot)
	host.view_zoom = target
	host.view_angle = wrapf(host.view_angle + spin, -PI, PI)
	host._apply_view()

static func start_gesture(host: CanvasView) -> void:
	host._gesture_active = true
	host._gesture_took_over = false
	host._g_moving = false
	host._gesture_consumed = false
	host._g_travel = 0.0
	host._g_start_ms = Time.get_ticks_msec()
	host._g_last_mid = host._mid()
	host._g_last_dist = host._spread()
	host._g_last_angle = host._twist()

static func finish_gesture(host: CanvasView) -> void:
	var duration: int = Time.get_ticks_msec() - host._g_start_ms
	var quiet: bool = host._g_travel <= host.TAP_SLOP * App.ui_scale
	var tapped: bool = duration <= host.TAP_MS and quiet and not host._g_moving

	if tapped:
		# The first finger of a tap has already put a dot down. Undoing on
		# top of that left one step taken back and a fresh one added in the
		# same breath — which is why repeated taps went nowhere. The dot is
		# rolled back first, so a tap is only ever a tap.
		host._cancel_input()
		if host._g_max_fingers == 2:
			host.undo()
		elif host._g_max_fingers >= 3:
			host.redo()
	elif host._g_moving:
		host._settle_angle()
	elif host._drawing:
		# Fingers came and went without navigating: the stroke was only
		# paused, so it is finished properly rather than lost.
		host._end_stroke(host._last_stamp)

	host._gesture_active = false
	host._gesture_took_over = false
	host._g_moving = false
	host._g_max_fingers = 0
	host._draw_finger = -1
