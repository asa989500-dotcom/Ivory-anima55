class_name BSplineRoom
extends Control
## A room for moving a drawing, rather than distorting one.

## The layer comes in on its own against a measured grid, and everything that
## happens here is done by steering curves and bones — never by pushing pixels
## about. That distinction runs through the whole design: a control point does
## not drag the ink near it, it changes the shape of a curve, and the drawing
## rides that curve. Which is why a limb bent here keeps its length and its
## thickness, and why the same bend done by shoving a mesh does not.
##
## The drawing is bound to a curve in **curve space**: for every scrap of ink,
## how far along the curve it sits and how far off to the side. Move the
## control points and the curve changes; each scrap is put back at the same
## place along the new curve, turned by however much the curve turned there.
## Length along the curve is preserved by construction, and because the curve
## is C² the turning changes smoothly — so a joint bends without the pinch
## that a triangle mesh folds into.

signal closed()
signal applied()

## Kept so the room can be laid out again after it is on screen — the first
## placement happens before `size` is anything, which is why the way out used
## to end up in the wrong place even once its anchor was right.
var _leave_btn: Button = null

const ICON: String = "res://assets/icons/%s.png"

## How close this room will let you get, and how far out.
##
## The same range Character 360 was given, and for the same reason: a bone is
## placed at the scale of the *joint*, not of the figure. At twenty-four times
## a knuckle on a full figure is a few pixels across and a point lands on the
## finger beside it. The floor comes down too, because getting the whole
## drawing back in one gesture matters as much as getting close to part of it.
const MIN_ZOOM: float = 0.02
const MAX_ZOOM: float = 64.0

## How near a finger has to be to catch a point or a bone end, in screen
## pixels. A little under half a centimetre — about the width of a
## fingertip's contact patch.
## How near a finger must be to take hold of a point, in screen pixels.
##
## Thirty was a fingertip and a half. On a figure where two points sit close
## together it meant reaching for one and moving the other — and once moved,
## the only way back was undo. Eighteen is still comfortably larger than the
## dot being aimed at, and small enough that two points a finger apart are two
## different targets.
const GRAB_PX: float = 18.0
## The room's own blue, taken from the mark on the application.
##
## It was very nearly black, and on a near-black field a dark drawing is a
## drawing you cannot see — which in a room built for placing points on
## artwork precisely is the one thing the background must never do. The teal
## of the logo is light enough that dark ink reads against it and still dark
## enough that ivory and gold read against *it*, so nothing else in here had
## to change to accommodate the swap.
const ROOM_BLUE: Color = Color("#2A6D80")
## Grid lines, in the same family and lifted off the field rather than laid
## over it, so the mesh stays legible without competing with the drawing.
const GRID_INK: Color = Color(0.72, 0.86, 0.92, 0.22)
const GRID_BOLD: Color = Color(0.80, 0.92, 0.97, 0.40)
const AXIS_INK: Color = Color(0.92, 0.97, 1.00, 0.78)
const GOLD: Color = Color("#D9B45B")
const IVORY: Color = Color("#FFF8E7")
const BONE_INK: Color = Color("#E8D5A3")
const TAP_MS: int = 320
const HOLD_MS: int = 380

enum Mode { ADD, MOVE, CONNECT, BONE, POSE }

# --- what came in ---
var view: CanvasView = null
var layer_id: int = -1
var page: Rect2i = Rect2i()
var art: Image = null
var _art_tex: ImageTexture = null
var _ink_rect: Rect2i = Rect2i()

# --- the rig ---
var spline: BSpline = null
var bones: Array = []
## The sheet of ink, as a mesh laid over it. Everything the rigs do is done
## to these vertices; the picture rides on them.
var _rest: PackedVector2Array = PackedVector2Array()
var _now: PackedVector2Array = PackedVector2Array()
var _uv: PackedVector2Array = PackedVector2Array()
var _tris: PackedInt32Array = PackedInt32Array()
var _cols: int = 0
var _rows: int = 0
var _cell: Vector2 = Vector2.ONE
var _slot: PackedInt32Array = PackedInt32Array()
var _home: PackedInt32Array = PackedInt32Array()
## Per vertex: where it sits in the rest curve's own frame.
## How far *along* the rest curve each vertex sat, measured as distance and
## not as parameter — see `_bind_curve` for why that distinction is the whole
## difference between moving a drawing and stretching one.
var _curve_s: PackedFloat32Array = PackedFloat32Array()
var _curve_t: PackedFloat32Array = PackedFloat32Array()
var _curve_n: PackedFloat32Array = PackedFloat32Array()
var _curve_pull: PackedFloat32Array = PackedFloat32Array()
## Which control point each vertex belongs to, and how far it is between that
## one and the next. See `_anchor_s` — this is what makes moving a point a
## *local* edit instead of one that slides the whole drawing along the curve.
var _curve_at: PackedInt32Array = PackedInt32Array()
var _curve_mix: PackedFloat32Array = PackedFloat32Array()
var _curve_off0: PackedFloat32Array = PackedFloat32Array()
var _curve_off1: PackedFloat32Array = PackedFloat32Array()
## Where each control point sits along the curve, in distance, as the curve
## stands now — and as it stood when the drawing was bound to it.
var _anchor_s: PackedFloat32Array = PackedFloat32Array()
var _rest_anchor_s: PackedFloat32Array = PackedFloat32Array()
## Per vertex per bone: the vertex written in that bone's rest frame, and how
## much say the bone has.
var _skin: Array = []
## The posed drawing, ready to draw. Rebuilt by `_push_mesh`, never by a drag.
var _bent: ArrayMesh = null
## Raised by `_pose`, lowered once a frame by `_process`.
##
## A finger reports far faster than the screen redraws — 120 to 240 times a
## second against 60 — so posing on every event did the same nine thousand
## vertices three or four times over and threw all but the last away. This is
## why the room felt heavy on a tablet that runs Clip Studio without
## complaint: not the device, but work being repeated between frames nobody
## ever saw.
var _pose_due: bool = false
var _arc_pts: PackedVector2Array = PackedVector2Array()
var _arc_len: PackedFloat32Array = PackedFloat32Array()

# --- what the hand is doing ---
var mode: int = Mode.ADD
var _grab: int = -1
var _grab_bone: int = -1
var _grab_end: int = 0

## Whether the bones have been swung since the skeleton was laid.
##
## Swinging a bone exists to *try* a bend — to see whether a shoulder reaches,
## whether an elbow lands where it should. It is not a pose being authored,
## and treating it as one is how a rig comes to leave the room bent into
## whatever position it happened to be in when the finger last lifted. That is
## nobody's intention and very hard to notice until a whole scene is wrong.
##
## So the bones go back to rest before anything leaves this room. What is
## committed is the body the bones were built on — the drawing as it was
## drawn — and every rehearsal is thrown away, which is exactly what makes
## rehearsing safe enough to do freely.
##
## The skeleton itself is kept. Where the bones *are* is a rehearsal; where
## they were *laid* is the rig, and that is saved as it always was.
var _rehearsing: bool = false
var _bone_from: Vector2 = Vector2.ZERO
var _bone_drawing: bool = false
var _tap_ms: int = 0
var _tap_at: int = -1
var _press_ms: int = 0
var _press_at: Vector2 = Vector2.ZERO

# --- the window onto the page ---
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _touches: Dictionary = {}
var _pinch_span: float = 0.0
var _pinch_zoom: float = 1.0
var _pinch_mid: Vector2 = Vector2.ZERO

var _board: Control = null
var _bar: PanelContainer = null
var _mode_buttons: Dictionary = {}
var _say: Label = null

## The bones this room holds are `BoneRig.Bone`, and every piece of
## arithmetic done to them lives in `bone_rig.gd`.
##
## This room used to carry a bone class of its own, and so did the room beside
## it. Two copies of a thing drift: this one grew closed-form reach
## and the other did not, this one snapped one end to quarter turns and the
## other snapped both. A person moving between the two rooms was moving
## between two tools that looked identical and did not behave identically.
##
## There is one bone now, in one file, and a correction made to it is a
## correction made in every room at once.

# ------------------------------------------------------------------ set up

## Opening a whole folder instead of one layer.
##
## Every rigged layer inside it is read in and its bones gathered into one
## skeleton, so a figure built as separate drawings — body, arm, head — poses
## as a figure. The layers stay exactly as many layers as they were: what is
## shared is the skeleton, never the ink.
var _framed: bool = false
var gather_group: int = -1
var _members: Array = []

func setup_group(canvas: CanvasView, group_id: int) -> bool:
	view = canvas
	if view == null or view.layers == null or view.projects.active == null:
		return false
	_members = []
	for l in view.layers.layers:
		if l.group_id == group_id and not l.rig.is_empty():
			_members.append(l)
	if _members.is_empty():
		return false
	gather_group = group_id
	if not setup(canvas):
		return false

	# The gathered skeleton is every member's bones side by side, in the pose
	# each was last left in. Read through the one reader, so a rig written
	# before turns were recorded opens standing exactly as it was left.
	bones.clear()
	for l in _members:
		for one in BoneRig.from_rows((l.rig as Dictionary).get("bones", [])):
			(one as BoneRig.Bone).parent = -1
			bones.append(one)

	# Bones that meet are chained, so a limb built across two layers still
	# swings from its shoulder rather than floating free of it. How near two
	# bones must be to count as jointed is a share of the figure rather than
	# a flat thirty units: a shoulder and an upper arm drawn on a large canvas
	# can be forty units apart and obviously joined, while on a small one
	# thirty units is halfway down the body and would chain two limbs that
	# never touch.
	BoneRig.chain(bones, BoneRig.join_reach(
		maxf(float(page.size.x), float(page.size.y))))
	BoneRig.adopt(bones)

	_set_mode(Mode.POSE)
	_rebind()
	_refresh()
	return true

