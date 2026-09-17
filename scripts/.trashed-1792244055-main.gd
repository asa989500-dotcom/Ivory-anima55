class_name MainRoom
extends Control
## IVORY — main room.
##
## The canvas gets the whole screen. Everything else is a small floating
## cluster that stays out of the drawing hand's way: tools on the left,
## selection and clipboard top-left, layers top-right, and readouts that
## appear only when they have something to say.

const ICON: String = "res://assets/icons/%s.png"
const ZOOM_HOLD: float = 0.9      # seconds the zoom badge lingers
const THUMB_EVERY: float = 1.2    # seconds between layer thumbnail refreshes

var view: CanvasView = null
var rail: PanelContainer = null
var edit_bar: PanelContainer = null
var layer_btn_bar: PanelContainer = null
var panel_host: PanelContainer = null
var layers_panel: LayersPanel = null
var coord_bar: PanelContainer = null
var zoom_badge: PanelContainer = null
var note_badge: PanelContainer = null
var page_bar: PanelContainer = null
var layout_bar: PanelContainer = null
var _layout_btn: Button = null
var timeline: TimelinePanel = null
var timeline_btn: PanelContainer = null
var _page_label: Label = null
var action_bar: PanelContainer = null
var solo_bar: PanelContainer = null
var puppet_bar: PanelContainer = null
var bspline_room: BSplineRoom = null
## The layer, opened by itself to take a skeleton. See `bone_room.gd`.
var bone_room: BoneRoom = null
## The dedicated Stretchy Studio room: fully standalone, no Ivory project,
## canvas, or layer stack involved. See `stretchy_studio_standalone.gd`.
## (The earlier `StretchyStudioRoom`, which shared the Ivory canvas on
## purpose, is left in `stretchy_studio_room.gd` but no longer opened from
## here — see `STAGE_170_STANDALONE_NOTES.md`.)
var stretchy_room: StretchyStudioStandalone = null

var open_panel: String = ""
var _shade_from: Vector2 = Vector2.ZERO
var _shade_armed: bool = false
var coord_label: Label = null
var zoom_label: Label = null
var note_label: Label = null
var solo_index: int = -1

var _tool_buttons: Dictionary = {}
var _last_world: Vector2 = Vector2.ZERO
var _settings_page: String = "menu"
var _save_timer: float = 1.0
## How long a project must have been waiting before it is written, and the
## least time between two writes. Together they mean: a few seconds after you
## stop, and never more often than this however busy the hand is.
const SAVE_SETTLE: float = 6.0
const SAVE_GAP: float = 10.0
var _last_save_ms: int = 0
var _comic_page: int = 0
var _ui: CanvasLayer = null

## The model pipeline, and the mark that says it is working. See
## `ai_assistant.gd` — including the line the API key goes on.
var ai: AIAssistant = null
var _ai_wait: AiWait = null
# These six are read and written from the lifted modules (`AiBridge`,
# `ImageImport`) rather than from this file, so Godot reports them as
# declared and never used. They are used; the compiler cannot see through
# `host._improving` back to here. Silenced one declaration at a time rather
# than for the whole file, so a variable that becomes genuinely dead still
# gets reported.
@warning_ignore("unused_private_class_variable")
var _ai_room: AiRoom = null
## Which layer an improvement was asked for, so the answer knows where to go.
@warning_ignore("unused_private_class_variable")
var _improving: int = -1
## Set while a picture is being brought in for the design room rather than
## for a layer.
@warning_ignore("unused_private_class_variable")
var _import_for_ai: bool = false
var _shade: Control = null
var _options_for: ProjectManager.Project = null
var _zoom_timer: float = 0.0
var _note_timer: float = 0.0
var _last_zoom: float = 1.0
var _thumb_timer: float = 0.0
var _btn_close_shape: Button = null
var _btn_place: Button = null
var _btn_cancel: Button = null
var _btn_symmetry_cancel: Button = null

func _ready() -> void:
	# Measure this device before anything asks what it can afford.
	#
	# Reading a stored result on every launch but the first, so the cost here
	# is one file read. On the first launch it is a few tens of milliseconds
	# of real timing — allocating a page, decoding a tile, writing to storage
	# — and every budget in `Perf` is arithmetic on those numbers from then
	# on, rather than on a figure somebody once felt was about right.
	Perf.calibrate()
	if OS.is_debug_build():
		print(Perf.report())

	App.ui_scale = clampf(float(DisplayServer.screen_get_dpi()) / 160.0, 1.0, 3.0)
	UiKit.scale = App.ui_scale
	UiKit.load_font()

	view = CanvasView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.view_changed.connect(_on_zoom)
	view.pointer_moved.connect(_on_pointer)
	view.selection_changed.connect(_refresh_action_bar)
	view.action_taken.connect(_on_action)
	view.notice.connect(_flash)
	view.text_restyle_needed.connect(_redraw_text_layer)
	view.project_menu_requested.connect(_show_project_options)
	view.frame_colour_requested.connect(_show_frame_colour)
	view.project_focused.connect(func(p: ProjectManager.Project) -> void:
		_comic_page = p.active_page
		_sync_shell()
		_refresh_timeline_button()
		_refresh_focus_bar()
		_flash(p.title))
	view.project_changed.connect(_sync_rail)
	view.project_changed.connect(_refresh_timeline_button)
	view.symmetry_mode_changed.connect(_on_symmetry_mode_changed)

	# The interface sits in its own layer. Project frames, titles and the
	# drawing itself all live in the canvas below it, so nothing can ever
	# be drawn over a button again — no matter what z-index it asks for.
	_ui = CanvasLayer.new()
	_ui.layer = 1
	add_child(_ui)

	# The one thing in the app that talks to a model.
	#
	# Made here rather than by whichever feature happens to ask first, so
	# there is a single queue: the layer improver, the design room and the
	# turnaround filler all wait in the same line. Two of them asking at once
	# used to be impossible to reason about; now it is a queue with a mark on
	# screen saying how long it is.
	ai = AIAssistant.new()
	ai.name = "AIAssistant"
	add_child(ai)
	ai.finished.connect(_on_ai_picture)
	ai.failed.connect(func(_id: int, why: String) -> void: _flash(why))

	# A sheet of nothing behind every floating panel. Reaching back to the
	# button that opened a panel in order to close it is the kind of small
	# tax a user pays a hundred times a session, and there is no reason for
	# it: a tap anywhere else already means "not this".
	_shade = Control.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Visual dismiss layer only. It must never sit between the drawing hand and
	# the canvas: a tool panel is UI, but the blank screen around it is still
	# live paper. Dismissal is handled in `_input` so the same touch can reach
	# `CanvasView` instead of being swallowed by this full-screen control.
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.visible = false
	# No GUI input handler here: the shade deliberately ignores input.
	_ui.add_child(_shade)

	# The waiting mark. Above the shade so it is readable while a panel is
	# open, and it never takes a touch except on its own Cancel.
	_ai_wait = AiWait.new()
	_ai_wait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_ai_wait)
	_ai_wait.watch(ai)

	_build_rail()
	_build_edit_bar()
	_build_layer_button()
	_build_coord_bar()
	_build_zoom_badge()
	_build_note_badge()
	_build_page_bar()
	_build_layout_bar()
	_build_timeline_button()
	_build_action_bar()
	_build_solo_bar()
	_build_puppet_bar()
	_build_symmetry_cancel()

	resized.connect(_layout)
	App.tool_changed.connect(_on_tool_changed)
	App.open_fill_colour.connect(func() -> void:
		_close_panel()
		_mount(ToolPanels.color(view, true), "fill"))

	get_tree().auto_accept_quit = false
	# Without this the export folder is invisible to the gallery and to
	# every other app on the phone, which defeats the point of exporting.
	if OS.get_name() == "Android":
		OS.request_permissions()
	# A drawing program is idle most of the time it is open. Sleeping
	# between frames rather than spinning is the single cheapest thing a
	# tablet app can do for its battery.
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 6000

	await get_tree().process_frame
	view.reset_view()
	# Anything left from last time comes back closed and compressed, so a
	# full workspace costs nothing until a project is opened.
	Vault.load_all(view.projects)
	# Anything on disk that no project answers for is swept up at startup,
	# so old copies cannot pile up unseen.
	Vault.purge_orphans(view.projects)
	_sync_shell()
	_last_zoom = view.view_zoom
	_layout()
	_sync_rail()
	_update_coords()

## The one moment where saving cannot be put off.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Back means *back*, not quit.
		#
		# It used to mean quit unconditionally, which on a phone is the worst
		# possible reading: the B-Spline room fills the screen, and a user who
		# reached for the system's way out of it closed the whole app instead.
		# Rooms and panels are places you are *in*; the gesture that leaves
		# them is the one every other app on the device uses.
		#
		# Quitting is still what is left when there is nowhere to step back
		# to, and `_park` still runs first either way, so nothing is lost.
		if _step_back():
			return
		_park()
		get_tree().quit()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_park()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Focus-out as well as pause. On Android the pause notification is
		# the last thing an app reliably gets, and by then there may be very
		# little time left — focus-out arrives earlier, when a notification
		# shade is pulled down or the task switcher opens, and most of the
		# time that is the real moment the user stopped drawing.
		_park()

## One layer out, if there is a layer to come out of.
##
## Ordered innermost first, which is the order the user went in: a room is
## deeper than a panel, a panel is deeper than being focused on a project.
## Returns false only when standing in the bare workspace with nothing open,
## which is the one place where back can honestly mean leave.
func _step_back() -> bool:
	if stretchy_room != null:
		_leave_stretchy_room()
		return true
	if bone_room != null:
		_leave_bone_room()
		return true
	if bspline_room != null:
		_leave_bspline_room()
		return true
	if open_panel != "":
		_close_panel()
		return true
	if view != null and view.projects != null \
			and view.projects.focus_on != null:
		leave_focus()
		return true
	return false

## A sheet the user opened the dialog for and never put down is thrown away
## rather than written to disk, so it cannot return uninvited.
func _park() -> void:
	if view == null:
		return
	# Anything the rig is still holding back is written first.
	#
	# A pose reaches the layer the instant a finger lifts, but the *keyframe*
	# waits a second of stillness so a minute of adjusting leaves one key
	# rather than forty. `_park` is the app being closed, backgrounded or
	# swiped away — and on Android it may be the last code that runs. A pose
	# still inside its second at that moment would be a pose the artist made
	# and the file never heard about, which is precisely the data loss this
	# whole path exists to prevent.
	BoneHandle.flush(view)
	var loose: ProjectManager.Project = view.projects.placing
	if loose != null:
		view.projects.remove(loose)
	Vault.save_all(view.projects)

