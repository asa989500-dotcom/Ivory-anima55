class_name CanvasSize
extends RefCounted
## Choosing how big a canvas is, on every kind of project.
##
## ## The gap this closes
##
## There was no choice. Every project of every kind was created at 1600 by
## 1200 and there was a comment in `settings_panels.gd` saying so — page
## dimensions were "intentionally not exposed". Which meant IVORY could not
## make anything at a standard size: no Full HD, no 4K, no A4, nothing that
## another program would accept without resampling. For an app whose whole
## output is video and printed pages, that is not a missing setting, it is a
## missing capability.
##
## ## Why it is a row that opens rather than a list on the sheet
##
## There are twenty-six sizes. Twenty-six buttons on the creation sheet would
## bury the four things that were already there — the name, the frame rate,
## the paper colour, the Create button — under a wall of numbers, on a sheet
## somebody sees every time they start anything.
##
## So it is one row showing the current size with a downward arrow, exactly
## like every other collapsed control in the app. Press it and a small
## floating panel comes up over the sheet; choose, and it closes and the row
## says what was chosen.
##
## ## Why there is a preview
##
## Because "3840 by 2160" is a pair of numbers and a canvas is a shape. The
## difference between 1080 by 1920 and 1920 by 1080 is invisible in the digits
## and unmissable in the outline, and choosing the wrong one of those is a
## project that has to be started again.
##
## The preview is drawn to scale against the largest offered size, so the
## outlines of two different presets are actually comparable — a preview that
## always filled its box would make an 8K canvas and a thumbnail look
## identical, which is worse than no preview at all because it looks like
## information.
##
## ## And two fields for anything else
##
## The presets cover what is standard. They cannot cover what somebody's
## printer, client or animation happens to need, and a chooser that only
## offers a list is a chooser that refuses those people. So there are two
## boxes, they take any number, and what they take is held inside what the
## device can actually open — see `_hold`.

## The largest side any preset offers, which the preview is drawn to scale
## against. Read from the table rather than written down, so adding a bigger
## preset cannot leave this stale.
static var _biggest: float = 0.0

## What the chooser hands back. A single-element array, because a Callable
## capturing a plain float captures a copy and the panel would have nothing to
## write into.
## The six best-known sizes, and a place to type any other.
##
## ## Why the ▾ went
##
## The row used to be a word and a little downward triangle, and every size in
## the app was behind that triangle. Two problems with it, and the second is
## the one that matters.
##
## A triangle is not a size. It says "there is more under here" and nothing at
## all about what — so the only way to find out whether the size you wanted
## exists is to open it, and the only way to compare two is to open it twice.
##
## And it hid the whole decision behind a target four millimetres across, at
## the exact moment somebody is making a new project and has the least idea
## what the app can do. The most common answer should not need a tap to
## discover.
##
## So the six that cover most work are on the surface as squares, each showing
## its own proportion drawn to scale, and anything else is typed into the two
## boxes beside them. The full table is still there — `panel` still builds it
## — for the cases the six do not cover.
##
## Six, not eight or ten: six fits two rows of three on the narrowest phone
## this runs on without either shrinking below a fingertip or scrolling, and a
## row of sizes that scrolls is a row whose last item nobody ever picks.
const QUICK: Array = [
	{"key": "Full HD", "w": 1920, "h": 1080},
	{"key": "Vertical HD", "w": 1080, "h": 1920},
	{"key": "Square 2K", "w": 2048, "h": 2048},
	{"key": "4K UHD", "w": 3840, "h": 2160},
	{"key": "A4 300", "w": 2480, "h": 3508},
	{"key": "Comic page", "w": 1988, "h": 3056},
]

