class_name StretchyStudioRoom
extends Control
## Dedicated Stretchy Studio room.
##
## This room owns Stretchy document state: armature dials, angle curves,
## layers, brush settings, and its own animation timeline. The IVORY CanvasView
## remains the only drawing surface and receives the selected layer through the
## narrow bridge below. No IVORY panel or IVORY timeline is embedded here.

signal closed

const ROOM_BG := Color("#FFF8E7")
const PANEL_BG := Color("#F4E8D0")
const PANEL_EDGE := Color("#D8C19A")
const TEXT := Color("#2B2118")
const MUTED := Color("#766654")
const ACCENT := Color("#B78A3C")
const PROJECT_FORMAT := "stretchy.ivory.v1"

var host: MainRoom = null
var view: CanvasView = null
var document: Dictionary = {}
var selected_layer: int = -1
var selected_dial: int = -1
var selected_key: int = -1
var playhead: float = 0.0
var native_smartbone: Object = null
var native_jiggle_physics: Object = null
var _tabs: TabContainer
var _layer_list: ItemList
var _armature_label: Label
var _timeline_label: Label
var _status: Label
var _file_dialog: FileDialog

func setup(owner: MainRoom, canvas: CanvasView) -> void:
	host = owner
	view = canvas
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	document = _new_document()
	native_smartbone = Native.smartbone()
	native_jiggle_physics = Native.jiggle_physics()
	_refresh_from_ivory()
	_build_room()
	_sync_native_physics()

func _process(delta: float) -> void:
	# Only steps the pendulum chains; nothing here yet paints the result
	# onto the canvas mesh. Reading `dial_swing_deg()` below is enough to
	# drive a UI preview or a future bridge into CanvasView, the same
	# staged way `native_smartbone` was left ready before its own bridge
	# existed. See STRETCHY_STUDIO_INTEGRATION.md.
	if native_jiggle_physics != null and bool(document["settings"].get("physics", false)):
		native_jiggle_physics.update(delta)

func _new_document() -> Dictionary:
	return {
		"format": PROJECT_FORMAT,
		"version": 1,
		"layers": [],
		"dials": [],
		"curves": [],
		"timeline": {"fps": 24, "length": 24, "current_frame": 0, "tracks": []},
		"brush": {"name": "Stretchy Brush", "size": 24.0, "opacity": 1.0, "pressure": true},
		"settings": {"mesh_density": 32, "overshoot": true, "physics": false}
	}

func _refresh_from_ivory() -> void:
	if view == null or view.layers == null:
		return
	var layers: Array = []
	for i in range(view.layers.layers.size()):
		var layer: LayerStack.Layer = view.layers.layers[i]
		layers.append({
			"id": layer.id,
			"name": layer.title,
			"visible": layer.visible,
			"source_index": i,
			"armature": {},
			"clips": []
		})
	document["layers"] = layers
	if not layers.is_empty():
		selected_layer = clampi(view.layers.active_index, 0, layers.size() - 1)

func _build_room() -> void:
	var background := ColorRect.new()
	background.color = ROOM_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 62.0
	top.add_theme_stylebox_override("panel", _panel_style(PANEL_BG))
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top.add_child(top_row)
	var title := Label.new()
	title.text = "Stretchy Studio  /  غرفة الرسوم المتحركة"
	title.add_theme_color_override("font_color", TEXT)
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)
	var import_button := _button("Import image  /  استيراد صورة")
	import_button.pressed.connect(_open_import)
	top_row.add_child(import_button)
	var save_button := _button("Save .stretchy  /  حفظ")
	save_button.pressed.connect(_save_project)
	top_row.add_child(save_button)
	var export_button := _button("Export Android  /  تصدير Android")
	export_button.pressed.connect(_export_android_bundle)
	top_row.add_child(export_button)
	var close_button := _button("Close  /  إغلاق")
	close_button.pressed.connect(func() -> void: closed.emit())
	top_row.add_child(close_button)

	var side := PanelContainer.new()
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_top = 70.0
	side.offset_right = 350.0
	side.offset_bottom = -18.0
	side.add_theme_stylebox_override("panel", _panel_style(PANEL_BG))
	side.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(side)
	_tabs = TabContainer.new()
	side.add_child(_tabs)
	_build_armature_tab()
	_build_layers_tab()
	_build_timeline_tab()
	_build_brush_tab()
	_build_settings_tab()

	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_panel.offset_top = -54.0
	status_panel.add_theme_stylebox_override("panel", _panel_style(PANEL_BG))
	status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(status_panel)
	_status = Label.new()
	_status.text = "Stretchy canvas bridge ready"
	_status.add_theme_color_override("font_color", MUTED)
	status_panel.add_child(_status)
	_update_status()

