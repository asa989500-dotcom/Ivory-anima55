// The three things that were wrong with the quick bones, as measurements.
#include "../src/ivory_bonepose.h"
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

// A five-joint arm: shoulder 0 - elbow 1 - wrist 2 - hand 3, and a thumb 4
// hanging off the hand, so there is something below an end to test with.
struct Arm {
	PackedVector2Array rest;
	PackedInt32Array parents;
	Arm() {
		rest.append(Vector2(0, 0));    // 0 shoulder (root)
		rest.append(Vector2(40, 0));   // 1 elbow
		rest.append(Vector2(80, 0));   // 2 wrist
		rest.append(Vector2(100, 0));  // 3 hand
		rest.append(Vector2(110, 10)); // 4 thumb
		parents.append(-1);
		parents.append(0);
		parents.append(1);
		parents.append(2);
		parents.append(3);
	}
};

static void test_refuses_a_broken_skeleton() {
	heading("a skeleton that cannot be walked is refused, not hung on");
	IvoryBonePose b;
	ok(!b.set_skeleton(PackedVector2Array(), PackedInt32Array()), "an empty skeleton was accepted");

	PackedVector2Array v;
	v.append(Vector2(0, 0));
	v.append(Vector2(10, 0));
	PackedInt32Array cycle;
	cycle.append(1);
	cycle.append(0);
	ok(!b.set_skeleton(v, cycle), "a two-joint cycle was accepted");

	PackedInt32Array self;
	self.append(0);
	self.append(0);
	ok(!b.set_skeleton(v, self), "a joint that is its own parent was accepted");

	PackedInt32Array far_off;
	far_off.append(-1);
	far_off.append(9);
	ok(!b.set_skeleton(v, far_off), "a parent index off the end was accepted");

	Arm a;
	ok(b.set_skeleton(a.rest, a.parents), "a sound arm was refused");
	ok(b.joint_count() == 5, "the joint count is wrong");
}

static void test_the_hierarchy_is_read_correctly() {
	heading("what is below a joint, and what is above it");
	Arm a;
	IvoryBonePose b;
	b.set_skeleton(a.rest, a.parents);

	ok(b.descendants(0).size() == 4, "the shoulder does not have the whole arm below it");
	ok(b.descendants(1).size() == 3, "the elbow does not have the forearm below it");
	ok(b.descendants(4).size() == 0, "the thumb has something below it");
	ok(b.parent_of(0) == -1, "the shoulder is not a root");
	ok(b.parent_of(3) == 2, "the hand's parent is not the wrist");
	ok(b.is_end(4), "the thumb is not recognised as an end");
	ok(!b.is_end(2), "the wrist was called an end");
	ok(b.descendants(-1).size() == 0, "an out-of-range joint returned descendants");
}

static void test_a_drag_carries_the_limb_and_keeps_its_length() {
	heading("dragging the wrist takes the hand with it and the bones keep length");
	Arm a;
	IvoryBonePose b;
	b.set_skeleton(a.rest, a.parents);

	const Vector2 hand_before = b.positions()[3];
	Dictionary r = b.drag(2, Vector2(70, 40), 60);
	ok(bool(r["ok"]), "the drag failed");
	ok(!bool(r["blocked"]), "an unpinned joint reported itself blocked");

	PackedVector2Array p = b.positions();
	ok((double)p[2].distance_to(Vector2(70, 40)) < 1e-6, "the dragged joint is not where the finger is");
	ok((double)p[3].distance_to(hand_before) > 5.0, "the hand did not come with the wrist");

	// The shoulder is a root with nothing above it; it should barely move.
	std::printf("    worst bone length error after a drag: %.4f px\n", b.length_error());
	ok(b.length_error() < 0.2, "a bone changed length during a drag");
}

