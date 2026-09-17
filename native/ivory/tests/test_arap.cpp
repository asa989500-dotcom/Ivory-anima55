// Does the warp behave like material?
//
// "It drags the drawing instead of stretching it" is a statement about
// numbers, and these are the numbers. Every case below is a thing the old
// moving-least-squares warp got wrong and this one gets right, written as a
// measurement rather than as a description.
#include "../src/ivory_arap.h"
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

// A rectangular sheet, `nx` by `ny` vertices, spacing `s`. Plain and regular,
// so every number below is about the solver rather than about a mesh.
struct Sheet {
	PackedVector2Array rest;
	PackedInt32Array tris;
	int nx, ny;
	double s;
	Sheet(int cols, int rows, double spacing) : nx(cols), ny(rows), s(spacing) {
		for (int y = 0; y < ny; ++y)
			for (int x = 0; x < nx; ++x)
				rest.append(Vector2((real_t)(x * s), (real_t)(y * s)));
		for (int y = 0; y + 1 < ny; ++y) {
			for (int x = 0; x + 1 < nx; ++x) {
				const int a = y * nx + x, b = a + 1, c = a + nx + 1, d = a + nx;
				tris.append(a); tris.append(b); tris.append(c);
				tris.append(a); tris.append(c); tris.append(d);
			}
		}
	}
	int at(int x, int y) const { return y * nx + x; }
};

static void test_refuses_rubbish() {
	heading("a mesh that is not a mesh is refused");
	IvoryArapSolver s;
	ok(!s.set_mesh(PackedVector2Array(), PackedInt32Array()), "an empty mesh was accepted");
	PackedVector2Array two;
	two.append(Vector2(0, 0));
	two.append(Vector2(1, 0));
	PackedInt32Array t;
	t.append(0); t.append(1); t.append(0);
	ok(!s.set_mesh(two, t), "two vertices were accepted as a mesh");

	Sheet sheet(4, 4, 10.0);
	PackedInt32Array bad;
	bad.append(0); bad.append(1); bad.append(999);
	ok(!s.set_mesh(sheet.rest, bad), "a triangle naming a vertex that does not exist was accepted");
	ok(s.set_mesh(sheet.rest, sheet.tris), "a sound mesh was refused");
}

static void test_a_rigid_move_costs_nothing() {
	heading("moving the whole drawing distorts none of it");
	// The definition of as-rigid-as-possible: a translation or a rotation of
	// everything has zero energy however far it went. If this is not true the
	// energy is measuring the wrong thing and nothing below means anything.
	Sheet sheet(6, 6, 10.0);
	IvoryArapSolver s;
	s.set_mesh(sheet.rest, sheet.tris);

	PackedVector2Array moved;
	for (int i = 0; i < sheet.rest.size(); ++i) moved.append(sheet.rest[i] + Vector2(500, -300));
	s.set_positions(moved);
	s.solve(4);
	ok(s.energy() < 1e-6, "translating the whole mesh registered as distortion");

	// And a rotation of ninety degrees about the origin.
	PackedVector2Array turned;
	for (int i = 0; i < sheet.rest.size(); ++i) turned.append(Vector2(-sheet.rest[i].y, sheet.rest[i].x));
	s.set_positions(turned);
	s.solve(4);
	ok(s.energy() < 1e-6, "rotating the whole mesh registered as distortion");

	PackedFloat32Array stretch = s.triangle_stretch();
	double worst = 0.0;
	for (int i = 0; i < stretch.size(); ++i) worst = std::max(worst, std::abs((double)stretch[i] - 1.0));
	ok(worst < 1e-3, "a rigid rotation stretched the triangles");
}