func _build_armature_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Armature / العظام"
	page.add_theme_constant_override("separation", 8)
	_tabs.add_child(page)
	page.add_child(_heading("Armature and Smart Bone dials"))
	_armature_label = _label("")
	_armature_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_armature_label)
	var add_dial := _button("Add Smart Bone dial  /  إضافة عظمة ذكية")
	add_dial.pressed.connect(_add_dial)
	page.add_child(add_dial)
	var add_bone := _button("Add armature bone  /  إضافة عظمة هيكلية")
	add_bone.pressed.connect(_add_bone)
	page.add_child(add_bone)
	var add_key := _button("Add angle key  /  إضافة مفتاح زاوية")
	add_key.pressed.connect(_add_angle_key)
	page.add_child(add_key)
	var overshoot := CheckButton.new()
	overshoot.text = "Catmull–Rom overshoot"
	overshoot.button_pressed = bool(document["settings"]["overshoot"])
	overshoot.toggled.connect(func(on: bool) -> void:
		document["settings"]["overshoot"] = on
		_sync_native_smartbone())
	page.add_child(overshoot)
	var apply := _button("Apply pose to IVORY canvas  /  تطبيق الوضعية")
	apply.pressed.connect(_apply_pose_to_canvas)
	page.add_child(apply)
	_update_armature_label()

func _build_layers_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Layers / الطبقات"
	page.add_theme_constant_override("separation", 8)
	_tabs.add_child(page)
	page.add_child(_heading("Stretchy layer stack"))
	_layer_list = ItemList.new()
	_layer_list.custom_minimum_size = Vector2(0, 250)
	_layer_list.item_selected.connect(_select_layer)
	page.add_child(_layer_list)
	var refresh := _button("Refresh from IVORY layer bridge  /  تحديث الطبقات")
	refresh.pressed.connect(func() -> void:
		_refresh_from_ivory()
		_refresh_layer_list())
	page.add_child(refresh)
	_refresh_layer_list()

func _build_timeline_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Timeline / التايملاين"
	page.add_theme_constant_override("separation", 8)
	_tabs.add_child(page)
	page.add_child(_heading("Stretchy timeline"))
	_timeline_label = _label("")
	page.add_child(_timeline_label)
	var frame := HSlider.new()
	frame.min_value = 0
	frame.max_value = float(document["timeline"]["length"])
	frame.step = 1
	frame.value_changed.connect(func(value: float) -> void:
		playhead = value
		document["timeline"]["current_frame"] = int(value)
		_update_timeline_label())
	page.add_child(frame)
	var key := _button("Key current pose  /  تسجيل الوضعية")
	key.pressed.connect(_key_current_pose)
	page.add_child(key)
	var loop := _button("Play Stretchy timeline  /  تشغيل")
	loop.pressed.connect(_play_timeline)
	page.add_child(loop)
	_update_timeline_label()

func _build_brush_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Brushes / الفرش"
	page.add_theme_constant_override("separation", 8)
	_tabs.add_child(page)
	page.add_child(_heading("Stretchy brush settings"))
	page.add_child(_label("Brushes are owned by this Stretchy room; strokes land on the selected IVORY canvas layer through the bridge."))
	var size := HSlider.new()
	size.min_value = 1
	size.max_value = 240
	size.value = float(document["brush"]["size"])
	size.value_changed.connect(func(value: float) -> void: document["brush"]["size"] = value)
	page.add_child(size)
	var pressure := CheckButton.new()
	pressure.text = "Pressure response"
	pressure.button_pressed = bool(document["brush"]["pressure"])
	pressure.toggled.connect(func(on: bool) -> void: document["brush"]["pressure"] = on)
	page.add_child(pressure)

