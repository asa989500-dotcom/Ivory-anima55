class_name BoneRoom
extends Control
## The layer, on its own, with nothing to do but take bones.
##
## ## Why this room exists at all
##
## Bones used to be reached through the B-Spline room, and the B-Spline room
## is a place you go to do four other things: add curve points, move them,
## connect them, and pose. Bones were the fourth button along a row of five,
## and a person who wanted to put a skeleton on a drawing had to know that the
## way to a bone ran through a curve tool they had no interest in.
##
## That is the wrong shape. A skeleton belongs to a **layer** — it is a fact
## about that drawing, in that drawing's own coordinates, and it is useless
## anywhere else. So it is reached from the layer: tap the layer you want to
## move, tap *Add bone*, and the layer opens here by itself with the rest of
## the application put away. Lay the skeleton. Tap *Accept*. The bones are
## merged into the drawing and the room closes.
##
## After that the figure is posed **on the canvas**, by dragging the joints —
## not in here. See `bone_handle.gd`. This room lays a skeleton and does not
## animate; that separation is the whole reason it can be this small.
##
## ## Character 360 extension
##
## A Character 360 layer also gets the native high-level controller: IK/FK,
## five pin types, angular/spring/look-at constraints, paintable weights and
## independent FFD. This room still only edits the skeleton; the controller
## math is shared with the canvas so the same rig cannot acquire two different
## meanings depending on which room touched it.

## The rig was accepted and written to the layer.
signal accepted(layer_index: int)
## Left without accepting. Nothing was written.
signal closed()

const ICON: String = "res://assets/icons/%s.png"

## The same range the other rig rooms use, and for the same reason: a bone is
## placed at the scale of the *joint*, not of the figure.
const MIN_ZOOM: float = 0.02
const MAX_ZOOM: float = 64.0
## How near a finger must be to catch a joint, in screen pixels — a little
## under half a centimetre, about a fingertip's contact patch.
const GRAB_PX: float = 20.0

const FIELD: Color = Color("#23303A")
const GRID_INK: Color = Color(0.72, 0.86, 0.92, 0.16)
const GRID_BOLD: Color = Color(0.80, 0.92, 0.97, 0.30)
const GOLD: Color = Color("#D9B45B")
const IVORY: Color = Color("#FFF8E7")
const BONE_INK: Color = Color("#E8D5A3")
const JOINT_EDGE: Color = Color("#8A7C58")
const REFUSED: Color = Color(0.85, 0.35, 0.30, 0.92)

enum Mode { ADD, MOVE, DROP, LOOSE }

## The tint a loose bone is drawn in — the one thing here that is not ivory,
## because "this bone is hair" has to be readable across a whole skeleton at a
## glance and a shade of the same colour would not be.
const LOOSE_INK: Color = Color("#7FC9E8")
## How much a bone marked loose trails behind the pose.
##
## Three quarters rather than all of it. A strand that follows the movement
## completely is a strand that never arrives — it lags for ever, and hair that
## never settles reads as a mistake rather than as weight. This is the value
## every soft-body rig in a 2-D package lands near, and it can be shaded per
## bone later without changing a thing here: `BoneRig.Bone.soft` is a float
## and only this line assumes it is one of two.
const LOOSE_AMOUNT: float = 0.75

# --- what came in ---
var view: CanvasView = null
var layer_index: int = -1
var layer_id: int = -1
var page: Rect2i = Rect2i()

var art: Image = null
var _art_tex: ImageTexture = null
var _ink: Rect2i = Rect2i()

## The skeleton being laid. `BoneRig.Bone`, like every skeleton in the app.
var bones: Array = []

# --- what the hand is doing ---
var mode: int = Mode.ADD
var _from: Vector2 = Vector2.ZERO
var _drawing: bool = false
var _grab: Array = []

# --- the window onto the page ---
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _framed: bool = false
var _touches: Dictionary = {}
var _pinch_span: float = 0.0
var _pinch_zoom: float = 1.0
var _pinch_mid: Vector2 = Vector2.ZERO

var _board: Control = null
var _bar: PanelContainer = null
var _leave: Button = null
var _say: Label = null
var _count: Label = null
var _buttons: Dictionary = {}

# ------------------------------------------------------------------ set up

