class_name LayersPanel
extends PanelContainer
## The layer stack, laid out the way drawing apps have settled on: topmost
## layer at the top, a picture of what each one holds, one tap to select.
##
## All touch in the list is handled here, in one place, as a single state
## machine with three outcomes:
##
##   short tap                -> select, or open settings if already selected
##   drag without holding     -> scroll the list
##   hold, then drag          -> pick the layer up and drop it somewhere else
##
## Doing it in one handler rather than per-row is what keeps the three from
## fighting: a nested scroll container and a drag-to-reorder row would each
## claim the same finger, and whichever won would feel broken.

signal solo_requested(index: int)
## The bones are to come off this layer.
##
## A signal rather than the panel doing it, because taking a skeleton off
## touches the pose track, the frame lock and whatever the player is currently
## showing — none of which is this panel's business to know about.
signal rig_removal_requested(index: int)
signal import_requested(index: int)
## A skeleton is to be laid on this layer, and taken off again.
##
## The layer opens by itself in the bone room, the bones go on, and Accept
## merges them into the drawing. Reached from a layer rather than from a room,
## because a skeleton is a fact about *this drawing* in *this drawing's*
## coordinates and is useless anywhere else.
signal bones_requested(index: int)
signal bones_removed(index: int)
signal puppet_requested(index: int)
signal animation_layer_requested(group_id: int)
signal text_edit_requested(index: int)
## The AI asked to improve what is drawn on a layer. See `ai_bridge.gd`.
signal improve_requested(index: int)

## Raised here rather than from `layer_rig_row.gd`, which builds the buttons:
## a signal belongs to the class that declares it, and one only ever emitted
## from elsewhere cannot be found by reading this file. Godot warns about it.
func ask_for_bones(index: int) -> void:
	bones_requested.emit(index)

func ask_to_remove_bones(index: int) -> void:
	bones_removed.emit(index)

func ask_for_animation_layer(gid: int) -> void:
	animation_layer_requested.emit(gid)

const ICON: String = "res://assets/icons/%s.png"
const ROW_H: float = 62.0
const GROUP_H: float = 42.0
const THUMB: float = 46.0
const LIST_MAX: float = 430.0
const HOLD_MS: int = 300
const MOVE_SLOP: float = 12.0

enum Mode { IDLE, WAITING, SCROLL, DRAG }

var view: CanvasView = null
var stack: LayerStack = null

var _body: VBoxContainer = null
var _clip: Control = null
var _host: VBoxContainer = null
var _settings: VBoxContainer = null
var _settings_scroll: TouchScroll = null
var _paint: Control = null

var _rows: Array = []              # {node, kind, index/gid}
var _slots: Array = []             # {y, index, group}
var _fold_btn: Button = null
var _add_btn: Button = null
var _undo_btn: Button = null
var _redo_btn: Button = null
var _settings_for: int = -1        # layer index
var _settings_group: int = -1      # group id
var _scroll: float = 0.0
var _content_h: float = 0.0

# --- gesture state ---
var _mode: int = Mode.IDLE
var _press_at: Vector2 = Vector2.ZERO
var _press_ms: int = 0
var _press_row: int = -1
var _pointer: Vector2 = Vector2.ZERO
var _drag_layer: int = -1
var _drag_slot: int = -1
var _scroll_from: float = 0.0

func setup(canvas: CanvasView) -> void:
	view = canvas
	stack = canvas.layers
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size = Vector2(UiKit.s(300.0), 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	_build_header()

	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.custom_minimum_size = Vector2(0.0, UiKit.s(160.0))
	_clip.resized.connect(_sync_host)
	_body.add_child(_clip)

	_host = VBoxContainer.new()
	_host.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_host)

	# The settings column scrolls: a layer with a merge, a solo view
	# and half a dozen notes is taller than a phone, and losing the last
	# button off the bottom is the same as not having it.
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	_settings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_scroll = UiKit.scroller(_settings, UiKit.s(400.0))
	_settings_scroll.visible = false
	_body.add_child(_settings_scroll)

	# Drop indicator and drag ghost live above everything else.
	_paint = Control.new()
	_paint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint.draw.connect(_draw_overlay)
	add_child(_paint)

	# Both of these fire when a layer is added, and both used to rebuild the
	# whole panel — so a single tap on `+` built every row twice, threw one
	# set away, and only then drew. They are coalesced into one rebuild at
	# the end of the frame instead: the panel is rebuilt once however many
	# things changed, which is also the right answer for a drag that moves a
	# layer between folders and fires several.
	stack.changed.connect(_ask_rebuild)
	stack.active_changed.connect(func(_i: int) -> void: _ask_rebuild())
	view.history_changed.connect(_sync_history)
	_rebuild()
	_sync_history()

## Opens the settings for whatever is selected.
func open_settings_for_active() -> void:
	_settings_group = -1
	_settings_for = stack.active_index
	_rebuild()

## Runs only while a finger is down and the long-press has not resolved yet.
##
## This panel used to be in the engine's process list for the whole life of
## the app, waking every frame to compare two numbers that are equal except
## during the third of a second after a press. The panel now switches itself
## on when a press begins and off the moment it is answered, so a tablet
## sitting still is running one less node per frame — and, more to the point,
## so does every other panel that follows this pattern.
func _process(_dt: float) -> void:
	if _mode != Mode.WAITING:
		set_process(false)
		return
	if Time.get_ticks_msec() - _press_ms >= HOLD_MS:
		set_process(false)
		_start_drag()

# ------------------------------------------------------------------ header

