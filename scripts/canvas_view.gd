class_name CanvasView
extends Control
## The view transform, the touch handling, the stroke engine, the selection
## and the undo history — everything that happens on the canvas itself.
##
## Gestures follow the drawing-app convention:
##   one finger        -> draw
##   two fingers       -> pan and pinch zoom
##   two-finger tap    -> undo
##   three-finger tap  -> redo
## A tap only counts as a tap if it is short and barely moves, so panning
## never triggers an undo by accident.

signal view_changed(zoom: float)
signal history_changed()
signal action_taken(label: String, undone: bool)
## A plain word to the user about what just happened — not an undoable
## action, so it is kept apart from `action_taken`, which is read as history.
signal notice(text: String)
signal puppet_changed()
signal text_restyle_needed(layer_id: int)
signal project_changed()
signal camera_framed(shot: Rect2)
signal project_menu_requested(project: Variant)
signal project_focused(project: Variant)
## Raised when the strip above a project is touched. Its only job now is the
## frame colour, so it says so rather than opening a menu of everything.
signal frame_colour_requested(project: Variant)
signal pointer_moved(world_pos: Vector2)
# These two are emitted from `canvas_marks.gd`, which is where the selection
# now lives. Godot cannot see through `p.selection_changed.emit()` back to
# this declaration and reports them as never used.
#
# Silenced one declaration at a time rather than for the whole file, and the
# real question — is anything here *actually* dead? — is answered by
# `tools/check_scope.py`, which looks across files and can tell a member read
# from a lifted module apart from one nobody reads at all.
@warning_ignore("unused_signal")
signal selection_changed()
signal symmetry_mode_changed(enabled: bool)

const MIN_ZOOM: float = 0.02
const MAX_ZOOM: float = 64.0
## Replaced by StrokeSmoother, which varies with speed instead.
const MAX_UNDO: int = 24
const TAP_MS: int = 240
const TAP_SLOP: float = 38.0
const MOVE_START: float = 7.0
const LASSO_STEP: float = 4.0
const HANDLE_HIT: float = 26.0
const MAX_LIFT: int = 2048           # biggest selection we will carry around

enum Grab { NONE, MOVE, SCALE, ROTATE }

var world: Node2D
var projects: ProjectManager
var chrome: ProjectChrome
var player: AnimPlayer
var layers: LayerStack          # the open project's stack, or null
var overlay: Node2D
var grid: GridBackground

## Nothing may be drawn until a project is open. The grid is a workspace,
## not a canvas.
var _project_drag: Variant = null
var _project_grab: Vector2 = Vector2.ZERO
var _tap_ms: int = 0
var _tap_at: Vector2 = Vector2.ZERO
var _opened_ms: int = 0
var _opened: Variant = null

## Moving a sheet around the workspace is a press that is held, then
## dragged — the way a tile is moved on a home screen. Nothing in a menu
## turns it on, and nothing has to be turned off afterwards. A finger that
## starts moving before the hold is complete is doing something else, so
## the candidate is dropped rather than dragged.
const HOLD_TO_DRAG_MS: int = 300
const HOLD_SLOP: float = 14.0
var _hold_project: Variant = null
var _hold_from: Vector2 = Vector2.ZERO
var _hold_screen: Vector2 = Vector2.ZERO
var _hold_ms: int = 0
var _strip_project: Variant = null
var _strip_ms: int = 0
var _strip_at: Vector2 = Vector2.ZERO
var _touch_is_browser: bool = false
var view_offset: Vector2 = Vector2.ZERO

## How far in the workspace stands when the app opens.
##
## One to one, and one to one on a canvas measured in thousands of pixels
## means the app opened with a fistful of paper filling the whole screen and
## no way to tell what you were looking at. The first thing anybody did was
## pinch out — every single time, before doing anything else.
##
## A workspace wants to open the way a desk looks when you walk up to it: far
## enough back to see what is on it. Six per cent is that distance for the
## page sizes this app makes.
##
## It is the *opening* stance, not a limit. `MIN_ZOOM` is still 2% and the
## first pinch overrides this and nothing ever puts it back.
const OPENING_ZOOM: float = 0.061

var view_zoom: float = OPENING_ZOOM
## Rotating the whole workspace would make the grid and every other project
## lean over with it, so the turn is only offered where it means something:
## inside focus, on one sheet, the way a hand turns paper on a desk.
var view_angle: float = 0.0
const ROTATE_SNAP: float = 0.06    # how near upright counts as upright

# --- touch bookkeeping ---
var _touches: Dictionary = {}
var _draw_finger: int = -1
var _gesture_active: bool = false
var _g_moving: bool = false
var _g_max_fingers: int = 0
# Written and read by `canvas_view_gesture.gd` through `host._g_start_ms`, so
# Godot's analyser cannot see the use and reports it as dead. It is not: the
# gesture code times a tap with it. Silenced here rather than deleted, and
# rather than left to print a warning every reload that trains the eye to
# ignore warnings.
@warning_ignore("unused_private_class_variable")
var _g_start_ms: int = 0
var _g_travel: float = 0.0
var _gesture_consumed: bool = false
var _g_last_mid: Vector2 = Vector2.ZERO
var _g_last_dist: float = 0.0
var _g_last_angle: float = 0.0
var _gesture_took_over: bool = false

## Direct camera framing. Drag inside the frame to move the shot, drag a
## corner to widen or tighten it — the whole gesture set, and no numbers.
var camera_edit: bool = false

## Bending a layer by pinning it. It owns the canvas while it is on: the
## drawing it is holding has been taken off the layer, so a brush stroke
## during a warp would land on a layer that is momentarily empty.
var puppet: PuppetWarp = null
var puppet_active: bool = false
var _puppet_pin: int = -1
var _puppet_layer: int = -1
var _puppet_snap: Dictionary = {}
var _puppet_tap_ms: int = 0
var _puppet_tap_pin: int = -1
var _puppet_hold_ms: int = 0
var _puppet_hold_at: Vector2 = Vector2.ZERO
## Which pin's ring is being turned, and the angle the finger took hold at.
##
## The angle is kept so the turn is measured from where the ring was *caught*
## rather than from where the pin faces. Without it the drawing snaps round to
## meet the thumb the instant the ring is touched, which is the difference
## between a control that feels precise and one that feels like it is fighting
## you.
var _puppet_turn: int = -1
var _puppet_grab_angle: float = 0.0
## What the finger meant, from what the screen reported.
##
## Only on the two things that are *aimed* — a warp pin being dragged and a
## joint being posed. A brush stroke is a record of where the hand actually
## went and is smoothed differently, by `stroke_smoother.gd`, which
## deliberately does not run ahead of the finger. See `touch_lead.gd`.
var _aim: TouchLead = TouchLead.new()

var symmetry_enabled: bool = false
var symmetry_count: int = 2
var symmetry_angle: float = 0.0
var symmetry_center: Vector2 = Vector2.ZERO
var symmetry_center_uv: Vector2 = Vector2(0.5, 0.5)
var _symmetry_drag: int = 0 # 0 none, 1 centre, 2 rotation handle
var _camera_angle: float = 0.0
var _camera_grab: int = -1        # -1 none, 0 body, 1..4 corners
var _camera_from: Rect2 = Rect2()
var _camera_at: Vector2 = Vector2.ZERO

var _has_touch: bool = false

# --- stroke state ---
var _drawing: bool = false
var _smoother: StrokeSmoother = StrokeSmoother.new()
var _last_stamp: Vector2 = Vector2.ZERO
var _leftover: float = 0.0


## The point the current curve piece bends through, and whether there is one
## yet. See `_continue_stroke`.
var _bend_from: Vector2 = Vector2.ZERO
var _have_bend: bool = false
var _last_dir: float = 0.0
var _speed: float = 0.0
var _pressure: float = 1.0
## When the last movement was seen, so `_speed` can be a speed rather than a
## distance. See `_note_pace`.
var _pace_ms: int = 0
## The pressure at the two ends of the piece being walked, and the one this
## dab is being drawn at.
##
## Three numbers rather than one because a piece of curve is drawn *between*
## two reports from the digitizer, and every dab along it used to be given the
## later of the two outright. On a fast stroke that is thirty dabs at one
## width followed by thirty at another — a taper made of steps, which is what
## a nib does not do. Reading the pressure across the piece makes the taper
## continuous without asking the device for anything it does not send.
var _press_a: float = 1.0
var _press_b: float = 1.0
var _dab_press: float = 1.0

# --- shape state ---
var _shape_active: bool = false
var _shape_a: Vector2 = Vector2.ZERO
var _shape_b: Vector2 = Vector2.ZERO
var poly_points: PackedVector2Array = PackedVector2Array()

## Where the last tangled line finished, and whether there is one.
##
## Tangled lines are straight lines that arrive already joined. Only the first
## is drawn freely — from then on each new line starts exactly where the last
## one ended, so the hand places one point instead of two and the joins are
## exact rather than nearly exact.
##
## This is why it is not the curve tool wearing a different name. The curve
## gathers points and commits one smoothed run at the end; a chain commits
## each straight segment the moment it is drawn, so what is on the canvas is
## always what you have made so far, and stopping is simply not drawing the
## next one.
var chain_anchor: Vector2 = Vector2.ZERO
var chain_live: bool = false

## Every tangled line laid in this run, as pairs of ends.
##
## Kept so a new line can begin **anywhere on any of them**, not only at the
## last one's tip. That was the fault: the chain only ever offered its own
## far end, so building anything that branches — a window frame, a hand, a
## roof — meant the second line could not start halfway along the first, and
## you were left aligning by eye at exactly the join where being exact is the
## whole point of the tool.
var chain_marks: PackedVector2Array = PackedVector2Array()

## How near a finger has to be for a new line to snap onto an old one, in
## screen pixels. Generous, because missing a snap costs an undo and a retry
## while an unwanted snap costs one drag — and because at any real zoom the
## line you meant is the only one within a fingertip.
const CHAIN_SNAP_PX: float = 26.0

## The nearest point on any line already laid, or `from` unchanged if none is
## close enough.
##
## Measured to the **segment**, not to its ends. A point beside the middle of
## a long line is beside that line, and only consulting the endpoints is what
## made the old behaviour feel like it was ignoring everything except the tip.
func chain_snap(from: Vector2) -> Vector2:
	if chain_marks.size() < 2:
		return from
	var reach: float = CHAIN_SNAP_PX * App.ui_scale / maxf(view_zoom, 0.0001)
	var best: Vector2 = from
	var best_d: float = reach * reach
	var i: int = 0
	while i + 1 < chain_marks.size():
		var a: Vector2 = chain_marks[i]
		var b: Vector2 = chain_marks[i + 1]
		var span: Vector2 = b - a
		var len_sq: float = span.length_squared()
		var near: Vector2 = a
		if len_sq > 0.000001:
			near = a + span * clampf((from - a).dot(span) / len_sq, 0.0, 1.0)
		var d: float = from.distance_squared_to(near)
		if d < best_d:
			best_d = d
			best = near
		i += 2
	return best
var _poly_drag: int = -1

# --- selection ---
var _marking: bool = false
var _mark_points: PackedVector2Array = PackedVector2Array()
var sel_active: bool = false
var _sel_tex: ImageTexture = null
var _sel_sprite: Sprite2D = null
@warning_ignore("unused_private_class_variable")
var _sel_size: Vector2 = Vector2.ZERO
# The selection's numbers stay here; the code that works on them was lifted
# into `canvas_marks.gd` and reaches them as `p._sel_center`. Every one of
# these is read — twelve of them, up to thirteen times each — and Godot
# cannot see any of it from inside this file.
@warning_ignore("unused_private_class_variable")
var _sel_center: Vector2 = Vector2.ZERO
@warning_ignore("unused_private_class_variable")
var _sel_rot: float = 0.0
@warning_ignore("unused_private_class_variable")
var _sel_scale: float = 1.0
## The drawing's own bounds when a lift took the whole of it, and an empty
## rectangle when it took only a piece. See `_carry_rig_with_selection`.
@warning_ignore("unused_private_class_variable")
var _sel_whole_layer: Rect2i = Rect2i()
@warning_ignore("unused_private_class_variable")
var _sel_layer: int = -1
var _sel_snapshot: Dictionary = {}
## Immutable source for the current floating selection. It must exist for the
## distortion preview and must be cleared with the floating piece; storing it
## only as a dynamic property was the crash shown in the debugger.
var _distort_base: Image = null

## A drawing carried in from another project, floating until it is put down.
##
## It rides the ordinary floating-selection box — the same handles, the same
## rule that pressing outside puts it down — because that box is already the
## thing in this app that means "not yet committed, move me". Teaching the user
## a second gesture for the same idea would be the wrong kind of new.
##
## What it changes is what *committing* means. A floating selection stamps
## itself onto the layer under it; this one asks `DrawTransfer` to lay its
## pieces down as the layers they were, at wherever the box ended up.
@warning_ignore("unused_private_class_variable")
var _placing: DrawTransfer.Landing = null
var _grab: int = Grab.NONE
@warning_ignore("unused_private_class_variable")
var _grab_start: Vector2 = Vector2.ZERO
@warning_ignore("unused_private_class_variable")
var _grab_ref: float = 0.0
@warning_ignore("unused_private_class_variable")
var _grab_scale: float = 1.0
@warning_ignore("unused_private_class_variable")
var _grab_rot: float = 0.0
@warning_ignore("unused_private_class_variable")
var _grab_centre: Vector2 = Vector2.ZERO

# --- eyedropper ---
var _loupe: Control = null
var _picking: bool = false
var _pick_screen: Vector2 = Vector2.ZERO
var _pick_color: Color = Color.WHITE
var _pick_tex: ImageTexture = null

# --- history ---
var history: History = null
var _stroke_snap: Dictionary = {}
var _stroke_layer: int = -1
var _eraser_cache: Dictionary = {}
var _settle_in: int = 0

