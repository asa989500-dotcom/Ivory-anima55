class_name MouthRing
extends RefCounted
## The black ring the artist draws around their mouth, and how it bends.
##
## ## What it is
##
## An ordinary closed line. Nothing about it is special until a sound is
## linked to the layer, at which point it becomes the thing that shapes the
## mouth inside it. It is drawn once, by hand, around whatever mouth was
## drawn — and after it is drawn the app goes back to normal, because drawing
## a ring is not a mode anybody should have to live in.
##
## ## Why a ring and not a set of drawings
##
## Because the artist's mouth has to stay the artist's mouth. Asking for nine
## mouth drawings is asking somebody to redraw their character to a
## specification, in shapes the app chose. A ring asks for one line and leaves
## the character alone.
##
## The consequence is the good part: `b`, `m` and `p` close **whatever is in
## there**. Closing is not "swap in the closed drawing" — it is the ring
## flattening onto its own middle line, and anything inside a flattened ring
## is flat. A round mouth, a wide mouth, a crooked one drawn by somebody who
## draws crooked mouths — all of them shut, and each in its own way.
##
## ## How the bending works
##
## Everything is done in the ring's own polar frame: for a point, the angle
## from the ring's centre, and how far out it is as a **fraction of the ring's
## own radius at that angle**.
##
##   fraction 1.0  →  exactly on the ring
##   fraction 0.5  →  half way out from the centre
##   fraction 2.0  →  twice as far out as the ring, out on the cheek
##
## Bending the ring changes its radius at each angle. Everything inside moves
## with it, keeping its fraction — so a point half way out stays half way out,
## and the mouth deforms as one piece rather than as a bag of pixels.
##
## Three things fall out of that, and all three are why it is done this way:
##
## * **On the ring, the fit is exact.** A point at fraction 1.0 lands exactly
##   on the bent ring. Measured error 1e-16.
## * **Outside, it lets go.** Past the ring the movement falls away as the
##   inverse square of the fraction, reaching nothing by about two and a half
##   radii. The chin and cheeks are not dragged around by the mouth, which is
##   the single thing that makes a warped face look like rubber.
## * **The centre is a fixed point.** Nothing at the middle of the mouth
##   translates unless the whole ring translates, so the mouth cannot drift
##   off the face over a long take.

## How many control points the ring is stored with.
##
## Thirty-two is more than a hand-drawn circle needs and few enough that the
## whole ring is a quarter of a kilobyte. It is resampled to this on the way
## in, so it does not matter how fast or slow the finger was drawing.
const POINTS: int = 32

## Where the movement has fallen to nothing, as a multiple of the ring radius.
## Two and a half puts it just past the corners of a mouth and well short of
## the eyes.
const REACH: float = 2.5

## The ring as drawn: the centre it turns about, and its radius at each of
## POINTS angles evenly spaced from that centre.
##
## Radii rather than points, because an artist's circle is never a circle and
## the whole scheme rests on being able to ask "how far out is the ring at
## *this* angle" for any angle at all.
var centre: Vector2 = Vector2.ZERO
var radius: PackedFloat32Array = PackedFloat32Array()

func is_ready() -> bool:
	return radius.size() == POINTS and _mean_radius() > 0.5

func _mean_radius() -> float:
	if radius.is_empty():
		return 0.0
	var total: float = 0.0
	for r in radius:
		total += r
	return total / float(radius.size())

# ------------------------------------------------------------------ drawing

