class_name PuppetWarpDraw
extends RefCounted
## Everything the puppet warp puts on screen: the wire mesh, the pins and
## their rings.
##
## Lifted out of `puppet_warp.gd` at stage 145 because that file was six
## hundred lines past what one file is allowed here, and this is the part of
## it that has no bearing on the solve. `PuppetWarp._draw` still exists — it
## has to, it is Godot’s own callback — and delegates here.
##
## Nothing about the appearance changed in the move. The one thing that did
## is mechanical and worth naming: `draw_line` and its neighbours are methods
## on the node, so every one of them is now called through `host`.

## The mesh and the pins, drawn at a constant size on screen: a hairline stays
## a hairline and a pin stays thumb-sized whether the page is at 20% or 600%.
static func draw(host: PuppetWarp) -> void:
	if host._now_v.is_empty():
		return
	var thin: float = 1.0 / maxf(host.zoom, 0.0001)

	if host.show_mesh:
		# Twice: a dark pass first so the mesh is legible over pale artwork,
		# then a bright one over it. One colour cannot be seen against both
		# white paper and black ink, and this mesh has to sit on top of both.
		host._draw_wire(Color(0.05, 0.04, 0.03, 0.35), 2.6 * thin)
		host._draw_wire(host.IVORY_WIRE, 1.1 * thin)
		# The outline of the mesh, which is the edge of what can be pinned.
		for i in host._rim.size():
			if host._rim[i] == 0:
				continue
			for k in 4:
				var other: int = host._near[i * 4 + k]
				if other > i and host._rim[other] == 1:
					host.draw_line(host._now_v[i], host._now_v[other],
						Color("#E8D5A3"), 2.0 * thin)

	# Deepest last, so where two pins overlap a finger lands on the one in
	# front.
	var order: Array = []
	for i in host.pins.size():
		order.append(i)
	order.sort_custom(func(x: int, y: int) -> bool:
		return (host.pins[x] as PuppetWarp.Pin).depth < (host.pins[y] as PuppetWarp.Pin).depth)
	for i in order:
		host._draw_pin(host.pins[i] as PuppetWarp.Pin, thin, i == host.selected)

## The mesh, as the triangles it actually is.
##
## ## Why it was drawn as squares when it is made of triangles
##
## Because it was drawn from `_near`, the four-neighbour adjacency, which
## exists for a different job entirely: it is the graph distances are walked
## along, and distances are walked between grid neighbours. Drawing every edge
## in that graph draws the grid — and the grid is not the mesh. The mesh is
## `_tris`, and it has a diagonal through every cell that the wire never
## showed.
##
## That mattered for more than looks. The diagonal is where a cell is actually
## allowed to fold, and it alternates direction from cell to cell precisely so
## the mesh has no bias along one diagonal. Somebody looking at a grid of
## squares and trying to predict how a pull would deform it was reading a
## picture of a structure the solver does not use.
static func draw_wire(host: PuppetWarp, col: Color, width: float) -> void:
	if host._wire.is_empty():
		# No edge list — a mesh that failed to build. The grid adjacency is a
		# worse picture of the mesh than none, but it is a picture, and an
		# invisible warp is harder to reason about than an imperfect one.
		for i in host._now_v.size():
			for k in 4:
				var other: int = host._near[i * 4 + k]
				if other > i:
					host.draw_line(host._now_v[i], host._now_v[other], col, width)
		return
	var pairs: int = floori(float(host._wire.size()) / 2.0)
	for e in pairs:
		host.draw_line(host._now_v[host._wire[e * 2]], host._now_v[host._wire[e * 2 + 1]], col, width)