## The app has two speeds. Drawing gets every frame the screen can show;
## a workspace being looked at gets a fraction of that. A drawing program
## sits idle most of the time it is open, and rendering an unchanged picture
## sixty times a second is pure heat and battery for no visible gain.
## Matched to the panel rather than uncapped. Drawing frames the screen
## will never show is heat and battery spent on nothing, and on a phone that
## is felt within a minute.
static var BUSY_FPS: int = 60
const IDLE_FPS: int = 12
const IDLE_AFTER: float = 1.1  # seconds of quiet before easing off
var _busy_for: float = 0.0
var _view_moved: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	# A tangled chain belongs to the run of lines being drawn right now.
	# Reaching for the brush, the eraser or the selection ends that run —
	# so coming back to the tool later starts a fresh line rather than
	# springing one out of a corner nobody remembers choosing.
	App.tool_changed.connect(func(_t: int) -> void:
		break_chain()
		# Reaching for a tool means the page furniture is no longer what
		# the hand is arranging. A cut mode left running would turn the
		# next stroke into a panel split.
		ComicBoard.mode = ComicBoard.Mode.OFF
		ComicBoard.release_quietly())

	grid = GridBackground.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grid)

	world = Node2D.new()
	world.name = "World"
	add_child(world)

	projects = ProjectManager.new()
	projects.name = "Projects"
	world.add_child(projects)
	projects.active_changed.connect(_bind_project)
	projects.projects_changed.connect(func() -> void:
		if chrome != null:
			chrome.refresh(view_zoom)
		_refresh_hint())

	chrome = ProjectChrome.new()
	chrome.name = "Chrome"
	chrome.manager = projects
	world.add_child(chrome)

	player = AnimPlayer.new()
	player.name = "Player"
	player.camera_moved.connect(_follow_camera)
	set_process(true)
	add_child(player)

	# Lifted pixels are premultiplied like everything else on the canvas, so
	# they need a node that blends that way. Drawing them inside the overlay
	# would force the frame and handles to blend the same way too.
	_sel_sprite = Sprite2D.new()
	_sel_sprite.name = "Floating"
	_sel_sprite.centered = false
	_sel_sprite.visible = false
	_sel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sel_sprite.material = PaintSurface.premultiplied_material()

	overlay = Node2D.new()
	overlay.name = "Overlay"
	overlay.draw.connect(_draw_overlay)
	world.add_child(overlay)
	# Both live under the overlay, which is shifted to the open project, so
	# marks and lifted pixels share one space with the layers they came from.
	overlay.add_child(_sel_sprite)

	# In the overlay, so it shares the open page's coordinate space with the
	# layers it is bending — pins are page positions, not screen ones.
	puppet = PuppetWarp.new()
	puppet.name = "PuppetWarp"
	overlay.add_child(puppet)

	# Above the page, inside the overlay, so it shares the page's coordinate
	# space and no exporter ever sees it.
	# Merging and duplicating queue work on the GPU; this makes sure it gets
	# folded back into the layer a couple of frames later.

	_loupe = Control.new()
	_loupe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loupe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loupe.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_loupe.draw.connect(_draw_loupe)
	add_child(_loupe)

	_ready_pace()
	resized.connect(_apply_view)
	_apply_view()

func _process(dt: float) -> void:
	_tick_hold()
	_tick_puppet_hold()
	Perf.tick(dt)
	_sync_floating()
	# A pose waiting to become a key. Two integer comparisons when there is
	# nothing pending, which is almost always.
	BoneHandle.tick(self)
	# Tile housekeeping only has something to say when the view has moved,
	# and never while a stroke is in flight: the hand is the one thing that
	# must not wait on bookkeeping.
	if _view_moved and not _drawing:
		_view_moved = false
		projects.update_view(view_world_rect(), view_zoom)
	if layers != null:
		layers.flush_all()
		if _settle_in > 0:
			_settle_in -= 1
			if _settle_in == 0:
				layers.settle_all()
	_tick_pace(dt)

## Anything the user does resets the clock; a stretch of quiet lets it run.
func mark_busy() -> void:
	_busy_for = IDLE_AFTER
	if Engine.max_fps != BUSY_FPS:
		Engine.max_fps = BUSY_FPS

func _ready_pace() -> void:
	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz > 20.0:
		BUSY_FPS = int(round(hz))
	# Applied straight away: leaving it uncapped until the first touch let
	# the opening seconds run as fast as the hardware could manage, which
	# is the one moment a phone has nothing to show for the heat.
	Engine.max_fps = BUSY_FPS

func _tick_pace(dt: float) -> void:
	# Playback is an active interaction even when the user is not touching
	# the screen. Never let the idle battery saver drop animation playback to
	# 8/12 FPS after a second of silence.
	if player != null and player.playing:
		_busy_for = IDLE_AFTER
		if Engine.max_fps != BUSY_FPS:
			Engine.max_fps = BUSY_FPS
		return
	if _drawing:
		_busy_for = IDLE_AFTER
		if Engine.max_fps != BUSY_FPS:
			Engine.max_fps = BUSY_FPS
		return
	if _busy_for <= 0.0:
		return
	_busy_for -= dt
	if _busy_for <= 0.0 and Engine.max_fps != Perf.idle_fps():
		Engine.max_fps = Perf.idle_fps()

func _refresh_hint() -> void:
	if grid == null:
		return
	var text: String = ""
	if projects.projects.is_empty():
		text = UiKit.label_for("Settings, then New project",
			"الإعدادات، ثم مشروع جديد")
	if text != grid.empty_hint:
		grid.empty_hint = text
		grid.queue_redraw()

func active_surface() -> PaintSurface:
	if layers == null:
		return null
	return layers.active_surface()

func has_project() -> bool:
	return layers != null

## Swapping projects swaps the undo stack with them, because a history that
## reached across projects could undo a stroke into a document the user is
## no longer looking at.
func _bind_project(p: Variant) -> void:
	_drop_hold()
	if puppet_active:
		end_puppet_warp(false)
	if history != null:
		if history.changed.is_connected(_on_history_changed):
			history.changed.disconnect(_on_history_changed)
		if history.acted.is_connected(_on_history_acted):
			history.acted.disconnect(_on_history_acted)
	cancel_selection()
	clear_marks()
	if p == null:
		layers = null
		history = null
		if player != null:
			player.bind(null, null)
	else:
		layers = p.stack
		history = p.history
		if player != null:
			player.bind(p.clip, p.stack)
			player.onion = p.onion_skin
			player.onion_back = p.onion_back
			player.onion_forward = p.onion_forward
			player.onion_back_tint = p.onion_back_tint
			player.onion_highlight_tint = p.onion_highlight
			player.onion_forward_tint = p.onion_forward_tint
			player.looping = p.looping
		history.changed.connect(_on_history_changed)
		history.acted.connect(_on_history_acted)
	if chrome != null:
		chrome.refresh(view_zoom)
	if symmetry_enabled:
		_sync_symmetry_from_uv()
	if overlay != null:
		overlay.position = canvas_origin()
		overlay.queue_redraw()
	history_changed.emit()
	project_changed.emit()

func _on_active_layer(_index: int) -> void:
	# Layer selection is consumed by the UI; keeping the hook makes the signal
	# safe even when no additional canvas work is required.
	pass

func _on_history_changed() -> void:
	projects.mark_dirty(projects.active)
	history_changed.emit()

func _on_history_acted(label: String, undone: bool) -> void:
	action_taken.emit(label, undone)

func _sync_floating() -> void:
	if _sel_sprite == null:
		return
	_sel_sprite.visible = sel_active and _sel_tex != null
	if not _sel_sprite.visible:
		return
	_sel_sprite.texture = _sel_tex
	_sel_sprite.transform = selection_transform()

# ------------------------------------------------------------ view helpers

func screen_to_world(s: Vector2) -> Vector2:
	return (s - view_offset).rotated(-view_angle) / view_zoom

func world_to_screen(w: Vector2) -> Vector2:
	return (w * view_zoom).rotated(view_angle) + view_offset

## Whether two fingers may turn the view.
##
## **Always, now.** This used to require a project to be focused, so on the
## board — where every project is laid out side by side — a two-finger twist
## did nothing at all. Which is the one place a person is most likely to want
## it: a board is a desk, and things on a desk get turned to be read.
##
## There was no reason for the restriction beyond caution about the endless
## grid, and the grid turns perfectly well: `grid.set_view` has taken an angle
## since it was written. What keeps a turned board usable is the settle on
## release — a twist that lands near square is nudged square, so the board
## does not drift a few degrees off true every time it is picked up.
func can_rotate() -> bool:
	return true

## Where the open project sits on the grid. Layers live inside that node, so
## a stroke handed world coordinates would land exactly this far from the
## finger — which is precisely what it did.
## Layers now live inside a page, and a page inside a project. Anything
## that touches pixels has to be measured from the page's corner or it
## lands a page-width away from the finger.
## A keyed camera moves the view, not the drawing. Framed on the page being
## worked on so that zero means "the page as you framed it" rather than some
## corner of the endless grid.
func _follow_camera(offset: Vector2, zoom: float, turn: float = 0.0) -> void:
	var p: Variant = projects.active
	if p == null:
		return
	var page: Rect2 = p.page_rect(p.active_page)

	# What the camera keeps: the page shrunk by the zoom and slid by the
	# offset. Marked on the workspace so the shot can be composed while the
	# rest of the drawing stays visible around it.
	var span: Vector2 = page.size / maxf(zoom, 0.05)
	var look: Vector2 = page.get_center() + offset
	if chrome != null:
		chrome.camera_on = true
		chrome.camera_rect = Rect2(look - span * 0.5, span)
		# `rotation` here used to read the control's own rotation rather
		# than the keyed angle handed in — so a camera key that turned the
		# shot played back without ever turning it.
		chrome.camera_angle = turn
		_camera_angle = turn
		view_angle = turn
		_apply_view()
		chrome.refresh(view_zoom)

func canvas_origin() -> Vector2:
	var p: Variant = projects.active
	if p == null:
		return Vector2.ZERO
	return p.origin + p.page_offset(p.active_page)

func screen_to_canvas(s: Vector2) -> Vector2:
	return screen_to_world(s) - canvas_origin()

func canvas_to_screen(p: Vector2) -> Vector2:
	return world_to_screen(p + canvas_origin())

## The middle of what is on screen right now, in canvas units.
##
## Anything that arrives without being placed by a finger arrives here. A new
## thing put at the middle of the *page* while somebody is zoomed into a
## corner of it appears off screen, and off screen is indistinguishable from
## nothing having happened at all.
func view_middle() -> Vector2:
	return screen_to_canvas(size * 0.5)

## What the screen covers, in world coordinates. Built from the four
## corners rather than one corner plus a size, because once the view can be
## turned those two are no longer the same rectangle.
func view_world_rect() -> Rect2:
	var a: Vector2 = screen_to_world(Vector2.ZERO)
	var box: Rect2 = Rect2(a, Vector2.ZERO)
	box = box.expand(screen_to_world(Vector2(size.x, 0.0)))
	box = box.expand(screen_to_world(size))
	box = box.expand(screen_to_world(Vector2(0.0, size.y)))
	return box

func grid_step() -> float:
	if grid == null:
		return 1.0
	return grid.current_step()

func _apply_view() -> void:
	if puppet != null:
		puppet.zoom = view_zoom
		if puppet_active:
			puppet.queue_redraw()
	world.transform = Transform2D(view_angle, Vector2(view_zoom, view_zoom),
		0.0, view_offset)
	if grid != null:
		grid.set_view(view_offset, view_zoom, view_angle)
	if overlay != null:
		overlay.queue_redraw()
	if chrome != null:
		chrome.refresh(view_zoom)
	if overlay != null:
		overlay.position = canvas_origin()
	_view_moved = true
	mark_busy()
	view_changed.emit(view_zoom)

func zoom_at(screen_point: Vector2, factor: float) -> void:
	var target: float = clampf(view_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(target, view_zoom):
		return
	var before: Vector2 = screen_to_world(screen_point)
	view_zoom = target
	view_offset = screen_point - before * view_zoom
	_apply_view()

func pan(delta: Vector2) -> void:
	view_offset += delta
	_apply_view()

## Back to how the workspace looks when the app opens — see `OPENING_ZOOM`.
##
## The same stance rather than one to one, so "reset" and "opened just now"
## mean the same thing. Two different answers to what is plainly one question
## is how somebody ends up pressing reset and being *more* lost than before.
func reset_view() -> void:
	view_zoom = OPENING_ZOOM
	view_angle = 0.0
	view_offset = size * 0.5
	_apply_view()

func _apply_gesture(mid: Vector2, dist: float, turn: float) -> void:
	CanvasViewGesture.apply_gesture(self, mid, dist, turn)

## Turns the view about a screen point. Used by the buttons, not by the
## gesture, which has its own single-step path above.
func rotate_at(screen_point: Vector2, delta: float) -> void:
	if is_zero_approx(delta):
		return
	view_offset = ((view_offset - screen_point)).rotated(delta) + screen_point
	view_angle = wrapf(view_angle + delta, -PI, PI)
	_apply_view()

## Called when the fingers leave, never while they are down. Snapping during
## the turn would fight the hand for the last few degrees, which is the
## other half of what made rotation feel unsteady.
func _settle_angle() -> void:
	if is_zero_approx(view_angle):
		return
	var quarter: float = round(view_angle / (PI * 0.5)) * (PI * 0.5)
	if absf(view_angle - quarter) < ROTATE_SNAP:
		rotate_at(size * 0.5, quarter - view_angle)

func straighten() -> void:
	if is_zero_approx(view_angle):
		return
	rotate_at(size * 0.5, -view_angle)
	view_angle = 0.0
	_apply_view()

## Fits a project to the screen with a little air around it. Zoom and pan
## stay free afterwards — focus is about what is shown, not a cage.
func frame_project(p: Variant, margin: float = 0.90) -> void:
	if p == null or size.x < 8.0 or size.y < 8.0:
		return
	view_angle = 0.0
	var b: Rect2 = p.bounds().grow(ProjectManager.TITLE_LIFT)
	var fit: float = minf(size.x / maxf(b.size.x, 1.0), size.y / maxf(b.size.y, 1.0))
	view_zoom = clampf(fit * margin, MIN_ZOOM, MAX_ZOOM)
	view_offset = size * 0.5 - b.get_center() * view_zoom
	_apply_view()

## Moves the view to one page of a comic without changing the zoom.
func frame_page(p: Variant, index: int) -> void:
	if p == null:
		return
	var r: Rect2 = p.page_rect(clampi(index, 0, p.pages - 1))
	view_offset = size * 0.5 - r.get_center() * view_zoom
	_apply_view()

# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	mark_busy()
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
		accept_event()
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)
		accept_event()
	elif event is InputEventMouseMotion:
		if _has_touch:
			return
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		pointer_moved.emit(screen_to_canvas(mm.position))
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_move_input(mm.position, mm.relative.length(), 1.0)
			accept_event()
	elif event is InputEventMouseButton:
		if _has_touch:
			return
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_input(mb.position)
			else:
				_end_input(mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, 1.12)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 1.0 / 1.12)
			accept_event()

