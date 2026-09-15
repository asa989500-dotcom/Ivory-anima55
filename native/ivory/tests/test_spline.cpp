// The curve: that it goes where the finger goes, and that nothing else moves.
#include "../src/ivory_spline.h"

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
		std::printf("  FAIL: %s (%.8f vs %.8f)\n", what, a, b);
	}
}

static void heading(const char *t) { std::printf("%s\n", t); }

// A long horizontal run of control points, so that "far away" is meaningful.
static void a_line(IvorySpline &s, int n) {
	PackedVector2Array p;
	for (int i = 0; i < n; ++i) {
		p.append(Vector2((real_t)(i * 100), 0));
	}
	s.set_points(p);
}

static void test_basics() {
	heading("the curve itself");

	IvorySpline s;
	ok(!s.ready(), "an empty spline is not ready");
	ok(s.eval(0.5) == Vector2(), "and evaluating it is harmless");

	a_line(s, 8);
	ok(s.ready(), "eight points make a curve");
	ok(s.size() == 8, "and it has eight");

	// Clamped: the curve starts at the first control point and ends at the
	// last. Anything else and somebody placing a point at the end of a limb
	// finds the curve stopping short of it.
	near(s.eval(s.first_u()).distance_to(Vector2(0, 0)), 0.0, 1e-4,
			"the curve starts on the first point");
	near(s.eval(s.last_u()).distance_to(Vector2(700, 0)), 0.0, 1e-4,
			"and ends on the last");

	// The basis values at any parameter sum to one — the partition of unity,
	// which is what makes the curve a weighted average of its points and so
	// keeps it inside their hull.
	for (int i = 0; i <= 20; ++i) {
		const double u = s.first_u() +
				(s.last_u() - s.first_u()) * (i / 20.0);
		Dictionary b = s.basis_at(u);
		PackedFloat32Array v = b["values"];
		double sum = 0.0;
		bool negative = false;
		for (int k = 0; k < v.size(); ++k) {
			sum += v[k];
			if (v[k] < -1e-6) negative = true;
		}
		++checks;
		if (std::fabs(sum - 1.0) > 1e-5 || negative) {
			++failures;
			std::printf("  FAIL: basis at %.3f sums to %.6f\n", u, sum);
			break;
		}
	}
	ok(true, "the basis values sum to one everywhere and none is negative");

	// A straight line of control points gives a straight curve, so a limb
	// drawn straight does not bow.
	double bow = 0.0;
	for (int i = 0; i <= 40; ++i) {
		const double u = s.first_u() +
				(s.last_u() - s.first_u()) * (i / 40.0);
		bow = std::max(bow, (double)std::fabs(s.eval(u).y));
	}
	near(bow, 0.0, 1e-3, "straight points give a straight curve");
}

static void test_pull_is_exact() {
	heading("the curve goes exactly where the finger goes");

	IvorySpline s;
	a_line(s, 10);

	// This is the whole complaint: dragging a control point moves the curve
	// only about two thirds of the way, so the finger and the curve never
	// meet. Pulling the curve instead lands it on the target first time.
	const double u = 0.5;
	const Vector2 target(500, 180);
	Dictionary r = s.pull_at(u, target, IvorySpline::MODE_ONE);
	ok(bool(r["ok"]), "the pull worked");
	near(s.eval(u).distance_to(target), 0.0, 1e-3,
			"one pull puts the curve exactly on the target");
	near(double(r["residual"]), 0.0, 1e-3, "and it says so");

	// Repeated pulls to the same place change nothing further, so a finger
	// held still does not creep.
	Vector2 before = s.eval(u);
	for (int i = 0; i < 20; ++i) {
		s.pull_at(u, target, IvorySpline::MODE_ONE);
	}
	near(s.eval(u).distance_to(before), 0.0, 1e-3,
			"holding still does not creep");

	// Spread mode lands on it too — the minimum-norm solution is still a
	// solution, not an approximation.
	IvorySpline t;
	a_line(t, 10);
	t.pull_at(0.35, Vector2(250, -140), IvorySpline::MODE_SPREAD);
	near(t.eval(0.35).distance_to(Vector2(250, -140)), 0.0, 1e-3,
			"spreading the correction still lands exactly");

	// And the number of control points each mode moves is what it says.
	IvorySpline one;
	a_line(one, 10);
	Dictionary a = one.pull_at(0.5, Vector2(500, 90), IvorySpline::MODE_ONE);
	ok(((PackedInt32Array)a["moved"]).size() == 1,
			"one mode moves exactly one control point");
	IvorySpline four;
	a_line(four, 10);
	Dictionary b = four.pull_at(0.5, Vector2(500, 90),
			IvorySpline::MODE_SPREAD);
	ok(((PackedInt32Array)b["moved"]).size() == 4,
			"spread moves the four that are active and no more");
}

