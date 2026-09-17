class_name ComicPage
extends RefCounted
## The frames a comic page is cut into.
##
## ## What this owns and what it does not
##
## It owns a list of polygons and which one is chosen. It does not own the
## drawing — a panel is a *region*, not a layer, and the difference matters:
## somebody who cuts a page into six frames and then merges two of them has
## not thrown away six layers' worth of work, they have changed a boundary.
##
## The geometry itself is in `ivory_comic.{h,cpp}`, with the same methods
## reimplemented below for a build without the extension. That is not
## duplication for its own sake — it is what lets the app run on a checkout
## nobody has compiled, and the C++ side carries the test bench that proves
## the two agree.
##
## ## Why panels are polygons and not rectangles
##
## Because the first diagonal cut makes a rectangle a lie. A system that
## stores rectangles has to either refuse the diagonal or store a rectangle
## that is not where the panel is, and the second is worse than the first: the
## drawing clips against a boundary nobody can see.
##
## ## Why the cuts are not stored
##
## The obvious model is a tree — this page was cut here, then the left half
## was cut there — and it is the wrong one. A split tree remembers *how* the
## page got its shape, which sounds like more information and is actually a
## cage: moving one border means re-deriving every cut that came after it, and
## a border that cannot be nudged is a layout that has to be started again
## whenever it is nearly right.
##
## Flat polygons have no such problem. Every operation takes polygons and
## returns polygons, and how it got there lives in the undo stack, which is
## where history belongs.

## The five ways a page can be cut. These mirror `IvoryComic::Cut` exactly and
## are passed across as plain integers.
enum Cut { LINE, CIRCLE, SQUARE, RECT, FREE }

## How far the border box sits inside the page, in page units.
##
## A comic page is printed with a margin and the frames sit inside it. This is
## that margin, and it is what makes the border box "a little smaller than the
## project's frame" — visibly inside it, so the edge of the paper and the edge
## of the artwork are two different lines.
const MARGIN: float = 42.0

## The white channel between two panels, in page units.
const GUTTER: float = 18.0

var panels: Array = []            # Array[PackedVector2Array]
## Which panel is being drawn in, or -1 for none.
var chosen: int = -1
## The gutter this page is using. Kept per page rather than global — a splash
## page and a nine-panel grid want different channels.
var gutter: float = GUTTER
## Whether the border is being enforced at all. See `confined`.
var confine: bool = true

var _fast: Object = null

# ------------------------------------------------------------------ making

## A page that is one frame, inset from its edges.
static func fresh(page: Vector2) -> ComicPage:
	var out: ComicPage = ComicPage.new()
	out.reset(page)
	return out

func reset(page: Vector2) -> void:
	var m: float = minf(MARGIN, minf(page.x, page.y) * 0.12)
	panels = [_frame_of(page, m)]
	chosen = -1

static func _frame_of(page: Vector2, m: float) -> PackedVector2Array:
	var w: float = maxf(page.x - m * 2.0, 8.0)
	var h: float = maxf(page.y - m * 2.0, 8.0)
	# Wound the same way as every other polygon in the system — see
	# `IvoryComic::page_frame`. Consistent winding is what lets the inset know
	# which way "inward" is without being told.
	return PackedVector2Array([
		Vector2(m, m), Vector2(m + w, m),
		Vector2(m + w, m + h), Vector2(m, m + h)])

## The native engine, loaded with the panels as they are now.
##
## Rebuilt on each call rather than kept in step. A cut is something a person
## does a few times a minute; keeping two copies of the layout synchronised
## between those moments would be a bug waiting for the one path that forgot.
func _engine() -> Object:
	if not Native.has_comic():
		return null
	if _fast == null:
		_fast = Native.comic()
	if _fast == null:
		return null
	_fast.set_panels(panels)
	return _fast

# ----------------------------------------------------------------- cutting