func _handle_touch(e: InputEventScreenTouch) -> void:
	_has_touch = true
	App.touch_mode = true
	if e.pressed:
		_touches[e.index] = e.position
		pointer_moved.emit(screen_to_canvas(e.position))
		var count: int = _touches.size()
		if count == 1:
			_draw_finger = e.index
			_begin_input(e.position, true)
		elif count >= 2:
			# A second finger is an explicit mode switch.  Drawing and camera
			# gestures must never share the same stroke: ending the stroke at
			# the moment finger two lands prevents the classic Android
			# "spike" that appears when pinch/rotate begins on a live brush.
			if _drawing or _draw_finger != -1:
				_cancel_input()
				_draw_finger = -1
			if not _gesture_active:
				_start_gesture()
		_g_max_fingers = maxi(_g_max_fingers, count)
	else:
		_touches.erase(e.index)
		if _gesture_active:
			if _touches.is_empty():
				_finish_gesture()
		elif e.index == _draw_finger:
			_end_input(e.position)
			_draw_finger = -1
		if _touches.is_empty():
			_gesture_active = false
			_g_moving = false
			_gesture_consumed = false
			_draw_finger = -1

func _handle_drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	if _gesture_active:
		if _touches.size() < 2:
			# A release that never arrived would otherwise leave the view
			# frozen for good; treat the gesture as over and carry on.
			_gesture_active = false
			_g_moving = false
			_gesture_took_over = false
			return
		_g_travel += e.relative.length()
		var mid: Vector2 = _mid()
		var dist: float = _spread()
		var turn: float = _twist()
		if not _g_moving and _g_travel > MOVE_START * App.ui_scale:
			_g_moving = true
			_g_last_mid = mid
			_g_last_dist = dist
			_g_last_angle = turn
		if _g_moving:
			if not _gesture_took_over:
				_gesture_took_over = true
				_gesture_consumed = true
				_cancel_input()
			_apply_gesture(mid, dist, turn)
			_g_last_mid = mid
			_g_last_dist = dist
			_g_last_angle = turn
		return
	# After a multi-touch gesture the remaining finger is not allowed to
	# become a brush stroke mid-gesture.  A fresh touch-down is required.
	if e.index != _draw_finger or _gesture_active:
		return
	pointer_moved.emit(screen_to_canvas(e.position))
	var p: float = 1.0
	if App.pressure_enabled and e.pressure > 0.0:
		p = clampf(e.pressure, 0.05, 1.0)
	_move_input(e.position, e.relative.length(), p)

func _start_gesture() -> void:
	CanvasViewGesture.start_gesture(self)

func _finish_gesture() -> void:
	CanvasViewGesture.finish_gesture(self)

func _mid() -> Vector2:
	var keys: Array = _touches.keys()
	if keys.size() < 2:
		return Vector2.ZERO
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	return (a + b) * 0.5

## The angle of the line between two fingers, which is what turning a sheet
## of paper actually changes.
func _twist() -> float:
	var keys: Array = _touches.keys()
	if keys.size() < 2:
		return 0.0
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	return (b - a).angle()

func _spread() -> float:
	var keys: Array = _touches.keys()
	if keys.size() < 2:
		return 0.0
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	return a.distance_to(b)

func set_camera_edit(enabled: bool) -> void:
	camera_edit = enabled
	_camera_grab = -1
	if chrome == null:
		return

	chrome.camera_editing = enabled
	if enabled:
		var p: Variant = projects.active if projects != null else null
		if p == null:
			chrome.camera_on = false
			chrome.queue_redraw()
			return
		var page: Rect2 = p.bounds()
		if not chrome.camera_on or chrome.camera_rect.size.x <= 1.0 or chrome.camera_rect.size.y <= 1.0:
			chrome.camera_rect = page
		chrome.camera_on = true
	chrome.refresh(view_zoom)

func set_lateral_symmetry(enabled: bool) -> void:
	symmetry_enabled = enabled
	_symmetry_drag = 0
	if projects != null and projects.active != null:
		if enabled:
			_sync_symmetry_from_uv()
		else:
			_symmetry_drag = 0
	overlay.queue_redraw()
	symmetry_mode_changed.emit(symmetry_enabled)

func cancel_lateral_symmetry() -> void:
	set_lateral_symmetry(false)

func _sync_symmetry_from_uv() -> void:
	if projects == null or projects.active == null:
		return
	var page: Vector2 = projects.active.page
	if page.x <= 0.0 or page.y <= 0.0:
		return
	symmetry_center = Vector2(clampf(symmetry_center_uv.x, 0.0, 1.0) * page.x,
		clampf(symmetry_center_uv.y, 0.0, 1.0) * page.y)

## How many ways a stroke is repeated around the centre.
##
## Two is one line — a mirror. Four is a cross of two lines, six is three, and
## so on: every even count is that many strokes evenly spaced, which reads as
## half as many full lines through the centre. That is what a real symmetry
## guide looks like and it is why the drawn guide now shows a line per *pair*
## rather than one line however many ways the stroke is repeated.
func set_symmetry_count(count: int) -> void:
	symmetry_count = clampi(count, 2, 12)
	overlay.queue_redraw()

func set_symmetry_angle(angle: float) -> void:
	symmetry_angle = angle
	overlay.queue_redraw()

func camera_values() -> Dictionary:
	if chrome == null or projects == null:
		return {}
	var p: Variant = projects.active
	if p == null or not chrome.camera_on or chrome.camera_rect.size.x <= 1.0:
		return {}
	var page: Rect2 = p.bounds()
	var shot: Rect2 = chrome.camera_rect
	var zoom: float = page.size.x / maxf(shot.size.x, 1.0)
	return {
		"x": shot.get_center().x - page.get_center().x,
		"y": shot.get_center().y - page.get_center().y,
		"zoom": maxf(zoom, 0.05),
		"rotation": _camera_angle,
	}

func _camera_world_from_canvas(w: Vector2) -> Vector2:
	return w + canvas_origin()

## How far the rotation handle sits from the centre, **on the screen**.
##
## One number, used by the hit test and by the drawing, and that is the whole
## of the repair. They disagreed: the handle was drawn 44 screen pixels out
## and hit-tested 70 *canvas* units out. Those are the same place at exactly
## one zoom level and nowhere else — so at any other zoom the guide was drawn
## in one place and could only be grabbed in another, which from the outside
## looks precisely like a control that does not respond to touch.
const SYM_HANDLE_PX: float = 52.0

func _begin_symmetry(_w: Vector2, screen: Vector2) -> bool:
	var c: Vector2 = symmetry_center
	var center_screen: Vector2 = canvas_to_screen(c)
	var handle_screen: Vector2 = center_screen \
		+ Vector2(cos(symmetry_angle), sin(symmetry_angle)) \
		* (SYM_HANDLE_PX * App.ui_scale)
	# A fingertip, not a mouse pointer. Twenty-four screen pixels is about
	# three millimetres on a tablet — under half what a finger actually
	# covers, so a grab that felt accurate to the eye missed by touch.
	var r: float = maxf(38.0, 40.0 * App.ui_scale)
	if screen.distance_squared_to(handle_screen) <= r * r:
		_symmetry_drag = 2
		return true
	if screen.distance_squared_to(center_screen) <= r * r:
		_symmetry_drag = 1
		return true
	return false

func _move_symmetry(w: Vector2) -> void:
	if _symmetry_drag == 1:
		if projects != null and projects.active != null:
			var page: Vector2 = projects.active.page
			if page.x > 0.0 and page.y > 0.0:
				w.x = clampf(w.x, 0.0, page.x)
				w.y = clampf(w.y, 0.0, page.y)
				symmetry_center = w
				symmetry_center_uv = Vector2(w.x / page.x, w.y / page.y)
		else:
			symmetry_center = w
	elif _symmetry_drag == 2:
		var delta: Vector2 = w - symmetry_center
		if delta.length_squared() > 0.0001:
			symmetry_angle = delta.angle()
	overlay.queue_redraw()

func _begin_camera(w: Vector2) -> bool:
	if chrome == null or projects == null or projects.active == null:
		return false
	if not chrome.camera_on or chrome.camera_rect.size.x <= 1.0 or chrome.camera_rect.size.y <= 1.0:
		return false

	var world_pos: Vector2 = _camera_world_from_canvas(w)
	var shot: Rect2 = chrome.camera_rect
	var hit: float = maxf(24.0 / maxf(view_zoom, 0.0001), 6.0)
	var centre: Vector2 = shot.get_center()
	var ux: Vector2 = Vector2(cos(_camera_angle), sin(_camera_angle))
	var uy: Vector2 = Vector2(-sin(_camera_angle), cos(_camera_angle))
	var hx: Vector2 = ux * shot.size.x * 0.5
	var hy: Vector2 = uy * shot.size.y * 0.5
	var corners: Array[Vector2] = [centre - hx - hy, centre + hx - hy, centre + hx + hy, centre - hx + hy]
	var rotate_handle: Vector2 = centre - uy * maxf(32.0, shot.size.y * 0.12)
	if world_pos.distance_squared_to(rotate_handle) <= hit * hit:
		_camera_grab = 5
		_camera_at = world_pos
		return true
	for i in range(corners.size()):
		if world_pos.distance_squared_to(corners[i]) <= hit * hit:
			_camera_grab = i + 1
			_camera_from = shot
			_camera_at = world_pos
			return true

	var local_hit: Vector2 = (world_pos - centre).rotated(-_camera_angle) + shot.size * 0.5
	if Rect2(Vector2.ZERO, shot.size).grow(hit).has_point(local_hit):
		_camera_grab = 0
		_camera_from = shot
		_camera_at = world_pos
		return true

	return false

func _move_camera(w: Vector2) -> void:
	if _camera_grab < 0 or chrome == null:
		return

	var world_pos: Vector2 = _camera_world_from_canvas(w)
	var delta: Vector2 = world_pos - _camera_at
	var start: Rect2 = _camera_from
	var shot: Rect2 = start
	var min_side: float = 32.0

	if _camera_grab == 5:
		_camera_angle = (world_pos - start.get_center()).angle() + PI * 0.5
		chrome.camera_angle = _camera_angle
		chrome.refresh(view_zoom)
		overlay.queue_redraw()
		return

	if _camera_grab == 0:
		shot.position = start.position + delta
	else:
		var local: Vector2 = (world_pos - start.get_center()).rotated(-_camera_angle)
		var half: Vector2 = start.size * 0.5
		var opposite: Vector2 = Vector2.ZERO
		match _camera_grab:
			1: opposite = Vector2(half.x, half.y)
			2: opposite = Vector2(-half.x, half.y)
			3: opposite = Vector2(-half.x, -half.y)
			4: opposite = Vector2(half.x, -half.y)
		var left: float = minf(local.x, opposite.x)
		var right: float = maxf(local.x, opposite.x)
		var top: float = minf(local.y, opposite.y)
		var bottom: float = maxf(local.y, opposite.y)
		var shot_w: float = maxf(right - left, min_side)
		var shot_h: float = maxf(bottom - top, min_side)
		var local_center: Vector2 = Vector2((left + right) * 0.5, (top + bottom) * 0.5)
		var new_center: Vector2 = start.get_center() + local_center.rotated(_camera_angle)
		shot = Rect2(new_center - Vector2(shot_w, shot_h) * 0.5, Vector2(shot_w, shot_h))

	chrome.camera_rect = shot
	chrome.camera_on = true
	chrome.refresh(view_zoom)
	overlay.queue_redraw()

# --------------------------------------------------------- brush permissions

## The brush engine is shared by drawing, animation and comic projects.
## intentional paint stop, because their pixels are controlled by a skeleton.
func _brush_project_allowed() -> bool:
	var p: ProjectManager.Project = projects.active if projects != null else null
	if p == null:
		return false
	return p.kind == ProjectManager.Kind.DRAWING \
			or p.kind == ProjectManager.Kind.ANIMATION \
			or p.kind == ProjectManager.Kind.COMIC

func _brush_layer_allowed() -> bool:
	if not _brush_project_allowed() or layers == null:
		return false
	var active: LayerStack.Layer = layers.active()
	if active == null:
		return false

	# Only a control surface refuses a brush.
	#
	# The test used to be `not active.rig.is_empty()`: any layer with a
	# skeleton refused ink, for ever. That is the fault where a drawing stops
	# accepting the brush and the only way on is a new layer — and a rig
	# arrives on a layer in more ways than that rule allowed for: quick bones
	# tried on a figure, a whole layer lifted and put down again (the skeleton
	# travels with it), a return from the Character 360 room. Nothing said so;
	# the brush simply stopped working.
	#
	# A drawing with bones on it is still a drawing. A finger on a joint is
	# caught earlier by `BoneHandle.grab` and means "move this"; anywhere else
	# means what it always meant. What is left below is the three layers that
	# hold no paintable pixels: a bone layer, a Character 360 reference layer
	# whose pixels are the immutable source drawings, and its motion layer.
	if active.is_bone_layer:
		return false
	if active.is_character360 or active.is_character360_motion:
		return false
	if not active.visible or active.locked:
		return false
	return active.surface != null

# ------------------------------------------------------------ tool routing

