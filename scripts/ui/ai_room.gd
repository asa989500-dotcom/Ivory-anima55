class_name AiRoom
extends PanelContainer
## AI-powered image design — the place where you talk to the model.
##
## Reached from the compass, beside B-Spline, because it is the same kind of
## thing: a room you go into to make something, not a tool you hold. Its mark
## is the one you supplied.
##
## A conversation rather than a single box with a Generate button, and that is
## the whole design. Nobody describes a picture correctly the first time. What
## actually happens is "a knight" → too plain → "a knight in silver armour" →
## wrong angle → "…, seen from below". Each of those is a small edit of the
## last, and a form that throws the words away between attempts makes the user
## retype the sentence every time. Here the thread stays: every attempt is on
## screen with the picture it produced, and the box keeps the words so the
## next try is an edit rather than a rewrite.
##
## Two ways to ask, exactly as specified:
##
##   **Words alone** — a picture from nothing but the description.
##   **Words and the drawing** — the layer being worked on goes up with the
##   description, and what comes back is that drawing, improved and guided.
##
## And three things to do with what comes back: put it into the project, keep
## it in the conversation's memory, or save it to the device. Plus bringing a
## picture in from the device to work from.

signal wants_layer_sketch(into: Array)
signal wants_place(picture: Image)
signal wants_import()
signal closed()

## How far the model may travel from the drawing, when there is one.
const KEEP_CLOSE: float = 0.35
const KEEP_LOOSE: float = 0.75

var assistant: AIAssistant = null

var _thread: VBoxContainer = null
var _box: TextEdit = null
var _with_art: CheckBox = null
var _travel: float = 0.5
var _last: Image = null
var _sent_for: int = -1
## Pictures the conversation has been told to hold on to.
var _kept: Array = []

## Who is being drawn, held for the length of the conversation.
##
## Established from the first description and then attached to everything
## after it. This is why the third attempt is the same character as the
## first rather than a third person who dresses similarly — and why editing
## the drawing and then asking for another angle gives back the drawing as
## edited. See `ai_identity.gd`.
var _who: AiIdentity = null
var _lock: CheckBox = null

func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	mouse_filter = Control.MOUSE_FILTER_STOP

func build(who: AIAssistant) -> void:
	assistant = who
	assistant.finished.connect(_on_picture)
	assistant.failed.connect(_on_trouble)

	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.s(9.0)))
	add_child(v)

	var head: HBoxContainer = HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiKit.make_label(
		UiKit.label_for("AI-powered image design",
			"تصميم الصور بالذكاء الاصطناعي"), 15.0, UiKit.TEXT))
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var shut: Button = UiKit.make_text_button(UiKit.label_for("Close", "إغلاق"))
	shut.pressed.connect(func() -> void: closed.emit())
	head.add_child(shut)

	if not AIAssistant.key_ready():
		var warn: Label = UiKit.make_label(UiKit.label_for(
			"No API key yet — put one on the API_TOKEN line in scripts/ai_assistant.gd.",
			"لا يوجد مفتاح API بعد — ضعه في سطر API_TOKEN في scripts/ai_assistant.gd."),
			11.0, UiKit.ACCENT)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(warn)

	# --- the conversation ---
	_thread = VBoxContainer.new()
	_thread.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	v.add_child(UiKit.scroller(_thread, UiKit.s(300.0)))
	_said(UiKit.label_for(
		"Describe what you want. Tick the box below to send the drawing on the current layer along with the words, and it will be improved rather than replaced.",
		"صف ما تريد. علّم المربع أدناه لإرسال الرسم الذي على الطبقة الحالية مع الكلمات، فيُحسَّن بدل أن يُستبدل."),
		false)

	v.add_child(HSeparator.new())

	# --- what to say ---
	_box = TextEdit.new()
	_box.custom_minimum_size = Vector2(0.0, UiKit.s(74.0))
	_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_box.placeholder_text = UiKit.label_for(
		"an anime character in silver armour",
		"شخصية أنمي ترتدي درعاً فضياً")
	v.add_child(_box)

	_lock = CheckBox.new()
	_lock.text = UiKit.label_for("Keep it the same character",
		"أبقِها الشخصية نفسها")
	_lock.button_pressed = true
	v.add_child(_lock)

	_with_art = CheckBox.new()
	_with_art.text = UiKit.label_for("Use the drawing on this layer",
		"استعمل الرسم الذي على هذه الطبقة")
	v.add_child(_with_art)

	UiKit.slider_row(v, UiKit.label_for("How far it may stray",
		"كم يبتعد عن رسمك"), KEEP_CLOSE, KEEP_LOOSE, 0.5, 0.05, "",
		func(x: float) -> void: _travel = x)

	var send: Button = UiKit.make_text_button(
		UiKit.label_for("Make it", "نفّذ"), true)
	send.pressed.connect(_ask)
	v.add_child(send)

	v.add_child(HSeparator.new())

	# --- what to do with a picture, once there is one ---
	var acts: HBoxContainer = HBoxContainer.new()
	acts.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	v.add_child(acts)

	var bring: Button = UiKit.make_text_button(
		UiKit.label_for("Import a picture", "استيراد صورة"))
	bring.pressed.connect(func() -> void: wants_import.emit())
	acts.add_child(bring)

	var keep: Button = UiKit.make_text_button(
		UiKit.label_for("Keep it here", "احفظها هنا"))
	keep.pressed.connect(_keep_last)
	acts.add_child(keep)

	var into: Button = UiKit.make_text_button(
		UiKit.label_for("Into the project", "إلى المشروع"))
	into.pressed.connect(func() -> void:
		if _last != null:
			wants_place.emit(_last))
	acts.add_child(into)

	var save: Button = UiKit.make_text_button(
		UiKit.label_for("Save to device", "حفظ في الجهاز"))
	save.pressed.connect(_save_last)
	acts.add_child(save)