## Reads the layer and builds the room. False when there is nothing here worth
## boning — an empty layer, or a drawing too small to hold a skeleton.
##
## The picture is trimmed to its own ink before anything else happens.
## `content_bounds` answers in whole tiles, so a small figure in the corner of
## a large page comes back inside a great deal of nothing, and a bone dropped
## out in that nothing would be a bone holding blank paper.
func setup(canvas: CanvasView, index: int) -> bool:
	view = canvas
	if view == null or view.layers == null or view.projects.active == null:
		return false
	if index < 0 or index >= view.layers.layers.size():
		return false
	var l: LayerStack.Layer = view.layers.layers[index]
	if l == null or l.surface == null:
		return false
	l.surface.flush()
	page = Rect2i(Vector2i.ZERO, Vector2i(view.projects.active.page))
	_ink = l.surface.content_bounds().intersection(page)
	if _ink.size.x < 4 or _ink.size.y < 4:
		return false
	art = l.surface.read_region(_ink)
	if art == null:
		return false
	var used: Rect2i = art.get_used_rect()
	if used.size.x < 4 or used.size.y < 4:
		return false
	if used.position != Vector2i.ZERO or used.size != _ink.size:
		var trim: Image = Image.create_empty(used.size.x, used.size.y, false,
			Image.FORMAT_RGBA8)
		trim.blit_rect(art, used, Vector2i.ZERO)
		art = trim
		_ink = Rect2i(_ink.position + used.position, used.size)
	_art_tex = ImageTexture.create_from_image(art)
	_build_mask()
	layer_index = index
	layer_id = l.id

	# A layer that already has a skeleton opens with it, so this room is a
	# place to correct one as well as to lay one. Coming back and finding the
	# drawing bare would mean every correction started from nothing.
	bones = BoneRig.from_rows((l.rig as Dictionary).get("bones", []))
	_build_shell()
	return true

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var back: ColorRect = ColorRect.new()
	back.color = FIELD
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_board = Control.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.draw.connect(_draw_board)
	_board.gui_input.connect(_on_board_input)
	add_child(_board)

	_build_leave()
	_build_bar()
	resized.connect(func() -> void:
		_place_leave()
		_layout_bar()
		_frame_page())

## The way out, in gold, alone at the top of the room.
##
## Anchored top-left and then placed by hand: with the anchor on the right,
## `position` would be an offset from the right edge and the arithmetic below
## measures from the left. That mistake put the same button a full screen
## width past the corner in another room, where it was drawn entirely off the
## display.
func _build_leave() -> void:
	var out: Button = UiKit.make_tool_button(ICON % "exit",
		UiKit.label_for("Exit", "خروج"))
	out.toggle_mode = false
	out.text = UiKit.label_for("Exit", "خروج")
	out.custom_minimum_size = Vector2(UiKit.s(124.0), UiKit.s(58.0))
	var pill: StyleBoxFlat = StyleBoxFlat.new()
	pill.bg_color = Color(0.06, 0.16, 0.20, 0.96)
	pill.border_color = GOLD
	pill.set_border_width_all(int(maxf(UiKit.s(2.0), 2.0)))
	pill.set_corner_radius_all(int(UiKit.s(14.0)))
	pill.content_margin_left = UiKit.s(12.0)
	pill.content_margin_right = UiKit.s(12.0)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		out.add_theme_stylebox_override(state, pill)
	for state: String in ["icon_normal_color", "icon_hover_color",
			"icon_pressed_color", "font_color", "font_hover_color",
			"font_pressed_color"]:
		out.add_theme_color_override(state, GOLD)
	if UiKit.font != null:
		out.add_theme_font_override("font", UiKit.font)
	out.add_theme_font_size_override("font_size", int(UiKit.s(15.0)))
	out.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	out.pressed.connect(func() -> void: closed.emit())
	add_child(out)
	_leave = out
	_place_leave()

func _place_leave() -> void:
	if _leave == null or not is_instance_valid(_leave):
		return
	var wide: float = maxf(_leave.size.x, _leave.custom_minimum_size.x)
	_leave.position = Vector2(size.x - wide - UiKit.s(14.0), UiKit.s(14.0))

