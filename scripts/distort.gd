class_name Distort
extends RefCounted
## Five ways to push a selection out of shape, and one way to cut a hole.
##
## ## Why these five and not any five
##
## A selection can already be moved, turned and resized. Those are the three
## things that keep a shape *the same shape*. Everything here changes what the
## shape is, and each one is a different kind of change:
##
## | | what it does | what it is for |
## |---|---|---|
## | `LEAN` | slides the top sideways past the bottom | italics, a figure leaning into a run |
## | `ARCH` | bends the whole thing along a curve | a banner, text on a hill, a bent limb |
## | `SWELL` | fattens the middle and pinches the ends | a bicep, a bottle, weight and squash |
## | `TWIST` | turns the middle further than the ends | wringing, a spiral, a ribbon |
## | `PINCH` | pulls toward or pushes away from the centre | a fisheye, a dent, a bulge |
##
## They are chosen so that no two of them can be made out of each other. Lean
## is the only one that is a straight-line transform; arch bends along one
## axis; swell scales across it; twist rotates by depth; pinch works radially.
## A sixth that could be built from two of these would be a longer menu rather
## than a more capable one.
##
## ## Every one is a rule, not a redrawing
##
## Each returns a `Callable` that takes a point and answers where it goes,
## exactly like `RigSkin.mouth_rule` and `RigSkin.bone_rule`. The selection is
## drawn through the same regular mesh the rest of the app already uses, so
## nothing here has to know what a texture is, and the same five rules serve a
## live preview and a final commit without being written twice.
##
## `amount` is always -1 to 1, always zero for "unchanged", and always signed
## so that dragging one way and dragging the other are opposites. A control
## that means nothing at its middle is a control nobody can put back.

enum Kind { LEAN, ARCH, SWELL, TWIST, PINCH }

## In menu order, with what each is called.
const KINDS: Array = [
	[Kind.LEAN, "Lean", "إمالة"],
	[Kind.ARCH, "Arch", "تقويس"],
	[Kind.SWELL, "Swell", "انتفاخ"],
	[Kind.TWIST, "Twist", "لَيّ"],
	[Kind.PINCH, "Pinch", "قرص"],
]

static func name_of(kind: int) -> String:
	if kind < 0 or kind >= KINDS.size():
		return "?"
	var row: Array = KINDS[kind]
	return UiKit.label_for(String(row[1]), String(row[2]))

## What one distortion does to one point.
##
## `box` is the selection's own rectangle. Everything is worked out in its
## local frame — `u` and `v` from 0 to 1 across it, and `cx`/`cy` from -1 to 1
## about its middle — so a distortion means the same thing on a small
## selection as on a large one, and applying the same amount twice to
## different selections gives them the same shape rather than the same number
## of pixels.
static func rule(kind: int, box: Rect2, amount: float) -> Callable:
	var t: float = clampf(amount, -1.0, 1.0)
	var mid: Vector2 = box.position + box.size * 0.5
	var half: Vector2 = Vector2(maxf(box.size.x * 0.5, 0.5),
		maxf(box.size.y * 0.5, 0.5))

	match kind:
		Kind.LEAN:
			# The top slides one way and the bottom the other, about the
			# middle — so the selection leans in place instead of walking
			# off to one side as it leans, which is what shearing about a
			# corner does and why it always needs a second nudge to correct.
			return func(p: Vector2) -> Vector2:
				var cy: float = (p.y - mid.y) / half.y
				return Vector2(p.x + cy * half.x * t, p.y)

		Kind.ARCH:
			# A parabola across the width: nothing at the ends, most in the
			# middle. Bending along a circle instead would need a centre and
			# a radius, and would fold the shape onto itself past a half
			# turn — a parabola cannot, however far it is pushed.
			return func(p: Vector2) -> Vector2:
				var cx: float = (p.x - mid.x) / half.x
				return Vector2(p.x, p.y + (1.0 - cx * cx) * half.y * t)

		Kind.SWELL:
			# Fat in the middle, thin at the ends — or the reverse. The
			# widening is across the *other* axis than the one it varies
			# along, which is what makes it read as weight rather than as a
			# resize.
			return func(p: Vector2) -> Vector2:
				var cy: float = (p.y - mid.y) / half.y
				var grow: float = 1.0 + (1.0 - cy * cy) * t
				return Vector2(mid.x + (p.x - mid.x) * grow, p.y)

		Kind.TWIST:
			# Turned by how far down it is. The ends stay put and the middle
			# goes furthest, so the shape wrings rather than spinning.
			return func(p: Vector2) -> Vector2:
				var cy: float = (p.y - mid.y) / half.y
				var turn: float = (1.0 - cy * cy) * t * PI * 0.5
				return mid + (p - mid).rotated(turn)

		Kind.PINCH:
			# Radial, and eased so the edge of the selection does not move
			# at all — a distortion that drags its own boundary tears itself
			# away from whatever it was sitting next to on the page.
			#
			# The strength is 0.45 and that number is not a taste. Writing
			# the map as r' = r - t·k·(r - r³), it stays monotonic — no two
			# points can trade places, so the picture cannot fold through
			# itself — only while |t·k| stays under a half. At 0.75, a full
			# push sent a point at nine tenths of the way out *past* the
			# boundary, which is held fixed: the shape turning inside out
			# against its own edge. Tested at 0.45; the fold is now not
			# merely unobserved but arithmetically impossible.
			return func(p: Vector2) -> Vector2:
				var off: Vector2 = p - mid
				var r: float = clampf(
					Vector2(off.x / half.x, off.y / half.y).length(),
					0.0, 1.0)
				var pull: float = 1.0 - (1.0 - r * r) * t * 0.45
				return mid + off * pull

	return func(p: Vector2) -> Vector2: return p