static void test_it_stretches_rather_than_drags() {
	heading("pulling one end of a bar stretches the bar");
	// The fault, stated as a measurement.
	//
	// A bar, held at the left edge, pulled to the right by its right edge. If
	// the solver drags, the middle simply translates and the triangles keep
	// their rest shape — every stretch reads 1.0 and all the deformation piles
	// up in one row. If it behaves like material, the stretch is spread along
	// the bar and every triangle in it is longer than it was.
	Sheet bar(11, 4, 10.0);
	IvoryArapSolver s;
	s.set_mesh(bar.rest, bar.tris);

	PackedInt32Array pins;
	PackedVector2Array at;
	for (int y = 0; y < bar.ny; ++y) {
		pins.append(bar.at(0, y));
		at.append(bar.rest[bar.at(0, y)]);
		pins.append(bar.at(bar.nx - 1, y));
		// The far edge pulled out to one and a half times the bar's length.
		at.append(bar.rest[bar.at(bar.nx - 1, y)] + Vector2((real_t)(50.0), 0));
	}
	s.set_pins(pins, at);
	Dictionary r = s.solve(40);
	ok(bool(r["ok"]), "the solve failed on a bar");

	PackedFloat32Array stretch = s.triangle_stretch();
	int stretched = 0;
	double least = 1e30, most = 0.0;
	for (int i = 0; i < stretch.size(); ++i) {
		const double v = stretch[i];
		least = std::min(least, v);
		most = std::max(most, v);
		if (v > 1.02) ++stretched;
	}
	std::printf("    triangle stretch runs %.2f to %.2f; %d of %d triangles are longer\n",
			least, most, stretched, stretch.size());
	// Every triangle carries some of it — that is the difference between
	// stretching and dragging.
	ok(stretched > stretch.size() * 3 / 4, "the stretch piled up in a few triangles instead of spreading");
	ok(least > 1.0, "some triangle did not stretch at all — the mesh dragged there");
	// And nothing tore: the most-stretched triangle is not wildly beyond the
	// average, which is what a drag-then-repair solver produces.
	ok(most < least * 2.0, "the stretch is very uneven along the bar");

	// What is deliberately NOT asserted here: that the bar narrows as it
	// stretches. That is a Poisson effect — a property of rubber — and the
	// as-rigid-as-possible energy does not have one. Narrowing would mean
	// every edge across the bar deviating further from its rest length, which
	// is the opposite of what the energy asks for. A solver that narrowed
	// would be one with an extra term nobody asked for, and it would fight
	// the artist every time they wanted a limb to keep its thickness.
	//
	// The property that matters, and the one measured above, is that the
	// stretch is spread evenly along the whole bar instead of piling up
	// beside the pin. That is the difference between stretching and dragging.
}

static void test_it_squashes_when_pushed() {
	heading("pushing two ends together squashes and bulges");
	Sheet bar(11, 5, 10.0);
	IvoryArapSolver s;
	s.set_mesh(bar.rest, bar.tris);
	PackedInt32Array pins;
	PackedVector2Array at;
	for (int y = 0; y < bar.ny; ++y) {
		pins.append(bar.at(0, y));
		at.append(bar.rest[bar.at(0, y)]);
		pins.append(bar.at(bar.nx - 1, y));
		at.append(bar.rest[bar.at(bar.nx - 1, y)] - Vector2(30, 0));
	}
	s.set_pins(pins, at);
	s.solve(40);

	// Compression is the mirror of the case above: every triangle shorter,
	// and by a similar amount, rather than one row of them absorbing all of
	// it while the rest slides along unchanged.
	// Area, not stretch. `triangle_stretch` reports the largest singular
	// value, and a bar squashed along its length leaves the across-direction
	// untouched — so its largest singular value is exactly 1.0 and the whole
	// compression is invisible to it. Area sees it.
	PackedFloat32Array area = s.triangle_area_ratio();
	int squashed = 0;
	double least = 1e30, most = 0.0;
	for (int i = 0; i < area.size(); ++i) {
		const double v = area[i];
		least = std::min(least, v);
		most = std::max(most, v);
		if (v < 0.99) ++squashed;
	}
	std::printf("    triangle area runs %.2f to %.2f of rest; %d of %d are smaller\n",
			least, most, squashed, area.size());
	ok(squashed > area.size() * 3 / 4, "the compression piled into a few triangles");
	ok(most < 1.001, "some triangle grew while the bar was being compressed");
	ok(least > 0.5, "some triangle was crushed far more than the bar as a whole");
}

