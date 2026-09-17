// Posing: what moves, what does not, and what the timeline hears about it.
#include "../src/ivory_pose.h"

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

// A four-bone arm: 0 -> 1 -> 2 -> 3, laid out along the x axis.
static void arm(IvoryPose &p) {
	PackedVector2Array h, t;
	PackedInt32Array up;
	for (int i = 0; i < 4; ++i) {
		h.append(Vector2((real_t)(i * 50), 0));
		t.append(Vector2((real_t)((i + 1) * 50), 0));
		up.append(i == 0 ? -1 : i - 1);
	}
	p.set_skeleton(h, t, up);
}

// Every point of the rig, so distances can be compared before and after.
static std::vector<Vector2> all_points(const IvoryPose &p) {
	std::vector<Vector2> out;
	PackedVector2Array h = p.head();
	PackedVector2Array t = p.tail();
	for (int i = 0; i < h.size(); ++i) {
		out.push_back(h[i]);
		out.push_back(t[i]);
	}
	return out;
}

static void test_rigidity() {
	heading("a part moves, nothing is distorted");

	IvoryPose p;
	arm(p);
	// Bone 1 and everything below it.
	std::vector<Vector2> before = all_points(p);

	p.begin_drag(1 * 2 + 1);
	p.set_steadiness(2.0, 0.5);
	p.drag(Vector2(100, 60));
	p.drag(Vector2(90, 90));
	p.end_drag();

	std::vector<Vector2> after = all_points(p);
	ok(before.size() == after.size(), "the rig still has the same bones");

	// The moved subtree is bones 1, 2, 3 — points 2 through 7. Every
	// distance within it must be identical, or something was distorted.
	double worst = 0.0;
	for (size_t i = 2; i < 8; ++i) {
		for (size_t k = i + 1; k < 8; ++k) {
			const double was = before[i].distance_to(before[k]);
			const double now = after[i].distance_to(after[k]);
			worst = std::max(worst, std::fabs(was - now));
		}
	}
	ok(worst < 1e-3, "every distance inside the moved part is unchanged");

	// Bone lengths never change, anywhere on the rig.
	PackedVector2Array h = p.head();
	PackedVector2Array t = p.tail();
	bool lengths_kept = true;
	for (int i = 0; i < h.size(); ++i) {
		if (std::fabs(h[i].distance_to(t[i]) - 50.0) > 1e-3) {
			lengths_kept = false;
		}
	}
	ok(lengths_kept, "no bone changed length");

	// And the joints stayed together: a child's head is still on its
	// parent's tail. This is the one that shows as a rig coming apart.
	bool joined = true;
	for (int i = 1; i < h.size(); ++i) {
		if (h[i].distance_to(t[i - 1]) > 1e-3) {
			joined = false;
		}
	}
	ok(joined, "the joints did not open");

	// The bone above the one dragged did not move at all.
	ok(after[0] == before[0] && after[1] == before[1],
			"the parent was left exactly where it was");
}

static void test_lock_above() {
	heading("locking what is above");

	IvoryPose p;
	arm(p);
	p.lock_above(2);

	ok(p.frozen(0), "the root is held");
	ok(p.frozen(1), "and so is everything up the chain");
	ok(!p.frozen(2), "the bone touched is free");
	ok(!p.frozen(3), "and so is what hangs below it");

	PackedInt32Array movable = p.movable_from(2);
	ok(movable.size() == 2, "two bones can move");
	ok(movable[0] == 2 && movable[1] == 3, "and they are the right two");

	// A frozen bone cannot be picked up at all. Refusing at the grab rather
	// than ignoring the drag afterwards is what makes it visible: the handle
	// simply does not answer.
	p.begin_drag(0 * 2 + 1);
	ok(!p.dragging(), "a frozen joint cannot be grabbed");
	p.begin_drag(3 * 2 + 1);
	ok(p.dragging(), "a free one can");
	p.end_drag();

	// And dragging below the freeze really does leave the rest alone.
	PackedVector2Array before_head = p.head();
	p.begin_drag(2 * 2 + 1);
	p.set_steadiness(1.0, 0.3);
	p.drag(Vector2(160, 80));
	p.end_drag();
	PackedVector2Array now = p.head();
	ok(now[0] == before_head[0] && now[1] == before_head[1] &&
			now[2] == before_head[2],
			"the frozen part of the rig did not drift by so much as a pixel");
	ok(now[3] != before_head[3], "and the free part did move");
}

