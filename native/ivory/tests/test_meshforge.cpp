// Does the mesh sit on the drawing?
//
// The old grid mesh had two faults that could only be seen by warping
// something and watching it come apart. Both are measurable, so they are
// measured here instead.
#include "../src/ivory_meshforge.h"
#include <algorithm>
#include <cmath>
#include <cstdio>

using namespace godot;

static int checks = 0, failures = 0;
static void ok(bool v, const char *m) {
	++checks;
	if (!v) { ++failures; std::printf("FAIL: %s\n", m); }
}
static void heading(const char *m) { std::printf("%s\n", m); }

struct Canvas {
	int w, h;
	PackedByteArray b;
	Canvas(int width, int height) : w(width), h(height) {
		b.resize(w * h * 4);
		b.fill(0);
	}
	void dot(int x, int y) {
		if (x < 0 || y < 0 || x >= w || y >= h) return;
		b[(y * w + x) * 4 + 3] = 255;
	}
	void box(int x0, int y0, int x1, int y1) {
		for (int y = std::max(0, y0); y <= std::min(h - 1, y1); ++y)
			for (int x = std::max(0, x0); x <= std::min(w - 1, x1); ++x) dot(x, y);
	}
	void disc(double cx, double cy, double r) {
		for (int y = 0; y < h; ++y)
			for (int x = 0; x < w; ++x) {
				const double dx = x - cx, dy = y - cy;
				if (dx * dx + dy * dy <= r * r) dot(x, y);
			}
	}
	// A one-pixel diagonal — the eyelash case, the thing the old ink map
	// dropped because a single opaque pixel averaged over a cell of a hundred
	// is an alpha below any floor.
	void hairline(int x0, int y0, int x1, int y1) {
		const int steps = std::max(std::abs(x1 - x0), std::abs(y1 - y0));
		for (int s = 0; s <= steps; ++s) {
			const double t = steps == 0 ? 0.0 : (double)s / steps;
			dot((int)std::lround(x0 + (x1 - x0) * t), (int)std::lround(y0 + (y1 - y0) * t));
		}
	}
};

static void test_refuses_rubbish() {
	heading("nothing to mesh is answered honestly, not with an empty mesh");
	IvoryMeshForge f;
	ok(!bool(f.build(PackedByteArray(), 0, 0, 8.0, 0.02)["ok"]), "an empty buffer produced a mesh");
	PackedByteArray truncated;
	truncated.resize(400);
	ok(!bool(f.build(truncated, 64, 64, 8.0, 0.02)["ok"]), "a short buffer produced a mesh");
	Canvas blank(64, 64);
	Dictionary d = f.build(blank.b, 64, 64, 8.0, 0.02);
	ok(!bool(d["ok"]), "a blank canvas produced a mesh");
	ok((int)d["ink_cells"] == 0, "a blank canvas reported ink in it");
}

static void test_every_pixel_of_ink_is_in_the_mesh() {
	heading("every drawn pixel is inside some triangle — including a hairline");
	// This is the fault, stated as a test. A stroke that is not in the mesh is
	// not drawn, so the drawing tears exactly where its finest detail was.
	Canvas c(200, 200);
	c.disc(70, 70, 34);                    // a solid blob
	c.box(120, 40, 128, 160);              // a bar
	c.hairline(20, 190, 190, 20);          // one pixel wide, corner to corner
	c.hairline(10, 10, 190, 14);           // and a near-horizontal one
	c.dot(5, 195);                         // a single isolated pixel

	IvoryMeshForge f;
	Dictionary d = f.build(c.b, c.w, c.h, 8.0, 0.02);
	ok(bool(d["ok"]), "a drawing with detail in it failed to mesh");
	ok((int)d["triangle_count"] > 0, "the mesh has no triangles");

	Dictionary cover = f.covers_all_ink(c.b, c.w, c.h, 0.02);
	ok((int)cover["ink_pixels"] > 500, "the test drawing has almost no ink in it");
	if (!bool(cover["ok"])) {
		const Vector2 miss = cover["first_uncovered"];
		std::printf("    %d of %d ink pixels are outside the mesh, first at %.0f,%.0f\n",
				(int)cover["uncovered"], (int)cover["ink_pixels"], (double)miss.x, (double)miss.y);
	}
	ok(bool(cover["ok"]), "part of the drawing is not covered by the mesh");
}