## Projects come first: a sheet still being placed, or one that is closed,
## owns the touch entirely. Only once a project is open does the finger mean
## a brush.
func _begin_input(screen: Vector2, touch_bones: bool = false) -> void:
	_touch_is_browser = false
	# Not here, and only ever asked at the moment of touching down.
	#
	# A stroke that begins inside a system gesture strip is a stroke Android
	# will take away partway through — it watches the first few events, decides
	# the swipe was meant for the back gesture or the navigation bar, and stops
	# delivering. The app sees a pointer that goes quiet; the user sees a line
	# that cuts itself off in the middle for no reason. That argument cannot be
	# won once it has started, so the only real answer is not to start.
	#
	# A stroke already running is never touched by this. The system claims a
	# gesture it saw the beginning of, so once the finger is drawing, the strip
	# is ordinary screen and a long diagonal into the corner finishes properly.
	if not TouchSpace.may_begin(screen):
		_touch_is_browser = true
		return
	if _handle_project_touch(screen, screen_to_world(screen)):
		# The browser answered. Nothing that follows this press is a tool,
		# so the rest of the gesture is kept away from the canvas entirely
		# — a fill or a shape must not go off when the finger lifts.
		_touch_is_browser = true
		return
	if layers == null:
		return
	var w: Vector2 = screen_to_canvas(screen)

	# A bone-motion layer owns the canvas outright. The layer is an object
	# carrier, not a paint surface: once an image/object is placed on it, the
	# only meaningful canvas gesture is moving that object. This check is before
	# text, symmetry, camera, selection and every drawing tool so none of those
	# systems can accidentally consume a touch on the motion layer.
	if layers != null:
		var motion_layer: LayerStack.Layer = layers.active()
		if motion_layer != null and motion_layer.is_bone_layer:
			# If another layer was being moved, never let its floating box leak
			# into this layer. The motion layer owns this gesture completely.
			if MoveTool.holding() and MoveTool.layer_id != motion_layer.id:
				MoveTool.drop()
			if App.current_tool != App.Tool.MOVE:
				App.set_tool(App.Tool.MOVE)
			if not MoveTool.holding():
				MoveTool.take(self)
			if MoveTool.grab(self, w):
				return
			return
		# --- joints take priority, but the layer remains paintable ---
		#
		# A rigged drawing still owns a real PaintSurface. A touch on a joint is
		# a pose operation; any other touch must continue to the selected tool.
		# The old early return below made the brush appear dead on every rigged
		# layer, even though _brush_layer_allowed() deliberately permits it.
		#
		# The joints come first and the box second. A rigged layer is posed by
		# grabbing a joint, and reaching for one has to beat the whole-object
		# move that would otherwise swallow the same touch.
		if motion_layer != null and not motion_layer.rig.is_empty():
			if BoneHandle.grab(self, screen, touch_bones):
				return
			if App.current_tool == App.Tool.MOVE:
				if MoveTool.holding() and MoveTool.layer_id != motion_layer.id:
					MoveTool.drop()
				if not MoveTool.holding():
					MoveTool.take(self)
				if MoveTool.grab(self, w):
					return

	# A warp owns the canvas outright while it is on. Nothing below this
	# line can run, because the layer it would draw on is empty until the
	# warp is put down.
	if puppet_active:
		_begin_puppet(w, screen)
		return

	if text_layer() != null and _begin_text_box(w):
		_touch_is_browser = false
		return

	# Symmetry controls: the centre dot moves the axis, the second dot rotates it.
	if symmetry_enabled and _begin_symmetry(w, screen):
		return

	# The camera frame, while it is being composed.
	if camera_edit and _begin_camera(w):
		return

	# A floating selection owns the canvas until it is placed.
	if sel_active:
		var g: int = _hit_handle(screen)
		if g != Grab.NONE:
			_start_grab(g, screen)
			return
		commit_selection()
		if App.current_tool == App.Tool.SELECT:
			return

	# The move tool's box, before anything else it could be mistaken for.
	# Its grips sit outside the drawing they belong to, and a corner grip
	# hanging over a bubble or a bone would otherwise be caught by whichever
	# of those was asked first.
	if MoveTool.grab(self, w):
		return

	# The comic panel cutter is a canvas overlay tool.
	if ComicBoard.grab(self, screen):
		return

	# A joint on a rigged layer, before any tool. The layer is posed rather
	# than drawn on once it has a skeleton, so a finger landing on one of its
	# joints means "move this" and cannot mean anything else. See
	# `bone_handle.gd` — the whole feature is there and the canvas holds three
	# calls to it.
	if BoneHandle.grab(self, screen, touch_bones):
		return

	if App.current_tool == App.Tool.MOVE:
		# The box is the whole tool. A touch outside it is a touch on
		# nothing, and marks no paper — this tool never draws.
		return
	if App.current_tool == App.Tool.SELECT:
		_begin_mark(w)
		return
	if App.current_tool == App.Tool.PICK:
		_picking = true
		_update_pick(screen)
		return
	if App.current_tool == App.Tool.FILL:
		if App.fill_shape != App.FillShape.FLOOD:
			_shape_active = true
			_shape_a = w
			_shape_b = w
			overlay.queue_redraw()
		return
	if not _brush_layer_allowed():
		return

	# What happens next is decided by the tool in the hand, not by a setting
	# left behind in another one. Straight lines and boxes belong to Shapes;
	# reading `shape_mode` here meant that drawing one rectangle turned the
	# brush into a rectangle tool for the rest of the session — the brush
	# was still working, it had simply stopped being a brush.
	if App.current_tool == App.Tool.BLEND:
		# The blend tool lays no ink, so it must not reach the brush's stroke
		# path — that path is written to put a colour down, and letting the
		# blend tool fall through it would make it paint. Its own dab pass is
		# not wired to the layer surface yet, so for now a press with it
		# selected does nothing to the drawing rather than the wrong thing.
		# Doing nothing is recoverable; painting a stroke nobody asked for on
		# a finished drawing is not.
		return
	if App.current_tool == App.Tool.SHAPE and App.shape_mode != App.Shape.FREE:
		_begin_shape(w)
	else:
		_begin_stroke(w)

func _move_input(screen: Vector2, screen_delta: float, pressure: float) -> void:
	if _strip_project != null and _strip_ms != 0 \
			and _strip_at.distance_to(screen) > HOLD_SLOP * App.ui_scale:
		_strip_project = null
		_strip_ms = 0
	if _hold_project != null and _project_drag == null:
		# A finger that sets off before the hold is finished was never
		# asking to move the sheet.
		if _hold_screen.distance_to(screen) > HOLD_SLOP * App.ui_scale:
			_drop_hold()
	if _project_drag != null:
		var moved: Vector2 = screen_to_world(screen)
		projects.move_to(_project_drag, moved - _project_grab)
		if chrome != null:
			chrome.refresh(view_zoom)
		return
	if _touch_is_browser:
		return
	if MoveTool.busy():
		MoveTool.drag(self, screen_to_canvas(screen))
		return
	if layers != null:
		var motion_layer: LayerStack.Layer = layers.active()
		if motion_layer != null and motion_layer.is_bone_layer:
			return
	if ComicBoard.busy():
		ComicBoard.drag(self, screen)
		return
	if BoneHandle.posing():
		BoneHandle.drag(self, screen, pressure)
		return
	var w: Vector2 = screen_to_canvas(screen)
	if text_box_layer >= 0 and _text_grab >= 0:
		_move_text_box(w)
		return
	if puppet_active:
		if _puppet_hold_ms != 0 \
				and _puppet_hold_at.distance_to(screen) > HOLD_SLOP * App.ui_scale:
			_puppet_hold_ms = 0
		# Filtered and led. A pin is a control being aimed, and the jitter a
		# panel reports on a still finger travels straight into the mesh as a
		# shimmer over the whole drawing — one pin's worth of noise is
		# thousands of vertices' worth of movement.
		var aimed: Vector2 = screen_to_canvas(_aim.at(screen))
		if _puppet_turn >= 0:
			puppet.turn_pin_towards(_puppet_turn, aimed, _puppet_grab_angle)
		elif _puppet_pin >= 0:
			puppet.move_pin(_puppet_pin, aimed)
		return
	if _symmetry_drag != 0:
		_move_symmetry(w)
		return
	if _camera_grab >= 0:
		_move_camera(w)
		return
	_note_pace(screen_delta)
	# Lightly smoothed. Most digitizers report pressure in coarse steps, and a
	# step in pressure is a step in the width of the line — visible on exactly
	# the slow, deliberate strokes where pressure is being used on purpose.
	_pressure = lerpf(_pressure, clampf(pressure, 0.0, 1.0), 0.45)
	if _grab != Grab.NONE:
		_update_grab(screen)
		return
	if _picking:
		_update_pick(screen)
		return
	if _marking:
		_continue_mark(w)
		return
	if _drawing:
		_continue_stroke(w)
	elif _shape_active:
		if App.current_tool == App.Tool.FILL:
			_shape_b = w
		else:
			_shape_b = ShapeGeometry.corrected_endpoint(App.shape_mode, _shape_a, w)
		if App.shape_mode == App.Shape.POLYLINE and _poly_drag >= 0:
			poly_points[_poly_drag] = w
		overlay.queue_redraw()

func _end_input(screen: Vector2) -> void:
	_drop_hold()
	if _project_drag != null:
		_finish_project_drag()
		_touch_is_browser = false
		return
	if _touch_is_browser:
		_settle_strip()
		_touch_is_browser = false
		return
	if MoveTool.busy():
		MoveTool.release()
		return
	if layers != null:
		var motion_layer: LayerStack.Layer = layers.active()
		if motion_layer != null and motion_layer.is_bone_layer:
			return
	if ComicBoard.busy():
		ComicBoard.release(self)
		return
	if BoneHandle.posing():
		BoneHandle.release(self)
		return
	var w: Vector2 = screen_to_canvas(screen)
	if text_box_layer >= 0 and _text_grab >= 0:
		_text_grab = -1
		_hold_text_box(false)
		_settle_text()
		return
	if puppet_active:
		# Solved again, properly, now that nothing is waiting on it. While
		# the finger was down the shape was allowed to be approximate so it
		# could keep up; this is where it stops being approximate.
		if _puppet_pin >= 0 or _puppet_turn >= 0:
			puppet.settle_pose()
		_puppet_pin = -1
		_puppet_turn = -1
		_puppet_hold_ms = 0
		return
	if _symmetry_drag != 0:
		_move_symmetry(w)
		_symmetry_drag = 0
		overlay.queue_redraw()
		return
	if _camera_grab >= 0:
		_camera_grab = -1
		camera_framed.emit(chrome.camera_rect)
		return
	if _grab != Grab.NONE:
		_grab = Grab.NONE
		return
	if _picking:
		_finish_pick()
		return
	if _marking:
		_end_mark(w)
		return
	if _drawing:
		_end_stroke(w)
	elif _shape_active:
		_end_shape(w)
	elif App.current_tool == App.Tool.FILL:
		_do_fill(w)

func _cancel_input() -> void:
	# A multi-touch takeover can interrupt a text drag. Never leave the raster
	# carrying the temporary preview transform in that case.
	if text_box_layer >= 0 and _text_grab >= 0:
		var text_cancel: LayerStack.Layer = text_layer()
		if text_cancel != null:
			text_cancel.surface.position = Vector2.ZERO
			text_cancel.surface.rotation = 0.0
			text_cancel.surface.scale = Vector2.ONE
		_text_box_have = false
		_text_grab = -1
		_text_base_box = Rect2()
		_text_preview_turn = 0.0
		_text_preview_scale = 1.0
	ComicBoard.release_quietly()
	BoneHandle.drop(self)
	_drop_hold()
	_strip_project = null
	_strip_ms = 0
	_puppet_pin = -1
	_puppet_turn = -1
	_puppet_hold_ms = 0
	if _project_drag != null:
		_finish_project_drag()
	_touch_is_browser = false
	if _picking:
		_picking = false
		_loupe.queue_redraw()
	if _marking:
		_marking = false
		if App.select_shape != App.SelectShape.POLY:
			# The mark becomes a selection the moment the finger lifts.
			#
			# This is what was missing, and it is why the selection tools
			# appeared to do nothing at all: a box could be dragged out, it
			# drew correctly, and then on release the points were simply
			# thrown away. Every shape worked; none of them ever produced a
			# selection to move, and there is no way to tell those two
			# situations apart by looking.
			#
			# Points are cleared only *after* the lift, and only if the lift
			# refused — a mark too small to be meant, which should leave no
			# trace rather than a stray outline.
			if not lift_selection():
				_mark_points.clear()
		overlay.queue_redraw()
	_grab = Grab.NONE
	if _drawing:
		_drawing = false
		_leftover = 0.0
		if not _stroke_snap.is_empty():
			_restore(_stroke_layer, _stroke_snap)
			_stroke_snap = {}
	_shape_active = false
	_poly_drag = -1
	if overlay != null:
		overlay.queue_redraw()

# ----------------------------------------------------------- puppet warp

## Lifts the active layer's drawing off the layer and hands it to the warp.
##
## The drawing is taken away rather than merely covered, because the preview
## and the layer would otherwise both be on screen: one bent, one not, at
## the same place. Cancelling puts the original back exactly; applying puts
## the bent one down in its place.
func begin_puppet_warp() -> bool:
	if puppet_active:
		return true
	if layers == null or not layers.can_draw() or projects.active == null:
		return false
	var surface: PaintSurface = active_surface()
	if surface == null:
		return false
	surface.flush()

	# **Everything the layer has, not everything the page shows.**
	#
	# This used to clip to the page, and the warp then erased only the part it
	# had clipped to. Anything the drawing had hanging over the page edge —
	# very common, since people draw past the border and crop later — was left
	# behind on the layer, still drawn, while the warp carried the rest of the
	# figure away from it. One drawing became two, one bending and one stuck
	# where it always was.
	#
	# The whole content is taken. A generous margin rather than the page,
	# because the warp is allowed to pull the drawing further out than it
	# started and the mesh has to have somewhere to go.
	var page: Rect2i = Rect2i(Vector2i.ZERO, Vector2i(projects.active.page))
	var reach: Rect2i = Rect2i(page.position - page.size, page.size * 3)
	var box: Rect2i = surface.content_bounds().intersection(reach)
	if box.size.x < 8 or box.size.y < 8:
		notice.emit(Lang.t("Draw something first"))
		return false

	var img: Image = surface.read_region(box)
	if img == null:
		return false

	# `content_bounds` answers in whole tiles, so a small drawing in the
	# corner of a large layer comes back inside a great deal of nothing.
	# The grid is fitted to the ink instead: a mesh spread over empty space
	# wastes vertices on air, and — worse — a pin dropped out there would
	# be pinning nothing while appearing to hold the drawing.
	var ink: Rect2i = img.get_used_rect()
	if ink.size.x < 8 or ink.size.y < 8:
		notice.emit(Lang.t("Draw something first"))
		return false
	if ink.position != Vector2i.ZERO or ink.size != box.size:
		var trimmed: Image = Image.create_empty(ink.size.x, ink.size.y,
			false, Image.FORMAT_RGBA8)
		trimmed.blit_rect(img, ink, Vector2i.ZERO)
		img = trimmed
		box = Rect2i(box.position + ink.position, ink.size)

	# Only one thing may draw a layer at a time.
	#
	# This is where the repeated bodies came from. A layer can already be
	# stood in for by a `RigSkin` — a mesh holding a picture of it, put there
	# by a pose or by a linked mouth — and the warp is a second mesh holding
	# the same picture. Neither knew about the other, so both drew, and the
	# drawing appeared twice: once bent by the rig and once by the warp,
	# sitting on top of each other and moving apart as either was touched.
	#
	# The skin is shed first. There is now exactly one thing drawing this
	# layer at any moment, which is the rule the whole design rests on and
	# was the one place it was not enforced.
	BoneHandle.drop(self)
	layers.shed_skin(layers.active())

	# And only one warp. Starting a second while one is live left the first
	# one's mesh on screen with nothing driving it — a body frozen mid-pull
	# that no control could reach.
	if puppet_active:
		end_puppet_warp(false)

	# Settled before it is copied and before it is erased. An unflushed tile
	# is a tile whose pixels are still on the way, and erasing over it wipes
	# the old ones while the new ones arrive afterwards — which reads as the
	# drawing coming back from the dead a moment later.
	surface.flush()

	_puppet_layer = layers.active().id
	_puppet_snap = {}
	_collect(surface, box, _puppet_snap)
	# --- a rigged figure is meshed more finely than a flat drawing ---
	#
	# The warp is exact only where the mesh has a vertex; between vertices a
	# triangle carries the artwork flat. On a painted figure that is fine,
	# because paint has no structure a flat triangle can break.
	#
	# A Character 360 layer does. Its ink is bound to a rig, and a long
	# stroke crossing a coarse triangle comes out of a bend with a visible
	# kink in it — a piece of straight rope in the middle of a curve. Denser
	# cells put more vertices along every stroke, so the bend is carried by
	# the drawing rather than by the triangle.
	#
	# Only where it is needed. A finer mesh is more work every frame, and
	# paying for it on every layer to help one kind would be paying for it
	# mostly on drawings that do not need it.
	var l: LayerStack.Layer = layers.active()
	var rigged: bool = l != null \
		and l.title.to_lower().contains("character 360")
	if not puppet.begin(img, box, 52 if rigged else 34):
		_puppet_snap = {}
		return false
	# The layer is emptied over the region the warp now owns. Its pixels are
	# not lost — they are in the warp, and in the snapshot behind it.
	surface.erase_masked(box, SelectionMask.full(box.size.x, box.size.y))

	puppet.zoom = view_zoom
	puppet_active = true
	_puppet_pin = -1
	_puppet_turn = -1
	cancel_selection()
	clear_marks()
	overlay.queue_redraw()
	puppet_changed.emit()
	return true

