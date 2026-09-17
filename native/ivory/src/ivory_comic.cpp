#include "ivory_comic.h"
#include <godot_cpp/core/math_defs.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// The smallest panel worth keeping, in square page units. A cut that shaves a
// sliver off a corner produces a panel nobody can draw in and nobody asked
// for; below this it is discarded rather than kept and immediately deleted by
// hand. Chosen at roughly a twelve-unit square, which at any sensible page
// size is smaller than the gutter.
static const double LEAST_AREA = 144.0;

void IvoryComic::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_panels", "polygons"),
			&IvoryComic::set_panels);
	ClassDB::bind_method(D_METHOD("panels"), &IvoryComic::panels);
	ClassDB::bind_method(D_METHOD("panel_count"), &IvoryComic::panel_count);
	ClassDB::bind_method(D_METHOD("panel", "index"), &IvoryComic::panel);
	ClassDB::bind_method(D_METHOD("page_frame", "page", "margin"),
			&IvoryComic::page_frame);
	ClassDB::bind_method(D_METHOD("split_by_line", "a", "b", "gutter"),
			&IvoryComic::split_by_line);
	ClassDB::bind_method(D_METHOD("split_by_shape", "kind", "box", "points",
			"gutter"), &IvoryComic::split_by_shape);
	ClassDB::bind_method(D_METHOD("reset_to", "page", "margin"),
			&IvoryComic::reset_to);
	ClassDB::bind_method(D_METHOD("panel_at", "at"), &IvoryComic::panel_at);
	ClassDB::bind_method(D_METHOD("edge_at", "at", "reach"),
			&IvoryComic::edge_at);
	ClassDB::bind_method(D_METHOD("bounds_of", "index"),
			&IvoryComic::bounds_of);
	ClassDB::bind_method(D_METHOD("area_of", "index"), &IvoryComic::area_of);
	ClassDB::bind_method(D_METHOD("mask_of", "index", "rect"),
			&IvoryComic::mask_of);
	ClassDB::bind_method(D_METHOD("inside", "index", "at"),
			&IvoryComic::inside);

	ClassDB::bind_static_method("IvoryComic",
			D_METHOD("clip_half", "poly", "a", "b", "keep_left"),
			&IvoryComic::clip_half);
	ClassDB::bind_static_method("IvoryComic", D_METHOD("inset", "poly", "by"),
			&IvoryComic::inset);
	ClassDB::bind_static_method("IvoryComic", D_METHOD("signed_area", "poly"),
			&IvoryComic::signed_area);
	ClassDB::bind_static_method("IvoryComic",
			D_METHOD("circle_in", "box", "steps"), &IvoryComic::circle_in);

	ClassDB::bind_method(D_METHOD("begin_cutting"), &IvoryComic::begin_cutting);
	ClassDB::bind_method(D_METHOD("cutting"), &IvoryComic::cutting);
	ClassDB::bind_method(D_METHOD("session_cuts"), &IvoryComic::session_cuts);
	ClassDB::bind_method(D_METHOD("finish_cutting", "min_area"),
			&IvoryComic::finish_cutting);
	ClassDB::bind_method(D_METHOD("abandon_cutting"),
			&IvoryComic::abandon_cutting);
	ClassDB::bind_method(D_METHOD("tidy", "min_area", "min_compactness"),
			&IvoryComic::tidy);

	BIND_ENUM_CONSTANT(CUT_LINE);
	BIND_ENUM_CONSTANT(CUT_CIRCLE);
	BIND_ENUM_CONSTANT(CUT_SQUARE);
	BIND_ENUM_CONSTANT(CUT_RECT);
	BIND_ENUM_CONSTANT(CUT_FREE);
}

// ------------------------------------------------------------- conversions

std::vector<Vector2> IvoryComic::to_vec(const PackedVector2Array &in) {
	std::vector<Vector2> out;
	out.reserve(in.size());
	for (int i = 0; i < in.size(); i++) {
		out.push_back(in[i]);
	}
	return out;
}

PackedVector2Array IvoryComic::to_packed(const std::vector<Vector2> &in) {
	PackedVector2Array out;
	out.resize((int)in.size());
	for (int i = 0; i < (int)in.size(); i++) {
		out[i] = in[i];
	}
	return out;
}

// ------------------------------------------------------------------ basics

