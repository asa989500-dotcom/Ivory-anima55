shader_type canvas_item;
render_mode blend_premul_alpha;

// Out-of-focus, the way a lens does it.
//
// A gaussian blur is the wrong shape for this. A lens does not spread a point
// of light in a bell curve — it spreads it across the shape of its aperture,
// evenly, with a hard edge. That flat shape is why an out-of-focus highlight
// in a photograph reads as a little disc rather than a smudge, and it is the
// whole difference between "defocused" and "smeared".
//
// Three things make this read as a camera rather than as a filter:
//
//   1. The aperture has blades. A real iris is a polygon of five to nine
//      leaves, and its bokeh is that polygon — hexagons behind a portrait,
//      not circles. Wide open it rounds off, which is why the blade count can
//      be dialled down to nought for a perfect disc.
//   2. Highlights bloom and everything else does not. A lens spreads *light*,
//      so the bright parts of a defocused image swell into their neighbours
//      while mid tones simply average. Weighting every bright pixel would only
//      wash the picture out; the knee here leaves ordinary tones alone and
//      lets genuine highlights carry many times their share.
//   3. Distance hazes. Something far enough out of focus to be unreadable is
//      also far enough away to have air in front of it, so its blacks lift
//      very slightly. It is a small number and it is the difference between a
//      background that sits behind the subject and one that sits under it.
//
// The samples are placed on a Fermat spiral rather than on rings. Rings at a
// low sample count leave the spokes visible as faint stars around a bright
// spot; the spiral's golden-angle step never repeats an alignment, so what is
// left over reads as fine grain instead of structure.
//
// Everything is done on premultiplied colour, which is what the canvas stores
// and the only form in which a weighted average of pixels is correct. Mixing
// straight alpha here would draw a dark halo around every stroke — the classic
// sign of a blur done in the wrong space. The haze is multiplied back by alpha
// for the same reason: lifting the blacks of a transparent pixel would light
// up the empty paper around the drawing.

uniform float radius : hint_range(0.0, 64.0) = 0.0;
uniform int taps : hint_range(4, 64) = 24;
// How far the aperture is open. Nought is a perfect disc; five to nine are the
// blade counts real irises are built with.
uniform int blades : hint_range(0, 9) = 6;
// Which way up the polygon sits.
uniform float blade_turn : hint_range(0.0, 6.283185) = 0.35;
// How much brighter-than-average pixels bloom into their neighbours.
uniform float bloom : hint_range(0.0, 8.0) = 3.2;
// Where a pixel stops being a mid tone and starts being a highlight.
uniform float bloom_knee : hint_range(0.2, 1.0) = 0.62;
// How much the blacks lift as the picture goes soft.
uniform float haze : hint_range(0.0, 0.2) = 0.045;

const float GOLDEN = 2.39996323;
const float PI2 = 6.28318530718;

// The radius of a bladed aperture at a given angle, as a fraction of the
// circle that contains it. A polygon is the circle pulled in between its
// corners, and this is that pull.
float aperture(float angle, int leaves) {
	if (leaves < 3) {
		return 1.0;
	}
	float wedge = PI2 / float(leaves);
	float half_wedge = wedge * 0.5;
	float local = mod(angle + blade_turn, wedge) - half_wedge;
	return cos(half_wedge) / max(cos(local), 0.0001);
}

void fragment() {
	vec2 step_size = TEXTURE_PIXEL_SIZE * radius;

	if (radius <= 0.01) {
		COLOR = texture(TEXTURE, UV);
	} else {
		vec4 sum = texture(TEXTURE, UV);
		float weight_sum = 1.0;
		int count = taps;

		for (int i = 1; i < 64; i++) {
			if (i >= count) {
				break;
			}
			float fi = float(i);
			// sqrt spreads the samples evenly over the *area* of the shape
			// rather than bunching them at the middle, which is what keeps
			// the blur flat instead of bell-shaped.
			float r = sqrt(fi / float(count));
			float a = fi * GOLDEN;
			vec2 offset = vec2(cos(a), sin(a)) * r * aperture(a, blades);
			vec4 sample_colour = texture(TEXTURE, UV + offset * step_size);

			// Premultiplied, so a sample sitting on empty paper is black at
			// zero alpha and would read as a dark pixel. Judging the light by
			// the straight colour keeps the paper out of the reckoning.
			float carry = max(sample_colour.a, 0.0001);
			vec3 straight = sample_colour.rgb / carry;
			float luma = dot(straight, vec3(0.2126, 0.7152, 0.0722));
			// A knee rather than a slope: mid tones weigh exactly one, and
			// only real highlights climb above it.
			float lift = smoothstep(bloom_knee, 1.0, luma) * sample_colour.a;
			float w = 1.0 + lift * lift * bloom;

			sum += sample_colour * w;
			weight_sum += w;
		}

		vec4 soft = sum / weight_sum;
		// Distance haze. Scaled by how far out of focus this is, so a light
		// touch of softness tints nothing, and multiplied by the pixel's own
		// alpha so the paper around the drawing stays paper.
		float depth = clamp(radius / 34.0, 0.0, 1.0);
		soft.rgb += vec3(haze) * depth * soft.a;
		COLOR = soft;
	}

	COLOR *= vec4(MODULATE.rgb, 1.0) * MODULATE.a;
}
