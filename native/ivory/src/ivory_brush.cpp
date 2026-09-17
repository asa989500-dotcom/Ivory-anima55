#include "ivory_brush.h"
#include <godot_cpp/core/math_defs.hpp>
#include "ivory_brush_safety.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

} // namespace

void IvoryBrush::_bind_methods() {
	ClassDB::bind_method(D_METHOD("web", "px", "variant"), &IvoryBrush::web);
	ClassDB::bind_method(D_METHOD("halo", "px", "variant"), &IvoryBrush::halo);
	ClassDB::bind_method(D_METHOD("chalk", "px", "variant"), &IvoryBrush::chalk);
	ClassDB::bind_method(D_METHOD("stamp", "family", "px", "variant"),
			&IvoryBrush::stamp);
	ClassDB::bind_method(D_METHOD("knows", "family"), &IvoryBrush::knows);
}

// ---------------------------------------------------------------- randomness

uint32_t IvoryBrush::hash32(uint32_t x) {
	// Wang/Jenkins integer hash. Chosen because it avalanches — one bit in
	// changes about half the bits out — which is what makes a lattice of
	// hashed indices look scattered instead of striped.
	x ^= x >> 16;
	x *= 0x7feb352dU;
	x ^= x >> 15;
	x *= 0x846ca68bU;
	x ^= x >> 16;
	return x;
}

double IvoryBrush::unit(int64_t a, int64_t b, int64_t salt) {
	uint32_t h = hash32((uint32_t)(a * 0x9E3779B1LL));
	h = hash32(h ^ (uint32_t)(b * 0x85EBCA77LL));
	h = hash32(h ^ (uint32_t)(salt * 0xC2B2AE3DLL));
	return (double)h / 4294967296.0;
}

double IvoryBrush::signed_unit(int64_t a, int64_t b, int64_t salt) {
	return unit(a, b, salt) * 2.0 - 1.0;
}