func _input(event: InputEvent) -> void:
	# Panels and bars live outside the canvas, so the canvas never sees the
	# touches that drive them — without this they would animate at the idle
	# pace and feel broken.
	if event is InputEventScreenTouch or event is InputEventScreenDrag \
			or event is InputEventMouseButton or event is InputEventKey:
		view.mark_busy()

	# Dismissing a floating tool panel must NOT consume the touch that dismissed
	# it. The old full-screen shade used MOUSE_FILTER_STOP, so a finger landing
	# on the canvas first hit the shade, `_shade_touched()` closed the panel, and
	# the actual drawing event was lost. That made every canvas tool look dead.
	# We close before GUI routing, then let the same event continue normally to
	# the CanvasView. A press inside the panel remains owned by the panel.
	if panel_host != null and is_instance_valid(panel_host):
		var outside_panel: bool = false
		if event is InputEventScreenTouch:
			var st: InputEventScreenTouch = event as InputEventScreenTouch
			outside_panel = st.pressed and not panel_host.get_global_rect().has_point(st.position)
		elif event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			outside_panel = mb.pressed \
					and mb.button_index == MOUSE_BUTTON_LEFT \
					and not panel_host.get_global_rect().has_point(mb.position)
		if outside_panel:
			_close_panel()

func _process(delta: float) -> void:
	# Autosave asks a question every second rather than counting down to one
	# moment. Three things have to be true before anything is written, and a
	# fixed interval could only ever express the third.
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 1.0
		_maybe_save()
	if _zoom_timer > 0.0:
		_zoom_timer -= delta
		if _zoom_timer <= 0.0:
			zoom_badge.visible = false
	if _note_timer > 0.0:
		_note_timer -= delta
		if _note_timer <= 0.0:
			note_badge.visible = false
	if layers_panel != null and layers_panel.visible:
		_thumb_timer -= delta
		if _thumb_timer <= 0.0:
			_thumb_timer = THUMB_EVERY
			layers_panel.refresh_thumbs()

# ------------------------------------------------------------------ layout

## Whether now is the moment to write a project to disk.
##
## Three questions, and all three have to answer yes.
##
## **Is anything waiting?** A workspace being looked at rather than drawn on
## writes nothing at all.
##
## **Has it settled?** Work reaches the disk a few seconds after the hand
## stops, instead of at whatever point a long fixed interval happened to fall.
## The wait is measured from when the project *first* became dirty, so a
## project being worked on continuously still gets written — a clock restarted
## by every dab would never run out for exactly the project with the most to
## lose.
##
## **Is the hand down?** Writing a project is tens of milliseconds of disk
## work, and doing it mid-stroke puts a visible hitch in that stroke. It is
## also exactly when a save is most likely to be due, because drawing is what
## makes documents dirty. So the write waits for the lift.
##
## One project per turn, oldest first. Several written in one frame is several
## times the hitch in one place, and they can just as well be spread across
## several turns.
func _maybe_save() -> void:
	if view == null or view.is_drawing():
		return
	# The same flush, on the way into a routine save. Without it the autosave
	# would write a project whose figure is posed but whose band has no mark
	# on it — and a project reopened from that file is not the one that was
	# closed, which is the one thing a save must never be.
	BoneHandle.flush(view)
	if Time.get_ticks_msec() - _last_save_ms < int(SAVE_GAP * 1000.0):
		return
	if view.projects.oldest_dirty_wait() < SAVE_SETTLE:
		return
	var waiting: Array = view.projects.take_dirty()
	if waiting.is_empty():
		return
	var p: ProjectManager.Project = waiting[0]
	_last_save_ms = Time.get_ticks_msec()
	if Vault.save(p):
		view.projects.mark_saved(p)
	# A failed write is left dirty on purpose, so the next turn retries it
	# rather than quietly declaring unsaved work clean.

func _layout() -> void:
	var pad: float = UiKit.s(14.0)
	if rail != null:
		rail.position = Vector2(pad, (size.y - rail.size.y) * 0.5)
	if edit_bar != null:
		edit_bar.position = Vector2(pad, pad)
	if layer_btn_bar != null:
		layer_btn_bar.position = Vector2(size.x - layer_btn_bar.size.x - pad, pad)
	if zoom_badge != null:
		zoom_badge.position = Vector2((size.x - zoom_badge.size.x) * 0.5, pad)
	if note_badge != null:
		note_badge.position = Vector2((size.x - note_badge.size.x) * 0.5,
			pad + UiKit.s(48.0))
	if solo_bar != null:
		solo_bar.position = Vector2((size.x - solo_bar.size.x) * 0.5, pad)
	if puppet_bar != null and puppet_bar.visible:
		puppet_bar.position = Vector2((size.x - puppet_bar.size.x) * 0.5,
			size.y - puppet_bar.size.y - pad)
	if _btn_symmetry_cancel != null and _btn_symmetry_cancel.visible:
		_btn_symmetry_cancel.position = Vector2((size.x - _btn_symmetry_cancel.size.x) * 0.5,
			pad + UiKit.s(54.0))
	if coord_bar != null:
		coord_bar.position = Vector2(size.x - coord_bar.size.x - pad,
			size.y - coord_bar.size.y - pad)
	if action_bar != null:
		action_bar.position = Vector2((size.x - action_bar.size.x) * 0.5,
			size.y - action_bar.size.y - pad)
	if layout_bar != null and layout_bar.visible:
		layout_bar.position = Vector2(pad, size.y - layout_bar.size.y - pad)
	if timeline_btn != null and timeline_btn.visible:
		# Lifted clear of the very corner, where a thumb resting on the
		# bezel would find it by accident.
		var lift: float = pad + UiKit.s(26.0)
		if timeline != null and timeline.visible:
			lift += timeline.size.y + UiKit.s(8.0)
		timeline_btn.position = Vector2(size.x - timeline_btn.size.x - pad,
			size.y - timeline_btn.size.y - lift)
	if timeline != null:
		var band: float = clampf(size.y * 0.34, UiKit.s(180.0), UiKit.s(360.0))
		timeline.size = Vector2(size.x, band)
		timeline.position = Vector2(0.0, size.y - band)
	if page_bar != null and page_bar.visible:
		var page_lift: float = pad
		if action_bar != null and action_bar.visible:
			page_lift += action_bar.size.y + UiKit.s(8.0)
		page_bar.position = Vector2((size.x - page_bar.size.x) * 0.5,
			size.y - page_bar.size.y - page_lift)
	if panel_host != null:
		# A panel is capped at the screen and then clamped inside it, so a
		# tall one can never grow off an edge and take its own buttons with
		# it. The cap comes first: clamping alone cannot rescue a panel
		# already taller than the screen.
		var room: Vector2 = size - Vector2(pad * 2.0, pad * 2.0)
		if panel_host.size.y > room.y:
			panel_host.size = Vector2(panel_host.size.x, room.y)
		var x: float = pad + (rail.size.x if rail != null else 0.0) + UiKit.s(12.0)
		if open_panel == "layers":
			x = size.x - panel_host.size.x - pad
		var x_max: float = maxf(size.x - panel_host.size.x - pad, pad)
		var y: float = (size.y - panel_host.size.y) * 0.5
		var y_max: float = maxf(size.y - panel_host.size.y - pad, pad)
		panel_host.position = Vector2(clampf(x, pad, x_max), clampf(y, pad, y_max))

# -------------------------------------------------------------------- rail

func _build_rail() -> void:
	rail = PanelContainer.new()
	rail.add_theme_stylebox_override("panel", UiKit.rail_style())
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ui.add_child(rail)
	rail.resized.connect(_layout)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", int(UiKit.s(4.0)))
	rail.add_child(col)

	col.add_child(_tool_btn("brush", "brush", UiKit.label_for("Brush", "الفرشاة")))
	# Directly under the brush, and there on purpose.
	#
	# It carries every brush shape there is — the same stamp, read as *how
	# much mixing happens where* rather than as how much ink lands — so it is
	# a way of using the brush rather than a separate thing, and it belongs
	# where the hand already is. It took the place of the knife, which made
	# rows of even dots nobody had asked for.
	col.add_child(_tool_btn("blend", "color_blend",
		UiKit.label_for("Blend colours", "دمج الألوان")))
	col.add_child(_tool_btn("fill", "fill", UiKit.label_for("Fill", "الملء")))
	col.add_child(_tool_btn("shapes", "shapes", UiKit.label_for("Shapes", "الأشكال")))
	col.add_child(_tool_btn("color", "color_wheel", UiKit.label_for("Color", "الألوان")))
	col.add_child(_tool_btn("eraser", "eraser", UiKit.label_for("Eraser", "الممحاة")))
	# Select, where the other tools are.
	#
	# It was reachable only from a button two panels deep that did not set the
	# tool, and from a keyboard shortcut on a device with no keyboard. A tool
	# nobody can find is a tool that does not exist, however complete the code
	# behind it — and `_sync_rail` was already written to light this button up
	# when the tool is chosen, for a button that had never been made.
	col.add_child(_tool_btn("select", "selection",
		UiKit.label_for("Select", "التحديد")))

func _tool_btn(id: String, icon_name: String, tip: String) -> Button:
	var b: Button = UiKit.make_tool_button(ICON % icon_name, tip)
	b.pressed.connect(func() -> void: _on_rail_pressed(id))
	_tool_buttons[id] = b
	return b

func _on_rail_pressed(id: String) -> void:
	if id == "brush":
		App.set_tool(App.Tool.BRUSH)
	elif id == "blend":
		App.set_tool(App.Tool.BLEND)
	elif id == "fill":
		App.set_tool(App.Tool.FILL)
	elif id == "shapes":
		App.set_tool(App.Tool.SHAPE)
	elif id == "eraser":
		App.set_tool(App.Tool.ERASER)
	elif id == "select":
		App.set_tool(App.Tool.SELECT)
	_toggle_panel(id)
	_sync_rail()

## Any tool at all was chosen, from anywhere.
##
## The one place every button in the rail arrives at, which is why leaving a
## comic mode belongs here rather than in each of them. A cut mode still
## running turns the next stroke into a panel split, and a tone mode still
## running turns it into a printed screen — surprises that cost somebody a
## page, and both were possible because nothing called `end_comic_mode`.
##
## What was already put down stays put down. Ending a mode is about what the
## *next* touch will do, never about undoing the last one.
func _on_tool_changed(t: int) -> void:
	# A bone-motion layer is exclusive: it can only be moved. If another tool
	# is chosen while it is active, immediately return to Move so the layer
	# can never be painted, erased, filled or selected by accident.
	if view != null and view.layers != null:
		var motion_layer: LayerStack.Layer = view.layers.active()
		if motion_layer != null and motion_layer.is_bone_layer and t != App.Tool.MOVE:
			App.set_tool(App.Tool.MOVE)
			return

	# Reaching for any other tool commits the move rather than throwing it
	# away. The box on screen is a change the person has already made and
	# looked at; losing it because they picked up the brush would be losing
	# work, and this tool writes only what they can see.
	if t != App.Tool.MOVE and MoveTool.holding():
		MoveTool.commit(view)
		_close_panel()
	if ComicBoard.mode != ComicBoard.Mode.OFF:
		end_comic_mode()
		_close_panel()
	if t == App.Tool.PICK:
		_close_panel()
	_sync_rail()

