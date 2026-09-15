class_name WebpAnim
extends RefCounted
## Animated WebP, assembled from the frames Godot already knows how to make.
##
## This is your idea, and it works for a reason worth stating plainly: a
## WebP file is a RIFF container holding one compressed frame, and that
## frame is VP8 — the same codec a WebM video carries. The engine ships the
## encoder; what it does not ship is the wrapper that turns a sequence of
## those frames into one moving file.
##
## So that wrapper is written here. Each frame is encoded with the engine's
## own `save_webp_to_buffer`, its VP8 payload is lifted out of the little
## container Godot wrapped it in, and the payloads are re-wrapped together
## with the ANIM and ANMF chunks the animated form requires.
##
## What this buys over GIF: full colour instead of 256, real transparency,
## and files several times smaller — because the compression is a video
## codec rather than one from 1987.
##
## What it is not: an MP4. Android has played animated WebP since version 9
## and every current browser shows it, but a video editor will not import
## one. For that, the numbered PNG sequence is still the road.

const RIFF: String = "RIFF"
const WEBP: String = "WEBP"

## `delay_ms` is milliseconds per frame — no rounding to hundredths here,
## which is one more thing this format does better than GIF.
static func encode(frames: Array, delay_ms: int, loop: bool = true) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	if frames.is_empty():
		return out

	var first: Image = frames[0]
	var w: int = first.get_width()
	var h: int = first.get_height()
	if w <= 0 or h <= 0:
		return out

	var body: PackedByteArray = PackedByteArray()

	# --- VP8X: says the file is extended, and that it animates ---
	var vp8x: PackedByteArray = PackedByteArray()
	vp8x.append(0x12)                      # animation + alpha
	vp8x.append(0)
	vp8x.append(0)
	vp8x.append(0)
	_u24(vp8x, w - 1)
	_u24(vp8x, h - 1)
	_chunk(body, "VP8X", vp8x)

	# --- ANIM: background and how many times to repeat ---
	var anim: PackedByteArray = PackedByteArray()
	_u32le(anim, 0x00000000)               # transparent background
	_u16le(anim, 0 if loop else 1)         # zero means forever
	_chunk(body, "ANIM", anim)

	for f in frames:
		var img: Image = f
		if img.get_width() != w or img.get_height() != h:
			continue
		var payload: PackedByteArray = _frame_payload(img)
		if payload.is_empty():
			continue

		var anmf: PackedByteArray = PackedByteArray()
		_u24(anmf, 0)                      # x, in units of two pixels
		_u24(anmf, 0)                      # y
		_u24(anmf, w - 1)
		_u24(anmf, h - 1)
		_u24(anmf, maxi(delay_ms, 1))
		# Blend with what came before, and do not clear first: the same
		# choice GIF makes, and what lets a still background cost nothing.
		anmf.append(0x00)
		anmf.append_array(payload)
		_chunk(body, "ANMF", anmf)

	out.append_array(RIFF.to_ascii_buffer())
	_u32le(out, body.size() + 4)
	out.append_array(WEBP.to_ascii_buffer())
	out.append_array(body)
	return out

## Encodes one frame with the engine, then lifts the picture out of the
## single-image container Godot wrapped it in. An ANMF holds the bare
## payload chunks, not a whole nested file.
static func _frame_payload(img: Image) -> PackedByteArray:
	var whole: PackedByteArray = img.save_webp_to_buffer(true, 0.9)
	if whole.size() < 20:
		return PackedByteArray()
	var out: PackedByteArray = PackedByteArray()
	var at: int = 12                       # past "RIFF" + size + "WEBP"
	while at + 8 <= whole.size():
		var tag: String = ""
		for i in 4:
			# `String.chr` rather than the bare `char()` this used to call:
			# that one is a Godot 3 global and the four-letter chunk tags of a
			# WebP file are read on every animated export, so a name that may
			# not exist is not worth the gamble.
			tag += String.chr(whole[at + i])
		var length: int = whole[at + 4] | (whole[at + 5] << 8) \
			| (whole[at + 6] << 16) | (whole[at + 7] << 24)
		var padded: int = length + (length & 1)
		if tag == "VP8 " or tag == "VP8L" or tag == "ALPH":
			# Copied whole, header and all: the frame keeps its own chunk
			# headers inside the ANMF, which is what the format expects.
			out.append_array(whole.slice(at, mini(at + 8 + padded, whole.size())))
		at += 8 + padded
	return out

# --------------------------------------------------------------- RIFF bits

static func _chunk(into: PackedByteArray, tag: String, payload: PackedByteArray) -> void:
	into.append_array(tag.to_ascii_buffer())
	_u32le(into, payload.size())
	into.append_array(payload)
	if payload.size() % 2 == 1:
		into.append(0)                     # chunks sit on even boundaries

static func _u16le(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)

static func _u24(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)

static func _u32le(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 24) & 0xFF)

## Rough size before spending the time. VP8 on flat animation art lands
## around a tenth of what the same frames cost as GIF.
static func estimate_mb(width: float, height: float, fps: int, seconds: float) -> float:
	var per_frame: float = width * height * 0.045 / 1048576.0
	return per_frame * float(fps) * seconds