func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", UiKit.rail_style())
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(_bar)
	_bar.resized.connect(_layout_bar)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	_bar.add_child(col)

	_say = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.custom_minimum_size = Vector2(UiKit.s(320.0), 0.0)
	col.add_child(_say)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	col.add_child(row)
	_mode_button(row, Mode.ADD, UiKit.label_for("Add bone", "أضف عظماً"))
	_mode_button(row, Mode.MOVE, UiKit.label_for("Move a joint",
		"حرّك مفصلاً"))
	_mode_button(row, Mode.DROP, UiKit.label_for("Remove a bone",
		"احذف عظماً"))
	_mode_button(row, Mode.LOOSE, UiKit.label_for("Loose", "سائب"))

	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", int(UiKit.s(5.0)))
	col.add_child(row2)

	_count = UiKit.make_label("", 11.0, UiKit.TEXT_DIM)
	row2.add_child(_count)

	var wipe: Button = UiKit.make_text_button(
		UiKit.label_for("Clear", "امسح الكل"), true)
	wipe.pressed.connect(func() -> void:
		bones.clear()
		_grab = []
		_refresh())
	row2.add_child(wipe)

	var go: Button = UiKit.make_text_button(
		UiKit.label_for("Accept", "تطبيق"), true)
	go.pressed.connect(_accept)
	row2.add_child(go)

	_set_mode(Mode.ADD)

func _mode_button(row: HBoxContainer, which: int, label: String) -> void:
	var b: Button = UiKit.make_text_button(label, true)
	b.toggle_mode = true
	b.pressed.connect(func() -> void: _set_mode(which))
	_buttons[which] = b
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
	for key in _buttons.keys():
		(_buttons[key] as Button).set_pressed_no_signal(key == which)
	_grab = []
	_drawing = false
	match which:
		Mode.ADD:
			_tell(UiKit.label_for(
				"Drag inside the drawing to lay a bone. Start on the end of a bone already there to chain another onto it.",
				"اسحب داخل الرسم لتضع عظماً. ابدأ من طرف عظم موجود ليتصل به عظم جديد."))
		Mode.MOVE:
			_tell(UiKit.label_for(
				"Drag a joint to put it where it belongs. Bones meeting there move with it, so a chain stays a chain.",
				"اسحب مفصلاً لتضعه في مكانه الصحيح. والعظام الملتقية عنده تتحرك معه، فتبقى السلسلة سلسلة."))
		Mode.DROP:
			_tell(UiKit.label_for(
				"Tap a bone to take it off. Anything hanging from it is joined to what it hung from.",
				"اضغط عظماً لإزالته. وما كان معلّقاً به يتصل بما كان معلّقاً هو به."))
		Mode.LOOSE:
			_tell(UiKit.label_for(
				"Tap the bones that are hair, cloth or a tail. They are drawn in blue, and while the scene plays they arrive a moment after the rest of the figure instead of being welded to it. Tap again to make one rigid.",
				"اضغط العظام التي هي شعر أو قماش أو ذيل. تُرسم بالأزرق، وأثناء تشغيل المشهد تصل بعد بقية الشخصية بلحظة بدل أن تكون ملحومة بها. واضغط ثانية لتعيدها صلبة."))
	_refresh()

func _tell(text: String) -> void:
	if _say != null:
		_say.text = text

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_page()
	_place_leave()

## Sets the drawing in the middle of the screen, once, the first moment both
## it and the screen have a size.
##
## Nothing is awaited. `setup` runs while this room is still a loose object —
## it is only added to the tree if setup succeeds — and `get_tree()` on a node
## outside the tree is null, so awaiting a frame from in there is a crash
## rather than a wait. The room is told when it is given a size instead.
func _frame_page() -> void:
	if _framed:
		return
	var span: Vector2 = Vector2(_ink.size)
	if span.x <= 0.0 or span.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	_framed = true
	_zoom = minf(size.x / span.x, size.y / span.y) * 0.68
	_pan = size * 0.5 - (Vector2(_ink.position) + span * 0.5) * _zoom
	_refresh()

func to_screen(p: Vector2) -> Vector2:
	return p * _zoom + _pan

func to_page(p: Vector2) -> Vector2:
	return (p - _pan) / maxf(_zoom, 0.000001)

func _refresh() -> void:
	if _count != null:
		_count.text = UiKit.label_for("%d bones" % bones.size(),
			"%d عظمة" % bones.size())
	if _board != null:
		_board.queue_redraw()

# ------------------------------------------------------------ safety sensor

