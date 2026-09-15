class_name SplineAnchor
extends RefCounted
## Pegging a drawing to the control points of a curve rather than to a
## distance along it.
##
## ## The fault this exists to fix
##
## A vertex used to remember one number: how far along the curve it sat, as an
## absolute distance. Four hundred units in. That distance is measured on the
## curve as it stood when the drawing was bound to it — and the moment a
## control point is dragged, the curve is a **different length**.
##
## So pull the first point out by thirty units and the curve grows by thirty.
## Every vertex still asks for the place four hundred units along, and four
## hundred units along the new curve is thirty units earlier in the shape than
## it used to be. The whole of the rest of the drawing slides along the spine.
## Nothing about those far vertices was edited; their coordinate simply
## stopped meaning what it meant.
##
## That is "moving one point moves parts that are not its", and it was worst
## furthest from the point — which is exactly the wrong way round for a curve
## whose entire reason for being a B-spline is local control.
##
## ## What a vertex remembers instead
##
## The two control points it lies between, and its distance from each of them
## along the curve. Both distances stay absolute, in pixels, so nothing
## stretches — that property was right and is kept untouched.
##
## At pose time each anchor answers where it is *now*, and the vertex takes a
## blend of the two answers weighted by which it started nearer. Three things
## follow, and together they are the whole of what precision here means:
##
##   * A vertex sitting on a control point follows that control point and no
##     other.
##   * A vertex between two of them is governed **only** by those two. A drag
##     four points away moves neither anchor, so the vertex does not move at
##     all. A handle's reach now stops at its neighbours.
##   * At rest it reproduces the old answer to the last decimal, because both
##     terms evaluate to the distance the vertex was bound at. Nothing that
##     already worked changes shape.

