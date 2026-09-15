class_name ToolPanels
extends RefCounted
## Each builder returns a finished PanelContainer. Panels are pure UI —
## they only ever write to App, and the canvas reads from App.
##
## One rule runs through the whole file and is worth stating once, because
## breaking it is what put an error on line 88 of the previous version:
## a lambda in GDScript captures the names it can see **at the moment it is
## written**, not at the moment it runs. So every Callable here is declared
## after everything it calls and before everything that calls it. Where two
## want each other, the shared state goes in an Array or Dictionary declared
## first — those are held by reference, so filling them later is seen.

const RECENT_SLOTS: int = 12

## The ten. Named here rather than in the colour panel so that the fill panel
## and the brush panel cannot drift apart, which is what happened the last
## time a colour was added to one of them.
const PALETTE: Array = [
	"#1B1C22",  # ink, the near-black everything is drawn with
	"#FFF8E7",  # ivory, the app's own light
	"#C0392B",  # red
	"#E67E22",  # orange
	"#F1C40F",  # yellow
	"#1E8449",  # green
	"#2A6D80",  # the room blue
	"#6C3483",  # violet
	"#8D6E5C",  # a warm neutral, for skin and wood
	"#000000",  # true black, which the ink deliberately is not
]

## Wide enough for a row of five shape buttons and a slider with its number
## on the end. At 250 the right-hand half of every row was being cut off —
## the size and opacity readouts, and two of the five shapes.
##
## The cap is a share of the screen rather than a number, so the panel is
## generous on a tablet and still fits a phone held upright.
static func _shell(width: float = 330.0) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.panel_style())
	var room: float = 640.0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		room = tree.root.get_visible_rect().size.x * 0.94
	p.set_meta("desired_width", minf(UiKit.s(maxf(width, 410.0)), room))
	p.custom_minimum_size = Vector2(0.0, 0.0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p

## Inside a scroller for the same reason the settings pages are: a panel
## that outgrows the screen must still be able to reach its own end.
static func _column(parent: PanelContainer, tall: float = 470.0) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.s(10.0)))
	# Never taller than the screen it has to fit on. The cap used to be a
	# flat number, so on a short screen a panel simply ran off the bottom and
	# the last rows could not be reached at all.
	var room: float = UiKit.s(tall)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		room = minf(room, tree.root.get_visible_rect().size.y * 0.84)
	parent.add_child(UiKit.scroller(v, room))
	return v

static func _title(v: VBoxContainer, en: String, ar: String) -> void:
	v.add_child(UiKit.make_label(UiKit.label_for(en, ar), 15.0, UiKit.TEXT))

