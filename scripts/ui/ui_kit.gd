class_name UiKit
extends RefCounted
## One place for every colour, size and widget shape in the app.
## The palette comes from the material the app is named after: bone whites,
## a slate rail, and a single brass accent borrowed from carving tools.

const RAIL: Color       = Color("#1b1c22")
const RAIL_EDGE: Color  = Color("#2c2e37")
const PANEL: Color      = Color("#20222b")
const PANEL_EDGE: Color = Color("#31353f")
const TEXT: Color       = Color("#eae7e0")
const TEXT_DIM: Color   = Color("#9aa0ab")
const ON_RAIL: Color    = Color("#cfc9bb")
const ACCENT: Color     = Color("#d8a24a")
## A fourth colour, taken from the rail and lifted until it reads on ivory.
## Cool where the accent is warm, so a folder outline and a selection can
## never be mistaken for one another — the accent means "this is what you
## are working on" and nothing else may borrow it.
const FOLDER: Color     = Color("#5f6675")

## Nothing in the interface is allowed to be see-through. A control sitting
## over a drawing has to read against whatever the user happened to paint
## underneath it — white paper, black ink, a red wash — and a translucent
## button reads against all three differently. These are the solid fills
## every control is built from.
const RAIL_FILL: Color  = Color("#20222b")
const RAIL_ON: Color    = Color("#33363f")
const CHIP: Color       = Color("#2b2f3a")
const CHIP_HOVER: Color = Color("#363b47")

static var font: Font = null
static var has_wide_font: bool = false
static var scale: float = 1.0

static func s(v: float) -> float:
	return v * scale

## A font covering Arabic, Japanese and Chinese is not something Godot ships
## with, so those languages need one dropped in here. Latin scripts work
## with the built-in font, which is why they are offered unconditionally.
static func load_font() -> void:
	for path in ["res://assets/fonts/ui.ttf", "res://assets/fonts/ui.otf"]:
		if ResourceLoader.exists(path):
			font = load(path)
			has_wide_font = true
			return

## True when the chosen language needs glyphs the built-in font lacks and
## none has been supplied.
static func missing_glyphs() -> bool:
	if has_wide_font:
		return false
	return Lang.current == Lang.L.AR or Lang.current == Lang.L.JA \
		or Lang.current == Lang.L.ZH

## Every visible string passes through here. The English text is the key,
## and the Arabic argument written at the call site is the fallback for the
## rows the table has not reached yet.
static func label_for(en: String, ar: String = "") -> String:
	return Lang.t(en, ar)

## The one plate every floating panel is built on.
##
## Dark, like the timeline, and no longer ivory: a pale panel over a pale
## drawing has no edge to speak of, and the eye has to hunt for where the
## control surface begins. Dark against ivory paper is unmistakable at a
## glance, and it is the same surface the timeline already uses — so the
## interface reads as one thing rather than two.
static func panel_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = PANEL_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(s(14.0)))
	sb.set_content_margin_all(s(14.0))
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	sb.shadow_size = int(s(14.0))
	sb.shadow_offset = Vector2(0.0, s(3.0))
	return sb

static func rail_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = RAIL
	sb.border_color = RAIL_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(s(16.0)))
	sb.set_content_margin_all(s(6.0))
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	sb.shadow_size = int(s(12.0))
	return sb

## A solid backing for anything floating over the canvas.
static func plate(colour: Color, radius: float = 12.0) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(int(s(radius)))
	sb.set_content_margin_all(s(8.0))
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	sb.shadow_size = int(s(10.0))
	return sb

## Wraps a column so a panel taller than the screen can be scrolled rather
## than having its bottom simply cut off. Used by every floating panel, so
## none of them can grow past the edge and hide its own controls.
static func scroller(inner: Control, max_height: float, touch_gutter: float = 46.0) -> TouchScroll:
	var box: TouchScroll = TouchScroll.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.set_meta("max_height", minf(max_height, s(520.0)))
	box.custom_minimum_size = Vector2(0.0, minf(max_height, s(520.0)))
	box.setup(inner, s(touch_gutter))
	return box

