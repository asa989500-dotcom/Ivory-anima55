class_name GifEncoder
extends RefCounted
## Writes an animated GIF, by hand.
##
## GIF is from 1987 and it shows: 256 colours per frame, and delays measured
## in hundredths of a second. What it has instead is that everything on
## earth opens it, which is exactly the property the app needs for sharing.
##
## Two things keep the files from being absurd:
##
##   Only the changed rectangle of each frame is stored. In animation most
##   of the picture holds still between frames, so this is usually the
##   difference between a file of tens of megabytes and one of hundreds.
##
##   The palette is built once from the whole clip rather than per frame,
##   which avoids colours shifting from frame to frame — the flickering
##   that makes hand-made GIFs look cheap.

const MAX_COLOURS: int = 256

## `delay_cs` is hundredths of a second. GIF cannot express anything finer,
## which is why the exporter only offers frame rates that divide 100 evenly.
static func encode(frames: Array, delay_cs: int, loop: bool = true) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	if frames.is_empty():
		return out

	var first: Image = frames[0]
	var w: int = first.get_width()
	var h: int = first.get_height()
	if w <= 0 or h <= 0:
		return out

	var palette: Array = _build_palette(frames)
	var lookup: Dictionary = {}
	for i in palette.size():
		lookup[int(palette[i])] = i

	# --- header and screen descriptor ---
	out.append_array("GIF89a".to_ascii_buffer())
	_u16(out, w)
	_u16(out, h)
	out.append(0xF7)                       # global table, 256 entries
	out.append(0)                          # background index
	out.append(0)                          # pixel aspect
	for i in 256:
		var c: int = int(palette[i]) if i < palette.size() else 0
		out.append((c >> 16) & 0xFF)
		out.append((c >> 8) & 0xFF)
		out.append(c & 0xFF)

	if loop:
		out.append(0x21)
		out.append(0xFF)
		out.append(11)
		out.append_array("NETSCAPE2.0".to_ascii_buffer())
		out.append(3)
		out.append(1)
		_u16(out, 0)                       # forever
		out.append(0)

	var previous: PackedByteArray = PackedByteArray()
	for f in frames:
		var img: Image = f
		if img.get_width() != w or img.get_height() != h:
			continue
		var indices: PackedByteArray = _quantise(img, lookup, palette, w, h)
		var box: Rect2i = _changed_box(previous, indices, w, h)
		previous = indices

		_frame(out, indices, w, box, delay_cs)
	out.append(0x3B)                       # trailer
	return out

# ----------------------------------------------------------------- palette

## One palette for the whole clip, gathered from every frame. Exact colours
## come first, because flat animation art usually has few of them and they
## should survive untouched; whatever is left over is filled from an even
## spread so photographs and gradients still land somewhere sensible.
static func _build_palette(frames: Array) -> Array:
	var seen: Dictionary = {}
	for f in frames:
		var img: Image = f
		var d: PackedByteArray = img.get_data()
		var count: int = img.get_width() * img.get_height()
		var step: int = maxi(floori(float(count) / 40000.0), 1)     # sampling is plenty here
		var i: int = 0
		while i < count:
			var o: int = i * 4
			var key: int = (d[o] << 16) | (d[o + 1] << 8) | d[o + 2]
			seen[key] = int(seen.get(key, 0)) + 1
			i += step
		if seen.size() > 6000:
			break

	var keys: Array = seen.keys()
	keys.sort_custom(func(a, b): return int(seen[a]) > int(seen[b]))

	var palette: Array = []
	for k in keys:
		if palette.size() >= MAX_COLOURS:
			break
		palette.append(int(k))
	while palette.size() < MAX_COLOURS:
		var n: int = palette.size()
		var r: int = (n & 0x07) * 36
		var g: int = ((n >> 3) & 0x07) * 36
		var b: int = ((n >> 6) & 0x03) * 85
		palette.append((r << 16) | (g << 8) | b)
	return palette

static func _quantise(img: Image, lookup: Dictionary, palette: Array,
		w: int, h: int) -> PackedByteArray:
	var d: PackedByteArray = img.get_data()
	var out: PackedByteArray = PackedByteArray()
	out.resize(w * h)
	var cache: Dictionary = {}
	for i in range(w * h):
		var o: int = i * 4
		var key: int = (d[o] << 16) | (d[o + 1] << 8) | d[o + 2]
		if lookup.has(key):
			out[i] = int(lookup[key])
			continue
		if cache.has(key):
			out[i] = int(cache[key])
			continue
		var best: int = _nearest(key, palette)
		cache[key] = best
		out[i] = best
	return out