## On the workspace there is one thing to do — make something — so there is
## one button. A rail of brushes over a grid with no paper on it is five
## controls that cannot do anything, and they were the first thing anyone
## saw. They come back the moment a project is focused.
func _sync_shell() -> void:
	var inside: bool = view.projects.focus_on != null
	if rail != null:
		rail.visible = inside
	if edit_bar != null:
		edit_bar.visible = inside
	if layer_btn_bar != null:
		# One bar, and what is on it depends entirely on where you are.
		#
		# Outside a project the only mark is the plus, and it now holds the
		# workspace's settings underneath the three ways of making something.
		# Two marks side by side told the user nothing about which of them
		# held *Language*; the only way to find out was to open both.
		#
		# Inside a project the plus goes away outright. It makes projects, and
		# a project is not a thing you make from inside another one — leaving
		# it there put an act with no subject in a bar that is otherwise
		# entirely about the drawing in front of you.
		layer_btn_bar.visible = true
		if _tool_buttons.has("layers"):
			(_tool_buttons["layers"] as Button).visible = inside
		if _tool_buttons.has("compass"):
			(_tool_buttons["compass"] as Button).visible = inside
		if _tool_buttons.has("timeline"):
			(_tool_buttons["timeline"] as Button).visible = inside
		if _tool_buttons.has("make"):
			(_tool_buttons["make"] as Button).visible = not inside
		if _tool_buttons.has("settings"):
			(_tool_buttons["settings"] as Button).visible = inside
		# The bar is a container: with one child visible it shrinks to one
		# button by itself, but only once it has been told to measure again.
		layer_btn_bar.reset_size()
	if coord_bar != null:
		coord_bar.visible = inside
	if inside and open_panel != "" and open_panel != "settings":
		pass
	elif not inside and open_panel != "" and open_panel != "settings":
		_close_panel()
	_layout()

func _sync_rail(_ignored: int = 0) -> void:
	var active: String = ""
	if App.current_tool == App.Tool.BRUSH:
		active = "brush"
	elif App.current_tool == App.Tool.FILL:
		active = "fill"
	elif App.current_tool == App.Tool.SHAPE:
		active = "shapes"
	elif App.current_tool == App.Tool.ERASER:
		active = "eraser"
		active = "blend"
	elif App.current_tool == App.Tool.SELECT:
		active = "select"
	for id in _tool_buttons.keys():
		var b: Button = _tool_buttons[id]
		var on: bool = (id == active) or (id == open_panel and id == "color") \
			or (id == "layers" and open_panel == "layers") \
			or (id == "compass" and open_panel == "compass") \
			or (id == "settings" and open_panel == "settings") \
			or (id == "make" and open_panel == "make")
		b.set_pressed_no_signal(on)

# ------------------------------------------------- selection and clipboard

func _build_edit_bar() -> void:
	edit_bar = PanelContainer.new()
	edit_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	edit_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ui.add_child(edit_bar)
	edit_bar.resized.connect(_layout)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(4.0)))
	edit_bar.add_child(row)

	var input_b: Button = UiKit.make_tool_button(ICON % "input_event",
		UiKit.label_for("Input event", "حدث الإدخال"))
	input_b.pressed.connect(_open_input_event)
	row.add_child(input_b)

	var copy_b: Button = UiKit.make_tool_button(ICON % "copy",
		UiKit.label_for("Copy", "نسخ"))
	copy_b.toggle_mode = false
	copy_b.pressed.connect(func() -> void: view.copy_selection())
	row.add_child(copy_b)

	var paste_b: Button = UiKit.make_tool_button(ICON % "paste",
		UiKit.label_for("Paste", "لصق"))
	paste_b.toggle_mode = false
	paste_b.pressed.connect(func() -> void: view.paste_clipboard())
	row.add_child(paste_b)

func _build_layer_button() -> void:
	layer_btn_bar = PanelContainer.new()
	layer_btn_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	layer_btn_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ui.add_child(layer_btn_bar)
	layer_btn_bar.resized.connect(_layout)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(4.0)))
	layer_btn_bar.add_child(row)
	row.add_child(_tool_btn("layers", "layers", UiKit.label_for("Layers", "الطبقات")))
	# The compass sits beside the layers button and in the same style, because
	# what it holds is the same kind of thing: not a brush, but a place to go.
	row.add_child(_tool_btn("compass", "compass",
		UiKit.label_for("Compass", "البوصلة")))
	# These two are never on screen together. The plus belongs to the
	# workspace, where it makes projects and carries the app's own settings
	# under them; the gear belongs inside a project, where it carries that
	# project's. `_sync_shell` decides which, and the bar resizes to whichever
	# is left. See the note there.
	row.add_child(_tool_btn("make", "add_project",
		UiKit.label_for("New project", "مشروع جديد")))
	row.add_child(_tool_btn("settings", "settings_gear",
		UiKit.label_for("Settings", "الإعدادات")))

# ---------------------------------------------------------------- compass

## What the compass holds: places, not tools.
##
## The rail chooses what the hand is doing to the drawing. These three change
## what is being worked on, or where the work is happening — which is why they
## are gathered under their own mark rather than added to a row of brushes.
func _compass_panel() -> PanelContainer:
	return ToolPanels.compass(
		func() -> void: add_text_layer(),
		func() -> void: begin_tangled_lines(),
		func() -> void: open_ai_room(),
		func() -> void: open_symmetry(),
		_project_kind(),
		func(key: String) -> void: open_comic_tool(key))