## Cuts with a straight run. Returns true when the page changed.
##
## Only panels the run touches are cut, which is the whole of "a cut need not
## go all the way across": split the page down the middle, then draw a short
## line inside the left half, and the right half is not consulted. See
## `IvoryComic::segment_cuts`, which explains why touching is the rule rather
## than crossing.
func cut_line(a: Vector2, b: Vector2) -> bool:
	var engine: Object = _engine()
	if engine != null:
		if int(engine.split_by_line(a, b, gutter)) <= 0:
			return false
		panels = engine.panels()
		return true
	return _cut_line_here(a, b)

## Cuts with a closed shape. The shape becomes a panel of its own.
func cut_shape(kind: int, box: Rect2,
		points: PackedVector2Array = PackedVector2Array()) -> bool:
	var engine: Object = _engine()
	if engine != null:
		if int(engine.split_by_shape(kind, box, points, gutter)) <= 0:
			return false
		panels = engine.panels()
		return true
	return _cut_shape_here(kind, box, points)

# ----------------------------------------------------------------- asking

## Which panel is under a point, or -1.
func panel_at(at: Vector2) -> int:
	var engine: Object = _engine()
	if engine != null:
		return int(engine.panel_at(at))
	# Backwards, so a shape cut out of a panel wins over the panel it came
	# from — the shape was added later and is what the finger meant.
	for i in range(panels.size() - 1, -1, -1):
		if _point_in(panels[i], at):
			return i
	return -1

func bounds_of(index: int) -> Rect2:
	if index < 0 or index >= panels.size():
		return Rect2()
	var poly: PackedVector2Array = panels[index]
	if poly.is_empty():
		return Rect2()
	var box: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for i in range(1, poly.size()):
		box = box.expand(poly[i])
	return box

## Whether a point may be painted.
##
## ## The rule, and why it is stated this way round
##
## Paint is refused when it falls outside the panel being drawn in. Not
## "allowed when inside" — the difference shows at the edges of the system:
## with no panels at all, with nothing chosen, or with confinement turned off,
## the honest answer is *yes, paint anywhere*, and a rule phrased as a
## permission would have to remember to say yes three times.
##
## A drawing tool that refuses to draw because a feature it knows nothing
## about is in a state it did not expect is the worst failure this could have.
## Whether a point is inside one named panel.
##
## `allows` asks about the *chosen* panel; this asks about any of them, which
## is what confinement needs once a mark is tied to the panel it began in
## rather than to whichever frame was last tapped.
func point_in_panel(index: int, at: Vector2) -> bool:
	if index < 0 or index >= panels.size():
		return false
	var engine: Object = _engine()
	if engine != null:
		return bool(engine.inside(index, at))
	return _point_in(panels[index], at)

func allows(at: Vector2) -> bool:
	if not confine:
		return true
	if chosen < 0 or chosen >= panels.size():
		return true
	if panels.is_empty():
		return true
	var engine: Object = _engine()
	if engine != null:
		return bool(engine.inside(chosen, at))
	return _point_in(panels[chosen], at)

## Whether anything is being confined right now, for the canvas to draw the
## chosen panel's outline brighter than the rest.
func confined() -> bool:
	return confine and chosen >= 0 and chosen < panels.size()

# --------------------------------------------------------------- the file

func to_dict() -> Dictionary:
	var rows: Array = []
	for one in panels:
		var poly: PackedVector2Array = one
		var flat: PackedFloat32Array = PackedFloat32Array()
		flat.resize(poly.size() * 2)
		for i in poly.size():
			flat[i * 2] = poly[i].x
			flat[i * 2 + 1] = poly[i].y
		rows.append(flat)
	# `chosen` is deliberately saved. Reopening a page with the panel you were
	# working in still chosen is the difference between picking up where you
	# were and finding the confinement silently off — and the second is
	# discovered by drawing over a border.
	return {
		"panels": rows,
		"chosen": chosen,
		"gutter": gutter,
		"confine": confine,
	}