static func make_label(text: String, size_px: float = 13.0, col: Color = TEXT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", int(s(size_px)))
	if font != null:
		l.add_theme_font_override("font", font)
	return l

## Icon button for the tool rail. The active state is a brass notch on the
## edge rather than a filled block, so the icon never loses contrast.
static func make_tool_button(icon_path: String, tip: String) -> Button:
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(s(52.0), s(52.0))
	b.toggle_mode = true
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	if ResourceLoader.exists(icon_path):
		b.icon = load(icon_path)
	b.expand_icon = true
	b.add_theme_color_override("icon_normal_color", ON_RAIL)
	b.add_theme_color_override("icon_hover_color", Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", ACCENT)
	b.add_theme_constant_override("icon_max_width", int(s(26.0)))

	# Opaque, not a tint over the canvas: the icon has to stay legible over
	# a black drawing and a white one alike.
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.bg_color = RAIL_FILL
	flat.set_corner_radius_all(int(s(12.0)))
	flat.set_content_margin_all(s(8.0))

	var hover: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
	hover.bg_color = RAIL_ON

	var on: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
	on.bg_color = RAIL_ON
	on.border_color = ACCENT
	on.border_width_left = int(s(3.0))

	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("focus", flat)
	return b

## The smallest anything the user is meant to hit may be, in points.
##
## One number, in one place, so raising it raises everything at once — and so
## a control written tomorrow can be checked against it rather than guessed.
const TOUCH_FLOOR: float = 44.0

static func make_text_button(text: String, wide: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var w: float = s(96.0) if wide else s(64.0)
	# Forty-four points, not thirty-eight.
	#
	# Thirty-eight is a size that works when it is tested with a mouse and
	# fails when it is used with a thumb. Every guideline written from actual
	# measurements of hands — Apple's, Google's, and the accessibility work
	# both are built on — puts the floor at forty-four, because that is about
	# where the miss rate stops climbing. Six points is nothing on screen and
	# is the difference between pressing a button and pressing near it.
	#
	# The floor, not the size: anything that wants to be bigger still sets
	# its own, and there are plenty in this app that do.
	b.custom_minimum_size = Vector2(w, s(TOUCH_FLOOR))
	b.add_theme_font_size_override("font_size", int(s(13.0)))
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	# Brass fills the pressed chip, so its label goes dark to stay legible.
	b.add_theme_color_override("font_pressed_color", Color("#1b1c22"))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.57, 0.62))

	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = CHIP
	n.border_color = PANEL_EDGE
	n.set_border_width_all(1)
	n.set_corner_radius_all(int(s(10.0)))
	n.set_content_margin_all(s(8.0))
	var h: StyleBoxFlat = n.duplicate() as StyleBoxFlat
	h.bg_color = CHIP_HOVER
	var p: StyleBoxFlat = n.duplicate() as StyleBoxFlat
	p.bg_color = ACCENT

	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", n)
	return b

## Labelled slider that keeps its own readout in sync.
## `on_change` is last on purpose, so a multi-line lambda can be passed
## without another argument trailing behind it.
static func slider_row(parent: Control, title: String, min_v: float, max_v: float,
		value: float, step: float, suffix: String, on_change: Callable) -> TouchSlider:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", int(s(0.0)))

	var head: HBoxContainer = HBoxContainer.new()
	var name_l: Label = make_label(title, 12.0, TEXT_DIM)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_l: Label = make_label("", 13.0, TEXT)
	head.add_child(name_l)
	head.add_child(val_l)
	box.add_child(head)

	var sl: TouchSlider = TouchSlider.new()
	sl.setup(min_v, max_v, value, step)
	box.add_child(sl)
	parent.add_child(box)

	var decimals: bool = step < 1.0
	val_l.text = format_value(value, decimals) + suffix
	# Kept on the slider so `slider_set` below can move the row from the
	# outside — the number beside the track belongs to the row, not to the
	# slider, and without this a value changed in code left a stale readout.
	sl.set_meta("readout", val_l)
	sl.set_meta("suffix", suffix)
	sl.set_meta("decimals", decimals)
	sl.value_changed.connect(func(v: float) -> void:
		val_l.text = format_value(v, decimals) + suffix
		on_change.call(v))
	return sl

## Moves a slider row from code without pretending a finger dragged it.
## `on_change` is deliberately not fired: the caller is the one who changed
## the underlying value, so calling back would be telling itself its own news.
static func slider_set(sl: TouchSlider, v: float) -> void:
	if sl == null or not is_instance_valid(sl):
		return
	sl.set_value_silent(v)
	if not sl.has_meta("readout"):
		return
	var l: Label = sl.get_meta("readout") as Label
	if l != null and is_instance_valid(l):
		l.text = format_value(sl.value, bool(sl.get_meta("decimals", false))) \
			+ String(sl.get_meta("suffix", ""))

static func format_value(v: float, decimals: bool) -> String:
	if decimals:
		return "%.2f" % v
	return str(int(round(v)))
