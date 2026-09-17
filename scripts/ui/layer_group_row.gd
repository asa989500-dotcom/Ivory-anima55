class_name LayerGroupRow
extends RefCounted
## A folder's settings sheet.
##
## Lifted out of `layers_panel.gd`, which was at its line ceiling again. The
## seam is the same one `LayerRigRow` follows: the panel decides *that* a
## folder's settings are open, and a file of its own decides what is in them.
##
## Everything here reaches back through `panel`, because a folder's settings
## are not a thing on their own — they are that panel's sheet, filled in.

static func build(panel: LayersPanel, gid: int) -> void:
	var g: LayerStack.Group = panel.stack.group_by_id(gid)
	if g == null:
		panel._close_settings()
		return
	panel._settings_header(g.title)

	var before: Array = []
	var fade: TouchSlider = UiKit.slider_row(panel._settings,
		UiKit.label_for("Folder opacity", "شفافية المجلد"),
		0.0, 1.0, g.opacity, 0.01, "",
		func(x: float) -> void:
			if before.is_empty():
				before.append(panel.stack.capture_arrangement())
			panel.stack.set_group_opacity(gid, x))
	fade.drag_ended.connect(func(_x: float) -> void:
		if before.is_empty():
			return
		panel.view.history.push(UiKit.label_for("Folder opacity", "شفافية مجلد"),
			[{"t": "arrangement", "state": before[0]}])
		before.clear())

	panel._settings.add_child(UiKit.make_label(
		UiKit.label_for("Dims every layer inside it.",
			"تخفّف كل الطبقات التي بداخله."), 11.0, UiKit.TEXT_DIM))

	var expand: Button = UiKit.make_text_button(
		UiKit.label_for("Open the folder", "افتح المجلد"), true)
	expand.pressed.connect(func() -> void:
		panel.stack.set_group_collapsed(gid, false)
		panel._close_settings())
	panel._settings.add_child(expand)

	# The animation layer: it sits at the head of the folder and reads the
	# bones of everything inside it, so a figure drawn across several layers
	# poses as one figure. It gathers the skeleton, never the drawings — the
	# layers under it stay exactly as many layers as they were.
	panel._settings.add_child(HSeparator.new())
	var rigged: bool = panel.stack.group_has_rig(gid)
	var anim: Button = UiKit.make_text_button(
		UiKit.label_for("Animation layer", "طبقة التحريك"), true)
	anim.disabled = not rigged
	anim.pressed.connect(func() -> void:
		g.is_animation = true
		panel.ask_for_animation_layer(gid)
		panel._close_settings())
	panel._settings.add_child(anim)
	panel._settings.add_child(UiKit.make_label(UiKit.label_for(
		"Gathers the bones of every rigged layer in this folder and moves them as one skeleton."
		if rigged else
		"Give a layer in this folder bones first, in the B-Spline room.",
		"يجمع عظام كل طبقة مُهيكلة في هذا المجلد ويحركها كهيكل واحد."
		if rigged else
		"أعطِ طبقةً في هذا المجلد عظاماً أولاً، من غرفة بي-سبلاين."),
		11.0, UiKit.TEXT_DIM))
	panel._settings.add_child(HSeparator.new())

	var undo_group: Button = UiKit.make_text_button(
		UiKit.label_for("Remove the folder", "أزل المجلد"), true)
	undo_group.pressed.connect(func() -> void:
		panel.stack.dissolve_group(gid)
		panel._close_settings())
	panel._settings.add_child(undo_group)

	panel._settings.add_child(UiKit.make_label(
		UiKit.label_for("The layers inside are kept.",
			"الطبقات التي بداخله تبقى كما هي."), 11.0, UiKit.TEXT_DIM))
