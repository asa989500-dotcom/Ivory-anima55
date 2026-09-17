class_name TouchScroll
extends Control
## A scrolling column that knows the difference between a drag and a tap.
##
## Godot's own scroll container loses this fight on a touchscreen: a button
## takes the press the moment a finger lands on it, so a finger that starts
## on a button and then moves has already committed to pressing it. On a
## panel that is mostly buttons — which is every panel here — that means the
## panel cannot be scrolled at all without setting something off.
##
## So this takes every touch itself, watches it, and decides afterwards. A
## finger that moves more than a few pixels is scrolling and no button ever
## hears about it. A finger that lifts without moving is a tap, and only
## then is the button under it told. The decision is made from what the
## finger did, not from where it happened to land.

const SLOP: float = 10.0          # movement that turns a tap into a drag
const GLIDE: float = 0.92         # how quickly a flick slows down

var content: Control = null

## Which way this one runs.
##
## A wall of page thumbnails wants to run sideways: pages are read left to
## right, a strip of them is the shape the eye already expects, and stacking
## them in two columns down a narrow panel meant a comic of eight pages showed
## three of them and no way to reach the rest.
##
## One flag rather than a second class. Everything below is the same logic
## with `x` and `y` exchanged, and two copies of a gesture handler is two
## chances for a flick to feel different in two places.
var sideways: bool = false

var _scroll: float = 0.0
var _span: float = 0.0
var _pressing: bool = false
var _dragging: bool = false
var _from: Vector2 = Vector2.ZERO
var _last_y: float = 0.0
var _speed: float = 0.0
var _clip: Control = null
var _left_gutter: float = 0.0
var _max_height: float = 520.0

## True while the press that is running started inside the left strip.
##
## That strip is for moving the list and nothing else. A finger there never
## reaches a control underneath — not on the way down, not on the way up,
## not even if it never moved a pixel. It is the one place on a panel full
## of buttons where a thumb can rest without setting something off, and a
## panel that closed itself the moment that thumb lifted was the reason it
## could not be trusted.
var _in_gutter: bool = false

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(inner: Control, left_gutter: float = 0.0) -> void:
	content = inner
	_left_gutter = maxf(left_gutter, 0.0)
	_max_height = maxf(float(get_meta("max_height", 520.0)), 1.0)
	_clip = Control.new()
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_clip)
	_clip.add_child(content)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_relayout)
	content.resized.connect(_relayout)
	draw.connect(_draw_gutter)
	_relayout()

## A pair of quiet rails down the strip, so it reads as something to pull
## rather than as empty margin.
func _draw_gutter() -> void:
	if sideways or _left_gutter <= 1.0:
		return
	var x: float = _left_gutter * 0.5
	var pad: float = minf(UiKit.s(14.0), size.y * 0.2)
	var col: Color = Color(UiKit.TEXT_DIM.r, UiKit.TEXT_DIM.g,
		UiKit.TEXT_DIM.b, 0.34 if _span > 0.0 else 0.16)
	var w: float = maxf(UiKit.s(2.0), 2.0)
	draw_line(Vector2(x - UiKit.s(3.0), pad),
		Vector2(x - UiKit.s(3.0), size.y - pad), col, w)
	draw_line(Vector2(x + UiKit.s(3.0), pad),
		Vector2(x + UiKit.s(3.0), size.y - pad), col, w)

func _relayout() -> void:
	if content == null:
		return
	var least: Vector2 = content.get_combined_minimum_size()
	if sideways:
		# Height is fixed to the strip and width is whatever the row needs,
		# which is the mirror of the column case below.
		var tall: float = minf(maxf(least.y, 1.0), _max_height)
		if tall > 1.0 and absf(custom_minimum_size.y - tall) > 0.5:
			custom_minimum_size.y = tall
		content.size = Vector2(least.x, maxf(size.y, tall))
		_span = maxf(content.size.x - size.x, 0.0)
		_scroll = clampf(_scroll, 0.0, _span)
		content.position = Vector2(-_scroll, 0.0)
		queue_redraw()
		return
	var usable_w: float = maxf(size.x - _left_gutter, 1.0)
	var content_min_y: float = least.y
	var cap: float = _max_height
	var target_h: float = minf(content_min_y, cap)
	if target_h > 1.0 and absf(custom_minimum_size.y - target_h) > 0.5:
		custom_minimum_size.y = target_h
	content.size = Vector2(usable_w, content_min_y)
	_span = maxf(content.size.y - size.y, 0.0)
	_scroll = clampf(_scroll, 0.0, _span)
	content.position = Vector2(_left_gutter, -_scroll)
	queue_redraw()

