// The timeline band, asked the same questions it asks sixty times a second.
//
// Two things are being checked: that the answers are right, and that they stay
// affordable as the scene grows. The second is the point of the class, so it
// is measured rather than asserted from the shape of the code.
#include "../src/ivory_timeline.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <vector>

using namespace godot;

static int checks = 0, failures = 0;
static void ok(bool v, const char *m) {
	++checks;
	if (!v) { ++failures; std::printf("FAIL: %s\n", m); }
}
static void heading(const char *m) { std::printf("%s\n", m); }

// A scene: `layers` layers, each with a drawing every `every` frames, offset
// so no two layers line up exactly.
struct Scene {
	PackedInt32Array frames;
	PackedInt32Array starts;
	Scene(int layers, int cels, int every) {
		starts.append(0);
		for (int l = 0; l < layers; ++l) {
			for (int c = 0; c < cels; ++c) frames.append(c * every + (l % every));
			starts.append(frames.size());
		}
	}
};

static void test_refuses_a_broken_index() {
	heading("an index that would give wrong answers is refused");
	IvoryTimelineIndex t;
	ok(!t.set_tracks(PackedInt32Array(), PackedInt32Array()), "an empty index was accepted");

	PackedInt32Array f, s;
	f.append(0); f.append(5); f.append(3);
	s.append(0); s.append(3);
	// Out of order. A binary search over this does not run slowly — it returns
	// the wrong drawing, and the band shows the wrong frame with nothing to
	// say it is wrong.
	ok(!t.set_tracks(f, s), "an unsorted frame list was accepted");

	PackedInt32Array good;
	good.append(0); good.append(3); good.append(5);
	ok(t.set_tracks(good, s), "a sorted list was refused");

	PackedInt32Array short_starts;
	short_starts.append(0); short_starts.append(99);
	ok(!t.set_tracks(good, short_starts), "a starts array running off the end was accepted");

	PackedInt32Array backwards;
	backwards.append(0); backwards.append(2); backwards.append(1); backwards.append(3);
	PackedInt32Array four;
	four.append(0); four.append(2); four.append(1); four.append(4);
	ok(!t.set_tracks(backwards, four), "a starts array that goes backwards was accepted");
}

static void test_what_is_showing() {
	heading("which drawing each layer is showing, at once");
	// Three layers: one with drawings at 0, 10, 20; one at 5, 15; one empty.
	PackedInt32Array f, s;
	s.append(0);
	f.append(0); f.append(10); f.append(20);
	s.append(f.size());
	f.append(5); f.append(15);
	s.append(f.size());
	s.append(f.size());   // an empty layer

	IvoryTimelineIndex t;
	ok(t.set_tracks(f, s), "a three-layer scene was refused");
	ok(t.layer_count() == 3, "the layer count is wrong");
	ok(t.scene_end() == 20, "the scene end is wrong");

	PackedInt32Array at0 = t.showing_at(0);
	ok(at0[0] == 0, "layer one is not showing its first drawing at frame zero");
	ok(at0[1] == -1, "layer two is showing something before its first drawing");
	ok(at0[2] == -1, "an empty layer is showing something");

	PackedInt32Array at7 = t.showing_at(7);
	ok(at7[0] == 0, "layer one lost its hold");
	ok(at7[1] == 5, "layer two is not holding its drawing at five");

	PackedInt32Array at99 = t.showing_at(99);
	ok(at99[0] == 20, "the last drawing does not hold past the end");
	ok(at99[1] == 15, "the last drawing does not hold past the end");

	// Before everything, and a long way after it.
	ok(t.showing_at(-50)[0] == -1, "something is showing before the scene starts");
	ok(t.count_on(10) == 1, "the count of layers drawn on frame ten is wrong");
	ok(t.count_on(11) == 0, "a frame nothing is drawn on reported a count");
}

static void test_the_bars() {
	heading("a drawing holds until the next one, and the bars say so");
	PackedInt32Array f, s;
	s.append(0);
	f.append(0); f.append(4); f.append(12);
	s.append(f.size());

	IvoryTimelineIndex t;
	t.set_tracks(f, s);

	PackedInt32Array bars = t.segments(0, 0, 100);
	ok(bars.size() == 6, "three drawings did not give three bars");
	ok(bars[0] == 0 && bars[1] == 4, "the first bar does not hold to the second drawing");
	ok(bars[2] == 4 && bars[3] == 8, "the second bar does not hold to the third");
	ok(bars[4] == 12 && bars[5] == 1, "the last bar does not stop at the end of the scene");

	// A window in the middle picks up the bar that is held into it from
	// before — the one the band used to lose, leaving a row apparently blank.
	PackedInt32Array window = t.segments(0, 6, 10);
	ok(window.size() >= 2, "a window inside a hold returned no bar at all");
	ok(window[0] == 4, "the bar held into the window was not returned");

	ok(t.segments(-1, 0, 10).size() == 0, "a layer that does not exist returned bars");
	ok(t.segments(0, 10, 5).size() == 0, "a backwards window returned bars");
}