## Straight lines that arrive already joined.
##
## Reached from the compass rather than from the shapes panel because it is a
## way of building rather than one more outline — you keep drawing until the
## thing is built, and every line lands joined to the last. It still *is* the
## shape tool underneath, which is why it inherits the brush, the colour and
## the undo you already have.
func begin_tangled_lines() -> void:
	_close_panel()
	if not view.has_project():
		_flash(UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
		return
	view.break_chain()
	App.shape_mode = App.Shape.CHAIN
	App.set_tool(App.Tool.SHAPE)
	App.settings_changed.emit()
	_flash(UiKit.label_for(
		"Draw the first line. Every line after it starts where the last one ended.",
		"ارسم الخط الأول. وكل خط بعده يبدأ حيث انتهى سابقه."))

# ------------------------------------------------------------------- text

var _text_state: Dictionary = {}

## Writing goes on a layer of its own, always.
##
## Text on a drawing layer is ink the moment it lands — to change a word you
## would have to erase it and hope you erased only that. On its own layer it
## can be moved, restyled, or thrown away without touching a single stroke
## underneath, which is what makes it text rather than a picture of text.
func add_text_layer() -> void:
	_close_panel()
	if not view.has_project():
		_flash(UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
		return
	if _text_state.is_empty():
		_text_state = {
			"text": "", "size": 64.0, "leading": 1.15,
			"keep_ratio": true, "snap_rotation": false, "snap_degrees": 15.0,
			"colour": Color("#1A1712"), "halo": 0.0,
			"halo_colour": Color("#FFF8E7"),
			"align": HORIZONTAL_ALIGNMENT_LEFT,
		}
	_mount(ToolPanels.text_maker(_text_state,
		func() -> void: pass,
		func() -> void: _place_text()), "text")

func _place_text() -> void:
	var words: String = String(_text_state.get("text", "")).strip_edges()
	if words == "":
		_flash(UiKit.label_for("Write something first", "اكتب شيئاً أولاً"))
		return
	var made: Image = await TextRender.render(_text_state)
	if made == null:
		_flash(UiKit.label_for("Could not draw that", "تعذّر رسم ذلك"))
		return
	var stack: LayerStack = view.layers
	var layer: LayerStack.Layer = stack.add_layer_here()
	if layer == null:
		_flash(UiKit.label_for("No room for another layer", "لا مكان لطبقة أخرى"))
		return
	layer.title = "%s — %s" % [UiKit.label_for("Text layer", "طبقة نص"),
		words.substr(0, 18)]
	layer.is_text = true
	layer.text_state = _text_state.duplicate(true)
	layer.text_turn = 0.0

	# Centred on **what is on screen**, not on the page.
	#
	# It was centred on the page, and on a page zoomed into or scrolled away
	# from — which is most of the time somebody is working — the writing
	# arrived somewhere off screen entirely. It looked like nothing had
	# happened. The middle of the view is where the eye already is, and it is
	# the only place a new thing can appear and be seen to have appeared.
	layer.text_scale = 1.0
	layer.text_size = Vector2(made.get_width(), made.get_height())
	var at: Vector2 = view.view_middle() - layer.text_size * 0.5
	layer.text_at = at.round()
	layer.surface.blit_image(made, layer.text_at, true)
	view.begin_text_box(layer.id)
	stack.changed.emit()
	view.projects.mark_dirty(view.projects.active)
	_close_panel()
	_flash(UiKit.label_for("Text layer added", "أُضيفت طبقة النص"))

## Writing that is already on the page, opened again.
##
## The words were kept, not just their picture, so this re-opens the same
## settings and re-renders from the text. Nothing is traced over or resampled.
func edit_text_layer(index: int) -> void:
	_close_panel()
	var stack: LayerStack = view.layers
	if index < 0 or index >= stack.layers.size():
		return
	var l: LayerStack.Layer = stack.layers[index]
	if not l.is_text:
		return
	stack.set_active(index)
	_text_state = l.text_state.duplicate(true)
	view.begin_text_box(l.id)
	_mount(ToolPanels.text_maker(_text_state,
		func() -> void: pass,
		func() -> void: _restyle_text(l)), "text")

## The box was let go of, so the writing is drawn again where and how it now
## sits. This is the whole reason text keeps its edge no matter how often it
## is turned: it is never a picture being rotated, always words being written.
func _redraw_text_layer(layer_id: int) -> void:
	var stack: LayerStack = view.layers
	var l: LayerStack.Layer = null
	for one in stack.layers:
		if one.id == layer_id:
			l = one
			break
	if l == null or not l.is_text or l.text_state.is_empty():
		return
	# Rendered at the size the box was dragged to, rather than rendered once
	# and scaled. This is what keeps writing sharp: a caption pulled to twice
	# the size is set again at twice the point size, so its edges are as
	# clean as they were, and pulled back down it loses nothing either.
	var doc: Dictionary = l.text_state.duplicate(true)
	doc["turn"] = l.text_turn
	doc["size"] = float(l.text_state.get("size", 64.0)) * maxf(l.text_scale, 0.05)
	var made: Image = await TextRender.render(doc)
	if made == null:
		return
	# The rendered picture grows when the writing is turned — a slanted line
	# needs a wider rectangle to sit in. The box must not: it is the writing's
	# own size, not the size of the paper it happens to be drawn on, or every
	# turn would inflate it a little and it would never come back.
	if l.text_size.x < 0.5:
		l.text_size = Vector2(made.get_width(), made.get_height())
	view.replace_text_at(layer_id, made, l.text_at)

func _restyle_text(l: LayerStack.Layer) -> void:
	var words: String = String(_text_state.get("text", "")).strip_edges()
	if words == "":
		_flash(UiKit.label_for("Write something first", "اكتب شيئاً أولاً"))
		return
	var doc: Dictionary = _text_state.duplicate(true)
	doc["turn"] = l.text_turn
	var made: Image = await TextRender.render(doc)
	if made == null:
		return
	l.text_state = _text_state.duplicate(true)
	# New words are a new shape, so the box is measured again from them —
	# and the scale is folded into the stored size and reset, so the box the
	# person sees is the box they will drag.
	l.text_size = Vector2(made.get_width(), made.get_height())
	l.text_scale = 1.0
	view.replace_text_pixels(l.id, made)
	_close_panel()
	_flash(UiKit.label_for("Text updated", "حُدّث النص"))

## Takes the skeleton off a layer and gives the drawing back.
##
## Everything a rig touches has to be undone together, or the layer is left in
## a state that is worse than either: a drawing that is no longer posed and is
## still refusing to be drawn on.
##
## **The bones go**, which is what unlocks the frames — see
## `LayerStack.frames_locked`, where an empty rig is the whole test.
##
## **The poses go with them.** A pose track is a list of angles for bones that
## no longer exist; keeping it would mean a layer that snapped back into a
## posture the moment it was rigged again.
##
## **The skin comes off and the drawing comes back.** While a layer is posed
## it is not drawn by its own surface at all — a mesh stands in for it and the
## surface is hidden. Taking that away without putting the surface back would
## leave the layer looking empty, which is the one outcome that would make
## somebody think their work had been deleted.
##
## The pixels are never touched. The drawing is exactly the drawing it was
## before a bone was ever put on it.
func _strip_rig(index: int) -> void:
	if view == null or view.layers == null:
		return
	if index < 0 or index >= view.layers.layers.size():
		return
	var l: LayerStack.Layer = view.layers.layers[index]
	if l.rig.is_empty():
		return
	l.rig = {}
	if l.poses != null:
		l.poses = RigTrack.new()
	# `shed_skin` puts the surface back on its own, and does it in a way that
	# leaves a layer the user has hidden hidden. Setting `visible` here as
	# well would be this function having an opinion about something
	# `_apply_looks` owns.
	view.layers.shed_skin(l)
	view.layers.changed.emit()
	if view.player != null:
		view.player.refresh_visuals()
	view.projects.mark_dirty(view.projects.active)
	_flash(UiKit.label_for("Bones removed — the drawing is yours again",
		"أُزيلت العظام — عادت الرسمة إليك"))

func _room_shell(inside: bool) -> void:
	if rail != null:
		rail.visible = not inside and view.projects.focus_on != null
	if edit_bar != null:
		edit_bar.visible = not inside and view.projects.focus_on != null
	if layer_btn_bar != null:
		layer_btn_bar.visible = not inside
	if coord_bar != null:
		coord_bar.visible = not inside and view.projects.focus_on != null
	if timeline_btn != null and inside:
		timeline_btn.visible = false
	if not inside:
		_sync_shell()
		_refresh_timeline_button()
		_refresh_action_bar()
	_layout()

# ---------------------------------------------------------------- bone room

## The layer, on its own, to take a skeleton.
##
## Reached from the layer's own settings rather than from the compass, because
## a skeleton is a fact about one drawing and belongs where that drawing is
## being talked about. Everything else on the screen steps aside while it is
## open, which is the same rule the other rooms follow: a full-screen room has
## exactly one way out and it must not be competing with a tool rail.
func enter_bone_room(index: int) -> void:
	_close_panel()
	if bone_room != null or bspline_room != null:
		return
	if view != null:
		# Any pose in progress ends before the layer is read, so what the room
		# captures is the drawing rather than a stand-in bent over it.
		BoneHandle.drop(view)
		if view.layers != null:
			view.layers.shed_all_skins()
	var room: BoneRoom = BoneRoom.new()
	if not room.setup(view, index):
		room.queue_free()
		_flash(UiKit.label_for("Draw something on this layer first",
			"ارسم شيئاً على هذه الطبقة أولاً"))
		return
	bone_room = room
	room.closed.connect(_leave_bone_room)
	room.accepted.connect(_bones_accepted)
	_ui.add_child(room)
	_bspline_shell(true)

## The skeleton was accepted. The room closes and the figure is immediately
## posable where it stands — there is no further step, and no mode to enter.
func _bones_accepted(index: int) -> void:
	_leave_bone_room()
	if view != null and view.layers != null:
		view.layers.set_active(index)
		BoneHandle.restore(view)
	_flash(UiKit.label_for("Bones merged. Drag a joint to move the drawing.",
		"دُمجت العظام. اسحب مفصلاً لتحريك الرسم."))

## Takes the skeleton off a layer and hands it back to every ordinary tool.
##
## One undo step, like everything else a layer can be told to do. And the
## stand-in goes with it: a posed skin outliving the rig that posed it is a
## drawing frozen in a shape nothing can now reach.
func _strip_bones(index: int) -> void:
	if view == null or view.layers == null:
		return
	if index < 0 or index >= view.layers.layers.size():
		return
	var l: LayerStack.Layer = view.layers.layers[index]
	if l == null or l.rig.is_empty():
		return
	BoneHandle.drop(view)
	var before: Array = view.layers.snapshot_state()
	l.rig = {}
	view.layers.shed_skin(l)
	view.layers.record_state(
		UiKit.label_for("Remove bones", "إزالة العظام"), before)
	view.queue_redraw()
	if view.overlay != null:
		view.overlay.queue_redraw()
	_flash(UiKit.label_for("Bones removed — the layer can be drawn on again",
		"أُزيلت العظام — صارت الطبقة تقبل الرسم"))

func _leave_bone_room() -> void:
	if bone_room == null:
		return
	bone_room.queue_free()
	bone_room = null
	_bspline_shell(false)

# ------------------------------------------------------------- b-spline room

## The folder, opened as one figure.
func enter_animation_layer(group_id: int) -> void:
	_close_panel()
	if bspline_room != null:
		return
	var room: BSplineRoom = BSplineRoom.new()
	if not room.setup_group(view, group_id):
		room.queue_free()
		_flash(UiKit.label_for("Nothing in this folder has bones yet",
			"لا شيء في هذا المجلد له عظام بعد"))
		return
	bspline_room = room
	room.closed.connect(_leave_bspline_room)
	# **Applied means done.**
	#
	# It used to stamp the drawing, say "Applied", and leave the room open —
	# so the work was saved and the person was still standing in the room
	# with no sign that anything had concluded. The usual next move was to
	# press it again, which stamps a second time.
	#
	# A button called Apply is the end of a task. The project is written and
	# the room closes, which is what every other room here does and what the
	# word means everywhere else.
	room.applied.connect(func() -> void:
		_leave_bspline_room()
		save_project()
		_flash(UiKit.label_for("Applied and saved",
			"طُبّق وحُفظ")))
	_ui.add_child(room)
	_bspline_shell(true)

func _leave_bspline_room() -> void:
	if bspline_room == null:
		return
	# Any stand-in mesh goes with the room. A skin outliving the thing that
	# posed it is a drawing frozen in a pose nobody can now change.
	if view != null and view.layers != null:
		view.layers.shed_all_skins()
	bspline_room.queue_free()
	bspline_room = null
	_bspline_shell(false)

## The room is the whole screen while it is open, so the shell steps aside
## entirely — the only way out is the one door it puts at the top right.
func _bspline_shell(inside: bool) -> void:
	if rail != null:
		rail.visible = not inside and view.projects.focus_on != null
	if edit_bar != null:
		edit_bar.visible = not inside and view.projects.focus_on != null
	if layer_btn_bar != null:
		layer_btn_bar.visible = not inside
	if coord_bar != null:
		coord_bar.visible = not inside and view.projects.focus_on != null
	if timeline_btn != null and inside:
		timeline_btn.visible = false
	if not inside:
		_sync_shell()
		_refresh_timeline_button()
		_refresh_action_bar()
	_layout()

# ------------------------------------------------------------ puppet warp

## While a layer is being bent there is nothing else the screen should be
## offering, so the bar carries only the three things left to decide: change
## how it bends, put it down, or take it back.
func _build_puppet_bar() -> void:
	puppet_bar = PanelContainer.new()
	puppet_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	puppet_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	puppet_bar.visible = false
	_ui.add_child(puppet_bar)
	puppet_bar.resized.connect(_layout)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	puppet_bar.add_child(row)

	var tune: Button = UiKit.make_text_button(
		UiKit.label_for("Settings", "الإعدادات"), true)
	tune.custom_minimum_size = Vector2(UiKit.s(108.0), UiKit.s(46.0))
	tune.pressed.connect(func() -> void:
		_close_panel()
		_mount(ToolPanels.puppet_warp(view), "puppet"))
	row.add_child(tune)

	var drop: Button = UiKit.make_text_button(
		UiKit.label_for("Cancel", "إلغاء"), true)
	drop.custom_minimum_size = Vector2(UiKit.s(100.0), UiKit.s(46.0))
	drop.pressed.connect(func() -> void: _finish_puppet(false))
	row.add_child(drop)

	var keep: Button = UiKit.make_text_button(
		UiKit.label_for("Apply", "تطبيق"), true)
	keep.custom_minimum_size = Vector2(UiKit.s(118.0), UiKit.s(46.0))
	keep.pressed.connect(func() -> void: _finish_puppet(true))
	row.add_child(keep)

## While a warp is on, everything that draws or edits pixels steps aside.
##
## The layer being bent has been emptied for the duration, so an undo or a
## brush stroke landing on it now would be acting on a page that is not
## really there. Taking the controls off screen is more honest than leaving
## them where they are and quietly ignoring them.
func _puppet_shell(warping: bool) -> void:
	var inside: bool = view.projects.focus_on != null
	if rail != null:
		rail.visible = inside and not warping
	if edit_bar != null:
		edit_bar.visible = inside and not warping
	if action_bar != null:
		action_bar.visible = not warping
	if coord_bar != null:
		coord_bar.visible = inside and not warping
	if timeline_btn != null and warping:
		timeline_btn.visible = false
	if not warping:
		_sync_shell()
		_refresh_timeline_button()
		_refresh_action_bar()
	_layout()

func start_puppet_warp(_index: int = -1) -> void:
	_close_panel()
	if not view.begin_puppet_warp():
		_flash(UiKit.label_for("Draw something first", "ارسم شيئاً أولاً"))
		return
	if puppet_bar != null:
		puppet_bar.visible = true
	_puppet_shell(true)
	_flash(UiKit.label_for("Pin what should stay, then pull what should move",
		"ثبّت ما يجب أن يبقى، ثم اسحب ما يجب أن يتحرك"))
	_layout()

func _finish_puppet(keep: bool) -> void:
	_close_panel()
	await view.end_puppet_warp(keep)
	if puppet_bar != null:
		puppet_bar.visible = false
	_puppet_shell(false)
	_flash(UiKit.label_for("Puppet warp applied", "طُبّق التحريك بالدبابيس")
		if keep else UiKit.label_for("Puppet warp cancelled", "أُلغي التحريك بالدبابيس"))
	_layout()

# ------------------------------------------------------- symmetry quick exit

func _build_symmetry_cancel() -> void:
	_btn_symmetry_cancel = UiKit.make_text_button(
		UiKit.label_for("Cancel symmetry", "إلغاء التناظر"), true)
	_btn_symmetry_cancel.visible = false
	_btn_symmetry_cancel.custom_minimum_size = Vector2(UiKit.s(172.0), UiKit.s(42.0))
	_btn_symmetry_cancel.pressed.connect(func() -> void:
		view.cancel_lateral_symmetry())
	_ui.add_child(_btn_symmetry_cancel)

func _on_symmetry_mode_changed(enabled: bool) -> void:
	if _btn_symmetry_cancel == null:
		return
	_btn_symmetry_cancel.visible = enabled and view.has_project()
	_layout()

# ------------------------------------------------------------- input event

## The move tool: pick the drawing up and put it somewhere else.
##
## This button used to open a panel holding copy and paste and nothing else,
## which is two marks that already have marks of their own beside it. Now it
## is the tool it is named for — the one thing in the app that takes hold of
## what is already drawn without being told what it is first.

func _open_input_event() -> void:
	_close_panel()
	if not MoveTool.take(view):
		_flash(UiKit.label_for("Nothing on this layer to move",
			"لا شيء في هذه الطبقة ليُحرَّك"))
		return
	App.set_tool(App.Tool.MOVE)
	_mount(ComicToolPanels.mover(
		func() -> void: _finish_move(),
		func() -> void: MoveTool.revert(view)), "move")
	view.overlay.queue_redraw()

## The move is over: the drawing is written where the box now is.
func _finish_move() -> void:
	var moved: bool = MoveTool.commit(view)
	App.set_tool(App.Tool.BRUSH)
	_close_panel()
	view.overlay.queue_redraw()
	if moved:
		view.projects.mark_dirty(view.projects.active)
		_flash(UiKit.label_for("Moved", "تمّ التحريك"))

# ---------------------------------------------------------------------- AI
#
# Three features, one pipeline. What is here is only the joining: taking a
# drawing off a layer, putting a picture back onto one, and opening the room.
# Everything about tokens, waiting and decoding lives in `ai_assistant.gd`.

func _layer_sketch(index: int) -> Image:
	return AiBridge.layer_sketch(self, index)

func improve_layer(index: int) -> void:
	AiBridge.improve_layer(self, index)

func _on_ai_picture(_id: int, picture: Image, _texture: ImageTexture,
		job: Dictionary) -> void:
	AiBridge.on_ai_picture(self, _id, picture, _texture, job)

func _place_ai_picture(picture: Image, own_layer: bool) -> void:
	AiBridge.place_ai_picture(self, picture, own_layer)

## What kind of project is open, or -1 when none is.
func _project_kind() -> int:
	var p: ProjectManager.Project = current_project()
	return p.kind if p != null else -1

## One of the comic tools, chosen from the compass.
##
## Comic-specific tools all enter through one small dispatcher.
func open_comic_tool(key: String) -> void:
	_close_panel()
	ComicBoard.on_done = func() -> void: _comic_mode_over()
	ComicBoard.on_change = func() -> void: _refresh_panels()
	match key:
		"panels":
			ComicBoard.mode = ComicBoard.Mode.CUT
			_mount(ComicToolPanels.panels(self, view), "panels")

## The frames panel, rebuilt after a choice inside it so what it shows is what
## is true. Cheap: the panel is a dozen buttons and rebuilding it is how every
## other panel in the app stays honest.
func _refresh_panels() -> void:
	if open_panel != "panels":
		return
	_close_panel()
	_mount(ComicToolPanels.panels(self, view), "panels")

## Leaves whichever comic-only mode was in force.
func end_comic_mode() -> void:
	ComicBoard.mode = ComicBoard.Mode.OFF
	ComicBoard.release_quietly()

## A comic-only mode has finished and the normal drawing hand can return.
func _comic_mode_over() -> void:
	end_comic_mode()
	_close_panel()
	_flash(UiKit.label_for("Back to the brush", "عودة إلى الفرشاة"))

## The symmetry panel, now reached from the compass.
func open_symmetry() -> void:
	_close_panel()
	_mount(ToolPanels.lateral_symmetry(view), "symmetry")

## Stretchy Studio is opened only from Animation project settings. Its advanced
## controls live in the room, while the selected animation project owns the
## canvas size, save record and return path.
func open_stretchy_studio() -> void:
	_close_panel()
	var project: ProjectManager.Project = current_project()
	if project == null or project.kind != ProjectManager.Kind.ANIMATION:
		_flash(UiKit.label_for("Open an animation project first", "افتح مشروع رسوم متحركة أولاً"))
		return
	if stretchy_room != null:
		return
	stretchy_room = StretchyStudioStandalone.new()
	stretchy_room.setup(self, project)
	stretchy_room.closed.connect(_leave_stretchy_room)
	_ui.add_child(stretchy_room)
	_room_shell(true)
func _leave_stretchy_room() -> void:
	if stretchy_room == null:
		return
	stretchy_room.commit_to_project()
	var project: ProjectManager.Project = current_project()
	if project != null:
		view.projects.mark_dirty(project)
		Vault.save(project)
	stretchy_room.queue_free()
	stretchy_room = null
	_room_shell(false)
	_flash(UiKit.label_for("Stretchy Studio closed — back to projects", "أُغلقت Stretchy Studio — عدت إلى لوحة المشاريع"))
func open_ai_room() -> void:
	AiBridge.open_ai_room(self)

# ------------------------------------------------------------------ panels

func _toggle_panel(id: String) -> void:
	var was: String = open_panel
	_close_panel()
	if was == id:
		return

	var built: PanelContainer = null
	if id == "brush":
		built = ToolPanels.brush(view)
	elif id == "eraser":
		built = ToolPanels.eraser(view)
	elif id == "blend":
		built = ToolPanels.blend(view)
	elif id == "shapes":
		built = ToolPanels.shapes(view)
	elif id == "select":
		built = ToolPanels.selection(view)
	elif id == "color":
		built = ToolPanels.color(view, false)
	elif id == "fill":
		built = ToolPanels.fill(view)
	elif id == "layers":
		if not view.has_project():
			_flash(UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
			return
		layers_panel = LayersPanel.new()
		layers_panel.setup(view)
		layers_panel.solo_requested.connect(_enter_solo)
		layers_panel.import_requested.connect(_ask_for_image)
		layers_panel.bones_requested.connect(enter_bone_room)
		layers_panel.bones_removed.connect(_strip_bones)
		layers_panel.puppet_requested.connect(start_puppet_warp)
		layers_panel.animation_layer_requested.connect(enter_animation_layer)
		layers_panel.text_edit_requested.connect(edit_text_layer)
		layers_panel.improve_requested.connect(improve_layer)
		layers_panel.rig_removal_requested.connect(_strip_rig)
		built = layers_panel
		_thumb_timer = 0.0
	elif id == "compass":
		if not view.has_project():
			_flash(UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
			return
		built = _compass_panel()
	elif id == "stretchy":
		open_stretchy_studio()
		return
	elif id == "make":
		_settings_page = "make"
		built = SettingsPanels.make_menu(self)
	elif id == "settings":
		_settings_page = "menu"
		built = SettingsPanels.menu(self)
	if built == null:
		return

	_show_shade(true)
	panel_host = built
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ui.add_child(panel_host)
	panel_host.resized.connect(_layout)
	panel_host.resized.connect(_claim_panel_space)
	open_panel = id
	_fit_panel_to_content()
	_layout()
	call_deferred("_fit_panel_to_content")
	call_deferred("_claim_panel_space")

## The shade sits at the bottom of the interface layer: above the drawing,
## below every button. So a tap on the canvas closes the panel, while the
## tool rail and the bars keep working — switching straight from one panel
## to another without a wasted tap in between.
func _show_shade(on: bool) -> void:
	if _shade == null:
		return
	_shade.visible = on
	if on:
		_ui.move_child(_shade, 0)

## A panel closes when the user taps away from it — press and release both
## outside it, close together. Closing on the press alone was enough while
## every touch stayed where it started, but a finger that scrolls a panel
## and drifts past its edge releases out here, and the panel it was reading
## went away underneath it. So both ends of the tap have to agree.
func _shade_touched(event: InputEvent) -> void:
	if panel_host == null:
		_show_shade(false)
		return
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_shade_from = st.position
			_shade_armed = true
		elif _shade_armed:
			_shade_armed = false
			if _shade_from.distance_to(st.position) <= UiKit.s(28.0):
				_close_panel()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_shade_from = mb.position
			_shade_armed = true
		elif _shade_armed:
			_shade_armed = false
			if _shade_from.distance_to(mb.position) <= UiKit.s(28.0):
				_close_panel()

func _fit_panel_to_content() -> void:
	if panel_host == null:
		return
	var room: Vector2 = size - Vector2(UiKit.s(24.0), UiKit.s(24.0))
	var desired: float = 0.0
	if panel_host.has_meta("desired_width"):
		desired = float(panel_host.get_meta("desired_width"))
	var minimum: Vector2 = panel_host.get_combined_minimum_size()
	var width: float = maxf(minimum.x, UiKit.s(240.0))
	if desired > 0.0:
		width = minf(maxf(width, minf(desired, room.x)), room.x)
	width = minf(width, room.x)
	var content_h: float = maxf(minimum.y, UiKit.s(52.0))
	var height: float = minf(content_h, room.y)
	panel_host.custom_minimum_size = Vector2(width, height)
	panel_host.size = Vector2(width, height)

## Tells the canvas exactly where the open panel is sitting.
##
## Godot routes a press that lands on a *control* to that control, which covers
## the buttons. It does not cover the panel itself: a floating card is rounded,
## padded and separated, and the corners, the margins and the gaps between its
## rows are not controls. A press there falls straight through and draws a mark
## inside what the user sees as a solid opaque panel — the exact complaint about
## the drawing area fighting the controls.
##
## Registered as one rect, refreshed whenever the panel is laid out again,
## because a panel that grows a row must not leave the old smaller rect behind.
func _claim_panel_space() -> void:
	if panel_host == null or not is_instance_valid(panel_host):
		TouchSpace.release("panel")
		return
	TouchSpace.claim("panel", panel_host.get_global_rect())

func _close_panel() -> void:
	_shade_armed = false
	TouchSpace.release("panel")
	if panel_host != null:
		panel_host.queue_free()
		panel_host = null
	layers_panel = null
	open_panel = ""
	_show_shade(false)
	_sync_rail()

# --------------------------------------------------------------- solo view

func _build_solo_bar() -> void:
	solo_bar = PanelContainer.new()
	solo_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	solo_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	solo_bar.visible = false
	_ui.add_child(solo_bar)
	solo_bar.resized.connect(_layout)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(8.0)))
	solo_bar.add_child(row)

	var back: Button = UiKit.make_text_button(UiKit.label_for("Back", "رجوع"))
	back.pressed.connect(_leave_solo)
	row.add_child(back)

	var note: Label = UiKit.make_label(
		UiKit.label_for("This layer only", "هذه الطبقة وحدها"), 12.0, UiKit.ON_RAIL)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)

## Shows one layer by itself, so it can be checked without the rest in the
## way. Nothing is changed — the others are only hidden for the moment.
func _enter_solo(index: int) -> void:
	if index < 0 or index >= view.layers.layers.size():
		return
	solo_index = index
	view.layers.set_active(index)
	view.layers.set_solo(view.layers.layers[index].id)
	_close_panel()
	_sync_rail()
	solo_bar.visible = true
	_layout()

func _leave_solo() -> void:
	solo_index = -1
	view.layers.set_solo(0)
	solo_bar.visible = false

# --------------------------------------------------------- floating pieces

func _build_action_bar() -> void:
	action_bar = PanelContainer.new()
	action_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	action_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	action_bar.visible = false
	_ui.add_child(action_bar)
	action_bar.resized.connect(_layout)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(6.0)))
	action_bar.add_child(row)

	_btn_close_shape = UiKit.make_text_button(
		UiKit.label_for("Close shape", "أغلق الشكل"), true)
	_btn_close_shape.pressed.connect(func() -> void: view.close_selection())
	row.add_child(_btn_close_shape)

	_btn_place = UiKit.make_text_button(UiKit.label_for("Place", "ثبّت"))
	_btn_place.pressed.connect(func() -> void: view.commit_selection())
	row.add_child(_btn_place)

	_btn_cancel = UiKit.make_text_button(UiKit.label_for("Cancel", "إلغاء"))
	_btn_cancel.pressed.connect(func() -> void: view.cancel_selection())
	row.add_child(_btn_cancel)

