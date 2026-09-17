class_name StretchyStudioStandalone
extends Control
## Stretchy Studio, on its own.
##
## Nothing here reads or writes an Ivory layer, bone, or canvas. The room
## owns its own document, its own drawing surface, and its own touch
## handling — the only thing connecting it to Ivory at all is the compass
## icon that opens it. That was a deliberate change from the previous
## `StretchyStudioRoom`, which shared Ivory's `CanvasView` on purpose; this
## class exists because that sharing is no longer what's wanted. See
## `STAGE_170_STANDALONE_NOTES.md` for what that previous room still is and
## why it was left in place rather than deleted.
##
## What's real in this stage: multi-touch pan/zoom, mesh-point placement and
## dragging, manual triangle assignment, a simple bone chain with touch
## rotation, per-parameter sliders, layer import from the device's own file
## picker, and one working exporter (`.model3.json`) written to wherever is
## correct for this OS. What's declared but not yet wired: motion3, moc3,
## the full cmo3 XML, and can3 — each is its own multi-hundred-line writer
## in the reference and is staged for later rather than guessed at now.

signal closed

const BG := Color("#000000")
const PANEL_BG := Color("#25252F")
const PANEL_EDGE := Color("#3A3A48")
const TEXT := Color("#EDEDF2")
const MUTED := Color("#9A9AA8")
const ACCENT := Color("#7FB7E8")
const GRID_LINE := Color(1, 1, 1, 0.045)
const POINT_COLOR := Color("#F2C46D")
const POINT_SELECTED := Color("#F26D6D")
const BONE_COLOR := Color("#6DE0C0")

enum Tool { MESH, ARMATURE, LAYERS, PARAMETERS, EXPORT }

var host: Object = null
var project: ProjectManager.Project = null
var document: Dictionary = {}
var native_document: Object = null
var active_tool: int = Tool.MESH
var selected_layer: int = -1
var selected_bone: int = -1
var _pending_triangle: Array = [] # up to 3 point indices, mesh tool

var _canvas: _StretchyCanvas
var _tabs: TabContainer
var _layer_list: ItemList
var _bone_list: ItemList
var _param_box: VBoxContainer
var _status: Label
var _file_dialog: FileDialog
var _undo_stack: Array = []
var _redo_stack: Array = []
var _dirty: bool = false
var _save_clock: float = 0.0
const HISTORY_LIMIT: int = 80
const AUTOSAVE_SECONDS: float = 1.0

# --------------------------------------------------------------- lifecycle

func setup(owner_: Object, source_project: ProjectManager.Project = null) -> void:
	host = owner_
	project = source_project
	native_document = Native.stretchy_document()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	document = _new_document()
	if project != null and not project.stretchy_document.is_empty():
		document.merge(project.stretchy_document.duplicate(true), true)
	if native_document != null:
		native_document.set_document(document)
	_reload_layer_textures()
	# The project canvas is authoritative. Stretchy never invents a second
	# project size; its black stage and drawing surface follow this rectangle.
	if project != null:
		document["canvas_size"] = [project.page.x, project.page.y]
	_build_room()
	set_process(true)

func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_clock += delta
	if _save_clock >= AUTOSAVE_SECONDS:
		_save_clock = 0.0
		_save_to_project()

func _serializable_document() -> Dictionary:
	var saved: Dictionary = document.duplicate(true)
	var layers: Array = []
	for index in saved.get("layers", []).size():
		var layer: Dictionary = saved["layers"][index]
		var row: Dictionary = (layer as Dictionary).duplicate(true)
		row.erase("texture")
		if project != null and layer.get("texture") != null:
			var dir := "user://projects/p%d/stretchy" % project.id
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
			var image: Image = layer["texture"].get_image()
			var target := dir.path_join("layer_%03d.png" % index)
			if image != null and image.save_png(target) == OK:
				row["texture_path"] = target
		layers.append(row)
	saved["layers"] = layers
	return saved

func _snapshot() -> Dictionary:
	return _serializable_document()

func _begin_edit() -> void:
	_undo_stack.append(_snapshot())
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()

func _changed() -> void:
	_dirty = true
	_save_clock = 0.0
	if native_document != null:
		native_document.set_document(document)
		document = native_document.document()

func _save_to_project() -> void:
	if project == null:
		return
	commit_to_project()
	if host != null and host.has_method("mark_stretchy_dirty"):
		host.mark_stretchy_dirty(project)
	else:
		Vault.save(project)
	_dirty = false