func setup(canvas: CanvasView) -> bool:
	view = canvas
	if view == null or view.layers == null or view.projects.active == null:
		return false
	var layer: LayerStack.Layer = view.layers.active()
	if layer == null:
		return false
	layer.surface.flush()
	page = Rect2i(Vector2i.ZERO, Vector2i(view.projects.active.page))
	_ink_rect = layer.surface.content_bounds().intersection(page)
	# The B-Spline room can be entered on an empty layer; a tiny placeholder
	# keeps the room layout valid until the user adds geometry.
	if _ink_rect.size.x < 4 or _ink_rect.size.y < 4:
		_ink_rect = Rect2i(Vector2i.ZERO, Vector2i(4, 4))
		art = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	else:
		art = layer.surface.read_region(_ink_rect)
		if art == null:
			art = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	var used: Rect2i = art.get_used_rect()
	if used.size.x >= 4 and used.size.y >= 4:
		if used.position != Vector2i.ZERO or used.size != _ink_rect.size:
			var trim: Image = Image.create_empty(used.size.x, used.size.y, false,
				Image.FORMAT_RGBA8)
			trim.blit_rect(art, used, Vector2i.ZERO)
			art = trim
			_ink_rect = Rect2i(_ink_rect.position + used.position, used.size)
	_art_tex = ImageTexture.create_from_image(art)
	layer_id = layer.id

	spline = BSpline.new()
	bones = []
	_build_shell()
	_build_mesh()
	# A layer posed before comes back standing as it was left.
	if not layer.rig.is_empty() and gather_group < 0:
		load_rig(layer.rig)
	return true

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var back: ColorRect = ColorRect.new()
	back.color = ROOM_BLUE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_board = Control.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	add_child(_board)

	# Only one thing lives at the top of this room, and it is the way out.
	# Named as well as drawn, and white rather than rail-grey.
	#
	# It was there all along and nobody could find it: a grey icon of a door
	# on a grey plate, in a room whose whole point is that everything else
	# has been taken away. The way out of a room you cannot leave is the one
	# control that must never need looking for.
	var leave: Button = UiKit.make_tool_button(ICON % "exit",
		UiKit.label_for("Exit", "خروج"))
	leave.toggle_mode = false
	leave.text = UiKit.label_for("Exit", "خروج")
	leave.custom_minimum_size = Vector2(UiKit.s(124.0), UiKit.s(58.0))
	# Gold on dark ink, not grey on grey.
	#
	# It was drawn in the rail's own colours, which are made to sit quietly
	# behind a drawing — and quiet is the opposite of what the only way out of
	# a full-screen room should be. It is now the one gold thing at the top of
	# the room and the only control up there at all, so there is nothing it
	# can be confused with.
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = Color(0.06, 0.16, 0.20, 0.96)
	pill.border_color = GOLD
	pill.set_border_width_all(int(maxf(UiKit.s(2.0), 2.0)))
	pill.set_corner_radius_all(int(UiKit.s(14.0)))
	pill.content_margin_left = UiKit.s(12.0)
	pill.content_margin_right = UiKit.s(12.0)
	leave.add_theme_stylebox_override("normal", pill)
	leave.add_theme_stylebox_override("hover", pill)
	leave.add_theme_stylebox_override("pressed", pill)
	leave.add_theme_stylebox_override("focus", pill)
	leave.add_theme_color_override("icon_normal_color", GOLD)
	leave.add_theme_color_override("icon_hover_color", GOLD)
	leave.add_theme_color_override("icon_pressed_color", GOLD)
	leave.add_theme_color_override("font_color", GOLD)
	leave.add_theme_color_override("font_hover_color", GOLD)
	leave.add_theme_color_override("font_pressed_color", GOLD)
	if UiKit.font != null:
		leave.add_theme_font_override("font", UiKit.font)
	leave.add_theme_font_size_override("font_size", int(UiKit.s(15.0)))
	# Anchored top-LEFT and then placed by hand.
	#
	# It was anchored top-right and *also* given a position measured from the
	# left edge. With the anchor on the right, `position` is an offset from
	# that right edge — so the button was placed a full screen width past the
	# corner and drawn entirely off the display. Every word of the note above
	# about the way out being easy to find was true, and the control it
	# described was not on the screen at all.
	#
	# Anchoring left makes `position` mean what the arithmetic below assumes:
	# a distance from the left edge, which is what `size.x - 118` is.
	leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	leave.position = Vector2(size.x - UiKit.s(118.0), UiKit.s(14.0))
	leave.pressed.connect(func() -> void:
		_end_rehearsal()
		closed.emit())
	add_child(leave)
	_leave_btn = leave
	resized.connect(func() -> void:
		_place_leave()
		_layout_bar())

	# Legacy compatibility room: controls are intentionally retired. The user-facing
	# Character 360 is a separate room and is not hosted here.

func _build_bar() -> void:
	pass

func _mode_button(row: HBoxContainer, which: int, label: String) -> void:
	var b: Button = UiKit.make_text_button(label, true)
	b.toggle_mode = true
	b.pressed.connect(func() -> void: _set_mode(which))
	_mode_buttons[which] = b
	row.add_child(b)

func _layout_bar() -> void:
	if _bar == null:
		return
	_bar.position = Vector2((size.x - _bar.size.x) * 0.5,
		size.y - _bar.size.y - UiKit.s(14.0))

## The rules change with the mode, so the room says which rule is in force
## rather than leaving it to be discovered by a gesture that does nothing.
func _set_mode(which: int) -> void:
	mode = which
	for key in _mode_buttons.keys():
		(_mode_buttons[key] as Button).set_pressed_no_signal(key == which)
	_grab = -1
	_grab_u = -1.0
	_grab_bone = -1
	_bone_drawing = false
	match which:
		Mode.ADD:
			_tell(UiKit.label_for(
				"Put every point on the drawing first. Points off the artwork are refused — a point with no ink under it has nothing to carry.",
				"ضع كل النقاط على الرسم أولاً. النقاط خارج الرسم مرفوضة — نقطة بلا حبر تحتها لا تحمل شيئاً."))
		Mode.MOVE:
			_tell(UiKit.label_for(
				"Move only. Points cannot be added here, so a hand reaching for one can never leave a new one behind.",
				"التحريك فقط. لا تُضاف نقاط هنا، فاليد الممتدة إلى نقطة لا تترك خلفها نقطة جديدة أبداً."))
		Mode.CONNECT:
			_tell(UiKit.label_for(
				"Tap between two points to put a new one there, or tap a point twice to make the curve turn a corner at it instead of flowing through.",
				"اضغط بين نقطتين لوضع نقطة بينهما، أو اضغط نقطة مرتين ليصنع المنحنى زاوية عندها بدل أن ينساب."))
		Mode.BONE:
			# Reachable only by a rig saved while this mode still had a button.
			# It says where bones live now rather than silently doing nothing.
			_tell(UiKit.label_for(
				"Bones are laid on the layer itself now — open the layer's settings and tap Add bone.",
				"العظام تُوضع على الطبقة نفسها الآن — افتح إعدادات الطبقة واضغط «أضف عظاماً»."))
		Mode.POSE:
			_tell(UiKit.label_for(
				"Drag a joint. It turns wherever you take it and stops where you stop — there is no angle it snaps to.",
				"اسحب مفصلاً. يدور حيث تأخذه ويقف حيث تقف — لا زاوية يقفز إليها."))
	_refresh()

func _tell(text: String) -> void:
	if _say != null:
		_say.text = text

# ------------------------------------------------------- page <-> screen

## Sets the page in the middle of the screen, once, the first moment both the
## page and the screen have a size.
##
## This used to `await get_tree().process_frame` from inside `setup()`. But
## `setup()` runs while the room is still a loose object — it is only added to
## anything if setup succeeds — and `get_tree()` on a node outside the tree is
## null. Awaiting a property of null is what raised
##
##     Invalid access to property or key 'process_frame'
##     on a base object of type 'null instance'
##
## and it is why the room never opened. Nothing needs to be awaited: the room
## is told when it is given a size, so it waits to be told.
func _frame_page() -> void:
	if _framed:
		return
	var span: Vector2 = Vector2(page.size)
	if span.x <= 0.0 or span.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	_framed = true
	_zoom = minf(size.x / span.x, size.y / span.y) * 0.72
	_pan = size * 0.5 - span * 0.5 * _zoom
	_refresh()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_frame_page)
	_frame_page()
	# The way out is placed from `size`, and `size` is nothing until this node
	# has been laid out at least once. Placing it again here means it is right
	# on the first frame the room is ever shown, not only after a rotation.
	_place_leave()
	# The tablet's own Back gesture leaves this room too, but that is handled
	# once in `Main._step_back` rather than here: the notification reaches
	# every node in the tree, so a second handler in the room would close it
	# and then have main act on the same press again.
	set_process_unhandled_input(true)

func _place_leave() -> void:
	if _leave_btn == null or not is_instance_valid(_leave_btn):
		return
	# Measured from the button's own width rather than a number typed twice.
	# The two used to be written separately and drifted apart the moment the
	# button was made bigger.
	var w: float = maxf(_leave_btn.size.x, _leave_btn.custom_minimum_size.x)
	_leave_btn.position = Vector2(size.x - w - UiKit.s(14.0), UiKit.s(14.0))