static func from_dict(doc: Dictionary) -> ComicPage:
	var out: ComicPage = ComicPage.new()
	out.panels = []
	for row in doc.get("panels", []):
		var flat: PackedFloat32Array = row
		var poly: PackedVector2Array = PackedVector2Array()
		var count: int = int(floor(float(flat.size()) / 2.0))
		poly.resize(count)
		for i in count:
			poly[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
		if poly.size() >= 3:
			out.panels.append(poly)
	out.chosen = int(doc.get("chosen", -1))
	out.gutter = float(doc.get("gutter", GUTTER))
	out.confine = bool(doc.get("confine", true))
	if out.chosen >= out.panels.size():
		out.chosen = -1
	return out

## A copy, for the undo stack.
##
## Deep, because the undo stack holds it while the live one keeps being cut,
## and a shallow copy would have the two sharing the polygon arrays — so
## undoing would restore a list of the panels as they are now.
func copy() -> ComicPage:
	var out: ComicPage = ComicPage.new()
	for one in panels:
		out.panels.append((one as PackedVector2Array).duplicate())
	out.chosen = chosen
	out.gutter = gutter
	out.confine = confine
	return out

# ------------------------------------------------ the same, in GDScript
#
# Everything below reimplements what `ivory_comic.cpp` does, for a build
# without the extension. It is kept deliberately identical in method — the
# same half-plane clip, the same inset, the same minimum area — so that a page
# cut on a machine without the library is the same page as one cut with it.
# A layout that depends on how the app was built is not a layout anybody can
# share.
#
# The C++ side carries the test bench. These are checked against it by
# construction: when the two disagree, one of them is wrong, and the bench
# says which.

const LEAST_AREA: float = 144.0

static func _signed_area(poly: PackedVector2Array) -> float:
	var n: int = poly.size()
	if n < 3:
		return 0.0
	var sum: float = 0.0
	for i in n:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % n]
		sum += p.x * q.y - q.x * p.y
	return sum * 0.5

static func _point_in(poly: PackedVector2Array, at: Vector2) -> bool:
	var n: int = poly.size()
	if n < 3:
		return false
	var inside: bool = false
	var j: int = n - 1
	for i in n:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[j]
		if (p.y > at.y) != (q.y > at.y):
			var t: float = (at.y - p.y) / (q.y - p.y)
			if at.x < p.x + t * (q.x - p.x):
				inside = not inside
		j = i
	return inside

## Sutherland–Hodgman against one half-plane. See `IvoryComic::clip_half`,
## which carries the full explanation.
static func _clip_half(poly: PackedVector2Array, a: Vector2, b: Vector2,
		keep_left: bool) -> PackedVector2Array:
	var n: int = poly.size()
	if n < 3:
		return PackedVector2Array()
	var run: Vector2 = b - a
	if run.length_squared() < 0.000000001:
		return poly
	var side: float = 1.0 if keep_left else -1.0
	var out: PackedVector2Array = PackedVector2Array()
	for i in n:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % n]
		var sp: float = (run.x * (p.y - a.y) - run.y * (p.x - a.x)) * side
		var sq: float = (run.x * (q.y - a.y) - run.y * (q.x - a.x)) * side
		var p_in: bool = sp >= 0.0
		var q_in: bool = sq >= 0.0
		if p_in:
			out.append(p)
		if p_in != q_in:
			var t: float = sp / (sp - sq)
			out.append(Vector2(p.x + t * (q.x - p.x), p.y + t * (q.y - p.y)))
	# Consecutive duplicates arise wherever a vertex sat exactly on the line.
	# Harmless for area and containment, and fatal for the inset, which
	# divides by edge length.
	var tidy: PackedVector2Array = PackedVector2Array()
	for p in out:
		if not tidy.is_empty() \
				and (p as Vector2).distance_squared_to(tidy[-1]) < 0.0000000001:
			continue
		tidy.append(p)
	if tidy.size() > 1 \
			and tidy[0].distance_squared_to(tidy[-1]) < 0.0000000001:
		tidy.remove_at(tidy.size() - 1)
	if tidy.size() < 3:
		return PackedVector2Array()
	return tidy

