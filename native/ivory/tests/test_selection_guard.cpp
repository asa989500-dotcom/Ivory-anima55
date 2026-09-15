#include "../src/ivory_selection_guard.h"
#include <cmath>
#include <cstdio>

using namespace godot;

static int checks = 0;
static int failures = 0;
static void ok(bool v, const char *m) {
	++checks;
	if (!v) { ++failures; std::printf("FAIL: %s\n", m); }
}

static bool passed(const Dictionary &d) { return bool(d.get("ok", false)); }

int main() {
	IvorySelectionGuard g;

	PackedVector2Array box;
	box.append(Vector2(10, 20));
	box.append(Vector2(100, 120));
	Dictionary r = g.validate_mark(box, 0, 2048);
	ok(passed(r), "normal rectangle was rejected");
	ok((int)r.get("width", 0) > 0 && (int)r.get("height", 0) > 0,
			"normal rectangle produced no bounds");

	PackedVector2Array nan;
	nan.append(Vector2(0, 0));
	nan.append(Vector2((float)NAN, 4));
	ok(!passed(g.validate_mark(nan, 0, 2048)), "NaN mark was accepted");

	PackedVector2Array huge;
	huge.append(Vector2(0, 0));
	huge.append(Vector2(1000000, 4));
	ok(!passed(g.validate_mark(huge, 0, 2048)), "huge selection crossed the limit");

	ok(passed(g.validate_transform(Vector2(50, 50), Vector2(100, 100),
			1.0, 0.0, 2048)), "normal transform was rejected");
	ok(!passed(g.validate_transform(Vector2(0, 0), Vector2(100, 100),
			41.0, 0.0, 2048)), "oversized scale was accepted");
	ok(!passed(g.validate_transform(Vector2(0, 0), Vector2(100, 100),
			1.0, NAN, 2048)), "NaN rotation was accepted");

	std::printf("Selection guard: %d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
