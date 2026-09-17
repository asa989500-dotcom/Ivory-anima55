#include "../src/ivory_diagnostics.h"

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

static PackedVector2Array mesh_points() {
	PackedVector2Array p;
	p.append(Vector2(0, 0));
	p.append(Vector2(10, 0));
	p.append(Vector2(0, 10));
	p.append(Vector2(10, 10));
	return p;
}

static PackedInt32Array neighbours() {
	PackedInt32Array n;
	for (int i = 0; i < 4; ++i) {
		n.append(i == 0 ? 1 : -1);
		n.append(i == 1 ? 0 : -1);
		n.append(i == 2 ? 3 : -1);
		n.append(i == 3 ? 2 : -1);
	}
	return n;
}

static PackedInt32Array triangles() {
	PackedInt32Array t;
	t.append(0); t.append(1); t.append(2);
	t.append(1); t.append(3); t.append(2);
	return t;
}

int main() {
	IvoryDiagnostics d;
	PackedVector2Array rest = mesh_points();
	PackedVector2Array now = rest;
	PackedByteArray rim;
	rim.resize(4); rim.fill(1);

	Dictionary m = d.check_mesh(rest, neighbours(), rim, triangles(), 1.0e-6);
	ok(bool(m["ok"]), "valid mesh passes");
	ok(int(m["failures"]) == 0, "valid mesh has no failures");

	PackedInt32Array bad_tri = triangles();
	bad_tri[2] = 99;
	Dictionary bad_m = d.check_mesh(rest, neighbours(), rim, bad_tri, 1.0e-6);
	ok(!bool(bad_m["ok"]), "bad triangle is rejected");

	now[1] = Vector2(11, 0);
	Dictionary pose = d.check_pose(rest, now, 20.0);
	ok(bool(pose["ok"]), "finite pose inside limit passes");
	now[2] = Vector2(NAN, 0);
	pose = d.check_pose(rest, now, 20.0);
	ok(!bool(pose["ok"]), "NaN pose is rejected");

	PackedVector2Array rp;
	PackedVector2Array np;
	PackedInt32Array pv;
	PackedFloat32Array pt;
	rp.append(Vector2(0, 0)); np.append(Vector2(1, 1)); pv.append(0); pt.append(0.0f);
	Dictionary pins = d.check_pins(rp, np, pv, pt, 4);
	ok(bool(pins["ok"]), "valid pin arrays pass");
	pv[0] = 8;
	pins = d.check_pins(rp, np, pv, pt, 4);
	ok(!bool(pins["ok"]), "out-of-range pin vertex is rejected");

	now = rest;
	now[3] = Vector2(10.00001f, 10.0f);
	Dictionary bounds = d.check_bounds(now, Vector2(0, 0), Vector2(10, 10), 0.001);
	ok(bool(bounds["ok"]), "epsilon is honoured");
	now[3] = Vector2(11, 10);
	bounds = d.check_bounds(now, Vector2(0, 0), Vector2(10, 10), 0.001);
	ok(!bool(bounds["ok"]), "escaped vertex is rejected");

	Dictionary frame = d.check_frame(8.0, 16.67, 100, 150);
	ok(bool(frame["ok"]), "frame inside budget passes");
	frame = d.check_frame(20.0, 16.67, 100, 150);
	ok(!bool(frame["ok"]), "frame over budget is reported");

	Dictionary health = d.health(m, pose, pins, bounds, frame);
	ok(!bool(health["ok"]), "aggregate health exposes failed instruments");

	std::printf("%d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
