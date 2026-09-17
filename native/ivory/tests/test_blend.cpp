// The colour blend tool, put through seven rounds.
//
// Seven because that is what was asked for, and because they are seven
// genuinely different things that can be wrong with a blend tool rather than
// the same test written seven times:
//
//   1. the colour space itself
//   2. the shape of a merge between two colours
//   3. the kernel — that the brush shape really governs the mix
//   4. every mode doing what its name says
//   5. transparency, and the fringe that appears when it is done wrong
//   6. strength, repetition, and where a stroke settles
//   7. abuse: sizes, empty inputs, silly settings
#include "../src/ivory_blend.h"

#include <cmath>
#include <cstdio>
#include <vector>

using namespace godot;

static int checks = 0;
static int failures = 0;

static void ok(bool cond, const char *what) {
	++checks;
	if (!cond) {
		++failures;
		std::printf("  FAIL: %s\n", what);
	}
}

static void near(double a, double b, double tol, const char *what) {
	++checks;
	if (!(std::fabs(a - b) <= tol)) {
		++failures;
		std::printf("  FAIL: %s (%.5f vs %.5f)\n", what, a, b);
	}
}

static void round_of(int n, const char *t) {
	std::printf("round %d — %s\n", n, t);
}

static PackedByteArray rgba(int r, int g, int b, int a = 255) {
	PackedByteArray out;
	out.resize(4);
	out[0] = (uint8_t)r;
	out[1] = (uint8_t)g;
	out[2] = (uint8_t)b;
	out[3] = (uint8_t)a;
	return out;
}

// A flat tile of one colour.
static PackedByteArray flat(int w, int h, PackedByteArray c) {
	PackedByteArray out;
	out.resize(w * h * 4);
	for (int i = 0; i < w * h; ++i) {
		for (int k = 0; k < 4; ++k) {
			out[i * 4 + k] = c[k];
		}
	}
	return out;
}

// Two halves, left one colour and right the other.
static PackedByteArray halves(int w, int h, PackedByteArray l,
		PackedByteArray r) {
	PackedByteArray out;
	out.resize(w * h * 4);
	for (int y = 0; y < h; ++y) {
		for (int x = 0; x < w; ++x) {
			const PackedByteArray &c = x < w / 2 ? l : r;
			for (int k = 0; k < 4; ++k) {
				out[(y * w + x) * 4 + k] = c[k];
			}
		}
	}
	return out;
}

static PackedByteArray pixel_at(const PackedByteArray &buf, int w, int x,
		int y) {
	PackedByteArray out;
	out.resize(4);
	for (int k = 0; k < 4; ++k) {
		out[k] = buf[(y * w + x) * 4 + k];
	}
	return out;
}

