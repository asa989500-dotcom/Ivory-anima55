#include "ivory_skin.h"

#include <godot_cpp/variant/packed_byte_array.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

void IvorySkin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("read_islands", "art", "cells"),
			&IvorySkin::read_islands);
	ClassDB::bind_method(D_METHOD("deform", "rest_points", "point_island",
								 "rest_a", "rest_b", "now_a", "now_b",
								 "bone_island"),
			&IvorySkin::deform);
	ClassDB::bind_method(D_METHOD("preserve_volume", "now_points",
								 "rest_points", "triangles", "point_island",
								 "strength", "iterations"),
			&IvorySkin::preserve_volume);
}

IvorySkin::IvorySkin() {}
IvorySkin::~IvorySkin() {}

// ------------------------------------------------------------------ islands

PackedInt32Array IvorySkin::read_islands(const Ref<Image> &art, int cells) {
	PackedInt32Array out;
	if (art.is_null()) {
		return out;
	}
	const int across = cells > 1 ? cells : 1;
	const int down = across;
	const int w = art->get_width();
	const int h = art->get_height();
	out.resize((across + 1) * (across + 1));
	if (w < 1 || h < 1) {
		return out;
	}

	// The layer is eight-bit RGBA. Anything else is converted once here rather
	// than being guessed at pixel by pixel.
	Ref<Image> pic = art;
	if (pic->get_format() != Image::FORMAT_RGBA8) {
		pic = art->duplicate();
		pic->convert(Image::FORMAT_RGBA8);
	}
	const PackedByteArray raw = pic->get_data();
	if (raw.size() < (int64_t)w * h * 4) {
		return out;
	}
	const uint8_t *bytes = raw.ptr();

	// A cell counts as ink if anything in it is more than faintly solid, and
	// every pixel of the cell is looked at. A sampled cell can miss a thin
	// stroke crossing between the samples, and a cell wrongly called empty is
	// a piece of drawing with no mesh under it — which a bone cannot reach and
	// a pose leaves standing still.
	std::vector<uint8_t> filled((size_t)across * down, 0);
	for (int cy = 0; cy < down; cy++) {
		const int y0 = (int)((int64_t)cy * h / down);
		int y1 = (int)((int64_t)(cy + 1) * h / down);
		if (y1 <= y0) {
			y1 = y0 + 1;
		}
		if (y1 > h) {
			y1 = h;
		}
		for (int cx = 0; cx < across; cx++) {
			const int x0 = (int)((int64_t)cx * w / across);
			int x1 = (int)((int64_t)(cx + 1) * w / across);
			if (x1 <= x0) {
				x1 = x0 + 1;
			}
			if (x1 > w) {
				x1 = w;
			}
			bool here = false;
			for (int y = y0; y < y1 && !here; y++) {
				const uint8_t *row = bytes + (size_t)y * w * 4;
				for (int x = x0; x < x1; x++) {
					if (row[(size_t)x * 4 + 3] > 16) {
						here = true;
						break;
					}
				}
			}
			filled[(size_t)cy * across + cx] = here ? 1 : 0;
		}
	}

	// Eight-connected flood fill over the occupancy grid. Two cells carry the
	// same number only if you could walk from one to the other without leaving
	// the ink.
	std::vector<int32_t> label((size_t)across * down, 0);
	std::vector<int32_t> queue;
	queue.reserve((size_t)across * down);
	int32_t next = 0;
	for (int start = 0; start < across * down; start++) {
		if (!filled[start] || label[start] != 0) {
			continue;
		}
		next++;
		label[start] = next;
		queue.clear();
		queue.push_back(start);
		size_t head = 0;
		while (head < queue.size()) {
			const int at = queue[head++];
			const int ax = at % across;
			const int ay = at / across;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					const int nx = ax + dx;
					const int ny = ay + dy;
					if (nx < 0 || ny < 0 || nx >= across || ny >= down) {
						continue;
					}
					const int nat = ny * across + nx;
					if (!filled[nat] || label[nat] != 0) {
						continue;
					}
					label[nat] = next;
					queue.push_back(nat);
				}
			}
		}
	}

	// The mesh has one more point than it has cells in each direction, and a
	// point sits at a corner where up to four cells meet. It takes the island
	// of whichever of them has ink, so the edge of a drawing belongs to the
	// drawing rather than to the paper beside it.
	for (int gy = 0; gy <= across; gy++) {
		for (int gx = 0; gx <= across; gx++) {
			int32_t found = 0;
			for (int dy = -1; dy <= 0; dy++) {
				for (int dx = -1; dx <= 0; dx++) {
					const int cx = gx + dx;
					const int cy = gy + dy;
					if (cx < 0 || cy < 0 || cx >= across || cy >= down) {
						continue;
					}
					const int32_t lab = label[(size_t)cy * across + cx];
					if (lab != 0) {
						found = lab;
					}
				}
			}
			out[gy * (across + 1) + gx] = found;
		}
	}
	return out;
}

