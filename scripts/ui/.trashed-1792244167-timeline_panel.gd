class_name TimelinePanel
extends PanelContainer
## The timeline, built to the shape you drew.
##
## One band at the foot of the screen: a row of controls, a ruler, and one
## line per layer with a dot on every frame that holds a drawing. The camera
## is a line among them — it behaves like a layer and is told apart by its
## colour rather than by living somewhere else.
##
## There are exactly two ways to add a frame, because those are the two
## things an animator does: **new frame** starts blank, and **duplicate
## after** starts from the drawing before it so the last pose can be traced.
## Everything else was taken out.
##
## Everything below the head bar is drawn by hand in one `_draw`. A grid of
## six hundred cells built from nodes would spend longer laying itself out
## than the drawing does.

signal closed()

const TREE_W: float = 150.0
## Folder headers are shallower than layer rows, the way they are in the
## layers panel — the band is short and a folder is a label, not a track.
const GROUP_H: float = 30.0
## How tall a layer row is.
##
## Thirty was a mouse's row height. On a tablet it is under four millimetres —
## less than half a fingertip — so choosing a layer in a stack of eight meant
## aiming, and aiming at the wrong one meant the frame buttons then acted on
## a layer nobody had chosen. Forty-two is a comfortable target and still
## fits eight rows in the band without scrolling.
const ROW_H: float = 42.0
const RULER_H: float = 26.0
## How fast the band travels when the finger is held at its edge while
## scrubbing, in frames a second at full push. See `_edge_follow`.
const FOLLOW_FPS: float = 26.0
const MIN_FRAME_W: float = 7.0
const MAX_FRAME_W: float = 56.0
const HOLD_MS: int = 340
const SLOP: float = 11.0

## The ivory a frame-rate unit is drawn in.
##
## Cream and see-through, so the drawings and the dots underneath it are still
## readable through the selection — a solid block over eight layers would hide
## exactly the thing being timed. The edge and the marks on it are the same
## colour at full strength, which is what keeps a pale translucent shape from
## dissolving into a pale translucent smudge.
const UNIT_FILL: Color = Color(0.949, 0.910, 0.804, 0.15)
const UNIT_EDGE: Color = Color(0.965, 0.933, 0.831, 0.66)
const UNIT_INK: Color = Color(0.992, 0.976, 0.925, 0.95)
## How far from a grip a finger still counts as being on it.
const GRIP_REACH: float = 16.0
const GRIP_R: float = 11.0

enum Mode { IDLE, WAITING, SCRUB, SCROLL, PAN, DRAG }

var player: AnimPlayer = null
var clip: Anim.Clip = null
var stack: LayerStack = null
var view: CanvasView = null

var frame_w: float = 13.0
var scroll_y: float = 0.0
## How far along the clip the grid is looking. Without it a long scene had
## an end nobody could reach: zooming out far enough to see frame six
## hundred left every dot too small to touch.
var scroll_x: float = 0.0

var _rows: Array = []          # {kind, layer, y}
var _content_h: float = 0.0
var _body: Control = null
var _head: HBoxContainer = null
var _play_btn: Button = null
## Asked for when a layer wants sound. The panel does not open files itself —
## picking a file is the app's business, and there is one place that knows how
## to do it properly on each platform.
signal audio_wanted(layer_index: int)

var _onion_btn: Button = null
var _camera_btn: Button = null
var _layer_btn: Button = null

# --- one touch, one state machine ---
var _mode: int = Mode.IDLE
var _press_at: Vector2 = Vector2.ZERO
var _press_ms: int = 0
var _scroll_from: float = 0.0
var _touches: Dictionary = {}
var _pinch_from: float = 0.0
var _pinch_span: float = 0.0
var _drag_layer: LayerStack.Layer = null
var _drag_frame: int = -1
var _drag_camera: bool = false
var _drag_edge: bool = false
var _hold_action: Callable = Callable()
var _hold_ms: int = 0
## The key most recently made or touched, so the band can point at it.
var _last_key_frame: int = -1
## The curve a new key is born with. Changed from the Curves sheet, which
## is also where every existing key can be set at once.
var _default_ease: int = Anim.Ease.SMOOTH
var _readout: Label = null
var _pan_from: float = 0.0
var _body_hold_ms: int = 0
var _drag_focus: Variant = null
var _drag_focus_end: int = 1
var _tap_key: int = -1
## Two taps close together on the same point. Kept here rather than shared
## with the frame gestures, so a quick tap on a drawing and then on a focus
## point is never read as one double tap across the two.
var _tap_ms: int = 0
## How close together two taps have to be to count as one double tap. The
## focus gestures were written against a constant that lives in another
## script and does not exist here, so the whole panel refused to compile.
const DOUBLE_TAP_MS: int = 320
var _last_head_x: float = -99999.0

# --- frame-rate units ---
## The unit a finger is currently changing, and which part of it.
##   -1  the left grip: where the unit begins
##    1  the right grip: where it ends
##    0  the whole unit, sliding along the band
var _drag_unit: Anim.Unit = null
var _drag_unit_side: int = 0
## How far into the unit the finger took hold of it, so sliding a unit keeps
## the frame that was under the thumb under the thumb.
var _drag_unit_grab: int = 0
## A unit being held rather than dragged. It becomes `_drag_unit` if the hold
## matures, and is forgotten if the finger moves first.
var _press_unit: Anim.Unit = null
var _unit_tap_ms: int = 0
var _unit_tap_id: int = -1
var _units_btn: Button = null
var _view_from_btn: Button = null
var _view_to_btn: Button = null
## The last frame in the scene that means anything, worked out once per
## refresh rather than per row. The band is endless, so this — not `length` —
## is where the drawings stop.
var _reach: int = 0

## Where every layer's drawings are, worked out once and kept until they
## change. See `TimelineIndex` for what was costing what.
var _index: TimelineIndex = TimelineIndex.new()
## Built once. A style box is the only way to get a rounded translucent plate
## out of `_draw`, and making one per unit per redraw would allocate on every
## frame of playback.
@warning_ignore("unused_private_class_variable")
var _unit_plate: StyleBoxFlat = null

const ICON: String = "res://assets/icons/%s.png"
const TL_ICON: Dictionary = {
	"anim_play": "res://assets/timeline_supplied/start animation/icons8-play-64 (1).png",
	"anim_stop": "res://assets/timeline_supplied/stop animation/icons8-stop-64.png",
	"anim_prev": "res://assets/timeline_supplied/back frame/icons8-double-left-64.png",
	"anim_next": "res://assets/timeline_supplied/to frame/icons8-double-right-64.png",
	"depth_focus": "res://assets/icons/depth_focus.png",
	"add_frame": "res://assets/timeline_supplied/add frame or dublicet after/icons8-keyframes-64.png",
	"anim_camera": "res://assets/timeline_supplied/add camera kay/icons8-add-camera-64.png",
	"add_file": "res://assets/timeline_supplied/Choose an animation layer/icons8-folder-60.png",
	"anim_onion": "res://assets/timeline_supplied/onion skin/icons8-onion-64.png",
	"anim_units": "res://assets/timeline_supplied/Dividing frame rate into units/icons8-cut-60.png"
}

# ---------------------------------------------------------------- set up

func setup(anim_player: AnimPlayer, target_clip: Anim.Clip,
		target_stack: LayerStack, canvas: CanvasView) -> void:
	player = anim_player
	clip = target_clip
	stack = target_stack
	view = canvas

	add_theme_stylebox_override("panel", UiKit.rail_style())
	mouse_filter = Control.MOUSE_FILTER_STOP

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", int(UiKit.s(2.0)))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# The toolbar contains every supplied timeline control. On a phone the
	# complete row is horizontally scrollable instead of squeezing icons until
	# their touch targets become unreliable.
	var rail: ScrollContainer = ScrollContainer.new()
	rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rail.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail.custom_minimum_size = Vector2(0.0, UiKit.s(44.0))
	rail.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(rail)
	_build_head(rail)

	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0.0, UiKit.s(RULER_H + ROW_H * 3.0))
	_body.draw.connect(_draw_body)
	_body.gui_input.connect(_body_input)
	column.add_child(_body)

	# Redrawing the whole band on every rendered frame of playback costs more
	# than the drawing does. The band only has something new to say when the
	# playhead has actually moved far enough to be seen moving, so that is
	# the only time it is asked to draw itself.
	player.frame_changed.connect(_on_frame_changed)
	player.playing_changed.connect(_show_transport)
	view.camera_framed.connect(_camera_changed)
	# Layers arriving, leaving or being foldered all change who is soft — a
	# focus worked out before that change is describing a stack that no
	# longer exists.
	stack.changed.connect(_apply_focus)
	# The one thing that invalidates the index: a drawing added, removed or
	# moved. Not a pose, not a repaint — where a cel sits on the band is the
	# only thing the cached answers depend on.
	stack.changed.connect(_index.forget)
	stack.changed.connect(rebuild)
	_show_transport(player.playing)
	_sync_readout(int(floor(player.frame)))
	_apply_focus()
	rebuild()

func _on_frame_changed(_f: float) -> void:
	_apply_focus()
	var x: float = x_of(player.frame)
	if absf(x - _last_head_x) < 0.75:
		return
	_last_head_x = x
	_follow_playhead()
	refresh()

## Keeps the playhead on screen while it is moving, the way a page turns
## itself under a line of text being read.
func _follow_playhead() -> void:
	if _body == null or clip == null:
		return
	var grid: Rect2 = grid_rect()
	if grid.size.x <= 1.0:
		return
	var x: float = x_of(player.frame)
	var margin: float = minf(grid.size.x * 0.22, UiKit.s(90.0))
	if x > grid.position.x + grid.size.x - margin:
		_set_scroll_x(scroll_x + (x - (grid.position.x + grid.size.x - margin)))
	elif x < grid.position.x + margin:
		_set_scroll_x(scroll_x - ((grid.position.x + margin) - x))

func _sync_readout(f: int) -> void:
	if _readout == null or clip == null:
		return
	# Through the language rather than glued together, so the number can sit
	# where each language puts it — and so Arabic gets Arabic digits.
	_readout.text = Lang.fill("Frame {0} of {1}",
		[f + 1, maxi(_reach + 1, 1)], "الإطار {0} من {1}")

func _dirty() -> void:
	if view == null or view.projects == null:
		return
	var p: ProjectManager.Project = view.projects.active
	if p == null:
		return
	# The scene, not the band. Scrolling out to look at frame four hundred
	# grows the band to reach it, and the project should not then claim to be
	# four hundred frames long.
	p.frames = maxi(_reach + 1, 1)
	p.fps = clampi(clip.fps, 1, 60)
	p.onion_skin = player.onion
	# Eight, matching the sliders and the loader.
	#
	# This clamped to five while the sliders offered eight and the vault read
	# eight back. So six, seven and eight could be chosen, worked on screen
	# straight away, and were quietly cut to five the next time the project
	# was written — which looks like the setting drifting on its own.
	p.onion_back = clampi(player.onion_back, 0, 8)
	p.onion_forward = clampi(player.onion_forward, 0, 8)
	p.onion_back_tint = player.onion_back_tint
	p.onion_highlight = player.onion_highlight_tint
	p.onion_forward_tint = player.onion_forward_tint
	p.looping = player.looping
	view.projects.mark_dirty(p)

