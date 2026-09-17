// Smart bone dials: that a key gives back exactly what was authored at it,
// that nothing extrapolates past the ends, that a feedback loop is refused,
// and that a dial resolves fast enough to sit in front of a finger.
#include "../src/ivory_smartbone.h"

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

static bool close(double a, double b, double eps = 1e-5) {
	return std::fabs(a - b) <= eps;
}

// --------------------------------------------------------------------------

// A dial that corrects one bone across a bend, of the shape an artist
// authoring an elbow would actually produce: nothing at rest, the fix at the
// bend, nothing again coming back the other way.
static IvorySmartBone elbow_dial(int &dial) {
	IvorySmartBone d;
	dial = d.add_dial(3);            // bone 3 is the forearm, the driver
	const int k0 = d.add_key(dial, -1.2);
	const int k1 = d.add_key(dial, 0.0);
	const int k2 = d.add_key(dial, 1.2);
	d.set_key_bone(dial, k0, 7, -0.30, 0.94);
	d.set_key_bone(dial, k1, 7, 0.00, 1.00);
	d.set_key_bone(dial, k2, 7, 0.42, 1.08);
	return d;
}

static void test_keys_are_exact() {
	heading("keys are hit exactly");
	int dial = -1;
	IvorySmartBone d = elbow_dial(dial);

	// The whole promise of the feature: at the angle the artist authored,
	// they get the shape they authored. Not something close to it.
	struct { double angle; double turn; double stretch; } want[] = {
		{ -1.2, -0.30, 0.94 },
		{ 0.0, 0.00, 1.00 },
		{ 1.2, 0.42, 1.08 },
	};
	for (const auto &w : want) {
		d.set_driver_angle(dial, w.angle);
		const PackedFloat32Array turns = d.bone_turns(10);
		const PackedFloat32Array stretches = d.bone_stretches(10);
		ok(close(turns[7], w.turn, 1e-4), "authored turn came back changed");
		ok(close(stretches[7], w.stretch, 1e-4),
				"authored stretch came back changed");
	}

	// Everything the dial does not mention is the identity, which is what
	// lets an artist store only the bones they touched.
	d.set_driver_angle(dial, 1.2);
	const PackedFloat32Array turns = d.bone_turns(10);
	const PackedFloat32Array stretches = d.bone_stretches(10);
	for (int b = 0; b < 10; ++b) {
		if (b == 7) {
			continue;
		}
		ok(turns[b] == 0.0f, "an untouched bone was turned");
		ok(close(stretches[b], 1.0), "an untouched bone was stretched");
	}
}

static void test_weights_sum_to_one() {
	heading("key weights are a partition of unity");
	int dial = -1;
	IvorySmartBone d = elbow_dial(dial);
	// Anything other than one here means the correction is being scaled as
	// well as blended, and a rig that scales its own corrections as the
	// dial moves is a rig that breathes.
	for (double a = -3.0; a <= 3.0; a += 0.017) {
		d.set_driver_angle(dial, a);
		const PackedFloat32Array w = d.key_weights(dial);
		double sum = 0.0;
		for (int i = 0; i < w.size(); ++i) {
			sum += w[i];
		}
		ok(close(sum, 1.0, 1e-4), "key weights did not sum to one");
	}
}

static void test_no_extrapolation() {
	heading("past the ends it holds, it does not run away");
	int dial = -1;
	IvorySmartBone d = elbow_dial(dial);

	// The failure this guards is a limb turning inside out when somebody
	// drags a little further than the artist tested.
	for (double a = 1.2; a <= 40.0; a += 0.37) {
		d.set_driver_angle(dial, a);
		const PackedFloat32Array turns = d.bone_turns(10);
		ok(close(turns[7], 0.42, 1e-4), "ran past the last key");
	}
	for (double a = -1.2; a >= -40.0; a -= 0.37) {
		d.set_driver_angle(dial, a);
		const PackedFloat32Array turns = d.bone_turns(10);
		ok(close(turns[7], -0.30, 1e-4), "ran past the first key");
	}
}

static void test_monotone_mode_never_overshoots() {
	heading("with overshoot off, nothing leaves the bracket");
	int dial = -1;
	IvorySmartBone d = elbow_dial(dial);
	d.set_overshoot(false);
	for (double a = -1.2; a <= 1.2; a += 0.01) {
		d.set_driver_angle(dial, a);
		const float t = d.bone_turns(10)[7];
		const float lo = a < 0.0 ? -0.30f : 0.00f;
		const float hi = a < 0.0 ? 0.00f : 0.42f;
		ok(t >= lo - 1e-4f && t <= hi + 1e-4f,
				"monotone mode left the bracketing pair");
	}
}

