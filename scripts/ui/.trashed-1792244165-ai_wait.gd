class_name AiWait
extends Control
## The mark that says a picture is being made, and how far along it is.
##
## It exists because the failure it prevents is the worst one this feature
## has: a request takes eight seconds, nothing on screen changes, and the user
## taps again. Now there are two requests, both cost money, and the second
## answer overwrites the first. An app that is thinking has to look like it is
## thinking.
##
## Deliberately not a modal. The canvas stays live underneath — drawing while
## a picture is being made is a perfectly reasonable thing to want, and taking
## the app away for the duration would make a slow answer feel like a hang.
## It sits out of the way, says what it is doing, and can be cancelled.

const RING: float = 15.0
const THICK: float = 3.0

var _spin: float = 0.0
var _note: Label = null
var _queued: Label = null
var _stop: Button = null
var _ring: Control = null
var assistant: AIAssistant = null

func _init() -> void:
	# Never swallows a touch aimed at the drawing under it. Only the Cancel
	# takes one.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _ready() -> void:
	# Nothing spins while nothing is being drawn. `_on_busy` turns it back on.
	set_process(false)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var box: PanelContainer = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.panel_style())
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(0.0, UiKit.s(14.0))
	add_child(box)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(10.0)))
	box.add_child(row)

	_ring = Control.new()
	_ring.custom_minimum_size = Vector2(UiKit.s(RING * 2.0 + 6.0),
		UiKit.s(RING * 2.0 + 6.0))
	_ring.draw.connect(_draw_ring)
	row.add_child(_ring)

	var words: VBoxContainer = VBoxContainer.new()
	words.add_theme_constant_override("separation", int(UiKit.s(2.0)))
	row.add_child(words)
	_note = UiKit.make_label(UiKit.label_for("Drawing", "يرسم"), 13.0,
		UiKit.TEXT)
	words.add_child(_note)
	_queued = UiKit.make_label("", 10.0, UiKit.TEXT_DIM)
	words.add_child(_queued)

	_stop = UiKit.make_text_button(UiKit.label_for("Cancel", "إلغاء"))
	_stop.pressed.connect(func() -> void:
		if assistant != null:
			assistant.stop_everything())
	row.add_child(_stop)

## Hooked to the pipeline once, in `main`. Everything after that is automatic:
## any of the three features asking for a picture makes this appear, and the
## last answer landing makes it go.
func watch(who: AIAssistant) -> void:
	assistant = who
	who.busy_changed.connect(_on_busy)
	who.started.connect(func(_id: int, note: String) -> void: _say(note))
	who.progress.connect(func(_id: int, note: String) -> void: _say(note))

func _on_busy(is_busy: bool) -> void:
	visible = is_busy
	set_process(is_busy)
	if is_busy:
		_refresh_queue()

func _say(note: String) -> void:
	if _note != null:
		_note.text = note
	_refresh_queue()

func _refresh_queue() -> void:
	if _queued == null or assistant == null:
		return
	var more: int = assistant.waiting()
	if more <= 0:
		_queued.text = UiKit.label_for("this may take a few seconds",
			"قد يستغرق هذا ثوانٍ")
		return
	_queued.text = UiKit.label_for("%d more waiting" % more,
		"و%d في الانتظار" % more)

func _process(delta: float) -> void:
	# One turn every one and a quarter seconds. Fast enough to read as alive,
	# slow enough not to nag.
	_spin = fposmod(_spin + delta * TAU * 0.8, TAU)
	if _ring != null:
		_ring.queue_redraw()

## An arc rather than a full circle, because a full circle that turns says
## nothing — the gap is the only part of a spinner that tells the eye it is
## moving at all.
func _draw_ring() -> void:
	if _ring == null:
		return
	var centre: Vector2 = _ring.size * 0.5
	var r: float = UiKit.s(RING)
	_ring.draw_arc(centre, r, 0.0, TAU, 48,
		Color(UiKit.TEXT_DIM.r, UiKit.TEXT_DIM.g, UiKit.TEXT_DIM.b, 0.35),
		UiKit.s(THICK), true)
	_ring.draw_arc(centre, r, _spin, _spin + TAU * 0.3, 24,
		UiKit.ACCENT, UiKit.s(THICK), true)