static func row(into: VBoxContainer, host: Node, kind_word: String,
		size: Array) -> void:
	into.add_child(UiKit.make_label(
		UiKit.label_for("Canvas size", "مقاس اللوحة"), 12.0, UiKit.TEXT_DIM))

	var note: Label = UiKit.make_label(_cost(size[0] as Vector2), 11.0,
		UiKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
	grid.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
	into.add_child(grid)

	var wide: LineEdit = _field(str(int((size[0] as Vector2).x)))
	var high: LineEdit = _field(str(int((size[0] as Vector2).y)))
	var tiles: Array[Button] = []

	# Declared before the tiles, because each tile's handler calls it.
	var restate: Callable = func() -> void:
		var now: Vector2 = size[0] as Vector2
		note.text = _cost(now)
		if not wide.has_focus():
			wide.text = str(int(now.x))
		if not high.has_focus():
			high.text = str(int(now.y))
		for i in tiles.size():
			var tile: Button = tiles[i]
			if not is_instance_valid(tile):
				continue
			var row_data: Dictionary = QUICK[i]
			var mine: bool = int(now.x) == int(row_data["w"]) \
				and int(now.y) == int(row_data["h"])
			var sb: StyleBoxFlat = StyleBoxFlat.new()
			sb.bg_color = UiKit.CHIP
			sb.set_corner_radius_all(int(UiKit.s(10.0)))
			sb.border_color = UiKit.ACCENT if mine else UiKit.PANEL_EDGE
			sb.set_border_width_all(int(UiKit.s(2.0)) if mine else 1)
			tile.add_theme_stylebox_override("normal", sb)
			tile.add_theme_stylebox_override("hover", sb)
			tile.add_theme_stylebox_override("pressed", sb)

	var choose: Callable = func(want: Vector2) -> void:
		size[0] = _hold(want)
		restate.call()

	for row_data in QUICK:
		var tile: Button = Button.new()
		tile.focus_mode = Control.FOCUS_NONE
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.custom_minimum_size = Vector2(UiKit.s(88.0), UiKit.s(70.0))
		var w: int = int(row_data["w"])
		var h: int = int(row_data["h"])
		var r: Vector2i = _ratio(Vector2(float(w), float(h)))
		# The name, the proportion and the pixels, in that order: the name is
		# what somebody is looking for, the proportion is what they are
		# choosing between, and the number is what they check afterwards.
		tile.text = "%s\n%d:%d\n%d × %d" % [String(row_data["key"]),
			r.x, r.y, w, h]
		tile.add_theme_font_size_override("font_size", int(UiKit.s(10.0)))
		tile.tooltip_text = _words(Vector2(float(w), float(h)))
		tile.pressed.connect(func() -> void:
			choose.call(Vector2(float(w), float(h))))
		tiles.append(tile)
		grid.add_child(tile)

	# --- anything else, typed ---
	var custom: HBoxContainer = HBoxContainer.new()
	custom.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	into.add_child(custom)
	custom.add_child(UiKit.make_label(UiKit.label_for("Or type", "أو اكتب"),
		11.0, UiKit.TEXT_DIM))
	wide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	high.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom.add_child(wide)
	custom.add_child(UiKit.make_label("×", 12.0, UiKit.TEXT_DIM))
	custom.add_child(high)

	# Read on leaving the box as well as on Enter. On a phone there is no
	# Enter unless the keyboard offers one, and a number typed and then
	# tapped away from must not be quietly discarded.
	var take: Callable = func(_ignored: String = "") -> void:
		var w: float = float(wide.text.strip_edges())
		var h: float = float(high.text.strip_edges())
		if w < 1.0 or h < 1.0:
			restate.call()
			return
		choose.call(Vector2(w, h))
	wide.text_submitted.connect(take)
	high.text_submitted.connect(take)
	wide.focus_exited.connect(func() -> void: take.call())
	high.focus_exited.connect(func() -> void: take.call())

	into.add_child(note)

	# The full table, for the sizes the six do not cover. Opened by its own
	# named button rather than by a triangle, so it says what it is.
	var more: Button = UiKit.make_text_button(
		UiKit.label_for("All sizes", "كل المقاسات"))
	more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	into.add_child(more)

	var pop: PanelContainer = panel(host, kind_word, size,
		func() -> void: restate.call())
	pop.top_level = true
	pop.visible = false
	pop.z_index = 220
	into.add_child(pop)
	# Tap anywhere else and it goes. Before this the only way to close it was
	# the button that opened it, and the first thing anyone does with a
	# floating panel is tap past it.
	Dismiss.watch(pop, func() -> void: pop.visible = false)

	# --- the panel floats over the sheet, it does not replace it ---
	#
	# The obvious build is `_close_panel` then `_mount`, which is how every
	# other panel in the app opens. It is wrong here and the reason is
	# specific to this one: the sheet underneath is a *form*. It is holding a
	# name somebody typed, a frame rate they chose and a paper colour they
	# picked, and closing it to show the size chooser throws all of that away.
	var place: Callable = func() -> void:
		var want: Vector2 = more.global_position + Vector2(0.0, more.size.y
			+ UiKit.s(6.0))
		var screen: Vector2 = more.get_viewport_rect().size
		var box: Vector2 = pop.size
		if box.x < 1.0:
			box = pop.get_combined_minimum_size()
		want.x = clampf(want.x, UiKit.s(6.0),
			maxf(screen.x - box.x - UiKit.s(6.0), UiKit.s(6.0)))
		want.y = clampf(want.y, UiKit.s(6.0),
			maxf(screen.y - box.y - UiKit.s(6.0), UiKit.s(6.0)))
		pop.global_position = want

	more.pressed.connect(func() -> void:
		pop.visible = not pop.visible
		if pop.visible:
			place.call()
			if more.is_inside_tree():
				more.get_tree().process_frame.connect(place,
					Object.CONNECT_ONE_SHOT))

	pop.set_meta("dismiss", func() -> void: pop.visible = false)
	restate.call()

## The floating panel itself.
static func panel(_host: Node, kind_word: String, size: Array,
		after: Callable) -> PanelContainer:
	var shell: PanelContainer = ToolPanels._shell(520.0)
	var v: VBoxContainer = ToolPanels._column(shell)
	ToolPanels._title(v, "Canvas size", "مقاس اللوحة")

	# --- the preview ---
	var preview: Control = Control.new()
	preview.custom_minimum_size = Vector2(0.0, UiKit.s(132.0))
	v.add_child(preview)
	preview.draw.connect(func() -> void:
		_draw_preview(preview, size[0] as Vector2))

	var reading: Label = UiKit.make_label(_words(size[0] as Vector2), 13.0,
		UiKit.TEXT)
	reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(reading)
	var cost: Label = UiKit.make_label(_cost(size[0] as Vector2), 11.0,
		UiKit.TEXT_DIM)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cost)

	var technical: Label = UiKit.make_label("", 10.0, UiKit.TEXT_DIM)
	technical.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	technical.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(technical)

	var update_technical: Callable = func() -> void:
		var native_profile: Object = Native.canvas()
		if native_profile == null:
			technical.text = UiKit.label_for(
				"Technical profile: native canvas module is not built.",
				"الملف التقني: وحدة الكانفاس C++ غير مبنية.")
			return
		var info: Dictionary = native_profile.profile(kind_word,
			Vector2i(int((size[0] as Vector2).x), int((size[0] as Vector2).y)),
			8, 48)
		technical.text = UiKit.label_for(
				"Tile %d px  ·  recommended undo %d  ·  estimated working set %.0f MB",
				"البلاطة %d بكسل  ·  التراجع المقترح %d  ·  الذاكرة التقديرية %.0f MB") % [
				int(info["tile"]), int(info["recommended_undo"]),
				float(info["estimated_mb"])]

	# One place that puts every part of the panel back in step, so a choice
	# made by a preset and one typed into a field cannot leave the preview
	# showing one thing and the reading another.
	var refresh: Callable = func() -> void:
		reading.text = _words(size[0] as Vector2)
		cost.text = _cost(size[0] as Vector2)
		preview.queue_redraw()
		update_technical.call()
		if after.is_valid():
			after.call()

	v.add_child(HSeparator.new())

	# --- your own numbers ---
	#
	# Above the presets rather than below them. Somebody who came here to type
	# a number should not have to scroll past twenty-six they did not want.
	ToolPanels._title(v, "Your own", "مقاسك أنت")
	var pair: HBoxContainer = HBoxContainer.new()
	pair.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	v.add_child(pair)
	var wide: LineEdit = _field(str(int((size[0] as Vector2).x)))
	var tall: LineEdit = _field(str(int((size[0] as Vector2).y)))
	pair.add_child(UiKit.make_label(UiKit.label_for("Width", "العرض"), 12.0,
		UiKit.TEXT_DIM))
	pair.add_child(wide)
	pair.add_child(UiKit.make_label(UiKit.label_for("Height", "الارتفاع"),
		12.0, UiKit.TEXT_DIM))
	pair.add_child(tall)

	var take: Callable = func(_txt: String) -> void:
		# Read on every keystroke rather than on a separate Apply button. An
		# apply step is one more thing to forget, and forgetting it means
		# creating a project at a size you did not choose and can no longer
		# change.
		size[0] = _hold(Vector2(float(int(wide.text)), float(int(tall.text))))
		refresh.call()
	wide.text_changed.connect(take)
	tall.text_changed.connect(take)
	# Held to whole numbers when the field is left, so 1920.4 does not sit
	# there implying it was accepted.
	var settle: Callable = func() -> void:
		wide.text = str(int((size[0] as Vector2).x))
		tall.text = str(int((size[0] as Vector2).y))
	wide.focus_exited.connect(settle)
	tall.focus_exited.connect(settle)
	ToolPanels._note_line(v, UiKit.label_for(
		"Any number either side. Held between 64 and 8192, and never so lopsided that one side is a hairline — a canvas thirty times longer than it is wide is a mistyped number far more often than it is a panorama.",
		"أيّ رقمٍ في الجهتين. يُحصر بين ٦٤ و٨١٩٢، ولا يُترك مائلاً حتى يصير أحد ضلعيه شعرة — فاللوحة الأطول من عرضها ثلاثين مرّة رقمٌ مطبوعٌ خطأً أكثر ممّا هي بانوراما."))

	v.add_child(HSeparator.new())

	# --- the presets ---
	for band in _bands(kind_word):
		ToolPanels._title(v, String(band["en"]), String(band["ar"]))
		var flow: HFlowContainer = HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", int(UiKit.s(5.0)))
		flow.add_theme_constant_override("v_separation", int(UiKit.s(5.0)))
		v.add_child(flow)
		for one in band["rows"]:
			var row_size: Vector2 = Vector2(float(one["w"]), float(one["h"]))
			var b: Button = UiKit.make_text_button(String(one["key"]))
			b.custom_minimum_size = Vector2(UiKit.s(84.0),
				UiKit.s(UiKit.TOUCH_FLOOR))
			b.tooltip_text = "%d x %d" % [int(row_size.x), int(row_size.y)]
			b.pressed.connect(func() -> void:
				size[0] = row_size
				wide.text = str(int(row_size.x))
				tall.text = str(int(row_size.y))
				refresh.call()
				if shell.has_meta("dismiss"):
					(shell.get_meta("dismiss") as Callable).call())
			flow.add_child(b)
	v.add_child(HSeparator.new())
	var done: Button = UiKit.make_text_button(UiKit.label_for("Done", "تمّ"),
		true)
	done.pressed.connect(func() -> void:
		if shell.has_meta("dismiss"):
			(shell.get_meta("dismiss") as Callable).call())
	v.add_child(done)
	return shell

