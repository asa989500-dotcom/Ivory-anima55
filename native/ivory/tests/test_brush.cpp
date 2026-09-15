// The three new stamp families, and the knife's one hard promise.
#include "../src/ivory_brush.h"

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

struct Stats {
	double lo = 1e30, hi = -1e30, mean = 0.0, ink = 0.0;
	int n = 0;
};

static Stats look(const PackedFloat32Array &a) {
	Stats s;
	s.n = a.size();
	double sum = 0.0;
	int lit = 0;
	for (int i = 0; i < a.size(); ++i) {
		const double v = a[i];
		s.lo = std::min(s.lo, v);
		s.hi = std::max(s.hi, v);
		sum += v;
		if (v > 0.05) ++lit;
	}
	s.mean = a.size() ? sum / a.size() : 0.0;
	s.ink = a.size() ? (double)lit / (double)a.size() : 0.0;
	return s;
}

// Every stamp has to satisfy the same handful of things or it is not usable
// as a stamp, whatever it looks like.
static void check_stamp(const PackedFloat32Array &a, int px, const char *name) {
	Stats s = look(a);
	++checks;
	if (s.n != px * px) {
		++failures;
		std::printf("  FAIL: %s is the wrong size (%d)\n", name, s.n);
		return;
	}
	bool finite = true;
	bool bounded = true;
	for (int i = 0; i < a.size(); ++i) {
		if (!std::isfinite((double)a[i])) finite = false;
		if (a[i] < 0.0f || a[i] > 1.0f) bounded = false;
	}
	ok(finite, "every value is a number");
	ok(bounded, "every value is between nought and one");
	ok(s.hi > 0.35, "the stamp actually has ink on it");
	ok(s.ink > 0.008, "and enough of it to see");
	ok(s.ink < 0.97, "and it is not simply a solid square");

	// The border must be clear, or every dab prints its own square outline.
	double edge = 0.0;
	for (int i = 0; i < px; ++i) {
		edge = std::max(edge, (double)a[i]);
		edge = std::max(edge, (double)a[(px - 1) * px + i]);
		edge = std::max(edge, (double)a[i * px]);
		edge = std::max(edge, (double)a[i * px + px - 1]);
	}
	ok(edge < 0.02, "the stamp fades out before its own border");
}

static void test_web() {
	heading("the cell network");

	IvoryBrush b;
	const int px = 96;
	for (int v = 0; v < 5; ++v) {
		check_stamp(b.web(px, v), px, "web");
	}

	// The five are genuinely different, which is the point of having five.
	std::vector<double> ink;
	for (int v = 0; v < 5; ++v) {
		ink.push_back(look(b.web(px, v)).ink);
	}
	bool distinct = true;
	for (size_t i = 0; i < ink.size(); ++i) {
		for (size_t k = i + 1; k < ink.size(); ++k) {
			if (std::fabs(ink[i] - ink[k]) < 0.004) distinct = false;
		}
	}
	ok(distinct, "the five nets are not five copies of one net");

	// Fine really does have smaller cells than coarse. Counted as strand
	// crossings along a line through the middle, which is the cell size
	// directly — total ink is not, since a fine net's strands are thinner
	// and the two effects very nearly cancel.
	auto crossings = [&](int v) {
		PackedFloat32Array a = b.web(px, v);
		int n = 0;
		bool was = false;
		for (int x = 0; x < px; ++x) {
			const bool on = a[(px / 2) * px + x] > 0.4;
			if (on && !was) ++n;
			was = on;
		}
		return n;
	};
	ok(crossings(1) > crossings(2),
			"the fine net has smaller cells than the coarse one");

	// A network is connected: the strands must reach across the stamp, not
	// sit in the middle. Checked by looking for ink in a ring well out from
	// the centre.
	PackedFloat32Array net = b.web(px, 0);
	double outer = 0.0;
	for (int y = 0; y < px; ++y) {
		for (int x = 0; x < px; ++x) {
			const double dx = x - px * 0.5, dy = y - px * 0.5;
			const double r = std::sqrt(dx * dx + dy * dy) / (px * 0.5);
			if (r > 0.45 && r < 0.6) {
				outer = std::max(outer, (double)net[y * px + x]);
			}
		}
	}
	ok(outer > 0.3, "the network reaches out from the middle");

	// Deterministic: the same brush twice is the same picture. A stamp that
	// re-rolls would make one stroke not match the next.
	ok(b.web(px, 3) == b.web(px, 3), "the same net is generated every time");
}

