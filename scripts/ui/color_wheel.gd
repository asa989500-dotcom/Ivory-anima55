class_name ColorWheel
extends Control
## A colour wheel, because a grid of ten squares is not a colour picker.
##
## ## What was there
##
## Ten fixed swatches. They are good swatches — a set of drawings made from one
## short palette looks like a set, which is why they exist and why they stay —
## but they are the whole of the choice. Any colour that is not one of the ten
## cannot be reached at all: no half-tone for shading, no wash, no picking the
## grey that is already in the drawing.
##
## ## What this is
##
## Hue around, saturation outward, and brightness on a bar beneath. The three
## coordinates of HSV, laid out the way every drawing program lays them out,
## so a hand that has used any of them already knows this one.
##
## ## Two details that decide whether it is usable with a finger
##
## **The marker is drawn, not themed.** It is a ring with a dark outline and a
## light one, so it can be seen on yellow and on navy — a single-colour marker
## disappears against half the wheel, which is the half you are looking at
## when you need it.
##
## **A drag keeps picking.** Lifting and re-tapping to nudge a colour is how a
## picker gets described as fiddly. The finger goes down anywhere on the wheel
## and the colour follows it until it lifts, including outside the wheel —
## where saturation simply clamps at full rather than the pick stopping dead.
##
## ## Why the wheel is an image and not a shader
##
## It is built once, at the size it will be drawn, and kept. A shader would be
## fewer lines and would re-run on every frame of a drag for a picture that
## never changes. The build is a few thousand pixels of trigonometry and
## happens when the panel opens.

signal picked(colour: Color)

## How much of the control's width the wheel takes. The rest is the brightness
## bar and the gap.
const BAR_H: float = 26.0
const GAP: float = 10.0

var _hue: float = 0.0
var _sat: float = 0.0
var _val: float = 1.0

var _wheel: ImageTexture = null
var _wheel_size: int = 0
var _dragging_wheel: bool = false
var _dragging_bar: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(0.0, UiKit.s(210.0))
	mouse_filter = Control.MOUSE_FILTER_STOP

## Puts the wheel on a colour without emitting. Used when the panel opens and
## whenever the colour is changed from somewhere else, so the marker never
## disagrees with the ink actually loaded.
func show_colour(c: Color) -> void:
	_hue = c.h
	_sat = c.s
	# A pure black or white has no meaningful hue, and reading one back would
	# throw away where the marker was. Only the parts that mean something are
	# taken.
	if c.s > 0.001:
		_hue = c.h
	_val = c.v
	queue_redraw()

func colour() -> Color:
	return Color.from_hsv(_hue, _sat, _val, 1.0)

# ------------------------------------------------------------------ layout

func _wheel_rect() -> Rect2:
	var side: float = minf(size.x, size.y - UiKit.s(BAR_H) - UiKit.s(GAP))
	side = maxf(side, 8.0)
	return Rect2((size.x - side) * 0.5, 0.0, side, side)

func _bar_rect() -> Rect2:
	var wheel: Rect2 = _wheel_rect()
	return Rect2(0.0, wheel.end.y + UiKit.s(GAP), size.x, UiKit.s(BAR_H))

# ------------------------------------------------------------------ drawing

