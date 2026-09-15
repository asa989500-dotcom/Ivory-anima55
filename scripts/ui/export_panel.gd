class_name ExportPanel
extends RefCounted
## Everything an MP4 is allowed to be, in one place.
##
## Lifted out of the animation settings, which had grown into two panels
## wearing one hat: how the scene is *timed* on top, and how it is *encoded*
## underneath, with a separator between them doing the work a file should be
## doing. They are asked at different moments by different people — frame
## rate while animating, bitrate while delivering — so they are two panels.
##
## The controls are laid out in the order somebody actually decides them:
## how much of the scene, how big, how good, then the sound, then the two
## numbers almost nobody touches.

static func _shell() -> PanelContainer:
	var shell: PanelContainer = PanelContainer.new()
	shell.add_theme_stylebox_override("panel", UiKit.panel_style())
	shell.custom_minimum_size = Vector2(UiKit.s(310.0), 0.0)
	return shell

static func _column(parent: PanelContainer) -> VBoxContainer:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(UiKit.s(9.0)))
	parent.add_child(outer)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.s(9.0)))
	var scroller: Control = UiKit.scroller(v, UiKit.s(470.0))
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroller)
	return v

static func _title(v: VBoxContainer, text: String) -> void:
	var l: Label = UiKit.make_label(text, 15.0, UiKit.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

static func _note(v: VBoxContainer, text: String) -> void:
	var l: Label = UiKit.make_label(text, 10.0, UiKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

## A row of choices where exactly one is on.
##
## The chosen one is found by comparing against the value the row was built
## with rather than by reading the button's own text, which broke the moment
## a label was translated: "عالٍ" is not "High", and the row silently stopped
## being able to show which option was picked.
static func _choice(v: VBoxContainer, columns: int, options: Array,
		chosen: String, on_pick: Callable) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
	grid.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
	v.add_child(grid)
	var made: Array = []
	for row in options:
		var value: String = String((row as Array)[0])
		var shown: String = String((row as Array)[1])
		var b: Button = UiKit.make_text_button(shown, true)
		b.toggle_mode = true
		b.set_pressed_no_signal(value == chosen)
		b.set_meta("value", value)
		made.append(b)
		grid.add_child(b)
	for one in made:
		var b: Button = one as Button
		b.pressed.connect(func() -> void:
			var picked: String = String(b.get_meta("value"))
			for other in made:
				(other as Button).set_pressed_no_signal(other == b)
			on_pick.call(picked))

# -------------------------------------------------------------- the panel

static func page(host: Node, back: Callable) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)

	var back_btn: Button = UiKit.make_text_button(
		UiKit.label_for("Back", "رجوع"), true)
	back_btn.pressed.connect(back)
	v.add_child(back_btn)
	_title(v, UiKit.label_for("Video export", "تصدير فيديو"))

	var p: ProjectManager.Project = host.current_project()
	if p == null:
		_note(v, UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
		return shell

	_note(v, UiKit.label_for(
		"Professional video export: frame-accurate, streamed, and verified after writing.",
		"تصدير فيديو احترافي: دقيق بالإطارات، متدفق دون حجز المشهد في الذاكرة، ويُتحقق منه بعد الكتابة."))
	_note(v, _encoder_words())
	_note(v, UiKit.label_for("Format", "الصيغة"))
	_choice(v, 2, [
		["mp4_h264", "MP4 / H.264"], ["mp4_hevc", "MP4 / HEVC"],
		["mov_h264", "MOV / H.264"], ["mkv_h264", "MKV / H.264"],
		["webm_vp9", "WebM / VP9"], ["webm_av1", "WebM / AV1"]],
		p.export_format, func(picked: String) -> void:
			p.export_format = picked)
	_note(v, UiKit.label_for("Formats unavailable in this build are rejected before encoding.",
		"الصيغ غير المتاحة في هذه النسخة تُرفض قبل بدء الترميز."))


	# ------------------------------------------------------------- range
	_title(v, UiKit.label_for("How much of the scene", "أي جزء من المشهد"))
	_choice(v, 3, [
		["Timeline", UiKit.label_for("All", "الكل")],
		["Playback", UiKit.label_for("Play range", "نطاق التشغيل")],
		["Custom", UiKit.label_for("Chosen", "محدّد")]],
		p.export_range, func(picked: String) -> void:
			p.export_range = picked)
	var last: int = maxi(p.frames - 1, 0)
	UiKit.slider_row(v, UiKit.label_for("First frame", "أول إطار"),
		0.0, float(maxi(last, 1)), float(p.export_from), 1.0, "",
		func(x: float) -> void: p.export_from = maxi(int(x), 0))
	UiKit.slider_row(v, UiKit.label_for("Last frame", "آخر إطار"),
		0.0, float(maxi(last, 1)), float(p.export_to), 1.0, "",
		func(x: float) -> void: p.export_to = maxi(int(x), 0))
	_note(v, UiKit.label_for(
		"Zero for the last frame means run to the end, so a scene that grows does not need correcting.",
		"صفر في آخر إطار يعني حتى النهاية، فالمشهد الذي يطول لا يحتاج تصحيحاً."))

	# -------------------------------------------------------- resolution
	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("Size", "الحجم"))
	_choice(v, 3, [["Source", UiKit.label_for("As drawn", "كما رُسم")],
		["480p", "480p"], ["720p", "720p"], ["1080p", "1080p"],
		["1440p", "1440p"], ["4K", "4K"]],
		p.export_resolution, func(picked: String) -> void:
			p.export_resolution = picked)

	# ----------------------------------------------------------- quality
	_title(v, UiKit.label_for("Quality", "الجودة"))
	_choice(v, 3, [["Draft", UiKit.label_for("Draft", "مسوّدة")],
		["Good", UiKit.label_for("Good", "جيّدة")],
		["High", UiKit.label_for("High", "عالية")],
		["Maximum", UiKit.label_for("Maximum", "قصوى")],
		["Advanced", UiKit.label_for("Advanced", "متقدّمة")]],
		p.export_quality, func(picked: String) -> void:
			p.export_quality = picked)
	_note(v, UiKit.label_for(
		"Draft is for checking timing. Maximum thinks harder about every frame: the same picture in a smaller file, and slower to write.",
		"المسوّدة لمراجعة التوقيت. والقصوى تفكّر أطول في كل إطار: الصورة نفسها بملف أصغر، لكن الكتابة أبطأ."))

	# ------------------------------------------------------------- sound
	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("Sound", "الصوت"))
	var heard: int = 0
	if p.clip != null and p.clip.audio != null:
		heard = p.clip.audio.live_clips().size()
	var ab: Button = UiKit.make_text_button(_audio_word(p.export_audio), true)
	ab.toggle_mode = true
	ab.set_pressed_no_signal(p.export_audio)
	v.add_child(ab)
	ab.pressed.connect(func() -> void:
		p.export_audio = ab.button_pressed
		ab.text = _audio_word(p.export_audio))
	UiKit.slider_row(v, UiKit.label_for("Sound quality", "جودة الصوت"),
		96.0, 320.0, float(p.export_audio_kbps), 32.0, " kbps",
		func(x: float) -> void:
			p.export_audio_kbps = clampi(int(round(x)), 64, 512))
	if heard > 0:
		_note(v, Lang.fill("{0} sounds will be mixed into this export.",
			[heard], "سيُمزج {0} صوتاً في هذا التصدير."))
	else:
		_note(v, UiKit.label_for(
			"No sounds yet. Press a layer in the timeline and choose Import audio.",
			"لا أصوات بعد. اضغط طبقة في التايم لاين واختر استيراد صوت."))

	# ---------------------------------------------------------- advanced
	v.add_child(HSeparator.new())
	_title(v, UiKit.label_for("Advanced", "متقدّم"))
	_note(v, UiKit.label_for(
		"Only read when Quality is set to Advanced. A lower CRF is a better picture; a bitrate above zero overrides it.",
		"لا تُقرأ إلا إذا كانت الجودة \"متقدّمة\". CRF الأقل صورة أفضل؛ ومعدل البت فوق الصفر يتغلب عليه."))
	UiKit.slider_row(v, "CRF", 10.0, 40.0, float(p.export_crf), 1.0, "",
		func(x: float) -> void: p.export_crf = clampi(int(x), 10, 40))
	UiKit.slider_row(v, UiKit.label_for("Bitrate", "معدل البت"),
		0.0, 50000.0, float(p.export_bitrate) / 1000.0, 250.0, " kbps",
		func(x: float) -> void:
			p.export_bitrate = maxi(int(round(x * 1000.0)), 0))
	_note(v, UiKit.label_for("H.264 profile", "ملف تعريف H.264"))
	_choice(v, 3, [["baseline", "Baseline"], ["main", "Main"],
		["high", "High"]], p.export_profile,
		func(picked: String) -> void: p.export_profile = picked)

	# --------------------------------------------------------- the guess
	v.add_child(HSeparator.new())
	_note(v, _size_words(p))

	var cancel: Button = UiKit.make_text_button(
		UiKit.label_for("Cancel Export", "إلغاء التصدير"), true)
	cancel.pressed.connect(func() -> void: host.cancel_export())
	v.add_child(cancel)
	return shell

