class_name BSpline
extends RefCounted
## Cubic B-spline curves, and binding a drawing to them.

## ## Why a B-spline and not a Bézier
##
## Two properties, and everything this room does comes out of them.
##
## **Local control.** A control point only touches the spans of the curve
## near it — for a cubic, four of them. Move one point and the far end of the
## curve does not stir. A Bézier of the same length is one polynomial: every
## point rewrites the whole thing.
##
## **C² continuity, for free.** The curve and its first *and second*
## derivatives are continuous everywhere. Curvature does not jump, so a bend
## has no corner in it and no flat spot before it — without a single handle to
## drag. Bézier chains only reach C¹ by hand, by keeping each pair of handles
## collinear, and every edit is a chance to break it.
##
## The price is that the curve does not pass through its control points. That
## is not a loss here: the points are magnets that steer the drawing, which is
## exactly how they are meant to be understood.
##
## ## How the curve is evaluated
##
## De Boor's algorithm, not a matrix and not a sum of basis polynomials. It is
## the numerically stable way — every step is a convex combination, so values
## stay bounded and rounding cannot accumulate into a wobble — and it is the
## only formulation that keeps working when knots are repeated, which is what
## makes sharp corners possible in the same curve as smooth ones.
##
## ## Sharp corners in a smooth curve
##
## A knot repeated `degree` times drops continuity at that spot to C⁰: the
## curve arrives, touches its control point exactly, and leaves in a new
## direction. One curve can therefore be silk along a back and a hard angle at
## a shoulder. Knots are inserted by Boehm's algorithm, which adds a knot
## *without changing the curve at all* — the shape before and after is
## identical to the last decimal, only now there is a place to break it.

const DEGREE: int = 3

var points: PackedVector2Array = PackedVector2Array()
var knots: PackedFloat32Array = PackedFloat32Array()
## Parallel to `points`: how sharp the curve is at each one. 0 is fully
## smooth, DEGREE is a corner.
var sharp: PackedInt32Array = PackedInt32Array()

# ------------------------------------------------------------------- shape

func clear() -> void:
	points = PackedVector2Array()
	knots = PackedFloat32Array()
	sharp = PackedInt32Array()

func size() -> int:
	return points.size()

## Enough points to have a curve at all.
func ready() -> bool:
	return points.size() >= DEGREE + 1

func add_point(where: Vector2) -> void:
	points.append(where)
	sharp.append(0)
	rebuild_knots()

func insert_point(index: int, where: Vector2) -> void:
	if index < 0 or index > points.size():
		return
	points.insert(index, where)
	sharp.insert(index, 0)
	rebuild_knots()

func remove_point(index: int) -> void:
	if index < 0 or index >= points.size():
		return
	points.remove_at(index)
	sharp.remove_at(index)
	rebuild_knots()

func move_point(index: int, to: Vector2) -> void:
	if index < 0 or index >= points.size():
		return
	points[index] = to

## A clamped knot vector: the first and last knots repeat `DEGREE + 1` times
## so the curve starts exactly at the first control point and ends exactly at
## the last. Without the clamping it would begin somewhere inside the run of
## points, which on screen looks like the ends have been eaten.
##
## Interior knots also repeat where a point has been marked sharp, which is
## what puts a corner there.
func rebuild_knots() -> void:
	knots = PackedFloat32Array()
	var n: int = points.size()
	if n == 0:
		return
	for i in DEGREE + 1:
		knots.append(0.0)
	var step: float = 1.0
	var value: float = 0.0
	for i in range(1, maxi(n - DEGREE, 0)):
		value += step
		var times: int = 1
		var owner: int = i + DEGREE - 1
		if owner >= 0 and owner < sharp.size():
			times = clampi(sharp[owner] + 1, 1, DEGREE)
		for k in times:
			knots.append(value)
	value += step
	for i in DEGREE + 1:
		knots.append(value)

func span_max() -> float:
	if knots.is_empty():
		return 0.0
	return knots[knots.size() - 1]

# -------------------------------------------------------------- evaluation

## The knot span a parameter falls in — the window of control points that has
## any say at this spot. Found by bisection, so a curve with a thousand points
## costs ten comparisons rather than a thousand.
func _span_of(u: float) -> int:
	var n: int = points.size() - 1
	if n < DEGREE:
		return DEGREE
	if u >= knots[n + 1]:
		return n
	if u <= knots[DEGREE]:
		return DEGREE
	var lo: int = DEGREE
	var hi: int = n + 1
	var mid: int = (lo + hi) >> 1
	while u < knots[mid] or u >= knots[mid + 1]:
		if u < knots[mid]:
			hi = mid
		else:
			lo = mid
		mid = (lo + hi) >> 1
		if mid <= DEGREE:
			return DEGREE
		if mid >= n:
			return n
	return mid

## De Boor. Each round replaces the working points with points between them,
## so the answer is always inside the hull of the control points it came from
## and can never fly off.
func at(u: float) -> Vector2:
	var n: int = points.size()
	if n == 0:
		return Vector2.ZERO
	if n <= DEGREE:
		# Too few points for a cubic. A straight run between them is the
		# honest answer while a curve is still being built.
		return _polyline_at(u)
	var top: float = span_max()
	var t: float = clampf(u, 0.0, top)
	var k: int = _span_of(t)

	var work: Array = []
	work.resize(DEGREE + 1)
	for j in DEGREE + 1:
		work[j] = points[clampi(j + k - DEGREE, 0, n - 1)]

	for r in range(1, DEGREE + 1):
		for j in range(DEGREE, r - 1, -1):
			var lo: int = j + k - DEGREE
			var hi: int = j + 1 + k - r
			var a: float = knots[clampi(lo, 0, knots.size() - 1)]
			var b: float = knots[clampi(hi, 0, knots.size() - 1)]
			var gap: float = b - a
			var alpha: float = 0.0 if gap <= 0.0000001 else (t - a) / gap
			work[j] = (work[j - 1] as Vector2).lerp(work[j] as Vector2, alpha)
	return work[DEGREE]

