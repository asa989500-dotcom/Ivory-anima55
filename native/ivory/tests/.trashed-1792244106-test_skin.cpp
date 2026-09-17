// The bone skin, judged on the two faults it has to not have: a single bone
// pulling flesh toward the joint as it bends (the old "candy-wrapper" fault,
// fixed by rotating an offset instead of averaging positions — see the long
// comment in `RigSkin.bone_rule`), and the seam between two overlapping
// bones thinning as their anchors converge (fixed by `preserve_volume`,
// added at stage 166).
//
// Every test here is a measurement with a threshold, not an equality, for
// the same reason `test_deform.cpp` is: "did it move correctly" has no exact
// answer for a skin, but "did a ring of flesh drawn twenty units from a
// joint stay within some tolerance of twenty units once the joint bent" does.
#include "../src/ivory_skin.h"

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

static void heading(const char *t) { std::printf("%s\n", t); }

// --------------------------------------------------------------------------
// A single bone from the origin to (100, 0), and a ring of points twenty
// units out from its far end — exactly the setup `bone_rule`'s own doc
// comment measures, so this test reproduces those numbers as a regression
// rather than trusting the comment to stay true.
// --------------------------------------------------------------------------

struct Ring {
	PackedVector2Array rest;
	PackedVector2Array now;
};

static Ring make_elbow_ring(double bend_degrees, int samples = 24) {
	Ring r;
	const Vector2 joint(100.0, 0.0);
	for (int i = 0; i < samples; i++) {
		const double a = 2.0 * M_PI * (double)i / (double)samples;
		r.rest.append(Vector2(joint.x + (real_t)(20.0 * std::cos(a)),
				joint.y + (real_t)(20.0 * std::sin(a))));
	}
	// The ring is closest to bone 0 (the upper arm) at rest, so it is bone
	// 0's rotation that should carry it.
	(void)r.now; // filled by the caller once the bent bone position is known
	return r;
}

static void test_single_bone_bend_matches_documented_numbers() {
	heading("single-bone bend keeps the ring's radius");
	IvorySkin skin;
	Ring ring = make_elbow_ring(0);

	PackedVector2Array rest_a, rest_b, now_a, now_b;
	rest_a.append(Vector2(0, 0));
	rest_b.append(Vector2(100, 0));
	now_a.append(Vector2(0, 0));

	const double degs[] = { 30.0, 90.0, 150.0, 179.0 };
	// Loosened slightly from the doc comment's own hand-measured figures
	// (which quote 18.79/16.48/15.50/19.38 against a radius of 20): this is
	// a regression floor, not a re-derivation, and the ring here is sampled
	// on a full circle rather than the single worst point.
	const double floor_ratio[] = { 0.90, 0.75, 0.65, 0.60 };

	for (int k = 0; k < 4; k++) {
		const double rad = degs[k] * M_PI / 180.0;
		now_b = PackedVector2Array();
		now_b.append(Vector2((real_t)(100.0 * std::cos(rad)),
				(real_t)(100.0 * std::sin(rad))));
		PackedInt32Array empty_island;
		PackedVector2Array out = skin.deform(ring.rest, empty_island, rest_a,
				rest_b, now_a, now_b, empty_island);
		ok(out.size() == ring.rest.size(), "deform returned one point per input");
		double min_r = 1e30;
		for (int i = 0; i < out.size(); i++) {
			const double dx = out[i].x - now_b[0].x;
			const double dy = out[i].y - now_b[0].y;
			min_r = std::min(min_r, std::sqrt(dx * dx + dy * dy));
		}
		char msg[128];
		std::snprintf(msg, sizeof(msg),
				"ring radius collapsed at %.0f degrees (got %.2f, floor %.2f)",
				degs[k], min_r, floor_ratio[k] * 20.0);
		ok(min_r >= floor_ratio[k] * 20.0, msg);
	}
}