double IvoryComic::area_of_vec(const std::vector<Vector2> &poly) {
	// The shoelace formula. Signed, so the sign is the winding and the
	// magnitude is the area — both wanted, and both from one loop.
	const int n = (int)poly.size();
	if (n < 3) {
		return 0.0;
	}
	double sum = 0.0;
	for (int i = 0; i < n; i++) {
		const Vector2 &p = poly[i];
		const Vector2 &q = poly[(i + 1) % n];
		sum += (double)p.x * (double)q.y - (double)q.x * (double)p.y;
	}
	return sum * 0.5;
}

double IvoryComic::signed_area(const PackedVector2Array &poly) {
	return area_of_vec(to_vec(poly));
}

bool IvoryComic::point_in(const std::vector<Vector2> &poly,
		const Vector2 &at) {
	// Crossing number. A ray is cast to the right and the edges it crosses
	// are counted; odd means inside. The `(p.y > at.y) != (q.y > at.y)` test
	// is the standard way of counting each edge exactly once regardless of
	// which way it runs, and of not counting an edge that merely touches the
	// ray's height — which is what makes it correct at a vertex.
	const int n = (int)poly.size();
	if (n < 3) {
		return false;
	}
	bool in = false;
	for (int i = 0, j = n - 1; i < n; j = i++) {
		const Vector2 &p = poly[i];
		const Vector2 &q = poly[j];
		if (((double)p.y > (double)at.y) != ((double)q.y > (double)at.y)) {
			const double t = ((double)at.y - (double)p.y)
					/ ((double)q.y - (double)p.y);
			const double x = (double)p.x + t * ((double)q.x - (double)p.x);
			if ((double)at.x < x) {
				in = !in;
			}
		}
	}
	return in;
}

// ----------------------------------------------------------- half-plane cut

PackedVector2Array IvoryComic::clip_half(const PackedVector2Array &poly,
		const Vector2 &a, const Vector2 &b, bool keep_left) {
	// Sutherland–Hodgman against one half-plane.
	//
	// Walk the edges. For each, look at which side its two ends are on:
	//
	//   in  -> in    keep the end
	//   in  -> out   keep the crossing
	//   out -> in    keep the crossing, then the end
	//   out -> out   keep nothing
	//
	// That is the whole algorithm. No sorting, no intersection list, no
	// special case for a vertex exactly on the line — a vertex on the line
	// has `side == 0`, counts as inside, and its crossing is itself.
	const std::vector<Vector2> in = to_vec(poly);
	std::vector<Vector2> out;
	const int n = (int)in.size();
	if (n < 3) {
		return PackedVector2Array();
	}
	const Vector2 run = b - a;
	if (run.length_squared() < 1.0e-12) {
		return poly;
	}
	// The cross product's sign is which side of the line a point is on. The
	// magnitude is proportional to the distance, which is why it can be used
	// directly for the interpolation below without normalising anything.
	auto side = [&](const Vector2 &p) -> double {
		const double s = (double)run.x * ((double)p.y - (double)a.y)
				- (double)run.y * ((double)p.x - (double)a.x);
		return keep_left ? s : -s;
	};

	out.reserve(n + 4);
	for (int i = 0; i < n; i++) {
		const Vector2 &p = in[i];
		const Vector2 &q = in[(i + 1) % n];
		const double sp = side(p);
		const double sq = side(q);
		const bool p_in = sp >= 0.0;
		const bool q_in = sq >= 0.0;
		if (p_in) {
			out.push_back(p);
		}
		if (p_in != q_in) {
			// Where the edge meets the line. Solved from the two side
			// values, which are already proportional to the distances, so
			// this is exact and needs no second projection.
			const double t = sp / (sp - sq);
			out.push_back(Vector2(
					(real_t)((double)p.x + t * ((double)q.x - (double)p.x)),
					(real_t)((double)p.y + t * ((double)q.y - (double)p.y))));
		}
	}

	// Consecutive duplicates, which arise whenever a vertex sat exactly on
	// the line: it is emitted once as an inside vertex and once as its own
	// crossing. Harmless to leave in for area and containment, and not
	// harmless at all for insetting, which divides by edge length.
	std::vector<Vector2> tidy;
	tidy.reserve(out.size());
	for (size_t i = 0; i < out.size(); i++) {
		const Vector2 &p = out[i];
		if (!tidy.empty() && (p - tidy.back()).length_squared() < 1.0e-10) {
			continue;
		}
		tidy.push_back(p);
	}
	if (tidy.size() > 1
			&& (tidy.front() - tidy.back()).length_squared() < 1.0e-10) {
		tidy.pop_back();
	}
	if (tidy.size() < 3) {
		return PackedVector2Array();
	}
	return to_packed(tidy);
}