func _build_head(rail: ScrollContainer) -> void:
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	_head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rail.add_child(_head)

	# Play / Stop share one button. The supplied timeline assets are used for
	# both states: play when idle, stop while playing.
	_play_btn = _icon("anim_play", UiKit.label_for("Play animation", "تشغيل الحركة"),
		_toggle_play_stop)
	_play_btn.toggle_mode = false
	_head.add_child(_play_btn)
	var frame_readout: Label = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	frame_readout.custom_minimum_size = Vector2(UiKit.s(94.0), UiKit.s(40.0))
	frame_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame_readout.name = "FrameReadout"
	_head.add_child(frame_readout)
	_readout = frame_readout
	player.frame_index_changed.connect(_sync_readout)

	# Tap steps one frame. Held, they jump to the next drawing rather than the
	# next frame — on a scene held on twos or threes that is the difference
	# between eight taps and one press.
	# Stepping a frame turns the ghosts on.
	#
	# Moving to the next frame is the moment onion skin is *for*: you are
	# there to draw the frame after the one you just drew, and the one you
	# just drew is the thing you need to see. Leaving it off meant reaching
	# for a second button every single time, and the app knowing perfectly
	# well what you were about to want.
	var back: Button = _icon("anim_prev",
		UiKit.label_for("Previous frame", "الإطار السابق"),
		func() -> void: _step_frame(-1))
	back.button_down.connect(func() -> void:
		_hold_start(func() -> void: player.step_to_drawing(-1)))
	back.button_up.connect(_hold_end)
	_head.add_child(back)

	var fwd: Button = _icon("anim_next",
		UiKit.label_for("Next frame", "الإطار التالي"),
		func() -> void: _step_frame(1))
	fwd.button_down.connect(func() -> void:
		_hold_start(func() -> void: player.step_to_drawing(1)))
	fwd.button_up.connect(_hold_end)
	_head.add_child(fwd)

	# The supplied keyframe icon is dedicated to Duplicate After. A normal tap
	# always duplicates immediately. Long-pressing opens the frame insertion
	# settings, where a blank frame can be inserted between the current frame
	# and an already-existing next frame.
	var add: Button = _icon("add_frame", UiKit.label_for("Duplicate after", "نسخ بعده"),
		func() -> void: _add_frame(true))
	add.button_down.connect(func() -> void: _hold_start(_open_frame_settings))
	add.button_up.connect(_hold_end)
	_head.add_child(add)

	# Dividing the frame rate into units. It sits with the frame controls
	# rather than with the settings, because what it changes is the timing of
	# frames — the same thing the two buttons on its left change.
	#
	# A tap lays a new unit down at the playhead; holding it opens the list of
	# every unit in the scene, which is the only way to reach one that has
	# been scrolled far off the band.
	_units_btn = _icon("anim_units",
		UiKit.label_for("Dividing frame rate into units",
			"تقسيم معدل الإطارات إلى وحدات"), _add_unit)
	_units_btn.button_down.connect(func() -> void: _hold_start(_open_units_list))
	_units_btn.button_up.connect(_hold_end)
	_head.add_child(_units_btn)

	# Depth of field. It acts on the layer chosen in the band, because
	# choosing what is sharp is the thing this does — and the layer under
	# your finger is the thing you are thinking about.
	_head.add_child(_icon("depth_focus",
		UiKit.label_for("Shallow depth of field", "عمق ميدان ضحل"),
		_add_focus))

	# One button, two meanings, in the order an animator meets them: add the
	# camera to the scene, then add keys to the camera. Holding it steps in
	# and out of composing the shot on the canvas.
	_camera_btn = _icon("anim_camera",
		UiKit.label_for("Add camera", "أضف كاميرا"), _camera_button)
	_camera_btn.toggle_mode = true
	_camera_btn.button_down.connect(func() -> void: _hold_start(_toggle_camera_edit))
	_camera_btn.button_up.connect(_hold_end)
	_head.add_child(_camera_btn)

	_layer_btn = _icon("add_file", UiKit.label_for("Choose animation layer",
		"اختيار طبقة الرسوم المتحركة"), _open_animation_layer_picker)
	_head.add_child(_layer_btn)

	_onion_btn = _icon("anim_onion", UiKit.label_for("Onion skin", "قشرة البصل"),
		_toggle_onion)
	_onion_btn.toggle_mode = true
	_onion_btn.button_down.connect(func() -> void: _hold_start(_open_onion_settings))
	_onion_btn.button_up.connect(_hold_end)
	_head.add_child(_onion_btn)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(UiKit.s(12.0), 1.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(spacer)

	# Where the band starts and where it stops — the two ends of what you are
	# looking at, chosen by you rather than by the app.
	#
	# They carry their own numbers rather than a symbol, so the window can be
	# read without opening anything: `◂ 1` and `0 ▸` is a band that starts at
	# the first frame and never ends. Nought is the end that means no end, and
	# it is nought because that is the number you type into the sheet to say
	# so — the button and the sheet agree instead of having to be learnt
	# separately.
	_view_from_btn = UiKit.make_text_button("◂ 1")
	_view_from_btn.custom_minimum_size = Vector2(UiKit.s(62.0), UiKit.s(40.0))
	_view_from_btn.tooltip_text = UiKit.label_for(
		"Show the band from this frame", "ابدأ عرض الشريط من هذا الإطار")
	_view_from_btn.pressed.connect(_open_view_from)
	_head.add_child(_view_from_btn)

	_view_to_btn = UiKit.make_text_button("0 ▸")
	_view_to_btn.custom_minimum_size = Vector2(UiKit.s(62.0), UiKit.s(40.0))
	_view_to_btn.tooltip_text = UiKit.label_for(
		"Show the band up to this frame — 0 for no end",
		"اعرض الشريط حتى هذا الإطار — صفر لبلا نهاية")
	_view_to_btn.pressed.connect(_open_view_to)
	_head.add_child(_view_to_btn)

	var curves: Button = UiKit.make_text_button(
		UiKit.label_for("Curves", "المنحنيات"), true)
	curves.custom_minimum_size = Vector2(UiKit.s(86.0), UiKit.s(40.0))
	curves.pressed.connect(_open_camera_curves)
	_head.add_child(curves)

	_head.add_child(_icon("settings_gear",
		UiKit.label_for("Timeline settings", "إعدادات التايم لاين"),
		_open_timeline_settings))

	var shut: Button = UiKit.make_text_button("▾")
	shut.custom_minimum_size = Vector2(UiKit.s(40.0), UiKit.s(40.0))
	shut.tooltip_text = UiKit.label_for("Hide the timeline", "أخفِ التايم لاين")
	shut.pressed.connect(func() -> void: closed.emit())
	_head.add_child(shut)

func _icon(icon_name: String, tip: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(UiKit.s(44.0), UiKit.s(40.0))
	var path: String = TL_ICON.get(icon_name, ICON % icon_name)
	if ResourceLoader.exists(path):
		b.icon = load(path)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", int(UiKit.s(21.0)))
	b.add_theme_color_override("icon_normal_color", UiKit.ON_RAIL)
	b.add_theme_color_override("icon_hover_color", Color.WHITE)
	b.add_theme_color_override("icon_pressed_color", Color("#1b1c22"))

	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.bg_color = UiKit.RAIL_FILL
	flat.set_corner_radius_all(int(UiKit.s(9.0)))
	var hover: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
	hover.bg_color = UiKit.RAIL_ON
	var on: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
	on.bg_color = UiKit.ACCENT
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("focus", flat)
	b.pressed.connect(action)
	return b

## Play / Stop is a single transport control. Its icon follows the current
## player state, using the supplied play and stop assets without changing the
## rest of the timeline toolbar.
func _toggle_play_stop() -> void:
	if player == null:
		return
	if player.playing:
		player.stop()
	else:
		player.play()

func _show_transport(on: bool) -> void:
	if _play_btn == null:
		return
	var icon_name: String = "anim_stop" if on else "anim_play"
	var path: String = TL_ICON.get(icon_name, ICON % icon_name)
	if ResourceLoader.exists(path):
		_play_btn.icon = load(path)
	_play_btn.tooltip_text = UiKit.label_for(
		"Stop animation" if on else "Play animation",
		"إيقاف الحركة" if on else "تشغيل الحركة")

# ---------------------------------------------------------------- layout

## One row per layer, top of the picture first, and the camera above them
## all — it frames everything, so it belongs at the top of the list.
func rebuild() -> void:
	_rows.clear()
	if stack == null or clip == null:
		refresh()
		return
	# A clip can never be shorter than the work inside it. Dragging a hold
	# out past the end, or loading a scene saved with a smaller length,
	# used to leave drawings sitting beyond the last frame — present in the
	# file, absent from playback and from every export.
	clip.grow_to_fit(stack)
	var y: float = 0.0
	if clip.camera_on:
		_rows.append({"kind": "camera", "layer": null, "y": y})
		y += UiKit.s(ROW_H)
	# The same order the layers panel shows, folders and all, taken from the
	# same call it uses. Two lists of the same layers in two different orders
	# is a thing nobody can hold in their head — you look at a row here and
	# count rows over there to find out which drawing it is.
	for entry in stack.display_rows():
		if String(entry["kind"]) == "group":
			_rows.append({"kind": "group", "layer": null,
				"gid": int(entry["gid"]), "y": y})
			y += UiKit.s(GROUP_H)
			continue
		var index: int = int(entry["index"])
		_rows.append({"kind": "layer", "layer": stack.layers[index],
			"index": index, "y": y})
		y += UiKit.s(ROW_H)
	_content_h = y
	refresh()

func refresh() -> void:
	if _onion_btn != null and player != null:
		_onion_btn.button_pressed = player.onion
	if _camera_btn != null and view != null and clip != null:
		_camera_btn.set_pressed_no_signal(view.camera_edit and clip.camera_on)
		_camera_btn.tooltip_text = UiKit.label_for("Add camera key",
			"إضافة مفتاح كاميرا") if clip.camera_on \
			else UiKit.label_for("Add camera", "أضف كاميرا")
	# Worked out once, here, and read by everything that draws. It is asked
	# for on every redraw, so it costs one question per layer rather than one
	# per drawing — see CelTrack.last_frame.
	if clip != null:
		# From the index rather than a walk over every layer. `clip.reach`
		# still exists and still gives the same answer — it is what the index
		# is checked against — but it is asked once per change now instead of
		# once per redraw and once per rendered frame of playback.
		var scene_end: int = _index.scene_end(stack)
		_reach = maxi(maxi(scene_end, clip.tail_hold), 0)
	_sync_view_buttons()
	scroll_x = _clamp_scroll_x(scroll_x)
	if _body != null:
		var down: float = maxf(_content_h - (_body.size.y - UiKit.s(RULER_H)), 0.0)
		scroll_y = clampf(scroll_y, 0.0, down)
	if player != null:
		_sync_readout(int(floor(player.frame + 0.000001)))
	if _body != null:
		_body.queue_redraw()

func grid_rect() -> Rect2:
	if _body == null:
		return Rect2()
	return Rect2(UiKit.s(TREE_W), 0.0,
		maxf(_body.size.x - UiKit.s(TREE_W), 1.0), _body.size.y)

func frame_at(x: float) -> float:
	return (x - grid_rect().position.x + scroll_x) / maxf(frame_w, 0.001)

func x_of(frame: float) -> float:
	return grid_rect().position.x + frame * frame_w - scroll_x

## The first frame the band shows. Chosen from the head bar; nought unless
## somebody has said otherwise.
func _view_lo() -> int:
	if clip == null:
		return 0
	return maxi(clip.view_from, 0)

## The last frame the band shows, or -1 for no end at all.
func _view_hi() -> int:
	if clip == null:
		return -1
	return clip.view_to

## The furthest left the grid may travel: the first frame being shown.
func _scroll_lo() -> float:
	return float(_view_lo()) * frame_w

## The furthest right it may travel.
##
## With an end chosen, that end plus a little air — the same as it always was,
## only the number now comes from the user rather than from the clip.
##
## With no end chosen, there is always one more screen ahead of wherever you
## are. That is what makes the band endless in the way that matters: you can
## keep going for as long as you keep dragging, and you can never be thrown
## somewhere far away, because a drag carries the grid exactly as far as the
## finger travels and no further.
func _scroll_hi() -> float:
	if _body == null:
		return _scroll_lo()
	var grid: Rect2 = grid_rect()
	var lo: float = _scroll_lo()
	if _view_hi() >= 0:
		return maxf(float(_view_hi() + 1) * frame_w + UiKit.s(40.0)
			- grid.size.x, lo)
	var content: float = float(_reach + 2) * frame_w + UiKit.s(40.0) \
		- grid.size.x
	return maxf(maxf(content, scroll_x + grid.size.x), lo)

func _clamp_scroll_x(value: float) -> float:
	var lo: float = _scroll_lo()
	return clampf(value, lo, maxf(_scroll_hi(), lo))

func _set_scroll_x(value: float) -> void:
	var wanted: float = _clamp_scroll_x(value)
	if absf(wanted - scroll_x) < 0.01:
		return
	scroll_x = wanted
	refresh()

## Brings a frame into view if it has been scrolled off the band. Used after a
## unit is made or picked from the list, so the thing just asked for is on
## screen rather than somewhere off to the right.
func _bring_into_view(frame: int) -> void:
	if _body == null:
		return
	var grid: Rect2 = grid_rect()
	if grid.size.x <= 1.0:
		return
	var x: float = x_of(float(frame))
	var margin: float = minf(grid.size.x * 0.3, UiKit.s(110.0))
	if x < grid.position.x + margin:
		_set_scroll_x(scroll_x - ((grid.position.x + margin) - x))
	elif x > grid.position.x + grid.size.x - margin:
		_set_scroll_x(scroll_x + (x - (grid.position.x + grid.size.x - margin)))

## The first and last frame worth drawing, so a six-hundred frame clip does
## not cost six hundred circles a redraw — and so an endless one does not cost
## an endless number of them.
func _visible_frames() -> Vector2i:
	var grid: Rect2 = grid_rect()
	var first: int = maxi(int(floor(frame_at(grid.position.x))) - 1, _view_lo())
	var last: int = int(ceil(frame_at(grid.position.x + grid.size.x))) + 1
	if _view_hi() >= 0:
		last = mini(last, _view_hi())
	return Vector2i(first, maxi(last, first))

# --------------------------------------------------------------- drawing

func _draw_body() -> void:
	TimelineDraw.draw_body(self)

func _draw_ruler(grid: Rect2) -> void:
	TimelineDraw.draw_ruler(self, grid)

func _draw_rows(grid: Rect2) -> void:
	TimelineDraw.draw_rows(self, grid)

## A layer's drawings: a line the length of the clip, and a dot on every
## frame that holds one. The line says the layer exists for the whole clip;
## the dots say where its drawings change.
## Rows are not all the same height, so how tall one is has to be asked
## rather than assumed — which is what a hard-coded ROW_H everywhere meant.
func _row_height(entry: Dictionary) -> float:
	return UiKit.s(GROUP_H) if String(entry["kind"]) == "group" \
		else UiKit.s(ROW_H)

func _draw_group_row(entry: Dictionary, grid: Rect2, y: float, f: Font) -> void:
	TimelineDraw.draw_group_row(self, entry, grid, y, f)

func _draw_cel_row(l: LayerStack.Layer, grid: Rect2, y: float) -> void:
	TimelineDraw.draw_cel_row(self, l, grid, y)

func _draw_camera_row(grid: Rect2, y: float) -> void:
	TimelineDraw.draw_camera_row(self, grid, y)

func _ease_lead(mode: int) -> float:
	return TimelineDraw.ease_lead(mode)

func _draw_playhead(grid: Rect2) -> void:
	TimelineDraw.draw_playhead(self, grid)

# ----------------------------------------------------- frame-rate units

func _unit_style() -> StyleBoxFlat:
	return TimelineDraw.unit_style(self)

func _unit_rect(one: Anim.Unit) -> Rect2:
	return TimelineDraw.unit_rect(self, one)

func _draw_units(grid: Rect2) -> void:
	TimelineDraw.draw_units(self, grid)

func _draw_unit_grip(at: Vector2, way: int, lit: bool) -> void:
	TimelineDraw.draw_unit_grip(self, at, way, lit)

# --------------------------------------------------------------- gestures

func _body_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		App.touch_mode = true
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() >= 2:
				_begin_pinch()
			else:
				_press(st.position)
		else:
			_touches.erase(st.index)
			if _mode == Mode.DRAG and _touches.is_empty():
				_mode = Mode.IDLE
				# A drag ends here rather than in `_release`, so whatever was
				# being carried has to be put down here too — otherwise the
				# next press anywhere on the band would still be holding it.
				_drag_unit = null
				_drag_focus = null
				_press_unit = null
			elif _touches.is_empty():
				_release(st.position)
		_body.accept_event()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			_update_pinch()
		else:
			_move(sd.position)
		_body.accept_event()
	elif event is InputEventMouseButton:
		if App.touch_mode:
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release(mb.position)
			_body.accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_time(1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_time(1.0 / 1.15)
	elif event is InputEventMouseMotion and _mode != Mode.IDLE:
		_move((event as InputEventMouseMotion).position)

## As in the layers panel: awake only while something is being held.
func _process(dt: float) -> void:
	_check_hold()
	_check_body_hold()
	# A finger held at the edge of the band while scrubbing keeps the band
	# travelling under it. See `_edge_follow` — this is why the loop has to
	# keep running while a scrub is live rather than only while something is
	# being held down.
	if _mode == Mode.SCRUB:
		_edge_follow(_press_at.x, dt)
		return
	if _hold_ms == 0 and _body_hold_ms == 0:
		set_process(false)

## A press held on a frame, rather than on a button — so the frame's own
## commands are reached from the frame itself.
func _check_body_hold() -> void:
	if _body_hold_ms == 0 or _mode != Mode.WAITING:
		return
	if Time.get_ticks_msec() - _body_hold_ms < HOLD_MS:
		return
	_body_hold_ms = 0
	_mode = Mode.IDLE
	# A unit held rather than tapped is a unit about to be moved. It does not
	# open a menu: sliding it is the thing a hand wants to do with it, and a
	# menu in the way would mean holding, reading, pressing and only then
	# dragging.
	if _press_unit != null:
		_drag_unit = _press_unit
		_press_unit = null
		_drag_unit_side = 0
		_mode = Mode.DRAG
		_tell_row(UiKit.label_for("Slide the unit along the band",
			"اسحب الوحدة على الشريط"))
		refresh()
		return
	if _drag_focus != null:
		_open_focus_menu(_drag_focus as Anim.Focus)
		_drag_focus = null
		return
	if _drag_camera:
		_open_camera_key_menu(_drag_frame)
	elif _drag_layer != null:
		_open_frame_menu(_drag_layer, _drag_frame)

func _press(at: Vector2) -> void:
	if player != null and player.playing:
		player.stop()
	_press_at = at
	_press_ms = Time.get_ticks_msec()
	_scroll_from = scroll_y
	_drag_layer = null
	_drag_frame = -1
	_drag_edge = false
	_drag_camera = false

	_pan_from = scroll_x
	_body_hold_ms = 0
	_drag_unit = null
	_press_unit = null
	if at.y <= UiKit.s(RULER_H):
		_mode = Mode.SCRUB
		set_process(true)
		_scrub(at.x)
		return

	# The grips first, before anything underneath them. They are drawn on top
	# of every row and they mean one thing only, so a finger that lands on one
	# should never come away holding a drawing instead.
	var grip: Dictionary = _unit_grip_at(at)
	if not grip.is_empty():
		_drag_unit = grip["unit"] as Anim.Unit
		_drag_unit_side = int(grip["side"])
		_drag_unit_grab = 0
		_mode = Mode.DRAG
		refresh()
		return

	var found: Dictionary = _dot_at(at)
	if not found.is_empty():
		_drag_focus = found.get("focus", null)
		_drag_focus_end = int(found.get("end", 1))
		if _drag_focus != null:
			# Two taps on the closing point ask what kind of softness this
			# is — the same gesture that opens a frame's own settings.
			var key: int = int(found["frame"]) * 4 + _drag_focus_end + 2
			var now: int = Time.get_ticks_msec()
			if now - _tap_ms <= DOUBLE_TAP_MS and _tap_key == key:
				_tap_ms = 0
				_tap_key = -1
				_open_focus_menu(_drag_focus as Anim.Focus)
				_drag_focus = null
				_mode = Mode.IDLE
				return
			_tap_ms = now
			_tap_key = key
		_drag_layer = found.get("layer", null)
		_drag_camera = bool(found.get("camera", false))
		_drag_edge = bool(found.get("edge", false))
		_drag_frame = int(found["frame"])
		# A drawing held under the finger has more to say than "move me",
		# and a band this size has no room for a row of small buttons. So
		# the rest of what a frame can do is behind a hold on the frame.
		_body_hold_ms = Time.get_ticks_msec()
	else:
		# Nothing of a layer's own under the finger, so a unit lying across
		# this frame is what is being touched.
		#
		# Checked after the drawings rather than before them on purpose: a
		# unit covers every row from top to bottom, so it lies over dots it
		# has nothing to do with, and dragging a drawing must go on working
		# through it. What is left is the space between the dots — which is
		# most of the box, and is where a hand reaches for the box itself.
		var over: Anim.Unit = _unit_body_at(at)
		if over != null:
			var id: int = clip.units.find(over)
			var when: int = Time.get_ticks_msec()
			if when - _unit_tap_ms <= DOUBLE_TAP_MS and _unit_tap_id == id:
				# Two taps open its rate. That is the gesture asked for, and
				# it leaves the single tap free to go on moving the playhead.
				_unit_tap_ms = 0
				_unit_tap_id = -1
				_mode = Mode.IDLE
				_open_unit_settings(over)
				return
			_unit_tap_ms = when
			_unit_tap_id = id
			_press_unit = over
			_drag_unit_grab = maxi(int(floor(frame_at(at.x)))
				- over.from_frame, 0)
			_body_hold_ms = Time.get_ticks_msec()
	_mode = Mode.WAITING
	set_process(true)

func _move(at: Vector2) -> void:
	if _mode == Mode.SCRUB:
		# Kept current so `_edge_follow` knows where the finger is holding.
		_press_at = at
		_scrub(at.x)
		return
	if _mode == Mode.WAITING:
		if _press_at.distance_to(at) <= SLOP * App.ui_scale:
			return
		_body_hold_ms = 0
		# Sideways means time, up and down means the list — whichever the
		# finger committed to first. Sideways on a drawing carries that
		# drawing; sideways on bare grid carries the whole clip past the
		# window, which is the only way to reach the end of a long scene.
		if absf(at.x - _press_at.x) > absf(at.y - _press_at.y):
			_mode = Mode.DRAG if _drag_frame >= 0 else Mode.PAN
		else:
			_mode = Mode.SCROLL
	if _mode == Mode.SCROLL:
		_set_scroll(_scroll_from - (at.y - _press_at.y))
	elif _mode == Mode.PAN:
		_set_scroll_x(_pan_from - (at.x - _press_at.x))
	elif _mode == Mode.DRAG:
		_drag_to(at.x)

func _release(at: Vector2) -> void:
	var was: int = _mode
	_mode = Mode.IDLE
	_body_hold_ms = 0
	_press_unit = null
	if _drag_unit != null:
		_drag_unit = null
		if was == Mode.DRAG:
			refresh()
			return
	if _drag_focus != null and was == Mode.DRAG:
		_drag_focus = null
		return
	if was == Mode.WAITING:
		_tap(at)
	_drag_layer = null
	_drag_frame = -1
	_drag_edge = false
	refresh()

func _tap(at: Vector2) -> void:
	if at.x < UiKit.s(TREE_W):
		var entry: Dictionary = _row_at(at.y)
		if entry.is_empty() or entry["kind"] != "layer":
			return
		var index: int = int(entry["index"])
		# First tap chooses the layer, second opens what belongs to it here.
		#
		# Two taps rather than one because the first tap has a job already —
		# choosing which layer the frame buttons act on — and because these
		# are a layer's *timeline* settings, which are not the same list as
		# its settings in the layers panel. Sound belongs to a layer's place
		# in time; opacity belongs to its place in the stack.
		#
		# Only on the name strip. A tap on the frames is scrubbing and must
		# stay scrubbing: a sheet opening under a thumb that meant to move
		# the playhead is the kind of interruption that makes a timeline
		# feel unsafe to touch.
		if index == stack.active_index and _layer_sheet_ready():
			_open_layer_settings(index)
			return
		stack.set_active(index)
		refresh()
		return
	# Anywhere in the grid moves the playhead. Scrubbing should not demand
	# the ruler when the whole row means the same thing.
	var entry2: Dictionary = _row_at(at.y)
	if not entry2.is_empty() and entry2["kind"] == "layer":
		stack.set_active(int(entry2["index"]))
	_scrub(at.x)

## Whether there is anything worth showing for a layer yet.
##
## Kept as its own question so the second tap does nothing rather than
## opening an empty sheet while the contents of that sheet are still being
## built. A control that opens onto nothing teaches people not to press it.
func _layer_sheet_ready() -> bool:
	return true

## This layer's sounds: what plays over it, and when.
##
## Music and effects, nothing else. A sound here is not attached to a drawing
## and does not shape one — it starts at a frame and plays. That is the whole
## of it, and it is deliberately the whole of it: the two jobs used to be one
## control, and one control that sometimes redraws your artwork is not a
## control anybody presses twice.
##
## The layer is only where the list is kept, so eight characters' worth of
## footsteps stay eight separate lists instead of one heap. Everything mixes
## together at export.
##
## Built with the same `_sheet` / `_sheet_column` pair every other sheet in
## this panel uses, so it floats, scrolls and dismisses exactly like they do.
func _open_layer_settings(index: int) -> void:
	if stack == null or index < 0 or index >= stack.layers.size():
		return
	var l: LayerStack.Layer = stack.layers[index]
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet, l.title)

	var add: Button = UiKit.make_text_button(
		UiKit.label_for("Import audio", "استيراد صوت"), true)
	add.pressed.connect(func() -> void:
		_shut_sheet()
		audio_wanted.emit(index))
	v.add_child(add)
	_sheet_note(v, UiKit.label_for(
		"Music and sound effects. MP3, M4A, AAC, FLAC, OGG, Opus, WMA, AIFF, WAV and more — several files at once.",
		"موسيقى ومؤثرات صوتية. MP3 وM4A وAAC وFLAC وOGG وOpus وWMA وAIFF وWAV وغيرها — عدّة ملفات دفعة واحدة."))

	var track: AudioTrack = clip.audio if clip != null else null
	if track == null:
		_float_sheet(sheet)
		return
	var mine: Array = track.for_layer(l.id)
	if mine.is_empty():
		_float_sheet(sheet)
		return

	v.add_child(HSeparator.new())
	for c in mine:
		TimelineAudio.row(v, track, c as AudioTrack.Clip, maxi(_reach + 1, 48),
			func() -> void: _dirty(),
			func() -> void: refresh(),
			func() -> void: _shut_sheet())
	_float_sheet(sheet)

func _row_at(y: float) -> Dictionary:
	var local: float = y - UiKit.s(RULER_H) + scroll_y
	for entry in _rows:
		var top: float = float(entry["y"])
		if local >= top and local < top + _row_height(entry):
			return entry
	return {}

func _dot_at(at: Vector2) -> Dictionary:
	var entry: Dictionary = _row_at(at.y)
	if entry.is_empty():
		return {}
	var reach: float = maxf(UiKit.s(12.0), frame_w * 0.5)
	if String(entry["kind"]) == "group":
		return {}
	if entry["kind"] == "camera":
		for s in clip.shots:
			if absf(x_of(float((s as Anim.Shot).frame)) - at.x) <= reach:
				return {"camera": true, "frame": (s as Anim.Shot).frame}
		return {}

	var l: LayerStack.Layer = entry["layer"]

	# The focus line sits a little above the layer's own, so it is checked
	# first — a finger reaching for it should never come away holding a
	# drawing instead.
	var lift: float = float(entry["y"]) + UiKit.s(ROW_H) * 0.5 - UiKit.s(7.0)
	var local_y: float = at.y - UiKit.s(RULER_H) + scroll_y
	if absf(local_y - lift) <= UiKit.s(9.0):
		for f in clip.focus_for(l.id):
			var one: Anim.Focus = f as Anim.Focus
			if absf(x_of(float(one.to_frame)) - at.x) <= reach:
				return {"focus": one, "end": 1, "frame": one.to_frame}
			if absf(x_of(float(one.from_frame)) - at.x) <= reach:
				return {"focus": one, "end": 0, "frame": one.from_frame}

	# The right edge first: it is a separate grip, and it lengthens the hold
	# rather than moving the drawing somewhere else.
	for frame in l.cels.frames():
		var one: int = int(frame)
		var held: int = l.cels.hold_length(one, _reach + 1)
		if absf(x_of(float(one + held)) - at.x) <= UiKit.s(11.0):
			return {"layer": l, "frame": one, "edge": true}
	for frame2 in l.cels.frames():
		if absf(x_of(float(int(frame2))) - at.x) <= reach:
			return {"layer": l, "frame": int(frame2), "edge": false}
	return {}

## Dragging a focus point stretches the line rather than moving it whole: the
## first point is where focus arrives and the second is where it leaves, and
## each is dragged to wherever that should be.
func _drag_focus_to(x: float) -> void:
	if _drag_focus == null:
		return
	var one: Anim.Focus = _drag_focus as Anim.Focus
	var want: int = clampi(int(round(frame_at(x))), 0, Anim.CEILING_FRAMES - 1)
	if _drag_focus_end == 0:
		one.from_frame = mini(want, one.to_frame)
	else:
		one.to_frame = maxi(want, one.from_frame)
	clip.grow_to_fit(stack, one.to_frame)
	_apply_focus()
	_dirty()
	refresh()

## The grip under a finger, if there is one.
##
## Generous on both axes, because these are the controls of a shape that has
## no other controls: eleven points of drawn circle against a band of thirty
## either side of the middle. A grip that has to be aimed at is a grip that
## gets missed, and missing it scrubs the playhead instead — which is exactly
## the kind of small betrayal that makes a timeline feel unsafe to touch.
func _unit_grip_at(at: Vector2) -> Dictionary:
	if clip == null or _body == null or clip.units.is_empty():
		return {}
	var top: float = UiKit.s(RULER_H)
	if at.y < top or at.x < grid_rect().position.x:
		return {}
	var mid: float = top + maxf(_body.size.y - top, 1.0) * 0.5
	if absf(at.y - mid) > UiKit.s(30.0):
		return {}
	var reach: float = UiKit.s(GRIP_REACH)
	var lowest: int = _view_lo()
	# Nearest first, so two units meeting edge to edge hand the finger the
	# grip it is actually on rather than whichever comes first in the list.
	var best: Dictionary = {}
	var gap: float = reach + 1.0
	for u in clip.units:
		var one: Anim.Unit = u
		var to_gap: float = absf(x_of(float(one.to_frame + 1)) - at.x)
		if to_gap <= reach and to_gap < gap:
			gap = to_gap
			best = {"unit": one, "side": 1}
		if one.from_frame <= lowest:
			continue
		var from_gap: float = absf(x_of(float(one.from_frame)) - at.x)
		if from_gap <= reach and from_gap < gap:
			gap = from_gap
			best = {"unit": one, "side": -1}
	return best

## The unit lying across the frame under a finger, if any.
func _unit_body_at(at: Vector2) -> Anim.Unit:
	if clip == null or _body == null:
		return null
	if at.x < grid_rect().position.x or at.y < UiKit.s(RULER_H):
		return null
	return clip.unit_at(int(floor(frame_at(at.x))))

## Resizing or sliding a unit, to the frame under the finger.
##
## Everything here is clamped against what the unit's neighbours leave it, so
## two units can meet exactly edge to edge and can never climb on top of one
## another — however hard the drag is pushed past the one next door. Sliding
## keeps the unit's length: a unit pushed against its neighbour stops there
## rather than being squashed.
func _drag_unit_to(x: float) -> void:
	var one: Anim.Unit = _drag_unit
	if one == null or clip == null:
		return
	var room: Vector2i = clip.unit_room(one)
	var floor_frame: int = maxi(room.x, _view_lo())
	var roof: int = room.y
	if _view_hi() >= 0:
		roof = mini(roof, _view_hi())
	if roof < floor_frame:
		return
	var want: int = int(round(frame_at(x)))
	var changed: bool = false

	if _drag_unit_side > 0:
		# The right grip sits on the far edge of the last frame, which is one
		# past the frame it holds — so what it is pointing at is `want - 1`.
		var to_frame: int = clampi(want - 1, one.from_frame, roof)
		if to_frame != one.to_frame:
			one.to_frame = to_frame
			changed = true
	elif _drag_unit_side < 0:
		var from_frame: int = clampi(want, floor_frame, one.to_frame)
		if from_frame != one.from_frame:
			one.from_frame = from_frame
			changed = true
	else:
		var run: int = one.count()
		var start: int = clampi(want - _drag_unit_grab, floor_frame,
			maxi(roof - run + 1, floor_frame))
		if start != one.from_frame:
			one.from_frame = start
			one.to_frame = start + run - 1
			changed = true

	if not changed:
		return
	clip.sort_units()
	clip.grow_to_fit(stack, one.to_frame)
	_dirty()
	_tell_unit(one)
	refresh()

## The unit's own numbers, in the place the frame count normally sits, so a
## drag can be judged without looking anywhere else on the screen.
func _tell_unit(one: Anim.Unit) -> void:
	_tell_row(Lang.digits("%d–%d  ·  %d f  ·  %.2fs"
		% [one.from_frame + 1, one.to_frame + 1, one.count(), one.seconds()]))

func _drag_to(x: float) -> void:
	if _drag_unit != null:
		_drag_unit_to(x)
		return
	if _drag_focus != null:
		_drag_focus_to(x)
		return
	var to: int = clampi(int(round(frame_at(x))), 0, maxi(clip.length - 1, 0))
	# The edge grip is measured from the end of the hold, not from the
	# drawing's own frame, so it must not be turned away by this guard.
	if to == _drag_frame and not _drag_edge:
		return
	if _drag_camera:
		var shot: Anim.Shot = clip.shot_at(_drag_frame)
		if shot == null or clip.shot_at(to) != null:
			return
		clip.drop_shot(_drag_frame)
		clip.set_shot(to, shot.offset, shot.zoom, shot.ease_mode, shot.rotation)
	elif _drag_layer != null and _drag_edge:
		# Lengthening a hold pushes everything after it along, so the
		# drawings that follow keep their own durations instead of being
		# eaten by the one being stretched.
		var held: int = _drag_layer.cels.hold_length(_drag_frame, _reach + 1)
		var wanted: int = clampi(to - _drag_frame, 1, 600)
		if wanted == held:
			return
		_drag_layer.cels.shift_after(_drag_frame, wanted - held)
		clip.length = maxi(clip.length, _drag_frame + wanted)
		# A hold dragged out past the last drawing is the one piece of timing
		# nothing else in the file remembers: no cel sits at its far end, so
		# working the scene's extent out from its contents would cut it back
		# to the drawing it started from the moment the project was reopened.
		clip.tail_hold = maxi(clip.tail_hold, _drag_frame + wanted - 1)
		_dirty()
		player.refresh_visuals()
		refresh()
		return
	elif _drag_layer != null:
		if _drag_layer.cels.has_frame(to):
			return
		_drag_layer.cels.move_frame(_drag_frame, to)
	_drag_frame = to
	player.apply()
	refresh()

func _begin_pinch() -> void:
	_mode = Mode.IDLE
	_body_hold_ms = 0
	_drag_layer = null
	_drag_frame = -1
	_drag_edge = false
	# A second finger arriving means the band is being zoomed, not that a
	# unit is being dragged. Whatever was in hand is put down rather than
	# being carried along by the pinch.
	_drag_unit = null
	_press_unit = null
	_pinch_span = _span()
	_pinch_from = frame_w

func _update_pinch() -> void:
	var span: float = _span()
	if _pinch_span < 8.0 or span < 8.0:
		return
	# The frame between the fingers is the one being held on to, so the
	# clip is scrolled to keep it where it was rather than letting the
	# whole scene slide away from under the pinch.
	var anchor: float = frame_at(_pinch_mid_x())
	frame_w = clampf(_pinch_from * (span / _pinch_span), MIN_FRAME_W, MAX_FRAME_W)
	var grid: Rect2 = grid_rect()
	scroll_x = _clamp_scroll_x(anchor * frame_w
		- (_pinch_mid_x() - grid.position.x))
	refresh()

func _pinch_mid_x() -> float:
	var keys: Array = _touches.keys()
	if keys.size() < 2:
		return grid_rect().get_center().x
	return ((_touches[keys[0]] as Vector2).x + (_touches[keys[1]] as Vector2).x) * 0.5

func _span() -> float:
	var keys: Array = _touches.keys()
	if keys.size() < 2:
		return 0.0
	return (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]] as Vector2)