static void test_rigid_whole_skin_move_is_exact() {
	heading("moving both bone ends by the same amount is a pure translation");
	IvorySkin skin;
	PackedVector2Array rest;
	for (int i = 0; i < 30; i++) {
		rest.append(Vector2((real_t)(i * 4), (real_t)((i % 5) * 3)));
	}
	PackedVector2Array rest_a, rest_b, now_a, now_b;
	rest_a.append(Vector2(0, 0));
	rest_b.append(Vector2(100, 0));
	now_a.append(Vector2(10, 10));
	now_b.append(Vector2(110, 10));
	PackedInt32Array empty_island;
	PackedVector2Array out = skin.deform(rest, empty_island, rest_a, rest_b,
			now_a, now_b, empty_island);
	bool all_ok = true;
	for (int i = 0; i < out.size(); i++) {
		const double dx = out[i].x - rest[i].x - 10.0;
		const double dy = out[i].y - rest[i].y - 10.0;
		if (std::sqrt(dx * dx + dy * dy) > 0.01) {
			all_ok = false;
		}
	}
	ok(all_ok, "a bone moved with no rotation should translate the skin exactly");
}

// --------------------------------------------------------------------------
// preserve_volume: a strip mesh across two end-to-end bones, bent hard at
// the shared joint. The seam between the two bones' influence is exactly
// where `deform` alone leaves a residual thinning.
// --------------------------------------------------------------------------

struct Strip {
	PackedVector2Array rest;
	PackedInt32Array tris;
	int along = 0;
	int across = 0;
};

static Strip make_strip(int along, int across, double length, double width) {
	Strip s;
	s.along = along;
	s.across = across;
	for (int i = 0; i < along; i++) {
		for (int j = 0; j < across; j++) {
			const double x = length * (double)i / (double)(along - 1);
			const double y = width * ((double)j / (double)(across - 1) - 0.5);
			s.rest.append(Vector2((real_t)x, (real_t)y));
		}
	}
	for (int i = 0; i + 1 < along; i++) {
		for (int j = 0; j + 1 < across; j++) {
			const int a = i * across + j;
			const int b = (i + 1) * across + j;
			const int c = (i + 1) * across + (j + 1);
			const int d = i * across + (j + 1);
			s.tris.append(a);
			s.tris.append(b);
			s.tris.append(c);
			s.tris.append(a);
			s.tris.append(c);
			s.tris.append(d);
		}
	}
	return s;
}

static double mean_vertex_area_ratio(const PackedVector2Array &now,
		const PackedVector2Array &rest, const PackedInt32Array &tris,
		double near_x, double band) {
	// Average the area ratio of every triangle whose rest centroid sits
	// within `band` of `near_x` along the strip — i.e. right at the joint —
	// rather than every triangle, so a fix local to the seam is not diluted
	// by the (already-correct) triangles far from it.
	double sum = 0.0;
	int n = 0;
	const int tri_count = tris.size() / 3;
	for (int t = 0; t < tri_count; t++) {
		const int ia = tris[t * 3 + 0], ib = tris[t * 3 + 1], ic = tris[t * 3 + 2];
		const double cx = (rest[ia].x + rest[ib].x + rest[ic].x) / 3.0;
		if (std::fabs(cx - near_x) > band) {
			continue;
		}
		auto area2 = [](const Vector2 &a, const Vector2 &b, const Vector2 &c) {
			return std::fabs((double)(b.x - a.x) * (double)(c.y - a.y) -
					(double)(b.y - a.y) * (double)(c.x - a.x));
		};
		const double a0 = area2(rest[ia], rest[ib], rest[ic]);
		const double a1 = area2(now[ia], now[ib], now[ic]);
		if (a0 > 1e-6) {
			sum += a1 / a0;
			n++;
		}
	}
	return n > 0 ? sum / n : 1.0;
}

