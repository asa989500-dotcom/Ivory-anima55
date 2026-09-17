// The rig: rest coordinates that do not drift, ink that rotates from where it
// was drawn, smart bones without a tick, and a cancel at every step.
#include "../src/ivory_rig360.h"

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

static void near(double a, double b, double tol, const char *what) {
	++checks;
	if (!(std::fabs(a - b) <= tol)) {
		++failures;
		std::printf("  FAIL: %s (%.6f vs %.6f)\n", what, a, b);
	}
}

static void heading(const char *t) { std::printf("%s\n", t); }

// Head, then a spine, then an arm off it.
static void an_arm(IvoryRig360 &r) {
	r.add_bone(Vector2(0, 0), Vector2(0, 60), -1, IvoryRig360::PART_HEAD);
	r.add_bone(Vector2(0, 60), Vector2(0, 140), 0, IvoryRig360::PART_SPINE);
	r.add_bone(Vector2(0, 70), Vector2(80, 70), 1, IvoryRig360::PART_ARM);
	r.add_bone(Vector2(80, 70), Vector2(120, 70), 2, IvoryRig360::PART_HAND);
	r.add_bone(Vector2(120, 70), Vector2(140, 70), 3, IvoryRig360::PART_FINGER);
}

static void test_rest_never_drifts() {
	heading("the rest pose is written once and never again");

	IvoryRig360 r;
	an_arm(r);

	const Vector2 rest_hand = r.rest_head(3);
	const Vector2 posed_at_rest = r.posed_head(3);
	ok(posed_at_rest == rest_hand, "at rest, posed and rest are the same");

	// Ten thousand poses, then back to rest. If anything composed from the
	// last pose instead of from the first, this drifts — and drift is what
	// makes a sleeve creep down an arm over a session.
	for (int i = 0; i < 10000; ++i) {
		r.set_angle(2, std::sin(i * 0.031) * 1.2);
		r.set_angle(3, std::cos(i * 0.017) * 0.7);
	}
	r.rest_all();
	ok(r.posed_head(3) == rest_hand,
			"ten thousand poses and back is exactly where it started");
	ok(r.rest_head(3) == rest_hand, "and the rest pose was never touched");
	ok(r.rest_tail(4) == Vector2(140, 70), "nor any other bone's");

	// Bones keep their length under any pose.
	r.set_angle(2, 1.1);
	r.set_angle(3, -0.6);
	for (int i = 0; i < r.bone_count(); ++i) {
		const double was = r.rest_head(i).distance_to(r.rest_tail(i));
		const double now = r.posed_head(i).distance_to(r.posed_tail(i));
		near(now, was, 1e-2, "a bone keeps its length under any pose");
	}
	// And the joints stay together.
	near(r.posed_head(3).distance_to(r.posed_tail(2)), 0.0, 1e-2,
			"the hand stays on the end of the arm");
	near(r.posed_head(4).distance_to(r.posed_tail(3)), 0.0, 1e-2,
			"and the finger on the end of the hand");
}