static void test_a_pinned_joint_does_not_move() {
	heading("a double-tapped joint holds its coordinates exactly");
	Arm a;
	IvoryBonePose b;
	b.set_skeleton(a.rest, a.parents);

	b.pin(1);
	ok(b.is_pinned(1), "pinning did not take");
	ok(b.pinned_count() == 1, "the pinned count is wrong");
	const Vector2 elbow = b.positions()[1];

	// Drag its neighbour about, hard, several times.
	for (int round = 0; round < 6; ++round) {
		b.drag(3, Vector2((real_t)(60 + round * 12), (real_t)(-40 + round * 15)), 60);
		PackedVector2Array p = b.positions();
		ok((double)p[1].distance_to(elbow) < 1e-9, "the pinned elbow moved while the hand was dragged");
	}

	// Dragging the pin itself is refused and says so, rather than appearing
	// not to respond.
	Dictionary r = b.drag(1, Vector2(500, 500), 40);
	ok(bool(r["blocked"]), "dragging a pinned joint was not reported as blocked");
	ok((double)b.positions()[1].distance_to(elbow) < 1e-9, "dragging a pinned joint moved it");

	b.unpin(1);
	ok(!b.is_pinned(1), "unpinning did not take");
	b.drag(3, Vector2(20, -60), 60);
	ok((double)b.positions()[1].distance_to(elbow) > 0.5, "an unpinned joint is still stuck");

	b.pin(0);
	b.pin(2);
	ok(b.pinned_count() == 2, "the pinned count did not follow");
	b.unpin_all();
	ok(b.pinned_count() == 0, "unpin_all left something pinned");
}

static void test_the_ring_turns_downward_only() {
	heading("the ring turns what is below the joint and nothing above it");
	Arm a;
	IvoryBonePose b;
	b.set_skeleton(a.rest, a.parents);

	const PackedVector2Array before = b.positions();
	Dictionary r = b.rotate_about(1, 1.5707963267948966);  // a quarter turn at the elbow
	ok(bool(r["ok"]), "the ring failed");
	ok((int)r["turned"] == 3, "the ring did not turn the three joints below the elbow");

	PackedVector2Array p = b.positions();
	// Above the elbow: untouched, to the bit.
	ok((double)p[0].distance_to(before[0]) < 1e-9, "turning the elbow moved the shoulder");
	ok((double)p[1].distance_to(before[1]) < 1e-9, "turning the elbow moved the elbow itself");
	// Below it: turned about the elbow. The wrist was 40 to the right of the
	// elbow and should now be 40 below it.
	ok(std::abs((double)p[2].x - 40.0) < 1e-4 && std::abs((double)p[2].y - 40.0) < 1e-4,
			"the wrist did not turn a quarter turn about the elbow");

	// A rotation is rigid, so no bone changed length at all.
	std::printf("    bone length error after a quarter turn: %.2e px\n", b.length_error());
	ok(b.length_error() < 1e-4, "the ring changed a bone length");

	// A full turn returns everything exactly.
	b.reset();
	b.rotate_about(1, 6.283185307179586);
	PackedVector2Array full = b.positions();
	double worst = 0.0;
	for (int i = 0; i < full.size(); ++i) worst = std::max(worst, (double)full[i].distance_to(before[i]));
	ok(worst < 1e-3, "a full turn did not come back to where it started");

	// The ring on an end bone has nothing below it to turn, and says so
	// rather than doing something surprising.
	Dictionary tip = b.rotate_about(4, 1.0);
	ok(bool(tip["ok"]) && (int)tip["turned"] == 0, "the ring on an end bone turned something");
	ok(!bool(b.rotate_about(-1, 1.0)["ok"]), "the ring accepted a joint that does not exist");
	ok(!bool(b.rotate_about(1, std::nan(""))["ok"]), "the ring accepted a NaN angle");
}

