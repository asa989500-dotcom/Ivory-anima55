#include "ivory_blend.h"

#include <algorithm>
#include <cmath>

using namespace godot;

double IvoryBlend::decode_[256] = { 0.0 };
bool IvoryBlend::table_built_ = false;

namespace {

double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

} // namespace

void IvoryBlend::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_surface", "rgba", "width", "height"),
			&IvoryBlend::set_surface);
	ClassDB::bind_method(D_METHOD("surface"), &IvoryBlend::surface);
	ClassDB::bind_method(D_METHOD("width"), &IvoryBlend::width);
	ClassDB::bind_method(D_METHOD("height"), &IvoryBlend::height);
	ClassDB::bind_method(D_METHOD("set_colours", "first", "second"),
			&IvoryBlend::set_colours);
	ClassDB::bind_method(D_METHOD("set_stamp", "weights", "px"),
			&IvoryBlend::set_stamp);
	ClassDB::bind_method(D_METHOD("set_strength", "strength"),
			&IvoryBlend::set_strength);
	ClassDB::bind_method(D_METHOD("set_size", "size"), &IvoryBlend::set_size);
	ClassDB::bind_method(D_METHOD("set_pickup", "pickup"),
			&IvoryBlend::set_pickup);
	ClassDB::bind_method(D_METHOD("set_mode", "mode"), &IvoryBlend::set_mode);
	ClassDB::bind_method(D_METHOD("set_touch_alpha", "on"),
			&IvoryBlend::set_touch_alpha);
	ClassDB::bind_method(D_METHOD("reset_carry"), &IvoryBlend::reset_carry);
	ClassDB::bind_method(D_METHOD("dab", "at", "t"), &IvoryBlend::dab);
	ClassDB::bind_method(D_METHOD("stroke", "path", "spacing"),
			&IvoryBlend::stroke);
	ClassDB::bind_method(D_METHOD("damage"), &IvoryBlend::damage);
	ClassDB::bind_method(D_METHOD("clear_damage"), &IvoryBlend::clear_damage);
	ClassDB::bind_static_method("IvoryBlend", D_METHOD("mix_srgb", "a", "b",
			"t"), &IvoryBlend::mix_srgb);
	ClassDB::bind_static_method("IvoryBlend", D_METHOD("to_oklab", "srgb"),
			&IvoryBlend::to_oklab);
	ClassDB::bind_static_method("IvoryBlend", D_METHOD("from_oklab", "lab",
			"alpha"), &IvoryBlend::from_oklab);
}

IvoryBlend::IvoryBlend() {
	build_table();
}

void IvoryBlend::build_table() {
	if (table_built_) {
		return;
	}
	for (int i = 0; i < 256; ++i) {
		const double c = (double)i / 255.0;
		// The real piecewise sRGB transfer function, not the 2.2 shorthand.
		// They differ most in the darks, which is exactly where a blend that
		// is slightly wrong looks muddy.
		decode_[i] = c <= 0.04045 ? c / 12.92
				: std::pow((c + 0.055) / 1.055, 2.4);
	}
	table_built_ = true;
}

uint8_t IvoryBlend::encode(double linear) {
	const double c = clampd(linear, 0.0, 1.0);
	const double s = c <= 0.0031308 ? c * 12.92
			: 1.055 * std::pow(c, 1.0 / 2.4) - 0.055;
	return (uint8_t)clampd(std::round(s * 255.0), 0.0, 255.0);
}

// ------------------------------------------------------------------- OKLab

IvoryBlend::Lab IvoryBlend::lab_from_linear(double r, double g, double b,
		double a) {
	// Ottosson's matrices, verbatim. The cube root is the whole of the
	// perceptual part: it is what makes equal steps in `l` look like equal
	// steps in lightness.
	const double l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
	const double m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
	const double s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

	const double l_ = std::cbrt(l);
	const double m_ = std::cbrt(m);
	const double s_ = std::cbrt(s);

	Lab out;
	out.l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
	out.a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
	out.b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
	out.alpha = a;
	return out;
}

