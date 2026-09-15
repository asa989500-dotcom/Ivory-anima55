class_name ColorWheelControl
extends Control
## Hue ring on the outside, lightness and colourfulness inside.
##
## Everything here is in Oklab, where equal distances are equal differences to
## the eye — so the ring holds one perceived lightness the whole way round and
## the square moves in even steps. See `Oklab` for what that fixes and why the
## old HSV wheel could not.
##
## Whichever zone you press stays active until you lift, so a shaky finger
## cannot jump from the square out to the ring mid-drag.

signal picked(color: Color)
## Fires once when the finger lifts. A drag passes through a hundred colours
## on the way to the one that was meant; only the last of them is a choice.
signal released(color: Color)

const RING_OUTER: float = 0.50
const RING_INNER: float = 0.38

## The chroma the square's right-hand edge asks for. Beyond what any hue can
## actually reach, on purpose: the gamut mapping then gives each hue its own
## strongest honest colour instead of holding every hue back to the weakest.
const MAX_CHROMA: float = 0.37
const RING_LIGHT: float = 0.72

## A turn in radians, not a fraction — this is a hue angle in Oklab, and
## calling it 0..1 would invite it to be confused with the HSV one.
var hue: float = 0.0
## Perceived lightness, 0 to 1.
var light: float = 0.55
## Colourfulness, 0 to MAX_CHROMA.
var chroma: float = 0.0

var _rect: ColorRect = null
var _marks: Control = null
var _mat: ShaderMaterial = null
var _mode: int = 0    # 0 none, 1 ring, 2 square

func _init() -> void:
	# Built here, not in _ready: callers set a colour before the node is
	# ever added to the tree.
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/color_wheel.gdshader")
	_mat.set_shader_parameter("ring_outer", RING_OUTER)
	_mat.set_shader_parameter("ring_inner", RING_INNER)
	_mat.set_shader_parameter("hue", hue / TAU)
	_mat.set_shader_parameter("ring_light", RING_LIGHT)

func _ready() -> void:
	custom_minimum_size = Vector2(UiKit.s(230.0), UiKit.s(230.0))
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	# Added after the wheel, so it draws after it. Sibling order is the
	# whole mechanism — there is no z-index needed and none used.
	_marks = Marks.new()
	_marks.wheel = self
	add_child(_marks)
	queue_redraw()

func set_color(c: Color) -> void:
	var lch: Vector3 = Oklab.from_color(c)
	light = lch.x
	chroma = lch.y
	# A grey has no hue to speak of, and reading the noise out of one would
	# throw the ring somewhere arbitrary. The last real hue is kept instead.
	if lch.y > 0.002:
		hue = lch.z
	if _mat != null:
		_mat.set_shader_parameter("hue", hue / TAU)
	_repaint()

func current() -> Color:
	return Oklab.to_color(light, chroma, hue, 1.0)

## True while a finger is on the ring or the square.
##
## The colour panel listens to App for changes and writes them back into the
## wheel. Mid-drag that write is the wheel's own value returning to it after a
## round trip through Oklab and back, and the small loss each way was enough
## to make the marker crawl away from the finger. It is skipped instead.
func is_adjusting() -> bool:
	return _mode != 0

func _gui_input(event: InputEvent) -> void:
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		if App.touch_mode:
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		pos = mb.position
		if mb.pressed:
			_mode = _zone(pos)
		else:
			var was: int = _mode
			_mode = 0
			if was != 0:
				released.emit(current())
			return
	elif event is InputEventMouseMotion:
		if App.touch_mode or _mode == 0:
			return
		pos = (event as InputEventMouseMotion).position
	elif event is InputEventScreenTouch:
		App.touch_mode = true
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		pos = st.position
		if st.pressed:
			_mode = _zone(pos)
		else:
			var was: int = _mode
			_mode = 0
			if was != 0:
				released.emit(current())
			return
	elif event is InputEventScreenDrag:
		if _mode == 0:
			return
		pos = (event as InputEventScreenDrag).position
	else:
		return

	if _mode == 1:
		_set_hue(pos)
	elif _mode == 2:
		_set_sv(pos)
	accept_event()