func _unhandled_input(event: InputEvent) -> void:
	# Escape on a keyboard, for anyone testing on a desktop.
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_end_rehearsal()
		closed.emit()
		get_viewport().set_input_as_handled()

func to_screen(p: Vector2) -> Vector2:
	return p * _zoom + _pan

func to_page(p: Vector2) -> Vector2:
	return (p - _pan) / maxf(_zoom, 0.000001)

# ------------------------------------------------------------ safety sensor

## Whether there is ink under a place on the page.
##
## This is the sensor the whole room leans on. A control point steers a curve
## that the drawing rides; a point placed where no drawing is has nothing
## under it to carry, and a bone laid across empty air is a bone belonging to
## no limb. Both are refused rather than accepted and left to behave oddly
## later.
func on_ink(at: Vector2) -> bool:
	if art == null or art.get_width() < 1 or art.get_height() < 1:
		return false
	var local: Vector2i = Vector2i((at - Vector2(_ink_rect.position)).floor())
	if local.x < 0 or local.y < 0 \
			or local.x >= art.get_width() or local.y >= art.get_height():
		return false
	return art.get_pixel(local.x, local.y).a > 0.02

## A bone has to lie *along* the drawing, not merely start and end on it —
## an arm and a leg both have ink, and a bone joining them would cross the
## paper between. So the whole length is walked and every step has to land on
## something.
func bone_fits(a: Vector2, b: Vector2) -> bool:
	var span: float = a.distance_to(b)
	if span < 6.0:
		return false
	var steps: int = maxi(int(span / 3.0), 8)
	var misses: int = 0
	for i in steps + 1:
		if not on_ink(a.lerp(b, float(i) / float(steps))):
			misses += 1
			# A few steps may fall in a gap inside a stroke — an outline
			# drawing is mostly hollow. A run of them means the bone has left
			# the drawing altogether.
			# Whole steps on purpose — this is a count of samples.
			@warning_ignore("integer_division")
			var slack: int = floori(float(steps) / 6.0)
			if misses > maxi(slack, 2):
				return false
		else:
			misses = 0
	return true

# ------------------------------------------------------------------- input

func _on_board_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 2:
				_begin_pinch()
			elif _touches.size() == 1:
				_press(st.position)
		else:
			_touches.erase(st.index)
			if _touches.is_empty():
				_release(st.position)
		_board.accept_event()
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			_pinch()
		else:
			_drag(sd.position)
		_board.accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release(mb.position)
		_board.accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drag(mm.position)
			_board.accept_event()

func _begin_pinch() -> void:
	_grab = -1
	_grab_u = -1.0
	_grab_bone = -1
	_bone_drawing = false
	var keys: Array = _touches.keys()
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	_pinch_span = a.distance_to(b)
	_pinch_zoom = _zoom
	_pinch_mid = (a + b) * 0.5

func _pinch() -> void:
	var keys: Array = _touches.keys()
	if keys.size() < 2:
		return
	var a: Vector2 = _touches[keys[0]]
	var b: Vector2 = _touches[keys[1]]
	var span: float = a.distance_to(b)
	if _pinch_span < 8.0 or span < 8.0:
		return
	var mid: Vector2 = (a + b) * 0.5
	var anchor: Vector2 = to_page(_pinch_mid)
	_zoom = clampf(_pinch_zoom * span / _pinch_span, MIN_ZOOM, MAX_ZOOM)
	_pan += mid - _pinch_mid
	_pinch_mid = mid
	_pan += to_screen(anchor).direction_to(mid) * 0.0
	_pan += mid - to_screen(anchor)
	_refresh()

func _zoom_at(screen: Vector2, by: float) -> void:
	var anchor: Vector2 = to_page(screen)
	_zoom = clampf(_zoom * by, MIN_ZOOM, MAX_ZOOM)
	_pan += screen - to_screen(anchor)
	_refresh()

func _press(screen: Vector2) -> void:
	var w: Vector2 = to_page(screen)
	var now: int = Time.get_ticks_msec()
	_press_ms = now
	_press_at = screen
	# Measured on the screen and scaled for the device, then converted to
	# page units — so the grab is the same size under the finger however far
	# in or out the room is zoomed. Twenty-two page units was a different
	# thing entirely: a hand's width when zoomed out, and nothing at all when
	# zoomed in, which is exactly when a point is being placed carefully.
	var reach: float = UiKit.s(GRAB_PX) / maxf(_zoom, 0.000001)

	match mode:
		Mode.ADD:
			if not on_ink(w):
				_tell(UiKit.label_for("That is off the drawing — no point put down",
					"هذا خارج الرسم — لم تُوضع نقطة"))
				return
			spline.add_point(w)
			_rebind()
			_refresh()
		Mode.MOVE:
			_grab = _point_at(w, reach)
			_grab_u = -1.0
		Mode.CONNECT:
			var hit: int = _point_at(w, reach)
			if hit >= 0:
				var double: bool = now - _tap_ms <= TAP_MS and _tap_at == hit
				_tap_ms = now
				_tap_at = hit
				if double:
					# A corner, or back to a flow. This is knot insertion: the
					# same curve, given a place it is allowed to break.
					var was: int = spline.sharpness(hit)
					spline.sharpen(hit, 0 if was > 0 else BSpline.DEGREE)
					_rebind()
					_refresh()
				return
			_insert_between(w)
		Mode.BONE:
			if not on_ink(w):
				_tell(UiKit.label_for("A bone starts on the drawing",
					"العظم يبدأ على الرسم"))
				return
			_bone_from = w
			_bone_drawing = true
		Mode.POSE:
			# One tap, one grab. The second tap used to mean something — it
			# switched the joint between a right-angle stop and a free turn —
			# and both the stop and the tap that reached it are gone. A joint
			# that can only point four ways is not a joint, and a gesture that
			# silently changes how the next drag will behave is worse than the
			# feature it reached.
			var found: Array = BoneRig.joint_at(bones, w, reach)
			if found.is_empty():
				return
			_grab_bone = int(found[0])
			_grab_end = int(found[1])

func _drag(screen: Vector2) -> void:
	var w: Vector2 = to_page(screen)
	if mode == Mode.MOVE and _grab >= 0:
		_move_grabbed(w)
		_pose()
		_refresh()
	elif mode == Mode.BONE and _bone_drawing:
		_refresh()
	elif mode == Mode.POSE and _grab_bone >= 0:
		# Dragging the far end of a bone that hangs from another is a reach:
		# the hand goes where the finger goes and the elbow works itself out.
		# Anything else is a swing, exactly as before. Nothing was taken away
		# to add this — a lone bone, or the near end of any bone, behaves
		# precisely as it did, so a rig built before this exists still poses
		# the way its author expects.
		# A rehearsal, recorded as one. See `_rehearsing`.
		_rehearsing = true
		var reached: bool = false
		if _grab_end == 1 \
				and (bones[_grab_bone] as BoneRig.Bone).parent >= 0:
			reached = BoneRig.reach(bones, _grab_bone, w)
		if not reached:
			BoneRig.swing(bones, _grab_bone, _grab_end, w)
		_pose()
		_refresh()

## Moving the point under the finger, and nothing else.
##
## ## What was wrong with `spline.move_point`
##
## Two separate things, and they compound into the stutter.
##
## **The curve does not reach the finger.** A B-spline is pulled towards its
## control points and never through them: at the strongest, a cubic's basis is
## about two thirds. So putting the control point where the finger is moves
## the curve only two thirds of the way there. The hand keeps going, the curve
## keeps lagging, and the correction is applied again every frame — which is
## exactly what "the movement is still bad" describes. It is not roughness in
## the sampling; it is the curve chasing something it is built never to catch.
##
## **The correction lands on whichever point was grabbed**, which need not be
## the one that governs the place under the finger. When it is not, most of
## the movement goes somewhere the person is not looking, and the shape near
## their finger barely moves while a neighbouring bend swings — read, fairly,
## as "it drags other points with it".
##
## ## What happens instead
##
## The place under the finger is found on the curve, and `IvorySpline` solves
## for the one control point that puts the curve **exactly** there:
##
##     dP_i = (target − S(t)) / N_i(t)
##
## Exactly, first time. Nothing to chase, so nothing to stutter. And the
## chosen point is the one with the largest basis value at that parameter, so
## the correction is the smallest possible — and because a cubic control
## point's basis is *identically zero* outside four knot spans, the curve
## everywhere else is not merely close to unchanged, it is the same number.
##
## Which is the whole of "it must move that circle and pull nothing else".
##
## The fallback is the old behaviour. It is worse, and it is better than a
## tool that does nothing on a build without the extension.
func _move_grabbed(w: Vector2) -> void:
	var fast: Object = _native_spline()
	if fast == null:
		spline.move_point(_grab, w)
		return
	fast.set_points(spline.points)
	# From the point being dragged, not from the finger. The finger may have
	# run ahead of the curve, and asking for the nearest place to *it* would
	# hand the drag to a different part of the curve mid-gesture — which is
	# the stutter, wearing a different hat.
	if _grab_u < 0.0:
		_grab_u = fast.nearest_u(_posed_point(_grab))
	fast.pull_at(_grab_u, w, 0)
	spline.points = fast.points()

## The native solver, made once per room and kept.
##
## Once, because `set_points` on it is cheap and making one per frame is not:
## a drag is sixty of these a second and each one would be an allocation and a
## registration lookup.
var _fast_spline: Object = null
## The parameter the drag took hold of, kept for the length of the gesture so
## that the same part of the curve answers the whole way through.
var _grab_u: float = -1.0