## Whether there is ink under a place on the page.
##
## The sensor the room leans on. A bone laid across empty air belongs to no
## limb, so it is refused rather than accepted and left to behave oddly later.
## --- the ink, as a coarse mask ---
##
## `on_ink` asks the image one pixel at a time, which is right for one
## question and wrong for the thousands that measuring a bone's girth asks.
## So the drawing is reduced once, on entry, to one byte per cell, and every
## measurement afterwards reads that.
##
## The cell is deliberately small — four pixels — because the thing being
## measured is how *thin* a limb is, and a coarse mask makes everything thin
## look the same width. Four pixels on a page is under a millimetre of a
## printed drawing and the mask costs a sixteenth of the image.
const MASK_CELL: int = 4

var _mask: PackedByteArray = PackedByteArray()
var _mask_cols: int = 0
var _mask_rows: int = 0

func _build_mask() -> void:
	_mask = PackedByteArray()
	_mask_cols = 0
	_mask_rows = 0
	if art == null:
		return
	var w: int = art.get_width()
	var h: int = art.get_height()
	_mask_cols = maxi(int(ceil(float(w) / float(MASK_CELL))), 1)
	_mask_rows = maxi(int(ceil(float(h) / float(MASK_CELL))), 1)
	_mask.resize(_mask_cols * _mask_rows)
	_mask.fill(0)
	# A cell counts as ink if *any* pixel in it is ink. The other way round —
	# requiring the cell to be mostly covered — loses every thin stroke, and a
	# thin stroke is exactly the case this exists to measure.
	for y in h:
		@warning_ignore("integer_division")
		var row: int = (y / MASK_CELL) * _mask_cols
		for x in w:
			if art.get_pixel(x, y).a > 0.02:
				@warning_ignore("integer_division")
				_mask[row + (x / MASK_CELL)] = 1

## How wide the drawing is across a bone, in page units.
##
## ## Why a bone should not be one fixed size
##
## Every bone was drawn the same width — a fraction of its own length, clamped
## between four and fifteen. So a bone down a forearm and a bone down a finger
## came out looking alike, and the one down the finger was wider than the
## finger. A skeleton whose bones are wider than the limbs they are in is a
## skeleton you cannot see the drawing through, and it is also a lie about
## what the bone will move.
##
## So the bone is sized from the artwork it was laid on: cast rays out from
## eleven stations along it, both ways, until the ink stops, and take the
## median half-width. The median rather than the mean because a limb usually
## overlaps the body at one end, and a mean would be dragged out to the width
## of the body by the two or three stations that see it.
##
## Returns nought when the line crosses no ink, and the caller falls back to
## the old length-based width.
func _girth_across(a: Vector2, b: Vector2) -> float:
	if _mask.is_empty():
		return 0.0
	var origin: Vector2 = Vector2(_ink.position)
	var cell: Vector2 = Vector2(float(MASK_CELL), float(MASK_CELL))
	if Native.has_bone():
		var solver: Object = Native.bones()
		if solver != null:
			return float(solver.span_across(_mask, _mask_cols, _mask_rows,
				origin, cell, a, b))
	return _girth_in_gdscript(a, b, origin, cell)

## The same measurement, for a build without the native library.
##
## Kept deliberately identical in method rather than approximated, so a bone
## laid on a machine without the extension is the same size as one laid with
## it — a rig that changes shape depending on how the app was built is not a
## rig anybody can share.
func _girth_in_gdscript(a: Vector2, b: Vector2, origin: Vector2,
		cell: Vector2) -> float:
	var run: Vector2 = b - a
	var span: float = run.length()
	if span < 0.001:
		return 0.0
	run = run / span
	var side: Vector2 = Vector2(-run.y, run.x)
	var step: float = maxf(minf(cell.x, cell.y), 0.5)
	var furthest: float = Vector2(float(_mask_cols) * cell.x,
		float(_mask_rows) * cell.y).length() * 0.5
	var widths: Array = []
	for station in 11:
		var t: float = float(station + 1) / 12.0
		var mid: Vector2 = a + run * (span * t)
		var total: float = 0.0
		for way in [1.0, -1.0]:
			var gone: float = 0.0
			var last: float = 0.0
			var gap: float = 0.0
			while gone <= furthest:
				var at: Vector2 = mid + side * (float(way) * gone)
				var cx: int = int(floor((at.x - origin.x) / cell.x))
				var cy: int = int(floor((at.y - origin.y) / cell.y))
				if cx < 0 or cy < 0 or cx >= _mask_cols or cy >= _mask_rows:
					break
				if _mask[cy * _mask_cols + cx] != 0:
					last = gone
					gap = 0.0
				else:
					gap += step
					if gap > step * 3.0:
						break
				gone += step
			total += last
		if total > 0.0:
			widths.append(total * 0.5)
	if widths.is_empty():
		return 0.0
	widths.sort()
	return float(widths[int(widths.size() / 2.0)])

