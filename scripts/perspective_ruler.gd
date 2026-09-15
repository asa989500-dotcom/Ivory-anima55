class_name PerspectiveRuler
extends RefCounted
## Vanishing points that a stroke is drawn along.
##
## ## What a perspective ruler actually does
##
## It does not draw anything. It answers one question — *given where the
## stroke started and where the finger is now, which way should the line
## run?* — and the brush obeys the answer.
##
## That is the whole mechanism, and it is why a ruler belongs with the shape
## tools rather than in a menu of its own: a ruler is a constraint on a line,
## and the line tool is where lines are made.
##
## ## One, two and three points
##
## A vanishing point is where parallel lines meet in the picture. Which and
## how many you need is a property of what is being drawn, not a setting:
##
##   **One point** — looking straight down a street or a corridor. Everything
##   receding runs to a single point; everything across stays horizontal;
##   everything upright stays vertical.
##   **Two points** — a building seen from a corner. Two sets of horizontals
##   run to their own points, uprights stay upright.
##   **Three points** — the same, looking up at a tower or down from one, so
##   even the uprights converge on a point above or below.
##
## The horizon carries the first two, which is why moving it moves them
## together: they are on it *by definition*, and a tool that let them drift
## off it would let somebody build a background that cannot be right.
##
## ## Why the nearest guide wins, and why upright and level are guides too
##
## Whichever available direction is closest to the way the hand is already
## going is the one taken. That is what makes a ruler feel like a ruler
## rather than a cage: aim roughly along a wall and the wall's own line is
## found; aim roughly upright and it goes upright. Nothing has to be chosen
## first, and the choice can be changed by aiming somewhere else.
##
## Upright and level are always in the running alongside the vanishing points
## — a building has verticals and a floor has a horizon line, and a ruler
## that only offered the receding directions would make the easy lines the
## hard ones.

enum Kind { OFF, ONE_POINT, TWO_POINT, THREE_POINT }

## How far off a guide the hand may be and still be taken along it.
##
## Wide, deliberately. A ruler is *on* or *off*: while it is on, every line
## should obey it, and a stroke that fell between two guides and came out
## freehand would be a surprise in the middle of careful work. With upright
## and level always present the guides are never more than forty-five degrees
## apart anyway, so a wide catch means "the nearest one" rather than "any".
const CATCH: float = PI * 0.5

var kind: int = Kind.OFF
## Where the eye is. The first two vanishing points live on this line.
var horizon: float = 600.0
var left_point: Vector2 = Vector2(-900.0, 600.0)
var right_point: Vector2 = Vector2(2500.0, 600.0)
## The third, above or below, for looking up at a tower or down from one.
var up_point: Vector2 = Vector2(800.0, -2600.0)

func on() -> bool:
	return kind != Kind.OFF

## Keeps the two horizon points on the horizon.
##
## Called whenever either is moved. They are on it by definition, so this is
## not a convenience — a vanishing point that had drifted off the horizon
## would silently make every line drawn to it wrong, in a way that looks
## almost right and cannot be diagnosed by eye.
func settle() -> void:
	left_point.y = horizon
	right_point.y = horizon

## The directions a line may run in, from a given starting point.
##
## Worked out per stroke rather than held, because a vanishing point is a
## *place*: the direction towards it is different from every point on the
## page, which is the entire idea of perspective and the reason a ruler
## cannot be reduced to a fixed set of angles.
func guides(from: Vector2) -> Array:
	var out: Array = []
	if kind == Kind.OFF:
		return out
	# Upright and level, always. A building has verticals; a ruler that made
	# those the hard ones would be worse than no ruler.
	out.append(Vector2.RIGHT)
	if kind != Kind.THREE_POINT:
		out.append(Vector2.DOWN)

	match kind:
		Kind.ONE_POINT:
			_add_towards(out, from, Vector2(
				(left_point.x + right_point.x) * 0.5, horizon))
		Kind.TWO_POINT:
			_add_towards(out, from, left_point)
			_add_towards(out, from, right_point)
		Kind.THREE_POINT:
			_add_towards(out, from, left_point)
			_add_towards(out, from, right_point)
			_add_towards(out, from, up_point)
	return out

func _add_towards(out: Array, from: Vector2, point: Vector2) -> void:
	var away: Vector2 = point - from
	if away.length_squared() < 1.0:
		return
	out.append(away.normalized())

## A stroke's end, moved onto the nearest guide.
##
## The distance travelled is kept and only the direction is changed, so a line
## is as long as it was drawn — a ruler that also decided length would be
## fighting the hand over something it has no opinion about.
##
## A guide and its opposite are the same line, so both are tried: a stroke
## drawn *away* from a vanishing point is as valid as one drawn towards it and
## has to snap just as readily.
func hold(from: Vector2, to: Vector2) -> Vector2:
	if kind == Kind.OFF:
		return to
	var span: Vector2 = to - from
	var far: float = span.length()
	if far < 1.0:
		return to
	var way: Vector2 = span / far

	var best: Vector2 = way
	var best_dot: float = -2.0
	for one in guides(from):
		var g: Vector2 = one
		for signed in [g, -g]:
			var dot: float = way.dot(signed)
			if dot > best_dot:
				best_dot = dot
				best = signed
	if best_dot < cos(CATCH):
		return to
	return from + best * far

## The lines to draw on screen so the ruler can be seen and aimed.
##
## Returned as pairs of page-space points. The horizon is always shown when a
## ruler is on, because every judgement about a perspective drawing is made
## against it — a ruler whose horizon was invisible would be a set of
## constraints with no way to tell whether they were the right ones.
func marks(page: Vector2) -> Array:
	var out: Array = []
	if kind == Kind.OFF:
		return out
	out.append([Vector2(-page.x, horizon), Vector2(page.x * 2.0, horizon)])
	var points: Array = []
	match kind:
		Kind.ONE_POINT:
			points.append(Vector2((left_point.x + right_point.x) * 0.5,
				horizon))
		Kind.TWO_POINT:
			points.append(left_point)
			points.append(right_point)
		Kind.THREE_POINT:
			points.append(left_point)
			points.append(right_point)
			points.append(up_point)
	# A fan from each point, so the directions are visible rather than only
	# felt. Few enough spokes to stay out of the way of the drawing.
	for one in points:
		var p: Vector2 = one
		for i in 9:
			var a: float = float(i) * PI / 8.0
			out.append([p, p + Vector2.RIGHT.rotated(a) * page.length()])
	return out

func to_dict() -> Dictionary:
	return {
		"kind": kind, "horizon": horizon,
		"lx": left_point.x, "rx": right_point.x,
		"ux": up_point.x, "uy": up_point.y,
	}

static func from_dict(doc: Dictionary) -> PerspectiveRuler:
	var r: PerspectiveRuler = PerspectiveRuler.new()
	r.kind = int(doc.get("kind", Kind.OFF))
	r.horizon = float(doc.get("horizon", 600.0))
	r.left_point = Vector2(float(doc.get("lx", -900.0)), r.horizon)
	r.right_point = Vector2(float(doc.get("rx", 2500.0)), r.horizon)
	r.up_point = Vector2(float(doc.get("ux", 800.0)),
		float(doc.get("uy", -2600.0)))
	r.settle()
	return r