static void test_a_single_pixel_still_gets_a_mesh() {
	heading("one opaque pixel in an empty canvas still gets material round it");
	Canvas c(120, 120);
	c.dot(61, 47);
	IvoryMeshForge f;
	Dictionary d = f.build(c.b, c.w, c.h, 8.0, 0.02);
	ok(bool(d["ok"]), "a single pixel produced no mesh at all");
	ok((int)d["triangle_count"] >= 2, "a single pixel got fewer than one cell of mesh");
	ok(bool(f.covers_all_ink(c.b, c.w, c.h, 0.02)["ok"]), "the single pixel is not inside the mesh");
	// And the skirt is there: the pixel is not sitting on the mesh's own edge,
	// where it would shear off the first time the mesh moved.
	ok((int)d["triangle_count"] >= 8, "the single pixel got no skirt of material round it");
}

static void test_the_mesh_follows_the_drawing_not_the_canvas() {
	heading("a small drawing in a large canvas gets a small mesh");
	// The old mesh covered the bounding box. A stick figure in a page-sized
	// canvas paid for a page-sized mesh and every drag solved over it.
	Canvas small(400, 400);
	small.disc(200, 200, 25);
	IvoryMeshForge f;
	Dictionary d = f.build(small.b, small.w, small.h, 8.0, 0.02);
	const int used = (int)d["triangle_count"];

	Canvas full(400, 400);
	full.box(0, 0, 399, 399);
	IvoryMeshForge g;
	Dictionary all = g.build(full.b, full.w, full.h, 8.0, 0.02);
	const int whole = (int)all["triangle_count"];

	ok(used > 0 && whole > 0, "one of the two meshes did not build");
	ok(used * 8 < whole, "a drawing covering 1/80th of the canvas got a mesh nearly as large");
}

static void test_the_boundary_is_snapped_to_the_outline() {
	heading("the rim follows the outline instead of stepping round it");
	// What "follows the outline" means, in numbers.
	//
	// The mesh deliberately keeps a skirt: the rim sits about half a cell
	// outside the drawing, so the outermost stroke has material beyond it to
	// pull against. So the rim is not *on* the outline and should not be. What
	// matters is that its distance from the outline is roughly the same all
	// the way round — a rim that is uniformly half a cell out is following the
	// shape, and a rim whose distance swings between nothing and three cells
	// is a staircase drawn round it.
	//
	// A plain grid, unsnapped, is out by anywhere from zero to a cell and a
	// half depending only on where the grid lines happened to fall. Spread is
	// therefore the honest measurement, and the one asserted here.
	const double R = 60.0;
	const double cell = 10.0;
	Canvas c(200, 200);
	c.disc(100, 100, R);
	IvoryMeshForge f;
	Dictionary d = f.build(c.b, c.w, c.h, cell, 0.02);
	ok(bool(d["ok"]), "a disc failed to mesh");
	ok((int)d["snapped"] > 0, "no vertex was snapped toward the outline at all");

	PackedVector2Array v = f.vertices();
	PackedByteArray rim = f.boundary();
	double lo = 1e30, hi = 0.0, total = 0.0;
	int rim_count = 0;
	for (int i = 0; i < v.size(); ++i) {
		if (!rim[i]) continue;
		++rim_count;
		const double dist = std::hypot((double)v[i].x - 100.0, (double)v[i].y - 100.0);
		lo = std::min(lo, dist);
		hi = std::max(hi, dist);
		total += dist;
	}
	ok(rim_count > 20, "the disc's mesh has almost no rim");
	const double spread = hi - lo;
	const double mean_gap = total / std::max(1, rim_count) - R;
	std::printf("    rim sits %.1f px outside the outline on average, spread %.1f px\n",
			mean_gap, spread);

	// Uniform to within a cell and a half. An unsnapped grid on this shape
	// spreads by more than two cells, and did.
	ok(spread < cell * 1.5, "the rim's distance from the outline varies like a staircase");
	// Outside the drawing, but not by much: enough to give the outermost
	// stroke something to hold on to, not so much that the mesh is padding.
	ok(mean_gap > 0.0, "the rim has cut inside the drawing");
	ok(mean_gap < cell * 1.2, "the rim is padding the drawing rather than hugging it");
	// And nowhere is it wildly out.
	ok(hi - R < cell * 2.0, "some part of the rim is more than two cells from the outline");
}