# ------------------------------------------------------------- the presets

## The table, from C++ when it is there and from here when it is not.
##
## The GDScript copy is not a fallback in the sense of being worse — it is the
## same numbers. It exists because the app has to run on a checkout where
## nobody has built the extension yet, and a project creation sheet that
## offers no sizes at all on that checkout would be a far larger failure than
## the one it is guarding against.
static func _table(kind_word: String) -> Array:
	var native: Object = Native.canvas()
	if native != null:
		return native.presets_for(kind_word)
	return _plain_table(kind_word)

static func _plain_table(kind_word: String) -> Array:
	var rows: Array = [
		{"key": "8K UHD", "w": 7680, "h": 4320, "group": "screen"},
		{"key": "4K UHD", "w": 3840, "h": 2160, "group": "screen"},
		{"key": "4K DCI", "w": 4096, "h": 2160, "group": "screen"},
		{"key": "2K QHD", "w": 2560, "h": 1440, "group": "screen"},
		{"key": "Full HD", "w": 1920, "h": 1080, "group": "screen"},
		{"key": "HD", "w": 1280, "h": 720, "group": "screen"},
		{"key": "SD", "w": 854, "h": 480, "group": "screen"},
		{"key": "Vertical HD", "w": 1080, "h": 1920, "group": "screen"},
		{"key": "Vertical 4K", "w": 2160, "h": 3840, "group": "screen"},
		{"key": "A3 300", "w": 3508, "h": 4961, "group": "print"},
		{"key": "A4 300", "w": 2480, "h": 3508, "group": "print"},
		{"key": "A5 300", "w": 1748, "h": 2480, "group": "print"},
		{"key": "A4 150", "w": 1240, "h": 1754, "group": "print"},
		{"key": "Letter 300", "w": 2550, "h": 3300, "group": "print"},
		{"key": "Tabloid 300", "w": 3300, "h": 5100, "group": "print"},
		{"key": "Comic page", "w": 1988, "h": 3056, "group": "print"},
		{"key": "Square 4K", "w": 4096, "h": 4096, "group": "square"},
		{"key": "Square 2K", "w": 2048, "h": 2048, "group": "square"},
		{"key": "Square 1K", "w": 1024, "h": 1024, "group": "square"},
		{"key": "Post", "w": 1080, "h": 1080, "group": "social"},
		{"key": "Story", "w": 1080, "h": 1920, "group": "social"},
		{"key": "Wide post", "w": 1200, "h": 630, "group": "social"},
		{"key": "Thumbnail", "w": 1280, "h": 720, "group": "social"},
		{"key": "Classic", "w": 1600, "h": 1200, "group": "screen"},
		{"key": "Sketch", "w": 1200, "h": 900, "group": "screen"},
		{"key": "Small", "w": 800, "h": 600, "group": "screen"},
	]
	# Whichever family this kind of project usually wants, first. One table in
	# two orders rather than two tables, which would stop agreeing the first
	# time a size was added to one of them.
	var moving: bool = kind_word == "animation"
	var lead: Array = []
	var rest: Array = []
	for r in rows:
		var wanted: bool = (String(r["group"]) == "screen") if moving \
			else (String(r["group"]) == "print")
		if wanted:
			lead.append(r)
		else:
			rest.append(r)
	return lead + rest