static void test_halo() {
	heading("the hair halos");

	IvoryBrush b;
	const int px = 96;
	for (int v = 0; v < 5; ++v) {
		check_stamp(b.halo(px, v), px, "halo");
	}

	// Dense really is denser than sparse.
	ok(look(b.halo(px, 2)).ink > look(b.halo(px, 1)).ink,
			"the foam is denser than the wide halos");

	// Screened, not added: the crossings must not have saturated the whole
	// stamp to solid. If they had, the mean would be near one over the ink.
	Stats dense = look(b.halo(px, 4));
	ok(dense.mean < 0.75, "crossings do not blow out to solid white");
	ok(dense.hi > 0.6, "but the crossings are still darker than one ring");

	ok(b.halo(px, 0) == b.halo(px, 0), "the same halo every time");
}

static void test_chalk() {
	heading("the chalk line");

	IvoryBrush b;
	const int px = 96;
	for (int v = 0; v < 5; ++v) {
		check_stamp(b.chalk(px, v), px, "chalk");
	}

	// Chalk has a tooth: the stamp must be broken up rather than smooth.
	// Measured as how much of the lit area is at neither extreme.
	PackedFloat32Array c = b.chalk(px, 0);
	int mid = 0, lit = 0;
	for (int i = 0; i < c.size(); ++i) {
		if (c[i] > 0.05) {
			++lit;
			if (c[i] < 0.85) ++mid;
		}
	}
	ok(lit > 0 && (double)mid / (double)lit > 0.25,
			"the mark is broken rather than a solid stripe");

	// Worn is bitten harder than fine, so it keeps less ink.
	ok(look(b.chalk(px, 3)).mean < look(b.chalk(px, 1)).mean,
			"the worn stub lays down less than the fine stick");

	// The broad one is squashed, so it is wider than it is tall.
	PackedFloat32Array broad = b.chalk(px, 2);
	double across = 0.0, down = 0.0;
	for (int i = 0; i < px; ++i) {
		if (broad[(px / 2) * px + i] > 0.05) across += 1.0;
		if (broad[i * px + px / 2] > 0.05) down += 1.0;
	}
	ok(across > down * 1.3, "the broad chalk is a chisel, not a circle");
}

static void test_dispatch() {
	heading("asking for a family by name");

	IvoryBrush b;
	ok(b.knows(String("web")), "web is known");
	ok(b.knows(String("halo")), "halo is known");
	ok(b.knows(String("chalk")), "chalk is known");
	ok(!b.knows(String("pen")), "a family that lives in GDScript is not");
	ok(b.stamp(String("pen"), 32, 0).is_empty(),
			"and asking for it gives nothing rather than a wrong shape");
	ok(b.stamp(String("web"), 32, 0).size() == 32 * 32, "web comes by name");
	// Out-of-range variants are clamped rather than crashing, because a
	// preset file from a later version will one day ask for a sixth.
	ok(b.stamp(String("web"), 32, 99).size() == 32 * 32,
			"an unknown variant is clamped");
	ok(b.stamp(String("web"), 32, -3).size() == 32 * 32,
			"and so is a negative one");
}

int main() {
	std::printf("\nthe three stamp families\n"
			"========================\n\n");
	test_web();
	test_halo();
	test_chalk();
	test_dispatch();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