func _refresh_action_bar() -> void:
	if action_bar == null:
		return
	var floating: bool = view.sel_active
	var marking: bool = view.has_marks() and App.select_shape == App.SelectShape.POLY
	_btn_close_shape.visible = marking and not floating
	_btn_place.visible = floating
	_btn_cancel.visible = floating
	action_bar.visible = floating or marking
	_layout()

# ----------------------------------------------------------- small readouts

func _build_coord_bar() -> void:
	coord_bar = PanelContainer.new()
	coord_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	coord_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	coord_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(coord_bar)
	coord_bar.resized.connect(_layout)

	coord_label = UiKit.make_label("X 0   Y 0", 11.0, UiKit.ON_RAIL)
	coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coord_label.custom_minimum_size = Vector2(UiKit.s(148.0), 0.0)
	coord_bar.add_child(coord_label)

func _build_zoom_badge() -> void:
	zoom_badge = PanelContainer.new()
	zoom_badge.add_theme_stylebox_override("panel", UiKit.rail_style())
	zoom_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	zoom_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_badge.visible = false
	_ui.add_child(zoom_badge)
	zoom_badge.resized.connect(_layout)

	zoom_label = UiKit.make_label("100%", 15.0, Color.WHITE)
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_label.custom_minimum_size = Vector2(UiKit.s(96.0), 0.0)
	zoom_badge.add_child(zoom_label)