func _build_header() -> void:
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	_body.add_child(head)

	var title: Label = UiKit.make_label(UiKit.label_for("Layers", "الطبقات"), 15.0, UiKit.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	# Only ever acts on a layer: a folder cannot be put inside a folder.
	_fold_btn = _icon_button("add_file",
		UiKit.label_for("Put this layer in a folder", "ضع هذه الطبقة في مجلد"))
	_fold_btn.pressed.connect(func() -> void:
		if stack.active_group != 0:
			return
		stack.group_layer(stack.active_index)
		_close_settings())
	head.add_child(_fold_btn)

	# One add button, and only one.
	#
	# There used to be a second `+` beside it that made a bone layer. Two
	# identical plus signs a few pixels apart, one of which quietly created a
	# layer nobody can draw on — it is gone. The button below now reads where
	# the selection is standing and decides for itself:
	#
	#   inside a Character 360 file  -> a Character 360 sub-layer, already
	#                                   bound to that file's motion bones;
	#   anywhere else                -> an ordinary drawing layer.
	#
	# Bone layers are no longer something a finger can create by accident.
	# The Character 360 builder makes exactly one, for the file it builds,
	# and that is the only way one comes into existence.
	_add_btn = _icon_button("add_layer",
		UiKit.label_for("New layer", "طبقة جديدة"))
	_add_btn.pressed.connect(func() -> void:
		stack.add_layer_here()
		_refresh_add_hint()
		_close_settings())
	head.add_child(_add_btn)

	var trash: Button = _icon_button("delete_layer",
		UiKit.label_for("Delete layer", "حذف الطبقة"))
	trash.pressed.connect(func() -> void:
		# Taken out of the scene from here on if it has a past worth keeping,
		# and deleted outright if it has not.
		#
		# Deleting used to reach backwards through the whole scene: a layer
		# added for one shot and no longer wanted could not be got rid of
		# without also emptying it out of the forty frames it had already
		# been in. Now the frames before this one are left exactly as they
		# were, and a layer with nothing behind it still simply goes.
		if not stack.retire_layer(stack.active_index, stack.shown_frame):
			stack.remove_layer(stack.active_index)
		_close_settings())
	head.add_child(trash)

	# Right here rather than only on the canvas: the moment a layer is
	# deleted by mistake is the moment the finger is already in this panel,
	# and asking it to travel to the drawing to take that back is the worst
	# time to ask.
	var undo_row: HBoxContainer = HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	_body.add_child(undo_row)

	_undo_btn = UiKit.make_text_button(UiKit.label_for("Undo", "تراجع"), true)
	_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_btn.pressed.connect(func() -> void: view.undo())
	undo_row.add_child(_undo_btn)

	_redo_btn = UiKit.make_text_button(UiKit.label_for("Redo", "إعادة"), true)
	_redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_redo_btn.pressed.connect(func() -> void: view.redo())
	undo_row.add_child(_redo_btn)

func _icon_button(icon_name: String, tip: String) -> Button:
	var b: Button = Button.new()
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(UiKit.s(44.0), UiKit.s(44.0))
	var path: String = ICON % icon_name
	if ResourceLoader.exists(path):
		b.icon = load(path)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", int(UiKit.s(22.0)))
	b.add_theme_color_override("icon_normal_color", UiKit.ON_RAIL)
	b.add_theme_color_override("icon_hover_color", Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", Color("#1b1c22"))

	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = UiKit.CHIP
	n.border_color = UiKit.PANEL_EDGE
	n.set_border_width_all(1)
	n.set_corner_radius_all(int(UiKit.s(10.0)))
	var h: StyleBoxFlat = n.duplicate() as StyleBoxFlat
	h.bg_color = UiKit.CHIP_HOVER
	var p: StyleBoxFlat = n.duplicate() as StyleBoxFlat
	p.bg_color = UiKit.ACCENT

	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", n)
	return b

# -------------------------------------------------------------------- list

## Asks for one rebuild, however many times it is asked.
##
## Deferred rather than timed: `call_deferred` runs at the end of the current
## frame, so the panel is never a frame behind what it is showing — it simply
## stops being built more than once for the same frame.
var _rebuild_asked: bool = false

func _ask_rebuild() -> void:
	if _rebuild_asked:
		return
	_rebuild_asked = true
	call_deferred("_do_rebuild")

func _do_rebuild() -> void:
	_rebuild_asked = false
	if is_instance_valid(self):
		_rebuild()

func refresh_thumbs() -> void:
	# Never mid-gesture, and never while a settings page holds a live slider.
	if _mode != Mode.IDLE or _settings_for >= 0 or _settings_group >= 0:
		return
	stack.refresh_all_thumbs(int(THUMB * 2.0))
	_rebuild()

func _close_settings() -> void:
	_settings_for = -1
	_settings_group = -1
	_rebuild()

func _rebuild() -> void:
	if _host == null:
		return
	for c in _host.get_children():
		_host.remove_child(c)
		c.queue_free()
	for c in _settings.get_children():
		_settings.remove_child(c)
		c.queue_free()
	_rows.clear()

	if _settings_group >= 0:
		_clip.visible = false
		_settings_scroll.visible = true
		_build_group_settings(_settings_group)
		return
	if _settings_for >= 0 and _settings_for < stack.layers.size():
		_clip.visible = false
		_settings_scroll.visible = true
		_build_layer_settings(_settings_for)
		return

	_clip.visible = true
	_settings_scroll.visible = false
	_sync_fold_button()
	_refresh_add_hint()

	var gap: float = UiKit.s(5.0)
	_content_h = 0.0
	for entry in stack.display_rows():
		var node: Control = null
		if String(entry["kind"]) == "group":
			node = _group_row(int(entry["gid"]))
			_content_h += UiKit.s(GROUP_H) + gap
		else:
			node = _layer_row(int(entry["index"]))
			_content_h += UiKit.s(ROW_H) + gap
		_host.add_child(node)
		var rec: Dictionary = entry.duplicate()
		rec["node"] = node
		_rows.append(rec)

	_content_h = maxf(_content_h - gap, 0.0)
	_clip.custom_minimum_size = Vector2(0.0, minf(_content_h, UiKit.s(LIST_MAX)))
	_sync_host()
	if _paint != null:
		_paint.queue_redraw()

## A plain Control does not lay out its children, so the list gets its width
## and height set by hand whenever either could have changed.
func _sync_host() -> void:
	if _host == null or _clip == null:
		return
	_host.size = Vector2(_clip.size.x, _content_h)
	_scroll = clampf(_scroll, 0.0, maxf(_content_h - _clip.size.y, 0.0))
	_host.position = Vector2(0.0, -_scroll)

## Greyed out when a folder is what is selected, so it is clear the button
## acts on layers rather than quietly doing nothing.
## A small sheet of choices over the panel, each with a line saying what it
## is for — because a name alone rarely tells anyone which one they want.
func _open_sheet(title: String, rows: Array) -> void:
	var shade: Control = Control.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent) -> void:
		var down: bool = false
		if e is InputEventScreenTouch:
			down = (e as InputEventScreenTouch).pressed
		elif e is InputEventMouseButton:
			down = (e as InputEventMouseButton).pressed
		if down:
			shade.queue_free())
	add_child(shade)

	var sheet: PanelContainer = PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UiKit.panel_style())
	sheet.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sheet.custom_minimum_size = Vector2(clampf(get_viewport_rect().size.x * 0.78, UiKit.s(320.0), UiKit.s(520.0)), 0.0)
	shade.add_child(sheet)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	sheet.add_child(outer)
	var head: Label = UiKit.make_label(title, 16.0, UiKit.TEXT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(head)

	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	var scroller: Control = UiKit.scroller(v, UiKit.s(420.0))
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroller)

	for row in rows:
		var box: VBoxContainer = VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		var b: Button = UiKit.make_text_button(String(row[0]), true)
		b.custom_minimum_size = Vector2(0.0, UiKit.s(46.0))
		var action: Callable = row[2]
		b.pressed.connect(func() -> void:
			shade.queue_free()
			action.call())
		box.add_child(b)
		var hint: Label = UiKit.make_label(String(row[1]), 10.0, UiKit.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)
		v.add_child(box)