static func _note_line(v: VBoxContainer, text: String) -> void:
	var l: Label = UiKit.make_label(text, 11.0, UiKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

static func _rule(v: VBoxContainer) -> void:
	v.add_child(HSeparator.new())

## One exclusive group of buttons, built once and used by five panels.
##
## Every one of those panels had its own copy of the same twelve lines: build
## the buttons, remember which index is which, then a second loop wiring each
## press to un-press the others. Five copies is five chances to get the
## un-pressing subtly wrong, and one of them — the symmetry counts — had in
## fact drifted, comparing button *labels* to decide which was active, so two
## choices that happened to read the same would have lit together.
##
## `entries` is rows of [value, English, Arabic]. The value is what reaches
## `on_pick`, so callers pass their enum straight through and never juggle
## positions against meanings.
##
## `on_pick` is the last argument on purpose, as it is everywhere else in
## this project: GDScript will not parse a lambda with a body spread over
## several lines if another argument trails behind it.
static func _choice(parent: VBoxContainer, entries: Array, current: int,
		columns: int, wide: bool, on_pick: Callable) -> Array[Button]:
	var box: Container
	if columns > 1:
		var grid: GridContainer = GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
		grid.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
		box = grid
	else:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
		box = row
	parent.add_child(box)

	var btns: Array[Button] = []
	# Declared before the loop that captures it, and reading from `entries`
	# rather than from the button faces, so a label can be translated or
	# reworded without quietly breaking which button lights up.
	var restate: Callable = func(chosen: int) -> void:
		for k in btns.size():
			if not is_instance_valid(btns[k]):
				continue
			var e: Array = entries[k]
			btns[k].set_pressed_no_signal(int(e[0]) == chosen)

	for i in entries.size():
		var row_i: Array = entries[i]
		var value: int = int(row_i[0])
		var b: Button = UiKit.make_text_button(
			UiKit.label_for(String(row_i[1]), String(row_i[2])), wide)
		b.toggle_mode = true
		b.set_pressed_no_signal(value == current)
		b.pressed.connect(func() -> void:
			restate.call(value)
			on_pick.call(value))
		btns.append(b)
		box.add_child(b)
	return btns

# ------------------------------------------------------------------ brush

## The widest panel in the app, and the tallest, because it holds the most.
##
## Half the brushes used to sit below the fold with nothing to say they were
## there — a grid that is cut off does not look cut off, it looks like that is
## all there is. It is given the room to show its rows instead.
static func brush(_view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell(560.0)
	var v: VBoxContainer = _column(shell, 660.0)
	_title(v, "Brush", "الفرشاة")

	var preview: BrushPreview = BrushPreview.new()
	v.add_child(preview)

	# Two rows rather than forty buttons. The family says what kind of mark
	# this is; the shape says which of its five. Forty in one grid would be
	# a wall to read every time, and the choice a user actually makes is
	# nearly always "same brush, different nib".
	var families: Array = App.library.families()
	var family_grid: GridContainer = GridContainer.new()
	family_grid.columns = 4
	family_grid.add_theme_constant_override("h_separation", int(UiKit.s(5.0)))
	family_grid.add_theme_constant_override("v_separation", int(UiKit.s(5.0)))
	v.add_child(family_grid)

	var shape_row: HBoxContainer = HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	v.add_child(shape_row)

	var family_btns: Array[Button] = []
	var shape_btns: Array[Button] = []

	var hint: Label = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.visible = false

	# The size and opacity dials live at the bottom of the panel, built after
	# everything above them — but choosing a brush has to move them, because
	# every preset carries its own defaults and App applies them the moment
	# the brush changes. Before, it did so silently: the dial went on showing
	# the old brush's number while the canvas painted with the new one's, and
	# the first touch of the slider snapped the size somewhere unasked for.
	#
	# An Array declared here and filled below is what lets the two meet: it
	# is held by reference, so the lambda sees what is appended after it.
	var dials: Array[TouchSlider] = []

	var is_light: Callable = func(family: int) -> bool:
		if family < 0 or family >= families.size():
			return false
		return String((families[family] as Dictionary)["id"]) == "light"

	# The shape names change with the family, because Light's five are five
	# different lights rather than five sizes of one — calling a lens flare
	# "Broad" would be telling the user the wrong thing about it.
	#
	# There was never a Light-only table on the library; it keeps one table,
	# `SPECIAL_NAMES`, keyed by family id, and Light is one of five families in
	# it. Reading that table instead of a name invented for Light alone both
	# fixes the error and repairs four families that were silently wrong: Cloud,
	# Foliage, Skydust and Sketch each carry their own five words — Thunderhead,
	# Frond, Fireflies, Charcoal — and the buttons were showing every one of
	# them as "Plain / Fine / Broad / Rough / Soft", while the brush list two
	# panels away named them correctly. It is the same table `_build` uses to
	# name the presets, so the two can no longer disagree.
	var relabel: Callable = func(family: int) -> void:
		var id: String = ""
		if family >= 0 and family < families.size():
			id = String((families[family] as Dictionary)["id"])
		var words: Array = BrushLibrary.SPECIAL_NAMES.get(id,
			BrushLibrary.VARIANT_NAMES)
		for k in shape_btns.size():
			if not is_instance_valid(shape_btns[k]):
				continue
			if k >= words.size():
				continue
			var names: Array = words[k]
			shape_btns[k].text = UiKit.label_for(
				String(names[0]), String(names[1]))

	# Light only behaves like light on a layer set to add. Said here, once,
	# where the choice was just made — rather than left to be discovered by
	# painting a glow that comes out as grey film.
	#
	# It is its own Callable now, and called on the way in as well as on every
	# pick. Opening the panel with Light already selected used to show nothing
	# at all: the note was written inside the pick handler, and opening a
	# panel is not picking.
	var say_light: Callable = func(family: int) -> void:
		if not is_instance_valid(hint):
			return
		hint.text = UiKit.label_for(
			"Turn on Light layer in this layer's settings so the glow adds to what is beneath instead of covering it.",
			"فعّل «طبقة ضوء» في إعدادات هذه الطبقة ليضيف التوهج إلى ما تحته بدل أن يغطيه.") \
			if bool(is_light.call(family)) else ""
		hint.visible = hint.text != ""

	var pick: Callable = func(family: int, shape: int) -> void:
		var index: int = App.library.index_of(family, shape)
		App.set_brush(index)
		for k in family_btns.size():
			family_btns[k].set_pressed_no_signal(k == family)
		for k in shape_btns.size():
			shape_btns[k].set_pressed_no_signal(k == shape)
		preview.refresh(index)
		relabel.call(family)
		say_light.call(family)
		if dials.size() == 2:
			UiKit.slider_set(dials[0], App.brush_size)
			UiKit.slider_set(dials[1], App.brush_opacity)

	for i in families.size():
		var row: Dictionary = families[i]
		var b: Button = UiKit.make_text_button(
			UiKit.label_for(String(row["en"]), String(row["ar"])), true)
		b.toggle_mode = true
		family_btns.append(b)
		family_grid.add_child(b)

	for v_index in BrushLibrary.PER_FAMILY:
		var names: Array = BrushLibrary.VARIANT_NAMES[v_index]
		var b2: Button = UiKit.make_text_button(
			UiKit.label_for(String(names[0]), String(names[1])))
		b2.toggle_mode = true
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shape_btns.append(b2)
		shape_row.add_child(b2)

	# `at_family` / `at_shape` rather than `family` / `shape`: the two words
	# are already the parameter names of `pick` above, and reusing them in the
	# same function body is what the compiler was warning about — an identifier
	# that means one thing at the top of a block and another at the bottom.
	for i in family_btns.size():
		var at_family: int = i
		family_btns[i].pressed.connect(func() -> void:
			pick.call(at_family, App.library.variant_of(App.brush_index)))
	for i in shape_btns.size():
		var at_shape: int = i
		shape_btns[i].pressed.connect(func() -> void:
			pick.call(App.library.family_index_of(App.brush_index), at_shape))

	# Clamped on the way in. The saved brush index outlives the list it points
	# into — the library has grown from eight presets to forty across builds —
	# and an index from an older run would otherwise index past the end here
	# and take the panel down with it before it ever appeared.
	var start_family: int = 0
	var start_shape: int = 0
	if not family_btns.is_empty():
		start_family = clampi(App.library.family_index_of(App.brush_index),
			0, family_btns.size() - 1)
		family_btns[start_family].set_pressed_no_signal(true)
	if not shape_btns.is_empty():
		start_shape = clampi(App.library.variant_of(App.brush_index),
			0, shape_btns.size() - 1)
		shape_btns[start_shape].set_pressed_no_signal(true)
	relabel.call(start_family)
	say_light.call(start_family)
	v.add_child(hint)

	_rule(v)

	dials.append(UiKit.slider_row(v, UiKit.label_for("Size", "الحجم"),
		1.0, 400.0, App.brush_size, 1.0, " px",
		func(x: float) -> void:
			App.brush_size = x
			App.settings_changed.emit()
			preview.queue_redraw()))

	dials.append(UiKit.slider_row(v, UiKit.label_for("Opacity", "الشفافية"),
		0.02, 1.0, App.brush_opacity, 0.01, "",
		func(x: float) -> void:
			App.brush_opacity = x
			App.settings_changed.emit()
			preview.queue_redraw()))

	dials.append(UiKit.slider_row(v,
		UiKit.label_for("Steady hand", "ثبات اليد"),
		0.0, 1.0, App.stabilizer, 0.05, "",
		func(x: float) -> void:
			App.stabilizer = x
			App.settings_changed.emit()))
	_note_line(v, UiKit.label_for(
		"Drags the nib along behind your finger on a short leash, so a fast sweep cuts the corner off every wobble instead of following it. At nought the line goes exactly where you do. Turned up, it ends a little behind your finger — that lag is the price, and it is why this is a dial rather than something always on.",
		"يجرّ السنّ خلف إصبعك بمقود قصير، فالمسحة السريعة تقطع زاوية كلّ تموّج بدل أن تتبعه. وعند الصفر يذهب الخطّ حيث تذهب تماماً. وكلّما رفعتَه تأخّر عن إصبعك قليلاً — وهذا التأخّر هو الثمن، ولهذا هو مؤشّر لا شيءٌ مفروض دائماً."))

	preview.refresh(App.brush_index)
	return shell

# ----------------------------------------------------------------- eraser

static func eraser(_view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)
	_title(v, "Eraser", "الممحاة")

	_choice(v, [
		[App.EraserShape.SOFT, "Soft", "ناعمة"],
		[App.EraserShape.HARD, "Hard", "حادة"],
		[App.EraserShape.SQUARE, "Square", "مربعة"],
	], App.eraser_shape, 1, false, func(value: int) -> void:
		App.eraser_shape = value
		App.settings_changed.emit())

	UiKit.slider_row(v, UiKit.label_for("Size", "الحجم"),
		2.0, 500.0, App.eraser_size, 1.0, " px",
		func(x: float) -> void:
			App.eraser_size = x
			# The eraser's own settings never told anyone they had changed,
			# so anything drawing a live preview of the nib kept the old
			# figure until some other control happened to speak up.
			App.settings_changed.emit())

	UiKit.slider_row(v, UiKit.label_for("Strength", "القوة"),
		0.05, 1.0, App.eraser_opacity, 0.01, "",
		func(x: float) -> void:
			App.eraser_opacity = x
			App.settings_changed.emit())

	return shell

# ----------------------------------------------------------------- shapes

static func shapes(view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)
	_title(v, "Shapes", "الأشكال")
	_note_line(v, UiKit.label_for(
		"Keep your finger down while dragging: shapes are corrected live. Near-square rectangles become exact squares, near-circles become true circles, diamonds stay symmetric, and lines snap straight.",
		"أبقِ إصبعك ضاغطاً أثناء السحب: تُصحَّح الأشكال مباشرة. المستطيل القريب من المربع يصبح مربعاً حقيقياً، والدائرة القريبة تصبح دائرة حقيقية، والمعيّن يبقى متماثلاً، والخط يستقيم."))

	_rule(v)

	var commit: Button = UiKit.make_text_button(
		UiKit.label_for("Draw the curve", "ارسم المنحنى"), true)
	var clear_pts: Button = UiKit.make_text_button(
		UiKit.label_for("Clear points", "امسح النقاط"), true)
	var fresh: Button = UiKit.make_text_button(
		UiKit.label_for("Start a new chain", "ابدأ سلسلة جديدة"), true)

	# Both belong to the curve and to nothing else. They used to sit there
	# lit in every mode, doing nothing at all when pressed — a button that
	# answers a press with silence reads as a broken app, not as a button
	# that did not apply. Now they grey out until the curve is the shape.
	var gate: Callable = func(mode: int) -> void:
		var on: bool = mode == App.Shape.POLYLINE
		commit.disabled = not on
		clear_pts.disabled = not on
		# Letting go of a chain without having to change tools to do it.
		fresh.disabled = mode != App.Shape.CHAIN

	_choice(v, [
		[App.Shape.FREE, "Free", "حر"],
		[App.Shape.LINE, "Line", "خط"],
		[App.Shape.RECT, "Rect", "مستطيل"],
		[App.Shape.SQUARE, "Square", "مربع"],
		[App.Shape.ELLIPSE, "Circle", "دائرة"],
		[App.Shape.DIAMOND, "Diamond", "معيّن"],
		[App.Shape.POLYLINE, "Curve", "منحنى"],
		[App.Shape.CHAIN, "Tangled", "متشابك"],
	], App.shape_mode, 2, true, func(value: int) -> void:
		App.shape_mode = value
		if is_instance_valid(view):
			view.break_chain()
		gate.call(value))

	commit.pressed.connect(func() -> void:
		if App.shape_mode == App.Shape.POLYLINE and is_instance_valid(view):
			view.commit_shape())
	v.add_child(commit)

	clear_pts.pressed.connect(func() -> void:
		if not is_instance_valid(view):
			return
		view.poly_points.clear()
		if view.overlay != null and is_instance_valid(view.overlay):
			view.overlay.queue_redraw())
	v.add_child(clear_pts)

	fresh.pressed.connect(func() -> void:
		if is_instance_valid(view):
			view.break_chain())
	v.add_child(fresh)
	_note_line(v, UiKit.label_for(
		"Tangled lines arrive already joined: only the first is free, and every one after it starts where the last ended.",
		"الخطوط المتشابكة تأتي متلاصقة: الأول وحده حر، وكل خط بعده يبدأ حيث انتهى سابقه."))

	gate.call(App.shape_mode)
	return shell

# ---------------------------------------------------------- lateral symmetry

static func lateral_symmetry(view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell(330.0)
	var v: VBoxContainer = _column(shell)
	_title(v, "Lateral symmetry", "التناظر الجانبي")

	var toggle: Button = UiKit.make_text_button(
		UiKit.label_for("Enable symmetry", "تفعيل التناظر"), true)
	toggle.toggle_mode = true
	toggle.set_pressed_no_signal(view.symmetry_enabled)
	toggle.pressed.connect(func() -> void:
		view.set_lateral_symmetry(toggle.button_pressed))
	v.add_child(toggle)

	_note_line(v, UiKit.label_for(
		"The line is the symmetry axis. Move its centre and rotate its handle directly on the canvas.",
		"الخط هو محور التناظر. حرّك مركزه وأدر مقبضه مباشرة على اللوحة."))

	_note_line(v, UiKit.label_for("Symmetry type", "نوع التناظر"))

	# The counts go through the shared group like every other choice, so the
	# lit button is decided by the number it stands for rather than by its
	# own printed label — which is what the old copy of this code compared.
	_choice(v, [
		[2, "2", "٢"], [3, "3", "٣"], [4, "4", "٤"],
		[5, "5", "٥"], [6, "6", "٦"], [8, "8", "٨"],
	], view.symmetry_count, 3, false, func(value: int) -> void:
		view.set_symmetry_count(value))

	UiKit.slider_row(v, UiKit.label_for("Axis angle", "زاوية المحور"),
		-180.0, 180.0, rad_to_deg(view.symmetry_angle), 1.0, "°",
		func(x: float) -> void: view.set_symmetry_angle(deg_to_rad(x)))

	_note_line(v, UiKit.label_for(
		"During drawing, each stroke is reproduced mathematically around the symmetry centre.",
		"أثناء الرسم، تُعاد كل ضربة حسابياً حول مركز التناظر بدقة."))
	return shell

# ------------------------------------------------------------------ color

## `for_fill` swaps the whole panel over to the bucket's colour. The two
## share nothing but the recent swatches, so choosing a flat never disturbs
## the outline colour sitting in the brush.
##
## The panel itself lives in `ColorPanel`; only the ten stay here, because the
## brush panel and the fill panel have to read the same list.
static func color(view: CanvasView, for_fill: bool = false) -> PanelContainer:
	return ColorPanel.build(view, for_fill)

# ------------------------------------------------------------------- blend

## The colour merge tool's panel.
##
## Its shapes are the brush library's, unchanged, because that is the whole
## idea of the tool: the same stamp read as *how much mixing happens where*
## rather than as how much ink lands. The middle of a soft round mixes fully
## and its edge barely at all; the chalk mixes through its own tooth and
## leaves the pits alone; the cell network mixes along its strands. So the
## shape row here is not a decoration on a blend tool — it is the blend tool's
## character, and it is the reason the button sits under the brush.
static func blend(_view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell(300.0)
	var v: VBoxContainer = _column(shell)
	_title(v, "Blend colours", "دمج الألوان")

	_note_line(v, UiKit.label_for(
		"Mixing happens in a perceptual colour space, so red into green gives a real olive rather than mud, and blue into white stays blue instead of going through purple.",
		"المزج يجري في فضاء لوني إدراكي، فالأحمر مع الأخضر يعطي زيتونياً حقيقياً لا طيناً، والأزرق مع الأبيض يبقى أزرق ولا يمرّ ببنفسجي."))

	# --- what it does with the two colours ---
	var ways: Array = [
			[0, UiKit.label_for("Mix", "مزج"),
				UiKit.label_for("Everything moves towards one colour taken from the line between the two.",
					"كل شيء يتحرك نحو لون واحد مأخوذ من الخط بين اللونين.")],
			[1, UiKit.label_for("Gradient", "تدرّج"),
				UiKit.label_for("One drag lays the whole ramp, from the first colour to the second.",
					"سحبة واحدة تضع التدرّج كاملاً من اللون الأول إلى الثاني.")],
			[3, UiKit.label_for("Average", "متوسط"),
				UiKit.label_for("Softens a border without moving either side past the other.",
					"يُنعّم الحد دون أن يجرّ أحد الجانبين فوق الآخر.")],
		[4, UiKit.label_for("Snap to two", "اقتناص اللونين"),
			UiKit.label_for("Tidies a muddled boundary towards the two colours rather than blurring it further.",
				"يرتّب حدّاً مختلطاً نحو اللونين بدل أن يزيده ضبابية.")],
	]

	var chips: Array[Button] = []
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(UiKit.s(5.0)))
	flow.add_theme_constant_override("v_separation", int(UiKit.s(5.0)))
	v.add_child(flow)

	var why: Label = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var restate: Callable = func() -> void:
		for i in chips.size():
			var chip: Button = chips[i]
			if not is_instance_valid(chip):
				continue
			chip.button_pressed = int(ways[i][0]) == App.blend_mode
			if chip.button_pressed:
				why.text = String(ways[i][2])

	for way in ways:
		var chip: Button = UiKit.make_text_button(String(way[1]), true)
		chip.custom_minimum_size = Vector2(0.0, UiKit.s(UiKit.TOUCH_FLOOR))
		chip.tooltip_text = String(way[2])
		var code: int = int(way[0])
		chip.pressed.connect(func() -> void:
			App.blend_mode = code
			App.settings_changed.emit()
			restate.call())
		chips.append(chip)
		flow.add_child(chip)
	v.add_child(why)

	# --- how hard, how big, how much it carries ---
	UiKit.slider_row(v, UiKit.label_for("Blend strength", "شدة الدمج"),
		0.02, 1.0, App.blend_strength, 0.01, "",
		func(x: float) -> void: App.blend_strength = x)
	UiKit.slider_row(v, UiKit.label_for("Blend size", "حجم الدمج"),
		4.0, 400.0, App.blend_size, 1.0, " px",
		func(x: float) -> void: App.blend_size = x)
	UiKit.slider_row(v, UiKit.label_for("Pick up", "الالتقاط"),
		0.0, 1.0, App.blend_pickup, 0.01, "",
		func(x: float) -> void: App.blend_pickup = x)

	_note_line(v, UiKit.label_for(
		"Pick up only matters where colour is carried. At one the brush forgets what it held instantly and smudges nothing; at nought it carries the first colour the whole way, which is painting.",
		"الالتقاط يهمّ فقط حيث يُحمَل اللون. عند واحد تنسى الفرشاة ما حملته فوراً فلا تُلطّخ شيئاً، وعند صفر تحمل اللون الأول طوال الطريق وهذا رسمٌ لا دمج."))

	# --- and whether it may touch transparency ---
	var alpha: Button = UiKit.make_text_button(
		UiKit.label_for("Let it change transparency", "اسمح بتغيير الشفافية"),
		true)
	alpha.button_pressed = App.blend_touch_alpha
	alpha.tooltip_text = UiKit.label_for(
		"Off by default. A blend tool that quietly erases is a blend tool nobody trusts.",
		"مغلق افتراضياً. أداة دمج تمحو بصمت هي أداة لا يثق بها أحد.")
	alpha.pressed.connect(func() -> void:
		App.blend_touch_alpha = alpha.button_pressed)
	v.add_child(alpha)

	restate.call()
	return shell

# -------------------------------------------------------------------- fill

## The bucket's own panel: its colour, and what shape it puts down. Kept
## apart from the brush panel because the two never share a colour.
static func fill(_view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)
	_title(v, "Fill", "الملء")

	_note_line(v, UiKit.label_for(
		"How far a colour may drift from the pixel you tapped and still count as the same area. Low stops hard at a clean line; high carries across a textured wash that a tight setting would dam up against its own soft edges.",
		"كم يمكن للّون أن يبتعد عن البكسل الذي ضغطته ويبقى محسوباً من المساحة نفسها. القليل يقف عند الخط النظيف، والكثير يعبر التدرجات التي يحتجزها الإعداد الضيق عند حوافها الناعمة."))
	var tol: TouchSlider = UiKit.slider_row(v, UiKit.label_for("Tolerance", "التسامح"),
		2.0, 200.0, float(App.fill_tolerance), 1.0, "",
		func(x: float) -> void: App.fill_tolerance = int(x))

	var creep: TouchSlider = UiKit.slider_row(v,
		UiKit.label_for("Tuck under the line", "الاندساس تحت الخط"),
		0.0, 6.0, float(App.fill_creep), 1.0, " px",
		func(x: float) -> void: App.fill_creep = int(x))
	_note_line(v, UiKit.label_for(
		"An inked line fades out over two or three pixels. A fill that stops the moment it touches one leaves a pale rim all the way round it — this pushes underneath instead.",
		"الخط المحبَّر يتلاشى عبر بكسلين أو ثلاثة. والملء الذي يقف فور ملامسته يترك حافة شاحبة حوله — وهذا يندسّ تحته بدلاً من ذلك."))

	_rule(v)

	# Every shape but the first is dragged out, and the two dials above only
	# have any say over the first. They are dimmed rather than hidden, so the
	# panel does not jump about as the choice changes and the reason they are
	# unavailable stays on screen.
	var gate: Callable = func(mode: int) -> void:
		# The whole row dims, label and number with it — dimming the track
		# alone would leave a bright figure over a grey slider and read as a
		# rendering fault rather than as "this does not apply here".
		var dim: Color = Color(1.0, 1.0, 1.0,
			1.0 if mode == App.FillShape.FLOOD else 0.4)
		var a: Control = tol.get_parent() as Control
		var b: Control = creep.get_parent() as Control
		if a != null:
			a.modulate = dim
		if b != null:
			b.modulate = dim

	_choice(v, [
		[App.FillShape.FLOOD, "Between lines", "بين الخطوط"],
		[App.FillShape.RECT, "Rect", "مربع"],
		[App.FillShape.ELLIPSE, "Circle", "دائرة"],
		[App.FillShape.TRIANGLE, "Triangle", "مثلث"],
		[App.FillShape.DIAMOND, "Diamond", "معيّن"],
		[App.FillShape.STAR, "Star", "نجمة"],
	], App.fill_shape, 2, true, func(value: int) -> void:
		App.fill_shape = value
		gate.call(value))
	gate.call(App.fill_shape)

	_note_line(v, UiKit.label_for(
		"A shape is dragged out and filled solid. Between lines needs only a tap.",
		"الشكل يُسحب فيُملأ صلباً. والملء بين الخطوط يحتاج ضغطة واحدة."))

	_rule(v)
	var swatch: ColorRect = ColorRect.new()
	swatch.custom_minimum_size = Vector2(0.0, UiKit.s(30.0))
	swatch.color = App.fill_ink
	v.add_child(swatch)
	var open_colour: Button = UiKit.make_text_button(
		UiKit.label_for("Fill colour", "لون الملء"), true)
	open_colour.pressed.connect(func() -> void: App.request_fill_colour())
	v.add_child(open_colour)

	var restate: Callable = func(c: Color) -> void:
		if is_instance_valid(swatch):
			swatch.color = c
	App.fill_color_changed.connect(restate)
	shell.tree_exiting.connect(func() -> void:
		if App.fill_color_changed.is_connected(restate):
			App.fill_color_changed.disconnect(restate))
	return shell

# -------------------------------------------------------------- selection

static func selection(view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell()
	var v: VBoxContainer = _column(shell)
	_title(v, "Select", "التحديد")
	_note_line(v, UiKit.label_for("Draw around a part, then drag, turn or resize it.",
		"ارسم حول جزء، ثم حرّكه أو أدره أو غيّر حجمه."))

	_choice(v, [
		[App.SelectShape.RECT, "Box", "مربع"],
		[App.SelectShape.ELLIPSE, "Circle", "دائرة"],
		[App.SelectShape.LASSO, "Free", "حر"],
		[App.SelectShape.POLY, "Points", "نقاط"],
	], App.select_shape, 2, true, func(value: int) -> void:
		App.select_shape = value
		if is_instance_valid(view):
			view.clear_marks())

	_rule(v)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	v.add_child(row)

	var copy_b: Button = UiKit.make_text_button(UiKit.label_for("Copy", "نسخ"))
	copy_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_b.pressed.connect(func() -> void:
		if is_instance_valid(view):
			view.copy_selection())
	row.add_child(copy_b)

	var paste_b: Button = UiKit.make_text_button(UiKit.label_for("Paste", "لصق"))
	paste_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Nothing has been copied yet on a fresh run, and a Paste that does
	# nothing is indistinguishable from a Paste that is broken.
	paste_b.disabled = App.clipboard == null
	paste_b.pressed.connect(func() -> void:
		if is_instance_valid(view):
			view.paste_clipboard())
	row.add_child(paste_b)

	# Not `row`: a second local of that name anywhere in this function is
	# refused by the parser, loop variables included. See the note further
	# down, where the same rule cost this whole class thirteen call sites.
	var clip_row: HBoxContainer = HBoxContainer.new()
	clip_row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	v.add_child(clip_row)

	var cut_b: Button = UiKit.make_text_button(UiKit.label_for("Cut", "قص"))
	cut_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cut_b.pressed.connect(func() -> void:
		if is_instance_valid(view):
			view.cut_selection())
	clip_row.add_child(cut_b)

	# Its own layer, which is what a piece brought in from somewhere else
	# nearly always wants. It takes the name of the layer it was copied from,
	# so the stack still reads as a list of things rather than of numbers.
	var onto_b: Button = UiKit.make_text_button(
		UiKit.label_for("Paste as new layer", "لصق كطبقة جديدة"))
	onto_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	onto_b.disabled = App.clipboard == null
	onto_b.pressed.connect(func() -> void:
		if is_instance_valid(view):
			view.paste_as_new_layer())
	clip_row.add_child(onto_b)

	var after_clip: Callable = func() -> void:
		if is_instance_valid(paste_b):
			paste_b.disabled = App.clipboard == null
		if is_instance_valid(onto_b):
			onto_b.disabled = App.clipboard == null
	copy_b.pressed.connect(after_clip)
	cut_b.pressed.connect(after_clip)

	_note_line(v, UiKit.label_for(
		"With nothing marked, Copy and Cut take the whole layer.",
		"بلا تحديد، النسخ والقص يأخذان الطبقة كاملة."))
	_note_line(v, UiKit.label_for(
		"Cut, paste and everything below are one step of undo each.",
		"القص واللصق وكل ما تحته: كل منها خطوة تراجع واحدة."))

	_rule(v)

	# A branch, not more of the same list.
	#
	# Selecting and distorting are different acts and the panel says so: move,
	# turn and resize keep a shape *the same shape*, and everything below this
	# line changes what the shape is. Mixed into one column they read as ten
	# equal buttons and the difference has to be learnt; separated, it is
	# visible before anything is pressed.
	_note_line(v, UiKit.label_for("↳  Reshape what is marked",
		"↳  إعادة تشكيل ما هو محدد"))

	var amount: TouchSlider = null
	var chosen: Array[int] = [Distort.Kind.LEAN]
	# Not `row`: a `row` already exists a few lines above, holding the copy
	# and paste strip. GDScript forbids a second local of that name anywhere
	# in the same function — loop variables included — and the parser stops
	# at it, which is why the whole class reported as unresolvable from
	# thirteen different call sites. The name says what it holds instead.
	var rows: Array = []
	for kind_row in Distort.KINDS:
		rows.append([int(kind_row[0]), String(kind_row[1]), String(kind_row[2])])
	var note: Label = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_choice(v, rows, chosen[0], 3, false, func(value: int) -> void:
		chosen[0] = value
		note.text = Distort.note_of(value)
		if is_instance_valid(view):
			view.set_distort(value, amount.value if amount != null else 0.0))
	v.add_child(note)
	note.text = Distort.note_of(chosen[0])

	amount = UiKit.slider_row(v, UiKit.label_for("Amount", "المقدار"),
		-1.0, 1.0, 0.0, 0.01, "",
		func(x: float) -> void:
			if is_instance_valid(view):
				view.set_distort(chosen[0], x))
	_note_line(v, UiKit.label_for(
		"Nought is unchanged, and either side of it are opposites — so anything done here can be undone by hand.",
		"الصفر بلا تغيير، وطرفاه متعاكسان — فكل ما يُصنع هنا يمكن ردّه باليد."))

	_rule(v)
	_note_line(v, UiKit.label_for("↳  Trim", "↳  قص الطرف"))
	_note_line(v, UiKit.label_for(
		"Choose a shape, place it over the marked part, and cut. What you cut is rubbed out; the rest stays.",
		"اختر شكلاً، ضعه على الجزء المحدد، ثم اقطع. ما تقطعه يُمحى، والباقي يبقى."))

	var cut_rows: Array = []
	for cut_row in Distort.CUTS:
		cut_rows.append([int(cut_row[0]), String(cut_row[1]), String(cut_row[2])])
	var cutter: Array[int] = [Distort.Cut.RECT]
	_choice(v, cut_rows, cutter[0], 2, true, func(value: int) -> void:
		cutter[0] = value)

	var away: Button = UiKit.make_text_button(
		UiKit.label_for("Cut the shape away", "اقطع الشكل"), true)
	away.pressed.connect(func() -> void:
		if is_instance_valid(view):
			view.trim_selection(cutter[0], false))
	v.add_child(away)

	var only: Button = UiKit.make_text_button(
		UiKit.label_for("Keep only the shape", "أبقِ الشكل وحده"), true)
	only.pressed.connect(func() -> void:
		if is_instance_valid(view):
			view.trim_selection(cutter[0], true))
	v.add_child(only)

	return shell

# ------------------------------------------------------------ puppet warp

## The controls for bending a layer.
##
## Deliberately short. The work happens on the drawing itself — put pins
## down, pull one — so this is only the handful of things a finger on the
## canvas cannot say: how fine the grid is, how tightly each pin holds, and
## which of the two ways out is wanted.
static func puppet_warp(view: CanvasView) -> PanelContainer:
	var shell: PanelContainer = _shell(360.0)
	var v: VBoxContainer = _column(shell)
	_title(v, "Puppet warp", "التحريك بالدبابيس")

	_note_line(v, UiKit.label_for(
		"This warp owns one layer at a time. Any rig standing in for that layer is put away while it runs, so the drawing is never on screen twice.",
		"هذا التشويه يملك طبقة واحدة في كل مرة. وأي هيكل ينوب عن تلك الطبقة يُنحّى أثناء عمله، فلا يظهر الرسم مرتين أبداً."))
	_note_line(v, UiKit.label_for(
		"Tap the drawing to put a pin down. Drag a pin to bend it. Pins you leave alone hold the drawing still, so pin what should stay before pulling what should move. Tap a pin twice to take it away.",
		"اضغط على الرسم لتضع دبوساً. اسحب دبوساً لتثنيه. الدبابيس التي تتركها تُمسك الرسم مكانه، فثبّت ما يجب أن يبقى قبل أن تسحب ما يجب أن يتحرك. اضغط على الدبوس مرتين لإزالته."))

	var count: Label = UiKit.make_label("", 12.0, UiKit.TEXT)
	v.add_child(count)

	# --- which pin the controls below are talking about ---
	var who: Label = UiKit.make_label("", 12.0, UiKit.TEXT)
	v.add_child(who)

	var lift: Button = UiKit.make_text_button(
		UiKit.label_for("Bring forward", "إلى الأمام"), true)
	var sink: Button = UiKit.make_text_button(
		UiKit.label_for("Send back", "إلى الخلف"), true)
	var hold: Button = UiKit.make_text_button(
		UiKit.label_for("Hold this pin still", "ثبّت هذا الدبوس"), true)
	var back: Button = UiKit.make_text_button(
		UiKit.label_for("Undo the last pull", "تراجع عن آخر سحبة"), true)

	var tell: Callable = func() -> void:
		if not is_instance_valid(who) or not is_instance_valid(view):
			return
		var at: int = view.puppet.selected
		# The three depth controls only mean anything with a pin chosen, and
		# the warp itself quietly ignores an index of -1 — so pressing them
		# with nothing selected did nothing and said nothing about why.
		var some: bool = at >= 0 and at < view.puppet.pins.size()
		lift.disabled = not some
		sink.disabled = not some
		hold.disabled = not some
		back.disabled = not view.puppet.has_step_back()
		if not some:
			who.text = UiKit.label_for("No pin chosen", "لا دبوس محدد")
			hold.text = UiKit.label_for("Hold this pin still", "ثبّت هذا الدبوس")
			return
		who.text = "%s %d  ·  %s %d" % [
			UiKit.label_for("Pin", "دبوس"), at + 1,
			UiKit.label_for("Depth", "العمق"), view.puppet.depth_of(at)]
		hold.text = UiKit.label_for("Let this pin go", "أطلق هذا الدبوس") \
			if view.puppet.is_anchored(at) \
			else UiKit.label_for("Hold this pin still", "ثبّت هذا الدبوس")

	lift.pressed.connect(func() -> void:
		var at: int = view.puppet.selected
		view.puppet.set_depth(at, view.puppet.depth_of(at) + 1)
		tell.call())
	sink.pressed.connect(func() -> void:
		var at: int = view.puppet.selected
		view.puppet.set_depth(at, view.puppet.depth_of(at) - 1)
		tell.call())
	hold.pressed.connect(func() -> void:
		view.puppet.toggle_anchor(view.puppet.selected)
		tell.call())

	var depth_row: HBoxContainer = HBoxContainer.new()
	depth_row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	lift.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sink.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_row.add_child(sink)
	depth_row.add_child(lift)
	v.add_child(depth_row)
	v.add_child(hold)
	_note_line(v, UiKit.label_for(
		"Where two parts of one drawing cross — an arm folded over a body — depth decides which is in front. Touch a pin to choose it.",
		"حين يتقاطع جزءان من رسم واحد — ذراع مطوية فوق جسد — العمق هو ما يقرر أيهما في الأمام. المس دبوساً لتختاره."))

	var say: Callable = func() -> void:
		if not is_instance_valid(count):
			return
		count.text = "%s: %d" % [UiKit.label_for("Pins", "الدبابيس"),
			view.puppet.pins.size()]
		tell.call()
	say.call()
	view.puppet.changed.connect(say)
	# The warp outlives this panel — it is still on the canvas after the
	# panel is closed — so the readout has to let go of it on the way out.
	# A connection left behind would be one more dead label told about
	# every pin, for the rest of the session.
	count.tree_exiting.connect(func() -> void:
		if view.puppet.changed.is_connected(say):
			view.puppet.changed.disconnect(say))

	_rule(v)

	# Higher holds each pin's own neighbourhood tighter; lower lets a pull
	# carry further across the drawing.
	# The low end reaches much further down than it did. Measuring distance
	# through the drawing instead of across it makes every pin more local by
	# nature, so the control that loosens them has to reach further to give
	# back a whole-shape bend when that is what is wanted.
	UiKit.slider_row(v, UiKit.label_for("Pin grip", "قبضة الدبوس"),
		0.35, 2.4, view.puppet.stiffness, 0.05, "",
		func(x: float) -> void:
			view.puppet.stiffness = x
			view.puppet.restyle())

	UiKit.slider_row(v, UiKit.label_for("Pin softness", "نعومة الدبوس"),
		1.0, 40.0, view.puppet.softness, 0.5, "",
		func(x: float) -> void:
			view.puppet.softness = x
			view.puppet.restyle())

	UiKit.slider_row(v, UiKit.label_for("Smoothing", "التنعيم"),
		0.0, 1.0, view.puppet.smoothing, 0.05, "",
		func(x: float) -> void:
			view.puppet.smoothing = x
			view.puppet.solve())

	# What this weighs is the as-rigid-as-possible solve — how hard the
	# drawing insists on keeping its own shape where no pin is holding it.
	# It used to weigh an area-restoring pass, which gave a squashed triangle
	# its area back without any opinion about what shape to give it back as.
	UiKit.slider_row(v, UiKit.label_for("Hold shape", "حفظ الشكل"),
		0.0, 1.0, view.puppet.area_keep, 0.05, "",
		func(x: float) -> void:
			view.puppet.area_keep = x
			view.puppet.solve())

	# Opens where the mesh actually is. It used to open at a flat 34 whatever
	# the drawing had been built with, so the first touch of the dial rebuilt
	# the mesh at a density nobody had asked for.
	UiKit.slider_row(v, UiKit.label_for("Grid", "دقة الشبكة"),
		float(PuppetWarp.MIN_CELLS), float(PuppetWarp.MAX_CELLS),
		float(view.puppet.cells), 1.0, "",
		func(x: float) -> void: view.puppet.set_density(int(x)))

	var wire: Button = UiKit.make_text_button(
		UiKit.label_for("Hide the grid", "أخفِ الشبكة"), true)
	wire.pressed.connect(func() -> void:
		view.puppet.show_mesh = not view.puppet.show_mesh
		wire.text = UiKit.label_for("Hide the grid", "أخفِ الشبكة") \
			if view.puppet.show_mesh \
			else UiKit.label_for("Show the grid", "أظهر الشبكة")
		view.puppet.queue_redraw())
	v.add_child(wire)

	back.pressed.connect(func() -> void:
		view.puppet.step_back()
		tell.call())
	v.add_child(back)

	var rest: Button = UiKit.make_text_button(
		UiKit.label_for("Back to the pose it started in", "أعده إلى وضعه الأصلي"), true)
	rest.pressed.connect(func() -> void:
		view.puppet.reset_pose()
		tell.call())
	v.add_child(rest)

	var strip: Button = UiKit.make_text_button(
		UiKit.label_for("Take every pin away", "أزل كل الدبابيس"), true)
	strip.pressed.connect(func() -> void:
		view.puppet.clear_pins()
		tell.call())
	v.add_child(strip)

	tell.call()
	_rule(v)
	return shell

# ---------------------------------------------------------------- compass

## A row in the compass: the mark, then the name, then what it is for.
##
## The mark carries the meaning after the first week and the name carries it
## on the first day — so both are here, and neither is decoration. An icon on
## its own has to be learnt before it helps; a name on its own has to be read
## every single time.
static func _place_row(v: VBoxContainer, icon_name: String, label: String,
		note: String, action: Callable) -> Button:
	var b: Button = UiKit.make_text_button(label, true)
	b.custom_minimum_size = Vector2(UiKit.s(240.0), UiKit.s(50.0))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var path: String = "res://assets/icons/%s.png" % icon_name
	if ResourceLoader.exists(path):
		b.icon = load(path)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", int(UiKit.s(24.0)))
	b.add_theme_constant_override("h_separation", int(UiKit.s(12.0)))
	b.add_theme_color_override("icon_normal_color", UiKit.TEXT)
	b.add_theme_color_override("icon_pressed_color", Color("#1b1c22"))
	b.pressed.connect(action)
	v.add_child(b)
	if note != "":
		_note_line(v, note)
	return b

## The compass: places, in the order they are likely to be wanted.
##
## Every row here is offered in every kind of project. Bending a drawing is as
## useful on a comic panel as it is in a scene, and so is writing on it.
## Whether the AI row is offered.
##
## One word, in one place, and everything behind it stays built. See the note
## where the row is added.
const SHOW_AI: bool = false

static func compass(on_text: Callable, on_tangled: Callable, on_ai: Callable,
			on_symmetry: Callable, kind: int = -1,
			on_comic: Callable = Callable()) -> PanelContainer:
	var shell: PanelContainer = _shell(390.0)
	var v: VBoxContainer = _column(shell, 520.0)
	_title(v, "Compass", "البوصلة")


	_place_row(v, "tangled_lines",
		UiKit.label_for("Tangled lines", "خطوط متشابكة"),
		UiKit.label_for(
			"Straight lines that arrive already joined. Only the first is drawn freely — after that each one starts exactly where the last ended, so you place one point instead of two and the corners meet exactly.",
			"خطوط مستقيمة تأتي متلاصقة. الأول وحده يُرسم حراً — وبعده يبدأ كل خط تماماً حيث انتهى سابقه، فتضع نقطة واحدة بدل اثنتين وتلتقي الزوايا بالضبط."),
		on_tangled)

	_place_row(v, "text_tool",
		UiKit.label_for("Text", "نص"),
		UiKit.label_for(
			"Writes on the page. What you write becomes a text layer of its own and stays editable.",
			"يكتب على الصفحة. وما تكتبه يصير طبقة نص خاصة به ويبقى قابلاً للتعديل."),
			on_text)

	# --- the AI row, put away ---
	#
	# Hidden, not deleted, and the distinction is the whole instruction.
	# Every line of `ai_assistant.gd`, `ai_room.gd` and `ai_identity.gd` is
	# exactly where it was, still compiled, still tested, still reachable
	# from `AiBridge.open_ai_room`. What has gone is the way in from here —
	# one row.
	#
	# So this comes back by flipping `SHOW_AI` and nothing else. Deleting the
	# row would have meant deleting the callable it takes, then the function
	# behind that, and by the third step the feature would be gone rather
	# than put away, and putting it back would be work rather than a word.
	if SHOW_AI:
		_rule(v)
		_place_row(v, "ai_design",
			UiKit.label_for("AI-powered image design",
				"تصميم الصور بالذكاء الاصطناعي"),
			UiKit.label_for(
				"Describe a picture and it is drawn, or send the drawing on this layer along with the words and it is improved rather than replaced. A conversation, so the second attempt is an edit of the first.",
				"صف صورة فتُرسم، أو أرسل الرسم الذي على هذه الطبقة مع الكلمات فيُحسَّن بدل أن يُستبدل. محادثة، فتكون المحاولة الثانية تعديلاً للأولى."),
			on_ai)

	# --- the comics section ---
	#
	# Present only in a comic, and **absent** rather than greyed out in
	# anything else. A disabled control is a promise that something could be
	# made to work; there is nothing here an animation could be made to want,
	# and four rows to read past on the way to the curve room is a real cost
	# The comic section is only shown for comic projects. See `ComicPanelsUi`.
	var comic_rows: Array = ComicPanelsUi.rows(kind)
	if not comic_rows.is_empty():
		_rule(v)
		v.add_child(UiKit.make_label(
			UiKit.label_for("Comics", "قصص مصورة"), 14.0, UiKit.TEXT))
		for row in comic_rows:
			var one: Dictionary = row
			var key: String = String(one["key"])
			_place_row(v, String(one["icon"]), String(one["title"]),
				String(one["note"]),
				func() -> void:
					if on_comic.is_valid():
						on_comic.call(key))

	# --- symmetry, moved here ---
	#
	# It was a mark in the touch panel beside the selection tools, which is a
	# place for things the *hand* does. Symmetry is not that: it is a way of
	# building, like the curve room and the tangled lines it now sits with,
	# and the compass is where ways of building live.
	_rule(v)
	# The compass rows look up `assets/icons/<name>.png`, and the file this
	# one has always been called by is `lateral_symmetry`. Naming it "symmetry"
	# here would have found nothing and drawn a row with a blank where every
	# other row has a mark — which is precisely the "does not look like the
	# rest of the app" that was asked about.
	_place_row(v, "lateral_symmetry",
		UiKit.label_for("Symmetry", "التناظر"),
		UiKit.label_for(
			"Draw one side and the other is drawn with it, mirrored across an axis you place. The axis can be moved and turned at any time, and what is already on the layer is left alone.",
			"ارسم جانباً فيُرسم الآخر معه، منعكساً حول محور تضعه. ويمكن تحريك المحور وإدارته في أيّ وقت، وما على الطبقة أصلاً يُترك كما هو."),
		on_symmetry)
	return shell

# ------------------------------------------------------------------- text

## Writing on the page.
##
## Text is shaped by the engine's own text server rather than laid out letter
## by letter here, which is what makes it correct in every script the font
## covers: Arabic joins and runs right to left, Devanagari reorders, CJK sets
## without spaces. Doing that by hand is how text tools end up working in one
## language and falling apart in the next.
static func text_maker(state: Dictionary, on_change: Callable,
		on_place: Callable) -> PanelContainer:
	var shell: PanelContainer = _shell(400.0)
	var v: VBoxContainer = _column(shell)
	_title(v, "Text", "نص")

	var box: TextEdit = TextEdit.new()
	box.text = String(state.get("text", ""))
	box.custom_minimum_size = Vector2(0.0, UiKit.s(96.0))
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	if UiKit.font != null:
		box.add_theme_font_override("font", UiKit.font)
	box.add_theme_font_size_override("font_size", int(UiKit.s(16.0)))
	v.add_child(box)

	# Typing used to re-render the whole text layer on every keystroke. On a
	# phone that is a full re-shape and re-blit per letter, and a fast typist
	# outruns it — which is one of the places the app felt heavy. The redraw
	# now waits for a breath in the typing instead. Nothing is lost: the last
	# keystroke always gets its redraw, a tenth of a second later.
	var beat: Timer = Timer.new()
	beat.wait_time = 0.12
	beat.one_shot = true
	box.add_child(beat)
	beat.timeout.connect(func() -> void: on_change.call())
	box.text_changed.connect(func() -> void:
		state["text"] = box.text
		beat.start())

	UiKit.slider_row(v, UiKit.label_for("Size", "الحجم"),
		8.0, 320.0, float(state.get("size", 64.0)), 1.0, "",
		func(x: float) -> void:
			state["size"] = x
			on_change.call())

	UiKit.slider_row(v, UiKit.label_for("Line spacing", "تباعد الأسطر"),
		0.7, 2.4, float(state.get("leading", 1.15)), 0.05, "",
		func(x: float) -> void:
			state["leading"] = x
			on_change.call())

	var snap: CheckButton = CheckButton.new()
	snap.text = UiKit.label_for("Snap rotation", "تثبيت الدوران")
	snap.button_pressed = bool(state.get("snap_rotation", false))
	snap.toggled.connect(func(on: bool) -> void:
		state["snap_rotation"] = on
		on_change.call())
	v.add_child(snap)

	UiKit.slider_row(v, UiKit.label_for("Rotation step", "خطوة الدوران"),
		1.0, 45.0, float(state.get("snap_degrees", 15.0)), 1.0, "°",
		func(x: float) -> void:
			state["snap_degrees"] = x
			on_change.call())

	_note_line(v, UiKit.label_for("Colour", "اللون"))
	_swatch_row(v, state, "colour", [
		Color("#1A1712"), Color("#FFF8E7"), Color("#D9B45B"),
		Color("#C0392B"), Color("#2E86C1"), Color("#27AE60")], on_change)

	UiKit.slider_row(v, UiKit.label_for("Halo", "الهالة"),
		0.0, 24.0, float(state.get("halo", 0.0)), 0.5, "",
		func(x: float) -> void:
			state["halo"] = x
			on_change.call())

	_note_line(v, UiKit.label_for("Halo colour", "لون الهالة"))
	_swatch_row(v, state, "halo_colour", [
		Color("#FFF8E7"), Color("#1A1712"), Color("#D9B45B"),
		Color("#C0392B"), Color("#2E86C1"), Color("#27AE60")], on_change)

	var align: HBoxContainer = HBoxContainer.new()
	align.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	v.add_child(align)
	var names: Array = [
		[HORIZONTAL_ALIGNMENT_LEFT, UiKit.label_for("Left", "يسار")],
		[HORIZONTAL_ALIGNMENT_CENTER, UiKit.label_for("Centre", "وسط")],
		[HORIZONTAL_ALIGNMENT_RIGHT, UiKit.label_for("Right", "يمين")]]
	var picks: Array[Button] = []
	var restate: Callable = func(chosen: int) -> void:
		for k in picks.size():
			if is_instance_valid(picks[k]):
				picks[k].set_pressed_no_signal(int(names[k][0]) == chosen)
	for i in names.size():
		var which: int = int(names[i][0])
		var b: Button = UiKit.make_text_button(String(names[i][1]), true)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_pressed_no_signal(int(state.get("align", HORIZONTAL_ALIGNMENT_LEFT)) == which)
		b.pressed.connect(func() -> void:
			state["align"] = which
			restate.call(which)
			on_change.call())
		picks.append(b)
		align.add_child(b)

	_note_line(v, UiKit.label_for(
		"Arabic, Hebrew, Japanese, Chinese and Korean are shaped by the same engine that draws this panel, so they come out joined and ordered correctly rather than as loose letters.",
		"العربية والعبرية واليابانية والصينية والكورية تُشكَّل بالمحرك نفسه الذي يرسم هذه اللوحة، فتخرج موصولة ومرتّبة كما ينبغي لا حروفاً متفرقة."))

	var place: Button = UiKit.make_text_button(
		UiKit.label_for("Put it on the page", "ضعه على الصفحة"), true)
	place.pressed.connect(on_place)
	v.add_child(place)
	return shell

static func _swatch_row(v: VBoxContainer, state: Dictionary, key: String,
		colours: Array, on_change: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	v.add_child(row)
	var chips: Array[Button] = []
	# Read defensively. `state` is a plain Dictionary that outlives this
	# panel and is written to from several places, so a key that is missing —
	# or holding something that is not a Colour — must not bring the panel
	# down on the way up.
	var current: Color = colours[0]
	if state.has(key) and typeof(state[key]) == TYPE_COLOR:
		current = state[key]
	var restate: Callable = func(chosen: int) -> void:
		for k in chips.size():
			if is_instance_valid(chips[k]):
				chips[k].set_pressed_no_signal(k == chosen)
	for i in colours.size():
		var col: Color = colours[i]
		var index: int = i
		var b: Button = Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(UiKit.s(40.0), UiKit.s(38.0))
		var flat: StyleBoxFlat = StyleBoxFlat.new()
		flat.bg_color = Color(col.r, col.g, col.b, 1.0)
		flat.set_corner_radius_all(int(UiKit.s(9.0)))
		flat.border_color = Color(0, 0, 0, 0.35)
		flat.set_border_width_all(1)
		var on: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
		on.border_color = UiKit.TEXT
		on.set_border_width_all(int(maxf(UiKit.s(3.0), 3.0)))
		b.add_theme_stylebox_override("normal", flat)
		b.add_theme_stylebox_override("hover", flat)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("focus", flat)
		b.set_pressed_no_signal(col.is_equal_approx(current))
		b.pressed.connect(func() -> void:
			state[key] = col
			restate.call(index)
			on_change.call())
		chips.append(b)
		row.add_child(b)