func on_ink(at: Vector2) -> bool:
	if art == null or art.get_width() < 1 or art.get_height() < 1:
		return false
	var local: Vector2i = Vector2i((at - Vector2(_ink.position)).floor())
	if local.x < 0 or local.y < 0 \
			or local.x >= art.get_width() or local.y >= art.get_height():
		return false
	return art.get_pixel(local.x, local.y).a > 0.02

func fits(a: Vector2, b: Vector2) -> bool:
	return BoneRig.fits_on_ink(a, b, on_ink)

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
	_grab = []
	_drawing = false
	var keys: Array = _touches.keys()
	_pinch_span = (_touches[keys[0]] as Vector2).distance_to(_touches[keys[1]])
	_pinch_zoom = _zoom
	_pinch_mid = ((_touches[keys[0]] as Vector2)
		+ (_touches[keys[1]] as Vector2)) * 0.5

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
	_pinch_mid = mid
	_pan += mid - to_screen(anchor)
	_refresh()

func _zoom_at(screen: Vector2, by: float) -> void:
	var anchor: Vector2 = to_page(screen)
	_zoom = clampf(_zoom * by, MIN_ZOOM, MAX_ZOOM)
	_pan += screen - to_screen(anchor)
	_refresh()

## How far a finger reaches, in page units.
##
## Measured on the screen and scaled for the device, then converted — so the
## grab is the same size under the finger however far the room is zoomed. A
## fixed number of page units would be a hand's width zoomed out and nothing
## at all zoomed in, which is exactly when a joint is being placed carefully.
func _reach() -> float:
	return UiKit.s(GRAB_PX) / maxf(_zoom, 0.000001)

func _press(screen: Vector2) -> void:
	var w: Vector2 = to_page(screen)
	match mode:
		Mode.ADD:
			if not on_ink(w):
				_tell(UiKit.label_for(
					"That is off the drawing — a bone starts on the artwork",
					"هذا خارج الرسم — العظم يبدأ على الرسم"))
				return
			# Starting within reach of an end already laid snaps to it, so a
			# chain is built by dragging out from the last joint and comes
			# out genuinely joined rather than nearly joined.
			var near: Array = BoneRig.joint_at(bones, w, _reach())
			if not near.is_empty():
				var one: BoneRig.Bone = bones[int(near[0])] as BoneRig.Bone
				w = one.rest_b if int(near[1]) == 1 else one.rest_a
			_from = w
			_drawing = true
		Mode.MOVE:
			# Bone posing is a touch-only operation. Mouse remains available for
			# editor navigation, but it can never seize a joint or alter a pose.
			_grab = BoneRig.joint_at(bones, w, _reach()) if _touches.size() > 0 else []
		Mode.DROP:
			var hit: int = _bone_at(w)
			if hit < 0:
				return
			_drop(hit)
		Mode.LOOSE:
			var caught: int = _bone_at(w)
			if caught < 0:
				return
			var b: BoneRig.Bone = bones[caught] as BoneRig.Bone
			b.soft = 0.0 if b.soft > 0.0 else LOOSE_AMOUNT
			_tell(UiKit.label_for("Loose", "سائب") if b.soft > 0.0
				else UiKit.label_for("Rigid", "صلب"))
			_refresh()

func _drag(screen: Vector2) -> void:
	if mode == Mode.ADD and _drawing:
		_refresh()
	elif mode == Mode.MOVE and not _grab.is_empty():
		_move_joint(to_page(screen))
		_refresh()

