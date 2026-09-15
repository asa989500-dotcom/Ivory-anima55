#include "ivory_timeline.h"

#include <algorithm>

namespace godot {

void IvoryTimelineIndex::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_tracks", "frames", "starts"), &IvoryTimelineIndex::set_tracks);
	ClassDB::bind_method(D_METHOD("layer_count"), &IvoryTimelineIndex::layer_count);
	ClassDB::bind_method(D_METHOD("total_frames"), &IvoryTimelineIndex::total_frames);
	ClassDB::bind_method(D_METHOD("showing_at", "at"), &IvoryTimelineIndex::showing_at);
	ClassDB::bind_method(D_METHOD("scene_end"), &IvoryTimelineIndex::scene_end);
	ClassDB::bind_method(D_METHOD("segments", "layer", "lo", "hi"), &IvoryTimelineIndex::segments);
	ClassDB::bind_method(D_METHOD("all_segments", "lo", "hi"), &IvoryTimelineIndex::all_segments);
	ClassDB::bind_method(D_METHOD("occupied", "lo", "hi"), &IvoryTimelineIndex::occupied);
	ClassDB::bind_method(D_METHOD("count_on", "frame"), &IvoryTimelineIndex::count_on);
	ClassDB::bind_method(D_METHOD("index_at_or_after", "layer", "at"), &IvoryTimelineIndex::index_at_or_after);
}

int IvoryTimelineIndex::begin_of(int layer) const { return starts_[(size_t)layer]; }
int IvoryTimelineIndex::end_of(int layer) const { return starts_[(size_t)layer + 1]; }

bool IvoryTimelineIndex::set_tracks(const PackedInt32Array &frames, const PackedInt32Array &starts) {
	frames_.clear();
	starts_.clear();
	end_ = -1;
	if (starts.size() < 2) return false;
	if (starts[0] != 0) return false;
	if (starts[starts.size() - 1] != frames.size()) return false;
	for (int i = 1; i < starts.size(); ++i) {
		if (starts[i] < starts[i - 1]) return false;
	}

	frames_.reserve(frames.size());
	for (int i = 0; i < frames.size(); ++i) frames_.push_back(frames[i]);
	starts_.reserve(starts.size());
	for (int i = 0; i < starts.size(); ++i) starts_.push_back(starts[i]);

	// Every layer's own list must be ascending. A binary search over an
	// unsorted list does not run slowly — it returns the wrong drawing, and
	// the band shows the wrong frame with no sign that anything is amiss. It
	// is worth one linear pass at build time to make that impossible.
	const int n = layer_count();
	for (int l = 0; l < n; ++l) {
		for (int i = begin_of(l) + 1; i < end_of(l); ++i) {
			if (frames_[(size_t)i] < frames_[(size_t)i - 1]) {
				frames_.clear();
				starts_.clear();
				return false;
			}
		}
		if (end_of(l) > begin_of(l)) end_ = std::max(end_, frames_[(size_t)end_of(l) - 1]);
	}
	return true;
}

int IvoryTimelineIndex::scene_end() const { return end_; }

// The latest frame at or before `at`, per layer.
//
// One binary search each, but all of them behind a single call. The playhead
// asks this on every rendered frame, and on a hundred-layer scene it was a
// hundred separate crossings of the script boundary sixty times a second.
PackedInt32Array IvoryTimelineIndex::showing_at(int at) const {
	PackedInt32Array out;
	const int n = layer_count();
	out.resize(n);
	for (int l = 0; l < n; ++l) {
		const int lo = begin_of(l), hi = end_of(l);
		if (hi <= lo) { out[l] = -1; continue; }
		// upper_bound, then step back one: the last entry <= at.
		const auto it = std::upper_bound(frames_.begin() + lo, frames_.begin() + hi, at);
		out[l] = (it == frames_.begin() + lo) ? -1 : *(it - 1);
	}
	return out;
}

int IvoryTimelineIndex::index_at_or_after(int layer, int at) const {
	const int n = layer_count();
	if (layer < 0 || layer >= n) return 0;
	const int lo = begin_of(layer), hi = end_of(layer);
	const auto it = std::lower_bound(frames_.begin() + lo, frames_.begin() + hi, at);
	return (int)(it - (frames_.begin() + lo));
}

PackedInt32Array IvoryTimelineIndex::segments(int layer, int lo, int hi) const {
	PackedInt32Array out;
	const int n = layer_count();
	if (layer < 0 || layer >= n || hi < lo) return out;
	const int a = begin_of(layer), b = end_of(layer);
	if (b <= a) return out;

	// One back from the first frame in the window: the drawing before the
	// window may still be held into it, and its bar has to be drawn or the
	// row appears to start blank.
	int i = a + index_at_or_after(layer, lo);
	if (i > a) --i;

	for (; i < b; ++i) {
		const int one = frames_[(size_t)i];
		if (one > hi) break;
		// The hold runs to the next drawing; past the last one it runs to the
		// end of the scene, because that is where the layer stops.
		const int next = (i + 1 < b) ? frames_[(size_t)i + 1] : (end_ + 1);
		const int held = std::max(next - one, 1);
		if (one + held < lo) continue;
		out.append(one);
		out.append(held);
	}
	return out;
}

Dictionary IvoryTimelineIndex::all_segments(int lo, int hi) const {
	Dictionary out;
	PackedInt32Array flat;
	PackedInt32Array starts;
	const int n = layer_count();
	starts.append(0);
	for (int l = 0; l < n; ++l) {
		PackedInt32Array one = segments(l, lo, hi);
		for (int i = 0; i < one.size(); ++i) flat.append(one[i]);
		starts.append(flat.size());
	}
	out["ok"] = true;
	out["segments"] = flat;
	out["starts"] = starts;
	out["layer_count"] = n;
	out["bars"] = flat.size() / 2;
	return out;
}

PackedInt32Array IvoryTimelineIndex::occupied(int lo, int hi) const {
	PackedInt32Array out;
	if (hi < lo) return out;
	// A bitmap over the window rather than a search per column. The window is
	// what fits on a screen — a few hundred columns — so this is a few hundred
	// bytes and one pass over the frames that fall inside it, instead of a
	// binary search per layer per column.
	std::vector<uint8_t> hit((size_t)(hi - lo + 1), 0);
	const int n = layer_count();
	for (int l = 0; l < n; ++l) {
		const int a = begin_of(l), b = end_of(l);
		for (int i = a + index_at_or_after(l, lo); i < b; ++i) {
			const int f = frames_[(size_t)i];
			if (f > hi) break;
			hit[(size_t)(f - lo)] = 1;
		}
	}
	for (int f = lo; f <= hi; ++f) {
		if (hit[(size_t)(f - lo)]) out.append(f);
	}
	return out;
}

int IvoryTimelineIndex::count_on(int frame) const {
	int n = 0;
	const int layers = layer_count();
	for (int l = 0; l < layers; ++l) {
		const int a = begin_of(l), b = end_of(l);
		if (b <= a) continue;
		if (std::binary_search(frames_.begin() + a, frames_.begin() + b, frame)) ++n;
	}
	return n;
}

} // namespace godot
