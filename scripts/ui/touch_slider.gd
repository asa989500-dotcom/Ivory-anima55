class_name TouchSlider
extends Control
## A slider built for fingers, not cursors.
##
## Godot's built-in sliders listen for mouse events, which is why they felt
## dead under touch. This one handles screen touch and drag itself, has a
## 48px tall hit area, jumps straight to wherever you tap, and slows down as
## you drag your finger away from the track so fine values are reachable.

signal value_changed(value: float)
## Fires once when the finger lifts. Anything that should count as a single
## action — a history entry, a save — listens here rather than to every tick.
signal drag_ended(value: float)

var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.01
var value: float = 0.0

var _dragging: bool = false
var _pointer: int = -1
var _fine_anchor: float = 0.0
var _grab_offset: float = 0.0

const TRACK_H: float = 8.0
const KNOB_R: float = 13.0

func _ready() -> void:
	custom_minimum_size = Vector2(UiKit.s(200.0), UiKit.s(48.0))
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(min_v: float, max_v: float, start: float, step_v: float) -> void:
	min_value = min_v
	max_value = max_v
	step = step_v
	value = clampf(start, min_v, max_v)
	queue_redraw()

func set_value_silent(v: float) -> void:
	value = clampf(v, min_value, max_value)
	queue_redraw()

# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		App.touch_mode = true
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_begin(st.position, st.index)
		elif st.index == _pointer:
			_end()
		accept_event()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		if _dragging and sd.index == _pointer:
			_move(sd.position)
		accept_event()
	elif event is InputEventMouseButton:
		if App.touch_mode:
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin(mb.position, -2)
			else:
				_end()
			accept_event()
	elif event is InputEventMouseMotion:
		if App.touch_mode:
			return
		if _dragging:
			_move((event as InputEventMouseMotion).position)
			accept_event()

## Entry point for a tap that came from the scroller rather than directly,
## so a slider inside a scrolling panel still answers a plain tap.
func tap_at(local: Vector2) -> void:
	_begin(local, -1)
	_end()

func _begin(pos: Vector2, index: int) -> void:
	_dragging = true
	_pointer = index
	_fine_anchor = pos.y
	# Tapping the knob keeps the value; tapping the track jumps to it.
	var knob_x: float = _value_to_x(value)
	if absf(pos.x - knob_x) <= UiKit.s(KNOB_R) * 1.6:
		_grab_offset = knob_x - pos.x
	else:
		_grab_offset = 0.0
		_apply(pos, 1.0)
	queue_redraw()

func _move(pos: Vector2) -> void:
	# The further the finger strays vertically, the finer the control —
	# the same trick hardware faders use, and it costs the user nothing.
	var stray: float = absf(pos.y - _fine_anchor) / UiKit.s(90.0)
	var precision: float = 1.0 / (1.0 + clampf(stray, 0.0, 4.0) * 3.0)
	_apply(pos, precision)

func _end() -> void:
	if not _dragging:
		return
	_dragging = false
	_pointer = -1
	queue_redraw()
	drag_ended.emit(value)

func _apply(pos: Vector2, precision: float) -> void:
	var target: float = _x_to_value(pos.x + _grab_offset)
	var next: float = value + (target - value) * precision
	next = clampf(next, min_value, max_value)
	if step > 0.0:
		next = round(next / step) * step
		next = clampf(next, min_value, max_value)
	if is_equal_approx(next, value):
		return
	value = next
	queue_redraw()
	value_changed.emit(value)

# ---------------------------------------------------------------- geometry

func _track_rect() -> Rect2:
	var pad: float = UiKit.s(KNOB_R) + UiKit.s(2.0)
	return Rect2(pad, size.y * 0.5 - UiKit.s(TRACK_H) * 0.5,
		maxf(size.x - pad * 2.0, 1.0), UiKit.s(TRACK_H))

func _value_to_x(v: float) -> float:
	var r: Rect2 = _track_rect()
	var span: float = maxf(max_value - min_value, 0.00001)
	return r.position.x + r.size.x * clampf((v - min_value) / span, 0.0, 1.0)

func _x_to_value(x: float) -> float:
	var r: Rect2 = _track_rect()
	var t: float = clampf((x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
	return min_value + t * (max_value - min_value)

# ----------------------------------------------------------------- drawing

func _draw() -> void:
	var r: Rect2 = _track_rect()
	var radius: float = r.size.y * 0.5

	draw_rect(r, Color("#ddd5c4"), true)
	_round_caps(r, Color("#ddd5c4"), radius)

	var knob_x: float = _value_to_x(value)
	var filled: Rect2 = Rect2(r.position, Vector2(knob_x - r.position.x, r.size.y))
	if filled.size.x > 0.5:
		draw_rect(filled, UiKit.ACCENT, true)
		_round_caps(filled, UiKit.ACCENT, radius)

	var kr: float = UiKit.s(KNOB_R) * (1.15 if _dragging else 1.0)
	var centre: Vector2 = Vector2(knob_x, r.position.y + radius)
	draw_circle(centre + Vector2(0.0, UiKit.s(1.5)), kr, Color(0.0, 0.0, 0.0, 0.16))
	draw_circle(centre, kr, Color("#fdfbf6"))
	draw_arc(centre, kr, 0.0, TAU, 28, UiKit.ACCENT, UiKit.s(2.5), true)

func _round_caps(r: Rect2, col: Color, radius: float) -> void:
	draw_circle(Vector2(r.position.x, r.position.y + radius), radius, col)
	draw_circle(Vector2(r.position.x + r.size.x, r.position.y + radius), radius, col)
