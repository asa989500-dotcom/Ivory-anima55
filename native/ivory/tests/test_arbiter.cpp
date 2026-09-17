// One tool at a time, and a way out that always works.
#include "../src/ivory_arbiter.h"

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

static void fill(IvoryArbiter &a) {
	a.offer(String("brush"), IvoryArbiter::KIND_MODE);
	a.offer(String("eraser"), IvoryArbiter::KIND_MODE);
	a.offer(String("blend2"), IvoryArbiter::KIND_MODE);
	a.offer(String("blend"), IvoryArbiter::KIND_MODE);
	a.offer(String("comic_cut"), IvoryArbiter::KIND_MODE);
	a.offer(String("bones"), IvoryArbiter::KIND_STANDING);
	a.offer(String("rig"), IvoryArbiter::KIND_STANDING);
}

static void test_exclusive() {
	heading("no two at once");

	IvoryArbiter a;
	fill(a);

	ok(!a.anything_live(), "nothing is live to begin with");

	Dictionary first = a.choose(String("brush"));
	ok(bool(first["ok"]), "the brush can be picked up");
	ok(a.live() == String("brush"), "and is live");
	ok(((String)first["dropped"]).is_empty(), "having dropped nothing");

	Dictionary second = a.choose(String("blend2"));
	ok(((String)second["dropped"]) == String("brush"),
			"picking up the blend2 drops the brush");
	ok(a.live() == String("blend2"), "and the blend2 is live");

	// Round the whole rail: at every point exactly one thing is live and
	// the last one was named as dropped.
	const char *ids[] = { "blend", "eraser", "comic_cut", "brush", "blend2" };
	String was = a.live();
	for (const char *id : ids) {
		Dictionary d = a.choose(String(id));
		ok(((String)d["dropped"]) == was, "each choice drops exactly the last");
		ok(a.live() == String(id), "and the new one is the only one live");
		was = String(id);
	}

	// Pressing the live one turns it off rather than doing nothing.
	Dictionary again = a.choose(a.live());
	ok(String(again["reason"]) == String("toggled_off"),
			"pressing the lit button turns it off");
	ok(!a.anything_live(), "and leaves nothing live");

	// An unknown tool cannot become live, or the next choice would report
	// dropping something the caller never turned on.
	Dictionary odd = a.choose(String("nonsense"));
	ok(!bool(odd["ok"]), "an unregistered tool is refused");
	ok(!a.anything_live(), "and does not become live");
}

static void test_standing() {
	heading("bones do not count");

	IvoryArbiter a;
	fill(a);

	a.choose(String("bones"));
	ok(a.standing(String("bones")), "the rig is up");
	ok(!a.anything_live(), "but it is not the live mode");

	a.choose(String("brush"));
	ok(a.live() == String("brush"), "the brush is live");
	ok(a.standing(String("bones")), "and the rig is still up");

	Dictionary d = a.choose(String("blend"));
	ok(((String)d["dropped"]) == String("brush"),
			"choosing a mode drops only the mode");
	ok(a.standing(String("bones")), "structure is left alone");

	a.clear();
	ok(!a.anything_live(), "clearing ends the mode");
	ok(a.standing(String("bones")), "and still leaves the rig up");

	a.choose(String("bones"));
	ok(!a.standing(String("bones")), "pressing it again lowers it");

	// A tool that changes from a mode to structure cannot stay live.
	a.choose(String("blend2"));
	a.offer(String("blend2"), IvoryArbiter::KIND_STANDING);
	ok(!a.anything_live(),
			"a tool that becomes structure stops being the live mode");

	// Forgetting the live tool clears it, so a screen that is torn down
	// cannot leave a live mode pointing at nothing.
	a.offer(String("blend2"), IvoryArbiter::KIND_MODE);
	a.choose(String("blend2"));
	a.forget(String("blend2"));
	ok(!a.anything_live(), "forgetting the live tool clears it");
}

// A whole four-finger tap, done properly.
static Dictionary four_finger_tap(IvoryArbiter &a, double t0, double travel,
		double hold, int fingers = 4, double spread = 0.0) {
	for (int i = 0; i < fingers; ++i) {
		a.finger_down(i, Vector2((real_t)(i * 40), 100),
				t0 + i * spread);
	}
	if (travel > 0.0) {
		for (int i = 0; i < fingers; ++i) {
			a.finger_moved(i, Vector2((real_t)(i * 40 + travel), 100));
		}
	}
	Dictionary last;
	for (int i = 0; i < fingers; ++i) {
		last = a.finger_up(i, t0 + hold);
	}
	return last;
}

static void test_four_fingers() {
	heading("four fingers cancel");

	IvoryArbiter a;
	fill(a);
	a.choose(String("bones"));
	a.choose(String("comic_cut"));

	Dictionary fired = four_finger_tap(a, 1.0, 0.0, 0.10);
	ok(bool(fired["fired"]), "four fingers fire");
	ok(((String)fired["cancelled"]) == String("comic_cut"),
			"and cancel whatever was live");
	ok(!a.anything_live(), "leaving nothing live");
	ok(a.standing(String("bones")),
			"but the rig is untouched — bones do not count");
	ok(a.cancels() == 1, "and it is counted");

	// It works from anywhere, whatever the mode is.
	const char *ids[] = { "brush", "eraser", "blend2", "blend" };
	for (const char *id : ids) {
		a.choose(String(id));
		Dictionary d = four_finger_tap(a, 10.0, 0.0, 0.08);
		ok(bool(d["fired"]) && !a.anything_live(),
				"it cancels every mode there is");
	}

	// And firing with nothing live is harmless.
	Dictionary empty = four_finger_tap(a, 20.0, 0.0, 0.08);
	ok(bool(empty["fired"]), "it still fires with nothing live");
	ok(!bool(empty["was_live"]), "and says there was nothing to cancel");
}