static void test_ink_rotates_from_where_it_was_drawn() {
	heading("ink drawn on a posed figure stays where it was put");

	IvoryRig360 r;
	an_arm(r);

	// Pose the arm first, then draw on it — a person decorating a figure
	// that is already in a pose, which is the normal case and the one that
	// used to go wrong.
	r.set_angle(2, 0.9);
	PackedVector2Array hair;
	for (int i = 0; i < 8; ++i) {
		hair.append(r.posed_head(2).lerp(r.posed_tail(2),
				(real_t)(i / 7.0)) + Vector2(0, -12));
	}
	const int id = r.bind_stroke(0, hair);
	ok(id > 0, "the stroke binds");

	// Right now it must be exactly where it was drawn. Not nearly — the
	// binding is an exact inverse, so this is an equality.
	PackedVector2Array now = r.stroke_now(id);
	ok(now.size() == hair.size(), "with all its points");
	double worst = 0.0;
	for (int i = 0; i < now.size(); ++i) {
		worst = std::max(worst, (double)now[i].distance_to(hair[i]));
	}
	near(worst, 0.0, 1e-2, "and it has not moved a bit from where it was put");

	// Move the arm further: the stroke goes with it.
	r.set_angle(2, 1.4);
	PackedVector2Array moved = r.stroke_now(id);
	ok(moved[moved.size() - 1].distance_to(hair[hair.size() - 1]) > 1.0,
			"moving the arm carries the ink");

	// Back to the pose it was drawn in: exactly where it was drawn.
	r.set_angle(2, 0.9);
	PackedVector2Array back = r.stroke_now(id);
	worst = 0.0;
	for (int i = 0; i < back.size(); ++i) {
		worst = std::max(worst, (double)back[i].distance_to(hair[i]));
	}
	near(worst, 0.0, 1e-2, "and coming back puts it exactly back");

	// The stroke keeps its own shape exactly: it is carried by one bone, so
	// it cannot tear at a joint however far the joint bends. This is the
	// whole reason `bind_stroke` picks one owner instead of one per point.
	r.set_angle(2, -0.5);
	PackedVector2Array bent = r.stroke_now(id);
	for (int i = 0; i + 1 < bent.size(); ++i) {
		near(bent[i].distance_to(bent[i + 1]),
				hair[i].distance_to(hair[i + 1]), 1e-2,
				"the stroke is carried rigidly, not stretched");
	}

	// And a stroke laid deliberately across a joint, bound point by point,
	// really does follow the shape — at the cost of separating there, which
	// is why it is not the default.
	IvoryRig360 q;
	an_arm(q);
	PackedVector2Array robe;
	for (int i = 0; i < 10; ++i) {
		robe.append(Vector2((real_t)(i * 14), 70));
	}
	const int spread = q.bind_stroke_spread(0, robe);
	q.set_angle(3, 0.8);
	PackedVector2Array after = q.stroke_now(spread);
	ok(after[9].distance_to(robe[9]) > 1.0,
			"a spread stroke follows the bone under each of its points");
	ok(after[0] == robe[0], "and the part on another bone stays put");
}

static void test_ownership() {
	heading("ink belongs to the bone it is nearest along");

	IvoryRig360 r;
	an_arm(r);
	// A point out by the fingertip. Measured to bone heads it belongs to the
	// spine, which is nearer its head than the finger's head is; measured to
	// the segments it belongs to the finger, which is right.
	PackedVector2Array tip;
	tip.append(Vector2(138, 74));
	const int id = r.bind_stroke(0, tip);
	r.set_angle(4, 1.2);
	ok(r.stroke_now(id)[0].distance_to(Vector2(138, 74)) > 1.0,
			"a mark by the fingertip moves with the finger");
	r.rest_all();
	r.set_angle(0, 0.0);

	// A mark on the head moves with the head, not the hand.
	PackedVector2Array crown;
	crown.append(Vector2(2, 10));
	const int c = r.bind_stroke(0, crown);
	r.set_angle(4, 1.5);
	near(r.stroke_now(c)[0].distance_to(Vector2(2, 10)), 0.0, 1e-2,
			"and a mark on the head is not moved by the finger");
}

static void test_smart_bones() {
	heading("smart bones, without the tick");

	IvoryRig360 r;
	an_arm(r);

	// One recording: the correction fades in from nothing.
	r.record_action(2, 1.0, 3, 0.5);
	ok(r.action_count(2) == 1, "one action is recorded");
	r.set_angle(2, 1.0);
	r.apply_actions();
	near(r.angle_of(3), 0.5, 1e-6, "at the recorded angle it is exact");
	r.set_angle(2, 0.5);
	r.apply_actions();
	near(r.angle_of(3), 0.25, 1e-6, "and halfway there it is halfway");
	r.set_angle(2, 0.0);
	r.apply_actions();
	near(r.angle_of(3), 0.0, 1e-6, "and at rest it does nothing");

	// Several recordings, interpolated smoothly. The measure of "smooth"
	// that matters is that the *rate* has no jump at a recorded angle — a
	// jump there is the limb ticking as it passes.
	IvoryRig360 s;
	an_arm(s);
	s.record_action(2, 0.0, 3, 0.0);
	s.record_action(2, 0.5, 3, 0.1);
	s.record_action(2, 1.0, 3, 0.8);
	s.record_action(2, 1.5, 3, 1.0);
	ok(s.action_count(2) == 4, "four recordings");

	auto value_at = [&](double a) {
		s.set_angle(2, a);
		s.apply_actions();
		return s.angle_of(3);
	};
	near(value_at(1.0), 0.8, 1e-6, "each recording is hit exactly");
	near(value_at(0.5), 0.1, 1e-6, "all of them");

	// The rate either side of a recorded angle is nearly the same. With a
	// linear blend the ratio here is about seven; with Catmull-Rom it is
	// close to one.
	const double h = 0.02;
	const double before = (value_at(0.5) - value_at(0.5 - h)) / h;
	const double after = (value_at(0.5 + h) - value_at(0.5)) / h;
	ok(std::fabs(before - after) < std::fabs(before) * 0.6 + 0.2,
			"and the rate does not jump as it passes one");

	// Past the last recording it holds rather than extrapolating. An
	// extrapolated spline is how a limb suddenly folds when somebody drags
	// a little further than they ever recorded.
	near(value_at(4.0), 1.0, 1e-6, "past the end it holds the last value");
	near(value_at(-4.0), 0.0, 1e-6, "and before the start, the first");

	// Recording twice at the same angle replaces rather than adding, or the
	// interpolation would have two answers at one place.
	s.record_action(2, 1.0, 3, 0.2);
	ok(s.action_count(2) == 4, "recording again at the same angle replaces");
	near(value_at(1.0), 0.2, 1e-6, "with the new value");

	ok(s.clear_actions(2), "actions can be cleared");
	ok(s.action_count(2) == 0, "and then there are none");

	// A driver cannot drive itself.
	s.record_action(2, 1.0, 2, 0.5);
	ok(s.action_count(2) == 0, "a bone cannot drive itself");
}