func _native_spline() -> Object:
	if _fast_spline == null:
		_fast_spline = Native.spline()
	return _fast_spline

func _release(screen: Vector2) -> void:
	var w: Vector2 = to_page(screen)
	if mode == Mode.BONE and _bone_drawing:
		_bone_drawing = false
		if bone_fits(_bone_from, w):
			var b: BoneRig.Bone = BoneRig.Bone.new()
			b.rest_a = _bone_from
			b.rest_b = w
			b.parent = BoneRig.parent_for(bones, _bone_from,
				BoneRig.join_reach(maxf(float(page.size.x),
					float(page.size.y))))
			b.rest()
			bones.append(b)
			BoneRig.solve(bones)
			_bind_bones()
			_tell(UiKit.label_for("Bone laid", "وُضع العظم"))
		else:
			_tell(UiKit.label_for(
				"That bone would leave the drawing — nothing laid",
				"هذا العظم يخرج عن الرسم — لم يُوضع شيء"))
		_refresh()
	var settled: bool = _grab >= 0
	_grab = -1
	_grab_u = -1.0
	_grab_bone = -1
	if settled:
		# Settled. Walk the curve at full precision now and pose from that,
		# so what is left on screen is the accurate shape rather than the
		# coarse one the drag was running on.
		_measure_arc()
		_pose()
		_refresh()

func _point_at(w: Vector2, reach: float) -> int:
	var best: int = -1
	var best_d: float = reach * reach
	for i in spline.size():
		var d: float = w.distance_squared_to(_posed_point(i))
		if d <= best_d:
			best_d = d
			best = i
	return best

func _posed_point(i: int) -> Vector2:
	return spline.points[i]

## Finding a joint, swinging one, reaching with a chain — all of it now lives
## in `bone_rig.gd`, and this room calls it rather than keeping a second copy.
##
## What went out with the copy: `_swing`, `_carry_children`, `_reach_to`,
## `_elbow_side`, `_join_reach` and `_joint_at`. Roughly a hundred and eighty
## lines, every one of which had a twin elsewhere that was already a little
## different.
##
## And `_carry_children` was not merely duplicated, it was **wrong**. It moved
## a child bone by however far its parent's tip had travelled — it *shifted*
## it. A shift is not a rotation. Swing an upper arm ninety degrees and the
## forearm arrived at the elbow still pointing the way it was drawn, sticking
## out of the arm sideways with the flesh nowhere near it. That is exactly the
## complaint that the bones do not stay inside the drawing, and it was true.
## `BoneRig.solve` carries rotation down the chain, which is what a skeleton
## does.

## Writes the gathered skeleton back to the layers it came from.
##
## This is what makes an animation folder a folder rather than a view of one.
## Bones were read out of every member on the way in and written back to only
## the layer that happened to be active on the way out — so a shoulder
## corrected across a two-layer figure was kept on one layer and silently
## lost on the other, and reopening the folder brought back the old bone with
## no sign that anything had been discarded.
##
## Each bone goes home to the member it came from. The order is the order
## they were gathered in, which is the order the members were walked in, so
## the two lists line up by construction rather than by matching positions
## back up afterwards — which would guess wrong the moment two bones sat on
## top of each other.
func _return_bones_to_members() -> void:
	if gather_group < 0 or _members.is_empty():
		return
	var at: int = 0
	for m in _members:
		var member: LayerStack.Layer = m
		var count: int = int((member.rig.get("bones", []) as Array).size())
		var mine: Array = bones.slice(at, mini(at + count, bones.size()))
		at += mine.size()
		if mine.is_empty():
			continue
		var rows: Array = BoneRig.to_rows(mine)
		var doc: Dictionary = member.rig.duplicate(true)
		doc["bones"] = rows
		member.rig = doc

func _rest_pose() -> void:
	BoneRig.rest_all(bones)
	_pose()
	_refresh()

## A new point is put where the curve already runs, between the two points it
## falls between — so adding one never changes the shape, it only gives the
## shape somewhere else to be held.
func _insert_between(w: Vector2) -> void:
	if spline.size() < 2:
		if on_ink(w):
			spline.add_point(w)
			_rebind()
			_refresh()
		return
	var best: int = 1
	var best_d: float = INF
	for i in range(1, spline.size()):
		var mid: Vector2 = (spline.points[i - 1] + spline.points[i]) * 0.5
		var d: float = w.distance_squared_to(mid)
		if d < best_d:
			best_d = d
			best = i
	var at: Vector2 = (spline.points[best - 1] + spline.points[best]) * 0.5
	spline.insert_point(best, at)
	_rebind()
	_refresh()

# ------------------------------------------------------------ curve binding

# ------------------------------------------------------------- the mesh

## A mesh over the ink, and nowhere else.
##
## Empty cells are dropped for the same reason they are dropped in the warp
## room: they cost the same to move as drawn ones and carry nothing, and they
## bridge gaps that the drawing does not — which is what lets one limb drag
## another it is not joined to.
func _build_mesh(density: int = 40) -> void:
	var span: Vector2 = Vector2(_ink_rect.size)
	var longest: float = maxf(span.x, span.y)
	_cols = clampi(int(round(density * span.x / longest)), 2, 96) + 1
	_rows = clampi(int(round(density * span.y / longest)), 2, 96) + 1
	_cell = Vector2(span.x / float(_cols - 1), span.y / float(_rows - 1))

	var cx_n: int = _cols - 1
	var cy_n: int = _rows - 1
	var probe: Image = art.duplicate()
	if cx_n < 1 or cy_n < 1 or probe.get_width() < 1 or probe.get_height() < 1:
		# A resize to nothing is a hard crash, and a drawing this small has
		# no rig worth building. Leaving the mesh empty is the honest answer.
		_rest = PackedVector2Array()
		_now = PackedVector2Array()
		_tris = PackedInt32Array()
		return
	probe.resize(cx_n, cy_n, Image.INTERPOLATE_BILINEAR)

	var live: PackedByteArray = PackedByteArray()
	live.resize(cx_n * cy_n)
	var any: bool = false
	for y in cy_n:
		for x in cx_n:
			var on: bool = probe.get_pixel(x, y).a > 0.004
			live[y * cx_n + x] = 1 if on else 0
			any = any or on
	# Which separate piece of drawing every cell belongs to, worked out here
	# and **before the grow below**. That order is the whole point: the grow
	# fattens the ink by a cell so the mesh has something to hold on to, and
	# two strokes a cell apart would be fused by it into one piece. Labelling
	# the ink as it was actually drawn keeps them two. See `_label_pieces`.
	_label_pieces(live, cx_n, cy_n)
	if not any:
		live.fill(1)
	else:
		var grown: PackedByteArray = live.duplicate()
		for y in cy_n:
			for x in cx_n:
				if live[y * cx_n + x] != 0:
					continue
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx: int = x + dx
						var ny: int = y + dy
						if nx < 0 or ny < 0 or nx >= cx_n or ny >= cy_n:
							continue
						if live[ny * cx_n + nx] != 0:
							grown[y * cx_n + x] = 1
		live = grown

	_slot = PackedInt32Array()
	_slot.resize(_cols * _rows)
	_slot.fill(-1)
	_rest = PackedVector2Array()
	_uv = PackedVector2Array()
	_home = PackedInt32Array()
	var origin: Vector2 = Vector2(_ink_rect.position)

	var claim: Callable = func(x: int, y: int) -> int:
		var at: int = y * _cols + x
		if _slot[at] >= 0:
			return _slot[at]
		var fx: float = float(x) / float(_cols - 1)
		var fy: float = float(y) / float(_rows - 1)
		_rest.append(origin + Vector2(fx * span.x, fy * span.y))
		_uv.append(Vector2(fx, fy))
		_home.append(at)
		_slot[at] = _rest.size() - 1
		return _slot[at]

	_tris = PackedInt32Array()
	for cy in cy_n:
		for cx in cx_n:
			if live[cy * cx_n + cx] == 0:
				continue
			var a: int = claim.call(cx, cy)
			var b: int = claim.call(cx + 1, cy)
			var c: int = claim.call(cx, cy + 1)
			var d: int = claim.call(cx + 1, cy + 1)
			if (cx + cy) % 2 == 0:
				_tris.append_array([a, b, c])
				_tris.append_array([b, d, c])
			else:
				_tris.append_array([a, b, d])
				_tris.append_array([a, d, c])
	_now = _rest.duplicate()
	_push_mesh()

## Rebuilds the drawable mesh from the posed vertices.
##
## Never called from a drag directly — `_pose` only raises a flag, and this
## runs at most once per frame from `_process`. Building an `ArrayMesh` is not
## free, and a finger reports two to four times faster than the screen redraws,
## so calling it per event threw most of the work away before anyone saw it.
func _push_mesh() -> void:
	if _now.is_empty() or _tris.is_empty() or _uv.size() != _now.size():
		_bent = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _now
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _tris
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_bent = mesh

# ---------------------------------------------------------- curve binding

