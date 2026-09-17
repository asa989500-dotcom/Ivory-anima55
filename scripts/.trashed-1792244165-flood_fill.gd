class_name FloodFill
extends RefCounted
## Fills only what is actually enclosed, and does it on a small map.
##
## The trick every paint app uses: solving the flood at full resolution is
## wasteful, because the answer is a shape, and a shape survives shrinking.
## So the map is shrunk sixteen-fold and solved there — but shrunk with a
## rule that protects hairlines: a small cell counts as linework if *any*
## pixel inside it is linework. A one-pixel line does not merely survive the
## shrink, it gets sturdier, which closes hairline gaps for free.
##
## The answer is then blown back up and refined against the real pixels, so
## the fill slides under the soft edge of every stroke with no white halo.
##
## Cost drops from millions of operations to tens of thousands, and it scales
## with the size of the area, not the size of the canvas.

## The window can be generous because the solve happens on a shrunken map
## whose size is held constant: a bigger reach costs a bigger first pass,
## not a bigger search.
## Big enough to cover a whole page at a normal zoom. The cost of a wider
## window is one linear pass, not a wider search — the search always happens
## on a map of about COARSE_TARGET across, whatever the window.
const MAX_SIDE: int = 3000     # working window, in canvas pixels
const COARSE_TARGET: int = 200 # the shrunken map is always about this wide
## Generous on purpose. Anti-aliased edges and lightly textured brushes put
## a spread of near-identical values around every flat area, and a tight
## tolerance turns each of those into a wall the colour cannot pass.
## The default, kept as the shipping value. The live number comes from the
## app state so it can be tuned per drawing.
const TOLERANCE: int = 56      # 0-255 per channel

static func tolerance_now() -> int:
	if tolerance_hint >= 0:
		return clampi(tolerance_hint, 2, 200)
	return clampi(App.fill_tolerance, 2, 200)

static func creep_now() -> int:
	if creep_hint >= 0:
		return clampi(creep_hint, 0, 6)
	return clampi(App.fill_creep, 0, 6)

## Set by the tests, which run without the autoloaded settings object. Left
## at -1 everywhere else, and then the user's own dials are what decide.
static var tolerance_hint: int = -1
static var creep_hint: int = -1

# ------------------------------------------------------------- diagnosis
#
# The complaint has been "the fill leaks" and "the fill stops short", and
# neither could be answered because the run left no trace of what it did. Two
# fills that look identical on screen can have taken completely different
# routes: one found the shape closed and filled it, the other found it open,
# bridged a two-cell gap and filled it anyway. Which of those happened decides
# whether the bug is in the bridging or in the tolerance, and until now there
# was no way to tell from the outside.
#
# So every run records what it did. `Perf.report()` prints the last one, and a
# screenshot of that turns "it leaked" into a line I can act on.

## What the last fill did:
##   outcome  filled | open | blocked-seed | unreadable | nothing
##   bridge   how wide a gap had to be bridged: 0 means the shape was closed
##   window   the search window in canvas pixels
##   scale    how hard the map was shrunk to solve on
##   pixels   how many pixels were painted
##   ms       how long the whole thing took
static var last: Dictionary = {}

static func _gave_up(why: String, started: int, extra: Dictionary = {}) -> Variant:
	last = {"outcome": why, "bridge": -1, "ms":
		float(Time.get_ticks_usec() - started) / 1000.0}
	last.merge(extra, true)
	Perf.since("fill", started)
	return null

## The last fill in one line, for the diagnostics sheet.
static func describe_last() -> String:
	if last.is_empty():
		return "fill: nothing yet"
	return "fill: %s, bridge %d, window %s, shrink %d, %d px, %.1f ms" % [
		String(last.get("outcome", "?")), int(last.get("bridge", -1)),
		String(last.get("window", "?")), int(last.get("scale", 0)),
		int(last.get("pixels", 0)), float(last.get("ms", 0.0))]
## In shrunken cells. Shrinking already thickens the linework, and these go
## further: three attempts, each willing to bridge a wider gap than the last.
const COARSE_BRIDGES: Array = [0, 1, 2, 3]
## Above this a pixel counts as solid linework the fill may tuck under but
## must never cover.
const CORE_ALPHA: int = 128

## How wide a working window this device can afford right now.
static func _window_side() -> int:
	if Perf.tier == Perf.Tier.LOW:
		return 1400
	if Perf.tier == Perf.Tier.MEDIUM:
		return 2200
	return MAX_SIDE