func _polyline_at(u: float) -> Vector2:
	var n: int = points.size()
	if n == 1:
		return points[0]
	var top: float = maxf(span_max(), 0.000001)
	var f: float = clampf(u / top, 0.0, 1.0) * float(n - 1)
	var i: int = clampi(int(floor(f)), 0, n - 2)
	return points[i].lerp(points[i + 1], f - float(i))

## The direction the curve is travelling. Taken as a difference over a short
## step rather than as a formula: at a repeated knot the true derivative does
## not exist, and a step across the corner still gives a usable heading
## instead of a division by zero.
func tangent_at(u: float) -> Vector2:
	var top: float = maxf(span_max(), 0.000001)
	var h: float = top * 0.0015
	var a: Vector2 = at(clampf(u - h, 0.0, top))
	var b: Vector2 = at(clampf(u + h, 0.0, top))
	var d: Vector2 = b - a
	if d.length_squared() < 0.000000001:
		return Vector2.RIGHT
	return d.normalized()

## Boehm's knot insertion. The curve is untouched — this only gives it another
## control point to be steered by, or another repeat at one place so it can be
## broken there.
func sharpen(index: int, amount: int) -> void:
	if index < 0 or index >= sharp.size():
		return
	sharp[index] = clampi(amount, 0, DEGREE)
	rebuild_knots()

func sharpness(index: int) -> int:
	if index < 0 or index >= sharp.size():
		return 0
	return sharp[index]

# ----------------------------------------------------------------- walking

## The curve as a run of straight pieces, spaced evenly in *length* rather
## than in parameter.
##
## Parameter and distance are not the same thing on a B-spline: the curve
## hurries through some spans and dawdles through others. Anything that walks
## the curve — binding a drawing to it, laying bones along it, drawing it —
## wants even spacing on the page, so the samples are re-spaced by arc length
## before they are handed out.
func walk(steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = maxi(steps, 2)
	var top: float = span_max()
	if points.is_empty() or top <= 0.0:
		return out
	# Dense first pass, measured, then re-spaced.
	var fine: int = n * 4
	var raw: PackedVector2Array = PackedVector2Array()
	var run: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for i in fine + 1:
		var p: Vector2 = at(top * float(i) / float(fine))
		if i > 0:
			total += p.distance_to(raw[i - 1])
		raw.append(p)
		run.append(total)
	if total <= 0.000001:
		out.append(raw[0])
		return out
	var cursor: int = 0
	for i in n:
		var want: float = total * float(i) / float(n - 1)
		while cursor < run.size() - 2 and run[cursor + 1] < want:
			cursor += 1
		var a: float = run[cursor]
		var b: float = run[cursor + 1]
		var f: float = 0.0 if b - a <= 0.000001 else (want - a) / (b - a)
		out.append(raw[cursor].lerp(raw[cursor + 1], f))
	return out

## The parameter of the point on the curve nearest a place on the page.
##
## Coarse sweep to find the neighbourhood, then a golden-section narrowing
## inside it. A plain fine sweep would need hundreds of evaluations for the
## same accuracy; this needs a few dozen and lands far closer.
func nearest(to: Vector2, coarse: int = 64) -> Dictionary:
	var top: float = span_max()
	if points.is_empty() or top <= 0.0:
		return {"u": 0.0, "point": Vector2.ZERO, "away": INF}
	var best_u: float = 0.0
	var best_d: float = INF
	for i in coarse + 1:
		var u: float = top * float(i) / float(coarse)
		var d: float = at(u).distance_squared_to(to)
		if d < best_d:
			best_d = d
			best_u = u
	var step: float = top / float(coarse)
	var lo: float = maxf(best_u - step, 0.0)
	var hi: float = minf(best_u + step, top)
	for i in 24:
		var m1: float = lo + (hi - lo) * 0.382
		var m2: float = lo + (hi - lo) * 0.618
		if at(m1).distance_squared_to(to) < at(m2).distance_squared_to(to):
			hi = m2
		else:
			lo = m1
	var u_final: float = (lo + hi) * 0.5
	var p: Vector2 = at(u_final)
	return {"u": u_final, "point": p, "away": p.distance_to(to)}

## Which control points have any say at a parameter. This is local control
## made explicit: for a cubic it is never more than four, whatever the length
## of the curve.
func influencing(u: float) -> Array:
	if points.size() <= DEGREE:
		var all: Array = []
		for i in points.size():
			all.append(i)
		return all
	var k: int = _span_of(clampf(u, 0.0, span_max()))
	var out: Array = []
	for j in DEGREE + 1:
		var i: int = clampi(j + k - DEGREE, 0, points.size() - 1)
		if not out.has(i):
			out.append(i)
	return out

func duplicate_spline() -> BSpline:
	var copy: BSpline = BSpline.new()
	copy.points = points.duplicate()
	copy.knots = knots.duplicate()
	copy.sharp = sharp.duplicate()
	return copy