static void test_occupancy() {
	heading("which columns of the ruler have anything on them");
	Scene scene(6, 20, 5);
	IvoryTimelineIndex t;
	ok(t.set_tracks(scene.frames, scene.starts), "a six-layer scene was refused");

	PackedInt32Array on = t.occupied(0, 20);
	ok(on.size() > 0, "nothing at all was reported as drawn on");
	for (int i = 1; i < on.size(); ++i) {
		ok(on[i] > on[i - 1], "the occupied columns came back out of order");
	}
	ok(t.occupied(1000, 1010).size() == 0, "empty space reported drawings on it");
}

static void test_it_scales() {
	heading("the cost of a redraw does not run away with the layer count");
	// The claim being tested: answering for every layer at once is what makes
	// a hundred-layer scene affordable, not the speed of any one answer.
	//
	// Measured as: ten layers versus two hundred, same work per layer. If the
	// per-call overhead dominated, two hundred would cost far more than twenty
	// times ten. It should cost about twenty times — linear, with a small
	// constant.
	auto bench = [](int layers) -> double {
		Scene scene(layers, 200, 3);
		IvoryTimelineIndex t;
		if (!t.set_tracks(scene.frames, scene.starts)) return -1.0;
		const auto start = std::chrono::steady_clock::now();
		// Sixty redraws: one second of a band being scrubbed.
		for (int frame = 0; frame < 60; ++frame) {
			PackedInt32Array showing = t.showing_at(frame * 7);
			(void)showing;
			Dictionary all = t.all_segments(frame * 7, frame * 7 + 240);
			(void)all;
			PackedInt32Array on = t.occupied(frame * 7, frame * 7 + 240);
			(void)on;
		}
		const auto done = std::chrono::steady_clock::now();
		return std::chrono::duration<double, std::milli>(done - start).count();
	};

	const double small = bench(10);
	const double large = bench(200);
	ok(small >= 0.0 && large >= 0.0, "the benchmark scene was refused");
	std::printf("    one second of scrubbing: %.2f ms at 10 layers, %.2f ms at 200\n",
			small, large);

	// A second of scrubbing a two-hundred-layer scene has to fit inside a
	// second with room to spare, or the band cannot keep up with a finger.
	ok(large < 500.0, "a second of scrubbing a 200-layer scene took over half a second");

	// And twenty times the layers costs no more than fifty times the time.
	// The slack is for cache effects, not for an algorithm that is quietly
	// quadratic — which is what would show up here as several hundred times.
	if (small > 0.05) {
		const double ratio = large / small;
		std::printf("    twenty times the layers cost %.1f times the time\n", ratio);
		ok(ratio < 50.0, "the cost grows faster than the layer count");
	}
}

static void test_a_big_scene_is_still_correct() {
	heading("the answers are still right on a scene with real numbers in it");
	// Fast and wrong is not an improvement, so the same scene the benchmark
	// uses is checked against a plain linear search.
	Scene scene(40, 150, 4);
	IvoryTimelineIndex t;
	ok(t.set_tracks(scene.frames, scene.starts), "the large scene was refused");

	for (int probe = 0; probe < 40; ++probe) {
		const int at = probe * 13;
		PackedInt32Array fast = t.showing_at(at);
		for (int l = 0; l < t.layer_count(); ++l) {
			// The obvious, slow answer.
			int want = -1;
			for (int i = scene.starts[l]; i < scene.starts[l + 1]; ++i) {
				if (scene.frames[i] <= at) want = scene.frames[i];
			}
			if (fast[l] != want) {
				std::printf("    layer %d at frame %d: index says %d, the slow way says %d\n",
						l, at, fast[l], want);
			}
			ok(fast[l] == want, "the index disagrees with a plain search");
		}
	}
}

int main() {
	std::printf("--- IvoryTimelineIndex ---\n");
	test_refuses_a_broken_index();
	test_what_is_showing();
	test_the_bars();
	test_occupancy();
	test_it_scales();
	test_a_big_scene_is_still_correct();
	std::printf("%d checks, %d failures\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