// ------------------------------------------------------------------- inset

PackedVector2Array IvoryComic::inset(const PackedVector2Array &poly,
		double by) {
	const std::vector<Vector2> in = to_vec(poly);
	const int n = (int)in.size();
	if (n < 3 || by <= 0.0) {
		return poly;
	}
	// Which way "inward" is depends on the winding, and a polygon that came
	// out of a clip can be wound either way. Read it from the signed area
	// rather than assumed — assuming it is how an inset becomes an outset on
	// half the panels on a page.
	const double turn = area_of_vec(in) > 0.0 ? 1.0 : -1.0;

	std::vector<Vector2> out;
	out.reserve(n);
	for (int i = 0; i < n; i++) {
		const Vector2 &prev = in[(i + n - 1) % n];
		const Vector2 &here = in[i];
		const Vector2 &next = in[(i + 1) % n];

		// Each of the two edges meeting at this vertex is pushed inward along
		// its own normal, and the vertex moves to where the two pushed edges
		// now cross. That is the correct answer for a straight skeleton step
		// and it is what keeps the corner sharp — averaging the two normals
		// instead, which is the tempting shortcut, rounds every corner in by
		// a factor of the cosine of half its angle and visibly bevels the
		// tight ones.
		Vector2 e1 = here - prev;
		Vector2 e2 = next - here;
		const double l1 = (double)e1.length();
		const double l2 = (double)e2.length();
		if (l1 < 1.0e-9 || l2 < 1.0e-9) {
			out.push_back(here);
			continue;
		}
		e1 /= (real_t)l1;
		e2 /= (real_t)l2;
		const Vector2 n1((real_t)(-e1.y * turn), (real_t)(e1.x * turn));
		const Vector2 n2((real_t)(-e2.y * turn), (real_t)(e2.x * turn));

		const Vector2 p1 = here + n1 * (real_t)by;
		const Vector2 p2 = here + n2 * (real_t)by;
		const double denom = (double)e1.x * (double)e2.y
				- (double)e1.y * (double)e2.x;
		if (std::fabs(denom) < 1.0e-9) {
			// The two edges are parallel: a straight run through a redundant
			// vertex. Both offsets are the same line, so either point will
			// do.
			out.push_back(p1);
			continue;
		}
		const double dx = (double)p2.x - (double)p1.x;
		const double dy = (double)p2.y - (double)p1.y;
		const double t = (dx * (double)e2.y - dy * (double)e2.x) / denom;
		out.push_back(Vector2((real_t)((double)p1.x + (double)e1.x * t),
				(real_t)((double)p1.y + (double)e1.y * t)));
	}

	// --- has the inset turned the polygon inside out? ---
	//
	// The tempting test is the sign of the area, on the reasoning that a
	// polygon folded through itself winds the other way. **That is false**,
	// and the test bench caught it: inset a 100x100 square by 60 and the
	// result runs from (60,60) to (40,40) — inverted on *both* axes, and
	// inverting both axes preserves the winding exactly. The area comes back
	// positive, four hundred square units of a square that does not exist.
	//
	// So the test is containment instead, which is the property actually
	// wanted: every vertex of an inset polygon must lie inside the polygon it
	// came from. That catches the double inversion above, catches a single
	// axis collapsing, and catches a concave corner shooting off to infinity
	// — all three, with one loop over a handful of points.
	const double was = area_of_vec(in);
	const double now = area_of_vec(out);
	if (now * was <= 0.0 || std::fabs(now) >= std::fabs(was)
			|| std::fabs(now) < LEAST_AREA) {
		return PackedVector2Array();
	}
	for (size_t i = 0; i < out.size(); i++) {
		if (!point_in(in, out[i])) {
			return PackedVector2Array();
		}
	}

	// --- and has any edge turned round? ---
	//
	// Containment is still not enough, which the bench also caught. Inset a
	// square by more than half and the result is a smaller square *inside*
	// the original, wound the same way, every vertex contained, smaller in
	// area — passing all three tests above and describing a shape that does
	// not exist. It is the original turned inside out through its own middle.
	//
	// What actually happened to it is visible one level down: **every edge
	// reversed direction.** The top edge ran left to right and now runs right
	// to left. That is the definitive test for an over-inset and it is one
	// dot product per edge: an inset edge is parallel to the edge it came
	// from, so it either points the same way or the inset has passed through
	// it.
	const int m = (int)out.size();
	for (int i = 0; i < m && i < n; i++) {
		const Vector2 was_dir = in[(i + 1) % n] - in[i];
		const Vector2 now_dir = out[(i + 1) % m] - out[i];
		if ((double)was_dir.x * (double)now_dir.x
				+ (double)was_dir.y * (double)now_dir.y < 0.0) {
			return PackedVector2Array();
		}
	}
	return to_packed(out);
}

