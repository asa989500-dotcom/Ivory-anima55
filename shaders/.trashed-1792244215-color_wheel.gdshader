shader_type canvas_item;
render_mode unshaded;

// A colour wheel in Oklab, not HSV.
//
// HSV is not a description of colour, it is a description of the numbers a
// screen takes. Its "value" is the largest of the three channels, so a fully
// saturated yellow and a fully saturated blue both count as V=1 while one is
// nearly white and the other nearly black. Measured in perceived lightness,
// the standard HSV ring runs from 0.968 at yellow down to 0.452 at blue — a
// spread of more than half the entire range, on a ring that is supposed to be
// varying only in hue.
//
// That one fact is behind everything people dislike about these wheels. It is
// why they look garish; why the yellows shout and the blues read as holes;
// why colours picked at the same height on the square do not hang together;
// and why dragging around the ring seems to speed up and slow down under the
// finger instead of moving evenly.
//
// Oklab was built to fix exactly this. Equal distances in it are equal
// differences to the eye. So this ring holds one lightness the whole way
// round and varies only hue — which is what a hue ring was always meant to
// mean — and the square moves in even steps of lightness and colourfulness.

uniform float ring_outer = 0.50;
uniform float ring_inner = 0.38;
uniform float hue = 0.0;
// The lightness the ring sits at. Mid-high: bright enough that every hue is
// unmistakable, low enough that all of them can reach a strong colourfulness
// without leaving what the screen can actually show.
uniform float ring_light = 0.72;

const float TAU_F = 6.28318530718;

vec3 oklab_to_linear(vec3 lab) {
	float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
	float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
	float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
	float l = l_ * l_ * l_;
	float m = m_ * m_ * m_;
	float s = s_ * s_ * s_;
	return vec3(
		 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

vec3 linear_to_srgb(vec3 c) {
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(hi, lo, step(c, vec3(0.0031308)));
}

bool inside_gamut(vec3 lin) {
	return lin.r >= -0.0005 && lin.g >= -0.0005 && lin.b >= -0.0005
		&& lin.r <= 1.0005 && lin.g <= 1.0005 && lin.b <= 1.0005;
}

// Not every lightness and colourfulness a person can imagine is a colour this
// screen can show. Rather than letting the out-of-range ones clip — which
// bends the hue as one channel saturates, and leaves flat dead patches where
// several distinct colours all become the same one — the colourfulness is
// reduced until the colour fits, keeping its hue and lightness exactly.
// Found by halving the interval, which lands within a fraction of a percent
// in ten steps.
vec3 oklch_to_srgb(float L, float C, float h) {
	float a = cos(h);
	float b = sin(h);
	vec3 lin = oklab_to_linear(vec3(L, C * a, C * b));
	if (!inside_gamut(lin)) {
		float lo = 0.0;
		float hi = C;
		for (int i = 0; i < 10; i++) {
			float mid = (lo + hi) * 0.5;
			vec3 test = oklab_to_linear(vec3(L, mid * a, mid * b));
			if (inside_gamut(test)) {
				lo = mid;
			} else {
				hi = mid;
			}
		}
		lin = oklab_to_linear(vec3(L, lo * a, lo * b));
	}
	return clamp(linear_to_srgb(lin), vec3(0.0), vec3(1.0));
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	float aa = fwidth(r) * 1.5;

	// --- the hue ring: one lightness, all the way round ---
	float ring = smoothstep(ring_outer, ring_outer - aa, r) *
	             smoothstep(ring_inner - aa, ring_inner, r);
	float ang = atan(p.y, p.x);
	// Asking for more colourfulness than any hue can reach, so the gamut
	// mapping does the work: every hue arrives at its own strongest honest
	// colour, rather than all of them being held back to the weakest one.
	vec3 ring_col = oklch_to_srgb(ring_light, 0.36, ang);

	// --- the square: lightness up, colourfulness across ---
	float half_side = (ring_inner - 0.035) * 0.7071;
	vec2 sq = (p + vec2(half_side)) / (2.0 * half_side);
	float in_sq = step(0.0, sq.x) * step(sq.x, 1.0)
		* step(0.0, sq.y) * step(sq.y, 1.0);
	float L = 1.0 - sq.y;
	float C = sq.x * 0.37;
	vec3 sq_col = oklch_to_srgb(L, C, hue * TAU_F);

	vec3 col = ring_col * ring + sq_col * in_sq * (1.0 - ring);
	float alpha = clamp(ring + in_sq, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