func _release(screen: Vector2) -> void:
	if mode == Mode.ADD and _drawing:
		_drawing = false
		var w: Vector2 = to_page(screen)
		if fits(_from, w):
			var b: BoneRig.Bone = BoneRig.Bone.new()
			b.rest_a = _from
			b.rest_b = w
			b.parent = BoneRig.parent_for(bones, _from, _join_reach())
			# Sized to the part of the drawing it was laid in, here and once.
			# Measuring on every frame of every draw would be reading the ink
			# thousands of times a second for an answer that cannot change:
			# the artwork does not move while a skeleton is being laid on it.
			b.girth = _girth_across(_from, w)
			b.rest()
			bones.append(b)
			BoneRig.solve(bones)
			_tell(UiKit.label_for("Bone laid", "وُضع العظم"))
		else:
			_tell(UiKit.label_for(
				"That bone would leave the drawing — nothing laid",
				"هذا العظم يخرج عن الرسم — لم يُوضع شيء"))
	_grab = []
	_refresh()

func _join_reach() -> float:
	return BoneRig.join_reach(maxf(float(page.size.x), float(page.size.y)))

## The bone under a place — the one whose length passes nearest it.
func _bone_at(w: Vector2) -> int:
	var best: int = -1
	var best_d: float = _reach() * _reach() * 2.25
	for i in bones.size():
		var one: BoneRig.Bone = bones[i] as BoneRig.Bone
		var span: Vector2 = one.rest_b - one.rest_a
		var len_sq: float = span.length_squared()
		var t: float = 0.0
		if len_sq > 0.000001:
			t = clampf((w - one.rest_a).dot(span) / len_sq, 0.0, 1.0)
		var d: float = w.distance_squared_to(one.rest_a + span * t)
		if d < best_d:
			best_d = d
			best = i
	return best

## Correcting where a joint sits.
##
## Every end at that place moves, not only the one the finger caught. Two
## bones meeting at an elbow are one joint as far as anybody looking at it is
## concerned, and moving half of it would pull the chain apart at exactly the
## place a chain must not come apart.
##
## Refused off the artwork. **This is the rule that keeps a skeleton inside
## its drawing**: a joint may be corrected anywhere the ink goes and nowhere
## else, so no amount of dragging can walk a bone out into blank paper, and a
## skeleton laid on a figure stays on that figure.
func _move_joint(to: Vector2) -> void:
	if _grab.is_empty() or not on_ink(to):
		return
	var index: int = int(_grab[0])
	var which: int = int(_grab[1])
	if index < 0 or index >= bones.size():
		return
	var lead: BoneRig.Bone = bones[index] as BoneRig.Bone
	var was: Vector2 = lead.rest_b if which == 1 else lead.rest_a
	var near: float = maxf(_join_reach() * 0.5, 4.0)
	for one in bones:
		var bone: BoneRig.Bone = one as BoneRig.Bone
		if bone.rest_a.distance_to(was) <= near:
			bone.rest_a = to
		if bone.rest_b.distance_to(was) <= near:
			bone.rest_b = to
	BoneRig.solve(bones)

## Taking a bone off, without orphaning what hung from it.
##
## A child whose parent is removed is given its grandparent, so a hand does
## not come loose from a body because a forearm was reconsidered. Indices
## above the removed one shift down by one and every reference to them has to
## shift with them — a parent index that still points at where a bone *used*
## to be is a rig that poses a completely different limb.
func _drop(index: int) -> void:
	if index < 0 or index >= bones.size():
		return
	var gone: BoneRig.Bone = bones[index] as BoneRig.Bone
	for one in bones:
		var bone: BoneRig.Bone = one as BoneRig.Bone
		if bone.parent == index:
			bone.parent = gone.parent
	bones.remove_at(index)
	for one in bones:
		var bone: BoneRig.Bone = one as BoneRig.Bone
		if bone.parent > index:
			bone.parent -= 1
		elif bone.parent == index:
			bone.parent = -1
	BoneRig.solve(bones)
	_tell(UiKit.label_for("Bone removed", "أُزيل العظم"))
	_refresh()

# ------------------------------------------------------------------ accept