func _sync_history() -> void:
	if _undo_btn != null:
		_undo_btn.disabled = not view.can_undo()
	if _redo_btn != null:
		_redo_btn.disabled = not view.can_redo()

## Keeps the single add button honest about what it is going to make.
##
## The tooltip is the only thing that changes; the button never disappears and
## never disables. A control that vanishes when the selection moves is a
## control the user stops trusting, and adding a layer is always allowed.
func _refresh_add_hint() -> void:
	if _add_btn == null:
		return
	if stack.in_character360_file(stack.active_index):
		_add_btn.tooltip_text = UiKit.label_for(
			"New Character 360 layer (moved by this file's bones)",
			"طبقة جديدة داخل ملف Character 360 (تحركها عظام الملف)")
	else:
		_add_btn.tooltip_text = UiKit.label_for("New layer", "طبقة جديدة")

func _sync_fold_button() -> void:
	if _fold_btn == null:
		return
	var ok: bool = stack.active_group == 0
	if ok and stack.active_index < stack.layers.size():
		var l: LayerStack.Layer = stack.layers[stack.active_index]
		ok = not l.is_background and l.group_id == 0
	_fold_btn.disabled = not ok

func _layer_row(index: int) -> Control:
	var l: LayerStack.Layer = stack.layers[index]
	var selected: bool = index == stack.active_index
	var indented: bool = l.group_id != 0

	var outer: MarginContainer = MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if indented:
		outer.add_theme_constant_override("margin_left", int(UiKit.s(16.0)))

	var row: PanelContainer = PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0.0, UiKit.s(ROW_H))
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color("#31363f") if selected else Color("#262a33")
	sb.set_corner_radius_all(int(UiKit.s(10.0)))
	sb.set_content_margin_all(UiKit.s(6.0))
	if selected:
		sb.border_color = UiKit.ACCENT
		sb.border_width_left = int(UiKit.s(3.0))
	if index == _drag_layer and _mode == Mode.DRAG:
		sb.bg_color = Color("#3a3f4a")
	row.add_theme_stylebox_override("panel", sb)
	outer.add_child(row)

	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	row.add_child(line)

	line.add_child(_thumb_box(l.thumb))

	var name_box: VBoxContainer = VBoxContainer.new()
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(name_box)

	var title: String = l.title
	if l.is_bone_layer:
		title = "🦴 " + UiKit.label_for("Bone Motion", "عظام — حركة فقط")
	if l.is_background:
		title = UiKit.label_for("Background", "الخلفية")
	name_box.add_child(UiKit.make_label(title, 13.0, UiKit.TEXT))

	var note: String = "%d%%" % int(round(l.opacity * 100.0))
	if l.locked:
		note += "  " + UiKit.label_for("locked", "مقفلة")
	if selected:
		note += "  ·  " + UiKit.label_for("tap again", "اضغط ثانية")
	name_box.add_child(UiKit.make_label(note, 10.0, UiKit.TEXT_DIM))

	var eye: Button = _icon_button("hide_layer",
		UiKit.label_for("Show or hide", "إظهار أو إخفاء"))
	eye.custom_minimum_size = Vector2(UiKit.s(40.0), UiKit.s(40.0))
	eye.modulate = Color(1.0, 1.0, 1.0, 1.0 if l.visible else 0.40)
	eye.pressed.connect(func() -> void:
		if index < stack.layers.size():
			stack.set_visible_at(index, not stack.layers[index].visible))
	line.add_child(eye)
	return outer

