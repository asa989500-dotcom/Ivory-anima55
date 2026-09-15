#ifndef IVORY_FIELD_H
#define IVORY_FIELD_H

// The canvas with no edges.
//
// ## What "infinite" has to mean to be useful
//
// Not "very large". A very large canvas is a fixed one with the limit moved,
// and it costs its whole area in memory whether anything is drawn on it or
// not. Somebody working in the top-left corner of a hundred-thousand-pixel
// square is paying for the other ninety-nine percent of it.
//
// Infinite means **addressed rather than allocated**. The plane is divided
// into tiles on a lattice indexed by whole numbers, the index is a 64-bit
// integer, and a tile exists only once something is drawn on it. There is no
// origin corner and no far corner. Drawing a mile to the left of where you
// started costs one tile, not a mile of tiles.
//
// The practical limit is then the addressable range, which at 256-pixel tiles
// and a signed 64-bit index is a canvas some two thousand million million
// pixels across. It is not literally infinite and saying so would be a lie;
// it is far enough that no drawing will reach the end of it, which is what
// was actually wanted.
//
// ## The part that was going wrong
//
// A tool anchored to the canvas must not move when the *view* moves. That
// sounds automatic and it is not, because of how the round trip is usually
// written:
//
//     canvas = (screen - pan) / zoom
//
// Every pan and every pinch recomputes it, in single precision, from numbers
// that are getting larger as the view travels. Far from the origin the
// difference `screen - pan` is a small number made by subtracting two large
// ones, which is where floating point loses most of its digits. The canvas
// position wobbles in the last places, and anything that reads it — the
// blend2's jitter seed, a pin's slot, a stamp's phase — wobbles with it. That
// is the shiver.
//
// Two things fix it here.
//
// **The arithmetic is done in double** and only the result is narrowed. A
// double has enough digits left after that subtraction to be exact over the
// whole addressable range.
//
// **And anything a tool remembers is quantised** before it is remembered.
// `anchor` snaps a canvas position to a lattice, so a position that does
// wobble in its last bits still lands on the same anchor, and a tool seeded
// from that anchor cannot re-roll. The lattice is coarse enough to absorb any
// plausible error and fine enough that two distinct marks get distinct
// anchors.
//
// ## Tiles, and what to throw away
//
// A session can touch more tiles than a phone can hold. Which to keep is a
// cache question and the answer is the ordinary one: keep what is on screen,
// then keep what was used most recently. What makes it worth writing down is
// the **ring**: tiles just outside the view are kept too, because the alternative
// is that every small pan throws away tiles that are about to be needed
// again, and the drawing flickers as they are rebuilt.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <map>
#include <vector>

namespace godot {

class IvoryField : public RefCounted {
	GDCLASS(IvoryField, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryField();
	~IvoryField() = default;

	// --- the lattice ---

	void set_tile(int px);
	int tile() const { return tile_; }

	// Which tile a canvas position falls in. Whole numbers, signed, so there
	// is no origin corner and negative coordinates are ordinary.
	Vector2i tile_of(const Vector2 &canvas) const;
	Rect2 tile_rect(const Vector2i &at) const;

	// Every tile a rectangle touches, as pairs of whole numbers. Capped, and
	// the cap is reported rather than silently applied: a caller asking for
	// a million tiles has a bug and should be told, not quietly given four
	// thousand.
	Dictionary tiles_in(const Rect2 &canvas_rect, int cap) const;

	// --- the view ---

	void set_view(const Vector2 &pan, double zoom, const Vector2 &screen_size);
	Vector2 pan() const { return Vector2((real_t)pan_x_, (real_t)pan_y_); }
	double zoom() const { return zoom_; }

	// Screen to canvas and back, in double. See the header — this is where
	// the shiver came from.
	Vector2 to_canvas(const Vector2 &screen) const;
	Vector2 to_screen(const Vector2 &canvas) const;
	Rect2 visible() const;

	// A canvas position snapped to the anchor lattice. Anything a tool wants
	// to remember across a redraw goes through here first.
	Vector2 anchor(const Vector2 &canvas) const;
	void set_anchor_grid(double px);
	double anchor_grid() const { return anchor_grid_; }

	// --- what has been drawn on ---

	// Widens the drawn area to take in a rectangle. This is how the canvas
	// grows: nothing is allocated, a bound is moved.
	void note(const Rect2 &canvas_rect);
	void note_point(const Vector2 &canvas);
	bool anything_drawn() const { return drawn_; }
	Rect2 content() const;
	void forget_content();

	// --- keeping tiles ---

	// Says a tile was used at `now`.
	void touch_tile(const Vector2i &at, double now);
	int live_tiles() const { return (int)seen_.size(); }
	// Which tiles to let go of, given a budget. On-screen tiles and the ring
	// just outside it are never chosen, whatever the budget says: throwing
	// away a tile that is about to be drawn is how a pan starts to flicker.
	PackedVector2Array evictions(int budget, int ring) const;
	void drop_tile(const Vector2i &at);

	// Roughly what the live tiles cost, in bytes, at four bytes a pixel.
	int64_t working_bytes() const;

	// A plain reading of where the view is and what it covers, for the
	// status line and for the tests.
	Dictionary report() const;

private:
	int tile_ = 256;
	double pan_x_ = 0.0;
	double pan_y_ = 0.0;
	double zoom_ = 1.0;
	double screen_w_ = 0.0;
	double screen_h_ = 0.0;
	double anchor_grid_ = 4.0;

	bool drawn_ = false;
	double x0_ = 0.0, y0_ = 0.0, x1_ = 0.0, y1_ = 0.0;

	std::map<int64_t, double> seen_;

	static int64_t key_of(int64_t x, int64_t y);
	static Vector2i from_key(int64_t key);
};

} // namespace godot

#endif // IVORY_FIELD_H