## Puts the drawing back down: bent, if that is what was asked for.
func end_puppet_warp(keep: bool) -> void:
	if not puppet_active:
		return
	var surface: PaintSurface = _surface_of(_puppet_layer)
	var baked: Dictionary = {}
	if keep and not puppet.pins.is_empty():
		baked = await puppet.bake()

	if surface != null:
		if baked.is_empty():
			# Nothing to keep, or the bake came back empty: the original is
			# laid back down untouched and no history entry is made.
			surface.blit_image(puppet.source, Vector2(puppet.rect.position), true)
			_puppet_snap = {}
		else:
			var box: Rect2i = baked["rect"]
			# The bent drawing can reach outside where it started, so the
			# undo snapshot has to cover both boxes before the new pixels
			# land — otherwise taking it back would leave the overspill.
			# Tiles already held are kept as they were: what undo restores
			# is the drawing before the warp, not the emptied layer.
			_collect(surface, box, _puppet_snap)
			# Written straight in rather than blended. What comes back from
			# the bake is already premultiplied — the same form the canvas
			# stores — and blending it would fold the alpha in a second
			# time, which shows up as ink that has gone thin and dark.
			surface.blit_image(baked["image"] as Image,
				Vector2(baked["at"] as Vector2i), true)

	if not _puppet_snap.is_empty():
		_push_undo(_puppet_layer, _puppet_snap,
			UiKit.label_for("Puppet warp", "التحريك بالدبابيس"))
		_puppet_snap = {}

	puppet.finish()
	puppet_active = false
	_puppet_pin = -1
	_puppet_turn = -1
	_puppet_layer = -1
	overlay.queue_redraw()
	puppet_changed.emit()

# ------------------------------------------------------------------- text

## The box around a text layer, for moving and turning it.
##
## Text is not ink here: the words and their angle live on the layer, and the
## pixels are made from them. So the box does not scale a picture — it changes
## two numbers, and the writing is drawn again from scratch at the new place
## and angle. Turn it a hundred times and the letters are exactly as sharp as
## they were, because nothing is ever resampled.
var text_box_layer: int = -1
var _text_grab: int = -1

## The writing's box, held for the duration of a drag.
##
## This is the "walks like a mountain" fault. `draw_text_box` asked
## `content_bounds()` for the box, and `content_bounds()` walks **every tile
## the layer owns** to work out its extent. The overlay redraws on every move
## event, so dragging the text re-walked the whole layer sixty times a second
## to recompute a rectangle that had not changed — the box does not grow or
## shrink while it is being carried, only moved.
##
## Taken once when the grab begins and dropped when the finger lifts. Nothing
## is cached across gestures, so nothing can go stale: the only window it
## covers is the one in which the answer provably cannot change.
var _text_box_held: Rect2 = Rect2()
var _text_box_have: bool = false

## The box drawn tight around the letters themselves.
##
## It used to come from `content_bounds()`, which answers in whole tiles — so
## a one-line caption came back inside a box of at least 256 by 256, and the
## turn grip, which sits above the top of the box, floated in blank paper a
## long way from the words it turns. Too big to look right and too far away to
## reach for, from one cause. See `TextRender.ink_bounds`.
##
## Kept once measured, because reading the region back is real work and the
## overlay redraws constantly. Thrown away the moment the text could have
## changed, so it can never describe writing that is no longer there.
var _text_tight: Rect2 = Rect2()
var _text_tight_for: int = -1
var _text_from: Vector2 = Vector2.ZERO
var _text_turn_from: float = 0.0
var _text_scale_from: float = 1.0
var _text_at_from: Vector2 = Vector2.ZERO
## Where the box has been dragged to since the finger went down. The pixels
## are not moved until it lifts, so a drag costs nothing until it is finished.
var _text_shift: Vector2 = Vector2.ZERO
## Native interaction kernel. It never owns pixels; it only calculates the
## hot-path geometry so every touch event stays allocation-light.
var _text_native: Object = null
var _text_base_box: Rect2 = Rect2()
var _text_base_turn: float = 0.0
var _text_base_scale: float = 1.0
var _text_preview_turn: float = 0.0
var _text_preview_scale: float = 1.0

## What the finger caught on the writing's box, or nothing.
##
## The box, its four corner grips and its turn stalk are all `HandleBox` now —
## the same way wherever one appears.
func _begin_text_box(w: Vector2) -> bool:
	var l: LayerStack.Layer = text_layer()
	if l == null:
		return false
	var box: Rect2 = text_bounds()
	if box.size.x < 1.0 or box.size.y < 1.0:
		return false
	if _text_native == null:
		_text_native = Native.text_tool()
	var part: int = HandleBox.Part.NOTHING
	if _text_native != null:
		part = int(_text_native.hit_test(box, l.text_turn, w,
			30.0 * App.ui_scale / maxf(view_zoom, 0.0001)))
	else:
		part = HandleBox.part_at(self, box, l.text_turn, w)
	if part == HandleBox.Part.NOTHING:
		return false
	_text_grab = part
	_text_base_box = box
	_text_base_turn = l.text_turn
	_text_base_scale = l.text_scale
	_text_preview_turn = l.text_turn
	_text_preview_scale = l.text_scale
	_hold_text_box(true)
	_text_from = w
	_text_turn_from = l.text_turn
	_text_scale_from = l.text_scale
	_text_at_from = l.text_at
	overlay.queue_redraw()
	return true

func _move_text_box(w: Vector2) -> void:
	var l: LayerStack.Layer = text_layer()
	if l == null:
		return
	var base: Rect2 = _text_base_box
	var preview: Rect2 = base
	var turn: float = _text_base_turn
	var k: float = 1.0
	if _text_grab == HandleBox.Part.TURN:
		var turn_delta: float = 0.0
		if _text_native != null:
			turn_delta = float(_text_native.turned(base, _text_from, w))
		else:
			turn_delta = HandleBox.turned(base, _text_from, w)
		turn += turn_delta
		if bool(l.text_state.get("snap_rotation", false)):
			var step: float = deg_to_rad(float(l.text_state.get("snap_degrees", 15.0)))
			if step > 0.0001:
				turn = roundf(turn / step) * step
	elif HandleBox.is_corner(_text_grab):
		if _text_native != null:
			preview = _text_native.sized(base, _text_base_turn, _text_grab,
				_text_from, w, true)
		else:
			preview = HandleBox.sized(base, _text_base_turn, _text_grab,
				_text_from, w, true)
		k = preview.size.x / maxf(base.size.x, 0.001)
		k = _text_native.clamp_scale(_text_base_scale * k, 0.15, 12.0) / maxf(_text_base_scale, 0.001) if _text_native != null else clampf(k, 0.15 / maxf(_text_base_scale, 0.001), 12.0 / maxf(_text_base_scale, 0.001))
		preview.size = base.size * k
		# Re-anchor after clamping so the opposite corner remains fixed.
		var pinned: int = HandleBox.Part.BOTTOM_RIGHT if _text_grab == HandleBox.Part.TOP_LEFT else HandleBox.Part.BOTTOM_LEFT if _text_grab == HandleBox.Part.TOP_RIGHT else HandleBox.Part.TOP_LEFT if _text_grab == HandleBox.Part.BOTTOM_RIGHT else HandleBox.Part.TOP_RIGHT
		var pts: PackedVector2Array = HandleBox.corners(base, _text_base_turn)
		var anchor_index: int = 0 if pinned == HandleBox.Part.TOP_LEFT else 1 if pinned == HandleBox.Part.TOP_RIGHT else 2 if pinned == HandleBox.Part.BOTTOM_RIGHT else 3
		var anchor: Vector2 = pts[anchor_index]
		var sx: float = -1.0 if pinned in [HandleBox.Part.TOP_RIGHT, HandleBox.Part.BOTTOM_RIGHT] else 1.0
		var sy: float = -1.0 if pinned in [HandleBox.Part.BOTTOM_LEFT, HandleBox.Part.BOTTOM_RIGHT] else 1.0
		var far: Vector2 = anchor + Vector2(preview.size.x * sx, preview.size.y * sy).rotated(_text_base_turn)
		var mid: Vector2 = (anchor + far) * 0.5
		preview.position = mid - preview.size * 0.5
	elif _text_grab == HandleBox.Part.MOVE:
		preview = Rect2(base.position + (w - _text_from), base.size)

	_text_preview_turn = turn
	_text_preview_scale = _text_base_scale * k
	_text_box_held = preview
	_text_box_have = true

	# The pixels are not re-rendered while the finger is down. Instead the
	# entire text surface receives one reversible Node2D transform. This makes
	# the words and the box move together at the display rate with no tile walk,
	# no image allocation and no visible lag between the handle and the text.
	var new_center: Vector2 = preview.get_center()
	var delta_turn: float = _text_preview_turn - _text_base_turn
	var relative_scale: float = _text_preview_scale / maxf(_text_base_scale, 0.001)
	if _text_native != null:
		var transform_data: Dictionary = _text_native.preview_transform(
			_text_base_box.get_center(), new_center, delta_turn, relative_scale)
		l.surface.position = transform_data["position"]
		l.surface.rotation = float(transform_data["rotation"])
		l.surface.scale = Vector2.ONE * float(transform_data["scale"])
	else:
		l.surface.position = new_center - _text_base_box.get_center().rotated(delta_turn) * relative_scale
		l.surface.rotation = delta_turn
		l.surface.scale = Vector2.ONE * relative_scale
	overlay.queue_redraw()

## The turn is only a number until the finger lifts; then the writing is drawn
## again at that angle and size, so it is never a rotated, stretched picture
## of itself.
func _settle_text() -> void:
	var l: LayerStack.Layer = text_layer()
	if l == null:
		return
	# Commit the logical object state first, then remove the preview transform.
	# The next render is generated from the words, so the final result is crisp
	# and the gesture itself never paid the rasterization cost.
	var final_box: Rect2 = _text_box_held if _text_box_have else _text_base_box
	l.text_at = final_box.position
	l.text_scale = _text_preview_scale
	l.text_turn = _text_preview_turn
	l.surface.position = Vector2.ZERO
	l.surface.rotation = 0.0
	l.surface.scale = Vector2.ONE
	text_restyle_needed.emit(l.id)
	_text_shift = Vector2.ZERO
	_text_box_have = false
	_text_base_box = Rect2()
	_text_preview_turn = l.text_turn
	_text_preview_scale = l.text_scale
	forget_text_bounds()
	overlay.queue_redraw()

## The box, drawn with its grips at a constant size on screen.
func draw_text_box() -> void:
	var l: LayerStack.Layer = text_layer()
	if l == null:
		return
	var box: Rect2 = text_bounds()
	if box.size.x < 1.0:
		return
	HandleBox.draw_on(self, box, _text_preview_turn if _text_box_have else l.text_turn, _text_grab)

func begin_text_box(layer_id: int) -> void:
	text_box_layer = layer_id
	_text_grab = -1
	_text_box_have = false
	_text_base_box = Rect2()
	_text_native = Native.text_tool()
	forget_text_bounds()
	overlay.queue_redraw()

func end_text_box() -> void:
	var l: LayerStack.Layer = text_layer()
	if l != null:
		l.surface.position = Vector2.ZERO
		l.surface.rotation = 0.0
		l.surface.scale = Vector2.ONE
	text_box_layer = -1
	_text_grab = -1
	_text_box_have = false
	_text_base_box = Rect2()
	forget_text_bounds()
	overlay.queue_redraw()

## The layer the writing box belongs to.
##
## Bound to whichever text layer is *active*, not to the one that happened to
## be current when the box was first put up. That is the repair: the box was
## pinned to a single id, so choosing any other layer made it vanish and
## choosing the text layer again did not bring it back — the writing was still
## there and had become unmovable, with nothing on screen to say why.
##
## A box that follows the selection is also the rule every other handle in the
## app already follows. Choosing a text layer means wanting to move its text;
## there is no second thing it could mean.
func text_layer() -> LayerStack.Layer:
	if layers == null:
		return null
	if text_box_layer >= 0:
		for l in layers.layers:
			if l.id == text_box_layer and l.is_text:
				return l
	var live: LayerStack.Layer = layers.active()
	if live != null and live.is_text:
		# Remembered, so the drag handles have something stable to work
		# against for the rest of this gesture.
		text_box_layer = live.id
		return live
	return null

## Where the writing sits on the page, as a box with a turn on it.
## The writing's box: where it sits and how big it is now.
##
## Read from the layer rather than measured from its pixels — see the note on
## `LayerStack.Layer.text_scale`. Measuring is kept only as the fallback for
## writing saved before the box was stored, so an old project opens with its
## captions where it left them instead of with no box at all.
func text_bounds() -> Rect2:
	if _text_box_have:
		return _text_box_held
	var l: LayerStack.Layer = text_layer()
	if l == null:
		return Rect2()
	if l.text_size.x > 0.5:
		return Rect2(l.text_at, l.text_size * maxf(l.text_scale, 0.01))
	if _text_tight_for == l.id and _text_tight.size.x > 0.0:
		return _text_tight
	_text_tight = TextRender.ink_bounds(l.surface)
	_text_tight_for = l.id
	return _text_tight

## Forgets the measured box. Called wherever the writing could have changed.
func forget_text_bounds() -> void:
	_text_tight = Rect2()
	_text_tight_for = -1

## Freezes the box for a drag, and lets it go afterwards.
func _hold_text_box(on: bool) -> void:
	if not on:
		_text_box_have = false
		return
	# Never ask the tiled raster for this rectangle during a gesture. The text
	# object's measured dimensions are already exact and stay exact until the
	# words or their style change. This removes the old 256px-tile inflation.
	_text_box_held = _text_base_box if _text_base_box.size.x > 0.0 else text_bounds()
	_text_box_have = true