// ---------------------------------------------------------------- the skin

PackedVector2Array IvorySkin::deform(const PackedVector2Array &rest_points,
		const PackedInt32Array &point_island, const PackedVector2Array &rest_a,
		const PackedVector2Array &rest_b, const PackedVector2Array &now_a,
		const PackedVector2Array &now_b, const PackedInt32Array &bone_island) {
	PackedVector2Array out = rest_points;
	const int points = rest_points.size();
	int bones = std::min((int)rest_a.size(), (int)rest_b.size());
	bones = std::min(bones, std::min((int)now_a.size(), (int)now_b.size()));
	if (points == 0 || bones == 0) {
		return out;
	}
	const bool by_island = point_island.size() == points;

	// Worked out once for the whole skin rather than once per point. This runs
	// for a thousand points on every frame of a pose, and the turn of a bone
	// is the same for all of them.
	std::vector<Vector2> span(bones), moved(bones);
	std::vector<double> len2(bones), reach2(bones), tcos(bones), tsin(bones);
	std::vector<int32_t> mine(bones, 0);
	for (int i = 0; i < bones; i++) {
		const Vector2 s = rest_b[i] - rest_a[i];
		const Vector2 m = now_b[i] - now_a[i];
		span[i] = s;
		moved[i] = m;
		len2[i] = (double)s.length_squared();
		// Twice the bone's own length and a little, so a short bone still
		// holds the flesh immediately around it.
		const double reach = std::sqrt(std::max(len2[i], 1.0)) * 0.42 + 8.0;
		reach2[i] = reach * reach;
		double turn = 0.0;
		if (len2[i] > 0.000001 && (double)m.length_squared() > 0.000001) {
			turn = std::atan2((double)m.y, (double)m.x) -
					std::atan2((double)s.y, (double)s.x);
		}
		tcos[i] = std::cos(turn);
		tsin[i] = std::sin(turn);
		mine[i] = i < bone_island.size() ? bone_island[i] : 0;
	}

	for (int p = 0; p < points; p++) {
		const Vector2 at = rest_points[p];
		const int32_t on_island = by_island ? point_island[p] : 0;
		double arx = 0.0, ary = 0.0, anx = 0.0, any = 0.0;
		double facex = 0.0, facey = 0.0;
		double total = 0.0;
		int closest = -1;
		double closest_d = 1.0e30;
		double closest_t = 0.0;

		for (int i = 0; i < bones; i++) {
			// A bone belonging to another drawing has nothing to say about
			// this point, however near it happens to be.
			if (mine[i] != 0 && on_island != 0 && mine[i] != on_island) {
				continue;
			}
			double t = 0.0;
			if (len2[i] > 0.000001) {
				const double dx = (double)at.x - rest_a[i].x;
				const double dy = (double)at.y - rest_a[i].y;
				t = (dx * span[i].x + dy * span[i].y) / len2[i];
				t = std::min(std::max(t, 0.0), 1.0);
			}
			const double nrx = rest_a[i].x + span[i].x * t;
			const double nry = rest_a[i].y + span[i].y * t;
			const double ddx = (double)at.x - nrx;
			const double ddy = (double)at.y - nry;
			const double d2 = ddx * ddx + ddy * ddy;
			if (d2 < closest_d) {
				closest_d = d2;
				closest = i;
				closest_t = t;
			}
			if (d2 >= reach2[i]) {
				continue;
			}
			// Smooth to zero at the edge of the reach, and finite on the bone
			// itself — a kernel that runs to infinity where the flesh meets
			// the bone hands neighbouring pixels wildly different weights and
			// shears them apart.
			const double fall = 1.0 - d2 / reach2[i];
			const double w = fall * fall / (d2 + 1.0);
			arx += nrx * w;
			ary += nry * w;
			anx += (now_a[i].x + moved[i].x * t) * w;
			any += (now_a[i].y + moved[i].y * t) * w;
			facex += tcos[i] * w;
			facey += tsin[i] * w;
			total += w;
		}

		if (total <= 0.0) {
			if (closest < 0) {
				// On a drawing no bone belongs to. Flesh with no skeleton of
				// its own must not be moved by somebody else's.
				continue;
			}
			// Carried rigidly by the nearest bone, so no part of a drawing is
			// ever left behind by its own skeleton.
			const double lrx = rest_a[closest].x + span[closest].x * closest_t;
			const double lry = rest_a[closest].y + span[closest].y * closest_t;
			const double lnx = now_a[closest].x + moved[closest].x * closest_t;
			const double lny = now_a[closest].y + moved[closest].y * closest_t;
			const double ox = (double)at.x - lrx;
			const double oy = (double)at.y - lry;
			out[p] = Vector2(
					(real_t)(lnx + ox * tcos[closest] - oy * tsin[closest]),
					(real_t)(lny + ox * tsin[closest] + oy * tcos[closest]));
			continue;
		}

		arx /= total;
		ary /= total;
		anx /= total;
		any /= total;
		// Two bones turned exactly opposite ways in equal measure sum to
		// nothing, and the angle of nothing is meaningless. The nearest bone
		// decides it, which is the only answer with any claim to being right.
		double cs = closest >= 0 ? tcos[closest] : 1.0;
		double sn = closest >= 0 ? tsin[closest] : 0.0;
		const double mag = std::sqrt(facex * facex + facey * facey);
		if (mag > 0.001) {
			cs = facex / mag;
			sn = facey / mag;
		}
		const double ox = (double)at.x - arx;
		const double oy = (double)at.y - ary;
		// One rotation, applied once, to one offset. This is the line that
		// makes the flesh keep its distance from the joint: a rotation cannot
		// change a length.
		out[p] = Vector2((real_t)(anx + ox * cs - oy * sn),
				(real_t)(any + ox * sn + oy * cs));
	}
	return out;
}

