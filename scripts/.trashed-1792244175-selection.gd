class_name SelectionMask
extends RefCounted
## Turns a drawn selection shape into a per-pixel stencil.
##
## Testing "is this point inside the shape" once per pixel would be far too
## slow for a lasso. Instead each row is solved once: find where the outline
## crosses that row, sort the crossings, and fill between pairs. That is the
## classic scanline fill, and it costs about one operation per pixel covered.

## Every pixel inside the box.
static func full(w: int, h: int) -> PackedByteArray:
	var m: PackedByteArray = PackedByteArray()
	m.resize(w * h)
	m.fill(1)
	return m

static func ellipse(w: int, h: int) -> PackedByteArray:
	var m: PackedByteArray = PackedByteArray()
	m.resize(w * h)
	m.fill(0)
	var rx: float = maxf(float(w) * 0.5, 0.5)
	var ry: float = maxf(float(h) * 0.5, 0.5)
	for y in range(h):
		var dy: float = (float(y) + 0.5 - ry) / ry
		var inside: float = 1.0 - dy * dy
		if inside <= 0.0:
			continue
		var span: float = sqrt(inside) * rx
		var x0: int = clampi(int(round(rx - span)), 0, w - 1)
		var x1: int = clampi(int(round(rx + span)) - 1, 0, w - 1)
		var row: int = y * w
		for x in range(x0, x1 + 1):
			m[row + x] = 1
	return m

## `points` are in world space; `origin` is the top-left of the mask box.
static func polygon(points: PackedVector2Array, origin: Vector2i,
		w: int, h: int) -> PackedByteArray:
	var m: PackedByteArray = PackedByteArray()
	m.resize(w * h)
	m.fill(0)
	var n: int = points.size()
	if n < 3:
		return m

	var xs: PackedFloat32Array = PackedFloat32Array()
	for y in range(h):
		var scan: float = float(origin.y) + float(y) + 0.5
		xs.clear()
		var j: int = n - 1
		for i in range(n):
			var a: Vector2 = points[j]
			var b: Vector2 = points[i]
			j = i
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				var t: float = (scan - a.y) / (b.y - a.y)
				xs.append(a.x + t * (b.x - a.x))
		if xs.size() < 2:
			continue
		xs.sort()
		var row: int = y * w
		var k: int = 0
		while k + 1 < xs.size():
			var left: int = int(ceil(xs[k] - float(origin.x) - 0.5))
			var right: int = int(floor(xs[k + 1] - float(origin.x) - 0.5))
			left = maxi(left, 0)
			right = mini(right, w - 1)
			for x in range(left, right + 1):
				m[row + x] = 1
			k += 2
	return m

## Bounding box of a point list, padded by one pixel and never empty.
static func bounds_of(points: PackedVector2Array) -> Rect2i:
	if points.is_empty():
		return Rect2i(0, 0, 0, 0)
	var lo: Vector2 = points[0]
	var hi: Vector2 = points[0]
	for p in points:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.y)
	var pos: Vector2i = Vector2i(int(floor(lo.x)) - 1, int(floor(lo.y)) - 1)
	var size: Vector2i = Vector2i(int(ceil(hi.x)) + 1, int(ceil(hi.y)) + 1) - pos
	size.x = maxi(size.x, 1)
	size.y = maxi(size.y, 1)
	return Rect2i(pos, size)

## Keeps only what the stencil covers; everything else becomes transparent.
##
## Canvas pixels are premultiplied, so clearing one means clearing all four
## channels. Zeroing alpha alone would leave colour behind with nothing
## carrying it, and that colour would reappear the moment the piece was
## blended anywhere.
static func apply(img: Image, mask: PackedByteArray) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if mask.size() < w * h:
		return false
	var bytes: PackedByteArray = img.get_data()
	var any: bool = false
	for i in range(w * h):
		var o: int = i * 4
		if mask[i] == 0:
			bytes[o] = 0
			bytes[o + 1] = 0
			bytes[o + 2] = 0
			bytes[o + 3] = 0
		elif bytes[o + 3] > 0:
			any = true
	img.set_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	return any