static void test_layers() {
	heading("character 360 layers");

	IvoryRig360 r;
	ok(r.next_layer_name() == String("character 360"),
			"the first layer is the plain name");
	r.add_layer();
	ok(r.layer_names()[0] == String("character 360"), "and it takes it");

	// An ordinary "add a layer" in this file makes another Character 360
	// layer, numbered — not an ordinary layer.
	r.add_layer();
	ok(r.layer_names()[1] == String("character 360 (2)"),
			"the next is numbered");
	r.add_layer();
	ok(r.layer_names()[2] == String("character 360 (3)"), "and the next");

	// Deleting the middle one and adding another must not produce two
	// layers with the same number. Counting is how that happens; naming
	// against what exists is how it does not.
	r.remove_layer(1);
	ok(r.layer_count() == 2, "one is removed");
	r.add_layer();
	PackedStringArray names = r.layer_names();
	ok(names[2] == String("character 360 (2)"),
			"the freed number is reused rather than skipped");
	bool duplicate = false;
	for (int i = 0; i < names.size(); ++i) {
		for (int k = i + 1; k < names.size(); ++k) {
			if (names[i] == names[k]) duplicate = true;
		}
	}
	ok(!duplicate, "and no two layers share a name");

	// Strokes on a removed layer go with it, and the ones above shift down.
	IvoryRig360 s;
	an_arm(s);
	s.add_layer();
	s.add_layer();
	PackedVector2Array p;
	p.append(Vector2(10, 10));
	s.bind_stroke(0, p);
	const int on_top = s.bind_stroke(1, p);
	ok(s.stroke_count() == 2, "two strokes");
	s.remove_layer(0);
	ok(s.stroke_count() == 1, "removing a layer takes its strokes");
	ok(s.stroke_layer(on_top) == 0, "and the one above moves down");
}