static func _nearest(key: int, palette: Array) -> int:
	var r: int = (key >> 16) & 0xFF
	var g: int = (key >> 8) & 0xFF
	var b: int = key & 0xFF
	var best: int = 0
	var best_d: int = 1 << 30
	for i in palette.size():
		var c: int = int(palette[i])
		var dr: int = r - ((c >> 16) & 0xFF)
		var dg: int = g - ((c >> 8) & 0xFF)
		var db: int = b - (c & 0xFF)
		var dist: int = dr * dr + dg * dg + db * db
		if dist < best_d:
			best_d = dist
			best = i
			if dist == 0:
				break
	return best

## The smallest rectangle that differs from the previous frame.
static func _changed_box(prev: PackedByteArray, cur: PackedByteArray,
		w: int, h: int) -> Rect2i:
	if prev.size() != cur.size():
		return Rect2i(0, 0, w, h)
	var min_x: int = w
	var min_y: int = h
	var max_x: int = -1
	var max_y: int = -1
	for y in range(h):
		var row: int = y * w
		for x in range(w):
			if prev[row + x] == cur[row + x]:
				continue
			if x < min_x:
				min_x = x
			if x > max_x:
				max_x = x
			if y < min_y:
				min_y = y
			if y > max_y:
				max_y = y
	if max_x < 0:
		# Nothing moved. One pixel keeps the frame legal and costs nothing.
		return Rect2i(0, 0, 1, 1)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

# ------------------------------------------------------------------- frame

static func _frame(out: PackedByteArray, indices: PackedByteArray, w: int,
		box: Rect2i, delay_cs: int) -> void:
	out.append(0x21)                       # graphic control extension
	out.append(0xF9)
	out.append(4)
	out.append(0x04)                       # keep the previous frame beneath
	_u16(out, maxi(delay_cs, 2))
	out.append(0)                          # no transparent index
	out.append(0)

	out.append(0x2C)                       # image descriptor
	_u16(out, box.position.x)
	_u16(out, box.position.y)
	_u16(out, box.size.x)
	_u16(out, box.size.y)
	out.append(0)                          # no local palette

	var slice: PackedByteArray = PackedByteArray()
	slice.resize(box.size.x * box.size.y)
	for y in range(box.size.y):
		var src: int = (box.position.y + y) * w + box.position.x
		var dst: int = y * box.size.x
		for x in range(box.size.x):
			slice[dst + x] = indices[src + x]
	_lzw(out, slice)

# --------------------------------------------------------------------- LZW

## GIF's variable-width LZW. Codes grow from 9 bits to 12, the dictionary is
## cleared when it fills, and the whole stream is cut into blocks of at most
## 255 bytes — all of which the format insists on.
static func _lzw(out: PackedByteArray, data: PackedByteArray) -> void:
	var code_size: int = 8
	out.append(code_size)

	var clear_code: int = 1 << code_size
	var end_code: int = clear_code + 1
	var next_code: int = end_code + 1
	var width: int = code_size + 1

	var dict: Dictionary = {}
	var bits: PackedByteArray = PackedByteArray()
	# A two-slot array rather than two plain ints: a GDScript lambda captures
	# by value, so assigning to a captured int inside one changes nothing
	# outside it. An array is a reference, and the writes land.
	var acc: PackedInt32Array = PackedInt32Array([0, 0])   # value, bit count

	var emit: Callable = func(code: int, w: int) -> void:
		acc[0] |= code << acc[1]
		acc[1] += w
		while acc[1] >= 8:
			bits.append(acc[0] & 0xFF)
			acc[0] >>= 8
			acc[1] -= 8

	emit.call(clear_code, width)

	if data.size() > 0:
		var prefix: int = data[0]
		for i in range(1, data.size()):
			var k: int = data[i]
			var key: int = (prefix << 8) | k
			if dict.has(key):
				prefix = int(dict[key])
				continue
			emit.call(prefix, width)
			dict[key] = next_code
			next_code += 1
			if next_code > (1 << width) and width < 12:
				width += 1
			elif next_code > 4095:
				emit.call(clear_code, width)
				dict.clear()
				next_code = end_code + 1
				width = code_size + 1
			prefix = k
		emit.call(prefix, width)

	emit.call(end_code, width)
	if acc[1] > 0:
		bits.append(acc[0] & 0xFF)

	var at: int = 0
	while at < bits.size():
		var run: int = mini(255, bits.size() - at)
		out.append(run)
		out.append_array(bits.slice(at, at + run))
		at += run
	out.append(0)

static func _u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
