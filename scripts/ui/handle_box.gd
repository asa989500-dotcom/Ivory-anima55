class_name HandleBox
extends RefCounted
## A box with grips: four corners that resize, one stalk above that turns,
## and the whole of the inside that moves.
##
## ## Why this is one class and not three
##
## Text had a box of its own. Bubbles had no box at all — they were dragged by
## whatever part of them happened to be under the finger, with nothing on
## screen saying what could be grabbed. And a general move-and-resize tool
## needs exactly the same thing a third time.
##
## Three copies of a gizmo is three chances for a corner to be four pixels
## wide in one place and nine in another, for a turn to go the short way here
## and the long way there. It is the same fault the two bone classes had, and
## it is answered the same way: one implementation, no opinions about what is
## inside the box.
##
## So this knows a rectangle and an angle. It does not know what it is
## wrapped around, cannot change it, and never touches a pixel. Whoever owns
## the thing asks `part_at` what the finger caught, calls `moved`, `sized` or
## `turned` for the answer, and applies it themselves.
##
## ## Why grips are a constant size on screen
##
## A corner is a target for a fingertip, and a fingertip is the same size
## whatever the zoom is. Scaling the grips with the drawing made them
## unusable zoomed out and absurd zoomed in — the one thing on screen that
## must not scale is the thing you aim at.

## What the finger caught. `NOTHING` is the miss, and it matters: a miss has
## to fall through to whatever is underneath rather than being swallowed.
enum Part { NOTHING, MOVE, TURN, TOP_LEFT, TOP_RIGHT, BOTTOM_RIGHT,
	BOTTOM_LEFT }

## Grip radius and reach in screen pixels, before the interface scale.
const GRIP_PX: float = 7.0
const REACH_PX: float = 30.0
## How far above the top edge the turn stalk stands, in screen pixels.
const STALK_PX: float = 34.0
## No box may be resized below this, in canvas units. A box dragged through
## nothing comes out inside out, and an inside-out box is a shape nobody can
## get hold of again.
const LEAST: float = 12.0

const IVORY: Color = Color("#FFF8E7")
const EDGE: Color = Color("#8A7C58")

## Canvas units per screen pixel, so a grip drawn in canvas space comes out
## the same size on screen at any zoom.
static func _unit(view: CanvasView) -> float:
	return App.ui_scale / maxf(view.view_zoom, 0.0001)

## The four corners of a box, turned about its centre, in drawing order.
static func corners(box: Rect2, turn: float) -> PackedVector2Array:
	var mid: Vector2 = box.get_center()
	var out: PackedVector2Array = PackedVector2Array()
	for c in [box.position, Vector2(box.end.x, box.position.y), box.end,
			Vector2(box.position.x, box.end.y)]:
		out.append(mid + ((c as Vector2) - mid).rotated(turn))
	return out

## Where the turn grip stands.
static func grip_at(view: CanvasView, box: Rect2, turn: float) -> Vector2:
	return box.get_center() + Vector2(0.0,
		-box.size.y * 0.5 - STALK_PX * _unit(view)).rotated(turn)

## What is under this point, in canvas coordinates.
##
## Corners are asked about before the body, because a corner sits *on* the
## body's edge and a box small enough that its corners overlap its middle is
## exactly the box whose corners are hardest to hit.
static func part_at(view: CanvasView, box: Rect2, turn: float,
		w: Vector2) -> int:
	if box.size.x < 1.0 or box.size.y < 1.0:
		return Part.NOTHING
	var reach: float = REACH_PX * _unit(view)
	if w.distance_to(grip_at(view, box, turn)) <= reach:
		return Part.TURN
	var pts: PackedVector2Array = corners(box, turn)
	var named: Array = [Part.TOP_LEFT, Part.TOP_RIGHT, Part.BOTTOM_RIGHT,
		Part.BOTTOM_LEFT]
	for i in 4:
		if w.distance_to(pts[i]) <= reach:
			return named[i]
	# Tested in the box's own frame, because the box is drawn turned and an
	# upright rectangle tested against a slanted one answers in the wrong
	# places along both diagonals and nowhere near its own corners.
	var mid: Vector2 = box.get_center()
	var local: Vector2 = mid + (w - mid).rotated(-turn)
	if box.grow(reach * 0.4).has_point(local):
		return Part.MOVE
	return Part.NOTHING