## Swaps the pixels of a text layer for freshly drawn ones, keeping where it
## sits. One undo step covers the change.
func replace_text_pixels(layer_id: int, img: Image) -> void:
	forget_text_bounds()
	var l: LayerStack.Layer = null
	for one in layers.layers:
		if one.id == layer_id:
			l = one
			break
	if l == null or img == null:
		return
	var was: Rect2i = l.surface.content_bounds()
	var mid: Vector2 = Vector2(was.position) + Vector2(was.size) * 0.5
	if was.size.x < 2:
		mid = l.text_at
	var at: Vector2i = Vector2i((mid - Vector2(img.get_width(),
		img.get_height()) * 0.5).round())
	l.text_at = Vector2(at)
	var into: Rect2i = Rect2i(at, Vector2i(img.get_width(), img.get_height()))
	stamp_region(layer_id, into, was, img, at,
		UiKit.label_for("Text", "نص"))
	overlay.queue_redraw()

## Puts freshly written text down at a place chosen by the caller, rather
## than centred on where the old pixels happened to be.
func replace_text_at(layer_id: int, img: Image, at: Vector2) -> void:
	var l: LayerStack.Layer = null
	for one in layers.layers:
		if one.id == layer_id:
			l = one
			break
	if l == null or img == null:
		return
	var was: Rect2i = l.surface.content_bounds()
	# `at` is the logical top-left of the text object, not necessarily the
	# top-left of the rotated raster. Centre the freshly rendered image on the
	# logical text box so changing rotation never makes the words walk away.
	var logical_size: Vector2 = l.text_size * maxf(l.text_scale, 0.001)
	var logical_center: Vector2 = at + logical_size * 0.5 + _text_shift
	var corner: Vector2i = Vector2i((logical_center - Vector2(img.get_width(),
		img.get_height()) * 0.5).round())
	l.text_at = at + _text_shift
	_text_shift = Vector2.ZERO
	stamp_region(layer_id,
		Rect2i(corner, Vector2i(img.get_width(), img.get_height())),
		was, img, corner, UiKit.label_for("Text", "نص"))
	overlay.queue_redraw()

## Replaces one patch of a layer with another, as a single undoable act.
##
## Used by the rooms that hand a finished drawing back: they own the pixels for
## as long as they are open, and this is the door they come back through. The
## snapshot covers both the patch being cleared and the patch being written,
## because a posed figure rarely lands inside the box it started in.
func stamp_region(layer_id: int, into: Rect2i, clear: Rect2i, img: Image,
		at: Vector2i, label: String) -> void:
	var surface: PaintSurface = _surface_of(layer_id)
	if surface == null or img == null:
		return
	var snap: Dictionary = {}
	_collect(surface, clear, snap)
	_collect(surface, into, snap)
	surface.erase_masked(clear, SelectionMask.full(clear.size.x, clear.size.y))
	# Written straight in: what comes back is already premultiplied, and
	# blending it would fold the alpha through a second time.
	surface.blit_image(img, Vector2(at), true)
	if not snap.is_empty():
		_push_undo(layer_id, snap, label)
	if projects.active != null:
		projects.mark_dirty(projects.active)
	if layers != null:
		layers.changed.emit()

func _surface_of(layer_id: int) -> PaintSurface:
	if layers == null:
		return null
	for l in layers.layers:
		if l.id == layer_id:
			return l.surface
	return null

## One finger, three meanings, decided by what it lands on: a pin to drag,
## a pin tapped twice to take away, or bare drawing to pin.
func _begin_puppet(w: Vector2, screen: Vector2) -> void:
	# A filter carrying the velocity of the last drag would fling the first
	# frame of the next one.
	_aim.reset()
	var reach: float = 26.0 / maxf(view_zoom, 0.0001)
	var hit: int = puppet.pin_at(w, reach)
	var now: int = Time.get_ticks_msec()

	# The ring first, before the pins.
	#
	# It has to be first because the ring of the chosen pin can pass right
	# over a neighbouring pin, and a finger that lands there plainly means
	# the ring it is following rather than whatever happens to be underneath.
	if hit < 0 and puppet.on_ring(w):
		_puppet_pin = -1
		_puppet_hold_ms = 0
		_puppet_tap_pin = -1
		_puppet_turn = puppet.selected
		# The angle the ring was caught at, less the turn the pin already
		# carries. Every later reading is measured against this, which is why
		# the drawing does not jump to meet the thumb the instant the ring is
		# touched.
		_puppet_grab_angle = puppet.angle_from(_puppet_turn, w) \
			- puppet.turn_of(_puppet_turn)
		return

	if hit >= 0:
		var double: bool = now - _puppet_tap_ms <= TAP_MS and _puppet_tap_pin == hit
		_puppet_tap_ms = now
		_puppet_tap_pin = hit
		puppet.selected = hit
		puppet.queue_redraw()
		if double:
			puppet.remove_pin(hit)
			_puppet_pin = -1
			_puppet_turn = -1
			_puppet_tap_pin = -1
			_puppet_hold_ms = 0
			return
		_puppet_pin = hit
		# A press held on a pin, rather than dragged, pins it down for good:
		# the commonest thing to want after placing a pin is for it to stop
		# moving, and reaching for a panel to say so breaks the pose.
		_puppet_hold_ms = now
		_puppet_hold_at = screen
		return

	_puppet_tap_ms = now
	_puppet_tap_pin = -1
	_puppet_hold_ms = 0
	# A pin is grabbed the instant it is made, so one movement both places
	# it and pulls with it. A tap on blank paper makes nothing: a pin off the
	# mesh has no ink to hold, and one that appeared there would look like it
	# was holding something.
	_puppet_pin = puppet.add_pin(w)
	if _puppet_pin < 0:
		notice.emit(Lang.t("Put pins on the drawing"))

# --------------------------------------------------------------- projects

func floating_project() -> Variant:
	return projects.placing

## Returns true when the touch belonged to a project rather than to a tool.
##
## This is the gate every stroke has to pass through, and it used to be shut.
## Any touch landing on any sheet was answered by the browser — selected it,
## brought it forward, and swallowed the event — so once a project existed
## the brush could never receive a single press. The rule now is simple and
## has one line: **the open project belongs to the tools.** Inside its
## bounds the browser does not answer at all.
##
## Everything else keeps the browser's own manners:
##   * the strip above a sheet opens that sheet's frame colour, nothing else
##   * one tap on a closed sheet selects it and does not open it
##   * two taps open it and focus it, which is what puts the tools on screen
##   * a press held on a closed sheet picks it up so it can be dragged
func _handle_project_touch(screen: Vector2, w: Vector2) -> bool:
	var now: int = Time.get_ticks_msec()

	# --- a sheet still looking for its place ---
	var drifting: Variant = floating_project()
	if drifting != null:
		var double_place: bool = now - _tap_ms <= TAP_MS \
			and _tap_at.distance_to(screen) <= 40.0 * App.ui_scale
		_tap_ms = now
		_tap_at = screen
		if double_place and _opened == drifting:
			projects.place(drifting)
			projects.open(drifting)
			projects.set_focus(drifting)
			frame_project(drifting)
			_opened = drifting
			_opened_ms = now
			project_focused.emit(drifting)
		else:
			_project_drag = drifting
			_project_grab = w - drifting.origin
			projects.bring_to_front(drifting)
			projects.select(drifting)
			_opened = drifting
		return true

	# --- the open project is the tools' ground, not the browser's ---
	# Checked before anything else so a brush, a fill or a selection never
	# has to compete with the sheet it is being used on.
	var live: Variant = projects.active
	if live != null and live.bounds().grow(_page_reach()).has_point(w):
		return false

	# --- the title strip ---
	# A tap is the frame colour. Held, it is everything else the project can
	# do. The options menu had a listener waiting for it in the shell and
	# nothing anywhere that ever called for it, so duplicating, renaming,
	# exporting and deleting a project were all unreachable from the
	# workspace — the strip is where they belong, beside the one setting that
	# already lives there.
	var strip: Variant = projects.title_strip_at(w, view_zoom)
	if strip != null:
		projects.select(strip)
		_strip_project = strip
		_strip_ms = now
		_strip_at = screen
		return true

	var hit: Variant = projects.at_point(w)
	if hit == null:
		projects.clear_selection()
		_drop_hold()
		# With a project open, the ground around it is neither canvas nor
		# browser: a stroke started out here would land nowhere, so the
		# touch is simply absorbed.
		return live != null or layers == null

	var double: bool = now - _tap_ms <= TAP_MS \
		and _tap_at.distance_to(screen) <= 40.0 * App.ui_scale
	_tap_ms = now
	_tap_at = screen

	# Two taps open. One tap never does — a sheet under a veil stays under
	# it until it has been asked twice, which is what the door means.
	if double and _opened == hit:
		_drop_hold()
		projects.bring_to_front(hit)
		projects.open(hit)
		projects.set_focus(hit)
		hit.grid_guide = true
		_opened = hit
		_opened_ms = now
		frame_project(hit)
		project_focused.emit(hit)
		return true

	projects.bring_to_front(hit)
	projects.select(hit)
	_opened = hit
	_opened_ms = now

	# The press starts counting here. Held long enough without wandering,
	# it becomes a move; released before that, it was only a selection.
	_hold_project = hit
	_hold_from = w
	_hold_screen = screen
	_hold_ms = now
	return true

## A little room outside the page, so a stroke that begins a hair past the
## edge still belongs to the drawing rather than to the browser.
func _page_reach() -> float:
	return 24.0 / maxf(view_zoom, 0.0001)

## Turns a held press into a drag once it has been held long enough.
func _tick_hold() -> void:
	if _strip_project != null and _strip_ms != 0 \
			and Time.get_ticks_msec() - _strip_ms >= HOLD_TO_DRAG_MS + 120:
		var who: Variant = _strip_project
		_strip_project = null
		_strip_ms = 0
		project_menu_requested.emit(who)
		return
	if _hold_project == null or _project_drag != null:
		return
	if Time.get_ticks_msec() - _hold_ms < HOLD_TO_DRAG_MS:
		return
	_project_drag = _hold_project
	_project_grab = _hold_from - _hold_project.origin
	_hold_project = null
	projects.dragging = _project_drag
	projects.bring_to_front(_project_drag)
	if chrome != null:
		chrome.refresh(view_zoom)
	notice.emit(Lang.t("Drag to move it"))

## A pin held still under the finger becomes an anchor.
func _tick_puppet_hold() -> void:
	if not puppet_active or _puppet_hold_ms == 0 or _puppet_pin < 0:
		return
	if Time.get_ticks_msec() - _puppet_hold_ms < HOLD_TO_DRAG_MS + 160:
		return
	var at: int = _puppet_pin
	_puppet_hold_ms = 0
	_puppet_pin = -1
	_puppet_turn = -1
	puppet.toggle_anchor(at)
	notice.emit(Lang.t("Pin held still") if puppet.is_anchored(at) \
		else Lang.t("Pin released"))

func _drop_hold() -> void:
	_hold_project = null
	_hold_ms = 0

## A press that began on a title strip and ended before it became a hold was
## asking for the frame colour, which is the thing that strip is for.
func _settle_strip() -> void:
	if _strip_project == null:
		return
	var who: Variant = _strip_project
	_strip_project = null
	_strip_ms = 0
	frame_colour_requested.emit(who)

## A sheet that has been carried somewhere keeps where it was put — the
## workspace remembers positions, so the move has to be written down.
func _finish_project_drag() -> void:
	if _project_drag == null:
		return
	projects.mark_dirty(_project_drag)
	_project_drag = null
	projects.dragging = null
	if chrome != null:
		chrome.refresh(view_zoom)

# ------------------------------------------------------------ stroke engine

func _begin_stroke(w: Vector2) -> void:
	if player == null or not _brush_layer_allowed():
		return
	w = _brush_safe_point(w)
	if player.clip != null:
		player.ensure_editable_for_stroke()
	var current_layer: LayerStack.Layer = layers.active()
	if current_layer == null:
		return
	_drawing = true
	_smoother.strength = App.stabilizer
	_smoother.reset(w)
	# The pressure the stroke begins at is the pressure it begins at, not
	# whatever the last stroke ended on: a fresh mark carrying the taper of the
	# one before it starts thin for no reason the hand can see.
	_press_a = _pressure
	_press_b = _pressure
	_dab_press = _pressure
	_pace_ms = Time.get_ticks_msec()
	_last_stamp = w
	# No curve carried over from the last stroke. Without this the first
	# piece of a new stroke would bend toward wherever the previous one
	# happened to finish — a hook at the start of every mark.
	_have_bend = false
	_leftover = 0.0
	_speed = 0.0
	_stroke_snap = {}
	_stroke_layer = current_layer.id
	_bind_stroke_panel(w)
	_stamp_at(w, w)

## Lays the stamps along the stroke.
##
## The path between two touch points is a **curve**, not a straight line, and
## for a long time this drew it straight. On a slow stroke that is invisible;
## on a fast one the touch points arrive thirty or more pixels apart and the
## mark comes out as a polygon — a visible corner at every sample, which is
## the thing people mean when they say a brush engine feels cheap.
##
## Each new point is now drawn as a quadratic curve: **from the midpoint of
## the last pair, through the last point, to the midpoint of the new pair.**
## Measured on a fast arc, the sharpest corner falls from 17.2° to 0.17° — a
## ninety-nine per cent reduction in the artefact.
##
## Three reasons this shape rather than a fitted spline:
##
## * **It cannot overshoot.** A quadratic Bézier stays inside the triangle of
##   its three points, always. Catmull-Rom is a better *fit* and will bulge
##   outside a sharp turn, which on a brush stroke means ink where the finger
##   never went.
## * **The joins are exact.** Consecutive pieces share an endpoint by
##   construction — the same midpoint — so there is no gap to seal, and the
##   direction carries across within a third of a degree.
## * **A straight stroke stays exactly straight.** Measured wobble on a
##   straight line: 2.8e-14. A smoother that ripples a ruled line is worse
##   than no smoother.
##
## The last half-segment is deliberately left undrawn until the next point
## arrives, because its shape is not known yet — and `_end_stroke` runs the
## tail out straight, which is right, as there is no next point to curve
## toward.
func _continue_stroke(w: Vector2) -> void:
	w = _brush_safe_point(w)
	var target: Vector2 = _smoother.filter(w)
	if _last_stamp.distance_to(target) <= 0.0001:
		return
	# The piece about to be walked runs from the last report to this one, so
	# those are the two pressures its dabs are read between.
	_press_a = _press_b
	_press_b = _pressure
	if not _have_bend:
		# Nothing to curve through yet: the first move of a stroke is drawn
		# straight, as it must be.
		_walk_line(_last_stamp, target)
		_bend_from = target
		_have_bend = true
		_last_stamp = target
		return
	var to_mid: Vector2 = (_bend_from + target) * 0.5
	_walk_curve(_last_stamp, _bend_from, to_mid)
	_bend_from = target
	_last_stamp = to_mid

