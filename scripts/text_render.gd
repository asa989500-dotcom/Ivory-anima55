class_name TextRender
extends RefCounted
## Turning written words into pixels.

## The shaping is not done here, and that is the point. Laying out text by
## walking a string and placing one glyph after another works in English and
## nowhere else: Arabic letters change shape depending on their neighbours and
## run right to left, Hebrew runs right to left with left-to-right numbers
## inside it, Devanagari reorders vowels around consonants, and Chinese,
## Japanese and Korean break lines without spaces to break at.
##
## So the words are handed to the same text server that draws every label in
## the app, and it is asked to render them. Whatever the font covers comes out
## correct, and there is no list of special cases to keep up to date.

const PAD: float = 24.0
const MAX_SIDE: int = 4096

## Draws the words and hands back the pixels, trimmed to what was actually
## marked.
static func render(state: Dictionary) -> Image:
	var words: String = String(state.get("text", ""))
	if words.strip_edges() == "":
		return null

	var font: Font = UiKit.font if UiKit.font != null else ThemeDB.fallback_font
	if font == null:
		return null
	var size_px: int = clampi(int(round(float(state.get("size", 64.0)))), 4, 512)
	var halo: float = maxf(float(state.get("halo", 0.0)), 0.0)
	var ink: Color = state.get("colour", Color("#1A1712"))
	var glow: Color = state.get("halo_colour", Color("#FFF8E7"))
	var leading: float = clampf(float(state.get("leading", 1.15)), 0.5, 3.0)
	var align: int = int(state.get("align", HORIZONTAL_ALIGNMENT_LEFT))

	# Measured before it is drawn, so the sheet is the size of the writing
	# rather than the size of a guess.
	var lines: PackedStringArray = words.split("\n")
	var widest: float = 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x)
	var line_h: float = font.get_height(size_px) * leading
	var pad: float = PAD + halo * 1.5
	var w: int = clampi(int(ceil(widest + pad * 2.0)), 8, MAX_SIDE)
	var h: int = clampi(int(ceil(line_h * float(lines.size()) + pad * 2.0)),
		8, MAX_SIDE)

	# Rendered larger than it is wanted, then shrunk.
	#
	# ## Why the writing came out soft
	#
	# It was drawn at final size into a viewport with `MSAA_4X` on. Multisample
	# anti-aliasing works on the coverage of a *polygon edge*; a glyph is not
	# drawn as a polygon here, it is blended from a texture the font server
	# has already anti-aliased. So the MSAA had nothing to sharpen and the
	# only thing it changed was to soften what the font had already got right
	# — and on a light halo it left a grey rim round every letter.
	#
	# Supersampling is the thing that does help: draw at twice the size, so
	# every glyph is rasterised with four times the detail, and then let the
	# shrink average it down. Curves and diagonals — which is most of Arabic —
	# come back with real gradients in them instead of the font server's guess
	# at one pixel per step. It costs four times the pixels of a picture that
	# is at most a few hundred a side and is drawn once.
	#
	# The factor comes down for very large text, where the detail is already
	# there and four times the area of a 512-pixel sheet is worth more than
	# the difference is.
	var over: int = 2 if size_px <= 160 else 1
	while over > 1 and (w * over > MAX_SIDE or h * over > MAX_SIDE):
		over -= 1

	var port: SubViewport = SubViewport.new()
	port.size = Vector2i(w * over, h * over)
	port.transparent_bg = true
	port.disable_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_ONCE
	port.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	# Deliberately off. See above: it had nothing to anti-alias and softened
	# what the font server had already done properly.
	port.msaa_2d = Viewport.MSAA_DISABLED

	var turn: float = float(state.get("turn", 0.0))
	if absf(turn) > 0.0001:
		# Turned as it is drawn, not turned afterwards. Rendering the words
		# at their angle keeps every letter as crisp as an upright one;
		# rotating the finished picture would resample it, and each turn
		# after that would resample the resampling.
		var reach: float = sqrt(float(w * w + h * h))
		w = clampi(int(ceil(reach)), 8, MAX_SIDE)
		h = clampi(int(ceil(reach)), 8, MAX_SIDE)

	var sheet: TextSheet = TextSheet.new()
	sheet.font = font
	sheet.size_px = size_px
	sheet.lines = lines
	sheet.ink = ink
	sheet.glow = glow
	sheet.halo = halo
	sheet.line_h = line_h
	sheet.pad = pad
	sheet.align = align
	sheet.box = Vector2(w, h)
	sheet.turn = turn
	# The sheet draws in final coordinates and is scaled up by the node, so
	# every number above stays in the units the caller thinks in.
	sheet.scale = Vector2(float(over), float(over))
	port.add_child(sheet)

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	tree.root.add_child(port)
	# Two frames, not one.
	#
	# `UPDATE_ONCE` schedules the draw; the first `frame_post_draw` after
	# adding the viewport can arrive before that draw has happened, and the
	# texture read back is then empty or half written. That is the report of
	# text that sometimes comes out blank or in pieces — it is a race, so it
	# depends on what else the app was doing at the moment the words were
	# committed, which is why it looked random.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out: Image = port.get_texture().get_image()
	port.queue_free()
	if out == null:
		return null
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	if over > 1:
		# Lanczos, because this shrink is the whole point of drawing large.
		# A bilinear halving averages two pixels of four and throws the
		# other two away, which gives back most of the softness the
		# supersampling was meant to remove.
		out.resize(maxi(w, 1), maxi(h, 1), Image.INTERPOLATE_LANCZOS)

	# Trimmed to the marks. The sheet was padded generously so a halo would
	# have room; keeping that padding would make the layer mostly empty and
	# put its centre in the wrong place.
	var used: Rect2i = out.get_used_rect()
	if used.size.x < 1 or used.size.y < 1:
		return null
	if used.position != Vector2i.ZERO or used.size != Vector2i(w, h):
		var trim: Image = Image.create_empty(used.size.x, used.size.y, false,
			Image.FORMAT_RGBA8)
		trim.blit_rect(out, used, Vector2i.ZERO)
		out = trim
	return out