## The presets grouped into the bands the panel lays out, in the table's own
## order so the leading family stays leading.
static func _bands(kind_word: String) -> Array:
	var titles: Dictionary = {
		"screen": {"en": "Screen and video", "ar": "الشاشة والفيديو"},
		"print": {"en": "Print", "ar": "الطباعة"},
		"square": {"en": "Square", "ar": "مربّع"},
		"social": {"en": "Social", "ar": "اجتماعي"},
	}
	var order: Array = []
	var held: Dictionary = {}
	for r in _table(kind_word):
		var g: String = String(r["group"])
		if not held.has(g):
			held[g] = []
			order.append(g)
		(held[g] as Array).append(r)
	var out: Array = []
	for g in order:
		var t: Dictionary = titles.get(g, {"en": g, "ar": g})
		out.append({"en": t["en"], "ar": t["ar"], "rows": held[g]})
	return out

# ------------------------------------------------------------ the numbers

## A size held inside what is sensible, through C++ when it is there.
static func _hold(want: Vector2) -> Vector2:
	var native: Object = Native.canvas()
	if native != null:
		var got: Vector2i = native.sane(Vector2i(int(want.x), int(want.y)))
		return Vector2(float(got.x), float(got.y))
	var w: float = clampf(want.x, 64.0, 8192.0)
	var h: float = clampf(want.y, 64.0, 8192.0)
	if w / h > 30.0:
		h = minf(round(w / 30.0), 8192.0)
	elif h / w > 30.0:
		w = minf(round(h / 30.0), 8192.0)
	return Vector2(maxf(w, 64.0), maxf(h, 64.0))