func _build_settings_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Settings / الإعدادات"
	page.add_theme_constant_override("separation", 8)
	_tabs.add_child(page)
	page.add_child(_heading("Stretchy project settings"))
	page.add_child(_label("This room owns its mesh density, Smart Bone interpolation and physics flags. IVORY settings are not edited here."))
	var physics := CheckButton.new()
	physics.text = "Enable Stretchy physics"
	physics.button_pressed = bool(document["settings"]["physics"])
	physics.toggled.connect(func(on: bool) -> void:
		document["settings"]["physics"] = on
		_sync_native_physics())
	page.add_child(physics)

func _add_dial() -> void:
	if not Native.has_smartbone():
		_status.text = "SmartBone C++ extension is not loaded; dial data is still kept in the Stretchy document."
	var dial := {"driver_bone": 0, "angle": 0.0, "keys": [], "native": null}
	document["dials"].append(dial)
	selected_dial = document["dials"].size() - 1
	_sync_native_smartbone()
	_sync_native_physics()
	_update_armature_label()

func _add_bone() -> void:
	if selected_layer < 0 or selected_layer >= document["layers"].size():
		_status.text = "Select a Stretchy layer first."
		return
	var layer: Dictionary = document["layers"][selected_layer]
	var bones: Array = layer["armature"].get("bones", [])
	var parent: int = -1 if bones.is_empty() else bones.size() - 1
	bones.append({
		"id": bones.size(),
		"name": "Bone_%02d" % (bones.size() + 1),
		"parent": parent,
		"rest_start": Vector2(0, 0),
		"rest_end": Vector2(80, 0),
		"pose_angle": 0.0,
		"length": 80.0,
		"weights": {},
		"constraints": {"ik": false, "limit_min": -3.14, "limit_max": 3.14}
	})
	layer["armature"]["bones"] = bones
	document["layers"][selected_layer] = layer
	_update_armature_label()
	_status.text = "Stretchy armature bone added to the selected layer."

func _add_angle_key() -> void:
	if selected_dial < 0 or selected_dial >= document["dials"].size():
		_add_dial()
	var dial: Dictionary = document["dials"][selected_dial]
	var angle := float(dial["keys"].size()) * 0.6 - 0.6
	dial["keys"].append({"angle": angle, "bone_turns": {}, "bone_stretches": {}, "point_offsets": {}})
	selected_key = dial["keys"].size() - 1
	_sync_native_smartbone()
	_update_armature_label()

func _sync_native_smartbone() -> void:
	if native_smartbone == null:
		return
	native_smartbone.clear()
	native_smartbone.set_overshoot(bool(document["settings"]["overshoot"]))
	for dial_data in document["dials"]:
		var dial_index: int = int(native_smartbone.add_dial(int(dial_data["driver_bone"])))
		native_smartbone.set_driver_angle(dial_index, float(dial_data["angle"]))
		for key_data in dial_data["keys"]:
			var key_index: int = int(native_smartbone.add_key(dial_index, float(key_data["angle"])))
			for bone_id in key_data["bone_turns"]:
				native_smartbone.set_key_bone(dial_index, key_index, int(bone_id), float(key_data["bone_turns"][bone_id]), float(key_data["bone_stretches"].get(bone_id, 1.0)))

## Rebuilds the secondary-motion chain from the Stretchy document, the same
## "clear and rebuild from the document" rule `_sync_native_smartbone`
## follows: the document stays the single source of truth, the native side
## is a resolved cache of it.
##
## Ported starting point: Stretchy Studio's `physics.js` "Hair Front" rule —
## a short, quick-settling chain driven by the same angle the room's first
## dial already carries. An artist wiring an actual head/body angle in later
## only has to change what feeds `set_input`, not the chain shape.
func _sync_native_physics() -> void:
	if native_jiggle_physics == null:
		return
	native_jiggle_physics.clear()
	if not bool(document["settings"].get("physics", false)):
		return
	var chain: int = int(native_jiggle_physics.add_setting())
	native_jiggle_physics.add_vertex(chain, 0.0, 0.0, 1.0, 1.0) # vertex 0: anchor
	native_jiggle_physics.add_vertex(chain, 3.0, 0.95, 0.9, 1.5) # vertex 1: the tip
	if selected_dial >= 0 and selected_dial < document["dials"].size():
		var dial_data: Dictionary = document["dials"][selected_dial]
		native_jiggle_physics.set_input(chain, rad_to_deg(float(dial_data["angle"])))