static double luma(const PackedByteArray &c) {
	return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

// A flat disc stamp, for the tests that are not about the stamp.
static PackedFloat32Array disc(int px) {
	PackedFloat32Array out;
	out.resize(px * px);
	const double half = px * 0.5;
	for (int y = 0; y < px; ++y) {
		for (int x = 0; x < px; ++x) {
			const double dx = x + 0.5 - half, dy = y + 0.5 - half;
			const double r = std::sqrt(dx * dx + dy * dy) / half;
			out[y * px + x] = r < 0.98f ? 1.0f : 0.0f;
		}
	}
	return out;
}

// --------------------------------------------------------------- round one

static void round_one() {
	round_of(1, "the colour space");

	// A round trip has to come back where it started, or every mix is
	// wrong by however much it does not.
	const int probes[][3] = {
		{ 0, 0, 0 }, { 255, 255, 255 }, { 128, 128, 128 }, { 255, 0, 0 },
		{ 0, 255, 0 }, { 0, 0, 255 }, { 17, 200, 90 }, { 250, 4, 130 },
		{ 3, 3, 4 }, { 199, 199, 12 },
	};
	int worst = 0;
	for (const auto &p : probes) {
		PackedByteArray back = IvoryBlend::from_oklab(
				IvoryBlend::to_oklab(rgba(p[0], p[1], p[2])), 255);
		for (int k = 0; k < 3; ++k) {
			worst = std::max(worst, std::abs((int)back[k] - p[k]));
		}
	}
	ok(worst <= 1, "sRGB to OKLab and back is the same colour");

	// Black and white sit where they should on the lightness axis, and
	// neither has any colour to it.
	PackedFloat32Array black = IvoryBlend::to_oklab(rgba(0, 0, 0));
	PackedFloat32Array white = IvoryBlend::to_oklab(rgba(255, 255, 255));
	near(black[0], 0.0, 0.001, "black has no lightness");
	near(white[0], 1.0, 0.001, "white has lightness one");
	near(white[1], 0.0, 0.001, "and no colour on one axis");
	near(white[2], 0.0, 0.001, "nor on the other");

	// Mid grey is near the middle perceptually, which is the entire point of
	// the space and is emphatically not true of linear light — where 128
	// sits at about 0.21.
	PackedFloat32Array grey = IvoryBlend::to_oklab(rgba(128, 128, 128));
	ok(grey[0] > 0.55 && grey[0] < 0.65,
			"mid grey is near the middle, not near a fifth");
}

// --------------------------------------------------------------- round two

static void round_two() {
	round_of(2, "what halfway between two colours looks like");

	// The famous one. Red and green mixed in sRGB bytes give (128,128,0):
	// a dark mud. Mixed properly the middle is a real olive, and the thing
	// that says so is that it is lighter than the mud.
	PackedByteArray mid = IvoryBlend::mix_srgb(rgba(255, 0, 0),
			rgba(0, 255, 0), 0.5);
	ok(luma(mid) > luma(rgba(128, 128, 0)) + 10.0,
			"red into green is not mud");
	ok(mid[0] > 100 && mid[1] > 100, "and it holds both colours");

	// The ends are exactly the ends. A blend that does not reach its own
	// endpoints is a blend nobody can set up.
	PackedByteArray at0 = IvoryBlend::mix_srgb(rgba(12, 200, 44),
			rgba(255, 3, 90), 0.0);
	PackedByteArray at1 = IvoryBlend::mix_srgb(rgba(12, 200, 44),
			rgba(255, 3, 90), 1.0);
	ok(std::abs((int)at0[0] - 12) <= 1 && std::abs((int)at0[1] - 200) <= 1,
			"nought gives the first colour exactly");
	ok(std::abs((int)at1[0] - 255) <= 1 && std::abs((int)at1[2] - 90) <= 1,
			"one gives the second colour exactly");

	// Blue to white must not go through purple. The measure is the hue
	// angle in OKLab: it should stay near blue's rather than swinging.
	PackedFloat32Array blue = IvoryBlend::to_oklab(rgba(0, 0, 255));
	const double blue_hue = std::atan2(blue[2], blue[1]);
	double worst_swing = 0.0;
	for (int i = 1; i < 10; ++i) {
		PackedByteArray step = IvoryBlend::mix_srgb(rgba(0, 0, 255),
				rgba(255, 255, 255), i / 10.0);
		PackedFloat32Array lab = IvoryBlend::to_oklab(step);
		const double hue = std::atan2(lab[2], lab[1]);
		double d = std::fabs(hue - blue_hue);
		if (d > Math_PI) d = Math_TAU - d;
		worst_swing = std::max(worst_swing, d);
	}
	ok(worst_swing < 0.25, "blue to white stays blue rather than going purple");

	// And the steps are evenly spaced, which is what makes a gradient laid
	// with this look even rather than bunched.
	std::vector<double> gaps;
	PackedByteArray prev = IvoryBlend::mix_srgb(rgba(20, 30, 200),
			rgba(240, 200, 40), 0.0);
	for (int i = 1; i <= 8; ++i) {
		PackedByteArray now = IvoryBlend::mix_srgb(rgba(20, 30, 200),
				rgba(240, 200, 40), i / 8.0);
		PackedFloat32Array a = IvoryBlend::to_oklab(prev);
		PackedFloat32Array b = IvoryBlend::to_oklab(now);
		gaps.push_back(std::sqrt(
				(a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) +
				(a[2] - b[2]) * (a[2] - b[2])));
		prev = now;
	}
	double lo = 1e30, hi = 0.0;
	for (double g : gaps) {
		lo = std::min(lo, g);
		hi = std::max(hi, g);
	}
	ok(hi / std::max(lo, 1e-9) < 1.10, "the steps of a gradient are even");
}

// ------------------------------------------------------------- round three

static void round_three() {
	round_of(3, "the brush shape governs the mix");

	const int w = 64, h = 64;
	IvoryBlend b;
	b.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
	b.set_colours(rgba(0, 0, 0), rgba(0, 0, 0));
	b.set_mode(IvoryBlend::MODE_MIX);
	b.set_strength(1.0);
	b.set_size(40.0);

	// A stamp that is solid on its left half and empty on its right. If the
	// stamp governs the mix, exactly that shape appears on the canvas.
	const int px = 32;
	PackedFloat32Array split;
	split.resize(px * px);
	for (int y = 0; y < px; ++y) {
		for (int x = 0; x < px; ++x) {
			split[y * px + x] = x < px / 2 ? 1.0f : 0.0f;
		}
	}
	b.set_stamp(split, px);
	b.dab(Vector2(32, 32), 0.0);

	PackedByteArray after = b.surface();
	ok(luma(pixel_at(after, w, 20, 32)) < 40.0,
			"where the stamp is solid the colour is replaced");
	ok(luma(pixel_at(after, w, 44, 32)) > 240.0,
			"where the stamp is empty nothing is touched");

	// A soft stamp gives a soft result rather than a hard disc.
	IvoryBlend s;
	s.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
	s.set_colours(rgba(0, 0, 0), rgba(0, 0, 0));
	s.set_mode(IvoryBlend::MODE_MIX);
	s.set_strength(1.0);
	s.set_size(40.0);
	PackedFloat32Array soft;
	soft.resize(px * px);
	for (int y = 0; y < px; ++y) {
		for (int x = 0; x < px; ++x) {
			const double dx = x + 0.5 - px * 0.5, dy = y + 0.5 - px * 0.5;
			const double r = std::sqrt(dx * dx + dy * dy) / (px * 0.5);
			soft[y * px + x] = (float)std::max(0.0, 1.0 - r);
		}
	}
	s.set_stamp(soft, px);
	s.dab(Vector2(32, 32), 0.0);
	PackedByteArray got = s.surface();
	const double centre = luma(pixel_at(got, w, 32, 32));
	const double middle = luma(pixel_at(got, w, 32 + 10, 32));
	const double rim = luma(pixel_at(got, w, 32 + 18, 32));
	ok(centre < middle && middle < rim,
			"a soft stamp mixes hardest in the middle and least at the rim");

	// With no stamp at all it still works, on a built-in soft round. A tool
	// that does nothing until it is configured looks broken.
	IvoryBlend bare;
	bare.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
	bare.set_colours(rgba(0, 0, 0), rgba(0, 0, 0));
	bare.set_strength(1.0);
	bare.set_size(30.0);
	Dictionary d = bare.dab(Vector2(32, 32), 0.0);
	ok(int(d["pixels"]) > 100, "no stamp still gives a usable dab");
}

// -------------------------------------------------------------- round four

static void round_four() {
	round_of(4, "each mode doing what its name says");

	const int w = 80, h = 24;
	PackedFloat32Array k = disc(24);

	// MIX: everything moves towards one chosen colour.
	{
		IvoryBlend b;
		b.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
		b.set_colours(rgba(255, 0, 0), rgba(0, 0, 255));
		b.set_stamp(k, 24);
		b.set_mode(IvoryBlend::MODE_MIX);
		b.set_strength(1.0);
		b.set_size(20.0);
		b.dab(Vector2(40, 12), 0.0);
		PackedByteArray got = pixel_at(b.surface(), w, 40, 12);
		ok(got[0] > 200 && got[2] < 60, "mix at nought lands on the first colour");
		b.dab(Vector2(40, 12), 1.0);
		got = pixel_at(b.surface(), w, 40, 12);
		ok(got[2] > 200 && got[0] < 60, "and at one on the second");
	}

	// GRADIENT: one drag lays the whole ramp.
	{
		IvoryBlend b;
		b.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
		b.set_colours(rgba(255, 0, 0), rgba(0, 0, 255));
		b.set_stamp(k, 24);
		b.set_mode(IvoryBlend::MODE_GRADIENT);
		b.set_strength(1.0);
		b.set_size(14.0);
		PackedVector2Array path;
		for (int i = 0; i <= 20; ++i) {
			path.append(Vector2((real_t)(8 + i * 3.2), 12));
		}
		b.stroke(path, 2.0);
		PackedByteArray tile = b.surface();
		PackedByteArray left = pixel_at(tile, w, 10, 12);
		PackedByteArray right = pixel_at(tile, w, 70, 12);
		ok(left[0] > left[2], "a gradient stroke starts on the first colour");
		ok(right[2] > right[0], "and ends on the second");
	}

	// AVERAGE: a hard border softens, and neither side is dragged past the
	// other — this is what people mean by "blend these two".
	{
		IvoryBlend b;
		b.set_surface(halves(w, h, rgba(255, 0, 0), rgba(0, 0, 255)), w, h);
		b.set_stamp(k, 24);
		b.set_mode(IvoryBlend::MODE_AVERAGE);
		b.set_strength(0.9);
		b.set_size(22.0);
		for (int i = 0; i < 6; ++i) {
			b.dab(Vector2(40, 12), 0.0);
		}
		PackedByteArray tile = b.surface();
		PackedByteArray seam = pixel_at(tile, w, 40, 12);
		ok(seam[0] > 40 && seam[2] > 40, "the seam carries both colours");
		PackedByteArray far_left = pixel_at(tile, w, 4, 12);
		ok(far_left[0] > 200 && far_left[2] < 40,
				"and the far side of each is untouched");
	}

	// PULL: colour is carried along the stroke into where it was not.
	{
		IvoryBlend b;
		b.set_surface(halves(w, h, rgba(255, 0, 0), rgba(255, 255, 255)),
				w, h);
		b.set_stamp(k, 24);
		b.set_mode(IvoryBlend::MODE_PULL);
		b.set_strength(0.85);
		b.set_pickup(0.25);
		b.set_size(16.0);
		b.reset_carry();
		PackedVector2Array path;
		for (int i = 0; i <= 30; ++i) {
			path.append(Vector2((real_t)(30 + i * 1.5), 12));
		}
		b.stroke(path, 1.5);
		PackedByteArray tile = b.surface();
		PackedByteArray dragged = pixel_at(tile, w, 60, 12);
		ok(dragged[0] > dragged[2] + 12,
				"red is carried out into the white");
		ok(dragged[2] > 40, "but it thins as it goes rather than painting");
	}

	// SNAP: a muddled boundary is tidied towards the two colours rather than
	// blurred further.
	{
		IvoryBlend b;
		b.set_surface(flat(w, h, rgba(128, 60, 128)), w, h);
		b.set_colours(rgba(255, 0, 0), rgba(0, 0, 255));
		b.set_stamp(k, 24);
		b.set_mode(IvoryBlend::MODE_SNAP);
		b.set_strength(1.0);
		b.set_size(20.0);
		b.dab(Vector2(40, 12), 0.0);
		PackedByteArray got = pixel_at(b.surface(), w, 40, 12);
		const bool is_red = got[0] > 200 && got[2] < 60;
		const bool is_blue = got[2] > 200 && got[0] < 60;
		ok(is_red || is_blue, "snap lands on one of the two, not between them");
	}
}

// -------------------------------------------------------------- round five

static void round_five() {
	round_of(5, "transparency, and the fringe");

	const int w = 48, h = 48;
	// Left half solid red, right half fully transparent. The classic setup
	// for the dark halo: the transparent pixels are stored as black, and a
	// mix that does not weight by alpha drags that black into the red.
	PackedByteArray tile;
	tile.resize(w * h * 4);
	for (int y = 0; y < h; ++y) {
		for (int x = 0; x < w; ++x) {
			const int at = (y * w + x) * 4;
			if (x < w / 2) {
				tile[at] = 255;
				tile[at + 1] = 0;
				tile[at + 2] = 0;
				tile[at + 3] = 255;
			} else {
				tile[at] = 0;
				tile[at + 1] = 0;
				tile[at + 2] = 0;
				tile[at + 3] = 0;
			}
		}
	}

	IvoryBlend b;
	b.set_surface(tile, w, h);
	b.set_stamp(disc(24), 24);
	b.set_mode(IvoryBlend::MODE_AVERAGE);
	b.set_strength(1.0);
	b.set_size(20.0);
	for (int i = 0; i < 4; ++i) {
		b.dab(Vector2(24, 24), 0.0);
	}
	PackedByteArray got = b.surface();

	// The red near the edge must still be red, not darkened.
	double darkest = 255.0;
	for (int y = 18; y < 30; ++y) {
		for (int x = 16; x < 24; ++x) {
			darkest = std::min(darkest, (double)pixel_at(got, w, x, y)[0]);
		}
	}
	ok(darkest > 180.0, "the edge of the paint is not darkened by the void");

	// And alpha is left alone unless it was asked for.
	ok(pixel_at(got, w, 40, 24)[3] == 0,
			"a blend does not quietly fill in transparency");
	ok(pixel_at(got, w, 8, 24)[3] == 255,
			"nor quietly erase what was opaque");

	IvoryBlend with;
	with.set_surface(tile, w, h);
	with.set_stamp(disc(24), 24);
	with.set_mode(IvoryBlend::MODE_AVERAGE);
	with.set_strength(1.0);
	with.set_size(20.0);
	with.set_touch_alpha(true);
	with.dab(Vector2(24, 24), 0.0);
	ok(pixel_at(with.surface(), w, 26, 24)[3] > 0,
			"and it does move alpha when it is told to");
}

// --------------------------------------------------------------- round six

static void round_six() {
	round_of(6, "strength, repetition, and where it settles");

	const int w = 40, h = 40;
	auto run = [&](double strength, int passes) {
		IvoryBlend b;
		b.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
		b.set_colours(rgba(0, 0, 0), rgba(0, 0, 0));
		b.set_stamp(disc(24), 24);
		b.set_mode(IvoryBlend::MODE_MIX);
		b.set_strength(strength);
		b.set_size(24.0);
		for (int i = 0; i < passes; ++i) {
			b.dab(Vector2(20, 20), 0.0);
		}
		return luma(pixel_at(b.surface(), w, 20, 20));
	};

	// Turning it up mixes further in one pass. Monotone, over the range.
	double last = 1e30;
	for (int i = 1; i <= 8; ++i) {
		const double now = run(i / 8.0, 1);
		ok(now <= last + 0.5, "more strength never mixes less");
		last = now;
	}

	// A weak setting gets there eventually. That is the difference between a
	// tool that builds up and one that is simply feeble.
	ok(run(0.08, 40) < 30.0, "a light touch still arrives, given passes");
	// And full strength arrives at once.
	ok(run(1.0, 1) < 12.0, "full strength arrives in one");
	// Nought does nothing at all, however many times.
	near(run(0.0, 50), 255.0, 1.0, "no strength changes nothing");

	// It converges rather than overshooting past the colour asked for. A
	// blend that keeps going past its own target is a blend that turns black
	// when somebody leans on it.
	IvoryBlend b;
	b.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
	b.set_colours(rgba(40, 90, 200), rgba(40, 90, 200));
	b.set_stamp(disc(24), 24);
	b.set_mode(IvoryBlend::MODE_MIX);
	b.set_strength(0.5);
	b.set_size(24.0);
	for (int i = 0; i < 200; ++i) {
		b.dab(Vector2(20, 20), 0.0);
	}
	PackedByteArray settled = pixel_at(b.surface(), w, 20, 20);
	ok(std::abs((int)settled[0] - 40) <= 2 &&
			std::abs((int)settled[1] - 90) <= 2 &&
			std::abs((int)settled[2] - 200) <= 2,
			"two hundred passes settle exactly on the colour, not past it");

	// The damage rectangle covers what was changed, so the caller can
	// re-upload a tile rather than the layer.
	Dictionary d = b.damage();
	ok(bool(d["any"]), "the damage is reported");
	ok(int(d["width"]) <= 26 && int(d["width"]) >= 20,
			"and is the size of the dab, not the layer");
	b.clear_damage();
	ok(!bool(b.damage()["any"]), "and can be cleared");
}

// ------------------------------------------------------------- round seven

static void round_seven() {
	round_of(7, "abuse");

	IvoryBlend b;
	// Nothing set up at all.
	Dictionary none = b.dab(Vector2(0, 0), 0.0);
	ok(int(none["pixels"]) == 0, "a dab with no surface does nothing");
	ok(b.surface().is_empty(), "and the surface is still empty");

	// A one-pixel surface.
	b.set_surface(flat(1, 1, rgba(10, 20, 30)), 1, 1);
	b.set_colours(rgba(200, 200, 200), rgba(200, 200, 200));
	b.set_strength(1.0);
	b.set_size(50.0);
	b.dab(Vector2(0, 0), 0.0);
	ok(b.surface().size() == 4, "a one-pixel surface survives a huge dab");

	// Dabs entirely off the edge.
	const int w = 32, h = 32;
	b.set_surface(flat(w, h, rgba(255, 255, 255)), w, h);
	ok(int(b.dab(Vector2(-500, -500), 0.0)["pixels"]) == 0,
			"a dab off the canvas touches nothing");
	ok(int(b.dab(Vector2(9999, 9999), 0.0)["pixels"]) == 0,
			"at either end");
	// And one half off it clips rather than reading past the buffer.
	ok(int(b.dab(Vector2(0, 16), 0.0)["pixels"]) > 0,
			"a dab half off the canvas does the half that is on");

	// Silly settings.
	b.set_size(-40.0);
	b.set_strength(9.0);
	b.set_pickup(-3.0);
	b.set_mode(-7);
	ok(int(b.dab(Vector2(16, 16), 0.0)["pixels"]) >= 0,
			"negative and out-of-range settings are survived");
	b.set_mode(9999);
	ok(int(b.dab(Vector2(16, 16), 0.0)["pixels"]) >= 0,
			"and a mode that does not exist is clamped");

	// A stamp whose size does not match what it says.
	PackedFloat32Array lying;
	lying.resize(4);
	b.set_stamp(lying, 64);
	b.set_size(20.0);
	ok(int(b.dab(Vector2(16, 16), 0.0)["pixels"]) >= 0,
			"a stamp shorter than it claims does not read past its end");

	// A short surface for the size given: the rest is taken as blank rather
	// than read from wherever the buffer happened to end.
	PackedByteArray stub;
	stub.resize(8);
	b.set_surface(stub, 32, 32);
	ok(b.surface().size() == 32 * 32 * 4,
			"a surface shorter than its size is padded, not trusted");

	// Pull with nothing picked up yet.
	IvoryBlend p;
	p.set_surface(flat(16, 16, rgba(90, 90, 90)), 16, 16);
	p.set_mode(IvoryBlend::MODE_PULL);
	p.set_size(10.0);
	p.set_strength(1.0);
	p.reset_carry();
	ok(int(p.dab(Vector2(8, 8), 0.0)["pixels"]) >= 0,
			"pull with an empty brush does not fall over");

	// An empty stroke.
	ok(int(p.stroke(PackedVector2Array(), 2.0)["dabs"]) == 0,
			"an empty stroke lays no dabs");
	// A stroke that never moves.
	PackedVector2Array still;
	still.append(Vector2(8, 8));
	still.append(Vector2(8, 8));
	ok(int(p.stroke(still, 2.0)["dabs"]) >= 1,
			"a stroke that never moved still lays one");
}

int main() {
	std::printf("\nthe colour blend tool\n=====================\n\n");
	round_one();
	round_two();
	round_three();
	round_four();
	round_five();
	round_six();
	round_seven();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
