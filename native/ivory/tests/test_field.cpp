// The canvas with no edges, and the eleven ways off it.
#include "../src/ivory_field.h"

#include <cmath>
#include <cstdio>

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

// ------------------------------------------------------------------- field

static void test_addressing() {
	heading("addressed, not allocated");

	IvoryField f;
	f.set_tile(256);

	ok(f.tile_of(Vector2(0, 0)) == Vector2i(0, 0), "the origin is tile nought");
	ok(f.tile_of(Vector2(255, 255)) == Vector2i(0, 0), "and so is its corner");
	ok(f.tile_of(Vector2(256, 0)) == Vector2i(1, 0), "the next one along is one");

	// Negative coordinates are ordinary, not a special case. Truncation
	// instead of flooring would fold -0.5 and +0.5 into one tile and put a
	// seam through the origin that nothing else in the app has.
	ok(f.tile_of(Vector2(-1, -1)) == Vector2i(-1, -1),
			"just left of the origin is tile minus one");
	ok(f.tile_of(Vector2(-256, 0)) == Vector2i(-1, 0), "and so is a tile out");
	ok(f.tile_of(Vector2(-257, 0)) == Vector2i(-2, 0), "and further still");

	// A long way out, which is the whole point.
	ok(f.tile_of(Vector2(-8000000, 3000000)).x < -30000,
			"a long way out is still addressable");

	Rect2 r = f.tile_rect(Vector2i(-3, 2));
	ok(r.position.x == -768 && r.position.y == 512,
			"a tile knows where it is");
	ok(r.size.x == 256, "and how big");

	// The cap is reported rather than silently applied.
	Dictionary small = f.tiles_in(Rect2(0, 0, 300, 300), 64);
	ok(((PackedVector2Array)small["tiles"]).size() == 4,
			"a small rectangle covers four tiles");
	ok(!bool(small["truncated"]), "and is not truncated");
	Dictionary huge = f.tiles_in(Rect2(0, 0, 500000, 500000), 100);
	ok(bool(huge["truncated"]), "an enormous one says it was truncated");
	ok(((PackedVector2Array)huge["tiles"]).size() == 100,
			"and stops at the cap");
	ok(int64_t(huge["wanted"]) > 100, "while still saying what was wanted");
}

static void test_no_shiver() {
	heading("nothing moves when the view does");

	IvoryField f;
	f.set_anchor_grid(4.0);

	// A mark a long way from the origin, which is where single-precision
	// round-tripping loses its digits.
	const Vector2 mark(184320.5f, -97280.25f);

	f.set_view(Vector2(0, 0), 1.0, Vector2(1080, 2400));
	const Vector2 first = f.anchor(f.to_canvas(f.to_screen(mark)));

	// Now pan and pinch the view through a hundred different states and ask
	// again every time. This is exactly what happens while a finger is
	// dragging the canvas around.
	bool steady = true;
	for (int i = 0; i < 100; ++i) {
		const double zoom = 0.25 + (i % 20) * 0.35;
		f.set_view(Vector2((real_t)(i * 137.4 - 5000.0),
				(real_t)(i * -91.7 + 3000.0)), zoom, Vector2(1080, 2400));
		const Vector2 now = f.anchor(f.to_canvas(f.to_screen(mark)));
		if (!(now == first)) {
			steady = false;
			break;
		}
	}
	ok(steady, "an anchored mark does not move through a hundred views");

	// The round trip itself is close, not merely stable.
	f.set_view(Vector2(-4211.5, 903.25), 3.75, Vector2(1080, 2400));
	const Vector2 back = f.to_canvas(f.to_screen(mark));
	ok(back.distance_to(mark) < 0.05, "and the round trip is accurate");

	// The anchor really does quantise: two nearby positions share one.
	ok(f.anchor(Vector2(100.1f, 40.9f)) == f.anchor(Vector2(102.9f, 43.1f)),
			"nearby positions share an anchor");
	ok(!(f.anchor(Vector2(100, 40)) == f.anchor(Vector2(140, 40))),
			"but distant ones do not");

	// A zoom of nought would divide by nought on the way back.
	f.set_view(Vector2(0, 0), 0.0, Vector2(100, 100));
	ok(std::isfinite((double)f.to_canvas(Vector2(50, 50)).x),
			"a zoom of nought is refused rather than dividing by it");
	f.set_view(Vector2(0, 0), -2.0, Vector2(100, 100));
	ok(f.zoom() > 0.0, "and a negative zoom does not mirror the drawing");
}

static void test_growth_and_tiles() {
	heading("growing, and letting go");

	IvoryField f;
	ok(!f.anything_drawn(), "a fresh canvas has nothing on it");
	f.note_point(Vector2(100, 100));
	f.note_point(Vector2(-4000, 250));
	ok(f.anything_drawn(), "and then it has");
	Rect2 c = f.content();
	ok(c.position.x <= -4000 && c.end().x >= 100,
			"the drawn area takes in everything noted");
	// A rectangle handed over backwards is still a rectangle.
	f.note(Rect2(50, 50, -200, -200));
	ok(f.content().position.y <= -150, "a backwards rectangle is still taken in");
	f.forget_content();
	ok(!f.anything_drawn(), "and it can be forgotten");

	// Tiles: the ring is what stops a pan from flickering.
	f.set_tile(256);
	f.set_view(Vector2(0, 0), 1.0, Vector2(512, 512));
	for (int y = -6; y <= 6; ++y) {
		for (int x = -6; x <= 6; ++x) {
			f.touch_tile(Vector2i(x, y), 1.0 + x * 0.01 + y * 0.02);
		}
	}
	ok(f.live_tiles() == 169, "every touched tile is live");
	ok(f.working_bytes() > 0, "and costs something");

	PackedVector2Array go = f.evictions(20, 2);
	ok(go.size() > 0, "over budget, something is let go");
	// Nothing on screen, or in the ring around it, is ever chosen.
	bool safe = true;
	for (int i = 0; i < go.size(); ++i) {
		if (go[i].x >= -2 && go[i].x <= 4 && go[i].y >= -2 && go[i].y <= 4) {
			safe = false;
		}
	}
	ok(safe, "but never a tile on screen or in the ring around it");

	ok(f.evictions(500, 2).is_empty(), "under budget, nothing is let go");
	f.drop_tile(Vector2i(-6, -6));
	ok(f.live_tiles() == 168, "a dropped tile is gone");

	Dictionary r = f.report();
	ok(int64_t(r["reach"]) > 100000000000LL,
			"the reach is a number rather than a claim");
}

// ------------------------------------------------------------------ export






int main() {
	std::printf("\nthe endless canvas\n"
			"==================\n\n");
	test_addressing();
	test_no_shiver();
	test_growth_and_tiles();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