static func run(surface_reader: Object, world_point: Vector2, ink: Color,
		view_size: Vector2, zoom: float, page: Vector2 = Vector2.ZERO) -> Variant:
	var started: int = Time.get_ticks_usec()
	# Whatever is on screen, but never less than a page: filling a shape the
	# user has zoomed into should not fail because its far edge is off view.
	var seen_w: int = int(view_size.x / maxf(zoom, 0.001))
	var seen_h: int = int(view_size.y / maxf(zoom, 0.001))
	# The window is bounded, but the bound has to move with the device. Three
	# thousand a side is nine million cells, and the fill holds several byte
	# maps of that size at once — comfortable on a good phone, and on a phone
	# already dropping frames it is the allocation that ends the session. The
	# search itself does not get any smaller: it always runs on a coarse map of
	# about `COARSE_TARGET` across, so a tighter window costs reach, not
	# accuracy, and reach past the page edge was never being used.
	var side: int = _window_side()
	var w: int = clampi(maxi(seen_w, int(page.x)), 128, side)
	var h: int = clampi(maxi(seen_h, int(page.y)), 128, side)
	# Shrink harder for a bigger window, so the search itself never grows.
	var scale: int = clampi(int(round(float(maxi(w, h)) / float(COARSE_TARGET))), 2, 12)
	w -= w % scale
	h -= h % scale
	var origin: Vector2i = Vector2i(
		int(floor(world_point.x)) - int(float(w) * 0.5),
		int(floor(world_point.y)) - int(float(h) * 0.5))

	var src: Image = surface_reader.read_region(Rect2i(origin, Vector2i(w, h)))
	if src == null:
		return _gave_up("unreadable", started)
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = src.get_data()

	var sx: int = int(floor(world_point.x)) - origin.x
	var sy: int = int(floor(world_point.y)) - origin.y
	if sx < 0 or sy < 0 or sx >= w or sy >= h:
		return _gave_up("outside", started)

	# Both went missing when the old upscaling path was cut out; the new one
	# still leans on them. `seed_index` rather than `seed`, because `seed`
	# is a built-in function in GDScript and an undeclared local of that
	# name silently resolves to it — which is exactly what the "invalid
	# index type Callable" message was reporting.
	var total: int = w * h
	var seed_index: int = sy * w + sx

	var o: int = seed_index * 4
	var sr: int = data[o]
	var sg: int = data[o + 1]
	var sb: int = data[o + 2]
	var sa: int = data[o + 3]

	# --- one full-resolution pass: who matches the seed, and the small map ---
	var qw: int = floori(float(w) / float(scale))
	var qh: int = floori(float(h) / float(scale))
	var same: PackedByteArray = PackedByteArray()
	same.resize(w * h)
	var blocked: PackedByteArray = PackedByteArray()
	blocked.resize(qw * qh)
	blocked.fill(0)

	for y in range(h):
		var row: int = y * w
		var qrow: int = floori(float(y) / float(scale)) * qw
		for x in range(w):
			var i: int = row + x
			if _same(data, i * 4, sr, sg, sb, sa):
				same[i] = 1
			else:
				# The one line that decides whether this tool works at all.
				#
				# It used to sit outside the `else`, so *every* coarse cell
				# was marked as linework — the whole map was a wall, the seed
				# was always inside it, `_solve` refused every bridge in turn
				# and the fill returned "nothing is enclosed" on every tap on
				# every drawing. The bucket has not filled anything since that
				# line moved; it fails silently, which is why it read as the
				# tool being fussy about closed shapes rather than as the tool
				# being dead.
				#
				# What it is supposed to say is the rule in the docstring at
				# the top of this file: a coarse cell counts as linework if
				# *any* pixel inside it is linework. That is what makes a
				# hairline get sturdier when the map is shrunk instead of
				# vanishing, and it is what closes a hair-thin gap for free.
				same[i] = 0
				blocked[qrow + floori(float(x) / float(scale))] = 1

	# --- solve small ---
	var qsx: int = floori(float(sx) / float(scale))
	var qsy: int = floori(float(sy) / float(scale))
	var solved: Variant = _solve(blocked, qw, qh, qsx, qsy, COARSE_BRIDGES)
	if solved == null:
		# Nothing enclosed even after bridging: open canvas, paint nothing.
		# Recorded rather than merely returned, because "I tapped inside a
		# shape and nothing happened" and "I tapped on open canvas and
		# nothing happened" look the same to the user and are not the same
		# bug at all.
		return _gave_up("open", started, {"window": "%dx%d" % [w, h],
			"scale": scale})

	var sd: Dictionary = solved
	var coarse: PackedByteArray = sd["mask"]

	# --- the coarse answer says *where*, not *exactly where* ---
	#
	# Solving on a shrunken map is what keeps the tool quick, but a shrunken
	# map cannot know a curve to the pixel: it thickens every line, and the
	# fill either stops short of the outline or spills past it. So the
	# coarse answer is used only to fence off a small region, and the real
	# boundary is found again at full resolution inside that fence.
	#
	# The search stays small — it can only ever cover the shape the coarse
	# pass already found — while the edge is exact.
	var allowed: PackedByteArray = _grow(coarse, qw, qh, int(sd["bridge"]) + 2)
	var fine_blocked: PackedByteArray = PackedByteArray()
	fine_blocked.resize(total)
	for y in range(h):
		var row: int = y * w
		var qrow2: int = floori(float(y) / float(scale)) * qw
		for x in range(w):
			var col2: int = floori(float(x) / float(scale))
			if allowed[qrow2 + col2] == 0 or same[row + x] == 0:
				fine_blocked[row + x] = 1
			else:
				fine_blocked[row + x] = 0

	if fine_blocked[seed_index] != 0:
		return _gave_up("blocked-seed", started, {"window": "%dx%d" % [w, h],
			"scale": scale, "bridge": int(sd["bridge"])})
	var exact: Variant = _flood_open(fine_blocked, w, h, sx, sy)
	if exact == null:
		return _gave_up("unreadable", started)
	var mask: PackedByteArray = exact

	# Overlap into the soft edge of the linework, and only into the soft part
	# — never into a stroke's solid core, which the colour must stay behind.
	# How far is the user's to choose: an inked line fades over two or three
	# pixels, a pencil over rather more.
	mask = _grow_into(mask, _core_of(data, total), w, h, creep_now())

	var out_bytes: PackedByteArray = PackedByteArray()
	out_bytes.resize(total * 4)
	out_bytes.fill(0)
	var a: int = int(clampf(ink.a, 0.0, 1.0) * 255.0)
	# Premultiplied, the way the canvas stores everything else.
	var cr: int = int(clampf(ink.r, 0.0, 1.0) * float(a))
	var cg: int = int(clampf(ink.g, 0.0, 1.0) * float(a))
	var cb: int = int(clampf(ink.b, 0.0, 1.0) * float(a))
	var painted: int = 0
	for i in range(total):
		if mask[i] == 0:
			continue
		painted += 1
		var o2: int = i * 4
		out_bytes[o2] = cr
		out_bytes[o2 + 1] = cg
		out_bytes[o2 + 2] = cb
		out_bytes[o2 + 3] = a
	if painted == 0:
		return _gave_up("nothing", started, {"window": "%dx%d" % [w, h],
			"scale": scale, "bridge": int(sd["bridge"])})

	var out: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.set_data(w, h, false, Image.FORMAT_RGBA8, out_bytes)
	last = {
		"outcome": "filled",
		"bridge": int(sd["bridge"]),
		"window": "%dx%d" % [w, h],
		"scale": scale,
		"pixels": painted,
		"ms": float(Time.get_ticks_usec() - started) / 1000.0,
	}
	Perf.since("fill", started)
	return {"image": out, "origin": origin}

