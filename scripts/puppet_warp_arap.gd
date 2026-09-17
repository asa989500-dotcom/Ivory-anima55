class_name PuppetWarpArap
extends RefCounted
## The as-rigid-as-possible relaxation the puppet warp runs after its pins,
## plus the painting order that decides which folded limb is on top.
##
## Lifted out of `puppet_warp.gd` at stage 145, unchanged, to bring that file
## back under the size the project allows. `PuppetWarp` keeps a one-line
## delegate for each, so nothing that called them moved.
##
## Worth reading beside `native/ivory/src/ivory_deform.cpp`, which does the
## same job for the Character 360 rig in C++ and documents the reasoning at
## length. Same idea in both places: the pins or the bones place the points,
## and a few passes over the edges pull the shape back to something that has
## not been torn.

## The local step: the rotation that best explains how each vertex's own
## neighbourhood has moved.
static func arap_fit(host: PuppetWarp) -> void:
	var n: int = host._rest_v.size()
	if host._rot_c.size() != n:
		host._rot_c.resize(n)
		host._rot_s.resize(n)
	for i in n:
		var along: float = 0.0
		var across: float = 0.0
		var base: int = i * 4
		var rest_i: Vector2 = host._rest_v[i]
		var now_i: Vector2 = host._now_v[i]
		for k in 4:
			var j: int = host._near[base + k]
			if j < 0:
				continue
			var e0: Vector2 = rest_i - host._rest_v[j]
			var e1: Vector2 = now_i - host._now_v[j]
			along += e0.x * e1.x + e0.y * e1.y
			across += e0.x * e1.y - e0.y * e1.x
		var mag: float = sqrt(along * along + across * across)
		if mag < 0.000000001:
			# A vertex whose neighbourhood has collapsed to a point has no
			# rotation to find. The honest answer is none, not a random one.
			host._rot_c[i] = 1.0
			host._rot_s[i] = 0.0
		else:
			host._rot_c[i] = along / mag
			host._rot_s[i] = across / mag

## The global step: one Gauss–Seidel sweep of `L p = b`.
##
## `pull` is how far towards the answer each vertex is allowed to move, and it
## is scaled down by `_hold` — how completely a pin owns this vertex. Right
## under a pin, MLS is exact and ARAP has nothing to add; out in the ground
## between pins, `_hold` is nothing and ARAP governs entirely. That single
## multiplication is what keeps the two solvers from arguing.
static func arap_sweep(host: PuppetWarp, backwards: bool, pull: float) -> void:
	var n: int = host._rest_v.size()
	if host._rot_c.size() != n or host._hold.size() != n:
		return
	for step in n:
		var i: int = (n - 1 - step) if backwards else step
		if host._pinned[i] == 1:
			continue
		var c_i: float = host._rot_c[i]
		var s_i: float = host._rot_s[i]
		var rest_i: Vector2 = host._rest_v[i]
		var base: int = i * 4
		var want: Vector2 = Vector2.ZERO
		var count: int = 0
		for k in 4:
			var j: int = host._near[base + k]
			if j < 0:
				continue
			var e0: Vector2 = rest_i - host._rest_v[j]
			# The average of the two rotations, applied to the rest edge. Not
			# normalised back to a rotation on purpose: this is the mean of two
			# rotated copies of the same vector, which is what the energy asks
			# for, and re-normalising it would be answering a different
			# question.
			var c_m: float = (c_i + host._rot_c[j]) * 0.5
			var s_m: float = (s_i + host._rot_s[j]) * 0.5
			want += host._now_v[j] + Vector2(e0.x * c_m - e0.y * s_m,
				e0.x * s_m + e0.y * c_m)
			count += 1
		if count == 0:
			continue
		var share: float = clampf(pull * (1.0 - host._hold[i]), 0.0, 1.0)
		if share <= 0.001:
			continue
		host._now_v[i] = host._now_v[i].lerp(want / float(count), share)

## Smoothing that does not shrink the drawing.
##
## Pulling every vertex towards the average of its neighbours turns the corner
## where two triangles meet into a curve running through both — but plain
## **Laplacian smoothing** does not only smooth, it **contracts**: run it on a
## circle and you get a smaller circle, and the more pins and smoothing asked
## for the more visible that got. **Taubin** is the standard answer: follow
## every inward pass with an outward one that pushes back slightly more. On a
## ring of sixty-four points over sixty passes, Laplacian alone takes a radius
## of 100 down to 94.4; Taubin leaves it at 100.2. Outline vertices are
## averaged only against other outline vertices, never inward — a silhouette
## relaxed towards the middle of the drawing would slowly eat itself.
static func relax_smooth(host: PuppetWarp) -> void:
	if host.smoothing <= 0.001:
		return
	host._smooth_by(host.smoothing * 0.5)
	host._smooth_by(-host.smoothing * 0.5 * host.INFLATE)

## One pass of Laplacian smoothing. A negative amount pushes outward instead,
## which is the whole of Taubin's trick. See `WarpMesh.smooth_pass`.
static func smooth_by(host: PuppetWarp, amount: float) -> void:
	WarpMesh.smooth_pass(host._now_v, host._fix, host._near, host._rim, host._hold, amount)