func _zoom_time(factor: float) -> void:
	frame_w = clampf(frame_w * factor, MIN_FRAME_W, MAX_FRAME_W)
	scroll_x = _clamp_scroll_x(scroll_x)
	refresh()

## Moves the playhead, anywhere the band is showing.
##
## The band has no end now, so neither does this: scrubbing out past the last
## drawing takes the scene with it rather than stopping at a wall. That is
## what makes the empty grid to the right usable — you can go and stand on
## frame four hundred and start drawing there.
##
## Growing the scene this way is safe because what *plays* is worked out from
## the drawings in it, not from how far anybody has scrolled. Going to look at
## an empty stretch never adds an empty stretch to the film.
## Dragging the ruler, with the band following the finger past its own edge.
##
## A drag used to stop at the edge of the band. To reach frame four hundred you
## scrubbed to the right-hand edge, lifted, panned, put the finger down and
## scrubbed again — and every lift is a chance to lose the place you were
## aiming for.
##
## Now the band travels. Hold in the last stretch before either edge and the
## whole band slides that way underneath the finger, faster the closer to the
## edge it is held. Come back inside, or let go, and it stops at once.
##
## The rate is in frames per second rather than pixels, so it means the same at
## every zoom — a pixel rate would crawl on a band showing twenty frames and
## bolt on one showing four hundred. Squared, so the first millimetre past the
## line is a nudge and the last is a sweep.
func _edge_follow(x: float, delta: float) -> void:
	if _mode != Mode.SCRUB or delta <= 0.0:
		return
	var grid: Rect2 = grid_rect()
	if grid.size.x < 40.0:
		return
	var margin: float = minf(UiKit.s(56.0), grid.size.x * 0.22)
	var push: float = 0.0
	if x < grid.position.x + margin:
		push = -(grid.position.x + margin - x) / margin
	elif x > grid.position.x + grid.size.x - margin:
		push = (x - (grid.position.x + grid.size.x - margin)) / margin
	if is_zero_approx(push):
		return
	# Squared, so the first millimetre past the line is a nudge and the last
	# is a sweep. A linear ramp makes the whole margin feel like one speed.
	push = clampf(push, -1.0, 1.0)
	var rate: float = push * absf(push) * FOLLOW_FPS * delta * frame_w
	_set_scroll_x(scroll_x + rate)
	_scrub(x)