func _group_row(gid: int) -> Control:
	var g: LayerStack.Group = stack.group_by_id(gid)
	var row: PanelContainer = PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0.0, UiKit.s(GROUP_H))
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color("#2e333d")
	sb.set_corner_radius_all(int(UiKit.s(10.0)))
	sb.set_content_margin_all(UiKit.s(6.0))
	row.add_theme_stylebox_override("panel", sb)

	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	row.add_child(line)

	# Its own button, so folding a folder and opening its settings never
	# compete for the same tap.
	var mark: Button = UiKit.make_text_button("-" if not g.collapsed else "+")
	mark.custom_minimum_size = Vector2(UiKit.s(38.0), UiKit.s(30.0))
	mark.tooltip_text = UiKit.label_for("Fold or unfold", "طيّ أو فتح")
	mark.pressed.connect(func() -> void:
		stack.set_group_collapsed(gid, not g.collapsed))
	line.add_child(mark)

	var name_l: Label = UiKit.make_label(
		"%s  (%d)" % [g.title, stack.member_count(gid)], 13.0, UiKit.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name_l)

	var eye: Button = _icon_button("hide_layer",
		UiKit.label_for("Show or hide the folder", "إظهار أو إخفاء المجلد"))
	eye.custom_minimum_size = Vector2(UiKit.s(38.0), UiKit.s(38.0))
	eye.modulate = Color(1.0, 1.0, 1.0, 1.0 if g.visible else 0.40)
	eye.pressed.connect(func() -> void: stack.set_group_visible(gid, not g.visible))
	line.add_child(eye)
	return row

func _thumb_box(tex: ImageTexture) -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(UiKit.s(THUMB), UiKit.s(THUMB))
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color("#f4f1ea")
	sb.border_color = Color("#4a505c")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(UiKit.s(7.0)))
	frame.add_theme_stylebox_override("panel", sb)

	var pic: TextureRect = TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Comes straight off the canvas, so it blends the canvas's way.
	pic.material = PaintSurface.premultiplied_material()
	pic.texture = tex
	frame.add_child(pic)
	return frame