## See `IvoryComic::inset`. The three validity checks at the end are there
## because the first two were not enough, and the test bench is what proved
## it — an over-inset square comes back wound the right way, contained inside
## the original and smaller than it, describing a shape that does not exist.
## What actually happened to it is that every edge reversed.
static func _inset(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	var n: int = poly.size()
	if n < 3 or by <= 0.0:
		return poly
	var turn: float = 1.0 if _signed_area(poly) > 0.0 else -1.0
	var out: PackedVector2Array = PackedVector2Array()
	for i in n:
		var prev: Vector2 = poly[(i + n - 1) % n]
		var here: Vector2 = poly[i]
		var next: Vector2 = poly[(i + 1) % n]
		var e1: Vector2 = here - prev
		var e2: Vector2 = next - here
		var l1: float = e1.length()
		var l2: float = e2.length()
		if l1 < 0.000000001 or l2 < 0.000000001:
			out.append(here)
			continue
		e1 /= l1
		e2 /= l2
		var p1: Vector2 = here + Vector2(-e1.y, e1.x) * turn * by
		var p2: Vector2 = here + Vector2(-e2.y, e2.x) * turn * by
		var denom: float = e1.x * e2.y - e1.y * e2.x
		if absf(denom) < 0.000000001:
			out.append(p1)
			continue
		var d: Vector2 = p2 - p1
		var t: float = (d.x * e2.y - d.y * e2.x) / denom
		out.append(p1 + e1 * t)
	var was: float = _signed_area(poly)
	var now: float = _signed_area(out)
	if now * was <= 0.0 or absf(now) >= absf(was) or absf(now) < LEAST_AREA:
		return PackedVector2Array()
	for p in out:
		if not _point_in(poly, p):
			return PackedVector2Array()
	for i in out.size():
		var was_dir: Vector2 = poly[(i + 1) % n] - poly[i]
		var now_dir: Vector2 = out[(i + 1) % out.size()] - out[i]
		if was_dir.dot(now_dir) < 0.0:
			return PackedVector2Array()
	return out

## Whether a cut gesture touches this panel: either end inside it, or two
## crossings of its boundary. See `IvoryComic::segment_cuts` for why touching
## is the rule.
static func _touches(poly: PackedVector2Array, a: Vector2,
		b: Vector2) -> bool:
	var n: int = poly.size()
	if n < 3:
		return false
	if _point_in(poly, a) or _point_in(poly, b):
		return true
	var crossings: int = 0
	var r: Vector2 = b - a
	for i in n:
		var p: Vector2 = poly[i]
		var s: Vector2 = poly[(i + 1) % n] - p
		var denom: float = r.x * s.y - r.y * s.x
		if absf(denom) < 0.000000000001:
			continue
		var gap: Vector2 = p - a
		var t: float = (gap.x * s.y - gap.y * s.x) / denom
		var u: float = (gap.x * r.y - gap.y * r.x) / denom
		if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
			crossings += 1
	return crossings >= 2

func _cut_line_here(a: Vector2, b: Vector2) -> bool:
	if (b - a).length_squared() < 0.000000001:
		return false
	var half: float = maxf(gutter, 0.0) * 0.5
	var next: Array = []
	var cut: int = 0
	for one in panels:
		var poly: PackedVector2Array = one
		if not _touches(poly, a, b):
			next.append(poly)
			continue
		var left: PackedVector2Array = _clip_half(poly, a, b, true)
		var right: PackedVector2Array = _clip_half(poly, a, b, false)
		if half > 0.0:
			left = _inset(left, half)
			right = _inset(right, half)
		var ok_l: bool = left.size() >= 3 \
			and absf(_signed_area(left)) >= LEAST_AREA
		var ok_r: bool = right.size() >= 3 \
			and absf(_signed_area(right)) >= LEAST_AREA
		if not ok_l and not ok_r:
			# The cut would have destroyed the panel. Left alone rather than
			# deleted — somebody who grazed a corner meant to miss.
			next.append(poly)
			continue
		if ok_l:
			next.append(left)
		if ok_r:
			next.append(right)
		cut += 1
	if cut <= 0:
		return false
	panels = next
	return true

static func shape_polygon(kind: int, box: Rect2,
		points: PackedVector2Array) -> PackedVector2Array:
	match kind:
		Cut.CIRCLE:
			var out: PackedVector2Array = PackedVector2Array()
			var mid: Vector2 = box.get_center()
			var r: Vector2 = box.size * 0.5
			for i in 48:
				var t: float = float(i) / 48.0 * TAU
				out.append(mid + Vector2(cos(t) * r.x, sin(t) * r.y))
			return out
		Cut.SQUARE:
			var s: float = minf(box.size.x, box.size.y)
			var c: Vector2 = box.get_center() - Vector2(s, s) * 0.5
			return PackedVector2Array([c, c + Vector2(s, 0.0),
				c + Vector2(s, s), c + Vector2(0.0, s)])
		Cut.RECT:
			return PackedVector2Array([box.position,
				box.position + Vector2(box.size.x, 0.0),
				box.position + box.size,
				box.position + Vector2(0.0, box.size.y)])
		Cut.FREE:
			return points
	return PackedVector2Array()

func _cut_shape_here(kind: int, box: Rect2,
		points: PackedVector2Array) -> bool:
	var cutter: PackedVector2Array = shape_polygon(kind, box, points)
	if cutter.size() < 3:
		return false
	var cut_box: Rect2 = Rect2(cutter[0], Vector2.ZERO)
	for i in range(1, cutter.size()):
		cut_box = cut_box.expand(cutter[i])
	var half: float = maxf(gutter, 0.0) * 0.5
	var next: Array = []
	var made: Array = []
	var touched: int = 0

	for one in panels:
		var poly: PackedVector2Array = one
		var host_box: Rect2 = Rect2(poly[0], Vector2.ZERO)
		for i in range(1, poly.size()):
			host_box = host_box.expand(poly[i])
		if not host_box.intersects(cut_box):
			next.append(poly)
			continue

		var inner: PackedVector2Array = poly
		for e in cutter.size():
			if inner.size() < 3:
				break
			inner = _clip_half(inner, cutter[e],
				cutter[(e + 1) % cutter.size()], true)
		if inner.size() < 3 or absf(_signed_area(inner)) < LEAST_AREA:
			next.append(poly)
			continue

		# What is left of the host, cut into rectangles by the shape's own
		# bounding edges. A shape landing in the middle of a panel would
		# otherwise leave a ring, and a ring cannot be written as one closed
		# loop of points — see `IvoryComic::split_by_shape`.
		var rest: Array = [poly]
		var bb0: Vector2 = cut_box.position
		var bb1: Vector2 = cut_box.position + cut_box.size
		var edges: Array = [
			[Vector2(bb0.x, bb0.y), Vector2(bb1.x, bb0.y)],
			[Vector2(bb1.x, bb0.y), Vector2(bb1.x, bb1.y)],
			[Vector2(bb1.x, bb1.y), Vector2(bb0.x, bb1.y)],
			[Vector2(bb0.x, bb1.y), Vector2(bb0.x, bb0.y)],
		]
		for e in edges:
			var grown: Array = []
			for piece in rest:
				var pk: PackedVector2Array = piece
				var in_side: PackedVector2Array = _clip_half(pk, e[0], e[1],
					true)
				var out_side: PackedVector2Array = _clip_half(pk, e[0], e[1],
					false)
				if in_side.size() < 3 or out_side.size() < 3:
					grown.append(pk)
					continue
				if absf(_signed_area(in_side)) >= LEAST_AREA:
					grown.append(in_side)
				if absf(_signed_area(out_side)) >= LEAST_AREA:
					grown.append(out_side)
			rest = grown

		var kept: Array = []
		for piece in rest:
			var pk2: PackedVector2Array = piece
			var mid: Vector2 = Vector2.ZERO
			for v in pk2:
				mid += v
			mid /= float(pk2.size())
			if cut_box.has_point(mid):
				continue
			kept.append(pk2)

		if half > 0.0:
			inner = _inset(inner, half)
		if inner.size() >= 3:
			made.append(inner)
		for piece in kept:
			var pk3: PackedVector2Array = piece
			if half > 0.0:
				pk3 = _inset(pk3, half)
			if pk3.size() >= 3 and absf(_signed_area(pk3)) >= LEAST_AREA:
				next.append(pk3)
		touched += 1

	if touched == 0:
		return false
	for m in made:
		next.append(m)
	panels = next
	return true