func _scrub(x: float) -> void:
	if player == null or clip == null:
		return
	# The moment to wait for has passed. A pose held back for its second of
	# stillness belongs to the frame it was made on, so it is written before
	# the playhead leaves that frame rather than landing on the new one.
	BoneHandle.flush(view)
	var want: float = frame_at(x)
	var lowest: float = float(_view_lo())
	if _view_hi() >= 0:
		want = clampf(want, lowest, float(_view_hi()))
	else:
		want = maxf(want, lowest)
	var index: int = int(round(want))
	if index > clip.length - 1:
		clip.grow_to_fit(stack, index)
	player.seek(want)

func _set_scroll(value: float) -> void:
	var span: float = maxf(_content_h - (_body.size.y - UiKit.s(RULER_H)), 0.0)
	scroll_y = clampf(value, 0.0, span)
	refresh()

func _open_animation_layer_picker() -> void:
	if stack == null:
		return
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		UiKit.label_for("Choose animation layer", "اختيار طبقة الرسوم المتحركة"))
	for i in range(stack.layers.size() - 1, -1, -1):
		var layer: LayerStack.Layer = stack.layers[i]
		var index: int = i
		var b: Button = UiKit.make_text_button(layer.title, index == stack.active_index)
		b.toggle_mode = true
		b.set_pressed_no_signal(index == stack.active_index)
		b.pressed.connect(func() -> void:
			stack.set_active(index)
			_shut_sheet()
			refresh())
		v.add_child(b)
	_float_sheet(sheet)