double IvoryBrush::smooth_step(double edge0, double edge1, double x) {
	if (edge1 <= edge0) {
		return x < edge0 ? 0.0 : 1.0;
	}
	const double t = clampd((x - edge0) / (edge1 - edge0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

double IvoryBrush::value_noise(double x, double y, int64_t salt) {
	const double fx = std::floor(x);
	const double fy = std::floor(y);
	const int64_t ix = (int64_t)fx;
	const int64_t iy = (int64_t)fy;
	const double tx = x - fx;
	const double ty = y - fy;
	// Smoothstep on the interpolation weights, not linear. Linear
	// interpolation of a lattice leaves visible creases along the lattice
	// lines, and on a chalk stamp those creases read as scratches.
	const double sx = tx * tx * (3.0 - 2.0 * tx);
	const double sy = ty * ty * (3.0 - 2.0 * ty);
	const double a = unit(ix, iy, salt);
	const double b = unit(ix + 1, iy, salt);
	const double c = unit(ix, iy + 1, salt);
	const double d = unit(ix + 1, iy + 1, salt);
	const double top = a + (b - a) * sx;
	const double bottom = c + (d - c) * sx;
	return top + (bottom - top) * sy;
}

double IvoryBrush::fbm(double x, double y, int octaves, double gain,
		int64_t salt) {
	double sum = 0.0;
	double amp = 1.0;
	double norm = 0.0;
	double freq = 1.0;
	for (int i = 0; i < std::max(1, octaves); ++i) {
		sum += amp * value_noise(x * freq, y * freq, salt + i * 7919);
		norm += amp;
		amp *= gain;
		freq *= 2.0;
	}
	return norm > 0.0 ? sum / norm : 0.0;
}

// ------------------------------------------------------------- the cell web

PackedFloat32Array IvoryBrush::web(int px, int variant) const {
	const int n = std::max(px, 8);
	PackedFloat32Array out;
	out.resize(n * n);
	out.fill(0.0f);

	// Five nets. What separates them is the size of the cells, how thin the
	// strands are, and how much the junctions swell — which between them are
	// the whole look of one.
	int cells = 5;          // lattice divisions across the stamp
	double strand = 0.055;  // strand half-width, as a fraction of the stamp
	double node = 0.9;      // how much junctions swell
	double roam = 0.42;     // how far a seed may wander in its lattice cell
	double flow = 0.0;      // extra taper along a strand: the venom look
	int64_t salt = 1301;

	switch (variant) {
		case 1:
			// Fine: many small cells, thin strands. The mesh under a wing.
			cells = 9;
			strand = 0.030;
			node = 0.7;
			salt = 2711;
			break;
		case 2:
			// Coarse: a few large cells, heavy strands.
			cells = 3;
			strand = 0.085;
			node = 1.1;
			roam = 0.34;
			salt = 3319;
			break;
		case 3:
			// Venom. Strands that thin almost away along their length and
			// pool heavily where three cells meet, so the mark reads as
			// something flowing into its junctions rather than a grid of
			// wires crossing at them.
			cells = 6;
			strand = 0.022;
			node = 2.4;
			roam = 0.48;
			flow = 1.0;
			salt = 4441;
			break;
		case 4:
			// Torn: seeds allowed to wander to the edge of their cell, so
			// the cells vary wildly and some strands nearly close up.
			cells = 7;
			strand = 0.045;
			node = 0.55;
			roam = 0.49;
			salt = 5557;
			break;
		default:
			break;
	}

	// One seed per lattice cell, displaced within it. See the header: free
	// scattering clumps, and a clump in a cell network is a cell too small
	// to see beside a cell the size of a thumb.
	//
	// A one-cell margin all round, so the network does not simply stop at
	// the edge of the stamp with cells that have nothing on their far side.
	const int span = cells + 4;
	std::vector<Vector2> seed;
	seed.reserve((size_t)(span * span));
	const double cell_px = (double)n / (double)cells;
	for (int gy = -2; gy < cells + 2; ++gy) {
		for (int gx = -2; gx < cells + 2; ++gx) {
			const double jx = signed_unit(gx, gy, salt) * roam;
			const double jy = signed_unit(gx, gy, salt + 17) * roam;
			seed.push_back(Vector2(
					(real_t)((gx + 0.5 + jx) * cell_px),
					(real_t)((gy + 0.5 + jy) * cell_px)));
		}
	}

	const double half = (double)n * 0.5;
	const double strand_px = strand * (double)n;
	const double node_px = strand_px * (1.0 + node * 2.0);

	for (int y = 0; y < n; ++y) {
		for (int x = 0; x < n; ++x) {
			const Vector2 p((real_t)(x + 0.5), (real_t)(y + 0.5));
			// Nearest three seeds. Kept as a running podium rather than by
			// sorting: three comparisons a seed beats sorting a few hundred.
			double f1 = 1e30, f2 = 1e30, f3 = 1e30;
			for (const Vector2 &s : seed) {
				const double d = p.distance_squared_to(s);
				if (d < f1) {
					f3 = f2; f2 = f1; f1 = d;
				} else if (d < f2) {
					f3 = f2; f2 = d;
				} else if (d < f3) {
					f3 = d;
				}
			}
			f1 = std::sqrt(f1);
			f2 = std::sqrt(f2);
			f3 = std::sqrt(f3);

			// The border between two cells is where the nearest two seeds
			// are equidistant. This is the Voronoi edge, exactly.
			const double edge = f2 - f1;
			// And a junction is where the nearest three are. The strand
			// swells here and nowhere else.
			const double junction = f3 - f1;
			const double swell = 1.0 - smooth_step(0.0, node_px, junction);
			double width = strand_px + (node_px - strand_px) * swell;

			if (flow > 0.0) {
				// A slow drift along the strand, so its thickness is not
				// constant between two junctions. Without this the venom
				// variant is a thin grid with fat corners; with it, it
				// visibly runs.
				const double drift = fbm(p.x / (cell_px * 0.8),
						p.y / (cell_px * 0.8), 2, 0.5, salt + 91);
				width *= 1.0 - flow * 0.55 * (1.0 - drift);
			}
			width = std::max(width, 0.35);

			double a = 1.0 - smooth_step(width * 0.45, width, edge);

			// The stamp has to fade at its own edge or every dab prints its
			// own square outline. A cosine shoulder over the outer fifth.
			const double r = std::sqrt((p.x - half) * (p.x - half) +
					(p.y - half) * (p.y - half)) / half;
			a *= 1.0 - smooth_step(0.72, 1.0, r);

			out[y * n + x] = (float)clampd(a, 0.0, 1.0);
		}
	}
	return out;
}

// ---------------------------------------------------------------- the halos

PackedFloat32Array IvoryBrush::halo(int px, int variant) const {
	const int n = std::max(px, 8);
	PackedFloat32Array out;
	out.resize(n * n);
	out.fill(0.0f);

	int rings = 110;        // how many circles
	double r_min = 0.030;   // radius range, as a fraction of the stamp
	double r_max = 0.150;
	double band = 0.011;    // how thick a ring's line is
	double fill = 0.0;      // how much of a ring is filled in
	int64_t salt = 6101;

	switch (variant) {
		case 1:
			// Sparse and large: a few wide halos, the out-of-focus kind.
			rings = 34;
			r_min = 0.090;
			r_max = 0.310;
			band = 0.009;
			salt = 6217;
			break;
		case 2:
			// Dense and small: foam. This is the one nearest the reference
			// sheet, where the circles are packed edge to edge.
			rings = 260;
			r_min = 0.018;
			r_max = 0.078;
			band = 0.007;
			salt = 6329;
			break;
		case 3:
			// Bubbles: the rings carry a little wash inside them, so they
			// read as things with a surface rather than as outlines.
			rings = 90;
			r_min = 0.040;
			r_max = 0.190;
			band = 0.013;
			fill = 0.22;
			salt = 6449;
			break;
		case 4:
			// Tangled: many, wide radius spread, thin line. Crossings
			// everywhere, which is what the screen operator is for.
			rings = 320;
			r_min = 0.016;
			r_max = 0.240;
			band = 0.0055;
			salt = 6577;
			break;
		default:
			break;
	}

	const double half = (double)n * 0.5;
	const double band_px = std::max(band * (double)n, 0.8);

	for (int i = 0; i < rings; ++i) {
		// Ring centres are pushed towards the middle by taking the square
		// root of a uniform radius — otherwise a uniform disc of centres
		// leaves the middle of the stamp visibly emptier than its rim.
		const double ang = unit(i, 1, salt) * TAU;
		const double rad = std::sqrt(unit(i, 2, salt)) * half * 0.86;
		const double cx = half + std::cos(ang) * rad;
		const double cy = half + std::sin(ang) * rad;
		// Small radii are more common than large ones, which is what a
		// squared unit gives and what foam actually looks like.
		const double t = unit(i, 3, salt);
		const double rr = (r_min + (r_max - r_min) * t * t) * (double)n;
		const double strength = 0.55 + 0.45 * unit(i, 4, salt);

		const int x0 = std::max(0, (int)std::floor(cx - rr - band_px * 3));
		const int x1 = std::min(n - 1, (int)std::ceil(cx + rr + band_px * 3));
		const int y0 = std::max(0, (int)std::floor(cy - rr - band_px * 3));
		const int y1 = std::min(n - 1, (int)std::ceil(cy + rr + band_px * 3));

		for (int y = y0; y <= y1; ++y) {
			for (int x = x0; x <= x1; ++x) {
				const double dx = (double)x + 0.5 - cx;
				const double dy = (double)y + 0.5 - cy;
				const double d = std::sqrt(dx * dx + dy * dy);
				const double off = (d - rr) / band_px;
				double a = std::exp(-off * off) * strength;
				if (fill > 0.0 && d < rr) {
					a = std::max(a, fill * strength *
							(1.0 - smooth_step(rr * 0.5, rr, d)));
				}
				if (a <= 0.002) {
					continue;
				}
				// Screened, not added. See the header — adding saturates
				// every crossing to solid white and the crossings are the
				// whole texture.
				const int at = y * n + x;
				const double was = out[at];
				out[at] = (float)(1.0 - (1.0 - was) * (1.0 - a));
			}
		}
	}

	for (int y = 0; y < n; ++y) {
		for (int x = 0; x < n; ++x) {
			const double dx = (double)x + 0.5 - half;
			const double dy = (double)y + 0.5 - half;
			const double r = std::sqrt(dx * dx + dy * dy) / half;
			const double fade = 1.0 - smooth_step(0.70, 1.0, r);
			out[y * n + x] = (float)clampd((double)out[y * n + x] * fade,
					0.0, 1.0);
		}
	}
	return out;
}

// ---------------------------------------------------------------- the chalk

PackedFloat32Array IvoryBrush::chalk(int px, int variant) const {
	const int n = std::max(px, 8);
	PackedFloat32Array out;
	out.resize(n * n);
	out.fill(0.0f);

	double grain = 9.0;     // how coarse the tooth is
	double bite = 0.42;     // how much of the grain is taken away
	double core = 0.42;     // how much of the stamp keeps nearly everything
	double squash = 1.0;    // above one, the stamp is a chisel
	int octaves = 3;
	int64_t salt = 7717;

	switch (variant) {
		case 1:
			// Fine: a hard thin stick of chalk, small grain, light bite.
			grain = 16.0;
			bite = 0.26;
			core = 0.55;
			salt = 7841;
			break;
		case 2:
			// Broad: a wide flat side of the stick. Squashed, so the mark
			// thickens and thins with its heading.
			grain = 7.0;
			bite = 0.40;
			core = 0.34;
			squash = 2.1;
			salt = 7963;
			break;
		case 3:
			// Worn: bitten deep and coarse, most of the middle broken too.
			// The end of a stub that has been used down to nothing.
			grain = 5.0;
			bite = 0.72;
			core = 0.14;
			octaves = 4;
			salt = 8087;
			break;
		case 4:
			// Soft pastel: barely any tooth, a wide soft body. It builds up
			// over passes rather than covering in one.
			grain = 11.0;
			bite = 0.18;
			core = 0.20;
			salt = 8209;
			break;
		default:
			break;
	}

	const double half = (double)n * 0.5;
	for (int y = 0; y < n; ++y) {
		for (int x = 0; x < n; ++x) {
			double dx = ((double)x + 0.5 - half) / half;
			double dy = ((double)y + 0.5 - half) / half;
			dy *= squash;
			const double r = std::sqrt(dx * dx + dy * dy);
			if (r >= 1.0) {
				continue;
			}
			// The body of the mark: full in the middle, falling away.
			double body = 1.0 - smooth_step(core, 1.0, r);

			// The tooth of the paper.
			const double g = fbm((double)x / (double)n * grain,
					(double)y / (double)n * grain, octaves, 0.55, salt);

			// The threshold rises towards the edges, so the middle keeps
			// nearly all of the grain and the edges keep only its peaks.
			// A flat threshold gives a stripe with holes punched in it,
			// which reads as a broken brush rather than as chalk.
			const double level = bite * (0.35 + 0.65 * smooth_step(core * 0.6,
					1.0, r));
			const double kept = smooth_step(level, level + 0.28, g);

			out[y * n + x] = (float)clampd(body * kept, 0.0, 1.0);
		}
	}
	return out;
}

// ------------------------------------------------------------------ dispatch

bool IvoryBrush::knows(const String &family) const {
	return family == String("web") || family == String("halo") ||
			family == String("chalk");
}

PackedFloat32Array IvoryBrush::stamp(const String &family, int px,
		int variant) const {
	if (!ivory::BrushSafety13::positive_size(px)) {
		return PackedFloat32Array();
	}
	const int v = std::max(0, std::min(variant, 4));
	if (family == String("web")) {
		return web(px, v);
	}
	if (family == String("halo")) {
		return halo(px, v);
	}
	if (family == String("chalk")) {
		return chalk(px, v);
	}
	return PackedFloat32Array();
}
