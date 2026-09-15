#ifndef IVORY_TIMELINE_H
#define IVORY_TIMELINE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <vector>

namespace godot {

// Every question the timeline band asks, answered for all layers at once.
//
// ## Where the time was going
//
// Not where it looked. `CelTrack` is already careful — its frame list is kept
// sorted, "which drawing is showing" is a binary search, and the band already
// skips drawings outside the visible window. Each of those is fast.
//
// The cost was that they are asked *per layer, from GDScript, every redraw*.
// A hundred-layer scene redrawing at sixty frames a second makes six thousand
// bound calls a second before anything is drawn, and every one of them crosses
// the script boundary, boxes its arguments into Variants and unboxes its
// result. The work inside each call is a handful of comparisons; the call
// itself costs more than the work.
//
// So this class takes every layer's frame list once, in one flat array, and
// answers the same questions for all of them in a single call. A hundred
// layers becomes one crossing instead of a hundred.
//
// ## The layout
//
// Compressed sparse row, the same shape a sparse matrix uses. `frames` holds
// every layer's sorted frame numbers end to end; `starts` says where each
// layer's run begins, with one extra entry at the end so the last layer's
// length is a subtraction like everyone else's. No array of arrays, no
// allocation per layer, and the whole index is two blocks of memory that fit
// in cache.
class IvoryTimelineIndex : public RefCounted {
	GDCLASS(IvoryTimelineIndex, RefCounted)

protected:
	static void _bind_methods();

public:
	// `frames` is every layer's sorted frame list end to end. `starts` has
	// layer_count + 1 entries: layer i occupies frames[starts[i]..starts[i+1]).
	//
	// Refused if `starts` is not ascending or runs off the end of `frames`, or
	// if any layer's own list is not sorted — a binary search over an unsorted
	// list returns a wrong answer rather than a slow one, which is far worse.
	bool set_tracks(const PackedInt32Array &frames, const PackedInt32Array &starts);

	int layer_count() const { return (int)starts_.empty() ? 0 : (int)starts_.size() - 1; }
	int total_frames() const { return (int)frames_.size(); }

	// Which drawing each layer is showing at this moment: the latest frame at
	// or before `at`, or -1 where the layer has nothing yet. One entry per
	// layer, in layer order.
	//
	// This is the call the playhead makes on every single rendered frame.
	PackedInt32Array showing_at(int at) const;

	// The last frame anything is drawn on, or -1 for an empty scene. The band
	// asks this every redraw to know where to stop the row lines.
	int scene_end() const;

	// The bars to draw for one layer inside a window: pairs of (frame, held),
	// where held is how long that drawing stays up. Only the bars that reach
	// the window are returned.
	PackedInt32Array segments(int layer, int lo, int hi) const;

	// The same for every layer at once, flattened, with a `starts` array
	// alongside so the caller can walk it the same way it walks the input.
	// Returns {ok, segments, starts, layer_count, bars}.
	Dictionary all_segments(int lo, int hi) const;

	// Which frames in a window have a drawing on any layer at all. What the
	// ruler shades, and previously a loop over every layer for every column.
	PackedInt32Array occupied(int lo, int hi) const;

	// How many layers have a drawing exactly on this frame.
	int count_on(int frame) const;

	// The index of the first frame at or after `at` in one layer's list, or
	// the list's length. The band's starting point for a windowed walk.
	int index_at_or_after(int layer, int at) const;

private:
	int begin_of(int layer) const;
	int end_of(int layer) const;

	std::vector<int> frames_;
	std::vector<int> starts_;
	int end_ = -1;
};

} // namespace godot
#endif