static void test_nothing_else_moves() {
	heading("and nothing outside it stirs at all");

	IvorySpline s;
	a_line(s, 14);
	s.measure(8);

	// Every control point, and the curve at forty places, before the pull.
	PackedVector2Array before_points = s.points();
	std::vector<Vector2> before_curve;
	std::vector<double> at;
	for (int i = 0; i <= 40; ++i) {
		const double u = s.first_u() +
				(s.last_u() - s.first_u()) * (i / 40.0);
		at.push_back(u);
		before_curve.push_back(s.eval(u));
	}

	Dictionary r = s.pull_at(0.5, Vector2(650, 220), IvorySpline::MODE_ONE);
	PackedInt32Array moved = r["moved"];
	ok(moved.size() == 1, "one point moved");
	const int which = moved[0];

	// Every other control point is byte-identical. Not nearly — identical.
	PackedVector2Array after_points = s.points();
	bool others_still = true;
	for (int i = 0; i < after_points.size(); ++i) {
		if (i == which) {
			continue;
		}
		if (!(after_points[i] == before_points[i])) {
			others_still = false;
		}
	}
	ok(others_still, "no other control point moved by so much as a bit");

	// And the curve outside the moved point's support is identical too. A
	// cubic control point's basis is *identically zero* outside four knot
	// spans, so this is an equality and not a tolerance.
	PackedFloat32Array k = s.knots();
	const double lo = k[which];
	const double hi = k[which + 4];
	int far = 0;
	bool far_still = true;
	for (size_t i = 0; i < at.size(); ++i) {
		if (at[i] > lo - 1e-9 && at[i] < hi + 1e-9) {
			continue;
		}
		++far;
		if (!(s.eval(at[i]) == before_curve[i])) {
			far_still = false;
		}
	}
	ok(far > 8, "there is plenty of curve outside the support to check");
	ok(far_still, "and every bit of it is unchanged, exactly");

	// Which includes both ends of the figure, which is what the complaint
	// was really about: a drag at the waist must not move a hand.
	ok(s.eval(s.first_u()) == before_curve.front(),
			"the far start of the curve did not move");
	ok(s.eval(s.last_u()) == before_curve.back(),
			"nor the far end");
}

static void test_stiff() {
	heading("bending without kinking");

	IvorySpline sharp;
	a_line(sharp, 12);
	sharp.pull_at(0.5, Vector2(550, 300), IvorySpline::MODE_ONE);
	const double kinky = sharp.bending_energy();

	IvorySpline soft;
	a_line(soft, 12);
	soft.pull_at(0.5, Vector2(550, 300), IvorySpline::MODE_STIFF);
	const double rounded = soft.bending_energy();

	ok(rounded < kinky, "the stiff mode bends more softly than the sharp one");
	// It is still a real bend, not a refusal to move.
	ok(soft.eval(0.5).distance_to(Vector2(550, 0)) > 100.0,
			"and it is still a real bend");

	// Relaxing must never move the ends. A relaxation free to move them
	// shortens the curve on every pass, and over a session the whole shape
	// creeps inwards.
	IvorySpline r;
	a_line(r, 10);
	const Vector2 first = r.point_at_index(0);
	const Vector2 last = r.point_at_index(9);
	r.relax(PackedInt32Array(), 1.0, 200);
	ok(r.point_at_index(0) == first, "relaxing leaves the first point");
	ok(r.point_at_index(9) == last, "and the last");

	// A held point stays where it was put.
	IvorySpline h;
	a_line(h, 10);
	h.set_point(4, Vector2(400, 250));
	PackedInt32Array held;
	held.append(4);
	h.relax(held, 1.0, 100);
	ok(h.point_at_index(4) == Vector2(400, 250),
			"a held point is not relaxed away");
}