## Merges the skeleton into the drawing and leaves.
##
## Nothing is drawn, stamped or redrawn here, and that is the point. The bones
## are written onto the layer beside the picture that is already there — a few
## dozen floats — and from that moment the layer is posed by dragging its
## joints on the canvas. The drawing itself is untouched, which is what makes
## accepting safe: there is no version of this that can damage the artwork.
##
## `bones_rest` is the same skeleton said a second way, in flat arrays, for
## the skin — which weights a thousand points against every bone on every
## frame and should not be unpacking dictionaries to do it. It is kept in
## memory and never written to disk, because derived state in a file is state
## that can come to disagree with what it came from.
func _accept() -> void:
	if view == null or view.layers == null:
		_tell(UiKit.label_for("The canvas is not open", "اللوحة ليست مفتوحة"))
		return
	var l: LayerStack.Layer = view.layers.by_id(layer_id)
	if l == null:
		_tell(UiKit.label_for(
			"The layer this skeleton belongs to is gone. Leave and open it again.",
			"الطبقة التي يخصّها هذا الهيكل لم تعد موجودة. اخرج وافتحها ثانية."))
		return
	# Taken before anything is written, so one tap puts the layer back exactly
	# as it was — with its old skeleton, or with none.
	var before: Array = view.layers.snapshot_state()

	if bones.is_empty():
		# Accepting an empty skeleton is how a layer is un-boned, and it is a
		# real thing to want — so it is allowed and said out loud rather than
		# refused as a mistake.
		l.rig = {}
		view.layers.record_state(UiKit.label_for("Remove bones", "إزالة العظام"),
			before)
		accepted.emit(layer_index)
		return

	# Laid flat. A skeleton is accepted in the pose it was drawn on, never in
	# whatever position it happened to be nudged into, so that the rest the
	# skin is weighted against is the drawing as it actually exists.
	BoneRig.rest_all(bones)
	var doc: Dictionary = (l.rig as Dictionary).duplicate(true)
	doc["bones"] = BoneRig.to_rows(bones)
	# **Where the drawing was when these bones were laid.**
	#
	# Bones are stored in page coordinates, and page coordinates are only
	# meaningful next to the drawing they describe. If anything ever moves
	# that drawing — a page offset, a re-import, a project opened with its
	# pages laid out differently — the numbers stay the same and stop
	# pointing at the figure, and the skeleton appears somewhere off to the
	# side of it. Which is exactly what it did.
	#
	# So the drawing's own rectangle goes in beside them. Anything reading
	# this rig compares that rectangle with where the drawing is *now* and
	# shifts by the difference, so the skeleton is pinned to the artwork
	# rather than to a coordinate system that was never promised to hold
	# still. See `BoneRig.anchor_shift`.
	#
	# **Measured with the same ruler that will read it back.** This room
	# worked `_ink` out its own way — whole tiles from `content_bounds`,
	# clipped to the page, then trimmed by `get_used_rect` — while
	# `BoneRig.anchor_shift` compares it against `BoneRig.ink_of`, which
	# measures the ink directly. Two rulers that usually agree and sometimes
	# do not, and where they did not the shift was wrong from the very first
	# read: the skeleton appeared beside the drawing the instant it was
	# accepted, having never moved at all.
	#
	# The comparison is only meaningful if both sides are measured the same
	# way, so the number written here is the one the reader will produce.
	var ruler: Rect2i = BoneRig.ink_of(l)
	if ruler.size.x < 1:
		ruler = _ink
	doc["ink"] = [ruler.position.x, ruler.position.y,
		ruler.size.x, ruler.size.y]
	l.rig = doc
	l.rig["bones_rest"] = BoneRig.rest_skeleton(bones)
	view.layers.record_state(UiKit.label_for("Add bones", "إضافة عظام"),
		before)
	accepted.emit(layer_index)

# -------------------------------------------------------------------- draw

func _draw_board() -> void:
	_draw_grid()
	_draw_art()
	_draw_bones()

## A quiet measured grid. The room is for placing things precisely, and a
## field with nothing in it gives the eye no scale at all.
func _draw_grid() -> void:
	var want: float = 72.0 / maxf(_zoom, 0.000001)
	var step: float = pow(10.0, floor(log(maxf(want, 1.0)) / log(10.0)))
	for mult in [1.0, 2.0, 5.0, 10.0]:
		if step * mult >= want:
			step *= mult
			break
	var first: Vector2 = to_page(Vector2.ZERO)
	var last: Vector2 = to_page(_board.size)
	var x: float = floor(first.x / step) * step
	while x <= last.x:
		var at: float = to_screen(Vector2(x, 0.0)).x
		_board.draw_line(Vector2(at, 0.0), Vector2(at, _board.size.y),
			GRID_BOLD if is_zero_approx(fmod(x, step * 5.0)) else GRID_INK,
			1.0)
		x += step
	var y: float = floor(first.y / step) * step
	while y <= last.y:
		var at_y: float = to_screen(Vector2(0.0, y)).y
		_board.draw_line(Vector2(0.0, at_y), Vector2(_board.size.x, at_y),
			GRID_BOLD if is_zero_approx(fmod(y, step * 5.0)) else GRID_INK,
			1.0)
		y += step