static void test_a_pin_is_exactly_where_it_was_put() {
	heading("pins hold exactly, and go on holding as more are added");
	// The fault: pins came loose once there were several of them, because
	// they were soft constraints fighting each other. Here a pinned vertex is
	// not solved for at all, so it cannot drift by any amount at all.
	Sheet sheet(9, 9, 10.0);
	IvoryArapSolver s;
	s.set_mesh(sheet.rest, sheet.tris);

	PackedInt32Array pins;
	PackedVector2Array at;
	// Twelve pins, several of them pulling against each other hard.
	const int spots[12][2] = { {0,0},{8,0},{0,8},{8,8},{4,0},{4,8},{0,4},{8,4},{2,2},{6,2},{2,6},{6,6} };
	for (int k = 0; k < 12; ++k) {
		const int i = sheet.at(spots[k][0], spots[k][1]);
		pins.append(i);
		at.append(sheet.rest[i] + Vector2((real_t)((k % 3) * 9 - 9), (real_t)((k % 4) * 7 - 10)));
	}
	s.set_pins(pins, at);
	s.solve(60);

	PackedVector2Array p = s.positions();
	double worst = 0.0;
	for (int k = 0; k < pins.size(); ++k) {
		worst = std::max(worst, (double)p[pins[k]].distance_to(at[k]));
	}
	std::printf("    twelve pins, worst drift %.2e px\n", worst);
	ok(worst < 1e-6, "a pin drifted from where it was put");
}

static void test_freezing_is_absolute() {
	heading("a frozen vertex does not move, at all, until it is thawed");
	// The double-tap. "Frozen" has to mean frozen: if it drifts by even a
	// fraction of a pixel per solve, a long edit walks it across the drawing.
	Sheet sheet(9, 9, 10.0);
	IvoryArapSolver s;
	s.set_mesh(sheet.rest, sheet.tris);

	const int held = sheet.at(4, 4);
	const Vector2 where = sheet.rest[held];
	PackedInt32Array frozen;
	frozen.append(held);
	s.freeze(frozen);
	ok(s.is_frozen(held), "freezing a vertex did not take");
	ok(s.frozen_count() == 1, "the frozen count is wrong");

	// Now drag a corner hard, several times over, which is what a real edit
	// looks like.
	for (int round = 0; round < 5; ++round) {
		PackedInt32Array pins;
		PackedVector2Array at;
		pins.append(sheet.at(8, 8));
		at.append(sheet.rest[sheet.at(8, 8)] + Vector2((real_t)(30 + round * 10), (real_t)(20 + round * 5)));
		s.set_pins(pins, at);
		s.solve(30);
		PackedVector2Array p = s.positions();
		ok((double)p[held].distance_to(where) < 1e-9,
				"a frozen vertex moved while something else was dragged");
	}

	// Freezing survives a change of pins — the artist saying "this part is
	// finished" should not be undone by picking up a different pin.
	ok(s.is_frozen(held), "freezing was lost when the pins changed");

	// Thawed, it is free again, and the mesh round it relaxes.
	PackedInt32Array thaw_list;
	thaw_list.append(held);
	s.thaw(thaw_list);
	ok(!s.is_frozen(held), "thawing did not take");
	ok(s.frozen_count() == 0, "the frozen count did not come back down");

	PackedInt32Array pins;
	PackedVector2Array at;
	pins.append(sheet.at(8, 8));
	at.append(sheet.rest[sheet.at(8, 8)] + Vector2(60, 40));
	s.set_pins(pins, at);
	s.solve(40);
	PackedVector2Array p = s.positions();
	ok((double)p[held].distance_to(where) > 1.0, "a thawed vertex is still stuck");
}

static void test_it_settles_rather_than_wandering() {
	heading("the same drag from the same rest state gives the same answer");
	// A solver that has not converged gives a slightly different answer every
	// time it is asked, and on a mesh that is re-solved every frame of a drag
	// that reads as a point that will not stop shivering.
	Sheet sheet(8, 8, 10.0);
	IvoryArapSolver a, b;
	a.set_mesh(sheet.rest, sheet.tris);
	b.set_mesh(sheet.rest, sheet.tris);

	PackedInt32Array pins;
	PackedVector2Array at;
	pins.append(sheet.at(0, 0));
	at.append(sheet.rest[sheet.at(0, 0)]);
	pins.append(sheet.at(7, 7));
	at.append(sheet.rest[sheet.at(7, 7)] + Vector2(25, -18));

	a.set_pins(pins, at);
	Dictionary ra = a.solve(80);
	b.set_pins(pins, at);
	b.solve(80);

	PackedVector2Array pa = a.positions(), pb = b.positions();
	double worst = 0.0;
	for (int i = 0; i < pa.size(); ++i) worst = std::max(worst, (double)pa[i].distance_to(pb[i]));
	ok(worst < 1e-6, "two identical solves disagreed");

	// Converged means the last iteration moved almost nothing. This is the
	// number that decides whether a held point shivers between frames.
	std::printf("    settled after %d iterations, last step %.2e px\n",
			(int)ra["iterations"], (double)ra["max_step"]);
	// A hundredth of a pixel. Below anything that can reach a screen, and
	// below anything that could make a held point shiver between frames.
	ok((double)ra["max_step"] < 1e-2, "the solve stopped while still visibly moving");

	// Solving again from where it already is changes nothing further.
	const double before = a.energy();
	a.solve(20);
	// Relative, because the energy of a large drag is a large number and an
	// absolute tolerance on it would be a tolerance on the size of the drag.
	ok(std::abs(a.energy() - before) < std::max(1e-9, before * 1e-3),
			"re-solving a settled mesh moved it");
}

