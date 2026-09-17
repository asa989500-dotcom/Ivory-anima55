class_name MoveTool
extends RefCounted
## Moving and resizing what is already on a layer, without selecting it first.
##
## ## What it is for
##
## Every other way of moving something in this app asks you to say what it is
## first — draw a selection round it, or put it on its own layer, or rig it.
## That is the right answer when there are several things on a layer and you
## mean one of them. It is the wrong answer, and an irritating one, when there
## is one drawing on the layer and you simply want it two inches to the left
## or half the size.
##
## So this takes the layer's drawing as it stands, wraps it in the same box
## the writing and the bubbles wear, and lets it be dragged and pulled. No
## selection, no lasso, no extra layer.
##
## ## Why nothing is committed until the tool is put down
##
## The drawing is read **once**, when the tool takes hold, and kept. Every
## resize afterwards is computed from that original — never from the last
## result.
##
## This is the whole difference between a tool that can be used and one that
## can be used once. Resampling a picture compounds: halve it, double it back,
## and the second answer is not the first one, it is a soft ruin of it. Do it
## four times while deciding on a size and there is nothing recognisable left.
## Working from the original every time means a person can pull a drawing
## about for a minute looking for the right size and lose exactly nothing,
## because only the last answer is ever written down.
##
## ## Why it does not rotate
##
## The box has a turn grip because the writing and the bubbles need one, and
## both of those are **redrawn** at a new angle rather than rotated. Ink is
## not: turning a raster drawing means resampling it at an angle, which softens
## every line in it, and doing so silently under a grip that looks like the
## other grips would be a promise this cannot keep. The grip is not offered
## here. Rotating ink is a real thing to want and it deserves its own answer,
## not a corner of this one.

## Nothing smaller than this, in canvas units, to stop a drawing being pulled
## through zero and coming out inside out.
const LEAST: float = 16.0

## Which layer is held, and the drawing that was on it when it was taken up.
static var layer_id: int = -1
static var _source: Image = null
## Where it was, and where it is being put.
static var _rest: Rect2 = Rect2()
static var box: Rect2 = Rect2()
## What the finger has hold of, and where the drag began.
static var _part: int = HandleBox.Part.NOTHING
static var _from: Vector2 = Vector2.ZERO
static var _box_from: Rect2 = Rect2()
static var _motion: bool = false
static var _motion_layer_id: int = -1
static var _motion_local_center: Vector2 = Vector2.ZERO
static var _motion_base_scale: float = 1.0
static var _motion_original_position: Vector2 = Vector2.ZERO
static var _motion_original_rotation: float = 0.0
static var _motion_original_scale: float = 1.0

static func holding() -> bool:
	return layer_id >= 0 and (_source != null or _motion)

static func busy() -> bool:
	return _part != HandleBox.Part.NOTHING

## Takes up the active layer's drawing, if it has one.
##
## Called when the tool is chosen rather than when the finger lands, so the
## box is on screen straight away and there is something to aim at. A tool
## whose first touch is invisible reads as a tool that did nothing.
static func take(view: CanvasView) -> bool:
	drop()
	if view == null or view.layers == null:
		return false
	var l: LayerStack.Layer = view.layers.active()
	if l == null or l.surface == null:
		return false
	if l.is_bone_layer:
		var motion_box: Rect2i = l.surface.content_bounds()
		if motion_box.size.x < 2 or motion_box.size.y < 2:
			return false
		l.surface.flush()
		_motion = true
		_motion_layer_id = l.id
		_motion_local_center = Rect2(Vector2(motion_box.position), Vector2(motion_box.size)).get_center()
		_motion_base_scale = maxf(l.motion_scale, 0.001)
		_motion_original_position = l.motion_position
		_motion_original_rotation = l.motion_rotation
		_motion_original_scale = l.motion_scale
		l.surface.rotation = l.motion_rotation
		l.surface.scale = Vector2.ONE * _motion_base_scale
		l.surface.position = l.motion_position
		var world_center: Vector2 = l.motion_position + _motion_local_center.rotated(l.motion_rotation) * _motion_base_scale
		_rest = Rect2(world_center - Vector2(motion_box.size) * _motion_base_scale * 0.5, Vector2(motion_box.size) * _motion_base_scale)
		box = _rest
		_source = null
		l.surface.queue_redraw()
		return true
	var found: Rect2i = l.surface.content_bounds()
	if found.size.x < 2 or found.size.y < 2:
		return false
	var got: Image = l.surface.read_region(found)
	if got == null or got.get_width() < 2:
		return false
	_source = got
	layer_id = l.id
	_rest = Rect2(Vector2(found.position), Vector2(found.size))
	box = _rest
	return true