## The node that does the drawing, in its own viewport.
class TextSheet extends Node2D:
	var font: Font = null
	var size_px: int = 64
	var lines: PackedStringArray = PackedStringArray()
	var ink: Color = Color.BLACK
	var glow: Color = Color.WHITE
	var halo: float = 0.0
	var line_h: float = 1.0
	var pad: float = 24.0
	var align: int = HORIZONTAL_ALIGNMENT_LEFT
	var box: Vector2 = Vector2.ONE
	var turn: float = 0.0

	func _draw() -> void:
		if font == null:
			return
		if absf(turn) > 0.0001:
			# Turned about the middle of the sheet, which is the middle of
			# the writing — so a line spun round stays where it was rather
			# than swinging away from under the finger. The offset undoes the
			# shift the rotation puts on the centre.
			var mid: Vector2 = box * 0.5
			draw_set_transform(mid - mid.rotated(turn), turn, Vector2.ONE)
		var top: float = pad + font.get_ascent(size_px)
		# A width is only given when the alignment needs one.
		#
		# `draw_string` uses the width for two things at once: it is the box
		# an aligned line is placed inside, and it is the point at which the
		# line is **cut off**. Left-aligned text needs no box, so passing one
		# bought nothing and risked everything — a line measured a fraction
		# wider than the sheet, or a sheet clamped at `MAX_SIDE`, lost its
		# last letters with no sign that anything had been dropped.
		var width: float = -1.0
		if align != HORIZONTAL_ALIGNMENT_LEFT:
			width = box.x - pad * 2.0
		for i in lines.size():
			var y: float = top + line_h * float(i)
			var line: String = lines[i]
			if halo > 0.5:
				# Drawn as a ring of copies behind the letters. A halo that is
				# one offset copy is a shadow; a ring of them is an outline,
				# and it holds the words legible over any drawing beneath.
				var steps: int = 16
				for k in steps:
					var ang: float = TAU * float(k) / float(steps)
					var off: Vector2 = Vector2(cos(ang), sin(ang)) * halo
					draw_string(font, Vector2(pad, y) + off, line, align,
						width, size_px, glow)
			draw_string(font, Vector2(pad, y), line, align, width, size_px, ink)

## The rectangle the ink itself occupies on a surface.
##
## ## Why the writing's box was enormous
##
## `content_bounds()` answers **in whole tiles**, and a tile is 256 pixels
## square. So a one-line caption forty pixels tall came back inside a box of
## at least 256 by 256, and one straddling a tile edge came back inside 512.
## The box was not describing the writing. It was describing which tiles the
## writing had touched.
##
## Two complaints follow from that single fact. It looked far too big, because
## it was — several times the size of the words. And it was hard to take hold
## of, because the turn grip is placed above the *top of the box*: with the box
## two hundred pixels taller than the letters, the grip floated in blank paper
## with no visible relation to the thing it turns. A person reaches for the
## writing, and the control was not near the writing.
##
## The tiles say where to look; the pixels inside them say where the ink
## actually stops. Costly enough that the caller must remember the answer —
## `canvas_view` keeps it and throws it away whenever the words could have
## changed — and exact, which is what makes the box fit the sentence instead
## of fitting the grid.
static func ink_bounds(surface: PaintSurface) -> Rect2:
	if surface == null:
		return Rect2()
	surface.flush()
	var tiles: Rect2i = surface.content_bounds()
	if tiles.size.x < 1 or tiles.size.y < 1:
		return Rect2()
	var img: Image = surface.read_region(tiles)
	if img == null:
		return Rect2(Vector2(tiles.position), Vector2(tiles.size))
	var used: Rect2i = img.get_used_rect()
	if used.size.x < 1 or used.size.y < 1:
		# Nothing drawn yet. The tiles are the only answer there is, and an
		# empty box would be worse than a loose one.
		return Rect2(Vector2(tiles.position), Vector2(tiles.size))
	return Rect2(Vector2(tiles.position + used.position), Vector2(used.size))