## The box moved by a drag.
static func moved(box: Rect2, from: Vector2, to: Vector2) -> Rect2:
	return Rect2(box.position + (to - from), box.size)

## The box turned by a drag, as an angle to add to the one it started at.
##
## Measured as the change in bearing from the centre rather than as a bearing,
## so a grab that lands slightly off the grip does not snap the box round to
## meet the finger the instant it is touched. That snap is the commonest fault
## in a rotate handle and it is entirely avoidable.
static func turned(box: Rect2, from: Vector2, to: Vector2) -> float:
	var mid: Vector2 = box.get_center()
	return (to - mid).angle() - (from - mid).angle()

## The box resized by dragging one corner, with the opposite corner pinned.
##
## ## Why the opposite corner is the anchor
##
## It is what the hand expects: the corner you are not touching is the one
## that stays. Resizing about the centre instead makes the whole shape breathe
## in and out around a point nobody is holding, and a caption being made
## slightly wider walks away from the line it was being aligned to.
##
## `even` keeps the proportions, which is what writing and a bubble both want
## — letters stretched on one axis are letters nobody chose. The scale taken
## is the larger of the two, so the box always contains the drag rather than
## lagging behind one axis of it.
static func sized(box: Rect2, turn: float, part: int, from: Vector2,
		to: Vector2, even: bool = true) -> Rect2:
	var pinned: int = _opposite(part)
	if pinned == Part.NOTHING:
		return box
	var pts: PackedVector2Array = corners(box, turn)
	var anchor: Vector2 = pts[_corner_index(pinned)]

	# --- the box must not jump on the first pixel of the drag ---
	#
	# ## What was wrong
	#
	# The scale was measured from where the *finger* landed: `to - anchor`
	# over `from - anchor`. A corner has a reach of thirty screen pixels, so a
	# finger routinely lands well short of the corner it is grabbing — and the
	# ratio between two distances that both start from the anchor is not one
	# when the numerator starts closer in. So the box resized to match the
	# finger's own distance the instant the drag began, and the corner leapt
	# to meet the thumb before it had moved at all.
	#
	# Worse near a corner's own axis: `was.x` is the finger's offset along one
	# axis, and when a finger lands nearly level with the anchor on that axis
	# it is a very small number. Dividing by it magnifies every later movement
	# without limit, which is the box behaving wildly along one direction and
	# sensibly along the other — exactly the "unstable" report.
	#
	# ## What it is now
	#
	# The offset between the finger and the corner it caught is measured once
	# and carried for the whole drag, so the *corner* follows the finger with
	# that offset held constant. Grabbing anywhere inside the reach now
	# behaves identically to grabbing the corner exactly: nothing moves until
	# the finger does, and then the corner moves exactly as far.
	var grabbed: Vector2 = pts[_corner_index(part)]
	var carried: Vector2 = to + (grabbed - from)

	# Both the grab and the drop are read in the box's own upright frame, so
	# the arithmetic below is the same whether the box is turned or not.
	var was: Vector2 = (grabbed - anchor).rotated(-turn)
	var now: Vector2 = (carried - anchor).rotated(-turn)
	if absf(was.x) < 0.001 or absf(was.y) < 0.001:
		return box
	var kx: float = now.x / was.x
	var ky: float = now.y / was.y
	if even:
		var k: float = maxf(absf(kx), absf(ky))
		kx = k
		ky = k
	else:
		kx = absf(kx)
		ky = absf(ky)
	var wide: Vector2 = Vector2(maxf(box.size.x * kx, LEAST),
		maxf(box.size.y * ky, LEAST))
	# Rebuilt from the pinned corner outwards, then said as an upright
	# rectangle again: the caller stores a box and an angle, never a
	# parallelogram, and this is where that promise is kept.
	var sign_x: float = -1.0 if pinned in [Part.TOP_RIGHT, Part.BOTTOM_RIGHT] \
		else 1.0
	var sign_y: float = -1.0 if pinned in [Part.BOTTOM_LEFT,
		Part.BOTTOM_RIGHT] else 1.0
	var far: Vector2 = anchor + Vector2(wide.x * sign_x,
		wide.y * sign_y).rotated(turn)
	var mid: Vector2 = (anchor + far) * 0.5
	return Rect2(mid - wide * 0.5, wide)