static void test_knots() {
	heading("adding a knot changes nothing");

	IvorySpline s;
	PackedVector2Array p;
	p.append(Vector2(0, 0));
	p.append(Vector2(60, 140));
	p.append(Vector2(180, -40));
	p.append(Vector2(300, 120));
	p.append(Vector2(420, 20));
	p.append(Vector2(520, 160));
	s.set_points(p);

	std::vector<Vector2> before;
	for (int i = 0; i <= 60; ++i) {
		before.push_back(s.eval(i / 60.0));
	}
	const int was = s.size();

	ok(s.insert_knot(0.42), "a knot goes in");
	ok(s.size() == was + 1, "and adds a control point");

	// Boehm's guarantee: the shape is the same curve. Not similar — the
	// same, to rounding. That is what makes it safe to do to a shape
	// somebody has already spent time on.
	double worst = 0.0;
	for (int i = 0; i <= 60; ++i) {
		worst = std::max(worst, before[(size_t)i].distance_to(s.eval(i / 60.0)));
	}
	near(worst, 0.0, 1e-3, "and the curve is unchanged everywhere");

	// Sharpening gives a corner: the curve touches its control point.
	IvorySpline c;
	c.set_points(p);
	ok(c.sharpen_at(2), "a point can be sharpened");
	// After sharpening, some control point sits on the curve.
	double closest = 1e30;
	for (int i = 0; i < c.size(); ++i) {
		for (int k = 0; k <= 200; ++k) {
			closest = std::min(closest,
					(double)c.eval(k / 200.0).distance_to(c.point_at_index(i)));
		}
	}
	near(closest, 0.0, 1.0, "and the curve now touches a control point");

	// A bad knot vector is refused rather than believed, because de Boor
	// divides by a knot span and a decreasing one turns the curve inside out.
	IvorySpline bad;
	bad.set_points(p);
	PackedFloat32Array wrong;
	for (int i = 0; i < p.size() + 4; ++i) {
		wrong.append((float)(10 - i));
	}
	PackedFloat32Array kept = bad.knots();
	bad.set_knots(wrong);
	ok(bad.knots() == kept, "a decreasing knot vector is refused");
	PackedFloat32Array short_one;
	short_one.append(0.0f);
	bad.set_knots(short_one);
	ok(bad.knots() == kept, "and so is one of the wrong length");
}

static void test_length() {
	heading("distance along the curve");

	IvorySpline s;
	a_line(s, 10);
	s.measure(12);
	// Nine hundred units of straight line.
	near(s.length(), 900.0, 0.5, "a straight run measures its own length");

	// Chord summing always under-reads, because a chord is shorter than its
	// arc. On a curved run the difference is what makes bound ink creep
	// towards the start every time the table is rebuilt.
	IvorySpline c;
	PackedVector2Array p;
	for (int i = 0; i < 10; ++i) {
		const double a = Math_PI * i / 9.0;
		p.append(Vector2((real_t)(200 * std::cos(a)),
				(real_t)(200 * std::sin(a))));
	}
	c.set_points(p);
	c.measure(4);
	const double coarse = c.length();
	c.measure(40);
	const double fine = c.length();
	ok(std::fabs(coarse - fine) / std::max(fine, 1.0) < 0.002,
			"the measured length barely changes with the sampling");

	// Length and parameter invert one another.
	c.measure(16);
	for (int i = 1; i < 10; ++i) {
		const double want = c.length() * i / 10.0;
		const double u = c.u_at_length(want);
		near(c.length_at_u(u), want, 0.5, "length and parameter invert");
	}

	// Curve space round-trips: a point put into it and taken back out lands
	// where it started. This is what binds a drawing to the curve, so an
	// error here is ink that moves when nothing was moved.
	IvorySpline b;
	b.set_points(p);
	b.measure(20);
	double worst = 0.0;
	for (int i = 0; i < 12; ++i) {
		const Vector2 probe((real_t)(-150 + i * 30), (real_t)(60 + i * 9));
		Dictionary cs = b.to_curve_space(probe);
		const Vector2 back = b.from_curve_space((double)cs["s"],
				(double)cs["side"]);
		worst = std::max(worst, (double)back.distance_to(probe));
	}
	ok(worst < 2.0, "curve space round-trips to within a couple of units");

	// And the side is signed, or ink flips across the curve when it is
	// rebound.
	Dictionary above = b.to_curve_space(Vector2(0, 260));
	Dictionary below = b.to_curve_space(Vector2(0, 140));
	ok((double(above["side"]) > 0.0) != (double(below["side"]) > 0.0),
			"which side of the curve a point was on is remembered");
}