// -------------------------------------------------------------- the panels

void IvoryComic::set_panels(const Array &polygons) {
	panels_.clear();
	for (int i = 0; i < polygons.size(); i++) {
		const PackedVector2Array one = polygons[i];
		if (one.size() < 3) {
			continue;
		}
		panels_.push_back(to_vec(one));
	}
}

Array IvoryComic::panels() const {
	Array out;
	for (size_t i = 0; i < panels_.size(); i++) {
		out.append(to_packed(panels_[i]));
	}
	return out;
}

PackedVector2Array IvoryComic::panel(int index) const {
	if (index < 0 || index >= (int)panels_.size()) {
		return PackedVector2Array();
	}
	return to_packed(panels_[index]);
}

PackedVector2Array IvoryComic::page_frame(const Vector2 &page,
		double margin) const {
	const double m = std::max(margin, 0.0);
	const double w = std::max((double)page.x - m * 2.0, 8.0);
	const double h = std::max((double)page.y - m * 2.0, 8.0);
	PackedVector2Array out;
	out.resize(4);
	// Clockwise in screen coordinates, where y runs down. Consistent winding
	// everywhere means `inset` never has to guess.
	out[0] = Vector2((real_t)m, (real_t)m);
	out[1] = Vector2((real_t)(m + w), (real_t)m);
	out[2] = Vector2((real_t)(m + w), (real_t)(m + h));
	out[3] = Vector2((real_t)m, (real_t)(m + h));
	return out;
}

void IvoryComic::reset_to(const Vector2 &page, double margin) {
	panels_.clear();
	panels_.push_back(to_vec(page_frame(page, margin)));
}

// --------------------------------------------------------- does it cut this

bool IvoryComic::segment_cuts(const std::vector<Vector2> &poly,
		const Vector2 &a, const Vector2 &b) {
	// --- which panels a cut applies to ---
	//
	// The cut *line* is infinite — clipping is against a half-plane, and a
	// half-plane has no ends. The cut *gesture* is a finger dragged from one
	// place to another, which does have ends. This function is where those
	// two meet, and the rule it chooses is the whole of "you do not have to
	// cut all the way across".
	//
	// The first attempt demanded two boundary crossings: the segment had to
	// enter and leave. That is what "the segment divides this polygon" means
	// literally, and it made the feature useless — drag halfway across the
	// left half of a page and *nothing happens*, because the finger stopped
	// inside and never came out. Which is exactly the gesture somebody makes
	// when they mean "split this panel here".
	//
	// So a panel is cut when the gesture **touches** it: either end inside
	// it, or two crossings of its boundary. A finger that stops inside a
	// panel has said which panel it meant, and the line does the rest. A
	// panel the finger never reached is left alone, which is the half of the
	// rule that matters — see `test_cut_is_local`.
	const int n = (int)poly.size();
	if (n < 3) {
		return false;
	}
	if (point_in(poly, a) || point_in(poly, b)) {
		return true;
	}
	int crossings = 0;
	const Vector2 r = b - a;
	for (int i = 0; i < n; i++) {
		const Vector2 &p = poly[i];
		const Vector2 &q = poly[(i + 1) % n];
		const Vector2 s = q - p;
		const double denom = (double)r.x * (double)s.y
				- (double)r.y * (double)s.x;
		if (std::fabs(denom) < 1.0e-12) {
			continue;
		}
		const Vector2 gap = p - a;
		const double t = ((double)gap.x * (double)s.y
				- (double)gap.y * (double)s.x) / denom;
		const double u = ((double)gap.x * (double)r.y
				- (double)gap.y * (double)r.x) / denom;
		if (t >= 0.0 && t <= 1.0 && u >= 0.0 && u <= 1.0) {
			crossings++;
		}
	}
	return crossings >= 2;
}