static void test_no_triangle_is_inverted() {
	heading("snapping never turns a triangle inside out");
	// Snapping moves vertices one at a time, so two of them can cross. An
	// inverted triangle renders as a fold: the drawing appears to double back
	// on itself, which looks like corruption rather than a warp.
	Canvas c(240, 240);
	// A shape with a narrow waist and sharp corners, which is where crossing
	// is most likely.
	c.box(40, 40, 200, 90);
	c.box(110, 90, 130, 150);
	c.box(40, 150, 200, 200);
	c.hairline(45, 45, 195, 195);

	IvoryMeshForge f;
	Dictionary d = f.build(c.b, c.w, c.h, 8.0, 0.02);
	ok(bool(d["ok"]), "the waisted shape failed to mesh");

	PackedVector2Array v = f.vertices();
	PackedInt32Array t = f.triangles();
	int inverted = 0, degenerate = 0;
	double first_sign = 0.0;
	for (int i = 0; i + 2 < t.size(); i += 3) {
		const Vector2 a = v[t[i]], b = v[t[i + 1]], cc = v[t[i + 2]];
		const double area = (double)(b.x - a.x) * (cc.y - a.y) - (double)(b.y - a.y) * (cc.x - a.x);
		if (std::abs(area) < 1e-6) { ++degenerate; continue; }
		if (first_sign == 0.0) first_sign = area;
		if (area * first_sign < 0.0) ++inverted;
	}
	if (inverted > 0) std::printf("    %d triangles are wound the wrong way\n", inverted);
	ok(inverted == 0, "snapping turned a triangle inside out");
	ok(degenerate == 0, "snapping collapsed a triangle to a line");
	ok((double)d["min_angle_deg"] > 5.0, "the mesh has a hinge-thin triangle in it");
}

static void test_a_pin_stays_bound_to_its_material() {
	heading("a pin holds the same piece of drawing wherever the mesh goes");
	// The old code kept a pin as a position and found the nearest vertex each
	// time. As the mesh moved, the nearest vertex changed, so the pin quietly
	// started holding a different piece of the drawing — which is why pins
	// came loose once there were several of them.
	Canvas c(160, 160);
	c.disc(80, 80, 50);
	IvoryMeshForge f;
	f.build(c.b, c.w, c.h, 8.0, 0.02);

	const Vector2 at(80, 80);
	Dictionary b = f.bind_point(at);
	ok(bool(b["ok"]), "a point in the middle of the drawing could not be bound");
	ok(bool(b["exact"]), "a point inside the mesh was reported as outside it");
	const double sum = (double)b["a"] + (double)b["b"] + (double)b["c"];
	ok(std::abs(sum - 1.0) < 1e-6, "the barycentric weights do not add to one");

	// Unmoved, the binding names the point it was made at.
	PackedVector2Array same = f.vertices();
	const Vector2 back = f.follow(b, same);
	ok(std::abs((double)back.x - 80.0) < 1.0 && std::abs((double)back.y - 80.0) < 1.0,
			"a binding on an unmoved mesh does not name the point it was made at");

	// Move the whole mesh a long way. The binding must travel with it exactly.
	PackedVector2Array moved;
	for (int i = 0; i < same.size(); ++i) moved.append(same[i] + Vector2(300, -120));
	const Vector2 carried = f.follow(b, moved);
	ok(std::abs((double)carried.x - ((double)back.x + 300.0)) < 1e-3,
			"the pin did not travel with the mesh");
	ok(std::abs((double)carried.y - ((double)back.y - 120.0)) < 1e-3,
			"the pin did not travel with the mesh");

	// A point outside the mesh binds to the nearest triangle rather than
	// failing, because a finger on an outline lands there constantly.
	Dictionary outside = f.bind_point(Vector2(400, 400));
	ok(bool(outside["ok"]), "a point off the mesh could not be bound at all");
	ok(!bool(outside["exact"]), "a point off the mesh was reported as inside it");
}

int main() {
	std::printf("--- IvoryMeshForge ---\n");
	test_refuses_rubbish();
	test_every_pixel_of_ink_is_in_the_mesh();
	test_a_single_pixel_still_gets_a_mesh();
	test_the_mesh_follows_the_drawing_not_the_canvas();
	test_the_boundary_is_snapped_to_the_outline();
	test_no_triangle_is_inverted();
	test_a_pin_stays_bound_to_its_material();
	std::printf("%d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
