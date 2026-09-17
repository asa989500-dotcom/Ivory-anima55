#ifndef IVORY_COMIC_H
#define IVORY_COMIC_H

// Comic panels: the geometry of cutting a page into frames.
//
// ## What a panel is here
//
// A closed simple polygon in page coordinates, and nothing else. Not a
// rectangle — the moment a diagonal cut is allowed, a rectangle cannot
// describe the result, and a system that stores rectangles has to either
// forbid the diagonal or lie about where the edges are. Not a tree of splits
// either: a split tree remembers *how* a page was cut, which sounds useful
// and is the wrong thing to store, because it makes "nudge this one edge"
// impossible without re-deriving every cut that came after it.
//
// So: a flat list of polygons. Every operation takes polygons and returns
// polygons, and the history of how they got that way lives in the undo stack
// where history belongs.
//
// ## How a cut works
//
// **Sutherland–Hodgman half-plane clipping.** A straight cut is a line, a
// line divides the plane into two half-planes, and clipping a convex polygon
// against a half-plane is a single pass over its edges: keep the vertices on
// the near side, and wherever an edge crosses the line, insert the crossing
// point. Run it twice with the half-plane flipped and you have both halves.
//
// It is about fifteen lines, it has no special cases, and it is exact — the
// crossing point is solved for, not searched for, so two panels cut from one
// share their border to the last bit rather than to within a tolerance. That
// matters more than it sounds: panels that *nearly* share a border leave
// hairline gaps that show up in print and in nothing else.
//
// The classic limitation is that it is only correct for a convex *clip
// region*, which a half-plane always is. The polygon being clipped may be
// concave, and for a concave one the result can come back with a zero-width
// bridge joining two lobes. That is a real artefact and it is handled where
// it arises rather than pretended away — see `split_by_line`.
//
// ## The gutter
//
// The white channel between panels. Cutting produces two polygons sharing an
// edge; the gutter is made by insetting each of them by half the channel
// width, so the channel is centred on the cut and both panels give up the
// same amount. Insetting the *cut edge only* would put the whole channel on
// one side and the page would visibly drift as it was subdivided.
//
// Inset is done by offsetting each edge inward along its normal and
// re-intersecting consecutive edges — the standard straight-skeleton step for
// one iteration. For the shallow insets a gutter needs (a few units against
// panels hundreds across) that is exact and cannot self-intersect.
//
// ## What is deliberately not here
//
// Rasterisation of a panel to a mask lives here too (`mask_of`), because
// confining paint to a panel needs one, and a scanline fill of a polygon is
// the same arithmetic as everything else in this file. But nothing about
// *drawing* a panel is here — no strokes, no borders, no colour. This class
// answers questions about shapes.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvoryComic : public RefCounted {
	GDCLASS(IvoryComic, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryComic() = default;
	~IvoryComic() = default;

	// The five ways a page can be cut. `LINE` is the one that does the work;
	// the other four are closed shapes that take a bite out of a panel and
	// become a panel themselves.
	enum Cut {
		CUT_LINE,
		CUT_CIRCLE,
		CUT_SQUARE,
		CUT_RECT,
		CUT_FREE,
	};

	// --- the page ---

	// Hands over every panel. Each entry is a PackedVector2Array of points in
	// page coordinates, wound either way.
	void set_panels(const Array &polygons);
	Array panels() const;
	int panel_count() const { return (int)panels_.size(); }

	// One panel back, or an empty array.
	PackedVector2Array panel(int index) const;

	// The whole page as one panel, inset from its edges. This is the border
	// box everything starts as.
	PackedVector2Array page_frame(const Vector2 &page, double margin) const;

	// --- cutting ---

	// Cuts with a straight run from `a` to `b`.
	//
	// Only panels the segment actually crosses are touched, which is the
	// whole of "a cut need not go all the way across the page": draw a line
	// down the middle, then draw a shorter one across the left half only, and
	// the right half is not consulted.
	//
	// Returns how many panels were cut.
	int split_by_line(const Vector2 &a, const Vector2 &b, double gutter);

	// Cuts with a closed shape. The shape becomes its own panel and is
	// removed from whatever it overlapped.
	//
	// `points` is the shape for `CUT_FREE`; for the other three it is ignored
	// and `box` describes the shape — a circle inscribed in it, a square
	// centred in it, or the rectangle itself.
	int split_by_shape(int kind, const Rect2 &box,
			const PackedVector2Array &points, double gutter);

	// Puts the page back to one panel.
	void reset_to(const Vector2 &page, double margin);

	// --- asking ---

	// Which panel contains this point, topmost first, or -1.
	int panel_at(const Vector2 &at) const;

	// Which panel *edge* is near this point: `panel * 64 + edge`, or -1.
	// Used for dragging a border after the fact.
	int edge_at(const Vector2 &at, double reach) const;

	Rect2 bounds_of(int index) const;
	double area_of(int index) const;

	// One byte per pixel over `rect`, 255 inside the panel and 0 outside.
	// This is what confines paint to a panel.
	PackedByteArray mask_of(int index, const Rect2i &rect) const;

	// Whether a point is inside a panel, without building a mask. The hot
	// path when a brush asks "may I put a dab here".
	bool inside(int index, const Vector2 &at) const;

	// --- a cutting session ---
	//
	// ## Why cutting needs a beginning and an end
	//
	// Once the cut mode is entered there is no way out of it that does not
	// involve guessing: the person draws a line, the page is divided, they
	// draw another, and nothing in the app ever says *that is the layout*.
	// The mode is left by picking up some other tool, which is leaving by
	// accident rather than finishing.
	//
	// So a session is opened before the first cut and closed by a button
	// that says so. Three things follow that could not be done without it.
	//
	// **It can be abandoned.** The panels as they stood when the session
	// opened are kept, so one press puts the page back — rather than as
	// many undo steps as there were cuts, each of which has to be counted.
	//
	// **It can be tidied at the end.** Repeated cutting leaves slivers:
	// panels a few units across, made where two cuts nearly met, too small
	// to draw in and easy to miss on a phone. They are cleared once, on
	// finishing, rather than after every cut — clearing after every cut
	// would delete a panel that the *next* cut was about to make useful.
	//
	// **And finishing is a decision with a report.** How many panels, how
	// many cuts, what was tidied away. A person who has just divided a page
	// eleven times cannot count what they got by looking at it.

	// Opens a session, remembering the panels as they stand.
	void begin_cutting();
	bool cutting() const { return cutting_; }
	int session_cuts() const { return session_cuts_; }

	// Closes it. `min_area` is the size below which a panel is a sliver and
	// is cleared away; pass nought to keep everything.
	Dictionary finish_cutting(double min_area);

	// Closes it and puts the page back to how it was.
	Dictionary abandon_cutting();

	// Clears away panels smaller than `min_area`, and panels so thin they
	// cannot be drawn in whatever their area. Returns how many went.
	//
	// Thinness is measured as area over the square of the perimeter — the
	// standard compactness ratio, which is large for a square and near
	// nought for a splinter. A pure area test keeps a panel four hundred
	// units long and two wide, and nobody can draw in that either.
	int tidy(double min_area, double min_compactness);

	// --- shared helpers, exposed because the tests want them ---

	static PackedVector2Array clip_half(const PackedVector2Array &poly,
			const Vector2 &a, const Vector2 &b, bool keep_left);
	static PackedVector2Array inset(const PackedVector2Array &poly,
			double by);
	static double signed_area(const PackedVector2Array &poly);
	static PackedVector2Array circle_in(const Rect2 &box, int steps);

private:
	std::vector<std::vector<Vector2>> panels_;
	std::vector<std::vector<Vector2>> before_;
	bool cutting_ = false;
	int session_cuts_ = 0;

	static double perimeter_of(const std::vector<Vector2> &poly);

	static std::vector<Vector2> to_vec(const PackedVector2Array &in);
	static PackedVector2Array to_packed(const std::vector<Vector2> &in);
	// Whether the segment a-b passes through this polygon's interior.
	static bool segment_cuts(const std::vector<Vector2> &poly,
			const Vector2 &a, const Vector2 &b);
	static bool point_in(const std::vector<Vector2> &poly, const Vector2 &at);
	static double area_of_vec(const std::vector<Vector2> &poly);
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryComic::Cut);

#endif // IVORY_COMIC_H