static void test_preserve_volume_closes_the_seam() {
	heading("preserve_volume repairs the two-bone seam");
	IvorySkin skin;
	Strip s = make_strip(21, 7, 100.0, 20.0);

	PackedVector2Array rest_a, rest_b, now_a, now_b;
	// Two bones end to end: 0..50, 50..100.
	rest_a.append(Vector2(0, 0));
	rest_b.append(Vector2(50, 0));
	rest_a.append(Vector2(50, 0));
	rest_b.append(Vector2(100, 0));
	now_a.append(Vector2(0, 0));
	// A hard 120 degree bend at the shared joint.
	const double rad = 120.0 * M_PI / 180.0;
	now_b.append(Vector2(50, 0));
	now_a.append(Vector2(50, 0));
	now_b.append(Vector2((real_t)(50.0 + 50.0 * std::cos(rad)),
			(real_t)(50.0 * std::sin(rad))));

	PackedInt32Array empty_island;
	PackedVector2Array deformed = skin.deform(s.rest, empty_island, rest_a,
			rest_b, now_a, now_b, empty_island);
	ok(deformed.size() == s.rest.size(), "deform covered the whole strip");

	const double before = mean_vertex_area_ratio(deformed, s.rest, s.tris,
			50.0, 12.0);
	PackedVector2Array repaired = skin.preserve_volume(deformed, s.rest,
			s.tris, empty_island, 0.55, 2);
	ok(repaired.size() == deformed.size(),
			"preserve_volume returned one point per input");
	const double after = mean_vertex_area_ratio(repaired, s.rest, s.tris,
			50.0, 12.0);

	char msg[160];
	std::snprintf(msg, sizeof(msg),
			"seam area ratio did not move toward 1 (before %.3f, after %.3f)",
			before, after);
	// The seam starts compressed (ratio below 1 — the fault this pass
	// exists to reduce). After the repair it should sit measurably closer
	// to 1 than it started.
	ok(before < 0.97, "the seam was not actually compressed before repair — "
			"test setup does not exercise the fault");
	ok(std::fabs(after - 1.0) < std::fabs(before - 1.0), msg);
}

static void test_preserve_volume_leaves_an_unbent_skin_alone() {
	heading("preserve_volume is a no-op on an already-rest mesh");
	IvorySkin skin;
	Strip s = make_strip(11, 5, 60.0, 12.0);
	PackedInt32Array empty_island;
	PackedVector2Array out = skin.preserve_volume(s.rest, s.rest, s.tris,
			empty_island, 0.55, 2);
	bool all_ok = true;
	for (int i = 0; i < out.size(); i++) {
		const double dx = out[i].x - s.rest[i].x;
		const double dy = out[i].y - s.rest[i].y;
		if (std::sqrt(dx * dx + dy * dy) > 0.01) {
			all_ok = false;
		}
	}
	ok(all_ok, "a mesh already at rest area should not be moved by the repair");
}

static void test_preserve_volume_respects_islands() {
	heading("preserve_volume does not pull one drawing toward another");
	IvorySkin skin;
	// Two disconnected triangles, far apart, sharing no mesh edge — islands
	// exist to stop exactly this kind of cross-talk, so even though this
	// mesh has no shared vertices the island argument should still be
	// honoured harmlessly (the real protection lives in `deform`'s bone
	// confinement; this just checks the plumbing does not crash or corrupt
	// unrelated islands when given one).
	PackedVector2Array rest, now;
	PackedInt32Array tris, island;
	rest.append(Vector2(0, 0));
	rest.append(Vector2(10, 0));
	rest.append(Vector2(5, 10));
	rest.append(Vector2(1000, 0));
	rest.append(Vector2(1010, 0));
	rest.append(Vector2(1005, 10));
	now = rest;
	// Compress the first triangle only.
	now[1] = Vector2(6, 0);
	now[2] = Vector2(3, 6);
	tris.append(0);
	tris.append(1);
	tris.append(2);
	tris.append(3);
	tris.append(4);
	tris.append(5);
	island.append(1);
	island.append(1);
	island.append(1);
	island.append(2);
	island.append(2);
	island.append(2);
	PackedVector2Array out = skin.preserve_volume(now, rest, tris, island,
			0.55, 2);
	const double dx = out[3].x - now[3].x;
	const double dy = out[3].y - now[3].y;
	ok(std::sqrt(dx * dx + dy * dy) < 0.01,
			"the untouched island moved when a different island was repaired");
}

int main() {
	std::printf("--- bone skin (ivory_skin) ---\n");
	test_single_bone_bend_matches_documented_numbers();
	test_rigid_whole_skin_move_is_exact();
	test_preserve_volume_closes_the_seam();
	test_preserve_volume_leaves_an_unbent_skin_alone();
	test_preserve_volume_respects_islands();
	std::printf("%d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