// ----------------------------------------------------------- volume repair

// Signed area of a triangle, twice over (the shoelace term). Consistently
// signed so a flipped triangle contributes a negative area rather than
// silently cancelling with a correctly-wound one when summed at a vertex.
static inline double tri_area2(const Vector2 &a, const Vector2 &b,
		const Vector2 &c) {
	return (double)(b.x - a.x) * (double)(c.y - a.y) -
			(double)(b.y - a.y) * (double)(c.x - a.x);
}

PackedVector2Array IvorySkin::preserve_volume(
		const PackedVector2Array &now_points,
		const PackedVector2Array &rest_points,
		const PackedInt32Array &triangles, const PackedInt32Array &point_island,
		double strength, int iterations) {
	const int n = now_points.size();
	PackedVector2Array out = now_points;
	if (n == 0 || n != rest_points.size() || triangles.size() < 3 ||
			strength <= 0.0 || iterations <= 0) {
		return out;
	}
	const int tri_count = triangles.size() / 3;
	const bool by_island = point_island.size() == n;
	strength = std::min(std::max(strength, 0.0), 1.0);

	// Each vertex's share of the triangles that touch it, gathered once. A
	// regular 32-cell grid has at most six such triangles per interior
	// vertex, so this is small even at the point count a full-detail skin
	// uses.
	std::vector<std::vector<int32_t>> touching(n);
	for (int t = 0; t < tri_count; t++) {
		const int32_t ia = triangles[t * 3 + 0];
		const int32_t ib = triangles[t * 3 + 1];
		const int32_t ic = triangles[t * 3 + 2];
		if (ia < 0 || ib < 0 || ic < 0 || ia >= n || ib >= n || ic >= n) {
			continue;
		}
		touching[ia].push_back(t);
		touching[ib].push_back(t);
		touching[ic].push_back(t);
	}

	// Direct mesh neighbours of each vertex, deduplicated, restricted to the
	// same island as the vertex itself — a point never gets pulled toward a
	// neighbour that belongs to a different drawing, for the same reason a
	// bone on one drawing never moves flesh on another.
	std::vector<std::vector<int32_t>> neighbours(n);
	for (int t = 0; t < tri_count; t++) {
		const int32_t tri[3] = { triangles[t * 3 + 0], triangles[t * 3 + 1],
			triangles[t * 3 + 2] };
		for (int e = 0; e < 3; e++) {
			const int32_t a = tri[e];
			const int32_t b = tri[(e + 1) % 3];
			if (a < 0 || b < 0 || a >= n || b >= n || a == b) {
				continue;
			}
			if (by_island && point_island[a] != 0 && point_island[b] != 0 &&
					point_island[a] != point_island[b]) {
				continue;
			}
			neighbours[a].push_back(b);
		}
	}
	for (int i = 0; i < n; i++) {
		std::sort(neighbours[i].begin(), neighbours[i].end());
		neighbours[i].erase(
				std::unique(neighbours[i].begin(), neighbours[i].end()),
				neighbours[i].end());
	}

	// Rest area at each vertex — a third of every incident triangle's rest
	// area, the standard "mixed Voronoi" stand-in that a uniform grid makes
	// exact enough to skip anything fancier. Fixed once; only the "now" side
	// is asked again as the correction runs.
	std::vector<double> rest_area(n, 0.0);
	for (int i = 0; i < n; i++) {
		double sum = 0.0;
		for (int32_t t : touching[i]) {
			const int32_t ia = triangles[t * 3 + 0];
			const int32_t ib = triangles[t * 3 + 1];
			const int32_t ic = triangles[t * 3 + 2];
			sum += std::abs(tri_area2(rest_points[ia], rest_points[ib],
					rest_points[ic]));
		}
		rest_area[i] = sum / 3.0;
	}

	// How far each point has already been pushed out of its rest area by
	// `deform`. Measured once, from the input, not recomputed every pass —
	// the correction is chasing where the bones actually put the skin, not
	// chasing itself as it moves.
	std::vector<double> target_scale(n, 1.0);
	for (int i = 0; i < n; i++) {
		if (rest_area[i] <= 1e-6 || touching[i].empty()) {
			continue;
		}
		double sum = 0.0;
		for (int32_t t : touching[i]) {
			const int32_t ia = triangles[t * 3 + 0];
			const int32_t ib = triangles[t * 3 + 1];
			const int32_t ic = triangles[t * 3 + 2];
			sum += std::abs(tri_area2(out[ia], out[ib], out[ic]));
		}
		const double now_area = sum / 3.0;
		double ratio = now_area / rest_area[i];
		// A joint that has thinned reports ratio < 1; a joint that has
		// bulged reports ratio > 1. Either way the fix is the same
		// direction of correction, and it is bounded so a single
		// nearly-degenerate triangle at a sharp fold cannot demand an
		// enormous, visible jump.
		ratio = std::min(std::max(ratio, 0.15), 6.0);
		// sqrt because area scales with the square of a linear expansion —
		// this is a linear (edge-length) scale factor, applied to an edge
		// below, not an area factor applied to one.
		const double linear = 1.0 / std::sqrt(ratio);
		target_scale[i] = 1.0 + (linear - 1.0) * strength;
	}

	// Differential-coordinate correction: pull each point toward or away
	// from the current centroid of its own mesh neighbours by its target
	// scale, run as a few Jacobi passes (read the old positions, write a
	// fresh array, then swap) so a correction at one point has a chance to
	// spread to the next before the next pass reads it. This is deliberately
	// not a solve to convergence — a drag re-poses every frame, and a
	// handful of passes is enough to visibly close a thinned joint without
	// paying for a linear system every frame the way the puppet warp's ARAP
	// solve does (see `ivory_arap.h`; that one runs on a drag, not a frame of
	// playback).
	std::vector<Vector2> cur(n);
	for (int i = 0; i < n; i++) {
		cur[i] = out[i];
	}
	std::vector<Vector2> next(n);
	for (int pass = 0; pass < iterations; pass++) {
		for (int i = 0; i < n; i++) {
			if (neighbours[i].empty() || target_scale[i] == 1.0) {
				next[i] = cur[i];
				continue;
			}
			double cx = 0.0, cy = 0.0;
			for (int32_t j : neighbours[i]) {
				cx += cur[j].x;
				cy += cur[j].y;
			}
			const double count = (double)neighbours[i].size();
			cx /= count;
			cy /= count;
			const double ox = (double)cur[i].x - cx;
			const double oy = (double)cur[i].y - cy;
			next[i] = Vector2((real_t)(cx + ox * target_scale[i]),
					(real_t)(cy + oy * target_scale[i]));
		}
		cur.swap(next);
	}

	for (int i = 0; i < n; i++) {
		out[i] = cur[i];
	}
	return out;
}
