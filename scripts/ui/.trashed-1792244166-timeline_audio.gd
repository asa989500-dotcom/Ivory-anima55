class_name TimelineAudio
extends RefCounted
## One imported sound, drawn as a row in a layer's timeline sheet.
##
## Its own file rather than more of `timeline_panel.gd`, which is already the
## second-longest thing in the project. A row of controls for one clip has no
## business knowing about scrubbing, pinch-zoom or onion skin, and it does
## not: it is handed the clip, the track it belongs to, and three things to
## call when something changes.

## A quiet line under a control, in the panel's own dim ink.
static func _note(v: VBoxContainer, text: String) -> void:
	var l: Label = UiKit.make_label(text, 10.0, UiKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

## One sound in the list: what it is, where it starts, how loud, and the two
## ways to be rid of it — silenced, or gone.
static func row(v: VBoxContainer, track: AudioTrack, one: AudioTrack.Clip,
		reach: int, dirty: Callable, redraw: Callable, shut: Callable) -> void:
	var head: Label = UiKit.make_label(one.title, 13.0, UiKit.TEXT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(head)
	var said: String = ""
	if one.missing():
		said = UiKit.label_for("The file has moved or been deleted",
			"الملف نُقل أو حُذف")
	elif one.seconds > 0.0:
		said = "%s  ·  %s" % [_clock(one.seconds),
			Lang.fill("starts at frame {0}", [one.start_frame + 1],
				"يبدأ عند الإطار {0}")]
	else:
		said = Lang.fill("starts at frame {0}", [one.start_frame + 1],
			"يبدأ عند الإطار {0}")
	_note(v, said)

	UiKit.slider_row(v, UiKit.label_for("Start frame", "إطار البداية"),
		0.0, float(maxi(reach, 48)), float(one.start_frame), 1.0, "",
		func(x: float) -> void:
			one.start_frame = maxi(int(round(x)), 0)
			dirty.call()
			redraw.call())
	UiKit.slider_row(v, UiKit.label_for("Volume", "مستوى الصوت"),
		0.0, 2.0, one.gain, 0.05, "",
		func(x: float) -> void:
			one.gain = clampf(x, 0.0, 2.0)
			dirty.call())

	# Named `buttons`, not `row`: this file's own entry point is called `row`,
	# and a local of the same name means that inside these few lines the
	# function cannot be reached by its own name.
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	v.add_child(buttons)
	var mute: Button = UiKit.make_text_button(
		UiKit.label_for("Silent", "مكتوم") if one.muted
		else UiKit.label_for("Playing", "يعمل"), false)
	mute.toggle_mode = true
	mute.set_pressed_no_signal(one.muted)
	mute.pressed.connect(func() -> void:
		one.muted = mute.button_pressed
		mute.text = UiKit.label_for("Silent", "مكتوم") if one.muted \
			else UiKit.label_for("Playing", "يعمل")
		dirty.call())
	buttons.add_child(mute)
	var drop: Button = UiKit.make_text_button(
		UiKit.label_for("Remove", "إزالة"), false)
	drop.pressed.connect(func() -> void:
		track.remove(one)
		dirty.call()
		shut.call())
	buttons.add_child(drop)
	v.add_child(HSeparator.new())

## Seconds as minutes and seconds, in the reader's own digits.
##
## Padded before the digits are converted rather than after. `pad_zeros` adds
## an ASCII nought, and an ASCII nought in front of an Arabic-Indic number is
## the one place a clock reads as two different alphabets at once.
static func _clock(seconds: float) -> String:
	var whole: int = int(round(seconds))
	var minutes: int = floori(float(whole) / 60.0)
	return "%s:%s" % [Lang.number(minutes),
		Lang.digits(str(whole - minutes * 60).pad_zeros(2))]