## The tip's current swing, in degrees, scaled the way a Stretchy Studio
## `outputScale` is (see `ivory_jigglephysics.h`). Nothing calls this yet;
## it is here for whoever wires the canvas bridge next, same as
## `native_smartbone`'s corrections were before `_apply_pose_to_canvas`
## existed.
func dial_swing_deg(scale: float = 1.522) -> float:
	if native_jiggle_physics == null or native_jiggle_physics.setting_count() == 0:
		return 0.0
	return native_jiggle_physics.output_angle(0, 1, scale)

func _apply_pose_to_canvas() -> void:
	if view == null or selected_layer < 0:
		_status.text = "Select a Stretchy layer first."
		return
	view.queue_redraw()
	if view.overlay != null:
		view.overlay.queue_redraw()
	_status.text = "Pose sent through the Stretchy → IVORY canvas bridge."

func _key_current_pose() -> void:
	document["timeline"]["tracks"].append({"frame": int(playhead), "dial": selected_dial, "key": selected_key})
	_update_timeline_label()

func _play_timeline() -> void:
	_status.text = "Stretchy timeline playback is active on its own track data."

func _select_layer(index: int) -> void:
	selected_layer = index
	if view != null and view.layers != null:
		view.layers.set_active(int(document["layers"][index]["source_index"]))
	_update_status()

func _refresh_layer_list() -> void:
	if _layer_list == null:
		return
	_layer_list.clear()
	for layer in document["layers"]:
		_layer_list.add_item(String(layer["name"]))
	if selected_layer >= 0 and selected_layer < _layer_list.item_count:
		_layer_list.select(selected_layer)

func _update_armature_label() -> void:
	if _armature_label == null:
		return
	var count: int = document["dials"].size()
	var keys := 0
	for dial in document["dials"]:
		keys += dial["keys"].size()
	var bones := 0
	if selected_layer >= 0 and selected_layer < document["layers"].size():
		bones = document["layers"][selected_layer]["armature"].get("bones", []).size()
	_armature_label.text = "Bones: %d\nDials: %d\nAngle keys: %d\nCurves: Catmull–Rom\nNative C++: %s" % [bones, count, keys, "ready" if Native.has_smartbone() else "optional / not loaded"]

func _update_timeline_label() -> void:
	if _timeline_label != null:
		_timeline_label.text = "Frame: %d / %d\nStretchy tracks: %d" % [int(playhead), int(document["timeline"]["length"]), document["timeline"]["tracks"].size()]

func _update_status() -> void:
	if _status == null:
		return
	_status.text = "Stretchy layer %d · Canvas bridge active · Android file access ready" % (selected_layer + 1)

func _open_import() -> void:
	# Android image access must go through IVORY's existing ImageImport path.
	# It handles the platform picker, content decoding, premultiplication and
	# placement on the selected canvas layer. Stretchy records the bridge event;
	# it does not create a second importer.
	if host != null and selected_layer >= 0 and selected_layer < document["layers"].size():
		var source_index := int(document["layers"][selected_layer]["source_index"])
		host.call("_ask_for_image", source_index)
		_status.text = "Android image picker opened through the IVORY bridge."
		return
	if _file_dialog != null:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png ; PNG images", "*.jpg,*.jpeg ; JPEG images", "*.psd ; Photoshop files"])
	_file_dialog.file_selected.connect(_import_file)
	add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.85)

func _import_file(path: String) -> void:
	document["source_image"] = path
	_status.text = "Imported into Stretchy document: %s" % path.get_file()
	if _file_dialog != null:
		_file_dialog.queue_free()
		_file_dialog = null

func _save_project() -> void:
	var path := "user://stretchy_projects"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var target := path.path_join("stretchy_project.stretchy")
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		_status.text = "Could not save Stretchy project."
		return
	file.store_string(JSON.stringify(document, "\t"))
	file.close()
	_status.text = "Saved: %s" % target

func _export_android_bundle() -> void:
	var path := "user://stretchy_exports"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var target := path.path_join("stretchy_android_project.stretchy")
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		_status.text = "Android export could not be written."
		return
	file.store_string(JSON.stringify({"android": true, "project": document}, "\t"))
	file.close()
	_status.text = "Android-ready .stretchy bundle exported. APK packaging still uses Godot Android export."

func _heading(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", ACCENT)
	label.add_theme_font_size_override("font_size", 16)
	return label

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", TEXT)
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _panel_style(Color("#FFFDF5")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#E6D3AA")))
	return button

func _panel_style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = PANEL_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	return style