static void test_nearest() {
	heading("finding the place under the finger");

	IvorySpline s;
	PackedVector2Array p;
	for (int i = 0; i < 9; ++i) {
		const double a = Math_PI * i / 8.0;
		p.append(Vector2((real_t)(300 * std::cos(a)),
				(real_t)(300 * std::sin(a))));
	}
	s.set_points(p);

	// A point right on the curve finds itself.
	for (int i = 1; i < 9; ++i) {
		const double u = i / 10.0;
		const Vector2 on = s.eval(u);
		near(s.eval(s.nearest_u(on)).distance_to(on), 0.0, 1.0,
				"a point on the curve finds itself");
	}
	// A point off it finds the nearest place, checked against a brute scan.
	const Vector2 off(80, 400);
	const double found = s.eval(s.nearest_u(off)).distance_to(off);
	double brute = 1e30;
	for (int i = 0; i <= 4000; ++i) {
		brute = std::min(brute, (double)s.eval(i / 4000.0).distance_to(off));
	}
	ok(found <= brute + 1.0, "and an off point finds the nearest place on it");
}

static void test_edges() {
	heading("spline things that should not crash");

	IvorySpline s;
	s.pull_at(0.5, Vector2(1, 1), IvorySpline::MODE_ONE);
	ok(s.size() == 0, "pulling an empty curve does nothing");
	ok(!s.insert_knot(0.5), "and a knot cannot go into it");
	ok(!s.sharpen_at(0), "nor a corner");
	ok(s.length() == 0.0, "and it has no length");
	ok(s.to_polyline(8).is_empty(), "and draws as nothing");
	ok(s.bending_energy() == 0.0, "and bends by nothing");

	// Fewer points than a cubic needs.
	PackedVector2Array few;
	few.append(Vector2(0, 0));
	few.append(Vector2(10, 10));
	s.set_points(few);
	ok(!s.ready(), "two points are not a cubic");
	ok(std::isfinite((double)s.eval(0.5).x), "but evaluating is still safe");

	// Exactly four: the minimum.
	few.append(Vector2(20, 0));
	few.append(Vector2(30, 10));
	s.set_points(few);
	ok(s.ready(), "four points are");
	s.measure(8);
	ok(s.length() > 0.0, "and have a length");

	// All the points on top of one another, which a double-tap can make.
	PackedVector2Array same;
	for (int i = 0; i < 6; ++i) {
		same.append(Vector2(50, 50));
	}
	IvorySpline flat;
	flat.set_points(same);
	flat.measure(8);
	ok(std::isfinite(flat.length()), "a curve of no length is still a number");
	ok(std::isfinite(flat.nearest_u(Vector2(0, 0))),
			"and can still be asked what is nearest");
	ok(std::isfinite(flat.curvature(0.5)),
			"and its curvature does not divide by nought");

	// Out-of-range indices and parameters.
	IvorySpline r;
	a_line(r, 8);
	r.set_point(-1, Vector2(0, 0));
	r.set_point(99, Vector2(0, 0));
	r.remove_point(-4);
	r.remove_point(99);
	ok(r.size() == 8, "silly indices change nothing");
	ok(std::isfinite((double)r.eval(-50.0).x), "a parameter below the range is clamped");
	ok(std::isfinite((double)r.eval(500.0).x), "and one above it");
	ok(r.point_at_index(-1) == Vector2(), "and a point that is not there is nought");
}

int main() {
	std::printf("\nthe b-spline\n============\n\n");
	test_basics();
	test_pull_is_exact();
	test_nothing_else_moves();
	test_stiff();
	test_knots();
	test_length();
	test_nearest();
	test_edges();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