static void test_cascade() {
	heading("the double tap and the cascade");

	IvoryPose p;
	arm(p);

	// One tap only selects.
	Dictionary first = p.tap(2, 1.00);
	ok(String(first["action"]) == String("selected"), "one tap selects");
	ok(!p.cascading(), "and turns nothing on");

	// Two, quickly, on the same circle.
	Dictionary second = p.tap(2, 1.20);
	ok(String(second["action"]) == String("cascaded"), "two taps cascade");
	ok(p.cascading(), "the rig is in the cascade");
	ok(p.frozen(0) && p.frozen(1), "everything above is held");
	ok(!p.frozen(2) && !p.frozen(3), "and the part below is open");

	// A third on the same circle lets it go again.
	Dictionary third = p.tap(2, 1.35);
	ok(String(third["action"]) == String("released"), "a third tap releases");
	ok(!p.cascading(), "and the rig is free again");
	ok(p.frozen_count() == 0, "with nothing held");

	// Two taps far apart in time are two separate taps.
	p.tap(1, 10.0);
	Dictionary late = p.tap(1, 12.0);
	ok(String(late["action"]) == String("selected"),
			"two slow taps are not a double tap");

	// Two taps on different circles are not a double tap either.
	p.tap(1, 20.0);
	Dictionary other = p.tap(3, 20.1);
	ok(String(other["action"]) == String("selected"),
			"two taps on different bones are not a double tap");

	// Moving the opening rather than adding a second one.
	p.tap(1, 30.0);
	p.tap(1, 30.2);
	ok(p.cascading() && !p.frozen(1), "opened below bone one");
	p.tap(3, 31.0);
	p.tap(3, 31.2);
	ok(p.frozen(1), "opening below bone three closed bone one again");
	ok(!p.frozen(3), "and bone three is the one open now");
}

static void test_steadiness() {
	heading("it does not shudder");

	IvoryPose p;
	arm(p);
	p.set_steadiness(4.0, 1.0);
	p.begin_drag(3 * 2 + 1);

	// A finger holding still on a noisy panel: half a pixel of jitter, over
	// and over. Nothing at all should happen.
	int moved = 0;
	for (int i = 0; i < 60; ++i) {
		const double n = (i % 2) ? 0.4 : -0.4;
		Dictionary d = p.drag(Vector2((real_t)(200 + n), (real_t)(n * 0.5)));
		if (bool(d["moved"])) ++moved;
	}
	ok(moved == 0, "jitter under the gate moves nothing");

	// A real movement starts it.
	Dictionary go = p.drag(Vector2(200, 40));
	ok(bool(go["moved"]), "a real drag starts it moving");

	// And once moving, small movements are honoured — otherwise the drag
	// would feel notchy, which is the other half of the problem.
	int fine = 0;
	for (int i = 0; i < 10; ++i) {
		Dictionary d = p.drag(Vector2((real_t)(200 + i * 1.5), 40));
		if (bool(d["moved"])) ++fine;
	}
	ok(fine >= 8, "once moving, small movements are followed");

	// The keep gate is forced below the start gate, whatever is asked for.
	// Equal gates are one gate, and one gate is the shudder.
	IvoryPose q;
	arm(q);
	q.set_steadiness(3.0, 99.0);
	q.begin_drag(1 * 2 + 1);
	Dictionary d = q.drag(Vector2(100, 20));
	ok(bool(d["moved"]), "a silly keep threshold is clamped, not obeyed");
}

static void test_timeline_mixing() {
	heading("three kinds of motion on one layer");

	IvoryPose p;
	arm(p);
	p.set_tracks(IvoryPose::TRACK_DRAW);
	ok(p.allows(IvoryPose::TRACK_DRAW), "a layer always draws");
	ok(!p.allows(IvoryPose::TRACK_RIG), "and starts with nothing else");

	p.allow_track(IvoryPose::TRACK_RIG);
	p.allow_track(IvoryPose::TRACK_WARP);
	ok(p.allows(IvoryPose::TRACK_DRAW) && p.allows(IvoryPose::TRACK_RIG) &&
			p.allows(IvoryPose::TRACK_WARP),
			"all three live on the same layer at once");

	// Adding one never removes another. That is the whole of "the timeline
	// stays balanced".
	p.allow_track(IvoryPose::TRACK_WARP);
	ok(p.allows(IvoryPose::TRACK_DRAW),
			"adding a track does not displace the others");

	Dictionary plan = p.plan_at(7);
	PackedInt32Array order = plan["order"];
	ok(order.size() == 3, "all three are in the plan");
	ok(order[0] == IvoryPose::TRACK_DRAW, "the picture comes first");
	ok(order[1] == IvoryPose::TRACK_RIG, "then how its parts are arranged");
	ok(order[2] == IvoryPose::TRACK_WARP, "and the bend goes on last");
	ok(bool(plan["mixed"]), "and it says so");

	// Keys are per track, so a drawn frame and a posed frame on the same
	// number are two separate facts.
	p.put_key(IvoryPose::TRACK_DRAW, 7);
	p.put_key(IvoryPose::TRACK_WARP, 12);
	ok(p.has_key(IvoryPose::TRACK_DRAW, 7), "a drawn key is recorded");
	ok(!p.has_key(IvoryPose::TRACK_RIG, 7), "and does not imply a posed one");
	PackedInt32Array keyed = ((Dictionary)p.plan_at(7))["keyed"];
	ok(keyed.size() == 1, "one track has something to say at frame seven");

	// A key put twice is one key, or scrubbing shows two frames where the
	// person made one.
	p.put_key(IvoryPose::TRACK_DRAW, 7);
	ok(p.keys_of(IvoryPose::TRACK_DRAW).size() == 1,
			"the same key twice is still one key");
	// And they come back in order.
	p.put_key(IvoryPose::TRACK_WARP, 3);
	PackedInt32Array warp = p.keys_of(IvoryPose::TRACK_WARP);
	ok(warp.size() == 2 && warp[0] == 3 && warp[1] == 12,
			"keys are kept in order");
}

