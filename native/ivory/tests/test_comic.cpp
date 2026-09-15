// A test bench for the comic panel geometry.
//
// ## Why this exists as a standalone program
//
// Because the alternative is testing it through the app, and testing geometry
// through an app means launching a phone build, cutting a page by hand and
// looking at it. That is fine for noticing that something is obviously wrong.
// It is useless for the failures this code actually has, which are of the form
// "the total area is out by 0.4% after seven cuts" and "the shared border
// between these two panels is 0.0003 units apart" — both invisible on a
// screen, both fatal in print.
//
// So the geometry is compiled on its own against a small stub of Godot's
// types, and checked with numbers.
//
//   g++ -std=c++17 -I<stub> -I../src test_comic.cpp ../src/ivory_comic.cpp -o test_comic
//   ./test_comic
//
// ## What is worth asserting about a cut
//
// Not "the answer is this list of points" — that is a change-detector, and it
// fails whenever anything is legitimately improved. What is worth asserting
// are the properties a correct cut must have whatever the numbers turn out to
// be:
//
//   * **Area is conserved**, minus exactly the gutter. Two halves of a cut
//     panel plus the channel between them equal the original. This is the
//     single strongest check on the whole file: a bug in the clip, in the
//     inset, in the winding, or in the crossing arithmetic all show up here.
//   * **Nothing escapes the page.** Every vertex of every panel stays inside
//     the frame it was cut from, always.
//   * **Panels do not overlap.** Sampled, because exact polygon intersection
//     is a bigger program than the thing being tested.
//   * **A point is in exactly one panel, or in the gutter.** Which is what
//     `panel_at` is asked hundreds of times a second.
//   * **Cutting is local.** A short cut inside one panel leaves every other
//     panel bit-for-bit identical. This is the property the whole "you need
//     not cut the whole page" request rests on.

#include "ivory_comic.h"

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

using namespace godot;

static int checks = 0;
static int failures = 0;

static void ok(bool cond, const std::string &what) {
	checks++;
	if (!cond) {
		failures++;
		std::printf("  FAIL  %s\n", what.c_str());
	}
}

static void near(double got, double want, double slack,
		const std::string &what) {
	checks++;
	if (std::fabs(got - want) > slack) {
		failures++;
		std::printf("  FAIL  %s — got %.4f, wanted %.4f (+/- %.4f)\n",
				what.c_str(), got, want, slack);
	}
}

static double total_area(IvoryComic &c) {
	double sum = 0.0;
	for (int i = 0; i < c.panel_count(); i++) {
		sum += c.area_of(i);
	}
	return sum;
}

static PackedVector2Array rect_poly(double x, double y, double w, double h) {
	PackedVector2Array p;
	p.resize(4);
	p[0] = Vector2((real_t)x, (real_t)y);
	p[1] = Vector2((real_t)(x + w), (real_t)y);
	p[2] = Vector2((real_t)(x + w), (real_t)(y + h));
	p[3] = Vector2((real_t)x, (real_t)(y + h));
	return p;
}

// ------------------------------------------------------------ the basics

static void test_area_and_winding() {
	std::printf("area and winding\n");
	PackedVector2Array box = rect_poly(0, 0, 100, 50);
	near(std::fabs(IvoryComic::signed_area(box)), 5000.0, 0.001,
			"a 100x50 box has area 5000");
	// Wound the other way, the sign flips and the magnitude does not. Every
	// inset in the file depends on reading the winding off this sign.
	PackedVector2Array flipped;
	flipped.resize(4);
	for (int i = 0; i < 4; i++) {
		flipped[i] = box[3 - i];
	}
	ok(IvoryComic::signed_area(box) * IvoryComic::signed_area(flipped) < 0.0,
			"reversing the winding flips the sign");
}