static func drop() -> void:
	layer_id = -1
	_source = null
	_motion = false
	_motion_layer_id = -1
	_motion_local_center = Vector2.ZERO
	_motion_base_scale = 1.0
	_rest = Rect2()
	box = Rect2()
	_part = HandleBox.Part.NOTHING

# ------------------------------------------------------------------- input

## True when the touch belongs to this tool.
static func grab(view: CanvasView, w: Vector2) -> bool:
	if not holding():
		return false
	var turn: float = 0.0
	if _motion:
		var ml: LayerStack.Layer = _layer_of(view)
		if ml != null:
			turn = ml.motion_rotation
	var part: int = HandleBox.part_at(view, box, turn, w)
	# The turn grip is drawn by the gizmo and ignored here — see the note at
	# the head of this file. Treated as a miss rather than as a move, so a
	# finger that lands on it does nothing instead of doing the wrong thing.
	if part == HandleBox.Part.NOTHING:
		return false
	if part == HandleBox.Part.TURN and not _motion:
		return false
	_part = part
	_from = w
	_box_from = box
	return true

static func drag(view: CanvasView, w: Vector2) -> void:
	if _part == HandleBox.Part.NOTHING:
		return
	if _motion:
		var l: LayerStack.Layer = _layer_of(view)
		if l == null or not l.is_bone_layer:
			return
		var turn: float = l.motion_rotation
		if _part == HandleBox.Part.TURN:
			turn += HandleBox.turned(_box_from, _from, w)
			box = Rect2(_box_from.position, _box_from.size)
			box = Rect2(box.get_center() - box.size * 0.5, box.size)
			l.motion_rotation = turn
		elif HandleBox.is_corner(_part):
			var sized_box: Rect2 = HandleBox.sized(_box_from, l.motion_rotation, _part, _from, w)
			var ratio: float = sized_box.size.x / maxf(_box_from.size.x, 0.001)
			l.motion_scale = maxf(_motion_base_scale * ratio, 0.01)
			box = sized_box
		else:
			box = HandleBox.moved(_box_from, _from, w)
		# Keep the object's visual centre under the gizmo centre.
		var center: Vector2 = box.get_center()
		l.motion_position = center - _motion_local_center.rotated(l.motion_rotation) * l.motion_scale
		l.surface.rotation = l.motion_rotation
		l.surface.scale = Vector2.ONE * l.motion_scale
		l.surface.position = l.motion_position
		if view != null and view.overlay != null:
			view.overlay.queue_redraw()
		return
	if HandleBox.is_corner(_part):
		box = HandleBox.sized(_box_from, 0.0, _part, _from, w)
		# Never below the floor, and never through it: a box dragged past
		# zero comes back inside out, and an inside-out box cannot be caught
		# again by any grip because its corners are on the wrong sides.
		box.size = Vector2(maxf(box.size.x, LEAST), maxf(box.size.y, LEAST))
	else:
		box = HandleBox.moved(_box_from, _from, w)
		box.position = _snapped(box.position)
	if view != null and view.overlay != null:
		view.overlay.queue_redraw()

static func release() -> void:
	_part = HandleBox.Part.NOTHING

## Whole pixels, always.
##
## A drawing put down at x = 40.3 is a drawing resampled by three tenths of a
## pixel across its whole width — every line in it softened, for a move nobody
## asked to be that precise. Landing on whole numbers means a pure move costs
## the drawing nothing at all, which is what a move should cost.
static func _snapped(at: Vector2) -> Vector2:
	return at.round()

## Puts the drawing back exactly where it was found.
##
## Worth its own way in rather than being left to undo. Undo after a commit
## works, but the person who has pulled a drawing around for thirty seconds
## and wants out has not committed anything yet — there is nothing to undo,
## and without this the only way back is to place it wrong on purpose and
## then undo that.
static func revert(view: CanvasView) -> void:
	if not holding():
		return
	if _motion:
		var l: LayerStack.Layer = _layer_of(view)
		if l != null:
			l.motion_position = _motion_original_position
			l.motion_rotation = _motion_original_rotation
			l.motion_scale = _motion_original_scale
			l.surface.position = l.motion_position
			l.surface.rotation = l.motion_rotation
			l.surface.scale = Vector2.ONE * l.motion_scale
	box = _rest
	_part = HandleBox.Part.NOTHING
	if view != null and view.overlay != null:
		view.overlay.queue_redraw()

