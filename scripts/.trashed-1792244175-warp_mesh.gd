class_name WarpMesh
extends RefCounted
## How a warp mesh is laid over a drawing, and how distance is measured across
## it.
##
## Lifted out of `puppet_warp.gd`, which had grown past what one file should
## hold, and lifted along a real seam: everything here answers a question
## about the *mesh* — where it should exist, and how far apart two parts of it
## are. Nothing here knows what a pin is or how one bends anything.
##
## Both of the faults that made a drawing come apart under Puppet Warp lived
## in these two functions, and the reasoning for each fix is written at the
## function it belongs to.

## Unreachable — a piece of drawing no path connects to.
const FAR: float = 1.0e20
## How many samples across each cell the ink map reads before deciding.
##
## Two, so a cell is judged on four readings rather than one. The cost is a
## fraction of a second once, when a warp opens; what it buys is that a stroke
## crossing a corner of a cell is seen rather than missed.
const INK_OVERSAMPLE: int = 2

## Which cells the drawing actually reaches.
##
## ## This is where the tearing came from
##
## The map used to be made by shrinking the drawing straight down to one pixel
## per cell in a single `resize` with `INTERPOLATE_BILINEAR`, and reading the
## alpha of each. On a complex drawing that quietly threw pieces away.
##
## Bilinear reads a two-by-two neighbourhood around each sample point. Going
## from a thousand pixels down to thirty-four cells is a shrink to about three
## per cent, and at that ratio the four pixels it reads are thirty apart —
## everything between them is never looked at. Microsoft's own imaging
## documentation puts the limit plainly: bilinear does no pre-filtering and is
## unsuitable below half size. This was running at a thirtieth.
##
## So a hairline, a hatch, an eyelash, a fine outline — anything a pixel or
## two wide — fell between the samples and its cells came back empty. Empty
## cells get **no triangles**. No triangles means that part of the drawing is
## not in the mesh at all, and what is not in the mesh is not drawn: the
## stroke vanishes and the artwork around it comes apart. The more detail a
## drawing had, the more of it was lost, which is exactly the way the fault
## presented.
##
## ## What it does now
##
## Three steps, and each is doing a different job:
##
## 1. **Halving.** The drawing is halved repeatedly. A halving is the one
##    ratio at which bilinear is honest — the four pixels it reads are exactly
##    the four it should average — so a stack of halvings is a true box
##    filter, and a stroke one pixel wide survives every step as a fainter but
##    real value instead of being skipped.
## 2. **A maximum, not an average.** The last reduction, from four samples per
##    cell down to one, takes the **largest** alpha rather than the mean. The
##    question being asked is "is there any drawing in this cell", and the
##    answer to that is a maximum. An average can wash a stroke out; a maximum
##    cannot.
## 3. **A floor that knows the scale.** A single opaque pixel averaged over a
##    cell of a thousand is an alpha of one part in a thousand, which is under
##    the old fixed floor of 0.004 — so even a correct average would have been
##    thresholded away. The floor is now derived from how many pixels a cell
##    covers, so it always means the same thing: about half a pixel of ink.
##
## The errors here are not symmetrical, and that is what settles every
## judgement call above. A cell wrongly kept costs two triangles nobody
## notices. A cell wrongly dropped tears a hole in the drawing. Every doubt is
## resolved towards keeping.
static func ink_map(source: Image, cells_x: int, cells_y: int,
		ink_floor: float) -> PackedByteArray:
	var raw: PackedByteArray = PackedByteArray()
	if cells_x < 1 or cells_y < 1 or source == null:
		# Nothing to measure. An empty map means "mesh everywhere", which is
		# the safe answer — a warp over a blank patch does nothing, where a
		# resize to zero brings the whole app down.
		raw.resize(maxi(cells_x * cells_y, 1))
		raw.fill(1)
		return raw
	raw.resize(cells_x * cells_y)

	var probe: Image = source.duplicate()
	if probe.get_width() < 1 or probe.get_height() < 1:
		raw.fill(1)
		return raw

	# How many source pixels one cell covers, before any of this. Needed for
	# the floor, and it has to be measured now because `probe` is about to
	# stop being the size it started at.
	var per_cell: float = maxf(
		float(probe.get_width()) * float(probe.get_height())
		/ maxf(float(cells_x * cells_y), 1.0), 1.0)

	# --- 1 and 2: down to four samples across each cell, by halving ---
	var fine_x: int = cells_x * INK_OVERSAMPLE
	var fine_y: int = cells_y * INK_OVERSAMPLE
	while probe.get_width() >= fine_x * 2 and probe.get_height() >= fine_y * 2 \
			and probe.get_width() > 2 and probe.get_height() > 2:
		probe.resize(maxi(int(probe.get_width() * 0.5), 1),
			maxi(int(probe.get_height() * 0.5), 1),
			Image.INTERPOLATE_BILINEAR)
	if probe.get_width() != fine_x or probe.get_height() != fine_y:
		# Whatever is left of the ratio. Lanczos rather than bilinear: it is
		# the slowest mode and the one Godot's own documentation names as
		# giving the best results when downscaling, and this runs once when a
		# warp opens, not per frame.
		probe.resize(fine_x, fine_y, Image.INTERPOLATE_LANCZOS)

	# --- 3: the floor, in proportion to what a cell covers ---
	var floor_a: float = clampf(0.45 / per_cell, 0.00002, ink_floor)
	var any: bool = false
	for y in cells_y:
		for x in cells_x:
			var most: float = 0.0
			for sy in INK_OVERSAMPLE:
				for sx in INK_OVERSAMPLE:
					most = maxf(most, probe.get_pixel(
						x * INK_OVERSAMPLE + sx,
						y * INK_OVERSAMPLE + sy).a)
			var on: bool = most > floor_a
			raw[y * cells_x + x] = 1 if on else 0
			any = any or on
	if not any:
		raw.fill(1)
		return raw

	# One ring outwards, so the mesh always extends a little past the ink and
	# an edge is never the very last row of vertices.
	var grown: PackedByteArray = raw.duplicate()
	for y in cells_y:
		for x in cells_x:
			if raw[y * cells_x + x] != 0:
				continue
			var touch: bool = false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= cells_x or ny >= cells_y:
						continue
					if raw[ny * cells_x + nx] != 0:
						touch = true
						break
				if touch:
					break
			if touch:
				grown[y * cells_x + x] = 1
	return grown