## Where the content sits for the scroll it is at. One place, so the four
## callers that move it cannot disagree about which axis is which.
func _at_scroll() -> Vector2:
	if sideways:
		return Vector2(-_scroll, 0.0)
	return Vector2(_left_gutter, -_scroll)

func _process(dt: float) -> void:
	if _dragging or absf(_speed) < 1.0:
		return
	# A flick keeps going and eases off, the way a list should.
	_scroll = clampf(_scroll - _speed * dt, 0.0, _span)
	_speed *= GLIDE
	if content != null:
		content.position = _at_scroll()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_press(st.position)
		else:
			_release(st.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_move((event as InputEventScreenDrag).position)
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release(mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = clampf(_scroll - UiKit.s(48.0), 0.0, _span)
			content.position = _at_scroll()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = clampf(_scroll + UiKit.s(48.0), 0.0, _span)
			content.position = _at_scroll()
	elif event is InputEventMouseMotion and _pressing:
		_move((event as InputEventMouseMotion).position)

func _press(at: Vector2) -> void:
	_pressing = true
	_dragging = false
	_in_gutter = (not sideways) and at.x <= _left_gutter
	_from = at
	_last_y = at.x if sideways else at.y
	_speed = 0.0

func _move(at: Vector2) -> void:
	if not _pressing:
		return
	# In the strip there is nothing to protect a button from, so the list
	# follows the finger straight away rather than after a threshold.
	var along: float = at.x if sideways else at.y
	var from_along: float = _from.x if sideways else _from.y
	if not _dragging and (_in_gutter
			or absf(along - from_along) > SLOP * App.ui_scale):
		_dragging = true
	if not _dragging or _span <= 0.0:
		return
	var step: float = along - _last_y
	_last_y = along
	_scroll = clampf(_scroll - step, 0.0, _span)
	_speed = step * 18.0
	if content != null:
		content.position = _at_scroll()

func _release(at: Vector2) -> void:
	var was_drag: bool = _dragging
	var gutter: bool = _in_gutter
	_pressing = false
	_dragging = false
	_in_gutter = false
	if was_drag or gutter:
		# Scrolled, or scrolling was all that was ever on offer. Either way
		# nothing underneath is told, and the panel stays exactly as it is.
		return
	# A tap, so whatever sits under the finger finally gets to hear about it.
	# The point is moved into the column's own space first: the column is
	# pushed right by the width of the strip, and forgetting that offset is
	# what used to hand a tap to whichever button happened to sit that far
	# to the left of the one being aimed at.
	var local_content_point: Vector2 = at + Vector2(_scroll, 0.0) \
		if sideways else at + Vector2(-_left_gutter, _scroll)
	var target: Control = _control_at(content, local_content_point)
	if target == null:
		return
	if target is Button:
		var b: Button = target as Button
		if b.disabled:
			return
		if b.toggle_mode:
			b.button_pressed = not b.button_pressed
		# Emit the real signal rather than relying on Godot's mouse emulation.
		# This is the mobile path and is deliberately independent of a cursor.
		b.pressed.emit()
	elif target is TouchSlider:
		(target as TouchSlider).tap_at(local_content_point - _global_offset(target))

## The deepest visible control containing the point, searched back to front
## so a button on top of a box wins over the box. Coordinates are kept in the
## scroller's local space; this avoids mixing viewport and child coordinates on
## Android, where the old hit test could miss every button by an offset.
func _control_at(node: Node, at: Vector2) -> Control:
	if node == null:
		return null
	for i in range(node.get_child_count() - 1, -1, -1):
		var child: Node = node.get_child(i)
		if not (child is Control):
			continue
		var c: Control = child as Control
		if not c.visible:
			continue
		var box: Rect2 = Rect2(_global_offset(c), c.size)
		if not box.has_point(at):
			continue
		var deeper: Control = _control_at(c, at)
		return deeper if deeper != null else c
	return null

## Where a control sits relative to the scrolled column.
## `content.position` is intentionally excluded because the release point is
## first moved back by `_scroll`; every descendant is then measured from the
## content origin in one consistent coordinate system.
func _global_offset(c: Control) -> Vector2:
	var out: Vector2 = Vector2.ZERO
	var walk: Node = c
	while walk != null and walk != content:
		if walk is Control:
			out += (walk as Control).position
		walk = walk.get_parent()
	return out