func _uv(pos: Vector2) -> Vector2:
	var side: float = minf(size.x, size.y)
	if side <= 0.0:
		return Vector2.ZERO
	var o: Vector2 = (size - Vector2(side, side)) * 0.5
	return (pos - o) / side - Vector2(0.5, 0.5)

func _zone(pos: Vector2) -> int:
	var p: Vector2 = _uv(pos)
	var r: float = p.length()
	if r <= RING_OUTER and r >= RING_INNER:
		return 1
	var half: float = (RING_INNER - 0.035) * 0.7071
	if absf(p.x) <= half and absf(p.y) <= half:
		return 2
	return 0

func _set_hue(pos: Vector2) -> void:
	var p: Vector2 = _uv(pos)
	hue = fposmod(atan2(p.y, p.x), TAU)
	if _mat != null:
		_mat.set_shader_parameter("hue", hue / TAU)
	_repaint()
	picked.emit(current())

func _set_sv(pos: Vector2) -> void:
	var p: Vector2 = _uv(pos)
	var half: float = (RING_INNER - 0.035) * 0.7071
	chroma = clampf((p.x + half) / (2.0 * half), 0.0, 1.0) * MAX_CHROMA
	light = clampf(1.0 - (p.y + half) / (2.0 * half), 0.0, 1.0)
	_repaint()
	picked.emit(current())

## The two markers live on their own node **above** the wheel.
##
## They used to be drawn in this Control's own `_draw`, and were invisible
## underneath the colours — because the wheel is a child `ColorRect` running a
## shader, and in Godot a child draws *after* its parent. Everything painted
## here was being painted over by the very thing it was meant to sit on top
## of. A marker you cannot see on a colour picker is not a cosmetic problem:
## it is the only thing telling you which colour you have.
class Marks extends Control:
	var wheel: ColorWheelControl = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if wheel != null and is_instance_valid(wheel):
			wheel.paint_marks(self)

## Redraws the markers. Called instead of `queue_redraw` everywhere the
## colour changes, because the thing that needs repainting is no longer this
## node but the one above it.
func _repaint() -> void:
	queue_redraw()
	if _marks != null and is_instance_valid(_marks):
		_marks.queue_redraw()

func paint_marks(on: CanvasItem) -> void:
	var side: float = minf(size.x, size.y)
	if side <= 0.0:
		return
	var o: Vector2 = (size - Vector2(side, side)) * 0.5 + Vector2(side, side) * 0.5

	var ring_mid: float = (RING_OUTER + RING_INNER) * 0.5 * side
	var hp: Vector2 = o + Vector2(cos(hue), sin(hue)) * ring_mid
	on.draw_arc(hp, UiKit.s(9.0), 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.95), UiKit.s(2.5), true)
	on.draw_arc(hp, UiKit.s(9.0), 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.55), UiKit.s(1.0), true)

	var half: float = (RING_INNER - 0.035) * 0.7071 * side
	var across: float = clampf(chroma / MAX_CHROMA, 0.0, 1.0)
	var sp: Vector2 = o + Vector2(-half + across * 2.0 * half,
		-half + (1.0 - light) * 2.0 * half)
	# The marker's outline is chosen against the lightness it sits on, and
	# lightness here is the real perceived one — so it is legible everywhere
	# instead of vanishing over yellow the way a value-based test does.
	var edge: Color = Color.BLACK if light > 0.55 else Color.WHITE
	on.draw_arc(sp, UiKit.s(8.0), 0.0, TAU, 24, edge, UiKit.s(2.0), true)

	# Where this hue runs out of screen. Past that line the square keeps
	# drawing colours, but they are all the same colour — the gamut has
	# nothing further to give. Showing the edge is the difference between a
	# square that lies quietly and one that tells the truth.
	var reachable: float = Oklab.max_chroma(light, hue) / MAX_CHROMA
	if reachable < 0.995:
		var x: float = o.x - half + clampf(reachable, 0.0, 1.0) * 2.0 * half
		on.draw_line(Vector2(x, o.y - half), Vector2(x, o.y + half),
			Color(1.0, 1.0, 1.0, 0.22), UiKit.s(1.0))