static void test_gesture_is_not_trigger_happy() {
	heading("and do not fire when nobody asked");

	IvoryArbiter a;
	fill(a);
	a.set_gesture(14.0, 0.35, 1.10);

	// Choosing the tool that is already live turns it off, so each of these
	// starts from nothing. Reaching for `choose` twice in a row here was a
	// mistake in an earlier draft of this file and it made three of the
	// checks below pass for the wrong reason.
	auto arm = [&](const char *id) {
		a.clear();
		a.choose(String(id));
	};

	// Three fingers: within reach of a hand resting on a phone.
	arm("brush");
	Dictionary three = four_finger_tap(a, 1.0, 0.0, 0.08, 3);
	ok(!bool(three["fired"]), "three fingers do not fire");
	ok(a.anything_live(), "and the tool is still there");

	// Five: a palm.
	arm("brush");
	Dictionary five = four_finger_tap(a, 2.0, 0.0, 0.08, 5);
	ok(!bool(five["fired"]), "five fingers do not fire");
	ok(a.anything_live(), "a palm does not cancel the tool");

	// A four-finger drag is a pan. This is the one that ruins the feature
	// if it is missed: every pan would cancel the tool underneath it.
	arm("brush");
	Dictionary drag = four_finger_tap(a, 3.0, 60.0, 0.20);
	ok(!bool(drag["fired"]), "a four-finger drag does not fire");
	ok(a.anything_live(), "so panning does not cancel the tool");

	// A drag that goes out and comes back has still been dragged.
	arm("brush");
	for (int i = 0; i < 4; ++i) {
		a.finger_down(i, Vector2((real_t)(i * 40), 100), 4.0);
	}
	for (int i = 0; i < 4; ++i) {
		a.finger_moved(i, Vector2((real_t)(i * 40 + 30), 100));
		a.finger_moved(i, Vector2((real_t)(i * 40), 100));
	}
	Dictionary there_and_back;
	for (int i = 0; i < 4; ++i) {
		there_and_back = a.finger_up(i, 4.2);
	}
	ok(!bool(there_and_back["fired"]),
			"a drag that returns to its start is still a drag");
	ok(a.anything_live(), "and does not cancel");

	// Four fingers arriving one at a time over a second is not a tap.
	arm("brush");
	Dictionary slow = four_finger_tap(a, 5.0, 0.0, 0.10, 4, 0.30);
	ok(!bool(slow["fired"]), "fingers arriving separately do not fire");

	// A hand rested on the screen and lifted later is not a tap either.
	arm("brush");
	Dictionary rested = four_finger_tap(a, 6.0, 0.0, 3.0);
	ok(!bool(rested["fired"]), "a rested hand does not fire");
	ok(a.anything_live(), "and does not cancel");

	// A small amount of travel is forgiven, because no finger is perfectly
	// still and a gesture that demands it never fires.
	arm("brush");
	Dictionary wobble = four_finger_tap(a, 7.0, 3.0, 0.10);
	ok(bool(wobble["fired"]), "a little wobble is still a tap");
}

static void test_edges() {
	heading("arbiter things that should not crash");

	IvoryArbiter a;
	ok(!bool(((Dictionary)a.choose(String("")))["ok"]),
			"an empty id is refused");
	a.offer(String(""), IvoryArbiter::KIND_MODE);
	ok(a.offered().is_empty(), "and is not registered");
	ok(a.kind_of(String("ghost")) == -1, "an unknown tool has no kind");
	a.forget(String("ghost"));
	a.raise(String("ghost"));
	a.lower(String("ghost"));
	ok(a.standing_now().is_empty(), "raising a tool that is not there does nothing");

	// A finger lifting that was never put down.
	Dictionary d = a.finger_up(9, 1.0);
	ok(!bool(d["fired"]), "an unmatched release does not fire");
	a.finger_moved(9, Vector2(0, 0));
	ok(a.fingers_down() == 0, "and moving one does not create it");

	// The same finger index down twice, which some panels do report.
	a.finger_down(1, Vector2(0, 0), 1.0);
	a.finger_down(1, Vector2(5, 5), 1.0);
	ok(a.fingers_down() == 1, "the same finger down twice is one finger");
	a.finger_up(1, 1.1);
	ok(a.fingers_down() == 0, "and one release clears it");

	// Silly gesture settings are clamped rather than making it impossible.
	a.set_gesture(-5.0, -1.0, -1.0);
	a.offer(String("brush"), IvoryArbiter::KIND_MODE);
	a.choose(String("brush"));
	four_finger_tap(a, 1.0, 0.0, 0.005);
	ok(true, "silly gesture settings do not divide by nought");
}

int main() {
	std::printf("\none tool at a time\n==================\n\n");
	test_exclusive();
	test_standing();
	test_four_fingers();
	test_gesture_is_not_trigger_happy();
	test_edges();
	std::printf("\n%d checks, %d failures\n\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