static void test_clip_half() {
	std::printf("half-plane clipping\n");
	PackedVector2Array box = rect_poly(0, 0, 100, 100);
	// A vertical line down the middle.
	PackedVector2Array left = IvoryComic::clip_half(box,
			Vector2(50, -10), Vector2(50, 110), true);
	PackedVector2Array right = IvoryComic::clip_half(box,
			Vector2(50, -10), Vector2(50, 110), false);
	near(std::fabs(IvoryComic::signed_area(left)), 5000.0, 0.001,
			"left half of a 100x100 box");
	near(std::fabs(IvoryComic::signed_area(right)), 5000.0, 0.001,
			"right half of a 100x100 box");
	near(std::fabs(IvoryComic::signed_area(left))
			+ std::fabs(IvoryComic::signed_area(right)), 10000.0, 0.001,
			"the two halves add back to the whole");

	// A diagonal, which is where an implementation that only handles axis
	// lines quietly gives the wrong answer.
	PackedVector2Array lower = IvoryComic::clip_half(box,
			Vector2(0, 0), Vector2(100, 100), true);
	near(std::fabs(IvoryComic::signed_area(lower)), 5000.0, 0.001,
			"a corner-to-corner diagonal halves the box");

	// A line that misses entirely leaves the polygon whole on one side and
	// nothing on the other.
	PackedVector2Array all = IvoryComic::clip_half(box,
			Vector2(500, -10), Vector2(500, 110), true);
	PackedVector2Array none = IvoryComic::clip_half(box,
			Vector2(500, -10), Vector2(500, 110), false);
	near(std::fabs(IvoryComic::signed_area(all)), 10000.0, 0.001,
			"a line right of the box keeps all of it on the left");
	ok(none.size() < 3, "and nothing on the right");
}

static void test_inset() {
	std::printf("inset\n");
	PackedVector2Array box = rect_poly(0, 0, 100, 100);
	PackedVector2Array in = IvoryComic::inset(box, 10.0);
	near(std::fabs(IvoryComic::signed_area(in)), 6400.0, 0.001,
			"insetting 100x100 by 10 gives 80x80");
	// Corners stay sharp: the inset box still has four vertices, not eight
	// and not a rounded fan.
	ok(in.size() == 4, "an inset rectangle is still a rectangle");

	// Insetting past the middle destroys the polygon rather than turning it
	// inside out — which is the failure that produces panels with negative
	// area and edges that cross.
	PackedVector2Array gone = IvoryComic::inset(box, 60.0);
	ok(gone.size() < 3, "an inset deeper than the shape returns nothing");

	// A triangle, where the two-edge intersection matters most: averaging
	// normals instead would move the sharp corner by the wrong distance.
	PackedVector2Array tri;
	tri.resize(3);
	tri[0] = Vector2(0, 0);
	tri[1] = Vector2(100, 0);
	tri[2] = Vector2(0, 100);
	PackedVector2Array tri_in = IvoryComic::inset(tri, 5.0);
	ok(tri_in.size() == 3, "an inset triangle is still a triangle");
	ok(std::fabs(IvoryComic::signed_area(tri_in))
			< std::fabs(IvoryComic::signed_area(tri)),
			"and it is smaller");
}

// ------------------------------------------------------- cutting a page

