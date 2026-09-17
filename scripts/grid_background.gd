class_name GridBackground
extends Control
## Draws an endless grid plus coordinate rulers.
##
## Every line is described by two points in world space and transformed on
## the way out, so one routine serves every angle. The earlier version had a
## straight case and a separate turned case, and the turned one quietly
## disagreed — which is why the grid vanished the moment anything rotated.

var view_offset: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0
var view_angle: float = 0.0

const PAPER: Color = Color("#fbfaf7")
const FINE: Color = Color("#e6e3db")
const BOLD: Color = Color("#d2cdc0")
const AXIS: Color = Color("#b08e5a")
const RULER_INK: Color = Color("#9b9280")
const RULER_BG: Color = Color(1.0, 1.0, 1.0, 0.72)

var _font: Font = null
var _font_size: int = 10

## Shown only when the workspace holds nothing at all. One line, because an
## empty grid with no explanation is a dead end, and anything more would be
## decoration on a surface meant to stay clear.
var empty_hint: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_font_size = int(UiKit.s(10.0))

func set_view(offset: Vector2, zoom: float, angle: float = 0.0) -> void:
	view_offset = offset
	view_zoom = zoom
	view_angle = angle
	queue_redraw()

func world_to_screen(w: Vector2) -> Vector2:
	return (w * view_zoom).rotated(view_angle) + view_offset

func screen_to_world(s: Vector2) -> Vector2:
	return (s - view_offset).rotated(-view_angle) / view_zoom

## Grid spacing that always lands between roughly 28 and 280 screen pixels.
func current_step() -> float:
	var raw: float = 64.0 / maxf(view_zoom, 0.00001)
	var mag: float = pow(10.0, floor(log(maxf(raw, 0.0001)) / log(10.0)))
	var step: float = mag
	for m in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0]:
		step = mag * m
		if step * view_zoom >= 28.0:
			break
	return step

## The visible area in world coordinates, built from the four screen corners
## so a turned view still yields the rectangle that actually contains it.
func world_view() -> Rect2:
	var box: Rect2 = Rect2(screen_to_world(Vector2.ZERO), Vector2.ZERO)
	box = box.expand(screen_to_world(Vector2(size.x, 0.0)))
	box = box.expand(screen_to_world(size))
	box = box.expand(screen_to_world(Vector2(0.0, size.y)))
	return box.grow(maxf(box.size.x, box.size.y) * 0.05)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER, true)

	var step: float = current_step()
	_draw_set(step, FINE, 1.0)
	_draw_set(step * 5.0, BOLD, 1.0)

	# origin cross, so you always know where 0,0 is
	var reach: float = size.length() / maxf(view_zoom, 0.0001)
	draw_line(world_to_screen(Vector2(-reach, 0.0)),
		world_to_screen(Vector2(reach, 0.0)), AXIS, 1.5)
	draw_line(world_to_screen(Vector2(0.0, -reach)),
		world_to_screen(Vector2(0.0, reach)), AXIS, 1.5)

	# Rulers read along the screen edge, and a number pinned to an edge
	# stops meaning anything once the paper is tilted.
	if is_zero_approx(view_angle):
		_draw_rulers(step * 5.0)
	_draw_hint()

func _draw_set(step: float, col: Color, width: float) -> void:
	var px: float = step * view_zoom
	if px < 6.0 or px > 4000.0:
		return
	var box: Rect2 = world_view()
	var left: float = box.position.x
	var right: float = box.position.x + box.size.x
	var top: float = box.position.y
	var bottom: float = box.position.y + box.size.y

	var x: float = floor(left / step) * step
	var guard: int = 0
	while x <= right and guard < 3000:
		draw_line(world_to_screen(Vector2(x, top)),
			world_to_screen(Vector2(x, bottom)), col, width)
		x += step
		guard += 1

	var y: float = floor(top / step) * step
	guard = 0
	while y <= bottom and guard < 3000:
		draw_line(world_to_screen(Vector2(left, y)),
			world_to_screen(Vector2(right, y)), col, width)
		y += step
		guard += 1

func _draw_hint() -> void:
	if empty_hint == "" or _font == null:
		return
	draw_string(_font, Vector2(0.0, size.y * 0.5), empty_hint,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, int(UiKit.s(15.0)),
		Color(0.62, 0.59, 0.53))

## Small numbers along the top and left edges — enough to place a mark
## exactly, not enough to fight with the drawing.
func _draw_rulers(step: float) -> void:
	if _font == null:
		return
	var px: float = step * view_zoom
	if px < 44.0 or px > 4000.0:
		return

	var pad: float = UiKit.s(3.0)
	var band: float = float(_font_size) + pad * 2.0
	draw_rect(Rect2(0.0, 0.0, size.x, band), RULER_BG, true)
	draw_rect(Rect2(0.0, band, band, size.y - band), RULER_BG, true)

	var top_left: Vector2 = screen_to_world(Vector2.ZERO)
	var bottom_right: Vector2 = screen_to_world(size)

	var x: float = floor(top_left.x / step) * step
	var guard: int = 0
	while x <= bottom_right.x and guard < 400:
		var sx: float = world_to_screen(Vector2(x, 0.0)).x
		if sx > band:
			draw_string(_font, Vector2(sx + pad, float(_font_size) + pad * 0.5),
				fmt(x, step), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, RULER_INK)
		x += step
		guard += 1

	var y: float = floor(top_left.y / step) * step
	guard = 0
	while y <= bottom_right.y and guard < 400:
		var sy: float = world_to_screen(Vector2(0.0, y)).y
		if sy > band:
			draw_string(_font, Vector2(pad, sy - pad),
				fmt(y, step), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, RULER_INK)
		y += step
		guard += 1

## Precision follows the zoom: whole numbers when far out, decimals when close.
static func fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return str(int(round(v)))
	elif step >= 0.1:
		return "%.1f" % v
	elif step >= 0.01:
		return "%.2f" % v
	return "%.3f" % v