# ------------------------------------------------------------------ commit

## Writes the drawing where the box now is, and lets go.
##
## The only moment anything is written. Called when the tool is put down, or
## from the panel's Done — and if the box has not moved, nothing is written at
## all, so choosing the tool and changing your mind costs the drawing nothing.
static func commit(view: CanvasView) -> bool:
	if not holding():
		return false
	# One declaration each, at the top of the function. Both branches below
	# want the same two things, and a second `var l` inside the motion branch
	# is the CONFUSABLE_LOCAL_DECLARATION the editor reported: the name reads
	# as the outer one and is not.
	var l: LayerStack.Layer = _layer_of(view)
	var before: Array = []
	if _motion:
		if l == null or not l.is_bone_layer:
			drop()
			return false
		before = view.layers.snapshot_state()
		var changed: bool = l.motion_position.distance_to(_motion_original_position) > 0.25 \
				or absf(l.motion_rotation - _motion_original_rotation) > 0.001 \
				or absf(l.motion_scale - _motion_original_scale) > 0.001
		view.layers.record_state(UiKit.label_for("Move object", "تحريك الجسم"), before)
		drop()
		return changed
	if box.position.distance_to(_rest.position) < 0.5 \
			and box.size.distance_to(_rest.size) < 0.5:
		drop()
		return false
	if l == null or l.surface == null:
		drop()
		return false
	before = view.layers.snapshot_state()

	# The drawing is lifted off first and then put down. Written without
	# clearing, the old copy stays where it was and the layer ends up holding
	# two of everything — which is what "move" must never mean.
	var blank: Image = Image.create_empty(int(_rest.size.x),
		int(_rest.size.y), false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 0.0, 0.0, 0.0))
	l.surface.blit_image(blank, _rest.position, true)

	# Resized from the *original* every time, never from the last result.
	# See the note at the head of this file — this one line is the reason a
	# drawing can be pulled about for a minute and lose nothing.
	var out: Image = _source.duplicate()
	var wide: int = maxi(int(round(box.size.x)), 1)
	var tall: int = maxi(int(round(box.size.y)), 1)
	# A drawing pulled to twenty times its size is tens of millions of
	# pixels, allocated in one go, on a phone. Capped at a size that is still
	# far past anything useful, so a slip of the finger cannot take the app
	# down with it.
	var most: int = 16384
	if wide > most or tall > most:
		var k: float = float(most) / float(maxi(wide, tall))
		wide = maxi(int(float(wide) * k), 1)
		tall = maxi(int(float(tall) * k), 1)
	if wide != out.get_width() or tall != out.get_height():
		# Lanczos going up for a clean edge; area averaging going down,
		# because Lanczos rings every line it reduces and a drawing with a
		# pale halo along every stroke is worse than a slightly softer one.
		var going_down: bool = wide < out.get_width()
		out.resize(wide, tall, Image.INTERPOLATE_TRILINEAR if going_down
			else Image.INTERPOLATE_LANCZOS)
	l.surface.blit_image(out, _snapped(box.position))
	l.surface.flush()
	view.layers.record_state(
		UiKit.label_for("Move the drawing", "تحريك الرسم"), before)
	drop()
	return true

static func _layer_of(view: CanvasView) -> LayerStack.Layer:
	if view == null or view.layers == null:
		return null
	for one in view.layers.layers:
		var l: LayerStack.Layer = one as LayerStack.Layer
		if l.id == layer_id:
			return l
	return null

# ------------------------------------------------------------------ drawing

## The box, and a hint of where the drawing came from.
##
## The rest position is left showing as a faint outline while the box is
## somewhere else, because "how far have I moved it" is the question being
## asked and a box on its own cannot answer it.
static func draw_on(view: CanvasView) -> void:
	if not holding() or view.overlay == null:
		return
	var thin: float = 1.0 / maxf(view.view_zoom, 0.0001)
	if box.position.distance_to(_rest.position) > 1.0 \
			or box.size.distance_to(_rest.size) > 1.0:
		var was: Rect2 = Rect2(view.canvas_to_screen(_rest.position),
			_rest.size * view.view_zoom)
		view.overlay.draw_rect(was, Color(1.0, 1.0, 1.0, 0.18), false,
			maxf(1.2, 1.2 * thin * view.view_zoom))
	var turn: float = 0.0
	if _motion:
		var l: LayerStack.Layer = _layer_of(view)
		if l != null:
			turn = l.motion_rotation
	HandleBox.draw_on(view, box, turn, _part)