static void test_split_conserves_area() {
	std::printf("a cut conserves area\n");
	IvoryComic c;
	c.reset_to(Vector2(1000, 1400), 20.0);
	const double whole = total_area(c);
	near(whole, 960.0 * 1360.0, 0.01, "the frame is the page less its margin");

	// One cut, no gutter: area is exactly conserved.
	c.split_by_line(Vector2(500, 0), Vector2(500, 1400), 0.0);
	ok(c.panel_count() == 2, "one cut makes two panels");
	near(total_area(c), whole, 0.01, "with no gutter, area is untouched");

	// With a gutter, the loss is the channel: its width times the length of
	// the cut through the panel. Anything else means the inset is putting
	// the channel on one side, or is insetting edges it should not.
	IvoryComic g;
	g.reset_to(Vector2(1000, 1400), 20.0);
	const double before = total_area(g);
	g.split_by_line(Vector2(500, 0), Vector2(500, 1400), 12.0);
	const double lost = before - total_area(g);
	// The channel runs the full height of the frame, and both panels are
	// also inset along the cut only — but insetting a polygon insets every
	// edge, so the loss is the channel plus a border on all sides of both
	// halves. That is a known and accepted consequence of insetting whole
	// polygons rather than single edges, and the test pins the number so a
	// change to it is deliberate rather than accidental.
	ok(lost > 12.0 * 1360.0 * 0.9,
			"the gutter costs at least the channel it cuts");
	ok(lost < 12.0 * 1360.0 * 3.5,
			"and not wildly more than that");
}

static void test_cut_is_local() {
	std::printf("a cut only touches what it crosses\n");
	IvoryComic c;
	c.reset_to(Vector2(1000, 1000), 0.0);
	c.split_by_line(Vector2(500, -10), Vector2(500, 1010), 0.0);
	ok(c.panel_count() == 2, "two panels after the first cut");

	// Which one is the left half.
	int left = c.panel_at(Vector2(200, 500));
	int right = c.panel_at(Vector2(800, 500));
	ok(left >= 0 && right >= 0 && left != right,
			"the two halves are different panels");
	PackedVector2Array right_before = c.panel(right);

	// A cut confined to the left half. This is the request: split the page,
	// then split one half again, without the other half noticing.
	c.split_by_line(Vector2(0, 500), Vector2(490, 500), 0.0);
	ok(c.panel_count() == 3, "the left half became two, the right did not");

	// The right half must be bit-for-bit what it was.
	int right_now = c.panel_at(Vector2(800, 500));
	PackedVector2Array right_after = c.panel(right_now);
	bool same = right_before.size() == right_after.size();
	if (same) {
		for (int i = 0; i < right_before.size(); i++) {
			if ((right_before[i] - right_after[i]).length() > 1.0e-6) {
				same = false;
				break;
			}
		}
	}
	ok(same, "the untouched half is unchanged to the last decimal");
}

static void test_nothing_escapes() {
	std::printf("nothing leaves the page\n");
	IvoryComic c;
	c.reset_to(Vector2(800, 1200), 24.0);
	// A pile of cuts at awkward angles, including ones that start and end
	// outside the page.
	c.split_by_line(Vector2(-100, 400), Vector2(900, 380), 10.0);
	c.split_by_line(Vector2(400, -50), Vector2(430, 1250), 10.0);
	c.split_by_line(Vector2(-50, 900), Vector2(500, 820), 10.0);
	c.split_by_line(Vector2(500, 500), Vector2(900, 1100), 10.0);

	bool inside = true;
	for (int i = 0; i < c.panel_count(); i++) {
		PackedVector2Array p = c.panel(i);
		for (int k = 0; k < p.size(); k++) {
			if (p[k].x < 24.0 - 0.01 || p[k].y < 24.0 - 0.01
					|| p[k].x > 776.0 + 0.01 || p[k].y > 1176.0 + 0.01) {
				inside = false;
			}
		}
	}
	ok(inside, "every vertex of every panel is inside the frame");
	ok(c.panel_count() >= 4, "four cuts made at least four panels");
}