## Where every part of the drawing sits *relative to the curve*, worked out
## once against the rest shape.
##
## Each vertex is written down as how far along the curve it lies and how far
## off to the side, measured in the curve's own frame at that spot. This is
## what makes the room move a drawing rather than distort one: the
## along-measure is never touched when the curve bends, so nothing stretches
## or compresses along its length. Only the frame turns, and the ink turns
## with it. A limb bent here comes out the same limb, the same length, the
## same thickness — bent.
func _bind_curve() -> void:
	var count: int = _rest.size()
	_curve_s = PackedFloat32Array()
	_curve_t = PackedFloat32Array()
	_curve_n = PackedFloat32Array()
	_curve_pull = PackedFloat32Array()
	_curve_at = PackedInt32Array()
	_curve_mix = PackedFloat32Array()
	_curve_off0 = PackedFloat32Array()
	_curve_off1 = PackedFloat32Array()
	_curve_s.resize(count)
	_curve_t.resize(count)
	_curve_n.resize(count)
	_curve_pull.resize(count)
	_curve_at.resize(count)
	_curve_mix.resize(count)
	_curve_off0.resize(count)
	_curve_off1.resize(count)
	_curve_at.fill(-1)
	if spline == null or not spline.ready() or count == 0:
		return

	# How far the curve's authority reaches. Anything much further off than
	# the drawing is wide has nothing to do with this curve, and is left
	# alone rather than dragged along by a spine it does not belong to.
	var span: float = maxf(_ink_rect.size.x, _ink_rect.size.y) * 0.55
	_measure_arc()
	# Which piece of drawing the curve itself lies on. The same strict rule as
	# the bones: a spine laid down one stroke governs that stroke, and a second
	# stroke beside it is not its business however close it runs.
	var curve_piece: int = -1
	if spline.points.size() >= 2:
		var tally: Dictionary = {}
		for k in 13:
			var at: int = _piece_at(_at_length(arc_length()
				* float(k) / 12.0)[0])
			if at >= 0:
				tally[at] = int(tally.get(at, 0)) + 1
		var most: int = 0
		for key in tally.keys():
			if int(tally[key]) > most:
				most = int(tally[key])
				curve_piece = int(key)

	_rest_anchor_s = _anchor_s.duplicate()
	for i in count:
		var mine: int = _piece_at(_rest[i])
		if curve_piece >= 0 and mine >= 0 and mine != curve_piece:
			# Another piece of drawing entirely. No pull, at any distance.
			_curve_pull[i] = 0.0
			continue
		var s_here: float = _nearest_length(_rest[i])
		var frame: Array = _at_length(s_here)
		var c: Vector2 = frame[0]
		var t: Vector2 = frame[1]
		var n: Vector2 = Vector2(-t.y, t.x)
		var off: Vector2 = _rest[i] - c
		_curve_s[i] = s_here
		_curve_t[i] = off.dot(t)
		_curve_n[i] = off.dot(n)
		_curve_pull[i] = clampf(1.0 - (off.length() / maxf(span, 1.0)), 0.0, 1.0)
		SplineAnchor.peg(i, s_here, _anchor_s, _curve_at, _curve_mix,
			_curve_off0, _curve_off1)

## Every vertex written in the frame of every bone near it.
##
## Standard skinning: a vertex is stored in each bone's own coordinates once,
## and put back through wherever that bone has moved to. Bones share a vertex
## by weight, so the ink around a joint is partly governed by each side of it
## and passes smoothly from one to the other instead of tearing along a line.
func _bind_bones() -> void:
	_skin = []
	if bones.is_empty() or _rest.is_empty():
		return
	# Which piece of drawing each bone was laid on, worked out once rather
	# than per vertex — there are a handful of bones and thousands of points.
	var bone_piece: PackedInt32Array = PackedInt32Array()
	bone_piece.resize(bones.size())
	for k in bones.size():
		var one: BoneRig.Bone = bones[k] as BoneRig.Bone
		bone_piece[k] = _piece_of_bone(one.rest_a, one.rest_b)

	for i in _rest.size():
		var rows: Array = []
		var total: float = 0.0
		# How much pull comes from bones this point is actually joined to by
		# drawing, as opposed to bones that merely happen to be near it.
		var clear_total: float = 0.0
		var mine: int = _piece_at(_rest[i])
		for k in bones.size():
			var b: BoneRig.Bone = bones[k] as BoneRig.Bone
			# **The strict rule.** A bone moves the piece of drawing it was
			# laid on and nothing else — not weakly, not at a distance, not at
			# all. Two strokes a hair apart and not touching are two pieces,
			# and a skeleton in one of them has no reach into the other
			# however close it lies. This is the one test that distance could
			# never express, and it is why the ink walk below is now only a
			# refinement rather than the thing holding the figure together.
			if bone_piece[k] >= 0 and mine >= 0 and bone_piece[k] != mine:
				continue
			var away: float = _away_from_segment(_rest[i], b.rest_a, b.rest_b)
			# How far this bone's say extends at all, and it is a hard edge.
			#
			# This is the fix for a knee that moved the shoulders. The old
			# weight was an inverse power of the distance, which never reaches
			# zero — every bone had *some* say over every vertex in the figure,
			# and the shares were then normalised. With two or three bones in
			# a limb that meant a vertex at the head, far from all of them,
			# splitting its pull forty-thirty-thirty between bones that should
			# have had no claim on it whatsoever. Bend one and the whole
			# drawing came with it.
			#
			# A bone reaches about as far as it is long, plus a hand's width
			# for the flesh around it. Past that it has no vote — not a small
			# one, none — so a point the skeleton does not reach stays exactly
			# where it was drawn.
			var span: float = maxf(b.rest_a.distance_to(b.rest_b), 1.0)
			var reach_b: float = span * 0.26 + 18.0
			if away >= reach_b:
				continue
			# A compact kernel rather than a decaying one: smooth in the
			# middle, exactly zero at the edge, and no discontinuity where it
			# meets it. `t⁴(4t+1)` is the standard shape for this and is the
			# reason a bend blends across a joint instead of creasing at it.
			var t_w: float = 1.0 - away / reach_b
			var w: float = t_w * t_w * t_w * t_w * (4.0 * t_w + 1.0)
			# ...and only if the two are actually joined by drawing. Straight
			# distance says a hand resting against a hip is part of the hip;
			# the paper between them says otherwise. Without this a bone in
			# one limb drags ink out of whatever limb happens to lie beside
			# it, which is the single worst thing a rig can do.
			var joined: bool = _ink_between(_rest[i], b.rest_a, b.rest_b)
			var frame: Transform2D = _bone_frame(b.rest_a, b.rest_b)
			rows.append({"bone": k, "w": w, "joined": joined,
				"local": frame.affine_inverse() * _rest[i]})
			total += w
			if joined:
				clear_total += w
		# Nothing the ink test would call joined — but something within reach.
		#
		# **This is what was tearing the figure apart.**
		#
		# The ink walk allows about a fifth of its length to be blank paper,
		# which is right for an outlined drawing and wrong for a drawn one.
		# The figure in the screenshot is a handful of strokes with air
		# between them, so a vertex a hand's width from a bone would fail the
		# walk while the vertex *beside* it passed. One froze exactly where it
		# was drawn, the other swung with the bone, and the mesh between them
		# was pulled to pieces. That is the shattering — not drift, a tear,
		# and it happens along whatever line the ink happened to break.
		#
		# The ink test is kept as a *preference* rather than a gate, because
		# the hard reach above now does the job it was really there for. Two
		# figures side by side are separated by far more than a bone's length
		# plus a hand, so the other drawing still cannot be touched — while a
		# gap inside one figure no longer freezes half of it.
		if clear_total <= 0.0:
			clear_total = total
			for row in rows:
				row["joined"] = true
		# Genuinely out of every bone's reach: no skeleton claims this point,
		# and it stays exactly where it was drawn. That is now a real
		# statement about distance rather than an accident of where a stroke
		# happened to stop.
		if total <= 0.0:
			_skin.append([])
			continue
		# Only the few bones with real say are kept. A bone across the figure
		# contributing a thousandth is noise that costs as much to apply as a
		# bone that matters.
		var kept: Array = []
		for row in rows:
			# Bones on another piece of drawing are dropped outright rather
			# than kept at a low weight. Shares are taken against the joined
			# bones alone, so a figure with a skeleton of its own is bound
			# exactly as firmly as it was before this rule existed.
			if not bool(row["joined"]):
				continue
			var share: float = float(row["w"]) / clear_total
			if share > 0.06:
				row["w"] = share
				kept.append(row)
		# Two bones at most, and the two strongest.
		#
		# A vertex belongs to a bone, or it sits at a joint and belongs to the
		# two that meet there. Nothing on a figure is genuinely governed by
		# three, and letting a third in is how a knee acquires a faint opinion
		# about the elbow — small per bend, and compounding over a pose. Two
		# is what a joint needs and it is where every skinning system settles.
		kept.sort_custom(func(x, y) -> bool:
			return float(x["w"]) > float(y["w"]))
		if kept.size() > 2:
			kept = kept.slice(0, 2)
		var again: float = 0.0
		for row in kept:
			again += float(row["w"])
		for row in kept:
			row["w"] = float(row["w"]) / maxf(again, 0.000001)
		_skin.append(kept)

# ------------------------------------------------------- pieces of drawing

## Which separate piece of drawing each cell of the grid belongs to.
##
## This is the strict rule: **a bone or a point may only ever move the piece of
## drawing it was placed on.** Two strokes side by side, a hair apart and not
## touching, are two pieces — and putting a skeleton in one of them must not
## move the other, no matter how close they lie.
##
## Distance cannot express that, and every attempt to make it try has failed in
## one of two ways. A generous rule carries the neighbouring stroke along. A
## strict one, measured per vertex, freezes half of the stroke it *is* meant to
## move wherever a gap happens to fall — which is the tearing.
##
## So the question is answered once, properly, and by connectivity rather than
## by distance. The ink is labelled into connected pieces, and then every blank
## cell is given the label of the piece nearest to it. A bone belongs to the
## piece under it; a vertex belongs to the piece nearest it; and a bone moves a
## vertex only when the two agree. Inside one piece there is nothing to tear,
## because every cell of it carries the same label whatever gaps run through
## it. Between two pieces there is no influence at all, at any distance.
var _piece: PackedInt32Array = PackedInt32Array()
var _piece_cols: int = 0
var _piece_rows: int = 0

