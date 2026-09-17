class_name StretchyStudioModule
extends RefCounted
## Stretchy Studio integration boundary.
##
## This file owns only the Stretchy-facing controls and state. It deliberately
## does not replace CanvasView, TimelinePanel, touch routing, or LayerStack.
## Existing Ivory C++ SmartBone is used when the native extension is present;
## the rest of the app remains available when it is not.

const IVORY_BG := Color("#FFF8E7")
const IVORY_PANEL := Color("#F4E8D0")
const IVORY_EDGE := Color("#D8C19A")
const IVORY_TEXT := Color("#2B2118")
const IVORY_MUTED := Color("#766654")
const IVORY_ACCENT := Color("#B78A3C")

static func panel(host: Node, view: CanvasView) -> PanelContainer:
	var shell := PanelContainer.new()
	shell.name = "StretchyStudioPanel"
	shell.set_meta("desired_width", 430.0)
	shell.add_theme_stylebox_override("panel", _panel_style())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(UiKit.s(390.0), UiKit.s(520.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	column.add_theme_constant_override("margin_left", int(UiKit.s(14.0)))
	column.add_theme_constant_override("margin_right", int(UiKit.s(14.0)))
	column.add_theme_constant_override("margin_top", int(UiKit.s(14.0)))
	column.add_theme_constant_override("margin_bottom", int(UiKit.s(14.0)))
	scroll.add_child(column)

	var title := Label.new()
	title.text = "Stretchy Studio  /  ستريتشـي ستوديو"
	title.add_theme_color_override("font_color", IVORY_TEXT)
	title.add_theme_font_size_override("font_size", int(UiKit.s(18.0)))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Animation workspace · bones · layers · mesh deformation"
	subtitle.add_theme_color_override("font_color", IVORY_MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)

	_section(column, "Workspace  /  مساحة العمل")
	_action(column, "layers", "Layers  /  الطبقات", "Open the existing layer stack", func() -> void:
		host.call("_close_panel")
		host.call("_toggle_panel", "layers"))
	_action(column, "anim_layer", "Animation layer  /  طبقة الرسوم", "Use the existing animation-layer workflow", func() -> void:
		host.call("_close_panel")
		host.call("_toggle_timeline"))
	_action(column, "anim_layer", "Timeline  /  التايملاين", "Open the existing timeline without replacing it", func() -> void:
		host.call("_close_panel")
		host.call("_toggle_timeline"))

	_section(column, "Armature  /  الهيكل العظمي")
	_action(column, "layers", "Rig current layer  /  تجهيز الطبقة الحالية", "Open the existing bone room on the active layer", func() -> void:
		var index := _active_layer(view)
		host.call("_close_panel")
		if index >= 0:
			host.call("enter_bone_room", index)
		else:
			host.call("_flash", UiKit.label_for("Select a layer first", "اختر طبقة أولاً"))
		)
	_action(column, "anim_layer", "Smart Bone dials  /  عظام Smart Bone", "Use the native C++ smart-bone engine when available", func() -> void:
		_show_smartbone_status(column, view))

	_section(column, "Stretchy tools  /  أدوات Stretchy")
	_action(column, "brush", "Brush library  /  مكتبة الفرش", "Open the existing touch-safe brush system", func() -> void:
		host.call("_close_panel")
		host.call("_toggle_panel", "brush"))
	_action(column, "layers", "Mesh and deformation  /  الشبكة والتشوه", "Open the existing puppet/mesh workflow", func() -> void:
		host.call("_close_panel")
		host.call("_toggle_panel", "layers"))

	_section(column, "Integration  /  الربط")
	var state := Label.new()
	state.text = _integration_status(view)
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_theme_color_override("font_color", IVORY_MUTED)
	column.add_child(state)
	var note := Label.new()
	note.text = "Canvas, touch routing, layers and timeline remain owned by IVORY. This module only provides the Stretchy workspace entry point and delegates to those existing owners."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", IVORY_TEXT)
	column.add_child(note)
	return shell

static func _active_layer(view: CanvasView) -> int:
	if view == null or view.layers == null:
		return -1
	return view.layers.active_index if view.layers.active_index >= 0 else -1

static func _integration_status(view: CanvasView) -> String:
	var native_state: String = "C++ SmartBone: available" if Native.has_smartbone() else "C++ SmartBone: optional extension not loaded"
	var project_state: String = "Animation project: ready" if view != null and view.has_project() else "Open an animation project first"
	return "%s\n%s\nTouch input: owned by IVORY" % [native_state, project_state]

static func _show_smartbone_status(column: VBoxContainer, _view: CanvasView) -> void:
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", IVORY_TEXT)
	if not Native.has_smartbone():
		status.text = "The native C++ SmartBone class is present in source but its GDExtension is not loaded in this checkout. Build the extension to enable live dials."
		column.add_child(status)
		return
	var smart := Native.smartbone()
	if smart == null:
		status.text = "SmartBone could not be instantiated. Existing bone and timeline tools remain unchanged."
		column.add_child(status)
		return
	var dial := smart.add_dial(0)
	smart.add_key(dial, -1.2)
	smart.add_key(dial, 0.0)
	smart.add_key(dial, 1.2)
	smart.set_overshoot(true)
	status.text = "Native SmartBone ready: Catmull–Rom angle curves, overshoot control, point offsets and project serialization are available for the current rig."
	column.add_child(status)

static func _section(parent: VBoxContainer, text: String) -> void:
	var rule := HSeparator.new()
	rule.add_theme_color_override("separator", IVORY_EDGE)
	parent.add_child(rule)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", IVORY_ACCENT)
	label.add_theme_font_size_override("font_size", int(UiKit.s(14.0)))
	parent.add_child(label)

static func _action(parent: VBoxContainer, icon_name: String, text: String, tip: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(UiKit.s(360.0), UiKit.s(48.0))
	button.focus_mode = Control.FOCUS_NONE
	var icon_path := "res://assets/icons/%s.png" % icon_name
	if ResourceLoader.exists(icon_path):
		button.icon = load(icon_path)
	button.add_theme_constant_override("icon_max_width", int(UiKit.s(24.0)))
	button.add_theme_constant_override("h_separation", int(UiKit.s(12.0)))
	button.add_theme_color_override("font_color", IVORY_TEXT)
	button.add_theme_color_override("font_hover_color", IVORY_TEXT)
	button.add_theme_color_override("icon_normal_color", IVORY_TEXT)
	button.add_theme_stylebox_override("normal", _button_style(IVORY_BG))
	button.add_theme_stylebox_override("hover", _button_style(Color("#FFFDF5")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#E6D3AA")))
	button.pressed.connect(action)
	parent.add_child(button)

static func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = IVORY_PANEL
	style.border_color = IVORY_EDGE
	style.set_border_width_all(int(UiKit.s(1.0)))
	style.set_corner_radius_all(int(UiKit.s(14.0)))
	style.set_content_margin_all(UiKit.s(8.0))
	return style

static func _button_style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = IVORY_EDGE
	style.set_border_width_all(int(UiKit.s(1.0)))
	style.set_corner_radius_all(int(UiKit.s(10.0)))
	style.set_content_margin_all(UiKit.s(8.0))
	return style