# ------------------------------------------------------------- the frames

## A drawing on this layer at this frame — never a new layer.
##
## `carry_on` starts it from the drawing before it, which is what tracing a
## movement wants; blank is what a fresh pose wants. Those are the two ways,
## and there is no third.
## Adding a frame — except where frames are not the way the layer moves.
##
## On a rigged layer this walks forward and does nothing else: it does not
## make a frame, and it does not touch the one that is there. The drawing
## stays exactly as it was and the playhead moves on, which is all that was
## wanted from the button in the first place on a layer that is posed rather
## than redrawn.
## A step, with the ghosts brought up behind it.
##
## Onion skin is turned on rather than toggled, and only in one direction:
## stepping never turns it off. If you have deliberately switched the ghosts
## off, the onion button is where you do that and it stays done — but arriving
## at an empty frame with nothing to draw against is not a state anybody
## chooses on purpose, and it was one button away every single time.
##
## At least one frame back, too. The ghosts being *on* with a look-back of
## nought shows nothing at all, which looks exactly like the feature being
## broken.
func _step_frame(by: int) -> void:
	if player == null:
		return
	player.step(by)
	if not player.onion:
		player.onion = true
		player.onion_back = maxi(player.onion_back, 1)
		if _onion_btn != null and is_instance_valid(_onion_btn):
			_onion_btn.button_pressed = true
		_dirty()
	player.refresh_visuals()
	refresh()

func _add_frame(carry_on: bool) -> void:
	if stack != null and stack.active_frames_locked():
		# A posed layer does not gain a *drawing* frame — but it should gain
		# a **key**, carried forward from where the pose is now.
		#
		# This is the correction to what the button used to do. It walked
		# the playhead on and left the skeleton behind, so the very next
		# bend keyed a pose with nothing before it to travel from, and the
		# character snapped into place instead of moving into it. What the
		# button means on a rigged layer is Duplicate After: the same pose,
		# one frame later, as a place to change something.
		#
		# Never a blank key. A blank key on a rigged layer is a character
		# collapsing to its rest pose for one frame, which is the single
		# most alarming thing a timeline can do.
		if _duplicate_pose_forward():
			return
		var here: int = int(round(player.frame))
		player.seek(float(clampi(here + 1, 0, maxi(clip.length - 1, 0))))
		_flash_locked()
		refresh()
		return
	_add_frame_now(carry_on)

func _duplicate_pose_forward() -> bool:
	return TimelinePoseFrames.duplicate_pose_forward(self)

func _flash_locked() -> void:
	var l: LayerStack.Layer = stack.layers[clampi(stack.active_index, 0,
		stack.layers.size() - 1)] if not stack.layers.is_empty() else null
	if l != null and not l.rig.is_empty():
		_tell_row(UiKit.label_for(
			"This layer is posed, not redrawn — moved on a frame instead",
			"هذه الطبقة تُحرَّك بالوضعيات لا بالرسم — تقدّم إطاراً بدل ذلك"))
	else:
		_tell_row(UiKit.label_for(
			"Animation folder — frames come from the layers inside it",
			"مجلد تحريك — الإطارات تأتي من الطبقات التي بداخله"))

func _tell_row(text: String) -> void:
	if _readout != null:
		_readout.text = text

func _add_frame_now(carry_on: bool) -> void:
	if stack == null or player == null or clip == null:
		return
	var index: int = stack.active_index
	if index < 0 or index >= stack.layers.size():
		return
	var l: LayerStack.Layer = stack.layers[index]
	var frame: int = clampi(int(floor(player.frame + 0.000001)), 0, maxi(clip.length - 1, 0))

	# Frame 0 is always the real first cel. If the user already drew there,
	# keep that drawing and never turn it into another page.
	if frame == 0 and l.cels.is_empty():
		l.cels.capture_surface(l.surface, 0)
		player.frame = 0.0
		player.onion = false
		player.refresh_visuals()
		stack.changed.emit()
		_dirty()
		rebuild()
		return

	# Duplicate After is explicit: the new cel is placed at frame + 1 only
	# when that destination is genuinely empty. An existing drawing is never
	# overwritten; the insert command handles that case by shifting it right.
	var target: int = frame + 1
	if target >= clip.length:
		clip.grow_to_fit(stack, target)
	if not l.cels.has_frame(frame):
		l.cels.capture_surface(l.surface, frame)
	if l.cels.has_frame(target):
		return
	l.cels.add_frame(l.surface, target, carry_on)
	_carry_pose(l, frame, target)
	player.frame = float(target)
	player.onion = true
	player.refresh_visuals()
	stack.changed.emit()
	_dirty()
	rebuild()

func _carry_pose(l: LayerStack.Layer, frame: int, target: int) -> void:
	TimelinePoseFrames.carry_pose(l, frame, target)

## Same rule as the frame button: a posed layer does not gain blank frames
## from anywhere, not from the button and not from a menu behind it.
func _insert_blank_after_current() -> void:
	if stack != null and stack.active_frames_locked():
		_flash_locked()
		return
	_insert_blank_now()

func _insert_blank_now() -> void:
	if stack == null or player == null or clip == null:
		return
	var current: int = clampi(int(floor(player.frame + 0.000001)), 0, maxi(clip.length - 1, 0))
	stack.insert_blank_frame_after(current)
	clip.insert_frame_after(current)
	# The clip has now grown by one frame, and all content after the insertion
	# point moved to the right. Activate the inserted blank frame.
	player.frame = float(current + 1)
	player.onion = true
	player.onion_back = maxi(player.onion_back, 1)
	player.refresh_visuals()
	_dirty()
	rebuild()

## What a single drawing can do, reached by holding that drawing.
##
## Until now a frame could be added and moved but never taken back, so a
## mistaken frame stayed in the scene for good. Delete is the reason this
## menu exists; the rest is here because the finger is already on the frame.
func _open_frame_menu(l: LayerStack.Layer, frame: int) -> void:
	if l == null or clip == null:
		return
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		"%s %d" % [UiKit.label_for("Frame", "فريم"), frame + 1])
	_sheet_note(v, l.title)

	var go: Button = UiKit.make_text_button(
		UiKit.label_for("Go to this frame", "اذهب إلى هذا الإطار"), true)
	go.pressed.connect(func() -> void:
		_shut_sheet()
		player.seek(float(frame)))
	v.add_child(go)

	var copy: Button = UiKit.make_text_button(
		UiKit.label_for("Duplicate after", "نسخ بعده"), true)
	copy.pressed.connect(func() -> void:
		_shut_sheet()
		player.seek(float(frame))
		_add_frame(true))
	v.add_child(copy)

	var blank: Button = UiKit.make_text_button(
		UiKit.label_for("Insert blank after current", "وضع إطار فارغ بعد الحالي"), true)
	blank.pressed.connect(func() -> void:
		_shut_sheet()
		player.seek(float(frame))
		_insert_blank_after_current())
	v.add_child(blank)

	var wipe: Button = UiKit.make_text_button(
		UiKit.label_for("Clear this drawing", "امسح هذا الرسم"), true)
	wipe.pressed.connect(func() -> void:
		_shut_sheet()
		_clear_frame(l, frame))
	v.add_child(wipe)
	_sheet_note(v, UiKit.label_for(
		"The frame stays where it is and keeps its timing. Only the drawing on it goes.",
		"يبقى الإطار مكانه ويحتفظ بتوقيته، ولا يذهب إلا الرسم الذي عليه."))

	# Frame zero is the layer's own drawing. Removing it would leave the
	# layer with a track and nothing in it, so it is emptied instead.
	if frame > 0:
		var armed: Array = [false]
		var kill: Button = UiKit.make_text_button(
			UiKit.label_for("Delete frame", "احذف الإطار"), true)
		kill.pressed.connect(func() -> void:
			if not armed[0]:
				armed[0] = true
				kill.text = UiKit.label_for("Tap again to delete",
					"اضغط ثانية للحذف")
				return
			_shut_sheet()
			_delete_frame(l, frame))
		v.add_child(kill)
	_float_sheet(sheet)

func _clear_frame(l: LayerStack.Layer, frame: int) -> void:
	if l == null or player == null:
		return
	stack.commit_all_cels()
	l.cels.cels[frame] = {"png": PackedByteArray(), "at": Vector2i.ZERO,
		"size": Vector2i.ZERO}
	if l.cels.loaded == frame:
		l.surface.clear_all()
	player.apply(true, false)
	player.refresh_visuals()
	stack.changed.emit()
	_dirty()
	rebuild()

func _delete_frame(l: LayerStack.Layer, frame: int) -> void:
	if l == null or player == null or frame <= 0:
		return
	stack.commit_all_cels()
	l.cels.remove_frame(frame)
	# The playhead may have been standing on what just went; the drawing
	# that holds through this moment is loaded in its place rather than
	# leaving the layer showing nothing.
	player.apply(true, false)
	player.refresh_visuals()
	stack.changed.emit()
	_dirty()
	rebuild()

## The camera key under the finger — moved by dragging it, removed here.
func _open_camera_key_menu(frame: int) -> void:
	if clip == null:
		return
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		"%s %d" % [UiKit.label_for("Camera key", "مفتاح الكاميرا"), frame + 1])

	var go: Button = UiKit.make_text_button(
		UiKit.label_for("Go to this frame", "اذهب إلى هذا الإطار"), true)
	go.pressed.connect(func() -> void:
		_shut_sheet()
		player.seek(float(frame)))
	v.add_child(go)

	var recut: Button = UiKit.make_text_button(
		UiKit.label_for("Reframe from the canvas", "أعد التأطير من اللوحة"), true)
	recut.pressed.connect(func() -> void:
		_shut_sheet()
		player.seek(float(frame))
		if view != null and not view.camera_edit:
			_toggle_camera_edit())
	v.add_child(recut)

	# The curve belongs to the key it leaves from, so it is set here rather
	# than only for the whole scene at once: a shot can build into one move
	# and settle out of the next.
	_vlabel(v, UiKit.label_for("Travel to the next key", "الانتقال إلى المفتاح التالي"))
	var here: Anim.Shot = clip.shot_at(frame)
	var current: int = here.ease_mode if here != null else Anim.Ease.SMOOTH
	for row in _ease_choices():
		var mode: int = int(row[0])
		var b: Button = UiKit.make_text_button(String(row[1]), true)
		b.toggle_mode = true
		b.set_pressed_no_signal(mode == current)
		b.pressed.connect(func() -> void:
			var target: Anim.Shot = clip.shot_at(frame)
			if target != null:
				target.ease_mode = mode
			player.apply(true, false)
			_dirty()
			_shut_sheet()
			rebuild())
		v.add_child(b)

	var armed: Array = [false]
	var kill: Button = UiKit.make_text_button(
		UiKit.label_for("Delete camera key", "احذف مفتاح الكاميرا"), true)
	kill.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			kill.text = UiKit.label_for("Tap again to delete", "اضغط ثانية للحذف")
			return
		_shut_sheet()
		clip.drop_shot(frame)
		if _last_key_frame == frame:
			_last_key_frame = -1
		player.apply(true, false)
		_dirty()
		rebuild())
	v.add_child(kill)
	_float_sheet(sheet)

func _open_frame_settings() -> void:
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		UiKit.label_for("Frame insertion", "إضافة إطار"))

	var copy: Button = UiKit.make_text_button(
		UiKit.label_for("Duplicate after", "نسخ بعده"), true)
	copy.pressed.connect(func() -> void:
		_shut_sheet()
		_add_frame(true))
	v.add_child(copy)
	_sheet_note(v, UiKit.label_for(
		"Copies the current drawing into the next empty frame. It never overwrites an existing frame.",
		"ينسخ الرسم الحالي إلى الإطار الفارغ التالي ولا يكتب فوق إطار موجود."))

	var insert_blank: Button = UiKit.make_text_button(
		UiKit.label_for("Insert blank after current", "وضع إطار فارغ بعد الحالي"), true)
	insert_blank.pressed.connect(func() -> void:
		_shut_sheet()
		_insert_blank_after_current())
	v.add_child(insert_blank)
	_sheet_note(v, UiKit.label_for(
		"If another drawn frame already exists immediately after the current one, it is shifted right and the new blank frame is inserted between them.",
		"إذا كان هناك فريم مرسوم مباشرة بعد الحالي، يُزاح إلى اليمين ويُدرج الفريم الفارغ بينهما."))
	_float_sheet(sheet)

# ------------------------------------------------------------ depth of field