static void test_keys_and_onion() {
	heading("when a frame gets built");

	IvoryPose p;
	arm(p);
	p.set_key_threshold(3.0);

	// Before anything, there is no previous pose to onion against.
	Dictionary before = p.timeline_state(0);
	ok(!bool(before["onion"]), "no onion skin before there is a pose to see");

	Dictionary made = p.make_key(0);
	ok(bool(made["first"]), "the first key says it is the first");
	ok(bool(made["dot"]), "and asks for the frame dot");

	// A pose that has not moved does not deserve a second frame. A timeline
	// full of identical keys cannot be scrubbed.
	ok(!p.wants_key(), "an unmoved pose does not want a key");

	p.begin_drag(3 * 2 + 1);
	p.set_steadiness(1.0, 0.3);
	p.drag(Vector2(200, 45));
	Dictionary end = p.end_drag();
	ok(bool(end["moved"]), "the rig moved");
	ok(p.drift() > 3.0, "and moved far enough to matter");
	ok(bool(end["wants_key"]), "so it asks for a frame");

	Dictionary second = p.make_key(4);
	ok(!bool(second["first"]), "the second key is not the first");
	ok(bool(second["onion"]), "and turns the onion skin on");

	Dictionary now = p.timeline_state(4);
	ok(bool(now["built"]), "the layer says it has just built this frame");
	ok(bool(now["dot"]), "the dot is on the frame that was built");
	ok(bool(now["onion"]), "and the onion skin is on");
	ok(!bool(((Dictionary)p.timeline_state(5))["dot"]),
			"and not on a frame that was not");

	// The drift is the furthest joint, not the average — one hand moving is
	// exactly the thing worth a frame.
	IvoryPose q;
	arm(q);
	q.set_key_threshold(5.0);
	q.make_key(0);
	q.begin_drag(3 * 2 + 1);
	q.set_steadiness(0.5, 0.2);
	q.drag(Vector2(200, 12));
	ok(q.drift() > 5.0, "one joint moving is enough to want a frame");
}

static void test_edges() {
	heading("pose things that should not crash");

	IvoryPose p;
	ok(p.bone_count() == 0, "an empty rig is allowed");
	p.cascade();
	ok(p.frozen_count() == 0, "cascading an empty rig holds nothing");
	p.lock_above(4);
	p.open_below(-1);
	ok(!p.frozen(0), "asking about a bone that is not there is safe");
	p.begin_drag(99);
	ok(!p.dragging(), "and so is grabbing one");
	Dictionary d = p.drag(Vector2(5, 5));
	ok(!bool(d["moved"]), "dragging nothing moves nothing");
	ok(String(((Dictionary)p.tap(-1, 0.0))["action"]) == String("none"),
			"tapping nothing does nothing");

	// A rig whose parents point at themselves, or forward, or off the end.
	// All three make the descendant walk loop for ever if they are believed,
	// and all three come out of files written by older versions.
	PackedVector2Array h, t;
	PackedInt32Array up;
	for (int i = 0; i < 3; ++i) {
		h.append(Vector2((real_t)(i * 10), 0));
		t.append(Vector2((real_t)(i * 10 + 10), 0));
	}
	up.append(0);    // its own parent
	up.append(2);    // a parent that comes later
	up.append(77);   // a parent that does not exist
	IvoryPose bad;
	bad.set_skeleton(h, t, up);
	ok(bad.bone_count() == 3, "a broken rig still loads");
	ok(bad.movable_from(0).size() >= 1, "and can be walked without hanging");
	bad.cascade();
	ok(bad.frozen_count() == 3, "and cascaded");

	// Mismatched head and tail lists.
	PackedVector2Array short_tail;
	short_tail.append(Vector2(0, 0));
	IvoryPose odd;
	odd.set_skeleton(h, short_tail, up);
	ok(odd.bone_count() == 1, "the shorter of the two lists wins");

	// An unknown track kind is refused rather than writing somewhere.
	IvoryPose k;
	k.put_key(999, 3);
	ok(k.keys_of(999).is_empty(), "an unknown track holds no keys");
	ok(!k.has_key(999, 3), "and reports none");
}

int main() {
	std::printf("\nposing a skeleton\n=================\n\n");
	test_rigidity();
	test_lock_above();
	test_cascade();
	test_steadiness();
	test_timeline_mixing();
	test_keys_and_onion();
	test_edges();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