int IvoryComic::split_by_line(const Vector2 &a, const Vector2 &b,
		double gutter) {
	if ((b - a).length_squared() < 1.0e-9) {
		return 0;
	}
	const double half = std::max(gutter, 0.0) * 0.5;
	std::vector<std::vector<Vector2>> next;
	int cut = 0;
	for (size_t i = 0; i < panels_.size(); i++) {
		const std::vector<Vector2> &one = panels_[i];
		if (!segment_cuts(one, a, b)) {
			// Untouched. This is the whole of "a cut need not cross the whole
			// page": draw a line down the middle, then a shorter one across
			// the left half, and the right half is simply not a panel the
			// second segment goes through.
			next.push_back(one);
			continue;
		}
		const PackedVector2Array packed = to_packed(one);
		PackedVector2Array left = clip_half(packed, a, b, true);
		PackedVector2Array right = clip_half(packed, a, b, false);
		if (half > 0.0) {
			left = inset(left, half);
			right = inset(right, half);
		}
		const bool ok_l = left.size() >= 3
				&& std::fabs(signed_area(left)) >= LEAST_AREA;
		const bool ok_r = right.size() >= 3
				&& std::fabs(signed_area(right)) >= LEAST_AREA;
		if (!ok_l && !ok_r) {
			// The cut would have destroyed the panel. Left alone rather than
			// deleted — somebody who grazed a corner meant to miss.
			next.push_back(one);
			continue;
		}
		if (ok_l) {
			next.push_back(to_vec(left));
		}
		if (ok_r) {
			next.push_back(to_vec(right));
		}
		if (ok_l && ok_r) {
			cut++;
		} else {
			// Only one side survived, so nothing was divided — but the
			// surviving side has been inset, and that is a change worth
			// reporting so the caller records it.
			cut++;
		}
	}
	panels_ = next;
	// A session counts cuts that actually did something. A line drawn across
	// empty page divides nothing, and counting it would tell the person at
	// the end that they made a cut they did not.
	if (cutting_ && cut > 0) {
		++session_cuts_;
	}
	return cut;
}

PackedVector2Array IvoryComic::circle_in(const Rect2 &box, int steps) {
	const int n = std::min(std::max(steps, 8), 128);
	const double cx = (double)box.position.x + (double)box.size.x * 0.5;
	const double cy = (double)box.position.y + (double)box.size.y * 0.5;
	const double rx = (double)box.size.x * 0.5;
	const double ry = (double)box.size.y * 0.5;
	PackedVector2Array out;
	out.resize(n);
	for (int i = 0; i < n; i++) {
		// Clockwise, matching `page_frame`, so every polygon in the system
		// winds the same way and `inset` never has to guess.
		const double t = (double)i / (double)n * TAU;
		out[i] = Vector2((real_t)(cx + std::cos(t) * rx),
				(real_t)(cy + std::sin(t) * ry));
	}
	return out;
}

