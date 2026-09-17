class_name Oklab
extends RefCounted
## Colour, described the way it is seen rather than the way a screen is wired.

## HSV is a description of the numbers a monitor takes, not of colour. Its
## "value" is simply the largest of the three channels, so a saturated yellow
## and a saturated blue are both V=1 while one is nearly white and the other
## nearly black. Measured properly, a standard HSV ring swings from a
## perceived lightness of 0.968 at yellow to 0.452 at blue — over half the
## whole range — while claiming to vary only in hue.
##
## Oklab is built so that equal distances in it are equal differences to the
## eye. Its polar form, OKLCH, gives the three things a person actually means:
## how light a colour is, how colourful, and which hue. Moving in a straight
## line through it looks like a straight line.
##
## These functions are the same arithmetic the wheel's shader runs, kept here
## so that what a finger picks and what the wheel draws are the same colour to
## the last decimal rather than two independent approximations of one idea.
## The round trip through sRGB is accurate to about a millionth.

# --------------------------------------------------------------- transfer

static func to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)

static func to_gamma(c: float) -> float:
	if c <= 0.0031308:
		return c * 12.92
	return 1.055 * pow(maxf(c, 0.0), 1.0 / 2.4) - 0.055

static func _cbrt(x: float) -> float:
	if x >= 0.0:
		return pow(x, 1.0 / 3.0)
	return -pow(-x, 1.0 / 3.0)

# ----------------------------------------------------------- conversions

## An ordinary colour, taken apart into lightness, colourfulness and hue.
## Hue is a turn in radians; chroma is roughly 0 to 0.37 for anything a
## screen can show.
static func from_color(c: Color) -> Vector3:
	var r: float = to_linear(c.r)
	var g: float = to_linear(c.g)
	var b: float = to_linear(c.b)

	var l: float = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	var m: float = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	var s: float = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

	var l_: float = _cbrt(l)
	var m_: float = _cbrt(m)
	var s_: float = _cbrt(s)

	var big_l: float = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
	var a: float = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
	var bb: float = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

	var chroma: float = sqrt(a * a + bb * bb)
	var hue: float = 0.0
	if chroma > 0.00001:
		hue = atan2(bb, a)
		if hue < 0.0:
			hue += TAU
	return Vector3(big_l, chroma, hue)

static func _to_linear_rgb(big_l: float, a: float, b: float) -> Vector3:
	var l_: float = big_l + 0.3963377774 * a + 0.2158037573 * b
	var m_: float = big_l - 0.1055613458 * a - 0.0638541728 * b
	var s_: float = big_l - 0.0894841775 * a - 1.2914855480 * b
	var l: float = l_ * l_ * l_
	var m: float = m_ * m_ * m_
	var s: float = s_ * s_ * s_
	return Vector3(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)

static func _fits(v: Vector3) -> bool:
	return v.x >= -0.0005 and v.y >= -0.0005 and v.z >= -0.0005 \
		and v.x <= 1.0005 and v.y <= 1.0005 and v.z <= 1.0005

## Back to a colour the screen can show.
##
## When the colour asked for is beyond what the display can reach, its
## colourfulness is walked back until it fits and its hue and lightness are
## kept exactly. Clipping the channels instead would bend the hue — as one
## channel pins at its maximum the balance between them shifts — and would
## flatten whole regions of the wheel into a single colour.
static func to_color(big_l: float, chroma: float, hue: float,
		alpha: float = 1.0) -> Color:
	var light: float = clampf(big_l, 0.0, 1.0)
	var want: float = maxf(chroma, 0.0)
	var ca: float = cos(hue)
	var sa: float = sin(hue)

	var lin: Vector3 = _to_linear_rgb(light, want * ca, want * sa)
	if not _fits(lin):
		var lo: float = 0.0
		var hi: float = want
		for i in 12:
			var mid: float = (lo + hi) * 0.5
			if _fits(_to_linear_rgb(light, mid * ca, mid * sa)):
				lo = mid
			else:
				hi = mid
		lin = _to_linear_rgb(light, lo * ca, lo * sa)

	return Color(
		clampf(to_gamma(lin.x), 0.0, 1.0),
		clampf(to_gamma(lin.y), 0.0, 1.0),
		clampf(to_gamma(lin.z), 0.0, 1.0), alpha)

## The most colourful this hue can be at this lightness. Used to draw the
## marker where the colour actually is rather than where the slider says.
static func max_chroma(big_l: float, hue: float) -> float:
	var ca: float = cos(hue)
	var sa: float = sin(hue)
	var lo: float = 0.0
	var hi: float = 0.45
	for i in 14:
		var mid: float = (lo + hi) * 0.5
		if _fits(_to_linear_rgb(big_l, mid * ca, mid * sa)):
			lo = mid
		else:
			hi = mid
	return lo

## How different two colours look, as one number. Small is "almost the same".
##
## The reason this is worth having: the obvious way to compare colours is to
## subtract their red, green and blue, and that answer has very little to do
## with what a person sees. Two blues a hair apart in RGB can be plainly
## different, and two greens far apart can be indistinguishable. Distance in
## Oklab is the difference the eye reports.
static func difference(a: Color, b: Color) -> float:
	var one: Vector3 = from_color(a)
	var two: Vector3 = from_color(b)
	var a1: float = one.y * cos(one.z)
	var b1: float = one.y * sin(one.z)
	var a2: float = two.y * cos(two.z)
	var b2: float = two.y * sin(two.z)
	return Vector3(one.x - two.x, a1 - a2, b1 - b2).length()
