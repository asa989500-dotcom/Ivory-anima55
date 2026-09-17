class_name TimelineFocusMenu
extends RefCounted
## The sheet that says how a focus line behaves.
##
## Lifted out of `timeline_panel.gd` at stage 153, unchanged. That file is one
## of the project's long-standing debts, and the size ledger's rule is that a
## file may grow only if the growth is paid for out of another — so the
## timeline gaining a cached scene index is paid for here.
##
## It lifts along a real seam. Everything in it answers one question — what
## kind of softness this line brings on, how much of it, and through what
## shape of iris — and nothing else in the band needs to know any of it.
## `TimelinePanel` keeps a one-line delegate, so no caller moved.

static func open(p: TimelinePanel, one: Anim.Focus) -> void:
	var sheet: PanelContainer = p._sheet()
	var v: VBoxContainer = p._sheet_column(sheet,
		UiKit.label_for("Depth of field", "عمق الميدان"))
	p._sheet_note(v, UiKit.label_for(
		"Everything without a focus line of its own goes soft while this one runs.",
		"كل ما ليس عليه خط تركيز خاص به يصبح ضبابياً ما دام هذا الخط ممتداً."))

	var cut: Button = UiKit.make_text_button(
		UiKit.label_for("Full blur, no build-up", "ضبابية كاملة بلا تدرج"), true)
	cut.toggle_mode = true
	cut.set_pressed_no_signal(one.mode == Anim.Blur.HARD)
	cut.pressed.connect(func() -> void:
		one.mode = Anim.Blur.HARD
		p._apply_focus()
		p._dirty()
		p._shutp._sheet()
		p.refresh())
	v.add_child(cut)

	var pull: Button = UiKit.make_text_button(
		UiKit.label_for("Cinematic fade", "تلاشٍ سينمائي"), true)
	pull.toggle_mode = true
	pull.set_pressed_no_signal(one.mode == Anim.Blur.CINEMATIC)
	pull.pressed.connect(func() -> void:
		one.mode = Anim.Blur.CINEMATIC
		p._apply_focus()
		p._dirty()
		p._shutp._sheet()
		p.refresh())
	v.add_child(pull)
	p._sheet_note(v, UiKit.label_for(
		"The blur comes on across the first quarter of the line and holds for the rest, the way a focus pull settles.",
		"تأتي الضبابية عبر الربع الأول من الخط وتثبت في بقيته، كما تستقر نقلة التركيز."))

	UiKit.slider_row(v, UiKit.label_for("How soft", "مقدار الضبابية"),
		0.15, 1.0, one.strength, 0.05, "",
		func(x: float) -> void:
			one.strength = x
			p._apply_focus()
			p._dirty())

	# --- the iris ---
	#
	# What shape the softness is, rather than how much of it there is.
	#
	# A lens spreads a point of light across the opening it is looking
	# through, so an out-of-focus highlight comes out as the shape of that
	# opening: a hexagon behind a portrait shot at six blades, a rounder one
	# at nine, a perfect disc only on a lens wide open or on one that never
	# existed. It is the single detail that separates a defocused image from a
	# blurred one, and until now this app only had the blurred one.
	v.add_child(HSeparator.new())
	p._vlabel(v, UiKit.label_for("Shape of the iris", "شكل الحدقة"))
	var iris_rows: Array = [
		[0, UiKit.label_for("Round", "دائرية")],
		[6, UiKit.label_for("Six blades", "ست شفرات")],
		[7, UiKit.label_for("Seven blades", "سبع شفرات")],
		[9, UiKit.label_for("Nine blades", "تسع شفرات")],
	]
	var iris_grid: GridContainer = GridContainer.new()
	iris_grid.columns = 2
	iris_grid.add_theme_constant_override("h_separation", int(UiKit.s(5.0)))
	iris_grid.add_theme_constant_override("v_separation", int(UiKit.s(5.0)))
	v.add_child(iris_grid)
	var iris_buttons: Array = []
	for i in iris_rows.size():
		var leaves: int = int(iris_rows[i][0])
		var index: int = i
		var b: Button = UiKit.make_text_button(String(iris_rows[i][1]), true)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_pressed_no_signal(leaves == one.blades)
		b.pressed.connect(func() -> void:
			one.blades = leaves
			for k in iris_buttons.size():
				(iris_buttons[k] as Button).set_pressed_no_signal(k == index)
			p._apply_focus()
			p._dirty()
			p.refresh())
		iris_buttons.append(b)
		iris_grid.add_child(b)
	p._sheet_note(v, UiKit.label_for(
		"Fewer blades give a more angular highlight. Six is what most lenses do; round is a lens wide open.",
		"كلما قلّت الشفرات صار وميض الخلفية أكثر زواية. والست هي ما تفعله أغلب العدسات، والدائرية عدسة مفتوحة على آخرها."))

	v.add_child(HSeparator.new())
	var armed: Array = [false]
	var kill: Button = UiKit.make_text_button(
		UiKit.label_for("Remove this focus line", "احذف خط التركيز"), true)
	kill.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			kill.text = UiKit.label_for("Tap again to delete", "اضغط ثانية للحذف")
			return
		p.clip.drop_focus(one)
		p._apply_focus()
		p._dirty()
		p._shutp._sheet()
		p.rebuild())
	v.add_child(kill)
	p._float_sheet(sheet)

# ------------------------------------------------------------- the camera

## The camera, in the order it is met.
##
## The first press puts a camera in the scene: a row appears above every
## layer, the frame is drawn on the page, and the first key is set right
## there so the shot has a starting pose. Every press after that adds a key
## at the playhead.