int IvoryComic::split_by_shape(int kind, const Rect2 &box,
		const PackedVector2Array &points, double gutter) {
	// The shape, as a polygon.
	PackedVector2Array shape;
	switch (kind) {
		case CUT_CIRCLE:
			shape = circle_in(box, 48);
			break;
		case CUT_SQUARE: {
			// A square centred in the box, sized to its shorter side.
			const double s = std::min((double)box.size.x, (double)box.size.y);
			const double cx = (double)box.position.x
					+ (double)box.size.x * 0.5;
			const double cy = (double)box.position.y
					+ (double)box.size.y * 0.5;
			shape = page_frame(Vector2((real_t)s, (real_t)s), 0.0);
			for (int i = 0; i < shape.size(); i++) {
				shape[i] = shape[i] + Vector2((real_t)(cx - s * 0.5),
						(real_t)(cy - s * 0.5));
			}
			break;
		}
		case CUT_RECT: {
			shape = page_frame(box.size, 0.0);
			for (int i = 0; i < shape.size(); i++) {
				shape[i] = shape[i] + box.position;
			}
			break;
		}
		case CUT_FREE:
			return 0; // Free-form is deliberately not an exposed comic cutter.
		default:
			return 0;
	}
	if (shape.size() < 3) {
		return 0;
	}
	const std::vector<Vector2> cutter = to_vec(shape);
	const double half = std::max(gutter, 0.0) * 0.5;

	// The shape's own panel: the shape clipped to whatever it landed on, so a
	// circle hanging half off a panel becomes a half circle rather than a
	// floating disc over the gutter.
	std::vector<std::vector<Vector2>> next;
	std::vector<std::vector<Vector2>> made;
	int touched = 0;
	Rect2 cut_box(cutter[0], Vector2());
	for (size_t k = 1; k < cutter.size(); k++) cut_box = cut_box.expand(cutter[k]);

	for (size_t i = 0; i < panels_.size(); i++) {
		const std::vector<Vector2> &one = panels_[i];
		// Cheap rejection first: no overlap of bounding boxes means no work.
		// On a page of thirty panels this is nearly all of them.
		Rect2 host_box(one[0], Vector2());
		for (size_t k = 1; k < one.size(); k++) {
			host_box = host_box.expand(one[k]);
		}
		if (!host_box.intersects(cut_box)) {
			next.push_back(one);
			continue;
		}

		// --- the piece of the host inside the shape ---
		//
		// The panel clipped against every edge of the shape in turn. That is
		// Sutherland–Hodgman used for what it is actually for: the *clipper*
		// is one half-plane at a time and a half-plane is always convex, so
		// this is correct even when the shape as a whole is not.
		//
		// `keep_left` is true because every polygon in this file winds the
		// same way — see `page_frame` and `circle_in` — and for that winding
		// the interior is on the left of each edge. Getting this backwards
		// was a real bug and it did not look like one: the clip succeeded,
		// returned the panel almost unchanged, and the cut silently did
		// nothing. The test bench caught it by checking the *area* of the
		// resulting panel against the area of the circle asked for.
		PackedVector2Array inner = to_packed(one);
		for (size_t e = 0; e < cutter.size() && inner.size() >= 3; e++) {
			const Vector2 &p = cutter[e];
			const Vector2 &q = cutter[(e + 1) % cutter.size()];
			inner = clip_half(inner, p, q, true);
		}
		if (inner.size() < 3
				|| std::fabs(signed_area(inner)) < LEAST_AREA) {
			next.push_back(one);
			continue;
		}

		// --- what is left of the host ---
		//
		// ## Why this is not simply "the host minus the shape"
		//
		// Because that is not always a polygon. A shape landing in the middle
		// of a panel leaves a ring, and a ring has a hole in it — it cannot
		// be written as one closed loop of points, which is the only thing
		// this file stores. Representing holes would mean carrying a winding
		// rule through every clip, every inset, every mask and every hit
		// test, to support a comic layout nobody draws.
		//
		// So the remainder is cut into rectangles instead: the host is split
		// by each of the shape's four bounding edges in turn, and any piece
		// that ends up wholly inside the shape's box is dropped. A shape in a
		// corner leaves an L, and the L comes back as two panels — which is
		// more useful than one L anyway, because each is a frame that can be
		// drawn in.
		std::vector<std::vector<Vector2>> rest;
		rest.push_back(one);
		const Vector2 bb0 = cut_box.position;
		const Vector2 bb1 = cut_box.position + cut_box.size;
		const Vector2 edges[4][2] = {
			{ Vector2(bb0.x, bb0.y), Vector2(bb1.x, bb0.y) },
			{ Vector2(bb1.x, bb0.y), Vector2(bb1.x, bb1.y) },
			{ Vector2(bb1.x, bb1.y), Vector2(bb0.x, bb1.y) },
			{ Vector2(bb0.x, bb1.y), Vector2(bb0.x, bb0.y) },
		};
		for (int e = 0; e < 4; e++) {
			std::vector<std::vector<Vector2>> grown;
			for (size_t k = 0; k < rest.size(); k++) {
				const PackedVector2Array packed = to_packed(rest[k]);
				// Both sides are kept and judged afterwards. Deciding in
				// advance which side is "outside" needs the piece's position
				// relative to the box, and a piece can straddle it.
				PackedVector2Array in_side = clip_half(packed, edges[e][0],
						edges[e][1], true);
				PackedVector2Array out_side = clip_half(packed, edges[e][0],
						edges[e][1], false);
				if (in_side.size() < 3 || out_side.size() < 3) {
					grown.push_back(rest[k]);
					continue;
				}
				if (std::fabs(signed_area(in_side)) >= LEAST_AREA) {
					grown.push_back(to_vec(in_side));
				}
				if (std::fabs(signed_area(out_side)) >= LEAST_AREA) {
					grown.push_back(to_vec(out_side));
				}
			}
			rest = grown;
		}
		// Drop every piece that sits inside the shape's box — that is the
		// part the shape took. Judged on the piece's own centre, which is
		// inside it for any convex piece, and every piece here is convex
		// because it came out of four half-plane clips.
		std::vector<std::vector<Vector2>> kept;
		for (size_t k = 0; k < rest.size(); k++) {
			Vector2 mid;
			for (size_t j = 0; j < rest[k].size(); j++) {
				mid += rest[k][j];
			}
			mid /= (real_t)rest[k].size();
			if (cut_box.has_point(mid)) {
				continue;
			}
			kept.push_back(rest[k]);
		}
		rest = kept;

		if (half > 0.0) {
			inner = inset(inner, half);
		}
		if (inner.size() >= 3) {
			made.push_back(to_vec(inner));
		}
		for (size_t k = 0; k < rest.size(); k++) {
			PackedVector2Array piece = to_packed(rest[k]);
			if (half > 0.0) {
				piece = inset(piece, half);
			}
			if (piece.size() >= 3
					&& std::fabs(signed_area(piece)) >= LEAST_AREA) {
				next.push_back(to_vec(piece));
			}
		}
		touched++;
	}
	if (touched == 0) {
		return 0;
	}
	for (size_t i = 0; i < made.size(); i++) {
		next.push_back(made[i]);
	}
	panels_ = next;
	if (cutting_) {
		++session_cuts_;
	}
	return touched;
}