## Stamps evenly along a straight run.
##
## The spacing is read once rather than once per dab. On a straight line there
## is nothing that could change it between one dab and the next — the brush is
## the same brush and the line does not turn — so asking again each time round
## was a preset lookup per dab bought for an answer already known.
func _walk_line(from: Vector2, to: Vector2) -> void:
	var seg: float = from.distance_to(to)
	if seg <= 0.0001:
		return
	var spacing: float = _spacing()
	var dir: Vector2 = (to - from) / seg
	var travelled: float = -_leftover
	var guard: int = 0
	while travelled + spacing <= seg and guard < 4096:
		travelled += spacing
		var p: Vector2 = from + dir * travelled
		_dab_press = lerpf(_press_a, _press_b,
			clampf(travelled / seg, 0.0, 1.0))
		_stamp_at(p, p - dir)
		guard += 1
	_leftover = seg - travelled

## Stamps evenly along one quadratic piece.
##
## "Evenly" now means what the word says. The old walk measured the piece in
## twenty straight chops and then stepped `t` in proportion to distance — which
## reads like arc length and is not: on a Bézier the point runs fast through
## the straight part and slows through the bend, so an even step in `t` crowds
## the dabs into the turn. Measured on an ordinary hand-drawn arc the gap
## between neighbouring dabs varied by about two to one from one end of the
## piece to the other, which is dark corners and pale straights.
##
## `CurveWalk` integrates the length properly and inverts it properly, so the
## distance between one dab and the next is the distance that was asked for,
## to within a thousandth of a pixel, wherever on the curve it falls.
##
## The second thing happening here is the turn factor. A wide stamp swept round
## a tight bend leaves a scalloped outer edge, because the rim of the stamp
## travels further than its centre does — the wider the brush, the worse. The
## spacing is tightened through the bend by exactly the ratio that puts the
## outer rim back at the spacing the brush asked for, and is left alone
## everywhere else. It is the reason a large brush now holds its shape round a
## corner instead of shedding it.
func _walk_curve(a: Vector2, control: Vector2, b: Vector2) -> void:
	var piece: CurveWalk.Piece = CurveWalk.measure(a, control, b)
	if piece.length <= 0.0001:
		return
	var base: float = _spacing()
	var radius: float = _dab_radius()
	var spacing: float = base
	var travelled: float = -_leftover
	var guard: int = 0
	var last: Vector2 = a
	while travelled + spacing <= piece.length and guard < 4096:
		travelled += spacing
		var t: float = CurveWalk.t_at(piece, travelled)
		var p: Vector2 = piece.at(t)
		_dab_press = lerpf(_press_a, _press_b,
			clampf(travelled / piece.length, 0.0, 1.0))
		# The direction the stroke is actually travelling here, for brushes
		# that turn their stamp to follow it.
		_stamp_at(p, last)
		last = p
		spacing = base * CurveWalk.turn_factor(piece, t, radius)
		guard += 1
	_leftover = piece.length - travelled