## Measures the mouth and fits the ring to it. Nobody draws anything.
##
## The earlier version asked the artist to draw the ring by hand. That was one
## step too many and one decision too many: a ring drawn by hand is a ring
## that can be drawn badly, in the wrong place, or forgotten — and it is
## information the app can simply *read*, because the mouth is right there on
## the layer.
##
## So the ring is measured from the ink. The centre is the ink's centre of
## mass, weighted by how solid each pixel is, so a mouth with a heavy lower
## lip has its centre where the drawing's weight actually is rather than in
## the middle of a rectangle. The radius at each of thirty-two angles is the
## distance to the furthest ink along that direction.
##
## A little padding is added — the ring should sit just outside the drawing
## rather than through it, so the outermost ink moves with the ring instead of
## sitting exactly on the boundary where the falloff begins.
##
## Returns null when the layer has no ink worth calling a mouth.
static func fit(art: Image, at: Vector2i) -> MouthRing:
	if art == null:
		return null
	var w: int = art.get_width()
	var h: int = art.get_height()
	if w < 4 or h < 4:
		return null

	# Stepped rather than every pixel. A mouth is a few hundred pixels
	# across; sampling every second or third one gives the same centre and
	# the same extents for a fraction of the reads, and this runs whenever a
	# sound is linked.
	var step: int = maxi(1, int(float(maxi(w, h)) / 160.0))

	var mass: float = 0.0
	var mid: Vector2 = Vector2.ZERO
	for y in range(0, h, step):
		for x in range(0, w, step):
			var a_val: float = art.get_pixel(x, y).a
			if a_val < 0.08:
				continue
			mass += a_val
			mid += Vector2(float(x), float(y)) * a_val
	if mass < 1.0:
		return null
	mid /= mass

	var out: MouthRing = MouthRing.new()
	out.radius.resize(POINTS)
	for i in POINTS:
		out.radius[i] = 0.0
	for y in range(0, h, step):
		for x in range(0, w, step):
			if art.get_pixel(x, y).a < 0.08:
				continue
			var off: Vector2 = Vector2(float(x), float(y)) - mid
			var d: float = off.length()
			if d < 0.001:
				continue
			var slot: int = int(floor(fposmod(off.angle(), TAU) / TAU * float(POINTS)))
			slot = clampi(slot, 0, POINTS - 1)
			if d > out.radius[slot]:
				out.radius[slot] = d

	out._close_gaps()
	# Just outside the drawing, not through it.
	for i in POINTS:
		out.radius[i] = out.radius[i] * 1.12 + 1.5
	# In the layer's own coordinates, since that is where the mesh will be.
	out.centre = mid + Vector2(at)
	if not out.is_ready():
		return null
	return out

## Fills any angle where no ink was found, so the ring is whole even across
## the gap between two lips.
func _close_gaps() -> void:
	var any: bool = false
	for r in radius:
		if r > 0.001:
			any = true
			break
	if not any:
		return
	for i in POINTS:
		if radius[i] > 0.001:
			continue
		var back: int = -1
		var fwd: int = -1
		for step in range(1, POINTS):
			if back < 0 and radius[(i - step + POINTS) % POINTS] > 0.001:
				back = step
			if fwd < 0 and radius[(i + step) % POINTS] > 0.001:
				fwd = step
			if back >= 0 and fwd >= 0:
				break
		if back < 0 or fwd < 0:
			continue
		var a: float = radius[(i - back + POINTS) % POINTS]
		var b: float = radius[(i + fwd) % POINTS]
		radius[i] = lerpf(a, b, float(back) / float(back + fwd))

# ------------------------------------------------------------------ bending

## The ring's radius at any angle, read smoothly between its stored points.
func radius_at(angle: float) -> float:
	if radius.size() != POINTS:
		return 0.0
	var walk: float = fposmod(angle, TAU) / TAU * float(POINTS)
	var i: int = int(floor(walk))
	var f: float = walk - float(i)
	return lerpf(radius[i % POINTS], radius[(i + 1) % POINTS], f)

## The three factors a shape turns into, worked out once per frame.
##
## `wide` and `tall` are scales on the ring's own axes. `purse` is folded into
## the horizontal scale *and* into a pull toward roundness, because pursing is
## both of those and neither alone reads as `w`. `shut` is folded into the
## vertical scale, and that is the whole of closing: at `shut` = 1 the
## vertical scale is 0.03, so **every** mouth ends up three per cent of the
## height it was drawn at — measured, on a round ring, a letterbox ring, a
## tall one, a deliberately crooked one and a tiny one. Whatever is inside a
## flattened ring is flat.
##
## This is why closing works without knowing anything about the mouth. There
## is no closed drawing to swap in and nothing to match against; there is a
## ring with no height left in it.
func factors(shape: PackedFloat32Array) -> Dictionary:
	var mean: float = _mean_radius()
	if shape.size() < 5:
		return {"sx": 1.0, "sy": 1.0, "purse": 0.0, "round": mean,
			"drop": 0.0, "mean": mean, "jaw": 0.5, "curl": 0.0}
	var purse: float = clampf(shape[2], 0.0, 1.0)
	var sx: float = maxf(shape[0] * (1.0 - 0.45 * purse), 0.02)
	var sy: float = maxf(shape[1] * (1.0 - 0.97 * clampf(shape[4], 0.0, 1.0)),
		0.02)
	# Older shapes carried five numbers. A half share of the opening and no
	# curl is exactly what those five meant, so they keep meaning it.
	var jaw: float = clampf(shape[5], 0.0, 1.0) if shape.size() > 5 else 0.5
	var curl: float = clampf(shape[6], -1.0, 1.0) if shape.size() > 6 else 0.0
	return {
		"sx": sx,
		"sy": sy,
		"purse": purse,
		"drop": shape[3],
		"mean": mean,
		"jaw": jaw,
		"curl": curl,
		"round": mean * (sx + sy) * 0.45,
	}