void IvoryBlend::linear_from_lab(const Lab &in, double &r, double &g,
		double &b) {
	const double l_ = in.l + 0.3963377774 * in.a + 0.2158037573 * in.b;
	const double m_ = in.l - 0.1055613458 * in.a - 0.0638541728 * in.b;
	const double s_ = in.l - 0.0894841775 * in.a - 1.2914855480 * in.b;

	const double l = l_ * l_ * l_;
	const double m = m_ * m_ * m_;
	const double s = s_ * s_ * s_;

	r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
	g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
	b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
}

IvoryBlend::Lab IvoryBlend::lab_of_bytes(const uint8_t *rgba) {
	return lab_from_linear(decode_[rgba[0]], decode_[rgba[1]],
			decode_[rgba[2]], (double)rgba[3] / 255.0);
}

void IvoryBlend::bytes_of_lab(const Lab &in, uint8_t *rgba, bool with_alpha) {
	double r, g, b;
	linear_from_lab(in, r, g, b);
	rgba[0] = encode(r);
	rgba[1] = encode(g);
	rgba[2] = encode(b);
	if (with_alpha) {
		rgba[3] = (uint8_t)clampd(std::round(in.alpha * 255.0), 0.0, 255.0);
	}
}

IvoryBlend::Lab IvoryBlend::lerp_lab(const Lab &a, const Lab &b, double t) {
	Lab out;
	out.l = a.l + (b.l - a.l) * t;
	out.a = a.a + (b.a - a.a) * t;
	out.b = a.b + (b.b - a.b) * t;
	out.alpha = a.alpha + (b.alpha - a.alpha) * t;
	return out;
}

double IvoryBlend::lab_distance(const Lab &a, const Lab &b) {
	const double dl = a.l - b.l;
	const double da = a.a - b.a;
	const double db = a.b - b.b;
	return std::sqrt(dl * dl + da * da + db * db);
}

PackedFloat32Array IvoryBlend::to_oklab(const PackedByteArray &srgb) {
	build_table();
	PackedFloat32Array out;
	out.resize(3);
	if (srgb.size() < 3) {
		return out;
	}
	const Lab lab = lab_from_linear(decode_[srgb[0]], decode_[srgb[1]],
			decode_[srgb[2]], 1.0);
	out[0] = (float)lab.l;
	out[1] = (float)lab.a;
	out[2] = (float)lab.b;
	return out;
}

PackedByteArray IvoryBlend::from_oklab(const PackedFloat32Array &lab,
		int alpha) {
	build_table();
	PackedByteArray out;
	out.resize(4);
	if (lab.size() < 3) {
		return out;
	}
	Lab in;
	in.l = lab[0];
	in.a = lab[1];
	in.b = lab[2];
	in.alpha = clampd((double)alpha / 255.0, 0.0, 1.0);
	uint8_t rgba[4] = { 0, 0, 0, 0 };
	bytes_of_lab(in, rgba, true);
	for (int i = 0; i < 4; ++i) {
		out[i] = rgba[i];
	}
	return out;
}

PackedByteArray IvoryBlend::mix_srgb(const PackedByteArray &a,
		const PackedByteArray &b, double t) {
	build_table();
	PackedByteArray out;
	out.resize(4);
	if (a.size() < 3 || b.size() < 3) {
		return out;
	}
	const double w = clampd(t, 0.0, 1.0);
	const Lab la = lab_from_linear(decode_[a[0]], decode_[a[1]], decode_[a[2]],
			a.size() > 3 ? (double)a[3] / 255.0 : 1.0);
	const Lab lb = lab_from_linear(decode_[b[0]], decode_[b[1]], decode_[b[2]],
			b.size() > 3 ? (double)b[3] / 255.0 : 1.0);
	uint8_t rgba[4] = { 0, 0, 0, 255 };
	bytes_of_lab(lerp_lab(la, lb, w), rgba, true);
	for (int i = 0; i < 4; ++i) {
		out[i] = rgba[i];
	}
	return out;
}

