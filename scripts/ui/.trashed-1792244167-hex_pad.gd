class_name HexPad
extends VBoxContainer
## A 16-key pad for entering a colour code.
##
## Deliberately not a text field: on a phone a text field means summoning the
## system keyboard, hunting for A-F among the letters, and losing half the
## panel to the keyboard itself. Sixteen keys is the whole alphabet here.

signal color_chosen(color: Color)

const KEYS: String = "0123456789ABCDEF"

var _digits: String = ""
var _preview: ColorRect = null
var _readout: Label = null

func _ready() -> void:
	add_theme_constant_override("separation", int(UiKit.s(6.0)))

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	add_child(head)

	_preview = ColorRect.new()
	_preview.custom_minimum_size = Vector2(UiKit.s(38.0), UiKit.s(34.0))
	_preview.color = App.ink
	head.add_child(_preview)

	_readout = UiKit.make_label("#", 16.0, UiKit.TEXT)
	_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_readout)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", int(UiKit.s(5.0)))
	grid.add_theme_constant_override("v_separation", int(UiKit.s(5.0)))
	add_child(grid)

	for i in KEYS.length():
		var ch: String = KEYS[i]
		var b: Button = _key(ch)
		b.pressed.connect(func() -> void: _push(ch))
		grid.add_child(b)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	add_child(row)

	var back: Button = _key("<")
	back.tooltip_text = UiKit.label_for("Delete", "حذف")
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_pop)
	row.add_child(back)

	var apply: Button = _key("OK")
	apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply.pressed.connect(_commit)
	row.add_child(apply)

	_refresh()

func set_from_color(c: Color) -> void:
	_digits = c.to_html(false).to_upper()
	_refresh()

func _key(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	# Deliberately tall: 46px is about the smallest target a thumb hits
	# reliably without looking.
	b.custom_minimum_size = Vector2(UiKit.s(46.0), UiKit.s(46.0))
	b.add_theme_font_size_override("font_size", int(UiKit.s(16.0)))
	b.add_theme_color_override("font_color", UiKit.TEXT)
	b.add_theme_color_override("font_pressed_color", Color("#1b1c22"))

	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = Color("#ece5d7")
	n.set_corner_radius_all(int(UiKit.s(9.0)))
	var h: StyleBoxFlat = n.duplicate() as StyleBoxFlat
	h.bg_color = Color("#e3dac7")
	var p: StyleBoxFlat = n.duplicate() as StyleBoxFlat
	p.bg_color = UiKit.ACCENT

	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", n)
	return b

func _push(ch: String) -> void:
	if _digits.length() >= 6:
		_digits = ""
	_digits += ch
	_refresh()
	if _digits.length() == 6:
		_commit()

func _pop() -> void:
	if _digits.length() > 0:
		_digits = _digits.substr(0, _digits.length() - 1)
	_refresh()

func _commit() -> void:
	var c: Color = _current()
	if c.a < 0.0:
		return
	color_chosen.emit(c)

func _current() -> Color:
	var text: String = _digits
	while text.length() < 6:
		text += "0"
	var html: String = "#" + text
	if not html.is_valid_html_color():
		return Color(0.0, 0.0, 0.0, -1.0)
	return Color(html)

func _refresh() -> void:
	_readout.text = "#" + _digits + "_".repeat(6 - _digits.length())
	var c: Color = _current()
	if c.a >= 0.0:
		_preview.color = c