static void test_a_pin_stops_the_ring_but_not_a_hand() {
	heading("a pinned joint blocks the turn; a pinned hand may still swing");
	Arm a;
	IvoryBonePose b;
	b.set_skeleton(a.rest, a.parents);

	// A pin on the wrist. Turning the shoulder must move the elbow, and stop
	// at the wrist — the forearm swings, the hand stays put.
	b.pin(2);
	const PackedVector2Array before = b.positions();
	Dictionary r = b.rotate_about(0, 0.6);
	ok(bool(r["ok"]), "the ring failed with a pin in the chain");
	PackedVector2Array p = b.positions();
	ok((double)p[1].distance_to(before[1]) > 1.0, "the elbow did not turn");
	ok((double)p[2].distance_to(before[2]) < 1e-9, "the pinned wrist was turned anyway");
	ok((double)p[3].distance_to(before[3]) < 1e-9, "a joint below the pinned wrist was turned");
	ok((int)r["blocked"] >= 2, "the ring did not report what it refused to turn");

	// A pin on the thumb — an end bone. Turning the hand must still swing it,
	// because pinning a tip in order to turn it about its own joint is the
	// commonest reason to pin anything.
	b.reset();
	b.unpin_all();
	b.pin(4);
	const PackedVector2Array before2 = b.positions();
	Dictionary swing = b.rotate_about(3, 0.8);
	ok(bool(swing["ok"]), "the ring failed on a hand with a pinned thumb");
	ok((int)swing["turned"] == 1, "the pinned end bone was not allowed to swing");
	ok((double)b.positions()[4].distance_to(before2[4]) > 0.5, "the pinned end bone did not swing");
}

static void test_it_settles_instead_of_shivering() {
	heading("the same drag gives the same pose, to the last bit");
	// The shivering joint, as a measurement. A solver that stops before it has
	// converged gives a slightly different answer each frame, and the joint
	// that inherits the leftover error is the one that will not sit still.
	Arm a;
	IvoryBonePose x, y;
	x.set_skeleton(a.rest, a.parents);
	y.set_skeleton(a.rest, a.parents);

	x.drag(3, Vector2(55, -35), 80);
	y.drag(3, Vector2(55, -35), 80);
	PackedVector2Array px = x.positions(), py = y.positions();
	double worst = 0.0;
	for (int i = 0; i < px.size(); ++i) worst = std::max(worst, (double)px[i].distance_to(py[i]));
	ok(worst < 1e-9, "two identical drags gave two different poses");

	// Dragging to the same place again moves nothing further. This is the
	// exact condition for a joint not to shiver while a finger is held still.
	const PackedVector2Array settled = x.positions();
	for (int again = 0; again < 5; ++again) {
		x.drag(3, Vector2(55, -35), 80);
		PackedVector2Array now = x.positions();
		double moved = 0.0;
		for (int i = 0; i < now.size(); ++i) moved = std::max(moved, (double)now[i].distance_to(settled[i]));
		if (moved >= 1e-4) std::printf("    re-drag %d moved the pose by %.2e px\n", again, moved);
		// A ten-thousandth of a pixel. The tolerance is not slack: positions
		// are stored as Godot's Vector2, which is single precision, and at
		// coordinates of a hundred or two the gap between representable
		// numbers is already a few millionths. Anything tighter would be a
		// test of the float format rather than of the solver. What matters is
		// that the residue is now at that floor instead of the hundredth of a
		// pixel it was, which is the difference between a joint that sits
		// still and one that visibly trembles.
		ok(moved < 1e-4, "holding the finger still moved the rig anyway");
	}
	std::printf("    the last relaxation pass moved %.2e px\n", x.last_step());
	ok(x.last_step() < 1e-4, "the solve stopped while the rig was still moving");

	// A long chain is the case where a fixed pass count leaves the most
	// residue, so it is the one where shivering showed. Twenty joints.
	PackedVector2Array rest;
	PackedInt32Array parents;
	for (int i = 0; i < 20; ++i) {
		rest.append(Vector2((real_t)(i * 12), 0));
		parents.append(i == 0 ? -1 : i - 1);
	}
	IvoryBonePose chain;
	ok(chain.set_skeleton(rest, parents), "a twenty-joint chain was refused");
	chain.drag(19, Vector2(60, 140), 200);
	std::printf("    twenty-joint chain: length error %.4f px, last step %.2e\n",
			chain.length_error(), chain.last_step());
	ok(chain.length_error() < 0.5, "a long chain came apart under a drag");
	const PackedVector2Array chain_settled = chain.positions();
	chain.drag(19, Vector2(60, 140), 200);
	double drift = 0.0;
	PackedVector2Array again = chain.positions();
	for (int i = 0; i < again.size(); ++i) drift = std::max(drift, (double)again[i].distance_to(chain_settled[i]));
	std::printf("    twenty-joint chain re-drag drift %.2e px\n", drift);
	ok(drift < 1e-4, "a long chain drifted when the finger was held still");
}