static void test_suggest_and_export() {
	heading("suggesting a rig, and getting it out");

	IvoryRig360 r;
	PackedVector2Array at;
	PackedInt32Array kind;
	at.append(Vector2(50, 20));   kind.append(0);   // head
	at.append(Vector2(50, 60));   kind.append(1);
	at.append(Vector2(50, 100));  kind.append(1);
	at.append(Vector2(10, 70));   kind.append(2);   // a hand
	at.append(Vector2(90, 70));   kind.append(2);
	at.append(Vector2(45, 150));  kind.append(2);   // a foot
	const int made = r.suggest_from(at, kind);
	ok(made >= 4, "a rig is suggested");
	ok(r.bone_count() == made, "and it is all of the bones");
	ok(r.part_of(0) == IvoryRig360::PART_HEAD, "the first bone is the head");
	// The foot is below the spine, so it is a leg rather than an arm.
	bool has_leg = false;
	for (int i = 0; i < r.bone_count(); ++i) {
		if (r.part_of(i) == IvoryRig360::PART_LEG) has_leg = true;
	}
	ok(has_leg, "and something below the body is a leg");
	// Every bone is reachable from a root without looping.
	bool sane = true;
	for (int i = 0; i < r.bone_count(); ++i) {
		int at_i = i;
		int guard = 0;
		while (at_i >= 0 && guard++ <= r.bone_count()) {
			at_i = r.parent_of(at_i);
		}
		if (guard > r.bone_count()) sane = false;
	}
	ok(sane, "and no bone is its own ancestor");

	r.add_layer();
	PackedVector2Array p;
	p.append(Vector2(50, 25));
	p.append(Vector2(52, 30));
	r.bind_stroke(0, p);
	r.set_angle(0, 0.3);
	r.record_action(0, 0.3, 1, 0.1);

	Dictionary out = r.to_project();
	ok(String(out["format"]) == String("ivory-character-360"),
			"the export says what it is");
	ok(((PackedVector2Array)out["rest_head"]).size() == r.bone_count(),
			"every bone's rest pose goes out");
	ok(((PackedVector2Array)out["posed_head"]).size() == r.bone_count(),
			"and its posed one");
	// Both, and not one: a file with only the pose cannot be re-posed, and
	// one with only the rest cannot show what was on screen when the button
	// was pressed.
	// Turning a bone leaves its own head where it was — it turns about it —
	// so the tail is what to compare.
	ok(!(((PackedVector2Array)out["rest_tail"])[0] ==
			((PackedVector2Array)out["posed_tail"])[0]),
			"and they are genuinely different once it is posed");
	ok(((Array)out["strokes"]).size() == 1, "the bound ink goes out");
	ok(((Array)out["actions"]).size() == 1, "and the smart actions");
	ok(((PackedStringArray)out["layers"]).size() == 1, "and the layers");

	Dictionary s = r.summary();
	ok(int(s["bones"]) == r.bone_count(), "the summary counts the bones");
	ok(int(s["posed"]) == 1, "and says one is posed");
}

static void test_cancel() {
	heading("a way back from every step");

	IvoryRig360 r;
	an_arm(r);
	r.forget_undo();

	// An angle.
	r.set_angle(2, 0.8);
	near(r.angle_of(2), 0.8, 1e-9, "the arm is turned");
	ok(bool(((Dictionary)r.undo_last())["ok"]), "and it can be undone");
	near(r.angle_of(2), 0.0, 1e-9, "back to where it was");

	// A bone.
	const int was = r.bone_count();
	r.add_bone(Vector2(0, 0), Vector2(10, 0), -1, IvoryRig360::PART_HAIR);
	ok(r.bone_count() == was + 1, "a bone is added");
	ok(bool(((Dictionary)r.undo_last())["ok"]), "and undone");
	ok(r.bone_count() == was, "and it is gone");

	// A stroke.
	PackedVector2Array p;
	p.append(Vector2(4, 4));
	r.bind_stroke(0, p);
	ok(r.stroke_count() == 1, "a stroke is bound");
	ok(bool(((Dictionary)r.undo_last())["ok"]), "and undone");
	ok(r.stroke_count() == 0, "and it is gone");

	// A layer.
	r.add_layer();
	ok(r.layer_count() == 1, "a layer is added");
	r.undo_last();
	ok(r.layer_count() == 0, "and undone");

	// An action.
	r.record_action(2, 1.0, 3, 0.4);
	ok(r.action_count(2) == 1, "an action is recorded");
	r.undo_last();
	ok(r.action_count(2) == 0, "and undone");

	// Undoing with nothing to undo is harmless.
	r.forget_undo();
	ok(!bool(((Dictionary)r.undo_last())["ok"]),
			"undoing nothing says so rather than falling over");

	// Several in a row, in the right order.
	IvoryRig360 s;
	an_arm(s);
	s.forget_undo();
	s.set_angle(2, 0.2);
	s.set_angle(2, 0.5);
	s.set_angle(2, 0.9);
	s.undo_last();
	near(s.angle_of(2), 0.5, 1e-9, "undo takes the last step");
	s.undo_last();
	near(s.angle_of(2), 0.2, 1e-9, "then the one before");
	s.undo_last();
	near(s.angle_of(2), 0.0, 1e-9, "and then the one before that");
}

