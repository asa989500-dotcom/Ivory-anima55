#ifndef IVORY_LAYOUT_H
#define IVORY_LAYOUT_H

// No two controls in the same place, ever.
//
// ## What goes wrong, and why it is not a layout bug
//
// Most of this app's controls are in containers, and containers do not
// overlap their children. The ones that collide are the ones that cannot be:
// floating panels placed under the button that opened them, tool rails that
// grow with the number of tools, the canvas overlay's own handles. Those are
// positioned by arithmetic, and arithmetic that was right on the screen it
// was written for is wrong on a screen four hundred pixels narrower.
//
// The failure is nastier than it looks. Two buttons overlapping by six pixels
// look fine — and the top one takes every touch in the shared strip, so the
// bottom one has a dead edge. Nobody reports "these overlap"; they report
// "sometimes this button doesn't work", which is a much harder thing to find.
//
// ## What this does
//
// Given a list of rectangles, it finds every overlapping pair and moves them
// apart along the axis where they overlap least. Repeatedly, because moving
// one apart can push it into a third.
//
// Two rules make the result predictable rather than merely non-overlapping:
//
//   * **Pinned rectangles never move.** A panel anchored under the button
//     that opened it must stay under it; if something else collides with it,
//     the something else moves. Without this, resolution shuffles the one
//     control whose position carries meaning.
//   * **Rectangles are moved along their smaller overlap.** Two buttons
//     overlapping by two pixels horizontally and forty vertically are a
//     horizontal problem, and pushing them apart vertically would move them
//     forty pixels for a two-pixel fault.
//
// ## Sweep and prune
//
// The naive check is every pair, which for the sixty or so controls on screen
// is under two thousand comparisons — fine. It is here anyway because the
// same routine is used on the tool rail while it is being dragged, once per
// frame, and because sorting by left edge and stopping the inner loop as soon
// as a rectangle starts beyond the current one's right edge turns the
// quadratic into something close to linear for the usual case, where controls
// are laid out in rows and almost nothing overlaps anything.
//
// ## The margin
//
// Separation is enforced with a gap, not to zero overlap. Two buttons exactly
// touching are still two buttons a fingertip cannot reliably choose between:
// a fingertip is around nine millimetres and lands with a spread of several
// pixels either way. The gap is what makes the boundary between two targets
// wide enough to miss.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvoryLayout : public RefCounted {
	GDCLASS(IvoryLayout, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryLayout() = default;
	~IvoryLayout() = default;

	// The controls to keep apart. `pinned` marks the ones that may not move;
	// it may be shorter than `boxes` or empty, and a box with no entry is
	// free to move.
	void set_boxes(const Array &boxes, const PackedInt32Array &pinned);

	// How much clear space to leave between two controls, in pixels.
	void set_margin(double margin);

	// How far outside `bounds` a control may end up. Passing an empty
	// rectangle turns the constraint off.
	void set_bounds(const Rect2 &bounds);

	// Pushes everything apart. Returns how many rectangles it had to move.
	int resolve(int rounds);

	Array boxes() const;
	Rect2 box(int index) const;

	// Every pair that still overlaps, as flat pairs of indices. Empty when
	// the layout is clean — which is what the test bench asserts, and what a
	// debug overlay can draw in red.
	PackedInt32Array collisions() const;

	// Whether any two overlap at all. Cheaper than building the list.
	bool tangled() const;

	// Which control a touch belongs to, or -1.
	//
	// Not simply the first rectangle containing the point. See the
	// implementation — a touch in the gap between two controls should go to
	// the nearer one rather than to nothing, and a touch inside two should go
	// to the one whose centre it is closest to rather than to whichever
	// happens to be first in the list.
	int touched(const Vector2 &at, double slop) const;

private:
	std::vector<Rect2> boxes_;
	std::vector<bool> pinned_;
	double margin_ = 6.0;
	Rect2 bounds_;
	bool bounded_ = false;

	bool overlaps(int a, int b) const;
	void hold_inside(int i);
};

} // namespace godot

#endif // IVORY_LAYOUT_H