// The drag guard (`configure_stability`) is meant to hold back a target that
// jumps too far in one call — a lag spike, a stray touch report — so the
// joint moves a bounded amount instead of teleporting. It is easy to compute
// that bounded amount and then solve towards the raw jump anyway, which
// looks identical in code review and does nothing at all on screen.
static void test_the_drag_guard_actually_guards() {
	heading("the drag guard actually limits the final position, not just a discarded number");
	Arm a;
	IvoryBonePose b;
	b.set_skeleton(a.rest, a.parents);
	b.configure_stability(0.25, 0.045, 50.0); // max_step_px = 50

	// Establish a grab near rest first — the very first drag on a joint is a
	// fresh touch-down and is deliberately unguarded, so it must not be the
	// call under test.
	b.drag(3, Vector2(101, 1), 40);
	b.drag(3, Vector2(5000, 5000), 40); // one huge jump, e.g. a lag spike
	PackedVector2Array p = b.positions();
	const double moved_this_call = (double)p[3].distance_to(Vector2(101, 1));
	std::printf("    hand moved %.2f px in one call against a 50 px cap\n", moved_this_call);
	ok(moved_this_call <= 60.0, "the max-step guard did not limit the final position");

	// The thumb hangs off the hand. If the guard holds the hand back while
	// the thumb is carried by the raw (unguarded) jump, the thumb tears away
	// from the hand by exactly the amount the guard just held back.
	const double thumb_hand = (double)p[4].distance_to(p[3]);
	const double rest_len = (double)a.rest[4].distance_to(a.rest[3]);
	std::printf("    thumb-hand distance %.4f px (rest %.4f)\n", thumb_hand, rest_len);
	ok(std::abs(thumb_hand - rest_len) < 0.5, "the thumb tore away from the guarded hand");
}

// The guard used to be one filter shared by the whole rig. Dragging one
// joint and then a different one handed the second joint the first one's
// leftover target, so it would crawl toward its own finger instead of
// arriving there.
static void test_the_drag_guard_is_independent_per_joint() {
	heading("dragging one joint does not disturb another joint's own guard");
	Arm a;
	IvoryBonePose b;
	b.set_skeleton(a.rest, a.parents);
	b.configure_stability(0.25, 0.045, 20.0); // a small cap makes contamination visible

	b.drag(1, Vector2(500, 500), 40); // drag the elbow far away first
	b.drag(3, Vector2(101, 1), 40);   // then a small, unrelated drag of the hand
	PackedVector2Array p = b.positions();
	const double d = (double)p[3].distance_to(Vector2(101, 1));
	std::printf("    hand distance to its own small target after an unrelated elbow drag: %.4f\n", d);
	ok(d < 25.0, "the hand's guard was contaminated by the elbow's leftover state");
}

int main() {
	std::printf("--- IvoryBonePose ---\n");
	test_refuses_a_broken_skeleton();
	test_the_hierarchy_is_read_correctly();
	test_a_drag_carries_the_limb_and_keeps_its_length();
	test_a_pinned_joint_does_not_move();
	test_the_ring_turns_downward_only();
	test_a_pin_stops_the_ring_but_not_a_hand();
	test_it_settles_instead_of_shivering();
	test_the_drag_guard_actually_guards();
	test_the_drag_guard_is_independent_per_joint();
	std::printf("%d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