## Puts a focus line on the chosen layer.
##
## It opens as a short span — two points close together, just above the
## layer's own line — and is dragged out to however long the shot holds focus
## there. Everything without a line of its own goes soft for as long as this
## one runs, which is what depth of field *is*: choosing the subject and
## choosing the blur are one act.
func _add_focus() -> void:
	if clip == null or stack == null or stack.layers.is_empty():
		return
	var l: LayerStack.Layer = stack.layers[clampi(stack.active_index, 0,
		stack.layers.size() - 1)]
	var here: int = clampi(int(round(player.frame)), 0, maxi(clip.length - 1, 0))
	for f in clip.focus_for(l.id):
		var one: Anim.Focus = f as Anim.Focus
		if here >= one.from_frame and here <= one.to_frame:
			_tell_row(UiKit.label_for("This layer is already the subject here",
				"هذه الطبقة هي الموضوع هنا بالفعل"))
			return
	clip.add_focus(l.id, here, here + 2)
	clip.grow_to_fit(stack, here + 2)
	_apply_focus()
	_dirty()
	rebuild()

## Hands the current focus to the layers, so what is on the band and what is
## on the canvas are the same thing.
func _apply_focus() -> void:
	if stack == null or clip == null or player == null:
		return
	stack.apply_focus(clip, int(floor(player.frame + 0.000001)))

func _draw_focus_row(l: LayerStack.Layer, grid: Rect2, y: float) -> void:
	TimelineDraw.draw_focus_row(self, l, grid, y)

## What kind of softness this line brings on.
func _open_focus_menu(one: Anim.Focus) -> void:
	TimelineFocusMenu.open(self, one)

func _camera_button() -> void:
	if clip == null or view == null:
		return
	if not clip.camera_on:
		_add_camera_track()
		return
	_add_camera_key()

func _add_camera_track() -> void:
	clip.camera_on = true
	# Composing starts immediately: a camera with no frame drawn on the page
	# is a row of dots with nothing to aim.
	view.set_camera_edit(true)
	if _camera_btn != null:
		_camera_btn.set_pressed_no_signal(true)
		_camera_btn.tooltip_text = UiKit.label_for("Add camera key",
			"إضافة مفتاح كاميرا")
	_add_camera_key()
	_dirty()
	rebuild()

## Keyed from the frame as it is drawn on screen, never from numbers typed
## at it. That is the difference between a camera you compose and a camera
## you configure.
##
## A key holds the whole pose at one moment: where the frame sits, how much
## of the page it keeps, and how far it is turned. Two keys are a move —
## everything between them is filled in from the two poses and the curve on
## the earlier key, at whatever rate the scene runs at.
func _add_camera_key() -> void:
	if clip == null or player == null or view == null:
		return
	if not view.camera_edit:
		view.set_camera_edit(true)
	var now: Dictionary = view.camera_values()
	if now.is_empty():
		return
	var frame: int = clampi(int(round(player.frame)), 0, maxi(clip.length - 1, 0))
	var ease_mode: int = _default_ease
	var here: Anim.Shot = clip.shot_at(frame)
	if here != null:
		ease_mode = here.ease_mode
	clip.set_shot(frame, Vector2(float(now["x"]), float(now["y"])),
		float(now["zoom"]), ease_mode, float(now.get("rotation", 0.0)))
	_last_key_frame = frame
	_dirty()
	rebuild()

## While the shot is being composed on the canvas, what the hand does goes
## into the key at the playhead.
##
## The old behaviour tried to guess a second key somewhere ahead of you and
## wrote into that instead, so framing a shot could move a key you were not
## looking at. A key belongs to the moment it was made at, and nowhere else.
## Nothing is keyed unless composing is switched on, so scrubbing a scene
## can never leave keys behind it.
func _camera_changed(_shot: Rect2) -> void:
	if clip == null or player == null or view == null:
		return
	if not clip.camera_on or not view.camera_edit:
		return
	var now: Dictionary = view.camera_values()
	if now.is_empty():
		return
	var frame: int = clampi(int(round(player.frame)), 0, maxi(clip.length - 1, 0))
	var here: Anim.Shot = clip.shot_at(frame)
	var ease_mode: int = here.ease_mode if here != null else _default_ease
	clip.set_shot(frame, Vector2(float(now["x"]), float(now["y"])),
		float(now["zoom"]), ease_mode, float(now.get("rotation", 0.0)))
	_last_key_frame = frame
	player.apply(true, false)
	_dirty()
	rebuild()

func _toggle_camera_edit() -> void:
	if view == null or clip == null:
		return
	if not clip.camera_on:
		_add_camera_track()
		return
	view.set_camera_edit(not view.camera_edit)
	if _camera_btn != null:
		_camera_btn.set_pressed_no_signal(view.camera_edit)
	refresh()

## The list of curves, in one place, so the sheet and the key menu can
## never drift apart.
func _ease_choices() -> Array:
	return [
		[Anim.Ease.SMOOTH, UiKit.label_for("Ease in and out", "تسارع وتباطؤ")],
		[Anim.Ease.IN, UiKit.label_for("Ease in — start slowly", "تسارع — يبدأ ببطء")],
		[Anim.Ease.OUT, UiKit.label_for("Ease out — arrive slowly", "تباطؤ — يصل ببطء")],
		[Anim.Ease.LINEAR, UiKit.label_for("Even speed", "سرعة ثابتة")],
		[Anim.Ease.HOLD, UiKit.label_for("Hard cut", "قطع حاد")],
	]

## How the camera travels between its keys.
##
## Two keys and the frames between them are the whole of a camera move: the
## app measures how far along each in-between frame is and bends that
## number by the curve chosen here. A straight line reads as machinery; a
## shot that leaves slowly and arrives slowly reads as a camera someone is
## holding.
func _open_camera_curves() -> void:
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		UiKit.label_for("Camera", "الكاميرا"))
	_sheet_note(v, UiKit.label_for(
		"Key the first shot, go to a later frame, frame it again. Every frame between the two is filled in for you at the scene's own rate.",
		"ثبّت اللقطة الأولى، ثم اذهب إلى إطار لاحق وأعد التأطير. وكل إطار بينهما يُملأ لك تلقائياً بمعدل المشهد نفسه."))

	_vlabel(v, UiKit.label_for("New keys use", "المفاتيح الجديدة تستخدم"))
	var buttons: Array = []
	var choices: Array = _ease_choices()
	for i in choices.size():
		var mode: int = int(choices[i][0])
		var index: int = i
		var b: Button = UiKit.make_text_button(String(choices[i][1]), true)
		b.toggle_mode = true
		b.set_pressed_no_signal(mode == _default_ease)
		b.pressed.connect(func() -> void:
			_default_ease = mode
			for k in buttons.size():
				(buttons[k] as Button).set_pressed_no_signal(k == index))
		buttons.append(b)
		v.add_child(b)

	v.add_child(HSeparator.new())
	_vlabel(v, UiKit.label_for("Set every key at once", "طبّق على كل المفاتيح"))
	for row in choices:
		var all_mode: int = int(row[0])
		var apply_all: Button = UiKit.make_text_button(String(row[1]), true)
		apply_all.pressed.connect(func() -> void:
			_default_ease = all_mode
			_set_camera_ease(all_mode)
			_shut_sheet())
		v.add_child(apply_all)
	_sheet_note(v, UiKit.label_for(
		"A single key can still be set on its own: hold it on the camera row.",
		"ويمكن ضبط مفتاح واحد بمفرده: اضغط عليه مطولاً في صف الكاميرا."))
	_float_sheet(sheet)

func _set_camera_ease(ease_mode: int) -> void:
	for s in clip.shots:
		(s as Anim.Shot).ease_mode = ease_mode
	player.apply()
	_dirty()
	rebuild()

# -------------------------------------------------------------- the rest

func _toggle_onion() -> void:
	if player == null:
		return
	player.onion = not player.onion
	player.refresh_visuals()
	_dirty()
	refresh()

## Four pairs, and each pair is one colour and its opposite.
##
## Behind and ahead have to be told apart in a glance while a hand is
## moving, so they are never two shades of one idea: pick a colour for the
## drawings behind you and the one for the drawings ahead is its opposite
## on the wheel. Strong and flat, because a ghost is competing with the ink
## on top of it.
const ONION_PAIRS: Array = [
	[Color(0.94, 0.16, 0.26, 0.52), Color(0.10, 0.72, 0.94, 0.50)],
	[Color(0.98, 0.45, 0.05, 0.52), Color(0.16, 0.34, 0.95, 0.50)],
	[Color(0.90, 0.12, 0.72, 0.52), Color(0.14, 0.80, 0.35, 0.50)],
	[Color(0.55, 0.24, 0.94, 0.52), Color(0.94, 0.82, 0.10, 0.52)],
]

func _open_onion_settings() -> void:
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		UiKit.label_for("Onion skin", "قشرة البصل"))
	_sheet_note(v, UiKit.label_for(
		"One colour for the drawings behind the playhead and one for the drawings ahead of it. The nearest drawing on each side is the strongest, and each one further out is fainter — so a run of ghosts reads as a direction.",
		"لون واحد للرسوم التي خلف رأس التشغيل ولون آخر للتي أمامه. الأقرب على كل جانب هو الأقوى، وكلما ابتعد الرسم خفت لونه — فتُقرأ سلسلة الأطياف كاتجاه."))

	# --- behind ---
	_vlabel(v, UiKit.label_for("Frames behind", "إطارات للخلف"))
	UiKit.slider_row(v, UiKit.label_for("How many behind", "كم إطاراً للخلف"),
		0.0, 8.0, float(player.onion_back), 1.0, "",
		func(x: float) -> void:
			player.onion_back = clampi(int(x), 0, 8)
			player.refresh_visuals()
			_dirty()
			refresh())
	_colour_strip(v, true)

	v.add_child(HSeparator.new())

	# --- ahead ---
	_vlabel(v, UiKit.label_for("Frames ahead", "إطارات للأمام"))
	UiKit.slider_row(v, UiKit.label_for("How many ahead", "كم إطاراً للأمام"),
		0.0, 8.0, float(player.onion_forward), 1.0, "",
		func(x: float) -> void:
			player.onion_forward = clampi(int(x), 0, 8)
			player.refresh_visuals()
			_dirty()
			refresh())
	_colour_strip(v, false)
	_float_sheet(sheet)

## A row of four swatches, drawn as swatches rather than opened from a
## colour dialog.
##
## The old rows used Godot's colour button, and on a touch panel it could
## not be reached at all: the panel forwards a tap as a plain press, and a
## colour button opens its wheel from its own input handling instead — so
## the row looked live and did nothing whatever you did to it. Four ready
## colours are also the better answer here: what these need to be is
## unmistakable, not exact.
func _colour_strip(v: VBoxContainer, behind: bool) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	v.add_child(row)

	var current: Color = player.onion_back_tint if behind \
		else player.onion_forward_tint
	var chips: Array = []
	for i in ONION_PAIRS.size():
		var pair: Array = ONION_PAIRS[i]
		var mine: Color = pair[0] if behind else pair[1]
		var other: Color = pair[1] if behind else pair[0]
		var index: int = i
		var chip: Button = _swatch(mine)
		chip.set_pressed_no_signal(_same_hue(mine, current))
		chips.append(chip)
		chip.pressed.connect(func() -> void:
			# Choosing one side chooses the other: the pair is the point.
			player.onion_back_tint = mine if behind else other
			player.onion_forward_tint = other if behind else mine
			player.onion = true
			player.refresh_visuals()
			_dirty()
			for k in chips.size():
				(chips[k] as Button).set_pressed_no_signal(k == index)
			refresh())
		row.add_child(chip)

## A solid block of the colour itself. A swatch that says its own name in
## words would be one more thing to read; this one simply is the answer.
func _swatch(col: Color) -> Button:
	var b: Button = Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(UiKit.s(52.0), UiKit.s(44.0))

	var solid: Color = Color(col.r, col.g, col.b, 1.0)
	var flat: StyleBoxFlat = StyleBoxFlat.new()
	flat.bg_color = solid
	flat.set_corner_radius_all(int(UiKit.s(10.0)))
	flat.border_color = Color(0.0, 0.0, 0.0, 0.35)
	flat.set_border_width_all(1)

	var hover: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
	hover.bg_color = solid.lightened(0.12)

	# The chosen one wears a thick pale ring. A tick or a tint would have to
	# survive being drawn on top of every colour in the row; a ring does.
	var on: StyleBoxFlat = flat.duplicate() as StyleBoxFlat
	on.border_color = UiKit.TEXT
	on.set_border_width_all(int(maxf(UiKit.s(3.0), 3.0)))

	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("focus", flat)
	return b