func _label_pieces(live: PackedByteArray, cols: int, rows: int) -> void:
	_piece_cols = cols
	_piece_rows = rows
	_piece = PackedInt32Array()
	if cols < 1 or rows < 1:
		return
	_piece.resize(cols * rows)
	_piece.fill(-1)

	# Pass one: label the ink itself, eight ways, so a diagonal stroke is one
	# piece rather than a dotted line of them.
	var next_label: int = 0
	var queue: PackedInt32Array = PackedInt32Array()
	for start in cols * rows:
		if live[start] == 0 or _piece[start] != -1:
			continue
		_piece[start] = next_label
		queue.clear()
		queue.append(start)
		var head: int = 0
		while head < queue.size():
			var at: int = queue[head]
			head += 1
			@warning_ignore("integer_division")
			var ay: int = at / cols
			var ax: int = at % cols
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx: int = ax + dx
					var ny: int = ay + dy
					if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
						continue
					var n: int = ny * cols + nx
					if live[n] == 0 or _piece[n] != -1:
						continue
					_piece[n] = next_label
					queue.append(n)
		next_label += 1

	if next_label == 0:
		# No ink at all: one piece, so nothing is arbitrarily excluded.
		_piece.fill(0)
		return

	# Pass two: every blank cell takes the label of the piece nearest to it.
	#
	# A single breadth-first sweep out of all the ink at once, which reaches
	# each blank cell from whichever piece is closest — the boundary between
	# two strokes lands exactly halfway between them, where it belongs. It
	# also means no vertex is ever unlabelled, so nothing freezes for want of
	# an answer.
	queue.clear()
	for i in cols * rows:
		if _piece[i] != -1:
			queue.append(i)
	var head2: int = 0
	while head2 < queue.size():
		var at2: int = queue[head2]
		head2 += 1
		var mine: int = _piece[at2]
		@warning_ignore("integer_division")
		var ay2: int = at2 / cols
		var ax2: int = at2 % cols
		for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx2: int = ax2 + int(step[0])
			var ny2: int = ay2 + int(step[1])
			if nx2 < 0 or ny2 < 0 or nx2 >= cols or ny2 >= rows:
				continue
			var n2: int = ny2 * cols + nx2
			if _piece[n2] != -1:
				continue
			_piece[n2] = mine
			queue.append(n2)

## The piece of drawing at a place on the page, or -1 if there is no grid yet.
func _piece_at(w: Vector2) -> int:
	if _piece.is_empty() or _piece_cols < 1 or _piece_rows < 1:
		return -1
	var span: Vector2 = Vector2(_ink_rect.size)
	if span.x <= 0.0 or span.y <= 0.0:
		return -1
	var rel: Vector2 = (w - Vector2(_ink_rect.position)) / span
	var x: int = clampi(int(rel.x * float(_piece_cols)), 0, _piece_cols - 1)
	var y: int = clampi(int(rel.y * float(_piece_rows)), 0, _piece_rows - 1)
	return _piece[y * _piece_cols + x]

## Which piece a bone lies on: the one most of its length sits over.
##
## Sampled along it rather than read at its middle, because a bone laid across
## a joint may have its midpoint over blank paper. A majority is the honest
## answer and it is stable — nudging the bone a pixel cannot flip it.
func _piece_of_bone(a: Vector2, b: Vector2) -> int:
	var tally: Dictionary = {}
	for i in 9:
		var at: int = _piece_at(a.lerp(b, float(i) / 8.0))
		if at < 0:
			continue
		tally[at] = int(tally.get(at, 0)) + 1
	var best: int = -1
	var most: int = 0
	for key in tally.keys():
		if int(tally[key]) > most:
			most = int(tally[key])
			best = int(key)
	return best

## A bone's own coordinate system: along itself, and across itself.
static func _bone_frame(a: Vector2, b: Vector2) -> Transform2D:
	var dir: Vector2 = b - a
	if dir.length_squared() < 0.000001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	return Transform2D(dir, Vector2(-dir.y, dir.x), a)

## Whether there is a line of drawing from a place to the bone nearest it.
##
## Walked in a straight line to the closest point on the bone, checking for
## ink the whole way. A short run of blank is allowed, because an outlined
## drawing is mostly hollow and a stroke's inside is empty paper. A long run
## means the two are not the same piece of the figure.
func _ink_between(from: Vector2, a: Vector2, b: Vector2) -> bool:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	var t: float = 0.0 if len2 < 0.000001 \
		else clampf((from - a).dot(ab) / len2, 0.0, 1.0)
	var to: Vector2 = a + ab * t
	var span: float = from.distance_to(to)
	if span < 3.0:
		return true
	var steps: int = clampi(int(span / 4.0), 3, 64)
	var blank: int = 0
	@warning_ignore("integer_division")
	var fifth: int = floori(float(steps) / 5.0)
	var allow: int = maxi(fifth, 2)
	for i in steps + 1:
		if on_ink(from.lerp(to, float(i) / float(steps))):
			blank = 0
		else:
			blank += 1
			if blank > allow:
				return false
	return true

static func _away_from_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## The curve, walked and measured.
##
## Parameter and distance are not the same thing on a B-spline: it hurries
## through some spans and dawdles through others. Binding by parameter looks
## right until the control points are spread further apart, and then the
## drawing stretches along its own length — the exact thing this room exists
## not to do. So the curve is measured in real distance, and a vertex two
## hundred units along the rest curve is put two hundred units along the posed
## one. Bend it however hard you like: the limb keeps its length.
func _measure_arc() -> void:
	_arc_pts = PackedVector2Array()
	_arc_len = PackedFloat32Array()
	if spline == null or not spline.ready():
		return
	var steps: int = clampi(spline.size() * 40, 120, 900)
	var top: float = spline.span_max()
	var run: float = 0.0
	for i in steps + 1:
		var p: Vector2 = spline.at(top * float(i) / float(steps))
		if i > 0:
			run += p.distance_to(_arc_pts[i - 1])
		_arc_pts.append(p)
		_arc_len.append(run)
	_anchor_s = SplineAnchor.measure(spline, _arc_pts, _arc_len)

## The whole length of the curve as it currently stands.
func arc_length() -> float:
	if _arc_len.is_empty():
		return 0.0
	return _arc_len[_arc_len.size() - 1]

## The place and heading at a given distance along the curve. Found by
## bisection on the measured table, so it costs a handful of comparisons
## however finely the curve was walked.
func _at_length(s: float) -> Array:
	if _arc_pts.size() < 2:
		return [Vector2.ZERO, Vector2.RIGHT]
	var want: float = clampf(s, 0.0, arc_length())
	var lo: int = 0
	var hi: int = _arc_len.size() - 1
	while lo < hi - 1:
		@warning_ignore("integer_division")
		var mid: int = (lo + hi) >> 1
		if _arc_len[mid] <= want:
			lo = mid
		else:
			hi = mid
	var a: float = _arc_len[lo]
	var b: float = _arc_len[lo + 1]
	var f: float = 0.0 if b - a < 0.000001 else (want - a) / (b - a)
	var at: Vector2 = _arc_pts[lo].lerp(_arc_pts[lo + 1], f)
	var ahead: Vector2 = _arc_pts[mini(lo + 2, _arc_pts.size() - 1)]
	var behind: Vector2 = _arc_pts[maxi(lo - 1, 0)]
	var dir: Vector2 = ahead - behind
	if dir.length_squared() < 0.000000001:
		dir = Vector2.RIGHT

	# How sharply the curve turns here, and over what length.
	#
	# Handed back with the frame because the frame alone is not enough to
	# place a vertex safely: on the inside of a bend the normals converge, and
	# anything sitting further in than the centre of that bend comes out the
	# other side of it. See `SplineAnchor.fold_safe`.
	#
	# Measured as the angle between the two half-steps around this sample
	# rather than from a derivative. The curve is already a walked polyline,
	# and the turn between three consecutive points *is* its curvature —
	# exactly, and with nothing to be noisy about.
	var into: Vector2 = at - behind
	var out_of: Vector2 = ahead - at
	var turn: float = 0.0
	if into.length_squared() > 0.000001 and out_of.length_squared() > 0.000001:
		turn = wrapf(out_of.angle() - into.angle(), -PI, PI)
	var step: float = maxf(behind.distance_to(ahead) * 0.5, 0.001)
	return [at, dir.normalized(), turn, step]

## The distance along the curve of the point on it nearest a place.
##
## Coarse first, then fine. Binding calls this once for every vertex of the
## mesh against a curve walked into hundreds of samples — checking all of them
## every time is a couple of million distance tests and a visible freeze on a
## tablet the moment a point is added. Striding the first pass and then looking
## closely only around the winner cuts that by roughly ten times and lands on
## the same answer, because the curve is smooth: the nearest sample to a place
## is always beside the nearest point to it.
func _nearest_length(to: Vector2) -> float:
	var count: int = _arc_pts.size()
	if count == 0:
		return 0.0
	@warning_ignore("integer_division")
	var chunk: int = floori(float(count) / 48.0)
	var stride: int = maxi(chunk, 1)
	var best: int = 0
	var best_d: float = INF
	var i: int = 0
	while i < count:
		var d: float = _arc_pts[i].distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = i
		i += stride
	var lo: int = maxi(best - stride, 0)
	var hi: int = mini(best + stride, count - 1)
	for k in range(lo, hi + 1):
		var d2: float = _arc_pts[k].distance_squared_to(to)
		if d2 < best_d:
			best_d = d2
			best = k
	return _arc_len[best]