// -------------------------------------------------------------- questions

int IvoryComic::panel_at(const Vector2 &at) const {
	// Backwards, so the most recently made panel wins where two overlap. A
	// shape cut out of a panel is added after it, and the shape is what the
	// finger meant.
	for (int i = (int)panels_.size() - 1; i >= 0; i--) {
		if (point_in(panels_[i], at)) {
			return i;
		}
	}
	return -1;
}

bool IvoryComic::inside(int index, const Vector2 &at) const {
	if (index < 0 || index >= (int)panels_.size()) {
		return false;
	}
	return point_in(panels_[index], at);
}

int IvoryComic::edge_at(const Vector2 &at, double reach) const {
	const double limit = reach * reach;
	double best = limit;
	int found = -1;
	for (size_t i = 0; i < panels_.size(); i++) {
		const std::vector<Vector2> &poly = panels_[i];
		const int n = (int)poly.size();
		// Sixty-four edges is the packing limit of `panel * 64 + edge`. A
		// panel with more than that is not something a person drew.
		for (int e = 0; e < std::min(n, 64); e++) {
			const Vector2 &p = poly[e];
			const Vector2 &q = poly[(e + 1) % n];
			const Vector2 span = q - p;
			const double len2 = (double)span.length_squared();
			if (len2 < 1.0e-9) {
				continue;
			}
			double t = ((double)(at.x - p.x) * (double)span.x
					+ (double)(at.y - p.y) * (double)span.y) / len2;
			t = std::min(std::max(t, 0.0), 1.0);
			const Vector2 on = p + span * (real_t)t;
			const double d2 = (double)(at - on).length_squared();
			if (d2 < best) {
				best = d2;
				found = (int)i * 64 + e;
			}
		}
	}
	return found;
}

Rect2 IvoryComic::bounds_of(int index) const {
	if (index < 0 || index >= (int)panels_.size()
			|| panels_[index].empty()) {
		return Rect2();
	}
	Rect2 box(panels_[index][0], Vector2());
	for (size_t i = 1; i < panels_[index].size(); i++) {
		box = box.expand(panels_[index][i]);
	}
	return box;
}

double IvoryComic::area_of(int index) const {
	if (index < 0 || index >= (int)panels_.size()) {
		return 0.0;
	}
	return std::fabs(area_of_vec(panels_[index]));
}