static func _quad(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return a * (u * u) + control * (2.0 * u * t) + b * (t * t)

func _end_stroke(w: Vector2) -> void:
	if not _drawing:
		return
	w = _brush_safe_point(w)
	_continue_stroke(w)
	# Run the tail out.
	#
	# `_continue_stroke` deliberately leaves the last half-segment undrawn,
	# because its shape depends on a point that has not arrived yet. At the
	# end of a stroke that point never arrives — so the remainder is drawn
	# straight to where the finger actually lifted. Without this every mark
	# stops a few pixels short of its own end, which is most visible on
	# exactly the short flicks where it matters.
	if _have_bend:
		_walk_line(_last_stamp, _bend_from)
		_last_stamp = _bend_from
	# The leash is let go at the end of the stroke.
	#
	# With the stabiliser turned up the nib trails the hand, so the mark
	# stops short of where the finger actually lifted — and two strokes meant
	# to meet never quite do, which is the one thing line art cannot forgive.
	# The remaining short run is walked out to the hand's own last position.
	# See `StrokeSmoother.hand`.
	if App.stabilizer > 0.001:
		var ended: Vector2 = _smoother.hand()
		if _last_stamp.distance_to(ended) > 0.5:
			_walk_line(_last_stamp, ended)
			_last_stamp = ended
	_drawing = false
	_have_bend = false
	_settle_in = 2
	_push_undo(_stroke_layer, _stroke_snap)
	# Commit the finished dab batch immediately so a frame drawn while the
	# playhead is parked is visible without requiring a frame step.
	var finished: PaintSurface = active_surface()
	if finished != null:
		finished.flush()
		finished.queue_redraw()
	_stroke_snap = {}

## Brush coordinates are always page-local. PaintSurface is intentionally
## tile-based and unbounded for import/export, but a user stroke must never
## create ink outside the active project's page rectangle.
func _brush_safe_point(w: Vector2) -> Vector2:
	var p: Variant = projects.active if projects != null else null
	if p == null:
		return w
	var page: Vector2 = p.page
	if page.x <= 0.0 or page.y <= 0.0:
		return w
	return Vector2(clampf(w.x, 0.0, page.x), clampf(w.y, 0.0, page.y))

func _spacing() -> float:
	if App.current_tool == App.Tool.ERASER:
		return maxf(App.eraser_size * 0.08, 0.6)
	var p: BrushLibrary.Preset = App.current_preset()
	var gap: float = 0.1
	if p != null:
		gap = p.spacing
	return maxf(App.brush_size * gap, 0.5)

## Half the width of what is being stamped, which is what decides how much a
## turn has to be tightened for. Jitter and pressure move the real dab about
## either side of this; the nominal size is the right thing to plan spacing
## from, because the spacing has to be one number for the whole piece.
func _dab_radius() -> float:
	if App.current_tool == App.Tool.ERASER:
		return App.eraser_size * 0.5
	return App.brush_size * 0.5

## How fast the hand is moving, in screen pixels per second.
##
## It used to be pixels *per event*, which is not a speed: the same hand at the
## same rate reports twice the number on a 120 Hz screen as on a 60 Hz one, so
## every brush that thins with speed behaved differently on different devices —
## and on the fast screens people buy for drawing, it thinned about twice as
## eagerly as it was ever meant to. Dividing by the time between reports makes
## it a real quantity. The threshold it is measured against was restated to
## match, so a stroke on a 60 Hz device looks exactly as it did and every other
## device now looks the same as that one.
func _note_pace(screen_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var gap: float = float(now - _pace_ms) / 1000.0
	_pace_ms = now
	# A stalled or duplicated report must not divide by nothing.
	gap = clampf(gap, 1.0 / 240.0, 1.0 / 20.0)
	_speed = lerpf(_speed, screen_delta / gap, 0.3)

func _stamp_symmetry(pos: Vector2, from: Vector2) -> void:
	if not symmetry_enabled:
		_stamp_single(pos, from)
		return
	var count: int = maxi(symmetry_count, 2)
	var centre: Vector2 = symmetry_center
	if count == 2:
		_stamp_single(pos, from)
		_stamp_reflected(pos, from)
		return
	var rel_pos: Vector2 = pos - centre
	var rel_from: Vector2 = from - centre
	for i in range(count):
		var a: float = symmetry_angle + TAU * float(i) / float(count)
		var rot: Transform2D = Transform2D(a, Vector2.ZERO)
		var a_pos: Vector2 = centre + rot * rel_pos
		var a_from: Vector2 = centre + rot * rel_from
		_stamp_single(a_pos, a_from)

func _stamp_reflected(pos: Vector2, from: Vector2) -> void:
	var d: Vector2 = pos - symmetry_center
	var n: Vector2 = Vector2(-sin(symmetry_angle), cos(symmetry_angle))
	var reflected: Vector2 = pos - 2.0 * n * d.dot(n)
	var df: Vector2 = from - symmetry_center
	var reflected_from: Vector2 = from - 2.0 * n * df.dot(n)
	_stamp_single(reflected, reflected_from)

func _stamp_single(pos: Vector2, from: Vector2) -> void:
	_stamp_impl(pos, from)

func _stamp_at(pos: Vector2, from: Vector2) -> void:
	if not symmetry_enabled:
		_stamp_impl(pos, from)
		return
	# Lateral symmetry uses the requested axis plus its repeated rotations.
	# For two-way symmetry this is a true mirror; higher counts are rotational.
	_stamp_symmetry(pos, from)

func _stamp_impl(pos: Vector2, from: Vector2) -> void:
	var surface: PaintSurface = active_surface()
	if surface == null:
		return
	var erasing: bool = App.current_tool == App.Tool.ERASER
	var tex: Texture2D = null
	var dab_size: float = 1.0
	var col: Color = Color.BLACK
	var angle: float = 0.0
	var place: Vector2 = pos

	if erasing:
		tex = _eraser_texture()
		dab_size = App.eraser_size
		col = Color(1.0, 1.0, 1.0, App.eraser_opacity)
	else:
		var preset: BrushLibrary.Preset = App.current_preset()
		if preset == null:
			return
		dab_size = App.brush_size
		tex = App.library.texture_for(App.brush_index, dab_size)
		col = App.ink
		col.a = App.brush_opacity

		if preset.follow_direction:
			var d: Vector2 = pos - from
			if d.length_squared() > 0.0001:
				_last_dir = d.angle()
			angle = _last_dir
		if preset.angle_jitter > 0.0:
			angle += randf_range(-preset.angle_jitter, preset.angle_jitter)
		if preset.size_jitter > 0.0:
			dab_size *= 1.0 + randf_range(-preset.size_jitter, preset.size_jitter)
		if preset.scatter > 0.0:
			var r: float = App.brush_size * preset.scatter
			place += Vector2(randf_range(-r, r), randf_range(-r, r))
		if preset.speed_thin > 0.0:
			# Two thousand four hundred pixels a second is forty pixels between
			# reports on a sixty-hertz screen — the old number, restated as a
			# speed so it means the same thing on every device.
			var fast: float = clampf(_speed / 2400.0, 0.0, 1.0)
			dab_size *= 1.0 - preset.speed_thin * fast
		# Eased rather than linear: light pressure should thin the mark
		# quickly and heavy pressure should saturate, which is how a real
		# nib behaves and how tapered ends appear.
		var shaped: float = _dab_press * _dab_press * (3.0 - 2.0 * _dab_press)
		dab_size *= lerpf(0.35, 1.0, shaped)

	if tex == null:
		return
	dab_size = maxf(dab_size, 0.5)
	# --- confined to the chosen comic frame, if there is one ---
	#
	# Asked before the snapshot as well as before the dab. Snapshotting a tile
	# the stroke is not allowed to touch would put an unchanged tile on the
	# undo stack, and an undo step that restores what was already there is an
	# undo press that appears to do nothing.
	if not _panel_allows(place):
		return
	_snapshot_for(surface, place, dab_size)
	surface.stamp(place, dab_size, angle, col, tex, erasing)

## Whether this world point may be painted, given the comic frame in force.
##
## Cheap and asked per dab. On anything that is not a comic page it is one
## null check; on a comic page it is a point-in-polygon over a handful of
## vertices, which is nothing beside the dab it is guarding.
## Which panel the mark in progress belongs to, or -1 when nothing confines
## it. Decided once, where the mark began — see `ComicConfine`.
var _stroke_panel: int = -1

## Ties the mark about to be made to the panel it starts in.
func _bind_stroke_panel(start: Vector2) -> void:
	_stroke_panel = -1
	if projects == null or projects.active == null:
		return
	var p: ProjectManager.Project = projects.active
	if p.kind != ProjectManager.Kind.COMIC:
		return
	if not ComicConfine.tool_is_confined(App.current_tool):
		return
	var page: ProjectManager.Page = p.page_at(p.active_page)
	if page == null or page.frames == null:
		return
	_stroke_panel = ComicConfine.panel_for(page.frames, start)

func _panel_allows(world_pos: Vector2) -> bool:
	if projects == null or projects.active == null:
		return true
	var p: ProjectManager.Project = projects.active
	if p.kind != ProjectManager.Kind.COMIC:
		return true
	var page: ProjectManager.Page = p.page_at(p.active_page)
	if page == null or page.frames == null:
		return true
	var sheet: ComicPage = page.frames
	if not sheet.confine:
		return true
	# The panel the mark began in, not the one last tapped. A page that has
	# been cut confines whether or not anybody has chosen a frame — that is
	# what cutting a page means — and a stroke that wandered into the next
	# panel used to be allowed there, which is the whole of "the drawing goes
	# outside the box".
	if _stroke_panel >= 0:
		return ComicConfine.allows(sheet, _stroke_panel, world_pos)
	if not sheet.confined():
		return true
	# `world_pos` is already page-local: it comes from `screen_to_canvas`,
	# which subtracts `canvas_origin()`, and `canvas_origin()` is the same
	# expression as `page_rect().position`. Subtracting it again asked the
	# frame about a point one page origin away from the finger, so on any page
	# but the first, a stroke inside a visible panel was refused and a stroke
	# outside one was allowed. See the note in `ComicBoard.page_origin`.
	return sheet.allows(world_pos)

func _eraser_texture() -> Texture2D:
	var key: int = App.eraser_shape
	if _eraser_cache.has(key):
		return _eraser_cache[key]
	var lib: BrushLibrary = App.library
	var tex: Texture2D = null
	if key == App.EraserShape.HARD:
		tex = lib.make_texture(lib.round_buffer(0.94))
	elif key == App.EraserShape.SQUARE:
		tex = lib.make_texture(lib.solid_buffer())
	else:
		tex = lib.make_texture(lib.round_buffer(0.35))
	_eraser_cache[key] = tex
	return tex

# ----------------------------------------------------------------- shapes

func _begin_shape(w: Vector2) -> void:
	CanvasShapes.begin(self, w)

func _end_shape(w: Vector2) -> void:
	CanvasShapes.finish(self, w)

func is_drawing() -> bool:
	return _drawing or _marking or _shape_active or _picking \
		or _puppet_pin >= 0 or _puppet_turn >= 0 or _text_grab >= 0 \
		or _symmetry_drag != 0 \
		or sel_active

func break_chain() -> void:
	if not chain_live:
		return
	chain_live = false
	# The lines are forgotten with the chain. Snapping onto something drawn
	# in a run you have already finished would be the app remembering
	# geometry you no longer think of as a chain.
	chain_marks = PackedVector2Array()
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_redraw()

func commit_shape() -> void:
	if layers == null or not layers.can_draw():
		return
	var pts: PackedVector2Array = _shape_points()
	if pts.size() < 2:
		return
	_stroke_snap = {}
	_stroke_layer = layers.active().id
	_speed = 0.0
	_pressure = 1.0
	_press_a = 1.0
	_press_b = 1.0
	_dab_press = 1.0
	_stroke_along(pts)
	_settle_in = 2
	_push_undo(_stroke_layer, _stroke_snap)
	_stroke_snap = {}
	if App.shape_mode == App.Shape.POLYLINE:
		poly_points.clear()
	overlay.queue_redraw()

func _shape_points() -> PackedVector2Array:
	return _outline(App.shape_mode == App.Shape.RECT or App.shape_mode == App.Shape.SQUARE,
		App.shape_mode == App.Shape.ELLIPSE,
		App.shape_mode == App.Shape.LINE or App.shape_mode == App.Shape.CHAIN,
		App.shape_mode == App.Shape.POLYLINE,
		_shape_a, _shape_b, poly_points, App.shape_mode == App.Shape.DIAMOND)

func _outline(is_rect: bool, is_ellipse: bool, is_line: bool, is_poly: bool,
		a: Vector2, b: Vector2, pts: PackedVector2Array,
		is_diamond: bool = false) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if is_line:
		out.append(a)
		out.append(b)
	elif is_diamond:
		var rr: Rect2 = Rect2(a, b - a).abs()
		var c: Vector2 = rr.position + rr.size * 0.5
		var rx: float = rr.size.x * 0.5
		var ry: float = rr.size.y * 0.5
		out.append(Vector2(c.x, c.y - ry))
		out.append(Vector2(c.x + rx, c.y))
		out.append(Vector2(c.x, c.y + ry))
		out.append(Vector2(c.x - rx, c.y))
		out.append(Vector2(c.x, c.y - ry))
	elif is_rect:
		var r: Rect2 = Rect2(a, b - a).abs()
		out.append(r.position)
		out.append(r.position + Vector2(r.size.x, 0.0))
		out.append(r.position + r.size)
		out.append(r.position + Vector2(0.0, r.size.y))
		out.append(r.position)
	elif is_ellipse:
		var rr: Rect2 = Rect2(a, b - a).abs()
		var c: Vector2 = rr.position + rr.size * 0.5
		var rad: Vector2 = rr.size * 0.5
		var steps: int = clampi(int(rr.size.length() * 0.7), 32, 256)
		for i in range(steps + 1):
			var t: float = TAU * float(i) / float(steps)
			out.append(c + Vector2(cos(t) * rad.x, sin(t) * rad.y))
	elif is_poly:
		out = _smooth_polyline(pts)
	return out

func _smooth_polyline(src: PackedVector2Array) -> PackedVector2Array:
	if src.size() < 3:
		return src
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = src.size()
	for i in range(n - 1):
		var p0: Vector2 = src[maxi(i - 1, 0)]
		var p1: Vector2 = src[i]
		var p2: Vector2 = src[i + 1]
		var p3: Vector2 = src[mini(i + 2, n - 1)]
		for s in range(16):
			var t: float = float(s) / 16.0
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(src[n - 1])
	return out

func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

## Inks an outline that has already been worked out as points.
##
## Shapes arrive here: a circle is two hundred and fifty-six short segments, a
## rectangle is four long ones. The spacing is read once for the whole outline
## rather than once per dab, and then tightened segment by segment wherever the
## outline turns — read off the angle to the next segment, which for a circle
## is the circle's own curvature and for a rectangle is nothing at all until
## the corner. It is the same rule the freehand curve uses, applied to the one
## other place dabs are laid down, so a wide brush draws a wide clean circle
## instead of a scalloped one.
func _stroke_along(pts: PackedVector2Array) -> void:
	var carry: float = 0.0
	var base: float = _spacing()
	var radius: float = _dab_radius()
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg <= 0.0001:
			continue
		var dir: Vector2 = (b - a) / seg
		var spacing: float = base
		if i + 2 < pts.size():
			var ahead: Vector2 = pts[i + 2] - b
			if ahead.length_squared() > 0.0000001:
				var bend: float = absf(dir.angle_to(ahead.normalized()))
				if bend > 0.0001:
					# Angle over distance is curvature; its reciprocal is the
					# radius of the turn the outline is making here.
					var turn: float = seg / bend
					spacing = base * clampf(turn / (turn + radius), 0.42, 1.0)
		var t: float = -carry
		var guard: int = 0
		while t + spacing <= seg and guard < 4096:
			t += spacing
			var p: Vector2 = a + dir * t
			_stamp_at(p, p - dir)
			guard += 1
		carry = seg - t

func _nearest_point(w: Vector2) -> int:
	var best: int = -1
	var best_d: float = 18.0 / maxf(view_zoom, 0.0001)
	for i in poly_points.size():
		var d: float = poly_points[i].distance_to(w)
		if d < best_d:
			best_d = d
			best = i
	return best

# --------------------------------------------------------------- selection

func _begin_mark(w: Vector2) -> void:
	CanvasMarks.begin_mark(self, w)

func _continue_mark(w: Vector2) -> void:
	CanvasMarks.continue_mark(self, w)

func _end_mark(_w: Vector2) -> void:
	CanvasMarks.end_mark(self, _w)

func close_selection() -> void:
	CanvasMarks.close_selection(self)

func clear_marks() -> void:
	CanvasMarks.clear_marks(self)

func has_marks() -> bool:
	return CanvasMarks.has_marks(self)

func lift_selection(keep_original: bool = false) -> bool:
	return CanvasMarks.lift_selection(self, keep_original)

func selection_transform() -> Transform2D:
	return CanvasMarks.selection_transform(self)

func _sel_corners() -> Array:
	return CanvasMarks.sel_corners(self)

func _rotate_handle() -> Vector2:
	return CanvasMarks.rotate_handle(self)

func _hit_handle(screen: Vector2) -> int:
	return CanvasMarks.hit_handle(self, screen)

func _start_grab(kind: int, screen: Vector2) -> void:
	CanvasMarks.start_grab(self, kind, screen)

func _update_grab(screen: Vector2) -> void:
	CanvasMarks.update_grab(self, screen)

func commit_selection() -> void:
	CanvasMarks.commit_selection(self)

func _carry_rig_with_selection() -> void:
	CanvasMarks.carry_rig_with_selection(self)

func _draw_layer_rig() -> void:
	CanvasViewDraw.draw_layer_rig(self)

func cancel_selection() -> void:
	CanvasMarks.cancel_selection(self)

func _drop_floating() -> void:
	CanvasMarks.drop_floating(self)

func float_image(img: Image, layer_id: int, centre: Vector2) -> bool:
	return CanvasMarks.float_image(self, img, layer_id, centre)

# --------------------------------------------------------------- clipboard

## Which distortion the floating selection is wearing, and how much.
##
## Held rather than applied at once, because a distortion is something you
## push and pull until it looks right. Nothing is written to the layer until
## the selection is put down — so every amount tried in between costs one
## reshaped mesh and nothing else, and the original is still exactly the
## original however long it took to settle on a number.
var distort_kind: int = Distort.Kind.LEAN
var distort_amount: float = 0.0

func set_distort(kind: int, amount: float) -> void:
	CanvasMarks.set_distort(self, kind, amount)

func trim_selection(cut_kind: int, keep_inside: bool) -> bool:
	return CanvasMarks.trim_selection(self, cut_kind, keep_inside)

func _note_clip() -> void:
	CanvasMarks.note_clip(self)

func copy_selection() -> bool:
	return CanvasMarks.copy_selection(self)

func cut_selection() -> bool:
	return CanvasMarks.cut_selection(self)

func paste_clipboard() -> bool:
	return CanvasMarks.paste_clipboard(self)

func begin_placement(landing: DrawTransfer.Landing) -> bool:
	return CanvasMarks.begin_placement(self, landing)

func _commit_placement() -> void:
	CanvasMarks.commit_placement(self)

func cancel_placement() -> void:
	CanvasMarks.cancel_placement(self)

func paste_as_new_layer() -> bool:
	return CanvasMarks.paste_as_new_layer(self)

func _commit_fill_shape() -> void:
	CanvasMarks.commit_fill_shape(self)

func _fill_mask(w: int, h: int) -> PackedByteArray:
	return CanvasMarks.fill_mask(w, h)

# ------------------------------------------------------------------- fill

func _do_fill(w: Vector2) -> void:
	var surface: PaintSurface = active_surface()
	if surface == null or layers == null or not layers.can_draw():
		return
	# The panel the seed lands in. A flood that starts in the gutter fills
	# nothing at all, which is the honest answer: there is no panel there.
	_bind_stroke_panel(w)
	if not _panel_allows(w):
		return
	var page: Vector2 = Vector2.ZERO
	if projects.active != null:
		page = projects.active.page
	var res: Variant = FloodFill.run(layers, w, App.fill_ink, size, view_zoom, page)
	if res == null:
		return
	var data: Dictionary = res
	var origin: Vector2i = data["origin"]
	var img: Image = data["image"]
	# Cut to the panel before it is laid down.
	#
	# A dab that is refused simply does not happen, so the brush needs nothing
	# more than the test above. A flood is decided in one go: it starts inside
	# the panel, runs wherever the drawing lets it, and one gap in a line lets
	# it out into the next panel as a solid block of colour. Trimming the
	# result also means the fill stops at the panel edge itself, without the
	# artist having to have drawn a line there.
	if _stroke_panel >= 0 and projects.active != null:
		var page_now: ProjectManager.Page = projects.active.page_at(
			projects.active.active_page)
		if page_now != null and page_now.frames != null:
			ComicConfine.clip_to_panel(page_now.frames, _stroke_panel, img,
				Vector2(origin))
	var snap: Dictionary = {}
	_collect(surface, Rect2i(origin, Vector2i(img.get_width(), img.get_height())), snap)
	surface.blit_image(img, Vector2(origin))
	history.push_pixels(UiKit.label_for("Fill", "ملء"), layers.active().id, snap)

# -------------------------------------------------------------- eyedropper

func _update_pick(screen: Vector2) -> void:
	var w: Vector2 = screen_to_canvas(screen)
	_pick_screen = screen
	if layers == null:
		return
	_pick_color = layers.sample(w)
	# A handful of pixels, so turning them back into ordinary colours for
	# the magnifier costs nothing worth measuring.
	var patch: Image = layers.read_region(Rect2i(
		Vector2i(int(floor(w.x)) - 7, int(floor(w.y)) - 7), Vector2i(15, 15)))
	if patch != null:
		for py in range(patch.get_height()):
			for px in range(patch.get_width()):
				patch.set_pixel(px, py,
					PaintSurface.to_straight(patch.get_pixel(px, py)))
		_pick_tex = ImageTexture.create_from_image(patch)
	pointer_moved.emit(w)
	_loupe.queue_redraw()

func _finish_pick() -> void:
	_picking = false
	_loupe.queue_redraw()
	if _pick_color.a < 0.02:
		App.end_pick()
		return
	var c: Color = _pick_color
	c.a = 1.0
	App.apply_picked(c)
	App.end_pick()

func _draw_loupe() -> void:
	CanvasViewDraw.draw_loupe(self)

# ---------------------------------------------------------------- history

func _snapshot_for(surface: PaintSurface, pos: Vector2, dab_size: float) -> void:
	var reach: float = dab_size * 0.75 + 2.0
	_collect(surface, Rect2i(
		Vector2i(int(floor(pos.x - reach)), int(floor(pos.y - reach))),
		Vector2i(int(reach * 2.0) + 2, int(reach * 2.0) + 2)), _stroke_snap)

func _snapshot_for_target(surface: PaintSurface, pos: Vector2,
		dab_size: float, target: Dictionary) -> void:
	var reach: float = dab_size * 0.75 + 2.0
	_collect(surface, Rect2i(
		Vector2i(int(floor(pos.x - reach)), int(floor(pos.y - reach))),
		Vector2i(int(reach * 2.0) + 2, int(reach * 2.0) + 2)), target)

func _snapshot_rect(surface: PaintSurface, rect: Rect2i) -> void:
	_collect(surface, rect, _sel_snapshot)

func _collect(surface: PaintSurface, rect: Rect2i, into: Dictionary) -> void:
	var c0: Vector2i = surface.tile_coord(Vector2(rect.position))
	var c1: Vector2i = surface.tile_coord(Vector2(rect.position + rect.size))
	for ty in range(c0.y, c1.y + 1):
		for tx in range(c0.x, c1.x + 1):
			var c: Vector2i = Vector2i(tx, ty)
			if into.has(c):
				continue
			into[c] = surface.snapshot_tile(c)

func _push_undo(layer_id: int, snap: Dictionary, label: String = "") -> void:
	if history == null:
		return
	if label == "":
		label = UiKit.label_for("Stroke", "خط")
	history.push_pixels(label, layer_id, snap)

func _restore(layer_id: int, snap: Dictionary) -> void:
	if layers == null:
		return
	var surface: PaintSurface = layers.surface_by_id(layer_id)
	if surface == null:
		return
	for c in snap.keys():
		surface.restore_tile(c, snap[c])

func can_undo() -> bool:
	return history != null and history.can_undo()

func can_redo() -> bool:
	return history != null and history.can_redo()

func undo() -> void:
	# A floating selection is a change in progress, not a finished one, so
	# the first undo puts it back rather than reaching past it.
	if sel_active:
		cancel_selection()
		return
	if history != null:
		history.undo()
	# **The chain guide goes back with the line it was guiding.**
	#
	# The blue marks are not painted onto the layer — they are an overlay
	# showing where the run of lines has been and which corner the next one
	# will start from. Undo puts pixels back, and an overlay has no pixels to
	# put back, so the drawn line vanished and its blue ghost stayed exactly
	# where it was: describing a chain that no longer existed, and offering to
	# snap the next line onto a corner that had been taken away.
	#
	# It could not be cleared by drawing over it, or by undoing again, or by
	# anything short of changing tool — which is why it read as damage rather
	# than as state.
	#
	# So an undo ends the run. That is also the honest reading of the gesture:
	# taking back the last line of a chain is saying the chain is not what you
	# wanted, and the next line should start where you put it rather than
	# where the withdrawn one happened to end.
	break_chain()

func redo() -> void:
	if history != null:
		history.redo()
	# For the same reason as undo: the guide describes a run that redo has
	# just rewritten, and a guide that disagrees with the drawing is worse
	# than none.
	break_chain()

func clear_active_layer() -> void:
	var surface: PaintSurface = active_surface()
	if surface == null or layers == null:
		return
	var snap: Dictionary = {}
	for c in surface.get_tile_coords():
		snap[c] = surface.snapshot_tile(c)
	surface.clear_all()
	history.push_pixels(UiKit.label_for("Erase layer", "مسح طبقة"), layers.active().id, snap)

# ----------------------------------------------------------------- overlay

func _draw_overlay() -> void:
	CanvasViewDraw.draw_overlay(self)

func _draw_marks(w: float) -> void:
	CanvasViewDraw.draw_marks(self, w)

func _draw_floating(w: float) -> void:
	CanvasViewDraw.draw_floating(self, w)