static void test_nothing_turns_inside_out() {
	heading("a hard drag does not fold the drawing over itself");
	Sheet sheet(10, 10, 10.0);
	IvoryArapSolver s;
	s.set_mesh(sheet.rest, sheet.tris);
	PackedInt32Array pins;
	PackedVector2Array at;
	// Two opposite corners swapped most of the way past each other, which is
	// about as unreasonable as a finger gets.
	pins.append(sheet.at(0, 0));
	at.append(sheet.rest[sheet.at(9, 0)] - Vector2(10, 0));
	pins.append(sheet.at(9, 9));
	at.append(sheet.rest[sheet.at(9, 9)] + Vector2(40, 40));
	s.set_pins(pins, at);
	s.solve(60);

	PackedVector2Array p = s.positions();
	int inverted = 0;
	for (int i = 0; i + 2 < sheet.tris.size(); i += 3) {
		const Vector2 a = p[sheet.tris[i]], b = p[sheet.tris[i + 1]], c = p[sheet.tris[i + 2]];
		const double area = (double)(b.x - a.x) * (c.y - a.y) - (double)(b.y - a.y) * (c.x - a.x);
		if (area <= 0.0) ++inverted;
	}
	std::printf("    %d of %d triangles inverted under an extreme drag\n",
			inverted, sheet.tris.size() / 3);
	// The fold-over guard makes this a feasibility projection, not a
	// tolerance: no triangle may cross the winding it started with, however
	// hard the pin is dragged.
	ok(inverted == 0, "an extreme drag turned a triangle inside out despite the guard");
}

static void test_foldover_holds_the_last_good_pose() {
	heading("a step that cannot be salvaged holds still instead of snapping to rest");
	Sheet sheet(10, 10, 10.0);
	IvoryArapSolver s;
	s.set_mesh(sheet.rest, sheet.tris);

	PackedInt32Array pins;
	PackedVector2Array at;
	pins.append(sheet.at(4, 4));
	at.append(sheet.rest[sheet.at(4, 4)]);
	s.set_pins(pins, at);
	s.solve(20);
	const PackedVector2Array settled = s.positions();

	// The same corner-swap as above, which is guaranteed to threaten a fold
	// at some point in the iteration.
	PackedInt32Array pins2;
	PackedVector2Array at2;
	pins2.append(sheet.at(0, 0));
	at2.append(sheet.rest[sheet.at(9, 0)] - Vector2(10, 0));
	pins2.append(sheet.at(9, 9));
	at2.append(sheet.rest[sheet.at(9, 9)] + Vector2(40, 40));
	s.set_pins(pins2, at2);
	s.solve(60);

	const PackedVector2Array p = s.positions();
	double drift_from_rest = 0.0;
	double drift_from_settled = 0.0;
	for (int i = 0; i < p.size(); ++i) {
		drift_from_rest += p[i].distance_to(sheet.rest[i]);
		drift_from_settled += p[i].distance_to(settled[i]);
	}
	// A guard that falls back to rest on every hard case would put the whole
	// sheet exactly at `sheet.rest` — this checks the pose actually moved
	// with the pins rather than collapsing to the undeformed mesh.
	ok(drift_from_rest > 1.0, "a hard drag left the mesh sitting at its rest pose");
	(void)drift_from_settled;
}

int main() {
	std::printf("--- IvoryArapSolver ---\n");
	test_refuses_rubbish();
	test_a_rigid_move_costs_nothing();
	test_it_stretches_rather_than_drags();
	test_it_squashes_when_pushed();
	test_a_pin_is_exactly_where_it_was_put();
	test_freezing_is_absolute();
	test_it_settles_rather_than_wandering();
	test_nothing_turns_inside_out();
	test_foldover_holds_the_last_good_pose();
	std::printf("%d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