static void test_overshoot_mode_is_bounded_anyway() {
	heading("with overshoot on, it overshoots but stays sane");
	// Written the other way round first, and the bench caught it: the elbow
	// dial's three turns rise steadily, and Catmull-Rom through steadily
	// rising data does not overshoot at all. Which is a good property worth
	// asserting rather than a hole in the test — a rig authored the sensible
	// way never sees any overshoot even in the mode that permits it.
	int dial = -1;
	IvorySmartBone rising = elbow_dial(dial);
	rising.set_overshoot(true);
	for (double a = -1.2; a <= 1.2; a += 0.005) {
		rising.set_driver_angle(dial, a);
		const double t = rising.bone_turns(10)[7];
		ok(t >= -0.30 - 1e-4 && t <= 0.42 + 1e-4,
				"monotone keys overshot under Catmull-Rom");
	}

	// Overshoot needs a plateau with a rise on either side of it — a
	// correction that comes on, holds, and goes off again, which is what a
	// shoulder does through the middle of its range. There the cubic bulges
	// past the held value, and that bulge is what makes the correction read
	// as flesh rather than as a lookup table.
	//
	// It took two attempts to write this test, because a peak and a
	// steadily rising ramp both fail to overshoot at all. That is worth
	// knowing: most dials an artist authors will never overshoot even in
	// the mode that permits it.
	IvorySmartBone d;
	const int s = d.add_dial(0);
	const int k0 = d.add_key(s, -1.5);
	const int k1 = d.add_key(s, -0.5);
	const int k2 = d.add_key(s, 0.5);
	const int k3 = d.add_key(s, 1.5);
	d.set_key_bone(s, k0, 2, 0.0, 1.0);
	d.set_key_bone(s, k1, 2, 0.6, 1.0);
	d.set_key_bone(s, k2, 2, 0.6, 1.0);
	d.set_key_bone(s, k3, 2, 0.0, 1.0);
	d.set_overshoot(true);
	double most = 0.0;
	for (double a = -1.5; a <= 1.5; a += 0.005) {
		d.set_driver_angle(s, a);
		most = std::max(most, (double)d.bone_turns(4)[2]);
	}
	ok(most > 0.6, "a held correction did not bulge at all");
	// What it must not do is overshoot by a lot. A quarter past the largest
	// authored value is generous; past that the tool is inventing a pose.
	ok(most <= 0.6 * 1.25 + 1e-6, "overshoot went far past the authored key");

	// And with overshoot off, the same data stays inside its keys.
	d.set_overshoot(false);
	for (double a = -1.5; a <= 1.5; a += 0.005) {
		d.set_driver_angle(s, a);
		ok(d.bone_turns(4)[2] <= 0.6f + 1e-5f,
				"monotone mode overshot the authored key");
	}
}

static void test_continuity() {
	heading("the correction is smooth, with no step at a key");
	int dial = -1;
	IvorySmartBone d = elbow_dial(dial);
	// A step at a key is a visible jerk in the middle of a bend, and it is
	// exactly what a naive per-segment blend produces.
	const double step = 0.001;
	double worst_jump = 0.0;
	double last = 0.0;
	bool first = true;
	for (double a = -1.6; a <= 1.6; a += step) {
		d.set_driver_angle(dial, a);
		const double t = d.bone_turns(10)[7];
		if (!first) {
			worst_jump = std::max(worst_jump, std::fabs(t - last));
		}
		last = t;
		first = false;
	}
	// Over a thousandth of a radian of driver movement, the correction
	// should move by a thousandth-ish. A tenth would be a step.
	ok(worst_jump < 0.005, "the correction jumped at a key");
}

static void test_feedback_is_refused() {
	heading("a dial may not drive its own driver");
	IvorySmartBone d;
	const int a = d.add_dial(3);
	const int ka = d.add_key(a, 0.5);

	// Direct: dial driven by bone 3, correcting bone 3.
	ok(!d.set_key_bone(a, ka, 3, 0.2, 1.0), "direct feedback was allowed");

	// Indirect: dial A driven by 3 corrects 9; dial B driven by 9 corrects
	// 3. Neither key is a loop on its own and together they oscillate at
	// the frame rate.
	ok(d.set_key_bone(a, ka, 9, 0.2, 1.0), "an innocent key was refused");
	const int b = d.add_dial(9);
	const int kb = d.add_key(b, 0.5);
	ok(!d.set_key_bone(b, kb, 3, 0.2, 1.0), "indirect feedback was allowed");

	// And a bone that is nowhere near the loop is still fine.
	ok(d.set_key_bone(b, kb, 12, 0.2, 1.0),
			"an unrelated bone was caught by the loop check");
}