## Solid linework: what the fill may tuck under but never cover.
static func _core_of(data: PackedByteArray, total: int) -> PackedByteArray:
	var core: PackedByteArray = PackedByteArray()
	core.resize(total)
	for i in range(total):
		core[i] = 1 if data[i * 4 + 3] > CORE_ALPHA else 0
	return core

## Like `_flood` but without the escape test: the fence has already decided
## what is reachable, so touching the window edge here is not a failure.
static func _flood_open(blocked: PackedByteArray, w: int, h: int,
		sx: int, sy: int) -> Variant:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)

	var stack: PackedInt32Array = PackedInt32Array()
	stack.append(sy * w + sx)
	while stack.size() > 0:
		var idx: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if mask[idx] != 0:
			continue
		var y: int = floori(float(idx) / float(w))
		var x: int = idx - y * w

		var xl: int = x
		while xl > 0 and mask[y * w + xl - 1] == 0 and blocked[y * w + xl - 1] == 0:
			xl -= 1
		var xr: int = x
		while xr < w - 1 and mask[y * w + xr + 1] == 0 and blocked[y * w + xr + 1] == 0:
			xr += 1

		var above: bool = false
		var below: bool = false
		for i in range(xl, xr + 1):
			mask[y * w + i] = 1
			if y > 0:
				var up: int = (y - 1) * w + i
				var ok_up: bool = mask[up] == 0 and blocked[up] == 0
				if ok_up and not above:
					stack.append(up)
				above = ok_up
			if y < h - 1:
				var dn: int = (y + 1) * w + i
				var ok_dn: bool = mask[dn] == 0 and blocked[dn] == 0
				if ok_dn and not below:
					stack.append(dn)
				below = ok_dn
	return mask