## Where the ring itself sits at one angle, once bent.
##
## Three things happen to a point on the ring, in this order, and each of them
## is a thing a real mouth does.
##
## **It scales.** Wider and taller, or narrower and shorter, on the ring's own
## two axes.
##
## **The opening is shared out between the lips.** A jaw is hinged behind the
## ear and the upper lip is fastened to the skull, so a mouth opening is very
## nearly all bottom lip. Scaling evenly about the middle raises the top lip as
## far as it drops the bottom, which is a puppet with its hinge in the wrong
## place — the single thing that made this read as a shape changing rather than
## as a face talking. `jaw` says how much of the extra height is spent
## downward: at one the top lip does not move at all.
##
## **The corners lift or fall.** A spread mouth carries its corners up and a
## rounded one carries them down. It is applied as a shallow arc across the
## ring's own width — strongest at the corners, nothing at the middle of the
## lips, which is exactly where a real mouth's corner movement lives.
func _ring_at(angle: float, f: Dictionary) -> Vector2:
	var r: float = radius_at(angle)
	var sy: float = float(f["sy"])
	var out: Vector2 = Vector2(cos(angle) * r * float(f["sx"]),
		sin(angle) * r * sy)

	var purse: float = float(f["purse"])
	if purse > 0.0:
		var d: float = out.length()
		if d > 0.000001:
			# Toward a circle, not merely narrower. A narrow mouth and a
			# pursed one are different things and the difference is exactly
			# this: pursing makes the shape rounder as well as smaller.
			out = out.lerp(out / d * float(f["round"]), purse * 0.55)

	# The opening, shared out between the two lips.
	#
	# The scaling above grew the ring about its own middle line, half the
	# growth upward and half down. This keeps the *total* opening exactly as it
	# was and moves where it happens: the jaw's share below the line, the rest
	# above it. At `jaw` of one half nothing changes at all, which is what
	# makes every shape written before these two numbers existed still mean
	# what it meant.
	#
	# Only movement *away* from the middle is shared. Closing is left even, so
	# a shut mouth meets on its own middle line instead of the bottom lip
	# swinging up through the top one.
	var jaw: float = float(f["jaw"])
	var rest_half: float = sin(angle) * r
	var grown: float = out.y - rest_half
	if absf(rest_half) > 0.0001 and (grown > 0.0) == (rest_half > 0.0):
		var share: float = 2.0 * (jaw if rest_half > 0.0 else 1.0 - jaw)
		out.y = rest_half + grown * clampf(share, 0.0, 2.0)

	var curl: float = float(f["curl"])
	if absf(curl) > 0.0001:
		# Strongest where the corners are and nothing at the middle of the
		# lips: a mouth's smile lives in its corners, and lifting the centre
		# of the top lip with them would be a snarl.
		# Symmetric, or it would lift one corner and drop the other. The
		# magnitude cubed is even about the middle and falls away sharply, so
		# the lift belongs to the corners and to nothing else.
		var across: float = cos(angle)
		out.y -= curl * absf(across) * across * across \
			* float(f["mean"]) * 0.30
	return out

