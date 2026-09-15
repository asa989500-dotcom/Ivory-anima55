class_name ColorPanel
extends RefCounted
## The colour panel: a wheel, an eyedropper, the ten, and what has been used.
##
## Lifted out of `tool_panels.gd` at stage 153. That file was already one of
## the project's long-standing debts, and this panel roughly trebled in size
## when it stopped being ten squares — so under the size ledger's rule, the
## growth is paid for by taking the whole panel out rather than by shaving
## something else.
##
## It lifts along an obvious seam: nothing else in `ToolPanels` refers to any
## of it, and `ToolPanels.color` stays as a one-line delegate so no caller
## moved. The ten swatches are still declared over there, in `PALETTE`, on
## purpose — the fill panel and the brush panel read the same list, and the
## last time a colour was added to one of them they drifted apart.

## `for_fill` swaps the whole panel over to the bucket's colour. The two
## share nothing but the recent swatches, so choosing a flat never disturbs
## the outline colour sitting in the brush.
## The ten. Named here rather than in the panel so that the fill panel and the
## brush panel cannot drift apart, which is what happened the last time a
## colour was added to one of them.


static func build(_view: CanvasView, for_fill: bool = false) -> PanelContainer:
	# Wider than the other panels, and deliberately. A wheel that has to share
	# a narrow column with a swatch grid ends up too small to place a finger
	# on accurately, which is the one thing a wheel has to be good at.
	var shell: PanelContainer = ToolPanels._shell(360.0)
	var v: VBoxContainer = ToolPanels._column(shell, 620.0)
	if for_fill:
		ToolPanels._title(v, "Fill colour", "لون الملء")
	else:
		ToolPanels._title(v, "Brush colour", "لون الفرشاة")

	var start_col: Color = App.fill_ink if for_fill else App.ink

	# --- the wheel ---
	#
	# Hue around, saturation outward, brightness on the bar. Any colour at
	# all, which is what the ten swatches below cannot give: they are a good
	# palette and they stay, but a palette is a set of decisions somebody
	# else made and there was no way past it — no half-tone for shading, no
	# wash, no matching a grey already in the drawing.
	var wheel: ColorWheel = ColorWheel.new()
	wheel.show_colour(start_col)
	v.add_child(wheel)

	var readout: Label = UiKit.make_label("", 12.0, UiKit.TEXT_DIM)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(readout)

	var swatch: ColorRect = ColorRect.new()
	swatch.custom_minimum_size = Vector2(0.0, UiKit.s(30.0))
	swatch.color = start_col
	v.add_child(swatch)

	# Live while the finger is down; recorded when it lifts.
	#
	# A single sweep across the wheel passes through dozens of colours. Every
	# one of them filed as a choice would fill the twelve recent slots with
	# the path a thumb took to reach one colour, which is why `set_ink_live`
	# exists — see the note on it in `app_state.gd`.
	var live: Callable = func(c: Color) -> void:
		if for_fill:
			App.set_fill_ink_live(c)
		else:
			App.set_ink_live(c)
	wheel.picked.connect(live)
	wheel.gui_input.connect(func(event: InputEvent) -> void:
		var lifted: bool = (event is InputEventScreenTouch \
				and not (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton \
				and not (event as InputEventMouseButton).pressed)
		if not lifted:
			return
		if for_fill:
			App.set_fill_ink(wheel.colour())
		else:
			App.set_ink(wheel.colour()))

	# --- the eyedropper ---
	#
	# Beside the wheel rather than buried in the toolbar, because the two are
	# the same job: the wheel is for a colour you can picture, the dropper for
	# one you are looking at. `pick_into_fill` is what tells the tool which of
	# the two inks the colour it lifts belongs to, and it is set here because
	# here is the only place that knows.
	var dropper: Button = UiKit.make_text_button(
		UiKit.label_for("Pick a colour from the drawing", "التقط لوناً من الرسم"), false)
	dropper.pressed.connect(func() -> void:
		# Which ink the lifted colour lands in. `apply_picked` reads this and
		# nothing else knows the answer — the tool is one tool whichever panel
		# opened it.
		App.pick_into_fill = for_fill
		App.set_tool(App.Tool.PICK))
	v.add_child(dropper)

	ToolPanels._rule(v)

	# --- the ten ---
	ToolPanels._note_line(v, UiKit.label_for(
		"Ten colours, one tap each. The same tap gives the same colour every time, which is what makes a set of drawings look like a set.",
		"عشرة ألوان، ضغطة واحدة لكلٍّ منها. الضغطة نفسها تعطي اللون نفسه في كل مرة، وهذا ما يجعل مجموعة رسومات تبدو مجموعة واحدة."))

	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
	grid.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
	v.add_child(grid)

	var chips: Array[Button] = []
	var apply: Callable = func(c: Color) -> void:
		if for_fill:
			App.set_fill_ink(c)
		else:
			App.set_ink(c)

	for code in ToolPanels.PALETTE:
		var chip: Button = Button.new()
		chip.focus_mode = Control.FOCUS_NONE
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(UiKit.s(44.0), UiKit.s(44.0))
		var c: Color = Color(String(code))
		chip.set_meta("colour", c)
		chip.tooltip_text = "#" + c.to_html(false).to_upper()
		chip.pressed.connect(func() -> void: apply.call(c))
		chips.append(chip)
		grid.add_child(chip)

	# --- what has been used already ---
	#
	# The colours of this drawing, as against the ten the app came with. On a
	# page that is half finished these are almost always what the hand wants
	# next, and they were reachable from nowhere.
	ToolPanels._rule(v)
	ToolPanels._note_line(v, UiKit.label_for("Used recently", "مستخدمة مؤخراً"))
	var recent_row: GridContainer = GridContainer.new()
	recent_row.columns = 6
	recent_row.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
	recent_row.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
	v.add_child(recent_row)

	var fill_recent: Callable = func() -> void:
		if not is_instance_valid(recent_row):
			return
		for child in recent_row.get_children():
			recent_row.remove_child(child)
			child.queue_free()
		for c in App.recent_colors:
			var used: Button = Button.new()
			used.focus_mode = Control.FOCUS_NONE
			used.custom_minimum_size = Vector2(UiKit.s(38.0), UiKit.s(38.0))
			var sb: StyleBoxFlat = StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(int(UiKit.s(8.0)))
			sb.border_color = Color(0.0, 0.0, 0.0, 0.22)
			sb.set_border_width_all(1)
			used.add_theme_stylebox_override("normal", sb)
			used.add_theme_stylebox_override("hover", sb)
			used.add_theme_stylebox_override("pressed", sb)
			used.tooltip_text = "#" + c.to_html(false).to_upper()
			used.pressed.connect(func() -> void: apply.call(c))
			recent_row.add_child(used)

	# Drawn rather than themed, because a swatch has to show the colour it
	# stands for and the one that is chosen at the same time. A pressed
	# stylebox can only do the second.
	var restate: Callable = func(now: Color) -> void:
		if not is_instance_valid(swatch):
			return
		swatch.color = now
		if is_instance_valid(readout):
			readout.text = "#%s   H %d°  S %d%%  V %d%%" % [
				now.to_html(false).to_upper(),
				int(round(now.h * 360.0)), int(round(now.s * 100.0)),
				int(round(now.v * 100.0))]
		if is_instance_valid(wheel) and not wheel.has_focus():
			wheel.show_colour(now)
		for chip in chips:
			if not is_instance_valid(chip):
				continue
			var c: Color = chip.get_meta("colour")
			var sb: StyleBoxFlat = StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(int(UiKit.s(8.0)))
			# The chosen one wears the gold ring. On a palette holding both a
			# near-black and a true black, a ring is the only mark that can
			# be seen on either — a lightened or darkened fill cannot.
			var picked: bool = c.to_html(false) == now.to_html(false)
			sb.border_color = UiKit.ACCENT if picked \
				else Color(0.0, 0.0, 0.0, 0.22)
			sb.set_border_width_all(int(UiKit.s(3.0)) if picked else 1)
			chip.add_theme_stylebox_override("normal", sb)
			chip.add_theme_stylebox_override("hover", sb)
			chip.add_theme_stylebox_override("pressed", sb)
		fill_recent.call()

	var feed: Signal = App.fill_color_changed if for_fill else App.color_changed
	feed.connect(restate)
	shell.tree_exiting.connect(func() -> void:
		if feed.is_connected(restate):
			feed.disconnect(restate))

	restate.call(start_col)
	return shell