# ------------------------------------------------------------------ solver

## Tries wider and wider bridges until the colour stays trapped.
static func _solve(blocked: PackedByteArray, w: int, h: int,
		sx: int, sy: int, bridges: Array) -> Variant:
	var cur: PackedByteArray = blocked
	var grown: int = 0
	var seed_index: int = sy * w + sx
	for entry in bridges:
		var bridge: int = int(entry)
		if bridge > grown:
			cur = _grow_blocked(cur, w, h, bridge - grown)
			grown = bridge
		if cur[seed_index] != 0:
			continue                        # the bridge swallowed the seed
		var mask: Variant = _flood(cur, w, h, sx, sy)
		if mask != null:
			return {"mask": mask, "bridge": bridge}
	return null

## Scanline flood that gives up the moment the colour touches the window
## edge. That is how "this shape is not closed" is detected, and it is
## detected fast — a tap on open canvas costs almost nothing.
static func _flood(blocked: PackedByteArray, w: int, h: int,
		sx: int, sy: int) -> Variant:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)

	var stack: PackedInt32Array = PackedInt32Array()
	stack.append(sy * w + sx)

	while stack.size() > 0:
		var idx: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		if mask[idx] != 0:
			continue
		var y: int = int(floor(float(idx) / float(w)))
		var x: int = idx - y * w
		if y == 0 or y == h - 1:
			return null

		var xl: int = x
		while xl > 0 and mask[y * w + xl - 1] == 0 and blocked[y * w + xl - 1] == 0:
			xl -= 1
		var xr: int = x
		while xr < w - 1 and mask[y * w + xr + 1] == 0 and blocked[y * w + xr + 1] == 0:
			xr += 1
		if xl == 0 or xr == w - 1:
			return null

		var above: bool = false
		var below: bool = false
		for i in range(xl, xr + 1):
			mask[y * w + i] = 1
			var up: int = (y - 1) * w + i
			var ok_up: bool = mask[up] == 0 and blocked[up] == 0
			if ok_up and not above:
				stack.append(up)
			above = ok_up
			var dn: int = (y + 1) * w + i
			var ok_dn: bool = mask[dn] == 0 and blocked[dn] == 0
			if ok_dn and not below:
				stack.append(dn)
			below = ok_dn
	return mask

static func _grow_blocked(src: PackedByteArray, w: int, h: int, steps: int) -> PackedByteArray:
	return _grow(src, w, h, steps)

## Expands the filled region outward, but never over solid linework — so the
## fill slides under the soft edge of a stroke without erasing it.
static func _grow_into(mask: PackedByteArray, core: PackedByteArray,
		w: int, h: int, steps: int) -> PackedByteArray:
	var cur: PackedByteArray = mask
	for _s in range(steps):
		var next: PackedByteArray = cur.duplicate()
		for y in range(h):
			var row: int = y * w
			for x in range(w):
				var i: int = row + x
				if cur[i] != 0 or core[i] != 0:
					continue
				if x > 0 and cur[i - 1] != 0:
					next[i] = 1
				elif x < w - 1 and cur[i + 1] != 0:
					next[i] = 1
				elif y > 0 and cur[i - w] != 0:
					next[i] = 1
				elif y < h - 1 and cur[i + w] != 0:
					next[i] = 1
		cur = next
	return cur

static func _grow(src: PackedByteArray, w: int, h: int, steps: int) -> PackedByteArray:
	var cur: PackedByteArray = src
	for _s in range(steps):
		var next: PackedByteArray = cur.duplicate()
		for y in range(h):
			var row: int = y * w
			for x in range(w):
				var i: int = row + x
				if cur[i] != 0:
					continue
				if x > 0 and cur[i - 1] != 0:
					next[i] = 1
				elif x < w - 1 and cur[i + 1] != 0:
					next[i] = 1
				elif y > 0 and cur[i - w] != 0:
					next[i] = 1
				elif y < h - 1 and cur[i + w] != 0:
					next[i] = 1
		cur = next
	return cur

# ----------------------------------------------------------------- helpers

static func _same(d: PackedByteArray, p: int, r: int, g: int, b: int, a: int) -> bool:
	var tol: int = tolerance_now()
	var pa: int = d[p + 3]
	if absi(pa - a) > tol:
		return false
	if pa < 8 and a < 8:
		return true                         # both effectively empty
	return absi(d[p] - r) <= tol \
		and absi(d[p + 1] - g) <= tol \
		and absi(d[p + 2] - b) <= tol