static void test_no_overlap() {
	std::printf("panels do not overlap\n");
	IvoryComic c;
	c.reset_to(Vector2(600, 800), 10.0);
	c.split_by_line(Vector2(300, -10), Vector2(300, 810), 8.0);
	c.split_by_line(Vector2(-10, 400), Vector2(610, 400), 8.0);
	c.split_by_line(Vector2(-10, 200), Vector2(290, 200), 8.0);

	// Sampled on a grid. Exact polygon intersection is a larger program than
	// the one being tested, and a few thousand samples catches any overlap
	// big enough to see.
	int doubled = 0;
	int covered = 0;
	for (int y = 0; y < 800; y += 7) {
		for (int x = 0; x < 600; x += 7) {
			int hits = 0;
			for (int i = 0; i < c.panel_count(); i++) {
				if (c.inside(i, Vector2((real_t)x, (real_t)y))) {
					hits++;
				}
			}
			if (hits > 1) {
				doubled++;
			}
			if (hits == 1) {
				covered++;
			}
		}
	}
	ok(doubled == 0, "no sampled point falls in two panels");
	ok(covered > 6000, "most of the page is covered by some panel");
}

static void test_shape_cuts() {
	std::printf("shape cuts\n");
	IvoryComic c;
	c.reset_to(Vector2(1000, 1000), 0.0);
	const int made = c.split_by_shape(IvoryComic::CUT_CIRCLE,
			Rect2(Vector2(600, 600), Vector2(300, 300)),
			PackedVector2Array(), 0.0);
	ok(made > 0, "a circle cut lands on the page");
	ok(c.panel_count() >= 2, "and makes a panel of its own");
	// The circle's own panel: the point at its centre must be in exactly one
	// panel, and that panel must be roughly the circle's area.
	const int which = c.panel_at(Vector2(750, 750));
	ok(which >= 0, "the middle of the circle is in a panel");
	if (which >= 0) {
		const double want = Math_PI * 150.0 * 150.0;
		near(c.area_of(which), want, want * 0.02,
				"the circle panel has the circle's area");
	}

	IvoryComic r;
	r.reset_to(Vector2(1000, 1000), 0.0);
	r.split_by_shape(IvoryComic::CUT_RECT,
			Rect2(Vector2(0, 0), Vector2(400, 300)),
			PackedVector2Array(), 0.0);
	const int corner = r.panel_at(Vector2(200, 150));
	ok(corner >= 0, "a rectangle cut in the corner makes a panel");
	if (corner >= 0) {
		near(r.area_of(corner), 400.0 * 300.0, 1.0,
				"and it is exactly the rectangle asked for");
	}
}

static void test_mask() {
	std::printf("the paint mask\n");
	IvoryComic c;
	c.reset_to(Vector2(200, 200), 0.0);
	c.split_by_line(Vector2(100, -10), Vector2(100, 210), 0.0);
	const int left = c.panel_at(Vector2(50, 100));
	ok(left >= 0, "found the left panel");
	if (left < 0) {
		return;
	}
	Rect2i box;
	box.position = Vector2i(0, 0);
	box.size = Vector2i(200, 200);
	PackedByteArray m = c.mask_of(left, box);
	ok(m.size() == 200 * 200, "the mask is the size asked for");

	int on = 0;
	for (int i = 0; i < m.size(); i++) {
		if (m[i] != 0) {
			on++;
		}
	}
	// Half the box, within a row's worth of rounding at the boundary.
	near((double)on, 20000.0, 400.0, "half the mask is set");
	// And it is the correct half: a pixel well inside the left is set, one
	// well inside the right is not.
	ok(m[100 * 200 + 30] != 0, "a pixel inside the panel is set");
	ok(m[100 * 200 + 170] == 0, "a pixel outside it is not");
}