# ----------------------------------------------------------------- gestures

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		App.touch_mode = true
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_press(st.position)
		else:
			_release(st.position)
		accept_event()
	elif event is InputEventScreenDrag:
		_drag_to((event as InputEventScreenDrag).position)
		accept_event()
	elif event is InputEventMouseButton:
		if App.touch_mode:
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release(mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_by(-UiKit.s(40.0))
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_by(UiKit.s(40.0))
			accept_event()
	elif event is InputEventMouseMotion:
		if App.touch_mode or _mode == Mode.IDLE:
			return
		_drag_to((event as InputEventMouseMotion).position)
		accept_event()

func _press(pos: Vector2) -> void:
	if not _clip.visible:
		return
	if not _in_list(pos):
		return
	_press_at = pos
	_pointer = pos
	_press_ms = Time.get_ticks_msec()
	set_process(true)
	_press_row = _row_at(pos)
	_scroll_from = _scroll
	_mode = Mode.WAITING

func _drag_to(pos: Vector2) -> void:
	_pointer = pos
	if _mode == Mode.WAITING:
		if absf(pos.y - _press_at.y) > MOVE_SLOP * App.ui_scale:
			# Moved before the hold matured: the finger wants to scroll.
			_mode = Mode.SCROLL
		else:
			return
	if _mode == Mode.SCROLL:
		_set_scroll(_scroll_from - (pos.y - _press_at.y))
	elif _mode == Mode.DRAG:
		_drag_slot = _nearest_slot(pos.y)
		_edge_scroll(pos.y)
		_paint.queue_redraw()

func _release(pos: Vector2) -> void:
	# The mode is cleared first: both branches below rebuild the list, and a
	# rebuild that still believed a drag was running would draw an indicator
	# against rows that no longer exist.
	var was: int = _mode
	_mode = Mode.IDLE
	_press_row = -1
	if was == Mode.DRAG:
		_finish_drag()
	elif was == Mode.WAITING:
		_tap(pos)
	_drag_layer = -1
	_drag_slot = -1
	_paint.queue_redraw()

func _tap(pos: Vector2) -> void:
	var r: int = _row_at(pos)
	if r < 0 or r >= _rows.size():
		return
	var entry: Dictionary = _rows[r]
	if String(entry["kind"]) == "group":
		var gid: int = int(entry["gid"])
		if stack.group_by_id(gid) == null:
			return
		stack.set_active_group(gid)
		_settings_group = gid
		_settings_for = -1
		_rebuild()
		return
	var index: int = int(entry["index"])
	if index == stack.active_index:
		_settings_for = index
		_settings_group = -1
		_rebuild()
		return
	stack.set_active(index)
	_close_settings()

func _start_drag() -> void:
	if _press_row < 0 or _press_row >= _rows.size():
		_mode = Mode.IDLE
		return
	var entry: Dictionary = _rows[_press_row]
	if String(entry["kind"]) != "layer":
		_mode = Mode.IDLE
		return
	var index: int = int(entry["index"])
	if index >= stack.layers.size() or stack.layers[index].is_background:
		_mode = Mode.IDLE
		return
	_drag_layer = index
	_mode = Mode.DRAG
	_build_slots()
	_drag_slot = _nearest_slot(_pointer.y)
	_paint.queue_redraw()

func _finish_drag() -> void:
	if _drag_layer < 0 or _drag_slot < 0 or _drag_slot >= _slots.size():
		return
	var slot: Dictionary = _slots[_drag_slot]
	stack.relocate(_drag_layer, int(slot["index"]), int(slot["group"]))

# ------------------------------------------------------------ drop targets

## One slot per gap between rows. A folder contributes two gaps at its top
## edge — one just above the header and one just below it — and that pair is
## what lets a finger say "beside the folder" or "inside it" without any
## extra gesture.
func _build_slots() -> void:
	_slots.clear()
	if _rows.is_empty():
		return
	var first: Control = _rows[0]["node"]
	_slots.append({
		"y": _list_y(first.position.y),
		"index": stack.layers.size(),
		"group": 0,
	})
	for entry in _rows:
		var node: Control = entry["node"]
		var bottom: float = _list_y(node.position.y + node.size.y)
		if String(entry["kind"]) == "group":
			var gid: int = int(entry["gid"])
			var top_index: int = _group_top_index(gid)
			_slots.append({"y": bottom, "index": top_index + 1, "group": gid})
		else:
			var index: int = int(entry["index"])
			_slots.append({
				"y": bottom,
				"index": index,
				"group": stack.layers[index].group_id,
			})

func _group_top_index(gid: int) -> int:
	var top: int = -1
	for i in stack.layers.size():
		if stack.layers[i].group_id == gid:
			top = i
	return top

func _nearest_slot(y: float) -> int:
	var best: int = -1
	var best_d: float = 1e20
	for i in _slots.size():
		var d: float = absf(float(_slots[i]["y"]) - y)
		if d < best_d:
			best_d = d
			best = i
	return best

## Dragging against the top or bottom edge creeps the list along, so a layer
## can travel further than one screenful without being put down first.
func _edge_scroll(y: float) -> void:
	var box: Rect2 = _clip_rect()
	var top: float = box.position.y
	var bottom: float = top + box.size.y
	var zone: float = UiKit.s(34.0)
	if y < top + zone:
		_set_scroll(_scroll - UiKit.s(9.0))
		_build_slots()
	elif y > bottom - zone:
		_set_scroll(_scroll + UiKit.s(9.0))
		_build_slots()

# -------------------------------------------------------------- list maths

## The list's box in panel-local coordinates — the same space _gui_input
## reports positions in. Everything below measures through this, so nested
## containers and their margins can never shift the maths out from under it.
func _clip_rect() -> Rect2:
	if _clip == null:
		return Rect2()
	return Rect2(_clip.global_position - global_position, _clip.size)

func _in_list(pos: Vector2) -> bool:
	return _clip_rect().has_point(pos)

func _list_y(host_y: float) -> float:
	return _clip_rect().position.y + _host.position.y + host_y

func _row_at(pos: Vector2) -> int:
	for i in _rows.size():
		var node: Control = _rows[i]["node"]
		var top: float = _list_y(node.position.y)
		if pos.y >= top and pos.y <= top + node.size.y:
			return i
	return -1

func _scroll_by(amount: float) -> void:
	_set_scroll(_scroll + amount)

func _set_scroll(value: float) -> void:
	var span: float = maxf(_content_h - _clip_rect().size.y, 0.0)
	_scroll = clampf(value, 0.0, span)
	_host.position = Vector2(0.0, -_scroll)
	_paint.queue_redraw()

# ----------------------------------------------------------------- overlay

func _draw_overlay() -> void:
	if _clip == null or not _clip.visible:
		return
	_draw_folder_frames()
	_draw_drop_hint()
	if _mode == Mode.DRAG:
		_draw_ghost()

## A folder should read as a container at a glance. An outline plus the
## faintest wash of the same colour does that without competing with the
## rows for attention.
##
## Three states, three meanings, and none of them borrows another's colour:
##   resting  — cool slate, "this is a container"
##   selected — brass, the app's one word for "you are working on this"
##   dragging — near-black, "this is somewhere a layer can land"
func _draw_folder_frames() -> void:
	var clip: Rect2 = _clip_rect()
	var dragging: bool = _mode == Mode.DRAG
	var target: int = 0
	if dragging and _drag_slot >= 0 and _drag_slot < _slots.size():
		target = int(_slots[_drag_slot]["group"])

	for g in stack.groups:
		var frame: Rect2 = _group_frame(g.id)
		if frame.size.y <= 0.0:
			continue
		# The gap between rows is shared by the row above and the row below,
		# so the frame may only take half of it. Any more and it reaches
		# across into a layer that is not in this folder.
		var air: float = UiKit.s(5.0) * 0.5 - UiKit.s(1.0)
		frame = frame.grow_individual(UiKit.s(2.0), air, UiKit.s(2.0), air)
		var width: float = UiKit.s(1.5)
		var tone: Color = UiKit.FOLDER
		var wash: float = 0.05

		if dragging:
			tone = UiKit.RAIL
			if g.id == target:
				# The frame stretches by a row, so the space the layer is
				# about to take is visible before the finger lets go.
				frame = frame.grow_individual(0.0, 0.0, 0.0, UiKit.s(ROW_H) * 0.5)
				width = UiKit.s(2.5)
				wash = 0.10
			else:
				width = UiKit.s(1.5)
				wash = 0.03
		elif stack.active_group == g.id:
			tone = UiKit.ACCENT
			width = UiKit.s(2.0)
			wash = 0.10

		var shown: Rect2 = frame.intersection(clip.grow(UiKit.s(4.0)))
		if shown.size.y <= 0.0 or shown.size.x <= 0.0:
			continue
		_paint.draw_rect(shown, Color(tone.r, tone.g, tone.b, wash), true)
		_paint.draw_rect(shown, tone, false, width)

func _draw_drop_hint() -> void:
	if _mode != Mode.DRAG or _drag_slot < 0 or _drag_slot >= _slots.size():
		return
	var box: Rect2 = _clip_rect()
	var slot: Dictionary = _slots[_drag_slot]
	var y: float = clampf(float(slot["y"]), box.position.y,
		box.position.y + box.size.y)
	var left: float = box.position.x
	var right: float = left + box.size.x
	# Brass, and deliberately not the folder's colour: the frame answers
	# "which container", this answers "which gap".
	_paint.draw_line(Vector2(left, y), Vector2(right, y), UiKit.ACCENT, UiKit.s(3.0))
	_paint.draw_circle(Vector2(left + UiKit.s(4.0), y), UiKit.s(5.0), UiKit.ACCENT)

## The exact span of one folder's rows, header included, and nothing else.
## Measured from the rows on screen rather than from the layer list, so a
## folded folder frames only its header and an open one stops at its last
## member instead of reaching into whatever follows.
func _group_frame(gid: int) -> Rect2:
	var top: float = 1e20
	var bottom: float = -1e20
	for entry in _rows:
		var belongs: bool = false
		if String(entry["kind"]) == "group":
			belongs = int(entry["gid"]) == gid
		else:
			var index: int = int(entry["index"])
			belongs = index < stack.layers.size() and stack.layers[index].group_id == gid
		if not belongs:
			continue
		var node: Control = entry["node"]
		top = minf(top, _list_y(node.position.y))
		bottom = maxf(bottom, _list_y(node.position.y + node.size.y))
	if bottom <= top:
		return Rect2()
	var box: Rect2 = _clip_rect()
	# Trimmed on the right so the frame ends where its rows end rather than
	# running the full width of the panel, and gaps between rows are not
	# counted as part of it.
	return Rect2(box.position.x + UiKit.s(1.0), top,
		box.size.x - UiKit.s(2.0), bottom - top)

## A small card riding under the finger, so it is never unclear what is
## being carried.
func _draw_ghost() -> void:
	if _drag_layer < 0 or _drag_layer >= stack.layers.size():
		return
	var l: LayerStack.Layer = stack.layers[_drag_layer]
	var clip: Rect2 = _clip_rect()
	var w: float = clip.size.x * 0.7
	var h: float = UiKit.s(44.0)
	var box: Rect2 = Rect2(clip.position.x + UiKit.s(18.0),
		_pointer.y - h * 0.5, w, h)

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.11, 0.13, 0.94)
	sb.set_corner_radius_all(int(UiKit.s(10.0)))
	_paint.draw_style_box(sb, box)

	var dot: Rect2 = Rect2(box.position + Vector2(UiKit.s(10.0), UiKit.s(10.0)),
		Vector2(h - UiKit.s(20.0), h - UiKit.s(20.0)))
	_paint.draw_rect(dot, UiKit.ACCENT, true)

	var f: Font = ThemeDB.fallback_font
	if f != null:
		var title: String = l.title
		if l.is_background:
			title = UiKit.label_for("Background", "الخلفية")
		_paint.draw_string(f, box.position + Vector2(h, h * 0.62), title,
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - h - UiKit.s(6.0),
			int(UiKit.s(12.0)), Color(0.88, 0.86, 0.81))