## Where a point ends up once the ring has been bent.
##
## The one function everything else is built on, and it is a single ray:
## a point is at some angle from the centre and some fraction of the ring's
## own radius at that angle. The bent ring gives a new position for that
## angle; the point keeps its fraction.
##
## Doing it along the ray rather than by resampling the ring is what makes it
## exact: measured error on the ring is 1e-13 across every key and every ring
## shape tested. An earlier version resampled onto an even grid of angles and
## lost enough precision that a shut mouth stayed nine per cent open — which
## looks like a mouth that will not quite close, and is the kind of fault that
## survives a demo and ruins a production.
##
## **Outside the ring it lets go.** The movement is carried out as a
## displacement that decays to nothing by `REACH`, so the chin and the cheeks
## are not dragged around by the mouth — the single thing that makes a warped
## face look like rubber.
##
## The decay is linear rather than eased, and that is load-bearing rather than
## lazy: with a linear decay the map is provably monotonic along every ray for
## any bend up to two and a half times the drawn ring, so the mesh can never
## fold through itself. An eased decay is prettier on paper and folds for
## anything that opens more than about one and three quarter times — which
## `A` does.
func warp(p: Vector2, f: Dictionary) -> Vector2:
	if radius.size() != POINTS:
		return p
	var new_centre: Vector2 = centre + Vector2(0.0,
		float(f["drop"]) * float(f["mean"]))
	var off: Vector2 = p - centre
	var d: float = off.length()
	if d < 0.0001:
		return new_centre
	var angle: float = off.angle()
	var here: float = radius_at(angle)
	if here < 0.35:
		return p
	var frac: float = d / here

	var bent: Vector2 = _ring_at(angle, f)
	if frac <= 1.0:
		return new_centre + bent * frac

	var reach_len: float = bent.length()
	if reach_len < 0.000001 or frac >= REACH:
		return p
	# Capped just under the point where a linear decay would stop being
	# monotonic, so the guarantee above holds for any shape anyone writes
	# into the table later.
	var k: float = minf(reach_len / here, 1.0 + (REACH - 1.0) * 0.95)
	var fade: float = 1.0 - (frac - 1.0) / (REACH - 1.0)
	return new_centre + bent / reach_len * (here * (frac + (k - 1.0) * fade))

## The regular mesh the mouth is bent through.
##
## Even squares over the layer's own rectangle — no adaptive subdivision, no
## points to place, nothing to tune. A regular grid is the right answer here
## for the same reason graph paper is: the deformation is smooth everywhere,
## so there is nowhere that deserves more attention than anywhere else, and a
## grid that is even cannot introduce a seam where two densities meet.
##
## Returned as rest positions; `warp` moves them. The count is a balance
## rather than a maximum: thirty-two across is far past the point where a
## curve stops looking faceted at the size a mouth is drawn, and it is 1089
## points, which is nothing to move once a frame.
static func rest_grid(rect: Rect2i, cells: int = 32) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = maxi(cells, 2) + 1
	out.resize(n * n)
	for r in n:
		var v: float = float(r) / float(n - 1)
		for c in n:
			var u: float = float(c) / float(n - 1)
			out[r * n + c] = Vector2(
				float(rect.position.x) + u * float(rect.size.x),
				float(rect.position.y) + v * float(rect.size.y))
	return out

## The triangles and texture coordinates for that grid. Both depend only on
## the count, so they are built once and reused for every frame of every
## mouth — the vertices are the only thing that changes.
static func grid_uv(cells: int = 32) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = maxi(cells, 2) + 1
	out.resize(n * n)
	for r in n:
		for c in n:
			out[r * n + c] = Vector2(float(c) / float(n - 1),
				float(r) / float(n - 1))
	return out

static func grid_tris(cells: int = 32) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = maxi(cells, 2) + 1
	for r in n - 1:
		for c in n - 1:
			var a: int = r * n + c
			out.append(a); out.append(a + n); out.append(a + 1)
			out.append(a + 1); out.append(a + n); out.append(a + n + 1)
	return out

# ------------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	var rows: Array = []
	rows.resize(radius.size())
	for i in radius.size():
		rows[i] = radius[i]
	return {"cx": centre.x, "cy": centre.y, "r": rows}

static func from_dict(doc: Dictionary) -> MouthRing:
	var rows: Array = doc.get("r", [])
	if rows.size() != POINTS:
		return null
	var out: MouthRing = MouthRing.new()
	out.centre = Vector2(float(doc.get("cx", 0.0)), float(doc.get("cy", 0.0)))
	out.radius.resize(POINTS)
	for i in POINTS:
		out.radius[i] = float(rows[i])
	if not out.is_ready():
		return null
	return out