func _rebind() -> void:
	_bind_curve()
	_bind_bones()
	_pose()

# ---------------------------------------------------------------- posing

## Both rigs speak in displacements, and the displacements add.
##
## Each one says how far it would move a vertex from its rest place, and the
## two are summed. That way either rig used alone is exactly itself, and used
## together neither one overwrites the other — which is what happens if you
## pose one after the other and feed the second the first one's output.
## Where one point of the drawing goes, given the bones that hold it.
##
## ## Why not the obvious thing
##
## The obvious thing — and what this did — is to push the point through each
## bone's transform and average the answers by weight. It is called linear
## blend skinning and it has one famous failure, which is exactly the failure
## your reference sheets are drawn to correct.
##
## Average two *positions* and you get a point on the straight line between
## them. Bend an elbow ninety degrees and the two answers sit on either side of
## the joint; halfway between them is nearer the bone than either — so the arm
## does not bend, it **pinches**. The flesh at the joint collapses toward the
## axis and the limb narrows to a waist. Animators call it the candy wrapper.
## It is the opposite of the purple bands in your second sheet, where the flesh
## at a bend stays thick and the *shape* is what gives.
##
## ## What this does instead
##
## Average the **turn**, not the position.
##
## Each bone has turned by some angle from where it was drawn. Those angles are
## averaged as directions — the sum of their unit vectors, then the angle of
## that sum — which is the correct mean for angles and, crucially, is always a
## real rotation. A rotation cannot shorten anything. So a point a certain
## distance from the joint is that same distance from it after the bend,
## wherever between the two bones its weight falls.
##
## This is the two-dimensional form of what film rigs use dual quaternions for,
## and in two dimensions it is four lines of arithmetic rather than an algebra.
##
## ## And then the flesh
##
## A rigid turn alone gives your first sheet's **bone: hard, rigid**. The
## second half of both sheets is the other half of the truth: at a bend the
## outside of the limb stretches and the inside gathers. So the offset from the
## joint is split along the bone and across it, and the across part is opened
## on the outside of the turn and closed on the inside — by an amount
## proportional to how far the joint is bent, and fading out along the bone so
## a knee does not thicken a thigh.
##
## The inside gives by rather less than the outside opens. Flesh gathers before
## it folds, and matching them exactly would let the two sides of a hard bend
## cross through each other.
const FLESH: float = 0.45

func _skinned(here: Vector2, rows: Array) -> Vector2:
	var turn_x: float = 0.0
	var turn_y: float = 0.0
	var pivot: Vector2 = Vector2.ZERO
	var rest_pivot: Vector2 = Vector2.ZERO
	var weight: float = 0.0
	var lead: BoneRig.Bone = null
	var lead_w: float = -1.0
	var first_turn: float = 0.0
	var second_turn: float = 0.0
	var have: int = 0

	for row in rows:
		var b: BoneRig.Bone = bones[int(row["bone"])] as BoneRig.Bone
		var w: float = float(row["w"])
		var rest_dir: Vector2 = b.rest_b - b.rest_a
		var now_dir: Vector2 = b.b - b.a
		if rest_dir.length_squared() < 0.000001 or now_dir.length_squared() < 0.000001:
			continue
		var turned: float = now_dir.angle() - rest_dir.angle()
		# Summed as directions, so the mean of 170° and -170° is 180° and not
		# zero. Averaging the numbers themselves would snap a limb straight
		# every time a bend crossed the half turn.
		turn_x += cos(turned) * w
		turn_y += sin(turned) * w
		pivot += b.a * w
		rest_pivot += b.rest_a * w
		weight += w
		if have == 0:
			first_turn = turned
		elif have == 1:
			second_turn = turned
		have += 1
		if w > lead_w:
			lead_w = w
			lead = b

	if weight <= 0.0 or lead == null:
		return here
	pivot /= weight
	rest_pivot /= weight
	var angle: float = atan2(turn_y, turn_x)
	var off: Vector2 = (here - rest_pivot).rotated(angle)

	# How hard the joint under this point is bent. One bone is a limb, not a
	# joint, and has nothing to gather or stretch.
	if have >= 2:
		var bend: float = wrapf(first_turn - second_turn, -PI, PI)
		if absf(bend) > 0.02:
			var along_dir: Vector2 = (lead.b - lead.a).normalized()
			var across_dir: Vector2 = Vector2(-along_dir.y, along_dir.x)
			var along: float = off.dot(along_dir)
			var across: float = off.dot(across_dir)
			# Fading out along the bone: the flesh gives at the joint, and a
			# knee has no business thickening the middle of a thigh.
			var span: float = maxf(lead.a.distance_to(lead.b), 1.0)
			var near: float = clampf(1.0 - absf(along) / span, 0.0, 1.0)
			var amount: float = FLESH * (absf(bend) / PI) * near
			# The outside of a turn is the side away from the direction it
			# turns toward.
			if signf(across) == -signf(bend):
				across *= 1.0 + amount
			else:
				across *= 1.0 - amount * 0.6
			off = along_dir * along + across_dir * across
	return pivot + off

## Asks for a pose. Cheap on purpose — see `_pose_due`.
func _pose() -> void:
	_pose_due = true

func _process(_delta: float) -> void:
	if not _pose_due:
		return
	_settle_pose()
	_refresh()

## Applies a pending pose right now.
##
## Anything that *reads* the posed vertices rather than merely showing them —
## baking the figure, putting it down on the canvas — has to call this first.
## Deferring the work to the next frame is what makes dragging cheap, and it
## is also how a stale set of vertices would otherwise end up committed to the
## layer: the finger lifts, Apply is pressed, and the pose from one frame ago
## is what gets stamped.
func _settle_pose() -> void:
	if not _pose_due:
		return
	_pose_due = false
	_pose_now()

func _pose_now() -> void:
	if _rest.is_empty():
		return
	var use_curve: bool = spline != null and spline.ready() \
		and _curve_s.size() == _rest.size()
	if use_curve:
		# The curve has changed shape since the last pose, so the map from
		# distance-along to place-on-it has to be measured again.
		_measure_arc()
	var use_bones: bool = not _skin.is_empty()

	for i in _rest.size():
		var here: Vector2 = _rest[i]
		var shift: Vector2 = Vector2.ZERO

		if use_curve:
			var frame: Array = _at_length(SplineAnchor.where_now(i,
				_anchor_s, _curve_at, _curve_mix, _curve_off0,
				_curve_off1, _curve_s))
			var c: Vector2 = frame[0]
			var t: Vector2 = frame[1]
			var n: Vector2 = Vector2(-t.y, t.x)
			# Held short of the centre of the bend. Without this the inner
			# edge of a sharp curve turns inside out — the drawing's inner
			# line crossing its outer one and the whole bend pinching into a
			# knot, worst exactly where somebody has bent hardest.
			var off_n: float = SplineAnchor.fold_safe(_curve_n[i],
				float(frame[2]), float(frame[3]))
			var landed: Vector2 = c + t * _curve_t[i] + n * off_n
			shift += (landed - here) * _curve_pull[i]

		if use_bones and i < _skin.size():
			var rows: Array = _skin[i]
			if not rows.is_empty():
				shift += _skinned(here, rows) - here

		_now[i] = here + shift
	_push_mesh()

# ------------------------------------------------------------------- apply

## Puts the posed drawing back on the canvas.
##
## The rig is not thrown away. The bones stay on the layer with the pose they
## were left in, so coming back into this room finds the figure standing where
## it was rather than flat again — which is the difference between a tool you
## pose with and a tool you use once.
## Puts the bones back where they were drawn.
##
## Silent when nothing was rehearsed, so it costs nothing in the ordinary
## case. Called before the drawing is committed, and again on the way out —
## leaving by the Exit button must be as safe as leaving by Apply.
func _end_rehearsal() -> void:
	# The skeleton goes home even when nothing was rehearsed — it may have
	# been corrected rather than swung, and a correction is the thing most
	# worth keeping.
	_return_bones_to_members()
	if not _rehearsing:
		return
	_rehearsing = false
	BoneRig.rest_all(bones)
	_pose()
	_refresh()