## "1920 x 1080 - 16:9".
static func _words(size: Vector2) -> String:
	var native: Object = Native.canvas()
	if native != null:
		return String(native.describe(Vector2i(int(size.x), int(size.y))))
	var r: Vector2i = _ratio(size)
	return "%d x %d  -  %d:%d" % [int(size.x), int(size.y), r.x, r.y]

static func _ratio(size: Vector2) -> Vector2i:
	var w: int = maxi(int(size.x), 1)
	var h: int = maxi(int(size.y), 1)
	var a: int = w
	var b: int = h
	while b != 0:
		var t: int = a % b
		a = b
		b = t
	var g: int = maxi(a, 1)
	@warning_ignore("integer_division")
	var rw: int = w / g
	@warning_ignore("integer_division")
	var rh: int = h / g
	if rw > 64 or rh > 64:
		# A ratio like 427:240 tells nobody anything. Past a point the honest
		# answer is the nearest common one, and the common ones are few.
		var common: Array = [Vector2i(16, 9), Vector2i(9, 16), Vector2i(4, 3),
			Vector2i(3, 4), Vector2i(3, 2), Vector2i(2, 3), Vector2i(1, 1),
			Vector2i(21, 9), Vector2i(5, 4), Vector2i(16, 10),
			Vector2i(10, 16)]
		var want: float = float(w) / float(h)
		var best: float = 1.0e9
		for c in common:
			var off: float = absf(float((c as Vector2i).x)
				/ float((c as Vector2i).y) - want)
			if off < best:
				best = off
				rw = (c as Vector2i).x
				rh = (c as Vector2i).y
	return Vector2i(rw, rh)