## The wheel itself, built once at the size it is drawn.
##
## Anti-aliased at the rim by fading alpha over the last pixel, because a hard
## edge on a circle this size reads as a cog rather than a disc.
func _build_wheel(side: int) -> void:
	side = clampi(side, 16, 512)
	if _wheel != null and _wheel_size == side:
		return
	var img: Image = Image.create(side, side, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid: float = float(side) * 0.5
	var radius: float = mid - 1.0
	for y in side:
		for x in side:
			var dx: float = float(x) + 0.5 - mid
			var dy: float = float(y) + 0.5 - mid
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist > radius + 1.0:
				continue
			var hue: float = fposmod(atan2(dy, dx), TAU) / TAU
			var sat: float = clampf(dist / radius, 0.0, 1.0)
			var c: Color = Color.from_hsv(hue, sat, 1.0, 1.0)
			# The last pixel fades out instead of stopping.
			c.a = clampf(radius + 1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, c)
	_wheel = ImageTexture.create_from_image(img)
	_wheel_size = side

func _draw() -> void:
	var wheel: Rect2 = _wheel_rect()
	_build_wheel(int(wheel.size.x))
	if _wheel != null:
		# Darkened by the brightness, which is exactly what value does to RGB.
		# Doing it here rather than rebuilding the wheel means the brightness
		# bar is free to drag.
		draw_texture_rect(_wheel, wheel, false, Color(_val, _val, _val, 1.0))

	# The marker.
	var mid: Vector2 = wheel.get_center()
	var radius: float = wheel.size.x * 0.5 - 1.0
	var at: Vector2 = mid + Vector2(cos(_hue * TAU), sin(_hue * TAU)) * (_sat * radius)
	var r: float = UiKit.s(9.0)
	# Two rings, dark under light. One ring can always be lost against the
	# wheel; two of opposite tone cannot.
	draw_arc(at, r + 1.0, 0.0, TAU, 28, Color(0, 0, 0, 0.75), 3.0, true)
	draw_arc(at, r, 0.0, TAU, 28, Color(1, 1, 1, 0.95), 2.0, true)

	# The brightness bar, black to the full-saturation hue.
	var bar: Rect2 = _bar_rect()
	var pure: Color = Color.from_hsv(_hue, _sat, 1.0, 1.0)
	draw_rect(bar, Color(0.1, 0.1, 0.1, 1.0))
	var steps: int = maxi(int(bar.size.x / 3.0), 8)
	for i in steps:
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		draw_rect(Rect2(bar.position.x + bar.size.x * t0, bar.position.y,
			bar.size.x * (t1 - t0) + 1.0, bar.size.y),
			Color(pure.r * t0, pure.g * t0, pure.b * t0, 1.0))
	var knob_x: float = bar.position.x + bar.size.x * _val
	draw_rect(Rect2(knob_x - UiKit.s(3.0), bar.position.y - 2.0,
		UiKit.s(6.0), bar.size.y + 4.0), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(knob_x - UiKit.s(2.0), bar.position.y - 1.0,
		UiKit.s(4.0), bar.size.y + 2.0), Color(1, 1, 1, 0.95))

# ------------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	var down: bool = false
	var pressed: bool = false
	var at: Vector2 = Vector2.ZERO
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		down = true
		pressed = touch.pressed
		at = touch.position
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		down = true
		pressed = click.pressed
		at = click.position
	elif event is InputEventScreenDrag:
		at = (event as InputEventScreenDrag).position
	elif event is InputEventMouseMotion:
		at = (event as InputEventMouseMotion).position
	else:
		return

	if down and pressed:
		# Which control the finger landed on is decided once, on the press.
		# Deciding it every frame would let a drag that started on the wheel
		# jump to the bar the moment it crossed it.
		_dragging_bar = _bar_rect().has_point(at)
		_dragging_wheel = not _dragging_bar
	elif down and not pressed:
		_dragging_wheel = false
		_dragging_bar = false
		return
	elif not _dragging_wheel and not _dragging_bar:
		return

	if _dragging_bar:
		var bar: Rect2 = _bar_rect()
		_val = clampf((at.x - bar.position.x) / maxf(bar.size.x, 1.0), 0.0, 1.0)
	else:
		var wheel: Rect2 = _wheel_rect()
		var mid: Vector2 = wheel.get_center()
		var radius: float = maxf(wheel.size.x * 0.5 - 1.0, 1.0)
		var d: Vector2 = at - mid
		_hue = fposmod(atan2(d.y, d.x), TAU) / TAU
		# Clamped rather than refused. A finger that slides off the rim while
		# choosing a strong colour means "more of that", not "stop".
		_sat = clampf(d.length() / radius, 0.0, 1.0)
	queue_redraw()
	picked.emit(colour())