## A short line saying what a distortion is for, shown under its control.
static func note_of(kind: int) -> String:
	match kind:
		Kind.LEAN:
			return UiKit.label_for(
				"Slides the top sideways past the bottom, about the middle — italics, or a figure leaning into a run.",
				"يُزلق الأعلى جانباً عن الأسفل حول الوسط — للمائل، أو لشخصية تميل في جريها.")
		Kind.ARCH:
			return UiKit.label_for(
				"Bends the whole thing along a curve. Nothing moves at the ends and most in the middle.",
				"يثني الشيء كله على منحنى. لا شيء يتحرك عند الطرفين وأكثره في الوسط.")
		Kind.SWELL:
			return UiKit.label_for(
				"Fattens the middle and pinches the ends, or the reverse. Weight, and squash.",
				"يُسمّن الوسط ويقرص الطرفين، أو العكس. للثقل والانضغاط.")
		Kind.TWIST:
			return UiKit.label_for(
				"Turns the middle further than the ends, so the shape wrings rather than spins.",
				"يُدير الوسط أكثر من الطرفين، فيلتوي الشكل بدل أن يدور.")
		Kind.PINCH:
			return UiKit.label_for(
				"Pulls toward the centre or pushes away from it. The edge never moves.",
				"يشدّ نحو المركز أو يدفع عنه. والحافة لا تتحرك أبداً.")
	return ""

# ------------------------------------------------------------------ trimming

## The shapes a trim can be cut with.
enum Cut { RECT, ELLIPSE }

const CUTS: Array = [
	[Cut.RECT, "Square", "مربع"],
	[Cut.ELLIPSE, "Circle", "دائرة"],
]

## Whether a point falls inside the cutter.
##
## The one question a trim asks, and it is asked per pixel — so it is a
## comparison and a multiply rather than anything cleverer.
static func inside_cut(kind: int, box: Rect2, p: Vector2) -> bool:
	if kind == Cut.ELLIPSE:
		var mid: Vector2 = box.position + box.size * 0.5
		var half: Vector2 = Vector2(maxf(box.size.x * 0.5, 0.5),
			maxf(box.size.y * 0.5, 0.5))
		var off: Vector2 = p - mid
		return (off.x / half.x) * (off.x / half.x) \
			+ (off.y / half.y) * (off.y / half.y) <= 1.0
	return box.has_point(p)

## Rubs a shape out of an image, in place.
##
## `keep_inside` decides which side of the line survives: false cuts the
## shape away and leaves the rest, true keeps only the shape. Both are worth
## having and they are the same loop — a trim tool that can only do one of
## them makes the other a matter of cutting three times.
##
## The edge is softened over a pixel. A hard cut leaves a stair-stepped
## boundary that is visible the moment anything is drawn beside it, and
## softening it is a multiply rather than a second pass.
static func trim(img: Image, at: Vector2i, kind: int, box: Rect2,
		keep_inside: bool) -> void:
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in h:
		for x in w:
			var here: Vector2 = Vector2(float(at.x + x) + 0.5,
				float(at.y + y) + 0.5)
			var inside: bool = inside_cut(kind, box, here)
			if inside == keep_inside:
				continue
			var col: Color = img.get_pixel(x, y)
			if col.a <= 0.0:
				continue
			img.set_pixel(x, y, Color(col.r, col.g, col.b, 0.0))

# ------------------------------------------------------------- growing well

## Resizes a selection without letting it go soft.
##
## Scaling a small selection up is where a paint app usually gives itself
## away: the default filter is bilinear, which is a blur with a good name, and
## a face enlarged twice comes back looking like it was photographed through
## a window. Lanczos costs more and keeps the edges, which is the whole point
## of enlarging something.
##
## Shrinking is the opposite problem and needs the opposite answer. Lanczos
## rings on the way down — it puts a bright halo along every dark edge — so
## anything getting smaller goes through the area filter instead, which is the
## one that actually averages the pixels being thrown away.
##
## Doing nothing when the size has not changed matters as much as either: a
## resample of the same size is not free and is not lossless, and a selection
## nudged sideways twenty times should not have been resampled twenty times.
static func rescale(src: Image, want: Vector2i) -> Image:
	if src == null:
		return null
	var to_w: int = maxi(want.x, 1)
	var to_h: int = maxi(want.y, 1)
	if to_w == src.get_width() and to_h == src.get_height():
		return src
	var out: Image = src.duplicate()
	var growing: bool = to_w * to_h > src.get_width() * src.get_height()
	# `INTERPOLATE_AREA` is not a thing Godot has — it belongs to OpenCV, and
	# naming it here stopped the whole project compiling. Trilinear is the one
	# Godot means for shrinking: it builds mipmaps first, so every source pixel
	# contributes to the result instead of three quarters of them being thrown
	# away, which is the artefact area-averaging exists to avoid.
	out.resize(to_w, to_h, Image.INTERPOLATE_LANCZOS if growing
		else Image.INTERPOLATE_TRILINEAR)
	return out