PackedByteArray IvoryComic::mask_of(int index, const Rect2i &rect) const {
	PackedByteArray out;
	if (index < 0 || index >= (int)panels_.size()) {
		return out;
	}
	const int w = std::max(rect.size.x, 0);
	const int h = std::max(rect.size.y, 0);
	if (w <= 0 || h <= 0) {
		return out;
	}
	out.resize(w * h);
	// Filled rather than left as whatever the allocation held. A mask with
	// uninitialised bytes in it clips paint at random.
	for (int i = 0; i < w * h; i++) {
		out[i] = 0;
	}
	const std::vector<Vector2> &poly = panels_[index];
	const int n = (int)poly.size();
	if (n < 3) {
		return out;
	}

	// Scanline fill. For each row, find where every edge crosses the row's
	// centre line, sort the crossings, and fill between them in pairs. This
	// is the standard even-odd fill and it is exact for any simple polygon,
	// convex or not — which matters, because a panel cut twice on the same
	// side is not convex.
	std::vector<double> hits;
	hits.reserve(n);
	for (int y = 0; y < h; y++) {
		const double sy = (double)(rect.position.y + y) + 0.5;
		hits.clear();
		for (int i = 0, j = n - 1; i < n; j = i++) {
			const double py = (double)poly[i].y;
			const double qy = (double)poly[j].y;
			if ((py > sy) == (qy > sy)) {
				continue;
			}
			const double t = (sy - py) / (qy - py);
			hits.push_back((double)poly[i].x
					+ t * ((double)poly[j].x - (double)poly[i].x));
		}
		if (hits.size() < 2) {
			continue;
		}
		std::sort(hits.begin(), hits.end());
		for (size_t k = 0; k + 1 < hits.size(); k += 2) {
			int x0 = (int)std::ceil(hits[k] - 0.5) - rect.position.x;
			int x1 = (int)std::floor(hits[k + 1] - 0.5) - rect.position.x;
			x0 = std::max(x0, 0);
			x1 = std::min(x1, w - 1);
			for (int x = x0; x <= x1; x++) {
				out[y * w + x] = 255;
			}
		}
	}
	return out;
}


// ------------------------------------------------------------- the session

void IvoryComic::begin_cutting() {
	before_ = panels_;
	cutting_ = true;
	session_cuts_ = 0;
}

double IvoryComic::perimeter_of(const std::vector<Vector2> &poly) {
	double sum = 0.0;
	for (size_t i = 0; i < poly.size(); ++i) {
		sum += poly[i].distance_to(poly[(i + 1) % poly.size()]);
	}
	return sum;
}

int IvoryComic::tidy(double min_area, double min_compactness) {
	const double floor_area = std::max(min_area, 0.0);
	const double floor_shape = std::max(min_compactness, 0.0);
	std::vector<std::vector<Vector2>> kept;
	kept.reserve(panels_.size());
	int gone = 0;
	for (const std::vector<Vector2> &poly : panels_) {
		if (poly.size() < 3) {
			++gone;
			continue;
		}
		const double area = std::fabs(area_of_vec(poly));
		if (area < floor_area) {
			++gone;
			continue;
		}
		// Compactness: four pi times area over perimeter squared. One for a
		// circle, about 0.78 for a square, and near nought for a splinter.
		// A panel four hundred long and two wide passes any area test worth
		// setting and fails this, which is the point of having it.
		const double p = perimeter_of(poly);
		const double compact = p > 1e-9 ? (4.0 * PI * area) / (p * p) : 0.0;
		if (compact < floor_shape) {
			++gone;
			continue;
		}
		kept.push_back(poly);
	}
	// A page with no panels at all is not a tidier page, it is a lost one.
	// If tidying would clear everything, nothing is cleared and the caller
	// is told none went.
	if (kept.empty() && !panels_.empty()) {
		return 0;
	}
	panels_.swap(kept);
	return gone;
}

Dictionary IvoryComic::finish_cutting(double min_area) {
	Dictionary out;
	const int was = (int)panels_.size();
	// A sliver is anything under the floor given, or anything too thin to
	// draw in whatever its area. The compactness floor is deliberately low:
	// a legitimate long thin panel across the top of a page is a real
	// layout, and only a genuine splinter falls below this.
	const int cleared = tidy(min_area, 0.02);
	out["ok"] = cutting_;
	out["panels"] = (int)panels_.size();
	out["was"] = was;
	out["cuts"] = session_cuts_;
	out["tidied"] = cleared;
	cutting_ = false;
	session_cuts_ = 0;
	before_.clear();
	return out;
}

Dictionary IvoryComic::abandon_cutting() {
	Dictionary out;
	out["ok"] = cutting_;
	out["cuts"] = session_cuts_;
	if (cutting_) {
		panels_ = before_;
	}
	out["panels"] = (int)panels_.size();
	cutting_ = false;
	session_cuts_ = 0;
	before_.clear();
	return out;
}