// ---------------------------------------------------------------- the state

void IvoryBlend::set_surface(const PackedByteArray &rgba, int width,
		int height) {
	w_ = std::max(width, 0);
	h_ = std::max(height, 0);
	pixel_.assign((size_t)std::max(w_ * h_ * 4, 0), 0);
	const int have = std::min(rgba.size(), (int)pixel_.size());
	for (int i = 0; i < have; ++i) {
		pixel_[(size_t)i] = rgba[i];
	}
	clear_damage();
}

PackedByteArray IvoryBlend::surface() const {
	PackedByteArray out;
	out.resize((int)pixel_.size());
	for (size_t i = 0; i < pixel_.size(); ++i) {
		out[(int)i] = pixel_[i];
	}
	return out;
}

void IvoryBlend::set_colours(const PackedByteArray &first,
		const PackedByteArray &second) {
	uint8_t a[4] = { 0, 0, 0, 255 };
	uint8_t b[4] = { 255, 255, 255, 255 };
	for (int i = 0; i < 4 && i < first.size(); ++i) {
		a[i] = first[i];
	}
	for (int i = 0; i < 4 && i < second.size(); ++i) {
		b[i] = second[i];
	}
	first_ = lab_of_bytes(a);
	second_ = lab_of_bytes(b);
}

void IvoryBlend::set_stamp(const PackedFloat32Array &weights, int px) {
	stamp_px_ = std::max(px, 0);
	stamp_.assign((size_t)std::max(stamp_px_ * stamp_px_, 0), 0.0f);
	const int have = std::min(weights.size(), (int)stamp_.size());
	for (int i = 0; i < have; ++i) {
		stamp_[(size_t)i] = (float)clampd(weights[i], 0.0, 1.0);
	}
}

void IvoryBlend::set_strength(double strength) {
	strength_ = clampd(strength, 0.0, 1.0);
}

void IvoryBlend::set_size(double size) {
	size_ = std::max(size, 1.0);
}

void IvoryBlend::set_pickup(double pickup) {
	pickup_ = clampd(pickup, 0.0, 1.0);
}

void IvoryBlend::set_mode(int mode) {
	mode_ = std::max(0, std::min(mode, (int)MODE_SNAP));
}

void IvoryBlend::set_touch_alpha(bool on) {
	touch_alpha_ = on;
}

void IvoryBlend::reset_carry() {
	carrying_ = false;
}

// -------------------------------------------------------------- the kernel

double IvoryBlend::weight_at(double u, double v) const {
	// `u` and `v` run nought to one across the dab.
	if (stamp_px_ <= 0 || stamp_.empty()) {
		// No stamp given: a soft round, so the tool is usable before a brush
		// has been chosen rather than doing nothing and looking broken.
		const double dx = u - 0.5, dy = v - 0.5;
		const double r = std::sqrt(dx * dx + dy * dy) * 2.0;
		if (r >= 1.0) {
			return 0.0;
		}
		const double f = 1.0 - r;
		return f * f * (3.0 - 2.0 * f);
	}
	// Bilinear, so a stamp scaled up does not show its own pixels. A blend
	// tool that prints the stamp's staircase along a soft edge is worse than
	// no texture at all.
	const double fx = clampd(u, 0.0, 1.0) * (double)(stamp_px_ - 1);
	const double fy = clampd(v, 0.0, 1.0) * (double)(stamp_px_ - 1);
	const int x0 = (int)fx;
	const int y0 = (int)fy;
	const int x1 = std::min(x0 + 1, stamp_px_ - 1);
	const int y1 = std::min(y0 + 1, stamp_px_ - 1);
	const double tx = fx - x0;
	const double ty = fy - y0;
	const double a = stamp_[(size_t)(y0 * stamp_px_ + x0)];
	const double b = stamp_[(size_t)(y0 * stamp_px_ + x1)];
	const double c = stamp_[(size_t)(y1 * stamp_px_ + x0)];
	const double d = stamp_[(size_t)(y1 * stamp_px_ + x1)];
	const double top = a + (b - a) * tx;
	const double bottom = c + (d - c) * tx;
	return top + (bottom - top) * ty;
}