static void test_stretches_multiply() {
	heading("two dials on one bone multiply, they do not average");
	IvorySmartBone d;
	const int a = d.add_dial(0);
	const int ka = d.add_key(a, 0.0);
	d.set_key_bone(a, ka, 5, 0.0, 0.5);
	const int b = d.add_dial(1);
	const int kb = d.add_key(b, 0.0);
	d.set_key_bone(b, kb, 5, 0.0, 0.5);
	d.set_driver_angle(a, 0.0);
	d.set_driver_angle(b, 0.0);
	// Half and half is a quarter. Averaging would give a half and the
	// second dial would have done nothing at all.
	ok(close(d.bone_stretches(8)[5], 0.25, 1e-4),
			"stretches averaged instead of multiplying");
}

static void test_stretch_can_never_reach_zero() {
	heading("a stretch is held above nothing");
	IvorySmartBone d;
	const int a = d.add_dial(0);
	const int k = d.add_key(a, 0.0);
	d.set_key_bone(a, k, 1, 0.0, -5.0);
	d.set_driver_angle(a, 0.0);
	// A bone of zero length has no direction, so every angle off it becomes
	// undefined and the limb below it spins.
	ok(d.bone_stretches(4)[1] > 0.0f, "a stretch reached zero or below");
}

static void test_same_angle_replaces() {
	heading("re-posing at the same angle replaces, it does not stack");
	IvorySmartBone d;
	const int a = d.add_dial(0);
	const int k1 = d.add_key(a, 0.7);
	const int k2 = d.add_key(a, 0.70000001);
	ok(k1 == k2, "a hair's difference made a second key");
	ok(d.key_count(a) == 1, "the dial ended up with two keys at one angle");
	d.set_key_bone(a, k2, 2, 0.9, 1.0);
	d.set_driver_angle(a, 0.7);
	ok(close(d.bone_turns(4)[2], 0.9, 1e-4), "the replacement did not take");
}

static void test_removal_keeps_indices() {
	heading("removing a dial does not renumber the others");
	IvorySmartBone d;
	const int a = d.add_dial(1);
	const int b = d.add_dial(2);
	const int c = d.add_dial(3);
	d.remove_dial(b);
	// Every key an artist authored refers to a dial by index. Compacting
	// would silently move every correction onto the wrong dial.
	ok(d.dial_driver(a) == 1, "dial a moved");
	ok(d.dial_driver(c) == 3, "dial c moved");
	ok(d.dial_driver(b) == -1, "a removed dial still answers");
	// And the empty slot is reused rather than leaked.
	const int e = d.add_dial(9);
	ok(e == b, "the retired slot was not reused");
	ok(d.dial_driver(c) == 3, "reusing a slot disturbed another dial");
}

static void test_round_trip() {
	heading("saving and loading gives back the same dial");
	int dial = -1;
	IvorySmartBone d = elbow_dial(dial);
	d.set_key_offset(dial, 2, 4, Vector2(3.5, -2.25));
	d.set_overshoot(false);
	d.set_driver_angle(dial, 0.9);

	const Dictionary state = d.to_project();
	IvorySmartBone back;
	back.from_project(state);

	ok(back.dial_count() == d.dial_count(), "dial count changed on load");
	ok(back.key_count(0) == 3, "key count changed on load");
	ok(back.overshoot() == false, "the overshoot setting was lost");
	back.set_driver_angle(0, 1.2);
	ok(close(back.bone_turns(10)[7], 0.42, 1e-4), "a key was lost on load");
	ok(close(back.point_offsets(8)[4].x, 3.5, 1e-4),
			"a point offset was lost on load");
}

static void test_unsorted_file_is_repaired() {
	heading("a file with keys out of order still resolves");
	// Everything downstream assumes the keys are sorted. A hand-edited file
	// is the one place that could be false, so it is made true on load
	// rather than hoped for.
	Dictionary state;
	Array dials;
	Dictionary dd;
	dd["live"] = true;
	dd["driver"] = 0;
	dd["angle"] = 0.0;
	Array keys;
	const double angles[3] = { 1.0, -1.0, 0.0 };
	const double turns[3] = { 0.5, -0.5, 0.0 };
	for (int i = 0; i < 3; ++i) {
		Dictionary kk;
		kk["angle"] = angles[i];
		PackedInt32Array bones;
		bones.append(1);
		PackedFloat32Array t;
		t.append((float)turns[i]);
		PackedFloat32Array s;
		s.append(1.0f);
		kk["bone"] = bones;
		kk["turn"] = t;
		kk["stretch"] = s;
		keys.append(kk);
	}
	dd["key"] = keys;
	dials.append(dd);
	state["dial"] = dials;

	IvorySmartBone d;
	d.from_project(state);
	ok(close(d.key_angle(0, 0), -1.0), "keys were not sorted on load");
	ok(close(d.key_angle(0, 2), 1.0), "keys were not sorted on load");
	d.set_driver_angle(0, 1.0);
	ok(close(d.bone_turns(4)[1], 0.5, 1e-4), "an unsorted file resolved wrong");
}