func undo_document() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_snapshot())
	document = _undo_stack.pop_back()
	_reload_layer_textures()
	_refresh_layer_list()
	_refresh_bone_list()
	_changed()
	_canvas.queue_redraw()

func redo_document() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_snapshot())
	document = _redo_stack.pop_back()
	_reload_layer_textures()
	_refresh_layer_list()
	_refresh_bone_list()
	_changed()
	_canvas.queue_redraw()

## Commits only serializable Stretchy authoring state to the owning Animation
## project. Runtime ImageTexture objects stay in the room and never enter JSON.
func commit_to_project() -> void:
	if project == null:
		return
	project.stretchy_document = _serializable_document()

func _reload_layer_textures() -> void:
	for layer in document.get("layers", []):
		var path := String(layer.get("texture_path", ""))
		if path != "" and ResourceLoader.exists(path):
			var img := Image.new()
			if img.load(path) == OK:
				layer["texture"] = ImageTexture.create_from_image(img)

func _new_document() -> Dictionary:
	if native_document != null:
		return native_document.create_document()
	return {
		"format": "stretchy.standalone.v1",
		"model_name": "character",
		"layers": [],
		"armature": [],
		"parameters": [
			{"id": "ParamAngleX", "name": "Angle X", "min": -30.0, "max": 30.0, "value": 0.0},
			{"id": "ParamAngleY", "name": "Angle Y", "min": -30.0, "max": 30.0, "value": 0.0},
			{"id": "ParamMouthOpenY", "name": "Mouth open", "min": 0.0, "max": 1.0, "value": 0.0},
		],
		"canvas_size": [1920.0, 1080.0],
	}

# -------------------------------------------------------------------- room

func _build_room() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_canvas = _StretchyCanvas.new()
	_canvas.room = self
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 8)
	top.position = Vector2(12, 12)
	add_child(top)

	var title := Label.new()
	title.text = "Stretchy Studio"
	title.add_theme_color_override("font_color", TEXT)
	top.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(func() -> void:
		_save_to_project()
		closed.emit())
	top.add_child(close_btn)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.position = Vector2(12, 48)
	add_child(toolbar)
	_toolbar_button(toolbar, "Mesh", Tool.MESH)
	_toolbar_button(toolbar, "Armature", Tool.ARMATURE)
	_toolbar_button(toolbar, "Layers", Tool.LAYERS)
	_toolbar_button(toolbar, "Params", Tool.PARAMETERS)
	_toolbar_button(toolbar, "Export", Tool.EXPORT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.plate(PANEL_BG))
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-330, 88)
	panel.custom_minimum_size = Vector2(310, 460)
	add_child(panel)

	_tabs = TabContainer.new()
	_tabs.tab_focus_mode = Control.FOCUS_NONE
	_tabs.custom_minimum_size = Vector2(300, 420)
	panel.add_child(_tabs)

	_tabs.add_child(_build_mesh_tab())
	_tabs.add_child(_build_armature_tab())
	_tabs.add_child(_build_layers_tab())
	_tabs.add_child(_build_parameters_tab())
	_tabs.add_child(_build_export_tab())
	for i in range(_tabs.get_tab_count()):
		_tabs.set_tab_title(i, ["Mesh", "Bones", "Layers", "Params", "Export"][i])

	_status = Label.new()
	_status.add_theme_color_override("font_color", MUTED)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_status.position = Vector2(12, -28)
	_status.text = "Touch the canvas: tap to add a mesh point."
	add_child(_status)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	add_child(_file_dialog)

func _exit_tree() -> void:
	_save_to_project()
	if _file_dialog != null and is_instance_valid(_file_dialog):
		_file_dialog.queue_free()

func _toolbar_button(row: HBoxContainer, label_text: String, tool: int) -> void:
	var b := UiKit.make_text_button(label_text)
	b.pressed.connect(func() -> void:
		active_tool = tool
		_pending_triangle.clear()
		_tabs.current_tab = tool
		_canvas.queue_redraw())
	row.add_child(b)

# ------------------------------------------------------------------ mesh tab