func _same_hue(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.06 and absf(a.g - b.g) < 0.06 \
		and absf(a.b - b.b) < 0.06

func _vlabel(v: VBoxContainer, text: String) -> void:
	v.add_child(UiKit.make_label(text, 12.0, UiKit.TEXT_DIM))

func _open_timeline_settings() -> void:
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		UiKit.label_for("Timeline settings", "إعدادات التايم لاين"))

	v.add_child(UiKit.make_label(
		UiKit.label_for("Frames per second", "إطارات في الثانية"),
		12.0, UiKit.TEXT_DIM))
	var rates: HBoxContainer = HBoxContainer.new()
	rates.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	v.add_child(rates)
	var choices: Array = [8, 12, 15, 24, 25, 30, 50, 60]
	var rate_buttons: Array = []
	for i in choices.size():
		var value: int = int(choices[i])
		var index: int = i
		var b: Button = UiKit.make_text_button(str(value))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_pressed_no_signal(value == clip.fps)
		b.pressed.connect(func() -> void:
			clip.fps = value
			for k in rate_buttons.size():
				(rate_buttons[k] as Button).set_pressed_no_signal(k == index)
			_dirty()
			refresh())
		rate_buttons.append(b)
		rates.add_child(b)
	_sheet_note(v, UiKit.label_for(
		"This is the rate the scene plays at and the rate it is written out at — change it here and every export follows.",
		"هذا هو المعدّل الذي يعمل به المشهد والمعدّل الذي يُصدَّر به — غيّره هنا ويتبعه كل تصدير."))

	v.add_child(HSeparator.new())

	# --- what plays ---
	#
	# Length is not asked for any more. A scene ends where the drawing ends,
	# and the band grows to fit it. What is worth choosing is which stretch
	# to watch — an action six frames long in the middle of a long scene
	# should be watchable without sitting through everything before it.
	_vlabel(v, UiKit.label_for("Play from frame", "التشغيل من الإطار"))
	# Over the scene, not over the band. The band has no end, so a slider
	# running to the end of it would have no end either.
	var last: int = maxi(_reach, 0)
	var span: Vector2i = clip.play_span(stack)
	var from_label: Label = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	var to_label: Label = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	var restate: Callable = func() -> void:
		var now: Vector2i = clip.play_span(stack)
		var whole: bool = clip.play_from < 0 and clip.play_to < 0
		from_label.text = UiKit.label_for("Whole scene", "المشهد كامله") if whole \
			else "%d → %d  ·  %d %s" % [now.x + 1, now.y + 1,
				now.y - now.x + 1, UiKit.label_for("frames", "إطاراً")]
		# Asked of the clip rather than worked out by dividing, because
		# frames no longer all last the same length of time: a stretch
		# holding a slowed unit runs longer than its frame count suggests,
		# and this is the number that has to agree with the film.
		to_label.text = "%s %s" % [
			Lang.decimal(clip.span_seconds(now.x, now.y), 2),
			UiKit.label_for("seconds", "ثانية")]

	UiKit.slider_row(v, UiKit.label_for("First frame", "أول إطار"),
		1.0, float(last + 1), float(span.x + 1), 1.0, "",
		func(x: float) -> void:
			clip.play_from = clampi(int(x) - 1, 0, maxi(_reach, 0))
			if clip.play_to >= 0 and clip.play_to < clip.play_from:
				clip.play_to = clip.play_from
			restate.call()
			_dirty()
			refresh())
	UiKit.slider_row(v, UiKit.label_for("Last frame", "آخر إطار"),
		1.0, float(last + 1), float(span.y + 1), 1.0, "",
		func(x: float) -> void:
			clip.play_to = clampi(int(x) - 1, 0, maxi(_reach, 0))
			if clip.play_from >= 0 and clip.play_from > clip.play_to:
				clip.play_from = clip.play_to
			restate.call()
			_dirty()
			refresh())
	v.add_child(from_label)
	v.add_child(to_label)
	restate.call()

	var whole_b: Button = UiKit.make_text_button(
		UiKit.label_for("Play the whole scene", "شغّل المشهد كامله"), true)
	whole_b.pressed.connect(func() -> void:
		clip.play_from = -1
		clip.play_to = -1
		restate.call()
		_dirty()
		refresh())
	v.add_child(whole_b)

	var loop: Button = UiKit.make_text_button(
		UiKit.label_for("Repeat", "تكرار"), true)
	loop.toggle_mode = true
	loop.set_pressed_no_signal(player.looping)
	loop.pressed.connect(func() -> void:
		player.looping = not player.looping
		_dirty()
		_shut_sheet())
	v.add_child(loop)

	UiKit.slider_row(v, UiKit.label_for("Frame width", "عرض الإطار"),
		MIN_FRAME_W, MAX_FRAME_W, frame_w, 1.0, "",
		func(x: float) -> void:
			frame_w = x
			refresh())
	_float_sheet(sheet)

# -------------------------------------------- dividing the rate into units

## Lays a new unit down at the playhead.
##
## If the playhead is already standing inside one, the new unit begins where
## that one ends — never on top of it, and never somewhere else on the band
## that happened to be free. Two rates over one frame is not a thing that can
## be played, so it is not a thing that can be made.
func _add_unit() -> void:
	if clip == null or player == null:
		return
	var here: int = clampi(int(floor(player.frame + 0.000001)), _view_lo(),
		Anim.CEILING_FRAMES - 2)
	var slot: Vector2i = clip.free_slot(here, Anim.UNIT_OPENING)
	if _view_hi() >= 0:
		slot.y = mini(slot.y, _view_hi())
	if slot.y < slot.x:
		_tell_row(UiKit.label_for("No room for a unit here",
			"لا يوجد متسع لوحدة هنا"))
		return
	var one: Anim.Unit = clip.add_unit(slot.x, slot.y, clip.fps)
	clip.grow_to_fit(stack, one.to_frame)
	_dirty()
	_bring_into_view(one.from_frame)
	_bring_into_view(one.to_frame + 1)
	_tell_unit(one)
	rebuild()

## Every unit in the scene, in order.
##
## Reached by holding the unit button. A unit that has been scrolled far off
## an endless band cannot be found by looking for it, so there has to be one
## place that lists them — and going to one from here brings it back on screen
## rather than leaving you to hunt for where it went.
func _open_units_list() -> void:
	if clip == null:
		return
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		UiKit.label_for("Frame rate units", "وحدات معدل الإطارات"))
	if clip.units.is_empty():
		_sheet_note(v, UiKit.label_for(
			"None yet. Tap the button to lay one down at the playhead, drag its arrows to cover the frames you mean, then tap it twice to set its rate.",
			"لا توجد بعد. اضغط الزر لوضع واحدة عند رأس التشغيل، واسحب سهميها لتغطي الإطارات التي تريدها، ثم اضغط عليها مرتين لضبط معدلها."))
		_float_sheet(sheet)
		return
	_sheet_note(v, UiKit.label_for("Going to one brings it back on screen.",
		"الذهاب إلى واحدة يعيدها إلى الشاشة."))
	for u in clip.units:
		var one: Anim.Unit = u
		var b: Button = UiKit.make_text_button(Lang.digits(
			"%d–%d  ·  %d fps  ·  %.2fs"
			% [one.from_frame + 1, one.to_frame + 1, one.fps, one.seconds()]),
			true)
		b.pressed.connect(func() -> void:
			_shut_sheet()
			_bring_into_view(one.from_frame)
			player.seek(float(one.from_frame))
			_open_unit_settings(one))
		v.add_child(b)
	_float_sheet(sheet)

## What a unit runs at.
##
## Opened by two taps on the unit itself, which is why it opens already
## knowing which one it is talking about and does not ask again.
## One end of a unit, as a number that can be stepped or typed.
##
## Both ends go through `_set_unit_edge`, which is the same clamping the drag
## arrows use — so there is exactly one rule about where a unit may reach, and
## it cannot be got round by typing what could not be dragged.
func _unit_edge_row(v: VBoxContainer, one: Anim.Unit, start_side: bool,
		title: String, restate: Callable) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	v.add_child(row)

	var name_l: Label = UiKit.make_label(title, 12.0, UiKit.TEXT_DIM)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_l)

	# Boxed for the same reason as the slider above: the field does not exist
	# yet when the buttons beside it are written, but the box does.
	var field: Array = [null]
	var restate_row: Callable = func() -> void:
		var now: int = (one.from_frame if start_side else one.to_frame) + 1
		var b: Button = field[0] as Button
		if b != null and is_instance_valid(b):
			b.text = Lang.number(now)
		restate.call()

	var less: Button = UiKit.make_text_button("◂")
	less.custom_minimum_size = Vector2(UiKit.s(46.0), UiKit.s(42.0))
	less.pressed.connect(func() -> void:
		_set_unit_edge(one, start_side,
			(one.from_frame if start_side else one.to_frame) - 1)
		restate_row.call())
	row.add_child(less)

	var value_btn: Button = UiKit.make_text_button("")
	value_btn.custom_minimum_size = Vector2(UiKit.s(78.0), UiKit.s(42.0))
	field[0] = value_btn
	value_btn.pressed.connect(func() -> void:
		var here: int = (one.from_frame if start_side else one.to_frame) + 1
		_open_number_sheet(title, UiKit.label_for(
			"The frame this end of the unit sits on. Out of reach numbers are pulled back to whatever the neighbouring unit leaves free.",
			"الإطار الذي يقف عليه هذا الطرف من الوحدة. والأرقام البعيدة تُردّ إلى ما تتركه الوحدة المجاورة حراً."),
			here, 1,
			[[UiKit.label_for("The playhead", "رأس التشغيل"),
				int(floor(player.frame + 0.000001)) + 1]],
			func(n: int) -> void:
				_set_unit_edge(one, start_side, n - 1)
				_open_unit_settings(one)))
	row.add_child(value_btn)

	var more: Button = UiKit.make_text_button("▸")
	more.custom_minimum_size = Vector2(UiKit.s(46.0), UiKit.s(42.0))
	more.pressed.connect(func() -> void:
		_set_unit_edge(one, start_side,
			(one.from_frame if start_side else one.to_frame) + 1)
		restate_row.call())
	row.add_child(more)
	restate_row.call()

## Moves one end of a unit, clamped exactly as a drag would be.
func _set_unit_edge(one: Anim.Unit, start_side: bool, want: int) -> void:
	if clip == null or one == null:
		return
	var room: Vector2i = clip.unit_room(one)
	var floor_frame: int = maxi(room.x, _view_lo())
	var roof: int = room.y
	if _view_hi() >= 0:
		roof = mini(roof, _view_hi())
	if roof < floor_frame:
		return
	if start_side:
		one.from_frame = clampi(want, floor_frame, one.to_frame)
	else:
		one.to_frame = clampi(want, one.from_frame, roof)
	clip.sort_units()
	clip.grow_to_fit(stack, one.to_frame)
	_bring_into_view(one.from_frame if start_side else one.to_frame + 1)
	_dirty()
	refresh()