func _draw_art() -> void:
	if _art_tex == null:
		return
	var at: Vector2 = to_screen(Vector2(_ink.position))
	var box: Rect2 = Rect2(at, Vector2(_ink.size) * _zoom)
	# A gold frame around the drawing's own edge, so it is obvious what the
	# skeleton is being laid onto and where that thing stops.
	_board.draw_texture_rect(_art_tex, box, false)
	_board.draw_rect(box, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), false,
		maxf(UiKit.s(1.6), 1.0))

func _draw_bones() -> void:
	for one in bones:
		var bone: BoneRig.Bone = one as BoneRig.Bone
		# Measured on the page and drawn on the screen, so a bone keeps the
		# same size relative to the drawing at every zoom.
		_girth = bone.girth * _zoom
		_draw_spindle(to_screen(bone.rest_a), to_screen(bone.rest_b),
			bone.soft > 0.0)
	_girth = 0.0
	_draw_joints()
	if mode == Mode.ADD and _drawing:
		var to: Vector2 = to_page(_board.get_local_mouse_position())
		var ok: bool = fits(_from, to)
		_board.draw_line(to_screen(_from), to_screen(to),
			BONE_INK if ok else REFUSED, maxf(UiKit.s(2.6), 2.0))

## Every joint, each place marked exactly once.
##
## Coincidence is measured on the screen rather than on the page, because that
## is where two markers would have overlapped: a gap the eye cannot resolve
## should read as one joint however far the room is zoomed in.
func _draw_joints() -> void:
	var spots: Array = []
	var near: float = maxf(UiKit.s(9.0), 6.0)
	for one in bones:
		var bone: BoneRig.Bone = one as BoneRig.Bone
		for at in [to_screen(bone.rest_a), to_screen(bone.rest_b)]:
			var found: bool = false
			for k in spots.size():
				if (spots[k] as Vector2).distance_to(at) <= near:
					found = true
					break
			if not found:
				spots.append(at)
	var wide: float = maxf(UiKit.s(9.0), 6.0) * 0.78
	for at in spots:
		_board.draw_circle(at, wide, IVORY)
		_board.draw_arc(at, wide, 0.0, TAU, 20, JOINT_EDGE, 2.0)

## A tapered spindle rather than a line, so which way a bone runs and where it
## pivots are both readable without a legend.
## The measured half-width of whichever bone is being drawn, set by
## `_draw_bones` just before each call. A parameter would have been cleaner and
## would have meant touching every call site including the live preview, which
## has no bone to read it from.
var _girth: float = 0.0

func _draw_spindle(a: Vector2, b: Vector2, loose: bool = false) -> void:
	var dir: Vector2 = b - a
	var span: float = dir.length()
	if span < 1.0:
		return
	dir = dir / span
	var side: Vector2 = Vector2(-dir.y, dir.x)
	# The width of the limb this bone is in, when it is known. Two thirds of
	# it, so the spindle sits *inside* the drawing rather than filling it and
	# the artwork stays visible through the skeleton. Falls back to the old
	# length-based width for a bone laid before this existed, or one whose
	# line crossed no ink to measure.
	var wide: float = clampf(span * 0.14, 4.0, 15.0)
	if _girth > 0.5:
		wide = clampf(_girth * 0.66, 2.5, maxf(span * 0.42, 4.0))
	var neck: Vector2 = a + dir * (span * 0.22)
	var tint: Color = LOOSE_INK if loose else BONE_INK
	var body: PackedVector2Array = PackedVector2Array([
		a, neck + side * wide, b, neck - side * wide])
	_board.draw_colored_polygon(body,
		Color(tint.r, tint.g, tint.b, 0.42))
	_board.draw_polyline(PackedVector2Array([a, neck + side * wide, b,
		neck - side * wide, a]), tint, 1.8, true)