func _build_mesh_tab() -> Control:
	var v := VBoxContainer.new()
	var hint := Label.new()
	hint.text = "Tap empty canvas: add a point.\nTap 3 points in a row: form a triangle.\nDrag a point: move it."
	hint.add_theme_color_override("font_color", MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(hint)
	var clear_btn := UiKit.make_text_button("Clear this layer's mesh")
	clear_btn.pressed.connect(func() -> void:
		if selected_layer >= 0:
			_begin_edit()
			document["layers"][selected_layer]["points"] = []
			document["layers"][selected_layer]["triangles"] = []
			_changed()
			_canvas.queue_redraw())
	v.add_child(clear_btn)
	return v

# -------------------------------------------------------------- armature tab

func _build_armature_tab() -> Control:
	var v := VBoxContainer.new()
	var hint := Label.new()
	hint.text = "Drag on empty canvas: draw a new bone (root to tip).\nDrag an existing tip: rotate that bone."
	hint.add_theme_color_override("font_color", MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(hint)
	_bone_list = ItemList.new()
	_bone_list.custom_minimum_size = Vector2(280, 220)
	_bone_list.item_selected.connect(func(i: int) -> void:
		selected_bone = i
		_canvas.queue_redraw())
	v.add_child(_bone_list)
	return v

func _refresh_bone_list() -> void:
	if _bone_list == null:
		return
	_bone_list.clear()
	for b in document["armature"]:
		_bone_list.add_item("%s (%.0f°)" % [b["name"], rad_to_deg(b["angle"])])

# ---------------------------------------------------------------- layers tab

func _build_layers_tab() -> Control:
	var v := VBoxContainer.new()
	_layer_list = ItemList.new()
	_layer_list.custom_minimum_size = Vector2(280, 300)
	_layer_list.item_selected.connect(func(i: int) -> void:
		selected_layer = i
		_canvas.queue_redraw())
	v.add_child(_layer_list)
	var add_btn := UiKit.make_text_button("Import image from device...")
	add_btn.pressed.connect(_pick_layer_image)
	v.add_child(add_btn)
	return v

func _pick_layer_image() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.png ; PNG images", "*.jpg,*.jpeg ; JPEG images"])
	for c in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(c["callable"])
	_file_dialog.file_selected.connect(_on_layer_image_chosen)
	_file_dialog.popup_centered_ratio(0.8)

func _on_layer_image_chosen(path: String) -> void:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		_status.text = "Couldn't load %s (%s)." % [path, error_string(err)]
		return
	var tex := ImageTexture.create_from_image(img)
	_begin_edit()
	document["layers"].append({
		"id": document["layers"].size(),
		"name": path.get_file(),
		"visible": true,
		"texture_path": path,
		"texture": tex,
		"points": [],
		"triangles": [],
	})
	_changed()
	selected_layer = document["layers"].size() - 1
	_refresh_layer_list()
	_canvas.queue_redraw()

func _refresh_layer_list() -> void:
	if _layer_list == null:
		return
	_layer_list.clear()
	for l in document["layers"]:
		_layer_list.add_item(l["name"])

# ------------------------------------------------------------ parameters tab

func _build_parameters_tab() -> Control:
	_param_box = VBoxContainer.new()
	for i in range(document["parameters"].size()):
		var p: Dictionary = document["parameters"][i]
		var step: float = 0.1 if p["max"] - p["min"] <= 2.0 else 1.0
		UiKit.slider_row(_param_box, p["name"], p["min"], p["max"], p["value"], step, "",
			func(v: float) -> void:
				document["parameters"][i]["value"] = v
				_changed()
				_canvas.queue_redraw())
	return _param_box

# ---------------------------------------------------------------- export tab

func _build_export_tab() -> Control:
	var v := VBoxContainer.new()
	var hint := Label.new()
	hint.text = "Stretchy JSON export plus IVORY animation exports for the current Animation project."
	hint.add_theme_color_override("font_color", MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(hint)
	var export_btn := UiKit.make_text_button("Export model3.json")
	export_btn.pressed.connect(_export_model3)
	v.add_child(export_btn)
	v.add_child(HSeparator.new())
	var ivory_title := Label.new()
	ivory_title.text = "IVORY animation export"
	ivory_title.add_theme_color_override("font_color", ACCENT)
	v.add_child(ivory_title)
	var ivory_note := Label.new()
	ivory_note.text = "Uses IVORY's existing timeline/export pipeline. It exports the active Animation project."
	ivory_note.add_theme_color_override("font_color", MUTED)
	ivory_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(ivory_note)
	var exports := [
		["mp4", "MP4 / H.264"],
		["mp4_small", "MP4 1280px"],
		["gif", "GIF"],
		["gif_small", "GIF 800px"],
		["webp_anim", "Animated WebP"],
		["webp_anim_small", "Animated WebP 960px"],
		["sequence", "PNG frame sequence"],
		["sheet", "Sprite sheet"],
	]
	for item in exports:
		var button := UiKit.make_text_button(String(item[1]), true)
		button.custom_minimum_size = Vector2(0.0, UiKit.s(44.0))
		var kind := String(item[0])
		button.pressed.connect(_export_ivory.bind(kind))
		v.add_child(button)
	var cancel := UiKit.make_text_button("Cancel current export", true)
	cancel.pressed.connect(func() -> void:
		if host != null and host.has_method("cancel_export"):
			host.cancel_export()
		_status.text = "IVORY export cancelled.")
	v.add_child(cancel)
	return v

func _export_ivory(kind: String) -> void:
	_save_to_project()
	if host == null or not host.has_method("run_export"):
		_status.text = "IVORY export bridge is unavailable."
		return
	host.run_export(kind)
	_status.text = "IVORY export started: %s" % kind

func _export_model3() -> void:
	var native_export := Native.stretchy_export()
	if native_export != null:
		var target_name := String(document["model_name"])
		var plan_export: Dictionary = native_export.target_plan()
		if plan_export["needs_dialog"]:
			_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
			_file_dialog.current_dir = String(plan_export["default_dir"])
			for c in _file_dialog.file_selected.get_connections():
				_file_dialog.file_selected.disconnect(c["callable"])
			_file_dialog.file_selected.connect(func(path: String) -> void:
				var result: Dictionary = native_export.export_json_bundle(document, path)
				_report_export(result))
			_file_dialog.popup_centered_ratio(0.8)
			return
		var result_native: Dictionary = native_export.export_json_bundle(document, String(plan_export["default_dir"]).path_join(target_name))
		_report_export(result_native)
		return

	var texture_files: Array = []
	for l in document["layers"]:
		texture_files.append(String(l["name"]).get_basename() + ".png")

	var json_text: String = StretchyModel3.to_json({
		"model_name": document["model_name"],
		"texture_files": texture_files,
	})
	var filename: String = "%s.model3.json" % document["model_name"]
	var plan_export_file: Dictionary = StretchyExportTarget.plan()
	if plan_export_file["needs_dialog"]:
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.filters = PackedStringArray(["*.json ; model3.json"])
		_file_dialog.current_dir = String(plan_export_file["default_dir"])
		_file_dialog.current_file = filename
		for c in _file_dialog.file_selected.get_connections():
			_file_dialog.file_selected.disconnect(c["callable"])
		_file_dialog.file_selected.connect(func(path: String) -> void:
			var result_file: Dictionary = StretchyExportTarget.write_text(path.get_base_dir(), path.get_file(), json_text)
			_report_export(result_file))
		_file_dialog.popup_centered_ratio(0.8)
	else:
		var result_file: Dictionary = StretchyExportTarget.smart_save_text(filename, json_text)
		_report_export(result_file)

func _report_export(result: Dictionary) -> void:
	if result.get("ok", false):
		_status.text = "Saved to %s" % result["path"]
	else:
		_status.text = "Export failed: %s" % result.get("error", "unknown error")

# ---------------------------------------------------------------- inner: canvas

## The room's own drawing surface — no `CanvasView`, no Ivory layer stack.
## Owns pan/zoom and forwards every touch/mouse event to whichever tool is
## active on the outer room.
class _StretchyCanvas:
	extends Control

	var room: StretchyStudioStandalone
	var pan: Vector2 = Vector2.ZERO
	var zoom: float = 1.0
	var _drag_point: int = -1
	var _bone_drag_start: Vector2 = Vector2.ZERO
	var _bone_dragging: int = -1 # index of bone being rotated, or -1
	var _touches: Dictionary = {} # index -> Vector2, for pinch/pan
	var _pinch_start_dist: float = 0.0
	var _pinch_start_zoom: float = 1.0
	var _primary_started: bool = false
	var _peak_fingers: int = 0
	var _gesture_moved: bool = false
	var _tap_started_ms: int = 0

	func _ready() -> void:
		# The canvas must receive every screen touch and drag. Overlay panels sit
		# above it and consume their own controls; ignoring input here would make
		# the professional canvas appear dead on touch devices.
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _to_world(local: Vector2) -> Vector2:
		return (local - size * 0.5 - pan) / zoom

	func _to_local(world: Vector2) -> Vector2:
		return world * zoom + size * 0.5 + pan

	func _draw() -> void:
		var step := 40.0 * zoom
		if step > 4.0:
			var origin := _to_local(Vector2.ZERO)
			var x := fmod(origin.x, step)
			while x < size.x:
				draw_line(Vector2(x, 0), Vector2(x, size.y), StretchyStudioStandalone.GRID_LINE)
				x += step
			var y := fmod(origin.y, step)
			while y < size.y:
				draw_line(Vector2(0, y), Vector2(size.x, y), StretchyStudioStandalone.GRID_LINE)
				y += step

		if room.selected_layer >= 0 and room.selected_layer < room.document["layers"].size():
			var l: Dictionary = room.document["layers"][room.selected_layer]
			if l.get("visible", true) and l.get("texture") != null:
				var tex: Texture2D = l["texture"]
				var tsize := Vector2(tex.get_width(), tex.get_height()) * zoom
				draw_texture_rect(tex, Rect2(_to_local(-tsize * 0.5 / zoom), tsize), false)

			for tri in l["triangles"]:
				var a: Vector2 = _to_local(Vector2(l["points"][tri[0]][0], l["points"][tri[0]][1]))
				var b: Vector2 = _to_local(Vector2(l["points"][tri[1]][0], l["points"][tri[1]][1]))
				var c: Vector2 = _to_local(Vector2(l["points"][tri[2]][0], l["points"][tri[2]][1]))
				draw_line(a, b, StretchyStudioStandalone.ACCENT, 1.5)
				draw_line(b, c, StretchyStudioStandalone.ACCENT, 1.5)
				draw_line(c, a, StretchyStudioStandalone.ACCENT, 1.5)

			for i in range(l["points"].size()):
				var p: Vector2 = _to_local(Vector2(l["points"][i][0], l["points"][i][1]))
				var picked := room._pending_triangle.has(i)
				draw_circle(p, 6.0, StretchyStudioStandalone.POINT_SELECTED if picked else StretchyStudioStandalone.POINT_COLOR)

		for i in range(room.document["armature"].size()):
			var bone: Dictionary = room.document["armature"][i]
			var root: Vector2 = _to_local(Vector2(float(bone["x"]), float(bone["y"])))
			var angle: float = float(bone["angle"])
			var bone_length: float = float(bone["length"])
			var tip: Vector2 = root + Vector2.RIGHT.rotated(angle) * bone_length * zoom
			var w: float = 3.0 if i == room.selected_bone else 1.5
			draw_line(root, tip, StretchyStudioStandalone.BONE_COLOR, w)
			draw_circle(root, 5.0, StretchyStudioStandalone.BONE_COLOR)
			draw_circle(tip, 4.0, StretchyStudioStandalone.BONE_COLOR.lightened(0.3))

	# ------------------------------------------------------------- input

	func _gui_input(event: InputEvent) -> void:
		# Stretchy Studio interaction is touch-first and touch-only.
		# Mouse button/motion events are deliberately not used.
		if event is InputEventMagnifyGesture:
			zoom = clampf(zoom * event.factor, 0.1, 8.0)
			queue_redraw()
			return
		if event is InputEventPanGesture:
			pan -= event.delta
			queue_redraw()
			return
		if event is InputEventScreenTouch:
			_handle_touch(event)
		elif event is InputEventScreenDrag:
			_handle_screen_drag(event)

	func _handle_touch(event: InputEventScreenTouch) -> void:
		if event.pressed:
			_touches[event.index] = event.position
			_peak_fingers = maxi(_peak_fingers, _touches.size())
			if _touches.size() == 1:
				_primary_started = false
				_gesture_moved = false
				_tap_started_ms = Time.get_ticks_msec()
			elif _touches.size() == 2:
				# A second finger cancels the pending one-finger action. No point or
				# bone is created before we know this is not a multi-touch tap.
				_primary_started = false
				var pts := _touches.values()
				_pinch_start_dist = max(1.0, (pts[0] - pts[1]).length())
				_pinch_start_zoom = zoom
		else:
			if _touches.size() == 1:
				if not _primary_started and not _gesture_moved \
						and Time.get_ticks_msec() - _tap_started_ms <= 350 \
						and _peak_fingers == 1:
					_begin_primary(event.position)
				_end_primary(event.position)
			_touches.erase(event.index)
			if _touches.is_empty():
				if not _gesture_moved and _peak_fingers == 2:
					room.undo_document()
				elif not _gesture_moved and _peak_fingers >= 3:
					room.redo_document()
				_peak_fingers = 0
				_primary_started = false

	func _handle_screen_drag(event: InputEventScreenDrag) -> void:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var pts := _touches.values()
			var dist: float = max(1.0, (pts[0] - pts[1]).length())
			zoom = clampf(_pinch_start_zoom * (dist / _pinch_start_dist), 0.1, 8.0)
			pan += event.relative * 0.5
			queue_redraw()
		elif _touches.size() == 1:
			if not _primary_started:
				_begin_primary(event.position)
				_primary_started = true
			_gesture_moved = true
			_drag_primary(event.position)

		## Shared by single-touch gestures: hit-test a point or a bone
		## tip, or start drawing a new bone, depending on the active tool.

	func _begin_primary(pos: Vector2) -> void:
		room._begin_edit()
		var world := _to_world(pos)
		match room.active_tool:
			StretchyStudioStandalone.Tool.MESH:
				if room.selected_layer < 0:
					room._status.text = "Pick a layer first."
					return
				var l: Dictionary = room.document["layers"][room.selected_layer]
				var hit := _hit_point(l, world)
				if hit >= 0:
					_drag_point = hit
				else:
					l["points"].append([world.x, world.y])
					var idx: int = l["points"].size() - 1
					room._pending_triangle.append(idx)
					if room._pending_triangle.size() == 3:
						l["triangles"].append(room._pending_triangle.duplicate())
						room._pending_triangle.clear()
					queue_redraw()
			StretchyStudioStandalone.Tool.ARMATURE:
				var hit_bone := _hit_bone_tip(world)
				if hit_bone >= 0:
					_bone_dragging = hit_bone
					room.selected_bone = hit_bone
				else:
					_bone_drag_start = world
					_bone_dragging = -2 # sentinel: drawing a brand new bone
			_:
				pass

	func _drag_primary(pos: Vector2) -> void:
		var world := _to_world(pos)
		if room.active_tool == StretchyStudioStandalone.Tool.MESH and _drag_point >= 0 and room.selected_layer >= 0:
			room.document["layers"][room.selected_layer]["points"][_drag_point] = [world.x, world.y]
			room._changed()
			queue_redraw()
		elif room.active_tool == StretchyStudioStandalone.Tool.ARMATURE and _bone_dragging >= 0:
			var bone: Dictionary = room.document["armature"][_bone_dragging]
			var root := Vector2(bone["x"], bone["y"])
			bone["angle"] = (world - root).angle()
			bone["length"] = max(4.0, (world - root).length())
			room._refresh_bone_list()
			queue_redraw()

	func _end_primary(pos: Vector2) -> void:
		var world := _to_world(pos)
		if room.active_tool == StretchyStudioStandalone.Tool.ARMATURE and _bone_dragging == -2:
			var length: float = maxf(8.0, (world - _bone_drag_start).length())
			room.document["armature"].append({
				"id": room.document["armature"].size(),
				"name": "Bone %d" % (room.document["armature"].size() + 1),
				"x": _bone_drag_start.x,
				"y": _bone_drag_start.y,
				"length": length,
				"angle": (world - _bone_drag_start).angle(),
			})
			room.selected_bone = room.document["armature"].size() - 1
			room._refresh_bone_list()
			room._changed()
		_drag_point = -1
		_bone_dragging = -1
		queue_redraw()

	func _hit_point(layer: Dictionary, world: Vector2, radius: float = 10.0) -> int:
		var r := radius / zoom
		for i in range(layer["points"].size()):
			var p := Vector2(layer["points"][i][0], layer["points"][i][1])
			if p.distance_to(world) <= r:
				return i
		return -1

	func _hit_bone_tip(world: Vector2, radius: float = 12.0) -> int:
		var r := radius / zoom
		for i in range(room.document["armature"].size()):
			var bone: Dictionary = room.document["armature"][i]
			var root: Vector2 = Vector2(float(bone["x"]), float(bone["y"]))
			var tip: Vector2 = root + Vector2.RIGHT.rotated(float(bone["angle"])) * float(bone["length"])
			if tip.distance_to(world) <= r:
				return i
		return -1