static func _opposite(part: int) -> int:
	match part:
		Part.TOP_LEFT:
			return Part.BOTTOM_RIGHT
		Part.TOP_RIGHT:
			return Part.BOTTOM_LEFT
		Part.BOTTOM_RIGHT:
			return Part.TOP_LEFT
		Part.BOTTOM_LEFT:
			return Part.TOP_RIGHT
	return Part.NOTHING

static func _corner_index(part: int) -> int:
	match part:
		Part.TOP_RIGHT:
			return 1
		Part.BOTTOM_RIGHT:
			return 2
		Part.BOTTOM_LEFT:
			return 3
	return 0

## Whether this part resizes the box, so a caller can branch once.
static func is_corner(part: int) -> bool:
	return part >= Part.TOP_LEFT

# ------------------------------------------------------------------ drawing

## The box and its grips, drawn on the overlay in canvas coordinates.
##
## Every width and radius is divided by the zoom, so the line stays one pixel
## and the grips stay thumb-sized however far in or out the drawing is.
static func draw_on(view: CanvasView, box: Rect2, turn: float,
		lit: int = Part.NOTHING) -> void:
	if view.overlay == null or box.size.x < 1.0:
		return
	var unit: float = _unit(view)
	var thin: float = 1.0 / maxf(view.view_zoom, 0.0001)
	var pts: PackedVector2Array = corners(box, turn)
	var ring: PackedVector2Array = pts.duplicate()
	ring.append(pts[0])
	# A dark line under the pale one, so the box reads on white paper and on
	# black ink alike. One colour cannot do that and this is cheaper than
	# working out what it is sitting on.
	view.overlay.draw_polyline(ring, Color(0.05, 0.04, 0.03, 0.45), 3.0 * thin)
	view.overlay.draw_polyline(ring, IVORY, 1.4 * thin)

	var grip: Vector2 = grip_at(view, box, turn)
	var mid: Vector2 = box.get_center()
	view.overlay.draw_line(
		mid + Vector2(0.0, -box.size.y * 0.5).rotated(turn), grip,
		Color(IVORY.r, IVORY.g, IVORY.b, 0.6), 1.4 * thin)
	_dot(view, grip, GRIP_PX * 1.3 * unit, lit == Part.TURN)

	var named: Array = [Part.TOP_LEFT, Part.TOP_RIGHT, Part.BOTTOM_RIGHT,
		Part.BOTTOM_LEFT]
	for i in 4:
		_dot(view, pts[i], GRIP_PX * unit, lit == named[i])

static func _dot(view: CanvasView, at: Vector2, r: float,
		lit: bool) -> void:
	var thin: float = 1.0 / maxf(view.view_zoom, 0.0001)
	view.overlay.draw_circle(at + Vector2(1.0, 2.0) * thin, r,
		Color(0.0, 0.0, 0.0, 0.3))
	view.overlay.draw_circle(at, r, Color("#D9B45B") if lit else IVORY)
	view.overlay.draw_arc(at, r, 0.0, TAU, 18, EDGE, 2.0 * thin)