## Undo now reaches structure as well as pixels, and a layer reappearing at
## the far end of a list is easy to miss. A one-line note says what moved.
func _build_note_badge() -> void:
	note_badge = PanelContainer.new()
	note_badge.add_theme_stylebox_override("panel", UiKit.rail_style())
	note_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	note_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_badge.visible = false
	_ui.add_child(note_badge)
	note_badge.resized.connect(_layout)

	note_label = UiKit.make_label("", 12.0, UiKit.ON_RAIL)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.custom_minimum_size = Vector2(UiKit.s(150.0), 0.0)
	note_badge.add_child(note_label)

func _flash(text: String) -> void:
	if note_label == null:
		return
	note_label.text = text
	note_badge.visible = true
	_note_timer = 1.1
	_layout()

## Undo now reaches structure as well as pixels, and a layer reappearing at
## the far end of a list is easy to miss. A one-line note says what moved.
func _on_action(label: String, undone: bool) -> void:
	_flash(("< " if undone else "> ") + label)

## The bar that only exists inside focus: a way out, a way to bring the
## neighbours back, and — for a comic — the page controls, which belong
## here rather than buried in a menu.
## The focus controls live in the project's own menu, reached from the strip
## above it. A permanent bar across the bottom of the screen is a bar across
## the drawing — the one place that has to stay clear.
func _refresh_focus_bar() -> void:
	_refresh_page_bar()
	_refresh_timeline_button()
	if open_panel == "settings" and _options_for != null:
		_show_project_options(_options_for)

## Turning pages is something a reader does constantly, so it belongs under
## the thumb rather than three taps deep in a menu. It appears only while a
## multi-page project is focused, and takes no room at any other time.
func _build_page_bar() -> void:
	page_bar = PanelContainer.new()
	page_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	page_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	page_bar.visible = false
	_ui.add_child(page_bar)
	page_bar.resized.connect(_layout)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	page_bar.add_child(row)

	var prev: Button = UiKit.make_text_button(UiKit.label_for("Previous", "السابقة"), true)
	prev.custom_minimum_size = Vector2(UiKit.s(96.0), UiKit.s(46.0))
	prev.pressed.connect(func() -> void: page_step(-1))
	row.add_child(prev)

	# The plus sits between them, where a thumb reaching for "one more" will
	# already be, and reads as one mark rather than a word to parse.
	var more: Button = UiKit.make_text_button("+")
	more.custom_minimum_size = Vector2(UiKit.s(58.0), UiKit.s(46.0))
	more.add_theme_font_size_override("font_size", int(UiKit.s(22.0)))
	more.tooltip_text = UiKit.label_for("Add page", "أضف صفحة")
	more.pressed.connect(add_page_here)
	row.add_child(more)

	var next: Button = UiKit.make_text_button(UiKit.label_for("Next", "التالية"), true)
	next.custom_minimum_size = Vector2(UiKit.s(96.0), UiKit.s(46.0))
	next.pressed.connect(func() -> void: page_step(1))
	row.add_child(next)

	_page_label = UiKit.make_label("1/1", 12.0, UiKit.ON_RAIL)
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(UiKit.s(52.0), 0.0)
	row.add_child(_page_label)

## Alone in the bottom-left corner, away from everything else, because it
## changes the shape of the whole document rather than the current page.
func _build_layout_bar() -> void:
	layout_bar = PanelContainer.new()
	layout_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	layout_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	layout_bar.visible = false
	_ui.add_child(layout_bar)
	layout_bar.resized.connect(_layout)

	_layout_btn = UiKit.make_text_button(UiKit.label_for("Side by side", "جنباً إلى جنب"), true)
	_layout_btn.custom_minimum_size = Vector2(UiKit.s(120.0), UiKit.s(46.0))
	_layout_btn.pressed.connect(toggle_layout)
	layout_bar.add_child(_layout_btn)

## Bottom right, and only while an animation project is focused. The
## timeline is the one panel that belongs to a single kind of project, so a
## button for it in the general rail was a button that did nothing most of
## the time.
func _build_timeline_button() -> void:
	timeline_btn = PanelContainer.new()
	timeline_btn.add_theme_stylebox_override("panel", UiKit.rail_style())
	timeline_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	timeline_btn.visible = false
	_ui.add_child(timeline_btn)
	timeline_btn.resized.connect(_layout)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	timeline_btn.add_child(row)

	var b: Button = UiKit.make_text_button(
		UiKit.label_for("Timeline", "التايم لاين"), true)
	b.custom_minimum_size = Vector2(UiKit.s(126.0), UiKit.s(46.0))
	b.pressed.connect(_toggle_timeline)
	row.add_child(b)

func _refresh_timeline_button() -> void:
	if timeline_btn == null:
		return
	var p: ProjectManager.Project = current_project()
	timeline_btn.visible = p != null and p.kind == ProjectManager.Kind.ANIMATION
	_layout()

func _refresh_page_bar() -> void:
	if page_bar == null:
		return
	var p: ProjectManager.Project = view.projects.focus_on
	var wanted: bool = p != null and p.kind == ProjectManager.Kind.COMIC
	page_bar.visible = wanted
	if layout_bar != null:
		layout_bar.visible = wanted
	if wanted:
		_page_label.text = "%d/%d" % [_comic_page + 1, p.pages]
		if _layout_btn != null:
			_layout_btn.text = UiKit.label_for("Side by side", "جنباً إلى جنب") \
				if p.stacked else UiKit.label_for("Stacked", "فوق بعضها")
	_layout()

## The timeline is not a floating panel: it is a band the canvas gives room
## to. So it lives outside the panel system, and the drawing area shrinks to
## meet it rather than being covered by it.
func _toggle_timeline() -> void:
	if timeline != null:
		_close_timeline()
		return
	var p: ProjectManager.Project = current_project()
	if p == null:
		_flash(UiKit.label_for("Open a project first", "افتح مشروعاً أولاً"))
		return
	if p.kind != ProjectManager.Kind.ANIMATION:
		_flash(UiKit.label_for("Animation projects only", "لمشاريع الرسوم المتحركة فقط"))
		return
	timeline = TimelinePanel.new()
	timeline.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ui.add_child(timeline)
	timeline.setup(view.player, p.clip, p.stack, view)
	timeline.closed.connect(_close_timeline)
	timeline.audio_wanted.connect(_ask_for_audio)
	_hook_audio_preview(p)
	timeline.resized.connect(_layout)
	_sync_rail()
	_refresh_timeline_button()
	_layout()

## Hidden, not closed: the clip and the playhead stay exactly where they
## were, and the same tap brings the band back.
func _toggle_timeline_visible() -> void:
	if timeline == null:
		_toggle_timeline()
		return
	timeline.visible = not timeline.visible
	_refresh_timeline_button()
	_layout()

func _close_timeline() -> void:
	if timeline == null:
		return
	timeline.queue_free()
	timeline = null
	_sync_rail()
	_refresh_timeline_button()
	_layout()

func _on_pointer(world_pos: Vector2) -> void:
	_last_world = world_pos
	_update_coords()

## Precision tracks the zoom: no fake decimals when far out, three when close.
func _update_coords() -> void:
	if coord_label == null or view == null:
		return
	var step: float = view.grid_step()
	coord_label.text = "X %s   Y %s" % [
		GridBackground.fmt(_last_world.x, step),
		GridBackground.fmt(_last_world.y, step)]

## The zoom badge is not a permanent fixture — it appears while the pinch is
## happening and fades out once the answer stops changing.
func _on_zoom(z: float) -> void:
	if zoom_label == null:
		return
	if not is_equal_approx(z, _last_zoom):
		_last_zoom = z
		_zoom_timer = ZOOM_HOLD
		zoom_badge.visible = true
	if z < 0.1:
		zoom_label.text = "%.1f%%" % (z * 100.0)
	else:
		zoom_label.text = "%d%%" % int(round(z * 100.0))
	_update_coords()
	_layout()

# ---------------------------------------------------------------- settings

func open_settings_page(page: String) -> void:
	SettingsRouter.open_settings_page(self, page)

## Settings pages own their button lifecycle. Navigation buttons rebuild the
## page, while actions such as presets deliberately keep the current page open.
## Do not attach a global close callback here: a deferred close could destroy a
## newly mounted page immediately after its action runs.

func _mount(built: PanelContainer, id: String) -> void:
	if built == null:
		return
	_show_shade(true)
	panel_host = built
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ui.add_child(panel_host)
	panel_host.resized.connect(_layout)
	panel_host.resized.connect(_claim_panel_space)
	open_panel = id
	_fit_panel_to_content()
	_layout()
	call_deferred("_fit_panel_to_content")
	call_deferred("_claim_panel_space")
	_sync_rail()

func current_project() -> ProjectManager.Project:
	return view.projects.active

## Changes the editor surface for this animation document only. The project
## remains an ordinary Animation card on the project board; Stretchy merely
## uses a black outer frame so its professional canvas reads as a dark stage.
func set_animation_ui_mode(mode: String) -> void:
	var p: ProjectManager.Project = current_project()
	if p == null or p.kind != ProjectManager.Kind.ANIMATION:
		return
	p.animation_ui = "stretchy" if mode == "stretchy" else "ivory"
	p.frame = Color("#000000") if p.animation_ui == "stretchy" \
		else ProjectManager.frame_for(p.kind)
	view.projects.mark_dirty(p)
	view.projects.projects_changed.emit()
	_sync_shell()