## Puts the posed drawing back on the canvas.
##
## Every way out of this now says which way it took.
##
## It used to return silently from three separate places — an empty mesh, a
## missing view, a layer that could no longer be found — and the button
## therefore did nothing at all, with nothing on screen to say why or even
## that anything had been tried. "It never works" is the only conclusion
## available to someone standing in front of that, and it is a fair one.
##
## Each of these is a real condition with a real cause the user can act on, so
## each one now names itself.
func _apply() -> void:
	_end_rehearsal()
	# Whatever the last drag asked for, before anything is read.
	_settle_pose()
	if view == null:
		_tell(UiKit.label_for("The canvas is not open", "اللوحة ليست مفتوحة"))
		return
	if _now.is_empty():
		# The mesh is built from the ink itself, so an empty one means there
		# was nothing under the rig to carry — an empty layer, or a drawing
		# too small to divide into cells.
		_tell(UiKit.label_for(
			"There is no artwork here to put down. Draw on this layer first.",
			"لا يوجد رسم هنا ليوضع. ارسم على هذه الطبقة أولاً."))
		return
	var baked: Dictionary = await _bake()
	if baked.is_empty():
		_tell(UiKit.label_for("Nothing to put down", "لا شيء ليوضع"))
		return
	# The rig as it stands, before this apply overwrites it.
	#
	# `stamp_region` below already puts the *pixels* on the undo stack. The
	# skeleton written a few lines down was not on it at all, so undoing an
	# apply gave back the old drawing and kept the new bones — half the change
	# reversed and half of it not, which is worse than either.
	var before: Array = view.layers.snapshot_state()
	view.layers.record_state(UiKit.label_for("B-Spline rig", "هيكل بي-سبلاين"),
		before)

	var surface: PaintSurface = null
	for l in view.layers.layers:
		if l.id == layer_id:
			surface = l.surface
			# Apply is the moment the rig becomes attached to the character. Rebuild
			# the hierarchy from the finished artwork and weld accepted joints exactly
			# tip-to-root before serialising, so no near-miss survives as a floating
			# bone in the canvas.
			BoneRig.stabilize_attachment(bones, maxf(float(_ink_rect.size.x), float(_ink_rect.size.y)))
			l.rig = save_rig()
			# Kept apart from `rig` in memory and never written to disk: it
			# is derived from the same bones, and derived state in a file is
			# state that can come to disagree with what it came from.
			l.rig["bones_rest"] = rest_skeleton()
			break
	if surface == null:
		_tell(UiKit.label_for(
			"The layer this rig belongs to is gone. Leave and open it again.",
			"الطبقة التي يخصّها هذا الهيكل لم تعد موجودة. اخرج وافتحها ثانية."))
		return

	var box: Rect2i = baked["rect"]
	view.stamp_region(layer_id, box, _ink_rect,
		baked["image"] as Image, baked["at"] as Vector2i,
		UiKit.label_for("B-Spline", "بي-سبلاين"))

	# The pose that was just put down becomes the new rest. Everything is
	# measured again from it — the rig is re-bound to where the drawing is
	# now, not to where it used to be — so the next pose starts from this one
	# instead of springing back to the first.
	_ink_rect = box.intersection(Rect2i(page.position - page.size,
		page.size * 3))
	surface.flush()
	var fresh: Image = surface.read_region(_ink_rect)
	if fresh != null:
		var used: Rect2i = fresh.get_used_rect()
		if used.size.x >= 2 and used.size.y >= 2:
			if used.position != Vector2i.ZERO or used.size != _ink_rect.size:
				var trim: Image = Image.create_empty(used.size.x, used.size.y,
					false, Image.FORMAT_RGBA8)
				trim.blit_rect(fresh, used, Vector2i.ZERO)
				fresh = trim
				_ink_rect = Rect2i(_ink_rect.position + used.position, used.size)
			art = fresh
			_art_tex = ImageTexture.create_from_image(art)
			# The texture is read straight off `_art_tex` at draw time now, so
			# there is nothing to hand it to. These two lines were the last
			# readers of the node that was never assigned; leaving them behind
			# when it was removed is what broke the parse.
			_build_mesh()
			# The pose that was just stamped is where the drawing now is, so it
			# becomes the rest and every turn goes back to nought. Moving the
			# rest without clearing the turns would apply the same bend a
			# second time on the very next solve — the limb folding twice as
			# far as it was taken.
			for b in bones:
				var one: BoneRig.Bone = b as BoneRig.Bone
				one.rest_a = one.a
				one.rest_b = one.b
				one.rest()
			BoneRig.solve(bones)
			_rebind()
	applied.emit()
	_refresh()
	_tell(UiKit.label_for("Put down on the canvas", "وُضع على اللوحة"))

## The bent drawing, rendered once by the graphics card.
func _bake() -> Dictionary:
	if _now.is_empty() or _art_tex == null:
		return {}
	var lo: Vector2 = _now[0]
	var hi: Vector2 = _now[0]
	for v in _now:
		lo.x = minf(lo.x, v.x)
		lo.y = minf(lo.y, v.y)
		hi.x = maxf(hi.x, v.x)
		hi.y = maxf(hi.y, v.y)
	var pad: Vector2 = Vector2(2.0, 2.0)
	var box: Rect2i = Rect2i(Vector2i((lo - pad).floor()),
		Vector2i((hi - lo + pad * 2.0).ceil()))
	box.size.x = clampi(box.size.x, 1, 4096)
	box.size.y = clampi(box.size.y, 1, 4096)

	var shifted: PackedVector2Array = PackedVector2Array()
	shifted.resize(_now.size())
	var origin: Vector2 = Vector2(box.position)
	for i in _now.size():
		shifted[i] = _now[i] - origin

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = shifted
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _tris
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var port: SubViewport = SubViewport.new()
	port.size = box.size
	port.transparent_bg = true
	port.disable_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_ONCE
	port.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	port.msaa_2d = Viewport.MSAA_4X

	var flat: MeshInstance2D = MeshInstance2D.new()
	flat.mesh = mesh
	flat.texture = _art_tex
	flat.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	flat.material = PaintSurface.premultiplied_material()
	port.add_child(flat)
	add_child(port)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out: Image = port.get_texture().get_image()
	port.queue_free()
	if out == null:
		return {}
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	return {"image": out, "at": box.position, "rect": box}

# ------------------------------------------------------------------- rig

## The rig, written down so the layer can carry it between sessions.
# ------------------------------------------------------------ rig keys

## Writes the pose currently on screen into this layer's own timeline.
##
## Note what is *not* here: no new layer, no new frame, no copy of the
## drawing. A pose is a few dozen floats laid beside the drawing that already
## exists, which is the whole economy of rigged animation — a hundred poses
## cost less than one extra drawn frame, and that is why a rig can be keyed
## on every frame on a tablet where hand-drawing cannot.
func record_key(frame: int) -> RigTrack.RigKey:
	if view == null or view.layers == null:
		return null
	var l: LayerStack.Layer = view.layers.by_id(layer_id)
	if l == null:
		return null
	if l.poses == null:
		l.poses = RigTrack.new()
	RigTrack.take_bones(l.poses, frame, bones)
	if view.puppet != null and not view.puppet.pins.is_empty():
		RigTrack.take_pins(l.poses, frame, view.puppet.pins)
	return l.poses.key_at(frame)

## Puts a pose from the timeline back on the bones and re-skins.
##
## The far end of each bone is rebuilt from its own rest length rather than
## read from the key, so a bone is exactly as long here as it was drawn —
## see the note at the head of `rig_track.gd` for why storing both ends
## would have made limbs shrink by half mid-swing.
func take_pose(pose: Dictionary) -> void:
	if pose.is_empty() or bones.is_empty():
		return
	if not pose.has("bones"):
		return
	RigTrack.lay_bones(bones, pose["bones"])
	# A key holds each bone as a pivot and an angle, which is where the bone
	# ends up and not how far it has turned. The turns are read back off those
	# ends so that the next drag continues from this pose rather than from the
	# one the bones were last solved into.
	BoneRig.adopt(bones)
	_pose()
	_refresh()

## The pose this layer holds at a frame, if it holds one.
func pose_at(frame: float) -> Dictionary:
	if view == null or view.layers == null:
		return {}
	var l: LayerStack.Layer = view.layers.by_id(layer_id)
	if l == null or l.poses == null:
		return {}
	return l.poses.pose_at(frame)

## The bones as they were drawn, in the form the canvas skin needs.
##
## `save_rig` already keeps the skeleton for this room to reopen with. This is
## the same skeleton said a second way — two flat arrays of endpoints and the
## lengths — because the skin is asked to weight a thousand points against
## every bone on every frame, and unpacking a nested dictionary a thousand
## times a frame to find four numbers is work nobody needs done.
func rest_skeleton() -> Dictionary:
	return BoneRig.rest_skeleton(bones)

func save_rig() -> Dictionary:
	var pts: Array = []
	for p in spline.points:
		pts.append([p.x, p.y])
	var sharps: Array = []
	for i in spline.sharp.size():
		sharps.append(spline.sharp[i])
	return {"points": pts, "sharp": sharps, "bones": BoneRig.to_rows(bones)}

func load_rig(doc: Dictionary) -> void:
	if doc.is_empty():
		return
	spline.clear()
	for row in doc.get("points", []):
		spline.add_point(Vector2(float(row[0]), float(row[1])))
	var sharps: Array = doc.get("sharp", [])
	for i in mini(sharps.size(), spline.sharp.size()):
		spline.sharp[i] = int(sharps[i])
	spline.rebuild_knots()

	bones = BoneRig.from_rows(doc.get("bones", []))
	_rebind()
	_refresh()

# -------------------------------------------------------------------- draw

func _refresh() -> void:
	if _board != null:
		_board.queue_redraw()

func _draw_board() -> void:
	_draw_grid()
	_draw_art()
	_draw_frame()
	_draw_curve()
	_draw_bones()

func _draw_grid() -> void:
	BSplineRoomDraw.draw_grid(self)

func _draw_art() -> void:
	BSplineRoomDraw.draw_art(self)

func _draw_frame() -> void:
	BSplineRoomDraw.draw_frame(self)

func _draw_curve() -> void:
	return

func _draw_curve_legacy() -> void:
	BSplineRoomDraw.draw_curve_legacy(self)

func _draw_bones() -> void:
	BSplineRoomDraw.draw_bones(self)

func _draw_joints() -> void:
	BSplineRoomDraw.draw_joints(self)

func _draw_spindle(a: Vector2, b: Vector2) -> void:
	BSplineRoomDraw.draw_spindle(self, a, b)

func _draw_joint(at: Vector2) -> void:
	BSplineRoomDraw.draw_joint(self, at)