static void test_edges() {
	heading("rig things that should not crash");

	IvoryRig360 r;
	ok(r.bone_count() == 0, "an empty rig is allowed");
	ok(r.pick(Vector2(0, 0), 20) == -1, "and picking finds nothing");
	r.set_angle(4, 1.0);
	ok(r.angle_of(4) == 0.0, "posing a bone that is not there does nothing");
	ok(r.posed_head(9) == Vector2(), "and asking about one gives nought");
	ok(r.name_of(-1).is_empty(), "and it has no name");
	ok(!r.remove_bone(3), "and cannot be removed");
	ok(!r.unbind_stroke(7), "nor a stroke that was never bound");
	ok(r.stroke_now(7).is_empty(), "which is nowhere");
	ok(!r.remove_layer(0), "nor a layer");
	ok(r.suggest_from(PackedVector2Array(), PackedInt32Array()) == 0,
			"suggesting from nothing makes nothing");

	// A stroke bound with no bones at all: kept, and left where it was.
	PackedVector2Array p;
	p.append(Vector2(3, 3));
	const int id = r.bind_stroke(0, p);
	ok(r.stroke_count() == 1, "a stroke binds even with no bones");
	ok(r.stroke_now(id)[0] == Vector2(3, 3), "and stays where it was drawn");

	// A bone whose parent is itself, or does not exist.
	IvoryRig360 s;
	s.add_bone(Vector2(0, 0), Vector2(10, 0), 0, IvoryRig360::PART_ROOT);
	s.add_bone(Vector2(10, 0), Vector2(20, 0), 77, IvoryRig360::PART_ARM);
	ok(s.parent_of(0) == -1, "a bone cannot be its own parent");
	ok(s.parent_of(1) == -1, "nor have one that does not exist");
	s.set_angle(0, 0.5);
	ok(std::isfinite((double)s.posed_tail(1).x),
			"and posing does not loop for ever");

	// Removing a bone re-hangs its children rather than deleting them.
	IvoryRig360 t;
	an_arm(t);
	const int before = t.bone_count();
	ok(t.remove_bone(2), "the arm is removed");
	ok(t.bone_count() == before - 1, "one bone went");
	ok(t.parent_of(2) == 1,
			"and the hand was re-hung on the spine, not deleted with it");

	// A part out of range is clamped rather than indexing off the end of the
	// name table.
	IvoryRig360 u;
	u.add_bone(Vector2(0, 0), Vector2(1, 0), -1, 9999);
	ok(!u.name_of(0).is_empty(), "a silly part is clamped, not read past");
	u.add_bone(Vector2(0, 0), Vector2(1, 0), -1, -5);
	ok(!u.name_of(1).is_empty(), "at either end");
}


static void test_ultra_bone_controls() {
	heading("ultra bone limits and multi-driver stability");
	IvoryRig360 r;
	an_arm(r);
	r.set_angle_limits(2, -0.4, 0.6);
	r.set_angle(2, 9.0);
	near(r.angle_of(2), 0.6, 1e-6, "a bone cannot be posed past its upper limit");
	r.set_angle(2, -9.0);
	near(r.angle_of(2), -0.4, 1e-6, "a bone cannot be posed past its lower limit");
	Dictionary lim = r.angle_limits(2);
	near((double)lim["min"], -0.4, 1e-6, "the lower limit is reported");
	near((double)lim["max"], 0.6, 1e-6, "the upper limit is reported");

	IvoryRig360 s;
	an_arm(s);
	s.record_action(2, 0.0, 3, 0.0);
	s.record_action(2, 1.0, 3, 1.0);
	s.set_angle_limits(3, -0.5, 0.5);
	s.set_angle(2, 0.5);
	s.apply_actions();
	ok(s.angle_of(3) <= 0.5 + 1e-6, "smart-bone output respects target limits");
	ok(s.angle_of(3) >= -0.5 - 1e-6, "smart-bone output respects lower target limits");
	PackedFloat32Array a = s.angles();
	ok(a.size() == s.bone_count(), "all bone angles can be sampled without allocation per bone");
}

int main() {
	std::printf("\nthe character 360 rig\n=====================\n\n");
	test_rest_never_drifts();
	test_ink_rotates_from_where_it_was_drawn();
	test_ownership();
	test_smart_bones();
	test_layers();
	test_suggest_and_export();
	test_cancel();
	test_edges();
	test_ultra_bone_controls();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