## Where each control point sits along the curve, in distance.
##
## Not the control point itself — a B-spline does not pass through its
## control points — but the place on the curve that point is most responsible
## for. That place is the **Greville abscissa**: the average of the `DEGREE`
## knots above the point. It is the standard answer to "which bit of the curve
## does this handle steer", it costs three additions, and it moves with the
## curve exactly as the handle does.
##
## These are the fixed marks the drawing is pegged to. Without them a vertex
## knows only "four hundred units along", and four hundred units along a curve
## that has just got longer is a different place — which is the whole of the
## fault described below in `_bind_curve`.
static func measure(spline: BSpline, arc_pts: PackedVector2Array,
		arc_len: PackedFloat32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if spline == null or spline.points.is_empty() or arc_len.is_empty():
		return out
	var top: float = spline.span_max()
	var count: int = spline.points.size()
	out.resize(count)
	for k in count:
		out[k] = _nearest(arc_pts, arc_len, spline.at(clampf(
			_greville(spline, k), 0.0, top)))
	return out

## The parameter a control point is centred on.
static func _greville(spline: BSpline, k: int) -> float:
	if spline == null or spline.knots.is_empty():
		return 0.0
	var total: float = 0.0
	var taken: int = 0
	for j in range(k + 1, k + BSpline.DEGREE + 1):
		if j < 0 or j >= spline.knots.size():
			continue
		total += spline.knots[j]
		taken += 1
	if taken == 0:
		return 0.0
	return total / float(taken)

## The distance along a walked curve of the sample nearest a place.
##
## A local copy so this module does not have to be handed the room's own
## search. Anchors are a handful per curve, so the plain scan is right here.
static func _nearest(arc_pts: PackedVector2Array, arc_len: PackedFloat32Array,
		to: Vector2) -> float:
	var best: int = 0
	var best_d: float = INF
	for i in arc_pts.size():
		var d: float = arc_pts[i].distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = i
	if best >= arc_len.size():
		return 0.0
	return arc_len[best]

## Pegs one vertex to the two control points it lies between.
static func peg(i: int, s_here: float, anchor_s: PackedFloat32Array,
		curve_at: PackedInt32Array, curve_mix: PackedFloat32Array,
		off0: PackedFloat32Array, off1: PackedFloat32Array) -> void:
	var count: int = anchor_s.size()
	if count < 2:
		curve_at[i] = -1
		return
	# The last anchor at or before this vertex. Anchors run in order along
	# the curve, so this is a walk rather than a search.
	var lo: int = 0
	for k in count:
		if anchor_s[k] <= s_here:
			lo = k
		else:
			break
	var hi: int = mini(lo + 1, count - 1)
	var a: float = anchor_s[lo]
	var b: float = anchor_s[hi]
	var mix: float = 0.0
	if hi != lo and b - a > 0.000001:
		mix = clampf((s_here - a) / (b - a), 0.0, 1.0)
	# Eased rather than straight, so the handover between one pair of anchors
	# and the next has no corner in it. A linear blend is continuous but its
	# *rate* is not, and a drawing bent across the seam shows that as a
	# crease — which would be trading one visible fault for another.
	mix = mix * mix * (3.0 - 2.0 * mix)
	curve_at[i] = lo
	curve_mix[i] = mix
	off0[i] = s_here - a
	off1[i] = s_here - b

## Where a vertex sits along the curve *now*, from the two control points it
## was pegged to. See `_peg`.
##
## Falls back to the distance it was bound at when there is nothing to peg to
## — a curve of one or two points, or a vertex on another piece of drawing.
## That is the old behaviour, and on a curve too short to have interior spans
## it is also the correct one.
static func where_now(i: int, anchor_s: PackedFloat32Array,
		curve_at: PackedInt32Array, curve_mix: PackedFloat32Array,
		off0: PackedFloat32Array, off1: PackedFloat32Array,
		curve_s: PackedFloat32Array) -> float:
	if i >= curve_at.size():
		return curve_s[i]
	var lo: int = curve_at[i]
	if lo < 0 or lo >= anchor_s.size():
		return curve_s[i]
	var hi: int = mini(lo + 1, anchor_s.size() - 1)
	var mix: float = curve_mix[i]
	return (anchor_s[lo] + off0[i]) * (1.0 - mix) \
		+ (anchor_s[hi] + off1[i]) * mix

# ------------------------------------------------------- not folding over

## How far off the spine a point may sit before the bend folds it through
## itself.
##
## ## The fault this prevents
##
## A vertex is placed by its frame: so far along the curve, so far out to the
## side. That is the right model — it is what keeps a drawing's thickness
## while its spine bends — and it has one failure, which is severe and which
## every warp-along-a-path tool has to answer.
##
## On the **inside** of a bend the normals converge. A curve of radius forty
## bending sharply has all of its inward normals crossing at the centre of
## that bend, so every vertex sitting more than forty units in lands *past*
## the centre and comes out the other side. The drawing turns inside out along
## the inner edge: the arm's inner line crosses the outer one, the fill
## reverses, and the whole bend pinches into a knot.
##
## It is worst exactly where a person bends hardest, which is why it reads as
## the tool failing rather than as a limit being reached.
##
## ## What it does instead
##
## The offset is held short of the centre of curvature. `SAFE` at 0.86 keeps
## it comfortably clear rather than exactly at the crossing point: a vertex
## landing precisely on the centre is a triangle of zero area, which renders
## as a bright seam even though nothing has crossed.
##
## Only the inside is limited. Outward offsets diverge — a bend spreads them
## apart, it never folds them — so touching those would be shrinking a drawing
## for no reason.
##
## Curvature is measured from the frame two samples either side rather than
## from a derivative, because the curve here is already a walked polyline and
## the turn between three consecutive points *is* its curvature. No second
## derivative to be noisy about.
static func fold_safe(offset_n: float, turn: float, step: float) -> float:
	if absf(turn) < 0.000001 or step <= 0.0:
		return offset_n
	# Radius from the angle swept over a known arc length: r = s / θ.
	var radius: float = step / absf(turn)
	# A positive turn bends one way, so the inside is the side whose sign
	# matches it. Only that side can fold.
	var inside: float = -offset_n if turn > 0.0 else offset_n
	if inside <= 0.0:
		return offset_n
	var most: float = radius * SAFE
	if inside <= most:
		return offset_n
	return -most if turn > 0.0 else most

## How much of the way to the centre of curvature a point may go.
const SAFE: float = 0.86