## What one page of this size costs to keep open.
##
## ## Why this is said out loud on the creation sheet
##
## Because it is the only moment it can still be changed painlessly. A 4K
## animation with twenty layers is a few hundred megabytes of surface before a
## single stroke, and on a mid-range phone that is the difference between an
## app and one that is killed on its third launch — discovered a week into the
## work, when the answer is to start again at a smaller size.
##
## Said as a plain number with a warning past the point where it matters,
## rather than as a refusal. Somebody on a tablet with plenty of memory should
## be able to make an 8K canvas, and telling them they may not because a phone
## could not is deciding for a device that is not in the room.
static func _cost(size: Vector2) -> String:
	var bytes: float = size.x * size.y * 4.0 * 8.0 * 1.2
	var native: Object = Native.canvas()
	if native != null:
		bytes = float(native.bytes_for(Vector2i(int(size.x), int(size.y)), 8))
	var mb: float = bytes / 1048576.0
	var plain: String = UiKit.label_for(
		"About %d MB for eight layers", "نحو %d ميغابايت لثماني طبقات") \
		% int(round(mb))
	if mb > 420.0:
		return plain + "  -  " + UiKit.label_for(
			"heavy; a phone may struggle to reopen it",
			"ثقيل؛ قد يعجز الهاتف عن إعادة فتحه")
	return plain

# ------------------------------------------------------------- the preview

## The chosen canvas, drawn to scale against the largest size on offer.
##
## Drawn to scale on purpose. A preview stretched to fill its box every time
## would make an 8K canvas and a thumbnail look identical, which is worse than
## no preview at all: it looks like information and is not.
static func _draw_preview(on: Control, size: Vector2) -> void:
	var box: Vector2 = on.size
	if box.x < 4.0 or box.y < 4.0:
		return
	if _biggest <= 0.0:
		for r in _plain_table("animation"):
			_biggest = maxf(_biggest,
				maxf(float(r["w"]), float(r["h"])))
	var pad: float = UiKit.s(10.0)
	# The room the very largest preset would take, which is what every smaller
	# one is measured against.
	var full: float = minf(box.x - pad * 2.0, box.y - pad * 2.0)
	var scale: float = full / maxf(_biggest, 1.0)
	# A floor, so a small canvas is still a shape rather than a dot. Below
	# about a fifth of the box the comparison has stopped being readable
	# anyway and what matters is the proportion.
	var shown: Vector2 = size * scale
	var least: float = full * 0.22
	if maxf(shown.x, shown.y) < least:
		shown *= least / maxf(maxf(shown.x, shown.y), 0.001)
	var at: Vector2 = (box - shown) * 0.5

	# The largest offered size, faintly, so the chosen one has something to be
	# smaller than. Without it "to scale" is a claim nobody can check.
	var full_box: Vector2 = Vector2(full, full)
	on.draw_rect(Rect2((box - full_box) * 0.5, full_box),
		Color(1.0, 0.98, 0.92, 0.05), false, maxf(UiKit.s(1.0), 1.0))

	on.draw_rect(Rect2(at, shown), Color(1.0, 1.0, 1.0, 0.10), true)
	on.draw_rect(Rect2(at, shown), Color("#FFF8E7"), false,
		maxf(UiKit.s(1.6), 1.4))

	# The proportion, written inside the outline where it is being looked at.
	var r: Vector2i = _ratio(size)
	var text: String = "%d:%d" % [r.x, r.y]
	var font: Font = ThemeDB.fallback_font
	var pt: int = maxi(int(UiKit.s(12.0)), 9)
	var wide: float = font.get_string_size(text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, pt).x
	on.draw_string(font,
		at + Vector2((shown.x - wide) * 0.5, shown.y * 0.5 + float(pt) * 0.36),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, pt,
		Color(1.0, 0.98, 0.92, 0.72))

static func _field(value: String) -> LineEdit:
	var f: LineEdit = LineEdit.new()
	f.text = value
	f.alignment = HORIZONTAL_ALIGNMENT_CENTER
	f.custom_minimum_size = Vector2(UiKit.s(72.0), UiKit.s(UiKit.TOUCH_FLOOR))
	f.add_theme_font_size_override("font_size", int(UiKit.s(14.0)))
	return f