# ------------------------------------------------------------------- asking

func _ask() -> void:
	if assistant == null or _box == null:
		return
	var words: String = _box.text.strip_edges()
	if words == "":
		_said(UiKit.label_for("Write something first", "اكتب شيئاً أولاً"),
			false)
		return
	_said(words, true)

	# The first description establishes who this is; everything after it is
	# asked of that same character unless the artist unticks the box.
	if _lock != null and _lock.button_pressed:
		if _who == null:
			_who = AiIdentity.make("", words)
			_said(UiKit.label_for(
				"This is the character now. Everything you ask for after this is the same one — same face, same clothes, same colours — until you untick the box.",
				"صارت هذه هي الشخصية. وكل ما تطلبه بعدها هو نفسها — الوجه نفسه والملابس نفسها والألوان نفسها — حتى تُلغِ علامة المربع."),
				false)
	else:
		_who = null

	if _with_art != null and _with_art.button_pressed:
		# The canvas hands the drawing over rather than this reaching into
		# it: the room has no business knowing about layers, projects or
		# which page is open.
		var basket: Array = []
		wants_layer_sketch.emit(basket)
		var sketch: Image = basket[0] if not basket.is_empty() else null
		if sketch == null:
			_said(UiKit.label_for(
				"There is nothing drawn on this layer, so the words go alone.",
				"لا يوجد رسم على هذه الطبقة، فتذهب الكلمات وحدها."), false)
		else:
			_sent_for = assistant.improve(sketch, words, _travel,
				{"from": "room"}, _who)
			return
	_sent_for = assistant.imagine(words, Vector2i(1024, 1024),
		{"from": "room"}, _who)

func _on_picture(id: int, picture: Image, texture: ImageTexture,
		job: Dictionary) -> void:
	if String((job.get("tag", {}) as Dictionary).get("from", "")) != "room":
		return
	if id != _sent_for:
		return
	_last = picture
	# The palette is re-read from what actually came back, so the fourth
	# request is anchored to the third picture rather than to the first
	# description. A character drifts one shade at a time otherwise.
	if _who != null:
		var flat: Image = picture.duplicate()
		AIAssistant._straighten(flat)
		_who.refresh_from(flat)
	_shown(texture)

func _on_trouble(id: int, why: String) -> void:
	if id != _sent_for and id != -1:
		return
	_said(why, false)

# ------------------------------------------------------------------- keeping

## Held in memory for the length of the conversation, so a picture that was
## nearly right can be come back to after three that were not.
func _keep_last() -> void:
	if _last == null:
		_said(UiKit.label_for("There is nothing to keep yet",
			"لا يوجد شيء لحفظه بعد"), false)
		return
	_kept.append(_last)
	_said(UiKit.label_for("Kept — %d in this conversation" % _kept.size(),
		"حُفظت — %d في هذه المحادثة" % _kept.size()), false)

## Written where the gallery can see it, like every other export in the app.
func _save_last() -> void:
	if _last == null:
		_said(UiKit.label_for("There is nothing to save yet",
			"لا يوجد شيء لحفظه بعد"), false)
		return
	var flat: Image = _last.duplicate()
	AIAssistant._straighten(flat)
	var dir: String = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = "user://"
	var path: String = "%s/ivory_ai_%d.png" % [dir,
		int(Time.get_unix_time_from_system())]
	if flat.save_png(path) == OK:
		_said(UiKit.label_for("Saved to %s" % path, "حُفظت في %s" % path),
			false)
	else:
		_said(UiKit.label_for("That could not be saved",
			"تعذّر الحفظ"), false)

## A picture brought in from the device becomes the thing being worked on.
func take_import(picture: Image) -> void:
	_last = picture
	# A picture brought in from the device becomes the character, if one is
	# being kept. This is the door for "here is my drawing — now give me it
	# from the side".
	if _who != null:
		var read: Image = picture.duplicate()
		AIAssistant._straighten(read)
		_who.refresh_from(read)
	var shown: Image = picture.duplicate()
	AIAssistant._straighten(shown)
	_shown(ImageTexture.create_from_image(shown))
	_said(UiKit.label_for(
		"Brought in. Describe a change and tick the box to work from it.",
		"أُدخلت. صف التغيير وعلّم المربع للعمل عليها."), false)

# ------------------------------------------------------------------ the thread

func _said(text: String, by_user: bool) -> void:
	if _thread == null:
		return
	var line: Label = UiKit.make_label(text, 12.0,
		UiKit.TEXT if by_user else UiKit.TEXT_DIM)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if by_user \
		else HORIZONTAL_ALIGNMENT_LEFT
	_thread.add_child(line)

func _shown(texture: ImageTexture) -> void:
	if _thread == null or texture == null:
		return
	var frame: TextureRect = TextureRect.new()
	frame.texture = texture
	frame.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.custom_minimum_size = Vector2(0.0, UiKit.s(190.0))
	_thread.add_child(frame)