# --------------------------------------------------------- layer settings

func _settings_header(title: String) -> void:
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	_settings.add_child(head)

	var back: Button = UiKit.make_text_button(UiKit.label_for("Back", "رجوع"))
	back.pressed.connect(_close_settings)
	head.add_child(back)

	var name_l: Label = UiKit.make_label(title, 15.0, UiKit.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(name_l)

	_settings.add_child(HSeparator.new())

func _note(text: String) -> void:
	var l: Label = UiKit.make_label(text, 10.0, UiKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings.add_child(l)

func _build_layer_settings(index: int) -> void:
	var l: LayerStack.Layer = stack.layers[index]
	var title: String = l.title
	if l.is_bone_layer:
		title = "🦴 " + UiKit.label_for("Bone Motion", "عظام — حركة فقط")
	if l.is_background:
		title = UiKit.label_for("Background", "الخلفية")
	_settings_header(title)

	if l.is_bone_layer:
		_note(UiKit.label_for(
			"Motion-only layer. Anything placed here is an object for movement only. No painting, filling, shaping, erasing, selecting, text, puppet warp or bone editing is allowed here.",
			"طبقة حركة فقط. أي جسم يوضع هنا مخصص للتحريك فقط. لا رسم ولا ملء ولا أشكال ولا ممحاة ولا تحديد ولا نص ولا تحريك بالدبابيس ولا تعديل عظام داخلها."))
		var move: Button = UiKit.make_text_button(
			UiKit.label_for("Move object", "حرّك الجسم"), true)
		move.pressed.connect(func() -> void:
			stack.set_active(index)
			App.set_tool(App.Tool.MOVE))
		_settings.add_child(move)
		var make_normal: Button = UiKit.make_text_button(
			UiKit.label_for("Convert to normal layer", "تحويل إلى طبقة عادية"), true)
		make_normal.pressed.connect(func() -> void:
			l.is_bone_layer = false
			stack.changed.emit()
			_close_settings())
		_settings.add_child(make_normal)
		# No ordinary layer controls are exposed on this special surface.
		return

	# The value is written live so the canvas answers the finger, but the
	# history only hears about it once, when the finger lifts.
	var before: Array = []
	var fade: TouchSlider = UiKit.slider_row(_settings,
		UiKit.label_for("Opacity", "الشفافية"),
		0.0, 1.0, l.opacity, 0.01, "",
		func(x: float) -> void:
			if before.is_empty():
				before.append(stack.capture_arrangement())
			stack.set_opacity_at(index, x))
	fade.drag_ended.connect(func(_x: float) -> void:
		if before.is_empty():
			return
		view.history.push(UiKit.label_for("Layer opacity", "شفافية طبقة"),
			[{"t": "arrangement", "state": before[0]}])
		before.clear())

	var lock: Button = UiKit.make_text_button(
		UiKit.label_for("Locked", "مقفلة") if l.locked
		else UiKit.label_for("Unlocked", "غير مقفلة"), true)
	lock.pressed.connect(func() -> void:
		stack.set_locked_at(index, not stack.layers[index].locked)
		_rebuild())
	_settings.add_child(lock)

	var bring: Button = UiKit.make_text_button(
		UiKit.label_for("Import image", "استيراد صورة"), true)
	bring.pressed.connect(func() -> void: import_requested.emit(index))
	_settings.add_child(bring)

	var copy: Button = UiKit.make_text_button(
		UiKit.label_for("Duplicate", "نسخة مطابقة"), true)
	copy.pressed.connect(func() -> void:
		stack.duplicate_layer(index)
		_close_settings())
	_settings.add_child(copy)

	var open_it: Button = UiKit.make_text_button(
		UiKit.label_for("Open this layer alone", "افتح هذه الطبقة وحدها"), true)
	open_it.pressed.connect(func() -> void: solo_requested.emit(index))
	_settings.add_child(open_it)

	# --- improving what is drawn here ---
	#
	# On the background layer this is refused rather than hidden, because the
	# background is a place to put an imported picture and there is nothing
	# drawn there to improve.
	if not l.is_background:
		var better: Button = UiKit.make_text_button(
			UiKit.label_for("Improve", "تحسين"), true)
		better.pressed.connect(func() -> void: improve_requested.emit(index))
		_settings.add_child(better)
		_note(UiKit.label_for(
			"Sends this drawing to be redrawn with cleaner lines and steadier proportions. What comes back arrives on a new layer called the improvement layer, so this one is untouched and the two can be compared by tapping the eye.",
			"يرسل هذا الرسم ليُعاد رسمه بخطوط أنظف ونسب أثبت. وما يعود يصل على طبقة جديدة اسمها طبقة التحسين، فتبقى هذه سليمة ويمكن مقارنة الاثنتين بضغط العين."))

	# --- the skeleton, if this layer has one ---
	#
	# A rigged layer is posed rather than drawn on, and until now that was a
	# one-way door: bones could be put on a drawing in the B-Spline room and
	# there was nowhere at all to take them off again. A layer boned by
	# mistake, or boned in a way that turned out wrong, had to be redrawn.
	#
	# Here rather than in the room, because this is where you come when you
	# have tapped the layer and want to know what is on it — and because a
	# rig you want rid of is usually one you have just noticed from outside
	# the room, not one you went back into the room to admire.
	if not l.rig.is_empty():
		var rows: Array = l.rig.get("bones", [])
		var count: int = rows.size()
		var loose: int = 0
		for row in rows:
			if float((row as Dictionary).get("soft", 0.0)) > 0.0:
				loose += 1
		_note(UiKit.label_for(
			"%d bones. Drag a joint on the canvas to move the drawing; it turns wherever you take it. While a layer has a skeleton it is posed rather than drawn on, and its frames follow the poses." % count,
			"%d عظمة. اسحب مفصلاً على اللوحة ليتحرك الرسم؛ يدور حيث تأخذه. وما دامت للطبقة هيكل فهي تُوضَّع لا يُرسم عليها، وإطاراتها تتبع الأوضاع." % count))

		UiKit.slider_row(_settings, UiKit.label_for("Show the skeleton",
			"إظهار الهيكل"), 0.0, 1.0, l.show_bones, 0.01, "",
			func(x: float) -> void:
				l.show_bones = x
				stack.changed.emit())
		_note(UiKit.label_for(
			"How plainly the bones are drawn over the figure. It governs only what you see while working; nothing of it ever reaches the drawing or the export.",
			"مدى وضوح رسم العظام فوق الشخصية. تحكم ما تراه أثناء العمل فقط، ولا يصل شيء منها إلى الرسم ولا إلى التصدير."))

		# How the figure trails behind its own pose. Off unless something
		# here was marked loose in the bone room, and said so rather than
		# greyed: three sliders that cannot do anything are three questions
		# with no answer.
		_settings.add_child(HSeparator.new())
		if loose > 0:
			var swing: Button = UiKit.make_text_button(
				UiKit.label_for("Let it trail", "اجعله يتأخر"), true)
			swing.toggle_mode = true
			swing.set_pressed_no_signal(l.dangle)
			swing.pressed.connect(func() -> void:
				l.dangle = not l.dangle)
			_settings.add_child(swing)
			_note(UiKit.label_for(
				"%d bones on this figure are marked loose. While the scene plays they arrive a moment after the pose does, so hair and cloth follow the movement instead of being welded to it." % loose,
				"%d من عظام هذه الشخصية مُعلَّمة سائبة. وأثناء تشغيل المشهد تصل بعد الوضعية بلحظة، فيتبع الشعر والقماش الحركة بدل أن يكونا ملحومين بها." % loose))
			UiKit.slider_row(_settings, UiKit.label_for("Stiffness",
				"الصلابة"), 0.5, 12.0, l.dangle_speed, 0.1, "",
				func(x: float) -> void: l.dangle_speed = x)
			UiKit.slider_row(_settings, UiKit.label_for("Settling",
				"الاستقرار"), 0.05, 1.5, l.dangle_damp, 0.01, "",
				func(x: float) -> void: l.dangle_damp = x)
			UiKit.slider_row(_settings, UiKit.label_for("Overshoot",
				"التجاوز"), -1.0, 3.0, l.dangle_swing, 0.05, "",
				func(x: float) -> void: l.dangle_swing = x)
			_note(UiKit.label_for(
				"High stiffness is wire, low is heavy rope. Low settling wobbles before it comes to rest, which is what hair does. Overshoot above one carries past the pose and comes back; below nought it draws back before it moves, which is a piece of animation grammar older than computers.",
				"الصلابة العالية سلك، والمنخفضة حبل ثقيل. والاستقرار المنخفض يتذبذب قبل أن يهدأ، وهذا ما يفعله الشعر. والتجاوز فوق الواحد يتخطى الوضعية ثم يعود، وتحت الصفر يتراجع قبل أن يتحرك، وهذه قاعدة في التحريك أقدم من الحواسيب."))
		else:
			_note(UiKit.label_for(
				"Nothing on this skeleton is loose. Open the bone room, choose Loose, and tap the bones that are hair, cloth or a tail — then they can be made to trail behind the movement.",
				"لا شيء في هذا الهيكل سائب. افتح غرفة العظام واختر «سائب» ثم اضغط العظام التي هي شعر أو قماش أو ذيل — عندها يمكن جعلها تتأخر خلف الحركة."))
		_settings.add_child(HSeparator.new())

		var armed: Array = [false]
		var strip: Button = UiKit.make_text_button(
			UiKit.label_for("Remove the bones", "أزل العظام"), true)
		strip.pressed.connect(func() -> void:
			if not armed[0]:
				armed[0] = true
				strip.text = UiKit.label_for("Tap again to remove",
					"اضغط ثانية للإزالة")
				return
			rig_removal_requested.emit(index)
			_close_settings())
		_settings.add_child(strip)

	# Light. It belongs to the layer rather than to the brush, because it is
	# about how this drawing meets the ones under it — and a glow painted
	# before the switch was flicked should not have to be painted again.
	var glow: Button = UiKit.make_text_button(
		UiKit.label_for("Light layer", "طبقة ضوء"), true)
	glow.toggle_mode = true
	glow.set_pressed_no_signal(l.glow)
	glow.pressed.connect(func() -> void:
		stack.set_glow_at(index, not l.glow))
	_settings.add_child(glow)
	_note(UiKit.label_for(
		"Adds its light to the layers below instead of covering them. A halo over a night scene lifts what it falls on and leaves the dark alone.",
		"يضيف ضوءه إلى الطبقات تحته بدل أن يغطيها. فالهالة فوق مشهد ليلي ترفع ما تقع عليه وتترك العتمة كما هي."))

	# A text layer still knows its own words, so it offers to be rewritten
	# rather than erased and typed again. This only appears on layers that
	# were made by writing — on a drawing there is nothing to reopen.
	if l.is_text:
		var rewrite: Button = UiKit.make_text_button(
			UiKit.label_for("Edit the text", "عدّل النص"), true)
		rewrite.pressed.connect(func() -> void:
			text_edit_requested.emit(index))
		_settings.add_child(rewrite)
		_note(UiKit.label_for(
			"The words are kept, not just their picture — so this restyles rather than redraws.",
			"الكلمات محفوظة لا صورتها فقط — فهذا يعيد تنسيقها لا رسمها."))

	LayerRigRow.build(self, l, index, _settings)

	# One heavy tool per layer, enforced rather than advised. Bones, puppet
	# and B-Spline reshape the same pixels by different arithmetic and do not
	# compose: whichever writes last wins while the other keeps a stand-in
	# showing where *it* thought the figure was — the doubled, ghosted
	# drawing. Taking the bones off opens the rest again.
	if not l.rig.is_empty():
		return

	# Bending belongs to a layer, so it is offered where a layer is talked
	# about rather than in the rail: the rail chooses what the hand does,
	# and this changes what the drawing already is.
	# One tool, two names, and the name is the difference. A rigged figure
	# already articulates, and calling that "warp" tells somebody their
	# character is about to be distorted — the exact thing they fear and the
	# exact thing that does not happen. The arithmetic is untouched: rigid
	# MLS fits rotation and position only, never scale, so a stroke keeps its
	# thickness. It was always rigging; only the name was wrong here.
	var rigged: bool = l.title.to_lower().contains("character 360")
	var warp: Button = UiKit.make_text_button(
		UiKit.label_for("Puppet rigging", "التحريك بالدبابيس")
		if rigged else UiKit.label_for("Puppet warp", "التحريك بالدبابيس"),
		true)
	warp.pressed.connect(func() -> void:
		stack.set_active(index)
		puppet_requested.emit(index))
	_settings.add_child(warp)
	_note(UiKit.label_for(
		"Pin the parts that should stay put and pull the rest. It moves the character, it does not distort it — only rotation and position are ever fitted, so a stroke keeps its thickness and a limb keeps its length however far you take it."
		if rigged else "Pin the drawing and pull. What you pin holds still.",
		"ثبّت الأجزاء التي يجب أن تبقى واسحب الباقي. يحرّك الشخصية ولا يشوّهها — فلا يُلائَم إلّا الدوران والموضع، فيحفظ الخيط سماكته ويحفظ الطرف طوله مهما أبعدتَه."
		if rigged else "ثبّت الرسم بالدبابيس ثم اسحب. وما تثبّته يبقى مكانه."))

	if not l.is_background:
		if l.group_id != 0:
			var out: Button = UiKit.make_text_button(
				UiKit.label_for("Take out of the folder", "أخرجها من المجلد"), true)
			out.pressed.connect(func() -> void:
				stack.ungroup_layer(index)
				_close_settings())
			_settings.add_child(out)

	if index > 0:
		var merge: Button = UiKit.make_text_button(
			UiKit.label_for("Merge into the one below", "دمج مع التي تحتها"), true)
		merge.pressed.connect(func() -> void:
			stack.merge_down(index)
			_close_settings())
		_settings.add_child(merge)

	var wipe: Button = UiKit.make_text_button(
		UiKit.label_for("Erase its contents", "امسح محتواها"), true)
	wipe.pressed.connect(func() -> void:
		stack.clear_layer(index)
		_close_settings())
	_settings.add_child(wipe)

	if l.is_background:
		_settings.add_child(UiKit.make_label(
			UiKit.label_for("The background stays. Only what is on it can go.",
				"الخلفية لا تُحذف. يُمسح محتواها فقط."), 11.0, UiKit.TEXT_DIM))

func _build_group_settings(gid: int) -> void:
	LayerGroupRow.build(self, gid)