static func draw_pin(host: PuppetWarp, p: PuppetWarp.Pin, thin: float, chosen: bool = false) -> void:
	var r: float = 13.0 * thin
	# Where it was placed, and the line back to it: the pin's own history is
	# the clearest way to see how far the drawing has been pulled.
	if p.now.distance_squared_to(p.rest) > 1.0:
		host.draw_circle(p.rest, 4.0 * thin, Color(0.95, 0.93, 0.88, 0.30))
		host.draw_line(p.rest, p.now, Color(0.95, 0.93, 0.88, 0.34), thin)

	host.draw_circle(p.now + Vector2(1.0, 2.0) * thin, r + 2.0 * thin,
		Color(0.0, 0.0, 0.0, 0.30))
	if p.anchored:
		# An anchor is a different shape, not a different shade: shape reads
		# at a glance over any drawing, a shade does not.
		var side: float = r * 0.92
		host.draw_rect(Rect2(p.now - Vector2(side, side), Vector2(side, side) * 2.0),
			Color("#FFF8E7"), true)
		host.draw_rect(Rect2(p.now - Vector2(side, side), Vector2(side, side) * 2.0),
			Color("#8A7C58"), false, 2.5 * thin)
	else:
		host.draw_circle(p.now, r, Color("#FFF8E7"))
		host.draw_arc(p.now, r, 0.0, TAU, 24, Color("#E8D5A3"), 2.5 * thin)
	host.draw_circle(p.now, r * 0.34, Color("#8A7C58"))
	if chosen:
		host.draw_arc(p.now, r * 1.55, 0.0, TAU, 28, Color("#FFF8E7"), 2.0 * thin)
		host._draw_ring(p, thin)
	if p.depth != 0:
		# A pin that has been lifted or pushed says so with rungs: up for in
		# front, down for behind. Countable at a glance, and unlike a colour
		# it survives being drawn over any artwork.
		var step: float = 3.6 * thin
		var dir: float = -1.0 if p.depth > 0 else 1.0
		for k in absi(p.depth):
			var oy: float = dir * (r + step * float(k + 1) + 2.0 * thin)
			host.draw_line(p.now + Vector2(-r * 0.5, oy),
				p.now + Vector2(r * 0.5, oy), Color("#FFF8E7"), 2.0 * thin)

## The ring around the chosen pin: take hold of it anywhere and turn.
##
## Drawn well clear of the pin so a thumb on the ring is never a thumb on the
## pin — the two gestures sit a finger's width apart on purpose, because one
## moves the drawing and the other turns it and confusing them mid-pose is
## maddening.
##
## Three things are on it, and each earns its place:
##
## **The circle**, dark then light, for the same reason the mesh is drawn
## twice: one colour cannot be seen against both white paper and black ink,
## and this sits over both.
##
## **The grips**, four of them at the quarters, because a bare circle does not
## look like something to be held. They are only a picture — the ring answers
## anywhere along its length, which is what makes it easy to catch — but a
## hand goes to them, and a hand that goes somewhere useful has been told the
## truth.
##
## **The pointer**, a spoke from the pin out to the ring showing which way the
## pin is facing, with a faint one left at nought. Without those two a turn
## past half a circle is impossible to read: the drawing is round again and
## nothing says whether it has been turned once, or not at all, or twice.
static func draw_ring(host: PuppetWarp, p: PuppetWarp.Pin, thin: float) -> void:
	var r: float = host.ring_radius()
	host.draw_arc(p.now, r, 0.0, TAU, 64, Color(0.05, 0.04, 0.03, 0.32), 4.5 * thin)
	host.draw_arc(p.now, r, 0.0, TAU, 64, Color("#FFF8E7"), 1.8 * thin)

	# Where it started, and where it is now.
	var home: Vector2 = Vector2(1.0, 0.0)
	host.draw_line(p.now + home * (r * 0.30), p.now + home * (r * 0.92),
		Color(0.99, 0.96, 0.88, 0.22), 1.6 * thin)
	var face: Vector2 = Vector2(cos(p.turn), sin(p.turn))
	host.draw_line(p.now + face * (r * 0.28), p.now + face * (r * 0.94),
		Color("#E8D5A3"), 2.4 * thin)

	# The turn so far, drawn as the arc it has swept. A number would be
	# smaller than the finger covering it; the arc is readable under a thumb.
	if absf(p.turn) > 0.02:
		host.draw_arc(p.now, r * 0.80, minf(0.0, p.turn), maxf(0.0, p.turn),
			48, Color(0.99, 0.96, 0.88, 0.45), 3.0 * thin)

	for k in 4:
		var a: float = p.turn + float(k) * PI * 0.5
		var at: Vector2 = p.now + Vector2(cos(a), sin(a)) * r
		host.draw_circle(at, 5.2 * thin, Color(0.05, 0.04, 0.03, 0.30))
		host.draw_circle(at, 4.2 * thin, Color("#FFF8E7"))