func mark_stretchy_dirty(project: ProjectManager.Project) -> void:
	if project == null:
		return
	view.projects.mark_dirty(project)
	Vault.save(project)

## New sheets appear in the middle of what the user is looking at, whatever
## corner of the endless grid that happens to be.
## Dedicated Stretchy creation path. The user chooses only the canvas here;
## the project is then handed straight to the standalone C++-backed Stretchy
## workspace, where its remaining animation settings live.
func open_stretchy_project_canvas_choice() -> void:
	close_or_switch_stretchy_launch_panel()
	var built: PanelContainer = SettingsPanels.stretchy_canvas_choice(self)
	_mount(built, "stretchy_canvas")

func close_or_switch_stretchy_launch_panel() -> void:
	_close_panel()

func spawn_stretchy_project(page_size: Vector2) -> void:
	var launcher: Object = Native.animation_launcher()
	if launcher == null:
		_flash(UiKit.label_for("Native C++ launcher unavailable", "وحدة C++ الأصلية غير متاحة"))
		return
	if not launcher.valid_workspace("stretchy"):
		_flash(UiKit.label_for("Invalid animation workspace", "بيئة رسوم غير صالحة"))
		return
	var index: int = view.projects.projects.size() + 1
	var title: String = "Stretchy %d" % index
	spawn_project(title, ProjectManager.Kind.ANIMATION, page_size,
		Color("#ffffff"), 1, int(launcher.default_fps()), Anim.OPENING_FRAMES)
	set_animation_ui_mode("stretchy")
	open_stretchy_studio()

func spawn_project(title: String, kind: int, page_size: Vector2,
		paper: Color, pages: int, fps: int = 24, frames: int = 24) -> void:
	var centre: Vector2 = view.screen_to_world(view.size * 0.5)
	var p: ProjectManager.Project = view.projects.create(
		title, kind, page_size, paper, pages, centre)
	if p != null and kind == ProjectManager.Kind.ANIMATION:
		p.fps = clampi(fps, 1, 60)
		p.frames = clampi(frames, 1, Anim.CEILING_FRAMES)
		for page in p.sheets:
			(page as ProjectManager.Page).clip.fps = p.fps
			(page as ProjectManager.Page).clip.length = p.frames
	if p == null:
		_flash(UiKit.label_for("Too many projects", "عدد المشاريع بلغ الحد"))
		return
	_close_panel()
	# A newly created project is immediately placed and opened, but its settings
	# stay closed until the user explicitly presses the Settings gear.
	view.projects.place(p)
	view.projects.open(p)
	view.projects.set_focus(p)
	view.frame_project(p)
	_comic_page = 0
	_sync_shell()
	_refresh_timeline_button()
	_refresh_focus_bar()
	_flash(p.title)

func set_language(code: int) -> void:
	Lang.current = code
	_close_panel()
	_rebuild_chrome()
	_flash(Lang.name_of(code))

## The swatch has answered; the sheet has nothing left to say.
func frame_colour_chosen() -> void:
	view.chrome.refresh(view.view_zoom)
	_close_panel()

func set_frame_colour(c: Color) -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	p.frame = c
	view.chrome.refresh(view.view_zoom)

func toggle_favourite() -> void:
	toggle_favourite_of(current_project())

func toggle_favourite_of(p: ProjectManager.Project) -> void:
	if p == null:
		return
	p.favourite = not p.favourite
	view.chrome.refresh(view.view_zoom)
	_close_panel()

## Writes the project to disk and leaves it open — the thing you want after
## an hour's work, which "save and close" was never quite.
func save_project() -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	if Vault.save(p):
		view.projects.mark_saved(p)
		_close_panel()
		_flash(UiKit.label_for("Saved", "حُفظ"))
	else:
		_flash(UiKit.label_for("Save failed — try again", "فشل الحفظ — حاول مرة أخرى"))

func save_and_close() -> void:
	close_project(current_project())

func close_project(p: ProjectManager.Project) -> void:
	if p == null:
		return
	if Vault.save(p):
		view.projects.mark_saved(p)
	if view.projects.focus_on == p:
		leave_focus()
	view.projects.close(p)
	_close_panel()
	_flash(UiKit.label_for("Save and close", "حفظ وإغلاق"))

func open_project(p: ProjectManager.Project) -> void:
	view.projects.open(p)
	if p != null:
		_comic_page = p.active_page
	_refresh_timeline_button()
	_close_panel()

func duplicate_project(p: ProjectManager.Project) -> void:
	view.projects.duplicate_project(p)
	_close_panel()

## Deleting means gone: from the workspace, from disk, and from anything
## left on disk that no longer answers to a project — which is what used to
## bring a deleted project back on the next launch.
func delete_project(p: ProjectManager.Project) -> void:
	if p == null:
		return
	if view.projects.focus_on == p:
		leave_focus()
	Vault.forget(p.id)
	view.projects.remove(p)
	Vault.purge_orphans(view.projects)
	_sync_shell()
	_refresh_timeline_button()
	_close_panel()
	_flash(UiKit.label_for("Deleted", "حُذف"))

func add_page(p: ProjectManager.Project) -> void:
	view.projects.add_page(p)
	_close_panel()

# ---------------------------------------------- transfer of the decree

## The three answers, kept here rather than inside a panel.
##
## Panels are built and thrown away — by a language change, by a rotation, by
## backing out of one screen and into it again. Anything held inside one is
## held for as long as that panel happens to live, which is not long enough to
## carry an answer from the first screen to the third.
var _transfer: DrawTransfer.Plan = null

func transfer_plan() -> DrawTransfer.Plan:
	if _transfer == null:
		_transfer = DrawTransfer.Plan.new()
	return _transfer

## Begun fresh every time. A plan half-filled from an hour ago, pointing at a
## project that has since been deleted, is worse than no plan.
func begin_transfer() -> void:
	var p: ProjectManager.Project = current_project()
	if not DrawTransfer.offered_by(p):
		return
	_transfer = DrawTransfer.Plan.new()
	_transfer.source = p
	_transfer.page = p.active_page
	# So the picker has pictures to show rather than empty boxes on the first
	# screen it is ever opened on.
	var page: ProjectManager.Page = p.page_at(p.active_page)
	if page != null and page.stack != null:
		page.stack.refresh_all_thumbs()
	open_settings_page("transfer")

## After a project board is tapped.
##
## With one layer chosen there is nothing to ask: one layer landing as one
## layer and one layer landing as several are the same act, and a screen whose
## two buttons do the identical thing teaches the user that the question was
## never real. So it is skipped, and only skipped, in exactly that case.
func choose_transfer_target() -> void:
	var plan: DrawTransfer.Plan = transfer_plan()
	if plan.target == null:
		return
	if plan.count() <= 1:
		finish_transfer(false)
		return
	open_settings_page("transfer_how")

## The last answer, and then the drawing goes on its way.
##
## The arithmetic runs to the end here, but the *page* is not written to. What
## comes back is a picture and the pieces behind it; the target project is
## opened and focused, the picture is floated inside it in the ordinary
## transform box, and the user puts it where it goes. Pressing anywhere outside
## the box lands it.
##
## Opening the target is not a side effect — it is the point. A transfer that
## finished silently into a project you were not looking at gave you no way to
## see where it had gone or to say it was wrong.
func finish_transfer(merge: bool) -> void:
	var plan: DrawTransfer.Plan = transfer_plan()
	plan.merge = merge
	var prepared: Dictionary = DrawTransfer.prepare(view.projects, plan)
	_close_panel()
	if not bool(prepared["ok"]):
		_transfer = null
		_flash(String(prepared["message"]))
		return

	var landing: DrawTransfer.Landing = prepared["landing"]
	_transfer = null

	# Focus rather than merely open: the drawing has to be visible at a size
	# the hand can aim at before being asked where it should sit, and on a
	# phone the workspace view of a page is a thumbnail.
	focus_project(landing.target)
	if landing.target.kind == ProjectManager.Kind.COMIC:
		_comic_page = landing.target_page
	# The selection tool, because the box that has just appeared is a selection
	# box and every one of its handles belongs to that tool. Arriving with the
	# brush still chosen would mean the first stroke meant to nudge the drawing
	# drew a line across it instead.
	App.current_tool = App.Tool.SELECT
	_sync_shell()

	if not view.begin_placement(landing):
		_flash(UiKit.label_for("Nothing to transfer", "لا شيء لنقله"))

## Focus fills the screen with one project and takes the neighbours out of
## sight — and out of the render. Zoom and pan stay free inside it.
func focus_project(p: ProjectManager.Project) -> void:
	if p == null:
		return
	view.projects.open(p)
	_comic_page = p.active_page
	view.projects.set_focus(p)
	p.grid_guide = true
	view.frame_project(p)
	_comic_page = 0
	_close_panel()
	_sync_shell()
	_flash(UiKit.label_for("Turn with two fingers", "أدر بإصبعين"))

func leave_focus() -> void:
	# A drawing still being placed has nowhere to go once the project it was
	# being placed into leaves the screen. Nothing was written to that project,
	# so letting go costs nothing — where leaving the box behind would strand a
	# set of handles over a page that is no longer under them.
	view.cancel_placement()
	var p: ProjectManager.Project = view.projects.focus_on
	if p != null:
		p.grid_guide = false
	view.projects.clear_focus()
	_sync_shell()
	_refresh_focus_bar()

func toggle_neighbours() -> void:
	view.projects.set_focus_shows_others(not view.projects.focus_shows_others)
	_refresh_focus_bar()

func toggle_guide() -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	p.grid_guide = not p.grid_guide
	view.projects.move_to(p, p.origin)

func page_step(delta: int) -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	_comic_page = clampi(_comic_page + delta, 0, p.pages - 1)
	# Turning the page changes which drawing the tools touch, not just
	# where the camera looks.
	view.projects.set_page(p, _comic_page)
	view.frame_page(p, _comic_page)
	_refresh_focus_bar()

## Goes to a page by number, from the page wall.
##
## The same three steps `add_page_here` takes — remember which page, frame it,
## refresh the bar — because they are what "being on a page" consists of and
## doing two of the three leaves the app half-moved.
func go_to_page(index: int) -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	_comic_page = clampi(index, 0, maxi(p.pages - 1, 0))
	p.active_page = _comic_page
	# Nothing on the old page is chosen any more. A box left round bubble
	# three would reappear round bubble three of whatever page came next.
	ComicBoard.unpick()
	view.frame_page(p, _comic_page)
	_refresh_focus_bar()

func add_page_here() -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	view.projects.add_page(p)
	_comic_page = p.pages - 1
	view.frame_page(p, _comic_page)
	_refresh_focus_bar()

## Across or down. Both read as a strip; which suits depends on the screen.
func toggle_layout() -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	view.projects.set_layout_stacked(p, not p.stacked)
	view.frame_page(p, _comic_page)
	_refresh_focus_bar()

func _format_export_time(seconds: float) -> String:
	var whole: int = maxi(int(round(seconds)), 0)
	# Divided as a float and floored on purpose. `whole / 60` on two integers
	# is an integer division, which is what was meant here and is also what
	# GDScript warns about — because nine times out of ten it is not what was
	# meant, and a warning nobody can silence honestly is a warning everybody
	# learns to scroll past.
	var minutes: int = floori(float(whole) / 60.0)
	var secs: int = whole - minutes * 60
	return "%02d:%02d" % [minutes, secs]