## Relaxes a distance field across the mesh until no route improves.
##
## Sweeps alternate direction so a distance travelling against the raster
## order does not need one pass per step.
static func spread(far: PackedFloat32Array, near: PackedInt32Array,
		rest_v: PackedVector2Array) -> void:
	var count: int = far.size()
	for round_i in 64:
		var moved: bool = false
		var forward: bool = round_i % 2 == 0
		for step in count:
			var i: int = step if forward else count - 1 - step
			var here: float = far[i]
			if here >= FAR:
				continue
			for k in 4:
				var other: int = near[i * 4 + k]
				if other < 0:
					continue
				var walk: float = here + rest_v[i].distance_to(rest_v[other])
				if walk < far[other] - 0.0001:
					far[other] = walk
					moved = true
		if not moved:
			return

## Gives a piece of drawing no path reaches something rather than nothing.
##
## ## The second half of the tearing
##
## A complex drawing is rarely one connected shape. Strokes that do not quite
## touch, a dot over an i, a highlight sitting inside an outline, an eye
## floating in a face — each is its own island in the mesh, because the mesh
## is built on ink and there is no ink between them.
##
## Walking the mesh could not reach any of them. They stayed at `FAR`, which
## meant every pin weighed nothing there, which meant `_warp` handed the
## vertex straight back where it started. Drag a pin and the connected part of
## the drawing bent while every loose piece stayed exactly where it was —
## bending a face and leaving its eyes behind in mid-air. That is coming
## apart, and again it got worse the more pieces a drawing had.
##
## ## Why a straight line is the right answer here and only here
##
## Walking the mesh exists to stop a pull crossing a gap the drawing does not
## cross — the two arms of a **U**, close across the mouth and far apart
## through the bend. That reasoning still holds and is untouched: the arms of
## a U *are* connected, so they are still measured the long way round.
##
## But when there is no path at all, there is no long way round to measure and
## no information left except proximity. So the straight line is used, plus a
## fixed cost for the crossing. The cost is what keeps the two kinds of
## distance in their proper order: ink you can walk to always outranks ink you
## have to jump to, so a piece stays with the pin it belongs to rather than
## with one that happens to be nearer as the crow flies.
##
## The result is that a loose piece is *carried* by the pins around it instead
## of being left behind. Which is what a person expects — they are moving a
## drawing, not a graph.
static func bridge_islands(far: PackedFloat32Array, from_at: Vector2,
		rest_v: PackedVector2Array, bridge: float) -> void:
	for i in far.size():
		if far[i] < FAR:
			continue
		far[i] = from_at.distance_to(rest_v[i]) + bridge

## One pass of Laplacian smoothing over a warp mesh.
##
## A **negative** amount pushes each vertex away from its neighbours instead of
## towards them, and that is the whole of Taubin's trick: an inward pass
## followed by a slightly larger outward one smooths without shrinking. Plain
## Laplacian smoothing contracts — a circle of points run through it enough
## times becomes a smaller circle, and on a warp that reads as the drawing
## quietly losing its size as more pins are added.
##
## `hold` keeps the pass off the ground near a pin: a pinned neighbourhood is
## meant to be exactly where the pin put it, and smoothing it would be undoing
## the instruction that was just given.
##
## A vertex on the rim never averages with one inside it. The edge of the mesh
## is the edge of the drawing, and letting the boundary pull inward towards the
## interior is another way of contracting — one that shows as the outline
## fraying rather than the whole shape shrinking.
static func smooth_pass(now: PackedVector2Array, fix: PackedVector2Array,
		near: PackedInt32Array, rim: PackedByteArray,
		hold: PackedFloat32Array, amount: float) -> void:
	for i in now.size():
		fix[i] = Vector2.ZERO
	for i in now.size():
		var sum: Vector2 = Vector2.ZERO
		var n: int = 0
		for k in 4:
			var other: int = near[i * 4 + k]
			if other < 0:
				continue
			if rim[i] == 1 and rim[other] == 0:
				continue
			sum += now[other]
			n += 1
		if n == 0:
			continue
		fix[i] = (sum / float(n) - now[i]) * amount * (1.0 - hold[i])
	for i in now.size():
		now[i] += fix[i]