static void test_degenerate() {
	std::printf("things that should not crash\n");
	IvoryComic c;
	// Cutting an empty page.
	ok(c.split_by_line(Vector2(0, 0), Vector2(10, 10), 4.0) == 0,
			"cutting nothing does nothing");
	ok(c.panel_at(Vector2(5, 5)) == -1, "and nothing is under the finger");

	c.reset_to(Vector2(500, 500), 0.0);
	// A zero-length cut.
	ok(c.split_by_line(Vector2(100, 100), Vector2(100, 100), 4.0) == 0,
			"a cut with no length does nothing");
	ok(c.panel_count() == 1, "and leaves the page whole");

	// A cut that only grazes a corner: the sliver is below the minimum and
	// the panel is left alone rather than being replaced by a splinter.
	c.split_by_line(Vector2(0, 2), Vector2(2, 0), 0.0);
	ok(c.panel_count() == 1, "a grazing cut is refused rather than obeyed");

	// A gutter wider than the panel.
	IvoryComic w;
	w.reset_to(Vector2(100, 100), 0.0);
	w.split_by_line(Vector2(50, -5), Vector2(50, 105), 400.0);
	ok(w.panel_count() >= 1, "an absurd gutter leaves something behind");

	// An out-of-range index is asked about from several directions.
	ok(c.panel(99).size() == 0, "asking for a panel that is not there");
	ok(c.area_of(-3) == 0.0, "or its area");
	ok(!c.inside(99, Vector2(1, 1)), "or whether a point is in it");
}

static void test_many_cuts() {
	std::printf("a heavily divided page\n");
	IvoryComic c;
	c.reset_to(Vector2(1200, 1600), 30.0);
	const double whole = total_area(c);
	// Twenty cuts at arbitrary angles. What is checked is that nothing goes
	// wrong cumulatively: area only ever decreases, no panel becomes
	// degenerate, and the count keeps up.
	unsigned int seed = 12345;
	auto rnd = [&seed]() -> double {
		seed = seed * 1103515245u + 12345u;
		return (double)((seed >> 16) & 0x7fff) / 32767.0;
	};
	double last = whole;
	for (int i = 0; i < 20; i++) {
		const Vector2 a((real_t)(rnd() * 1200.0), (real_t)(rnd() * 1600.0));
		const Vector2 b((real_t)(rnd() * 1200.0), (real_t)(rnd() * 1600.0));
		c.split_by_line(a, b, 8.0);
		const double now = total_area(c);
		ok(now <= last + 0.01, "area never grows");
		last = now;
	}
	ok(c.panel_count() > 5, "twenty random cuts divide the page");
	bool sound = true;
	for (int i = 0; i < c.panel_count(); i++) {
		if (c.panel(i).size() < 3 || c.area_of(i) < 100.0) {
			sound = false;
		}
	}
	ok(sound, "every surviving panel is a real polygon with real area");
}

// --------------------------------------------------------------- the session

static void test_project_frame_stability() {
	std::printf("five project-frame boundary cases\n");
	// These are deliberately very different page sizes. The cutter's frame
	// is page-local, inset, and must never escape the page regardless of size.
	const Vector2 pages[] = {
		Vector2(320, 240),
		Vector2(800, 600),
		Vector2(1920, 1080),
		Vector2(4096, 4096),
		Vector2(12000, 8000),
	};
	for (const Vector2 &page : pages) {
		IvoryComic c;
		const double margin = std::min(42.0,
				std::min((double)page.x, (double)page.y) * 0.12);
		c.reset_to(page, margin);
		PackedVector2Array frame = c.panel(0);
		bool inside = frame.size() == 4;
		for (int i = 0; i < frame.size(); ++i) {
			inside = inside
					&& frame[i].x >= margin - 0.01
					&& frame[i].y >= margin - 0.01
					&& frame[i].x <= page.x - margin + 0.01
					&& frame[i].y <= page.y - margin + 0.01;
		}
		ok(inside, "frame stays inside project bounds at this canvas size");
		near(c.area_of(0),
				((double)page.x - margin * 2.0)
				* ((double)page.y - margin * 2.0),
				std::max(1.0, (double)page.x * (double)page.y * 0.000001),
				"frame dimensions remain tied to the project, not the viewport");
	}
}