## Gives every triangle back the area it started with.
##
## ## Superseded, and kept for the record
##
## This is no longer called. It was the patch for MLS collapsing the ground
## between two pins, and it restored *area* with no opinion about *shape* — so
## a square squashed into a thin diamond was handed its area back as a fatter
## diamond rather than as a square. The as-rigid-as-possible solve above
## replaces it with something that is about shape by construction. Left here
## because the reasoning below is still the clearest statement of what the
## problem was.
##
## Rigid MLS never stretches a triangle on its own — it fits a rotation and
## nothing else. What squashes the drawing is the blend *between* two pins
## pulling different ways: each region is rigid, and the ground between them
## takes up the difference by collapsing. Pull two pins together and the
## drawing between them thins out.
##
## For each triangle, take how much area it has lost, work out which direction
## each corner would have to move to give that area back fastest, and move
## them that way by the smallest amount that does it. Because area is width
## times height, a triangle squeezed one way is handed its area back as width
## in the other — the behaviour wanted, arrived at by arithmetic rather than
## bolted on as a rule.
static func relax_area(host: PuppetWarp) -> void:
	if host.area_keep <= 0.001 or host._rest_area.is_empty():
		return
	# --- and never while the drawing is being squashed ---
	#
	# This pass hands a triangle back the area it lost. That is exactly right
	# under a rigid fit, where a triangle losing area means the mesh is
	# folding and needs pushing apart. Under an affine fit it is precisely
	# backwards: a triangle *should* lose area when the drawing is compressed,
	# and giving it back is undoing the squash the person just made — the
	# drawing springs out sideways as fast as it is pushed in, which was the
	# whole complaint about pulling one pin onto another.
	if host.fit_mode != host.Fit.RIGID:
		return
	for i in host._now_v.size():
		host._fix[i] = Vector2.ZERO
	var count: int = floori(float(host._tris.size()) / 3.0)
	for t in count:
		var ia: int = host._tris[t * 3]
		var ib: int = host._tris[t * 3 + 1]
		var ic: int = host._tris[t * 3 + 2]
		var a: Vector2 = host._now_v[ia]
		var b: Vector2 = host._now_v[ib]
		var c: Vector2 = host._now_v[ic]
		var err: float = PuppetWarp._area(a, b, c) - host._rest_area[t]
		if absf(err) < 0.0001:
			continue
		# Which way each corner moves to change the area quickest.
		var ga: Vector2 = Vector2(b.y - c.y, c.x - b.x) * 0.5
		var gb: Vector2 = Vector2(c.y - a.y, a.x - c.x) * 0.5
		var gc: Vector2 = Vector2(a.y - b.y, b.x - a.x) * 0.5
		var denom: float = ga.length_squared() + gb.length_squared() \
			+ gc.length_squared()
		if denom < 0.000001:
			continue
		# `push` rather than `scale`: this class is a Node2D and `scale` is
		# one of its own properties, so a local of that name hides it.
		var push: float = -err / denom * host.area_keep * 0.5
		host._fix[ia] += ga * push * (1.0 - host._hold[ia])
		host._fix[ib] += gb * push * (1.0 - host._hold[ib])
		host._fix[ic] += gc * push * (1.0 - host._hold[ic])
	for i in host._now_v.size():
		host._now_v[i] += host._fix[i]

## Puts the triangles in the order they should be painted.
##
## A flat mesh has no depth buffer — later simply covers earlier. So when a
## limb is folded across a body, which one is on top is decided by nothing at
## all, and the two sets of triangles interleave. Each triangle takes the
## depth of the pins nearest it, weighted the way the warp weights them, and
## the list is sorted lowest first. Sorting happens when the depths change,
## not while a pin is dragged: a triangle's depth is read from where it
## started, so a drag cannot alter it.
static func order_triangles(host: PuppetWarp) -> void:
	host._order_dirty = false
	var count: int = floori(float(host._tris.size()) / 3.0)
	if count == 0:
		return

	var mixed: bool = false
	for p in host.pins:
		if (p as PuppetWarp.Pin).depth != 0:
			mixed = true
			break
	if not mixed or host.pins.is_empty() or host._reach.size() != host.pins.size():
		# Everything on one plane: the grid's own order is correct and costs
		# nothing.
		host._index = host._tris.duplicate()
		return

	var soft2: float = host.softness * host.softness
	var ranked: Array = []
	ranked.resize(count)
	for t in count:
		var total: float = 0.0
		var deep: float = 0.0
		for i in host.pins.size():
			var d: float = 0.0
			for k in 3:
				d += (host._reach[i] as PackedFloat32Array)[host._tris[t * 3 + k]]
			d /= 3.0
			if d >= host.FAR:
				continue
			var w: float = 1.0 / (d * d + soft2)
			total += w
			deep += w * float((host.pins[i] as PuppetWarp.Pin).depth)
		ranked[t] = [deep / maxf(total, 0.000001), t]
	ranked.sort_custom(func(x: Array, y: Array) -> bool:
		return float(x[0]) < float(y[0]))

	var out: PackedInt32Array = PackedInt32Array()
	out.resize(host._tris.size())
	for k in count:
		var t: int = int((ranked[k] as Array)[1])
		out[k * 3] = host._tris[t * 3]
		out[k * 3 + 1] = host._tris[t * 3 + 1]
		out[k * 3 + 2] = host._tris[t * 3 + 2]
	host._index = out