func _hook_audio_preview(p: ProjectManager.Project) -> void:
	AudioImport.hook_preview(self, p)

func cancel_export() -> void:
	Mp4Export.cancel()
	_flash(UiKit.label_for("Cancelling export…", "جارٍ إلغاء التصدير…"))

func set_fps(value: int) -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	p.fps = clampi(value, 1, 60)
	for page in p.sheets:
		(page as ProjectManager.Page).clip.fps = p.fps
	view.projects.mark_dirty(p)

func set_frames(value: int) -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	p.frames = clampi(value, 1, 3600)
	for page in p.sheets:
		(page as ProjectManager.Page).clip.length = p.frames
	view.projects.mark_dirty(p)

## What this project should be exported as when nobody has said.
##
## Read off what the project actually contains rather than asked for. A scene
## with more than one drawing in it is an animation and wants a moving file; a
## document with several pages is a comic and wants a comic archive; anything
## else is a picture. Getting this right is the difference between one press
## and a list every single time.
func _natural_export(p: ProjectManager.Project) -> String:
	if p == null:
		return "png"
	if p.clip != null and p.stack != null and Exporters.frame_count(p) > 1:
		return "mp4"
	if p.pages > 1:
		return "cbz"
	return "png"

## One press, straight to the device, in whatever this project was last
## exported as.
##
## The list is still there for changing your mind. What this removes is having
## to walk it again for the eleventh export of the same project in the same
## kind — which is what exporting actually is while a piece is being finished.
@warning_ignore("redundant_await")
func export_again() -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		_flash(UiKit.label_for("Nothing to export yet", "لا يوجد ما يُصدَّر بعد"))
		return
	var kind: String = p.export_kind
	if kind == "":
		kind = _natural_export(p)
	await run_export(kind)

## One MP4, from the settings the project is carrying.
##
## Its own function because the export list calls it twice — full size and
## small — and because working out the numbers is six lines that have nothing
## to do with choosing a kind of file.
@warning_ignore("redundant_await")
func _run_mp4(p: ProjectManager.Project, force_width: int) -> String:
	var began: int = Time.get_ticks_msec()
	var width: int = force_width
	if width <= 0:
		width = Mp4Export.resolution_width(p.export_resolution,
			int(p.page.x), int(p.page.y))
	var crf: int = p.export_crf
	var bitrate: int = p.export_bitrate
	var preset: String = p.export_preset
	var kbps: int = p.export_audio_kbps
	if p.export_quality != "Advanced" and p.export_bitrate <= 0:
		var quality: Dictionary = Mp4Export.quality_settings(
			p.export_quality, width, p.fps)
		crf = int(quality["crf"])
		bitrate = int(quality["bitrate"])
		preset = String(quality["preset"])
	var said: Callable = func(done: int, total: int, _frame: int,
			_rate: int) -> void:
		# Every third frame. `_flash` lays the whole interface out again, and
		# doing that sixty times a second costs more than the encoding does.
		if done % 3 != 0 and done != total:
			return
		var gone: float = float(Time.get_ticks_msec() - began) / 1000.0
		var left: float = 0.0
		if done > 0:
			left = (gone / float(done)) * float(total - done)
		_flash("%s %s%%  ·  %s / %s  ·  %s" % [
			UiKit.label_for("Encoding", "يُرمَّز"),
			Lang.number(int(round(float(done) * 100.0 / float(maxi(total, 1))))),
			Lang.number(done), Lang.number(total),
			_format_export_time(left)])
	var made: String = await Mp4Export.save(p, width, bitrate, crf,
		p.export_profile, p.export_audio, said, -1, -1, preset, kbps, p.export_format)
	if made == "":
		return made
	if Mp4Export.last_note != "":
		_flash(Mp4Export.last_note)
	elif String(Mp4Export.last_report.get("published", "")) != "":
		# Said only when it is true. A film in the gallery is findable from
		# every other app on the phone, and that is the difference between a
		# finished export and a file somewhere the person cannot reach.
		_flash(UiKit.label_for("Saved to your videos", "حُفظ في الفيديوهات"))
	return made

func run_export(kind: String) -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		_flash(UiKit.label_for("Nothing to export yet", "لا يوجد ما يُصدَّر بعد"))
		return
	# An animation of any length takes real time to render, and a screen that
	# does nothing at all for twenty seconds is a screen somebody taps again.
	var moving: bool = kind in ["mp4", "mp4_small", "sequence", "sheet",
		"gif", "gif_small", "webp_anim", "webp_anim_small"]
	if moving:
		var count: int = Exporters.frame_count(p)
		if count > 1:
			_flash(Lang.fill("Rendering {0} frames…", [count],
				"يُعالج {0} إطاراً…"))
			# Shown before the work starts rather than after it, which needs
			# the interface to be given a turn to draw.
			await get_tree().process_frame
	var out: String = ""
	if kind == "png" or kind == "jpg" or kind == "webp":
		out = Exporters.save_flat(p, kind, false)
	elif kind == "pages":
		out = Exporters.save_flat(p, "png", true)
	elif kind == "psd":
		out = Exporters.save_psd(p)
	elif kind == "cbz":
		out = Exporters.save_cbz(p)
	elif kind == "pdf":
		out = Exporters.save_pdf(p)
	elif kind == "sequence":
		out = Exporters.save_sequence(p)
	elif kind == "sheet":
		out = Exporters.save_sprite_sheet(p)
	elif kind == "mp4" or kind == "mp4_small":
		out = await _run_mp4(p, 1280 if kind == "mp4_small" else 0)
	elif kind == "gif":
		out = Exporters.save_gif(p, 0)
	elif kind == "gif_small":
		out = Exporters.save_gif(p, 800)
	elif kind == "webp_anim":
		out = Exporters.save_webp_anim(p, 0)
	elif kind == "webp_anim_small":
		out = Exporters.save_webp_anim(p, 960)
	if out == "":
		var why: String = "Nothing to export yet"
		if kind == "mp4" or kind == "mp4_small":
			why = Mp4Export.last_error
		_flash(why)
		return
	# Remembered on the project, so the next export of *this* piece needs no
	# choosing. A failed export is deliberately not remembered: a kind that
	# did not work is not the kind to repeat by default.
	p.export_kind = kind
	view.projects.mark_dirty(p)
	# A clip that had to stop short still exports, and the file is real — but
	# saying only "saved" about a scene that came out two thirds of its length
	# would be the worst kind of quiet failure: it opens, it plays, and it is
	# wrong. So the shortfall is part of the sentence.
	var short_by: int = Exporters.last_short_by
	if short_by > 0:
		_flash("%s %s  ·  %s" % [UiKit.label_for("Saved to", "حُفظ في"),
			out.get_file(),
			Lang.fill("{0} frames left out — not enough memory", [short_by],
				"حُذف {0} إطاراً — الذاكرة لا تكفي")])
	else:
		_flash("%s %s" % [UiKit.label_for("Saved to", "حُفظ في"), out.get_file()])

# ------------------------------------------------------------ placing art

@warning_ignore("unused_private_class_variable")
var _picker: FileDialog = null
@warning_ignore("unused_private_class_variable")
var _import_into: int = -1
@warning_ignore("unused_private_class_variable")
var _last_import_dir: String = ""

func _ask_for_image(layer_index: int) -> void:
	ImageImport.ask_for_image(self, layer_index)

## Which layer asked for sound. Held here rather than in `AudioImport`
## because it is a fact about this room's timeline, not about files.
var _sound_into: int = -1

## Picking and adding sounds — see `AudioImport`, which is where the picker,
## the formats and the flash messages live.
func _ask_for_audio(layer_index: int) -> void:
	_sound_into = layer_index
	AudioImport.pick(self)

func _take_audio(paths: PackedStringArray) -> void:
	AudioImport.take(self, paths, _sound_into)

func _place_image(path: String) -> void:
	ImageImport.place_image(self, path)

static func _premultiply(img: Image) -> void:
	ImageImport.premultiply(img)

func show_project_menu(p: ProjectManager.Project) -> void:
	_show_project_options(p)

## Clears the disk and the workspace together, so nothing can come back.
## Empties everything an open project is holding: the undo history of every
## page, every frame kept in memory, and the tiles the graphics card is
## sitting on. The old clear only reached the history, which is why memory
## came back a moment later.
func free_memory() -> void:
	var p: ProjectManager.Project = current_project()
	if p == null:
		return
	var freed: int = 0
	for page in p.sheets:
		var one: ProjectManager.Page = page
		one.history.clear()
		for l in one.stack.layers:
			freed += l.cels.bytes()
			l.surface.settle()
			l.surface.sleep_all()
	_flash("%s  %.1f MB" % [UiKit.label_for("Freed", "حُرِّر"),
		float(freed) / 1048576.0])

func forget_everything() -> void:
	for p in view.projects.projects.duplicate():
		view.projects.remove(p)
	Vault.forget_all()
	_close_panel()
	_flash(UiKit.label_for("Forget everything saved", "انسَ كل ما هو محفوظ"))

## Touching the strip above a project asks one question and no others: what
## colour should its frame be. A menu of everything was in the way of the
## one thing anyone reaches for there.
func _show_frame_colour(p: ProjectManager.Project) -> void:
	_options_for = p
	_close_panel()
	_mount(SettingsPanels.frame_colour_for(self, p), "settings")

func _show_project_options(p: ProjectManager.Project) -> void:
	_options_for = p
	_close_panel()
	_mount(SettingsPanels.project_options(self, p), "settings")

## Language changes reach into panels that are already on screen, so the
## simplest correct answer is to build them again.
func _rebuild_chrome() -> void:
	view.chrome.refresh(view.view_zoom)

# ------------------------------------------------------------------ export

func share_project() -> void:
	# Awaited, because exporting can now take a turn or two of the loop for
	# a scene of any length. Opening the folder before the file has landed in
	# it shows an empty folder, which reads as an export that failed.
	await run_export("png")
	var folder: String = ProjectSettings.globalize_path(Exporters.out_dir())
	DisplayServer.clipboard_set(folder)
	OS.shell_open(folder)

# --------------------------------------------------------------- shortcuts

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k: InputEventKey = event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.ctrl_pressed and k.keycode == KEY_Z:
		if k.shift_pressed:
			view.redo()
		else:
			view.undo()
		get_viewport().set_input_as_handled()
	elif k.ctrl_pressed and k.keycode == KEY_C:
		view.copy_selection()
	elif k.ctrl_pressed and k.keycode == KEY_X:
		view.cut_selection()
	elif k.ctrl_pressed and k.keycode == KEY_V:
		if k.shift_pressed:
			view.paste_as_new_layer()
		else:
			view.paste_clipboard()
	elif k.keycode == KEY_B:
		App.set_tool(App.Tool.BRUSH)
	elif k.keycode == KEY_E:
		App.set_tool(App.Tool.ERASER)
	elif k.keycode == KEY_G:
		App.set_tool(App.Tool.FILL)
	elif k.keycode == KEY_S:
		App.set_tool(App.Tool.SELECT)
	elif k.keycode == KEY_ESCAPE:
		if view.sel_active:
			view.cancel_selection()
		else:
			view.clear_marks()
	elif k.keycode == KEY_0:
		view.reset_view()