func _open_unit_settings(one: Anim.Unit) -> void:
	if clip == null or one == null:
		return
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet,
		UiKit.label_for("Frame rate unit", "وحدة معدل الإطارات"))
	_sheet_note(v, UiKit.label_for(
		"The frames inside this unit are held at their own rate. Nothing is added and nothing is moved along — only how long each frame lasts. Slowing a unit down stretches time where it stands instead of stretching the band, so everything after it simply happens later.",
		"تُعرض الإطارات داخل هذه الوحدة بمعدلها الخاص. لا يُضاف شيء ولا يتزحزح شيء — يتغيّر فقط طول بقاء كل إطار. فتبطيء الوحدة يمدّ الزمن في مكانه لا يمدّ الشريط، وكل ما بعدها يحدث متأخراً وحسب."))

	var readout: Label = UiKit.make_label("", 13.0, UiKit.TEXT)
	readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(readout)

	# Boxed, because a lambda takes a copy of what it can see when it is made
	# — and the slider does not exist yet when the buttons below are written.
	# The box does exist, and the box is what they hold on to.
	var rate_slider: Array = [null]
	var restate: Callable = func() -> void:
		readout.text = Lang.fill(
			"Frames {0} to {1} — {2} frames at {3} a second, lasting {4} seconds",
			[one.from_frame + 1, one.to_frame + 1, one.count(), one.fps,
				one.seconds()],
			"الإطارات {0} إلى {1} — {2} إطاراً بمعدل {3} في الثانية، فتستغرق {4} ثانية")
	restate.call()

	_sheet_note(v, Lang.fill("The scene itself runs at {0} a second.",
		[clip.fps], "المشهد نفسه يعمل بمعدل {0} في الثانية."))

	# --- which frames, in numbers ---
	#
	# The arrows on the band are still there and still the quickest way to
	# find the right frames by eye. But a unit that has to land exactly on
	# frames 41 to 47 should not have to be *aimed* at them with a thumb over
	# a grid seven points wide, and reading the frame back off the band to
	# check is worse. So the same two edges are here as numbers, steppable one
	# frame at a time and typeable outright.
	v.add_child(HSeparator.new())
	_vlabel(v, UiKit.label_for("Which frames", "أي الإطارات"))
	_unit_edge_row(v, one, true,
		UiKit.label_for("First frame", "أول إطار"), restate)
	_unit_edge_row(v, one, false,
		UiKit.label_for("Last frame", "آخر إطار"), restate)

	var from_here: Button = UiKit.make_text_button(
		UiKit.label_for("Begin at the playhead", "ابدأ عند رأس التشغيل"), true)
	from_here.pressed.connect(func() -> void:
		_set_unit_edge(one, true, int(floor(player.frame + 0.000001)))
		_shut_sheet()
		_open_unit_settings(one))
	v.add_child(from_here)

	var to_here: Button = UiKit.make_text_button(
		UiKit.label_for("End at the playhead", "انتهِ عند رأس التشغيل"), true)
	to_here.pressed.connect(func() -> void:
		_set_unit_edge(one, false, int(floor(player.frame + 0.000001)))
		_shut_sheet()
		_open_unit_settings(one))
	v.add_child(to_here)
	_sheet_note(v, UiKit.label_for(
		"A unit can never be pushed onto its neighbour: both ends stop where the next unit begins.",
		"لا يمكن دفع وحدة فوق جارتها: يقف طرفاها حيث تبدأ الوحدة التالية."))

	v.add_child(HSeparator.new())
	rate_slider[0] = UiKit.slider_row(v,
		UiKit.label_for("Frames a second", "إطارات في الثانية"),
		float(Anim.MIN_UNIT_FPS), float(Anim.MAX_UNIT_FPS), float(one.fps),
		1.0, "",
		func(x: float) -> void:
			one.fps = clampi(int(round(x)), Anim.MIN_UNIT_FPS,
				Anim.MAX_UNIT_FPS)
			restate.call()
			_dirty()
			refresh())

	# The rates worth having under a thumb rather than at the end of a drag.
	# Two is the slowest a unit may run and sixty the fastest, and both ends
	# are here so neither has to be aimed at on a slider.
	_vlabel(v, UiKit.label_for("Straight to", "مباشرةً إلى"))
	var quick: GridContainer = GridContainer.new()
	quick.columns = 4
	quick.add_theme_constant_override("h_separation", int(UiKit.s(5.0)))
	quick.add_theme_constant_override("v_separation", int(UiKit.s(5.0)))
	v.add_child(quick)
	for rate in [2, 4, 6, 8, 12, 24, 30, 60]:
		var value: int = int(rate)
		var chip: Button = UiKit.make_text_button(Lang.number(value))
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.pressed.connect(func() -> void:
			one.fps = clampi(value, Anim.MIN_UNIT_FPS, Anim.MAX_UNIT_FPS)
			UiKit.slider_set(rate_slider[0] as TouchSlider, float(one.fps))
			restate.call()
			_dirty()
			refresh())
		quick.add_child(chip)

	var same: Button = UiKit.make_text_button(
		UiKit.label_for("Back to the scene's rate", "عد إلى معدل المشهد"), true)
	same.pressed.connect(func() -> void:
		one.fps = clampi(clip.fps, Anim.MIN_UNIT_FPS, Anim.MAX_UNIT_FPS)
		UiKit.slider_set(rate_slider[0] as TouchSlider, float(one.fps))
		restate.call()
		_dirty()
		refresh())
	v.add_child(same)

	v.add_child(HSeparator.new())
	_sheet_note(v, UiKit.label_for(
		"Drag the arrows on its edges to change which frames it covers. Hold the unit and drag to slide it along the band.",
		"اسحب السهمين على حافتيها لتغيير الإطارات التي تغطيها. واضغط عليها مطولاً ثم اسحب لتحريكها على الشريط."))

	var armed: Array = [false]
	var kill: Button = UiKit.make_text_button(
		UiKit.label_for("Remove this unit", "احذف هذه الوحدة"), true)
	kill.pressed.connect(func() -> void:
		if not armed[0]:
			armed[0] = true
			kill.text = UiKit.label_for("Tap again to delete", "اضغط ثانية للحذف")
			return
		clip.drop_unit(one)
		if _drag_unit == one:
			_drag_unit = null
		if _press_unit == one:
			_press_unit = null
		_unit_tap_id = -1
		_dirty()
		_shut_sheet()
		rebuild())
	v.add_child(kill)
	_float_sheet(sheet)

# ------------------------------------------------------- the view window

func _sync_view_buttons() -> void:
	if clip == null:
		return
	# Written only when it changes. This runs on every move of the playhead,
	# and handing a control the string it already has still costs a re-layout
	# of the row it sits in.
	if _view_from_btn != null and is_instance_valid(_view_from_btn):
		var lo_text: String = "◂ " + Lang.number(_view_lo() + 1)
		if _view_from_btn.text != lo_text:
			_view_from_btn.text = lo_text
	if _view_to_btn != null and is_instance_valid(_view_to_btn):
		var hi: int = _view_hi()
		var hi_text: String = Lang.number((hi + 1) if hi >= 0 else 0) + " ▸"
		if _view_to_btn.text != hi_text:
			_view_to_btn.text = hi_text

func _open_view_from() -> void:
	if clip == null:
		return
	_open_number_sheet(
		UiKit.label_for("Show the band from frame", "ابدأ عرض الشريط من الإطار"),
		UiKit.label_for(
			"Where the band begins. This changes what you are looking at, not what plays — the frames before it are still there and still in the film.",
			"من أين يبدأ الشريط. هذا يغيّر ما تنظر إليه لا ما يُعرض — فالإطارات التي قبله باقية وما زالت في الفيلم."),
		_view_lo() + 1, 1,
		[[UiKit.label_for("The playhead", "رأس التشغيل"),
			int(floor(player.frame + 0.000001)) + 1]],
		func(n: int) -> void:
			clip.view_from = maxi(n - 1, 0)
			if clip.view_to >= 0 and clip.view_to < clip.view_from:
				clip.view_to = clip.view_from
			scroll_x = _clamp_scroll_x(float(clip.view_from) * frame_w)
			_dirty()
			refresh())

func _open_view_to() -> void:
	if clip == null:
		return
	var hi: int = _view_hi()
	_open_number_sheet(
		UiKit.label_for("Show the band up to frame",
			"اعرض الشريط حتى الإطار"),
		UiKit.label_for(
			"Where the band stops. Nought means it never stops: the band runs on forward for as long as you keep dragging it, past the last drawing and out into empty frames waiting to be used.",
			"أين يتوقف الشريط. والصفر يعني أنه لا يتوقف: يمضي الشريط إلى الأمام ما دمت تسحبه، متجاوزاً آخر رسم إلى إطارات فارغة تنتظر الاستعمال."),
		(hi + 1) if hi >= 0 else 0, 0,
		[[UiKit.label_for("No end", "بلا نهاية"), 0],
			[UiKit.label_for("The last drawing", "آخر رسم"), _reach + 1]],
		func(n: int) -> void:
			if n <= 0:
				clip.view_to = -1
			else:
				clip.view_to = maxi(n - 1, clip.view_from)
			_dirty()
			refresh())

## A pad for typing one number.
##
## Ten keys rather than a text field, for the same reason the colour pad is
## sixteen: a text field on a phone means summoning the system keyboard over
## the very band the number is about, and then hunting for digits among the
## letters. Ten large keys are the whole alphabet here.
func _open_number_sheet(title: String, note: String, value: int,
		floor_value: int, extras: Array, on_ok: Callable) -> void:
	var sheet: PanelContainer = _sheet()
	var v: VBoxContainer = _sheet_column(sheet, title)
	_sheet_note(v, note)

	var typed: Array = [str(maxi(value, 0))]
	var readout: Label = UiKit.make_label("", 22.0, UiKit.TEXT)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.custom_minimum_size = Vector2(0.0, UiKit.s(38.0))
	v.add_child(readout)

	# Not `show` and not `hide`: every Node already has methods by those
	# names, and a local that shadows one is the kind of thing that reads
	# perfectly and then surprises somebody a year later.
	var restate: Callable = func() -> void:
		readout.text = Lang.digits(String(typed[0]) if String(typed[0]) != ""
			else "0")
	restate.call()

	var finish: Callable = func() -> void:
		var text: String = String(typed[0])
		var n: int = maxi(int(text) if text.is_valid_int() else floor_value,
			floor_value)
		_shut_sheet()
		on_ok.call(n)

	var pad: GridContainer = GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", int(UiKit.s(6.0)))
	pad.add_theme_constant_override("v_separation", int(UiKit.s(6.0)))
	v.add_child(pad)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		pad.add_child(_pad_key(String(key), func() -> void:
			_pad_push(typed, String(key))
			restate.call()))
	pad.add_child(_pad_key("⌫", func() -> void:
		var text: String = String(typed[0])
		typed[0] = text.substr(0, maxi(text.length() - 1, 0))
		restate.call()))
	pad.add_child(_pad_key("0", func() -> void:
		_pad_push(typed, "0")
		restate.call()))
	pad.add_child(_pad_key(UiKit.label_for("OK", "تم"), func() -> void:
		finish.call()))

	if not extras.is_empty():
		v.add_child(HSeparator.new())
		for e in extras:
			var pair: Array = e
			var quick: Button = UiKit.make_text_button(String(pair[0]), true)
			var quick_value: int = int(pair[1])
			quick.pressed.connect(func() -> void:
				_shut_sheet()
				on_ok.call(maxi(quick_value, floor_value)))
			v.add_child(quick)
	_float_sheet(sheet)

## Digits are appended, and a leading nought is replaced rather than kept —
## typing 1 then 2 into a field showing 0 should give twelve, not twelve
## hundred and something with a nought in front of it.
func _pad_push(typed: Array, digit: String) -> void:
	var text: String = String(typed[0])
	if text == "0":
		text = ""
	if text.length() >= 6:
		return
	typed[0] = text + digit

func _pad_key(label: String, action: Callable) -> Button:
	var b: Button = UiKit.make_text_button(label)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Deliberately tall. This is a number being typed with a thumb over a
	# panel that is already crowded, and a key that has to be aimed at is a
	# key that puts the wrong frame in the box.
	b.custom_minimum_size = Vector2(UiKit.s(64.0), UiKit.s(50.0))
	b.add_theme_font_size_override("font_size", int(UiKit.s(17.0)))
	b.pressed.connect(action)
	return b

# ------------------------------------------------------------ the sheets

## Every sheet is built the same way: a title, a scrolling column, and a
## shade over the whole screen. Pressing anything inside closes it, because
## a settings sheet has said its piece the moment it is used.
func _sheet() -> PanelContainer:
	var sheet: PanelContainer = PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UiKit.panel_style())
	var screen_w: float = get_viewport_rect().size.x
	var min_w: float = clampf(screen_w * 0.78, UiKit.s(320.0), UiKit.s(520.0))
	sheet.custom_minimum_size = Vector2(min_w, 0.0)
	return sheet

func _sheet_column(sheet: PanelContainer, title: String) -> VBoxContainer:
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	sheet.add_child(outer)
	var heading: Label = UiKit.make_label(title, 16.0, UiKit.TEXT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size = Vector2(0.0, UiKit.s(26.0))
	outer.add_child(heading)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.s(10.0)))
	var scroller: Control = UiKit.scroller(v, UiKit.s(420.0))
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroller)
	return v

func _sheet_note(v: VBoxContainer, text: String) -> void:
	var l: Label = UiKit.make_label(text, 10.0, UiKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

var _shade: Control = null

func _shut_sheet() -> void:
	if _shade != null:
		_shade.queue_free()
		_shade = null
	refresh()

func _float_sheet(sheet: PanelContainer) -> void:
	_shut_sheet()
	_shade = Control.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.offset_top = -get_viewport_rect().size.y
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.gui_input.connect(func(e: InputEvent) -> void:
		var down: bool = false
		if e is InputEventScreenTouch:
			down = (e as InputEventScreenTouch).pressed
		elif e is InputEventMouseButton:
			down = (e as InputEventMouseButton).pressed
		if down:
			_shut_sheet())
	add_child(_shade)

	sheet.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_shade.add_child(sheet)
	# Guarded on both sides of the wait. Before it, because `get_tree()` on a
	# node outside the tree is null — the exact fault that stopped the
	# B-Spline room opening. After it, because a frame is long enough for the
	# panel to have been closed and freed while we were away.
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(sheet):
		return

	# Placed against the whole screen rather than the band, which is short
	# enough to cut a sheet in half.
	var screen: Vector2 = get_viewport_rect().size
	var here: Vector2 = global_position
	var max_h: float = screen.y - UiKit.s(24.0)
	if sheet.size.y > max_h:
		sheet.size = Vector2(minf(sheet.size.x, screen.x - UiKit.s(24.0)), max_h)
	else:
		sheet.size.x = minf(sheet.size.x, screen.x - UiKit.s(24.0))
	var top: float = clampf(here.y - sheet.size.y - UiKit.s(10.0),
		UiKit.s(12.0), screen.y - sheet.size.y - UiKit.s(12.0)) - here.y
	var left: float = clampf((screen.x - sheet.size.x) * 0.5, UiKit.s(12.0),
		screen.x - sheet.size.x - UiKit.s(12.0))
	sheet.position = Vector2(left, top)

# --------------------------------------------------------- held buttons

func _hold_start(action: Callable) -> void:
	_hold_action = action
	_hold_ms = Time.get_ticks_msec()
	set_process(true)

func _hold_end() -> void:
	_hold_action = Callable()
	_hold_ms = 0

func _check_hold() -> void:
	if _hold_ms == 0 or not _hold_action.is_valid():
		return
	if Time.get_ticks_msec() - _hold_ms < HOLD_MS:
		return
	var action: Callable = _hold_action
	_hold_end()
	action.call()