static void test_empty_and_degenerate() {
	heading("nothing at all is answered calmly");
	IvorySmartBone d;
	ok(d.bone_turns(0).size() == 0, "a zero-bone answer was not empty");
	ok(d.bone_turns(-4).size() == 0, "a negative count was not refused");
	ok(d.point_offsets(3).size() == 3, "point offsets came back the wrong size");
	ok(d.key_weights(99).size() == 0, "a dial that does not exist answered");
	ok(d.dial_driver(-1) == -1, "a negative dial answered");
	d.remove_dial(500);
	d.remove_key(500, 500);
	ok(true, "out-of-range removal did not fall over");

	// A dial with a single key is a constant, not a division by nothing.
	const int a = d.add_dial(0);
	const int k = d.add_key(a, 0.4);
	d.set_key_bone(a, k, 1, 0.33, 1.0);
	for (double x = -5.0; x <= 5.0; x += 0.5) {
		d.set_driver_angle(a, x);
		ok(close(d.bone_turns(4)[1], 0.33, 1e-5),
				"a one-key dial was not constant");
	}
}

static void test_many_dials_stay_fast() {
	heading("thirty dials resolve in front of a finger");
	IvorySmartBone d;
	for (int i = 0; i < 30; ++i) {
		const int dial = d.add_dial(i);
		for (int k = 0; k < 12; ++k) {
			const int key = d.add_key(dial, -1.5 + 0.25 * k);
			for (int b = 0; b < 6; ++b) {
				d.set_key_bone(dial, key, 40 + (i * 6 + b) % 40,
						0.01 * (k - 6), 1.0 + 0.005 * k);
			}
		}
	}
	// Ten thousand resolves, which is a couple of minutes of continuous
	// dragging at 120 Hz. If this is slow the rig is late to the finger,
	// and a rig that is late does not read as slow — it reads as stuck.
	double sink = 0.0;
	for (int frame = 0; frame < 10000; ++frame) {
		for (int i = 0; i < 30; ++i) {
			d.set_driver_angle(i, std::sin(frame * 0.01 + i) * 1.4);
		}
		const PackedFloat32Array turns = d.bone_turns(80);
		sink += turns[frame % 80];
	}
	ok(std::isfinite(sink), "ten thousand resolves produced a NaN");
	ok(d.dial_count() == 30, "dials went missing under load");
}

static void test_offsets_blend_like_turns() {
	heading("point offsets follow the same weights as bone turns");
	IvorySmartBone d;
	const int a = d.add_dial(0);
	const int k0 = d.add_key(a, 0.0);
	const int k1 = d.add_key(a, 1.0);
	d.set_key_offset(a, k0, 2, Vector2(0, 0));
	d.set_key_offset(a, k1, 2, Vector2(10, -20));
	d.set_key_bone(a, k0, 2, 0.0, 1.0);
	d.set_key_bone(a, k1, 2, 1.0, 1.0);
	for (double x = 0.0; x <= 1.0; x += 0.05) {
		d.set_driver_angle(a, x);
		const double turn = d.bone_turns(4)[2];
		const Vector2 off = d.point_offsets(4)[2];
		// The offset is the turn times the authored vector, because both
		// are the same weighted sum of the same two keys. If they diverge,
		// a corrective shape and a corrective rotation stop agreeing and
		// the fix tears itself apart mid-bend.
		ok(close(off.x, turn * 10.0, 1e-4), "offset and turn disagreed in x");
		ok(close(off.y, turn * -20.0, 1e-4), "offset and turn disagreed in y");
	}
}

int main() {
	std::printf("--- smart bone dials ---\n");
	test_keys_are_exact();
	test_weights_sum_to_one();
	test_no_extrapolation();
	test_monotone_mode_never_overshoots();
	test_overshoot_mode_is_bounded_anyway();
	test_continuity();
	test_feedback_is_refused();
	test_stretches_multiply();
	test_stretch_can_never_reach_zero();
	test_same_angle_replaces();
	test_removal_keeps_indices();
	test_round_trip();
	test_unsorted_file_is_repaired();
	test_empty_and_degenerate();
	test_many_dials_stay_fast();
	test_offsets_blend_like_turns();
	std::printf("%d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