void IvoryBlend::touch(int x0, int y0, int x1, int y1) {
	if (dirty_x1_ < dirty_x0_) {
		dirty_x0_ = x0;
		dirty_y0_ = y0;
		dirty_x1_ = x1;
		dirty_y1_ = y1;
		return;
	}
	dirty_x0_ = std::min(dirty_x0_, x0);
	dirty_y0_ = std::min(dirty_y0_, y0);
	dirty_x1_ = std::max(dirty_x1_, x1);
	dirty_y1_ = std::max(dirty_y1_, y1);
}

void IvoryBlend::clear_damage() {
	dirty_x0_ = 0;
	dirty_y0_ = 0;
	dirty_x1_ = -1;
	dirty_y1_ = -1;
}

Dictionary IvoryBlend::damage() const {
	Dictionary out;
	const bool any = dirty_x1_ >= dirty_x0_;
	out["any"] = any;
	out["x"] = any ? dirty_x0_ : 0;
	out["y"] = any ? dirty_y0_ : 0;
	out["width"] = any ? dirty_x1_ - dirty_x0_ + 1 : 0;
	out["height"] = any ? dirty_y1_ - dirty_y0_ + 1 : 0;
	return out;
}

// ------------------------------------------------------------------- a dab

Dictionary IvoryBlend::dab(const Vector2 &at, double t) {
	Dictionary out;
	out["pixels"] = 0;
	out["moved"] = 0.0;
	if (w_ <= 0 || h_ <= 0 || pixel_.empty()) {
		return out;
	}

	const double radius = size_ * 0.5;
	const int x0 = std::max(0, (int)std::floor(at.x - radius));
	const int x1 = std::min(w_ - 1, (int)std::ceil(at.x + radius));
	const int y0 = std::max(0, (int)std::floor(at.y - radius));
	const int y1 = std::min(h_ - 1, (int)std::ceil(at.y + radius));
	if (x1 < x0 || y1 < y0) {
		return out;
	}

	// Modes that need to know what is already there read it first, in one
	// pass, before anything is written. Reading and writing in the same pass
	// would make the answer depend on which corner the loop started at.
	Lab pooled;
	bool have_pool = false;
	if (mode_ == MODE_AVERAGE || mode_ == MODE_PULL) {
		double sum_l = 0.0, sum_a = 0.0, sum_b = 0.0, sum_w = 0.0;
		double sum_alpha = 0.0;
		for (int y = y0; y <= y1; ++y) {
			for (int x = x0; x <= x1; ++x) {
				const double u = (x + 0.5 - (at.x - radius)) / size_;
				const double v = (y + 0.5 - (at.y - radius)) / size_;
				const double k = weight_at(u, v);
				if (k <= 0.0) {
					continue;
				}
				const uint8_t *px = &pixel_[(size_t)((y * w_ + x) * 4)];
				const Lab lab = lab_of_bytes(px);
				// Premultiplied: a transparent pixel contributes its
				// transparency and not its colour. See the header — this is
				// what removes the fringe along every edge.
				const double weight = k * lab.alpha;
				sum_l += lab.l * weight;
				sum_a += lab.a * weight;
				sum_b += lab.b * weight;
				sum_alpha += lab.alpha * k;
				sum_w += weight;
			}
		}
		if (sum_w > 1e-9) {
			pooled.l = sum_l / sum_w;
			pooled.a = sum_a / sum_w;
			pooled.b = sum_b / sum_w;
			pooled.alpha = clampd(sum_alpha / std::max(sum_w, 1e-9), 0.0, 1.0);
			have_pool = true;
		}
	}

	if (mode_ == MODE_PULL && have_pool) {
		if (!carrying_) {
			carry_ = pooled;
			carrying_ = true;
		} else {
			// The brush loses a share of what it holds to what it is passing
			// over. At pickup one it forgets instantly and smudges nothing;
			// at nought it carries the first colour the whole way, which is
			// a paint tool rather than a blend one. Between them it does
			// what a finger through wet paint does.
			carry_ = lerp_lab(carry_, pooled, pickup_);
		}
	}

	int touched = 0;
	double moved = 0.0;
	const double gradient_t = clampd(t, 0.0, 1.0);

	for (int y = y0; y <= y1; ++y) {
		for (int x = x0; x <= x1; ++x) {
			const double u = (x + 0.5 - (at.x - radius)) / size_;
			const double v = (y + 0.5 - (at.y - radius)) / size_;
			const double k = weight_at(u, v);
			if (k <= 0.0) {
				continue;
			}
			const double amount = clampd(k * strength_, 0.0, 1.0);
			if (amount <= 0.0) {
				continue;
			}
			uint8_t *px = &pixel_[(size_t)((y * w_ + x) * 4)];
			const Lab was = lab_of_bytes(px);

			Lab target = was;
			switch (mode_) {
				case MODE_MIX:
					target = lerp_lab(first_, second_, gradient_t);
					break;
				case MODE_GRADIENT:
					target = lerp_lab(first_, second_, gradient_t);
					break;
				case MODE_PULL:
					if (!carrying_) {
						continue;
					}
					target = carry_;
					break;
				case MODE_AVERAGE:
					if (!have_pool) {
						continue;
					}
					target = pooled;
					break;
				case MODE_SNAP: {
					// Towards whichever of the two it already resembles.
					// Distance in OKLab is a perceptual distance, so "looks
					// more like" is exactly what is being measured.
					const double da = lab_distance(was, first_);
					const double db = lab_distance(was, second_);
					target = da <= db ? first_ : second_;
					break;
				}
				default:
					break;
			}

			Lab now = lerp_lab(was, target, amount);
			if (!touch_alpha_) {
				now.alpha = was.alpha;
			}
			bytes_of_lab(now, px, true);
			moved += lab_distance(was, now);
			++touched;
		}
	}

	if (touched > 0) {
		touch(x0, y0, x1, y1);
	}
	out["pixels"] = touched;
	out["moved"] = moved;
	out["carrying"] = carrying_;
	return out;
}

