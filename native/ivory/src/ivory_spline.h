#ifndef IVORY_SPLINE_H
#define IVORY_SPLINE_H

// The curve the B-spline room steers a drawing with, in C++.
//
// ## The complaint
//
// "Moving a point drags other points with it, and drags part of the outline
// outside the point along too."
//
// Both halves of that are real and they have different causes, so they need
// different answers.
//
// ## Half one: the curve does not go where the finger goes
//
// A B-spline does not pass through its control points. It is *pulled towards*
// them, and the amount by which is the basis function — for a cubic, about
// two thirds at the strongest. So dragging a control point onto a place moves
// the curve about two thirds of the way there, and the natural thing to do
// next is drag further, overshoot, and drag back. The curve chases the finger
// and never arrives.
//
// The fix is not to drag control points at all. It is to let the person drag
// **the curve**, and solve for what the control points must be. That has an
// exact answer and it is one line of algebra:
//
//     S(t) = sum_j N_j(t) P_j
//
// so moving only `P_i` moves `S(t)` by `N_i(t) * dP_i`. To put `S(t)` exactly
// on a target, set
//
//     dP_i = (target - S(t)) / N_i(t)
//
// and the curve passes through the target **exactly**, first time, with no
// chasing. Choosing `i` as the control point with the largest `N_i(t)` makes
// the required displacement the smallest it can be, and dividing by the
// largest basis value is also the best-conditioned of the four choices.
//
// ## Half two: "it drags the outline outside the point"
//
// This one is a real guarantee and it is worth stating precisely, because it
// is the property the whole room is built on.
//
// A cubic B-spline control point `P_i` has support over exactly the knot span
// range `[u_i, u_{i+4})`. Outside that range `N_i(u)` is **identically zero** —
// not small, zero — so the curve there is not merely nearly unchanged, it is
// bit-for-bit the same number it was before. `MODE_ONE` moves exactly one
// control point, so a drag near a shoulder cannot stir an ankle, and
// `test_spline.cpp` asserts that on the raw floats rather than within a
// tolerance.
//
// The two other modes exist because "smallest possible change" and "smoothest
// possible change" are not the same wish:
//
//   * **`MODE_ONE`** — one control point moves. The strictest guarantee, the
//     smallest number of things that changed, and a slightly sharper local
//     bend because all the correction is at one place.
//   * **`MODE_SPREAD`** — the minimum-norm correction over the four control
//     points that are active at `t`. This is the least-squares solution of an
//     underdetermined system: `dP_j = N_j(t) / sum(N^2) * delta`. It moves
//     four points instead of one, still touches nothing outside their joint
//     support, and gives a rounder bend because the correction is shared.
//   * **`MODE_STIFF`** — as `MODE_SPREAD`, then a bending-energy relaxation
//     over the neighbouring points with the target held fixed. It is what to
//     use when the curve is a spine or a limb and the wanted answer is "bend,
//     do not kink".
//
// ## Why the arc-length table is done by Gauss–Legendre
//
// Binding a drawing to a curve needs distance *along* it, and a B-spline's
// arc length has no closed form. Sampling it as a polyline and adding up the
// chords is the usual answer and it always under-reads, because a chord is
// shorter than the arc it spans — so ink bound to the curve creeps towards
// the start every time the table is rebuilt.
//
// Five-point Gauss–Legendre per knot span integrates `|S'(u)|` exactly for
// polynomials up to degree nine. A cubic's derivative magnitude is not a
// polynomial, but the error falls as the tenth derivative, which for a cubic
// piece is nought — so on each span the answer is exact to rounding. No
// creep, at a twentieth of the samples.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvorySpline : public RefCounted {
	GDCLASS(IvorySpline, RefCounted)

protected:
	static void _bind_methods();

public:
	IvorySpline() = default;
	~IvorySpline() = default;

	enum Mode {
		MODE_ONE,
		MODE_SPREAD,
		MODE_STIFF,
	};

	static const int DEGREE = 3;

	// --- the curve ---

	// Hands over the control points. The knot vector is rebuilt clamped and
	// uniform unless one is given, so the curve starts at the first point
	// and ends at the last, which is what anybody placing points expects.
	void set_points(const PackedVector2Array &points);
	void set_knots(const PackedFloat32Array &knots);
	PackedVector2Array points() const;
	PackedFloat32Array knots() const;
	int size() const { return (int)point_.size(); }
	bool ready() const { return (int)point_.size() >= DEGREE + 1; }

	void set_point(int index, const Vector2 &to);
	Vector2 point_at_index(int index) const;
	void insert_point(int before, const Vector2 &at);
	void remove_point(int index);
	void clear();

	// The parameter range the curve is actually defined over.
	double first_u() const;
	double last_u() const;

	// De Boor. Every step is a convex combination, so nothing can grow and
	// rounding cannot accumulate into a wobble.
	Vector2 eval(double u) const;
	Vector2 tangent(double u) const;
	// Signed curvature. Used to decide where a bend needs more mesh, and to
	// tell a person that they have made a kink.
	double curvature(double u) const;

	// The four basis values at `u`, and the index of the first of them.
	Dictionary basis_at(double u) const;

	// --- moving the curve, not the points ---

	// Puts the curve at parameter `u` exactly on `to`.
	//
	// Returns which control points moved and by how much, so the interface
	// can show it and the undo can reverse exactly that and nothing else.
	Dictionary pull_at(double u, const Vector2 &to, int mode);

	// The parameter of the place on the curve nearest a point. Coarse scan
	// then a few Newton steps, because a scan fine enough on its own would
	// have to be very fine and Newton converges quadratically once it is
	// close.
	double nearest_u(const Vector2 &to) const;

	// Drag the curve at whatever place is nearest `from`. The whole gesture
	// in one call: this is what a finger on the curve does.
	Dictionary pull_nearest(const Vector2 &from, const Vector2 &to, int mode);

	// --- shape ---

	// Boehm knot insertion. Adds a knot without changing the curve at all —
	// the shape before and after is identical, only now there is somewhere
	// to break it.
	bool insert_knot(double u);
	// Repeats a knot until continuity there drops to C0 and the curve
	// touches its control point exactly: a corner in an otherwise silk
	// curve.
	bool sharpen_at(int index);

	// Total bending energy, the integral of curvature squared. What
	// `MODE_STIFF` reduces, and a number the room can show.
	double bending_energy() const;
	// One pass of energy relaxation with `held` control points pinned.
	void relax(const PackedInt32Array &held, double strength, int passes);

	// --- length along the curve ---

	// Rebuilds the arc-length table. `per_span` is how many entries each
	// knot span gets.
	void measure(int per_span);
	double length() const;
	// The parameter at a given distance along the curve, and the reverse.
	double u_at_length(double s) const;
	double length_at_u(double u) const;

	// Where a point sits in curve space: how far along, and how far off to
	// the side. This is how a drawing is bound.
	Dictionary to_curve_space(const Vector2 &at) const;
	Vector2 from_curve_space(double s, double side) const;

	// A polyline of the curve, for drawing it.
	PackedVector2Array to_polyline(int per_span) const;

private:
	std::vector<Vector2> point_;
	std::vector<double> knot_;
	std::vector<double> arc_u_;
	std::vector<double> arc_s_;

	void rebuild_knots();
	int span_of(double u) const;
	static void basis_values(const std::vector<double> &knot, int span,
			double u, double *out);
	double span_length(double a, double b) const;
	Vector2 derivative(double u) const;
	Vector2 second_derivative(double u) const;
};

} // namespace godot

VARIANT_ENUM_CAST(IvorySpline::Mode);

#endif // IVORY_SPLINE_H