## Which encoder is actually going to run, said plainly.
##
## Worth a line because it changes what to expect: the phone's own chip is
## several times faster than software H.264 and does not warm the device,
## and if neither route is present that is something to learn before pressing
## export rather than after.
static func _encoder_words() -> String:
	match Mp4Export.backend_name():
		"MediaCodec":
			if MP4Direct.is_hardware() and true:
				return UiKit.label_for("Using this phone's own video chip.",
					"يستخدم شريحة الفيديو في هذا الهاتف.")
			return UiKit.label_for("Using Android's built-in encoder.",
				"يستخدم مُرمّز أندرويد المدمج.")
		"FFmpeg":
			return UiKit.label_for("Using the software encoder.",
				"يستخدم المُرمّز البرمجي.")
	return UiKit.label_for(
		"No video encoder in this build — MP4 export will not run.",
		"لا يوجد مُرمّز فيديو في هذه النسخة — لن يعمل تصدير MP4.")

static func _audio_word(on: bool) -> String:
	if on:
		return UiKit.label_for("Sound: on", "الصوت: تشغيل")
	return UiKit.label_for("Sound: off", "الصوت: إيقاف")

## Roughly how big and how long, said before the export rather than after.
##
## A two-hour scene at maximum quality is a real decision, and an app that
## only mentions it once the file is four gigabytes has not helped anybody.
static func _size_words(p: ProjectManager.Project) -> String:
	var width: int = Mp4Export.resolution_width(p.export_resolution,
		int(p.page.x), int(p.page.y))
	var quality: Dictionary = Mp4Export.quality_settings(p.export_quality,
		width, p.fps)
	var crf: int = p.export_crf
	var bitrate: int = p.export_bitrate
	if p.export_quality != "Advanced" and p.export_bitrate <= 0:
		crf = int(quality["crf"])
		bitrate = int(quality["bitrate"])
	var mb: float = Mp4Export.estimate_mb(p, width, bitrate, crf,
		p.export_audio_kbps if p.export_audio else 0)
	if mb <= 0.0:
		return ""
	return Lang.fill("Roughly {0} MB", [int(round(mb))],
		"نحو {0} ميغابايت")