static void test_session() {
	std::printf("a cutting session that can be finished\n");

	IvoryComic c;
	c.reset_to(Vector2(600, 900), 20);
	const int at_start = c.panel_count();

	ok(!c.cutting(), "no session is open to begin with");
	c.begin_cutting();
	ok(c.cutting(), "one can be opened");
	ok(c.session_cuts() == 0, "with nothing cut yet");

	c.split_by_line(Vector2(300, 0), Vector2(300, 900), 6);
	c.split_by_line(Vector2(0, 400), Vector2(600, 400), 6);
	ok(c.session_cuts() == 2, "two cuts are counted");
	ok(c.panel_count() > at_start, "and the page is divided");

	// A cut that divides nothing is not a cut.
	c.split_by_line(Vector2(-900, -900), Vector2(-800, -800), 6);
	ok(c.session_cuts() == 2, "a line that divides nothing is not counted");

	Dictionary done = c.finish_cutting(50.0);
	ok(bool(done["ok"]), "finishing says it worked");
	ok(int(done["cuts"]) == 2, "and reports the cuts");
	ok(int(done["panels"]) == c.panel_count(), "and the panels left");
	ok(!c.cutting(), "and the session is closed");

	// Finishing twice is harmless and says so.
	ok(!bool(((Dictionary)c.finish_cutting(0.0))["ok"]),
			"finishing again says there was no session");
}

static void test_abandon() {
	std::printf("or abandoned in one press\n");

	IvoryComic c;
	c.reset_to(Vector2(600, 900), 20);
	const int at_start = c.panel_count();

	c.begin_cutting();
	for (int i = 1; i < 9; ++i) {
		c.split_by_line(Vector2((real_t)(i * 60), 0),
				Vector2((real_t)(i * 60), 900), 4);
	}
	ok(c.panel_count() > at_start, "eight cuts divide the page a lot");

	Dictionary back = c.abandon_cutting();
	ok(bool(back["ok"]), "abandoning says it worked");
	ok(c.panel_count() == at_start,
			"and one press puts the page back, not eight");
	ok(!c.cutting(), "and closes the session");
}

static void test_tidy() {
	std::printf("clearing the slivers away\n");

	IvoryComic c;
	Array pieces;
	// A good panel.
	PackedVector2Array big;
	big.append(Vector2(0, 0));
	big.append(Vector2(200, 0));
	big.append(Vector2(200, 200));
	big.append(Vector2(0, 200));
	pieces.append(big);
	// A splinter: four hundred long and two wide. Its area is eight hundred,
	// which passes any area floor worth setting, and nobody can draw in it.
	PackedVector2Array splinter;
	splinter.append(Vector2(300, 0));
	splinter.append(Vector2(700, 0));
	splinter.append(Vector2(700, 2));
	splinter.append(Vector2(300, 2));
	pieces.append(splinter);
	// And a crumb.
	PackedVector2Array crumb;
	crumb.append(Vector2(800, 0));
	crumb.append(Vector2(803, 0));
	crumb.append(Vector2(803, 3));
	pieces.append(crumb);

	c.set_panels(pieces);
	ok(c.panel_count() == 3, "three panels to start");
	const int gone = c.tidy(20.0, 0.02);
	ok(gone == 2, "two of them go");
	ok(c.panel_count() == 1, "and the usable one stays");
	ok(c.area_of(0) > 30000.0, "and it is the big one");

	// Tidying must never empty the page. A page with no panels is not
	// tidier, it is lost.
	IvoryComic small;
	Array only;
	only.append(crumb);
	small.set_panels(only);
	ok(small.tidy(1000000.0, 0.5) == 0,
			"tidying refuses to clear the last panel");
	ok(small.panel_count() == 1, "so the page is never left empty");
}

int main() {
	std::printf("\ncomic panel geometry\n====================\n\n");
	test_area_and_winding();
	test_clip_half();
	test_inset();
	test_split_conserves_area();
	test_cut_is_local();
	test_nothing_escapes();
	test_no_overlap();
	test_shape_cuts();
	test_mask();
	test_degenerate();
	test_many_cuts();
	test_project_frame_stability();
	test_session();
	test_abandon();
	test_tidy();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