Dictionary IvoryBlend::stroke(const PackedVector2Array &path, double spacing) {
	Dictionary out;
	int pixels = 0;
	int dabs = 0;
	double moved = 0.0;
	if (path.size() == 0) {
		out["pixels"] = 0;
		out["dabs"] = 0;
		out["moved"] = 0.0;
		return out;
	}

	// Total length first, so that `t` is a real fraction of the stroke. A
	// gradient that used the point index instead would bunch wherever the
	// finger moved slowly, which is at both ends of every stroke a person
	// draws.
	double total = 0.0;
	for (int i = 0; i + 1 < path.size(); ++i) {
		total += path[i].distance_to(path[i + 1]);
	}

	const double step = std::max(spacing, 0.25);
	if (path.size() == 1 || total < 1e-9) {
		Dictionary one = dab(path[0], 0.0);
		out["pixels"] = one["pixels"];
		out["dabs"] = 1;
		out["moved"] = one["moved"];
		return out;
	}

	double walked = 0.0;
	double next_at = 0.0;
	for (int i = 0; i + 1 < path.size(); ++i) {
		const Vector2 a = path[i];
		const Vector2 b = path[i + 1];
		const double leg = a.distance_to(b);
		if (leg < 1e-9) {
			continue;
		}
		while (next_at <= walked + leg) {
			const double f = (next_at - walked) / leg;
			const Vector2 at = a.lerp(b, (real_t)f);
			Dictionary one = dab(at, next_at / total);
			pixels += (int)one["pixels"];
			moved += (double)one["moved"];
			++dabs;
			next_at += step;
		}
		walked += leg;
	}

	out["pixels"] = pixels;
	out["dabs"] = dabs;
	out["moved"] = moved;
	return out;
}
