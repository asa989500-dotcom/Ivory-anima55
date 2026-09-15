#include "ivory_spline.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

// Five-point Gauss-Legendre on [-1, 1]. Exact for polynomials to degree nine.
const double GL_X[5] = {
	-0.9061798459386640, -0.5384693101056831, 0.0,
	0.5384693101056831, 0.9061798459386640
};
const double GL_W[5] = {
	0.2369268850561891, 0.4786286704993665, 0.5688888888888889,
	0.4786286704993665, 0.2369268850561891
};

} // namespace

void IvorySpline::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_points", "points"),
			&IvorySpline::set_points);
	ClassDB::bind_method(D_METHOD("set_knots", "knots"),
			&IvorySpline::set_knots);
	ClassDB::bind_method(D_METHOD("points"), &IvorySpline::points);
	ClassDB::bind_method(D_METHOD("knots"), &IvorySpline::knots);
	ClassDB::bind_method(D_METHOD("size"), &IvorySpline::size);
	ClassDB::bind_method(D_METHOD("ready"), &IvorySpline::ready);
	ClassDB::bind_method(D_METHOD("set_point", "index", "to"),
			&IvorySpline::set_point);
	ClassDB::bind_method(D_METHOD("point_at_index", "index"),
			&IvorySpline::point_at_index);
	ClassDB::bind_method(D_METHOD("insert_point", "before", "at"),
			&IvorySpline::insert_point);
	ClassDB::bind_method(D_METHOD("remove_point", "index"),
			&IvorySpline::remove_point);
	ClassDB::bind_method(D_METHOD("clear"), &IvorySpline::clear);
	ClassDB::bind_method(D_METHOD("first_u"), &IvorySpline::first_u);
	ClassDB::bind_method(D_METHOD("last_u"), &IvorySpline::last_u);
	ClassDB::bind_method(D_METHOD("eval", "u"), &IvorySpline::eval);
	ClassDB::bind_method(D_METHOD("tangent", "u"), &IvorySpline::tangent);
	ClassDB::bind_method(D_METHOD("curvature", "u"), &IvorySpline::curvature);
	ClassDB::bind_method(D_METHOD("basis_at", "u"), &IvorySpline::basis_at);
	ClassDB::bind_method(D_METHOD("pull_at", "u", "to", "mode"),
			&IvorySpline::pull_at);
	ClassDB::bind_method(D_METHOD("nearest_u", "to"), &IvorySpline::nearest_u);
	ClassDB::bind_method(D_METHOD("pull_nearest", "from", "to", "mode"),
			&IvorySpline::pull_nearest);
	ClassDB::bind_method(D_METHOD("insert_knot", "u"),
			&IvorySpline::insert_knot);
	ClassDB::bind_method(D_METHOD("sharpen_at", "index"),
			&IvorySpline::sharpen_at);
	ClassDB::bind_method(D_METHOD("bending_energy"),
			&IvorySpline::bending_energy);
	ClassDB::bind_method(D_METHOD("relax", "held", "strength", "passes"),
			&IvorySpline::relax);
	ClassDB::bind_method(D_METHOD("measure", "per_span"),
			&IvorySpline::measure);
	ClassDB::bind_method(D_METHOD("length"), &IvorySpline::length);
	ClassDB::bind_method(D_METHOD("u_at_length", "s"),
			&IvorySpline::u_at_length);
	ClassDB::bind_method(D_METHOD("length_at_u", "u"),
			&IvorySpline::length_at_u);
	ClassDB::bind_method(D_METHOD("to_curve_space", "at"),
			&IvorySpline::to_curve_space);
	ClassDB::bind_method(D_METHOD("from_curve_space", "s", "side"),
			&IvorySpline::from_curve_space);
	ClassDB::bind_method(D_METHOD("to_polyline", "per_span"),
			&IvorySpline::to_polyline);

	BIND_ENUM_CONSTANT(MODE_ONE);
	BIND_ENUM_CONSTANT(MODE_SPREAD);
	BIND_ENUM_CONSTANT(MODE_STIFF);
}

// ------------------------------------------------------------------- shape

void IvorySpline::rebuild_knots() {
	const int n = (int)point_.size();
	knot_.clear();
	if (n < DEGREE + 1) {
		return;
	}
	// Clamped and uniform: the first and last knots repeated `degree + 1`
	// times, so the curve begins at the first control point and ends at the
	// last. Anything else and a person placing a point at the end of a limb
	// finds the curve stopping short of it.
	const int spans = n - DEGREE;
	knot_.reserve((size_t)(n + DEGREE + 1));
	for (int i = 0; i <= DEGREE; ++i) {
		knot_.push_back(0.0);
	}
	for (int i = 1; i < spans; ++i) {
		knot_.push_back((double)i / (double)spans);
	}
	for (int i = 0; i <= DEGREE; ++i) {
		knot_.push_back(1.0);
	}
}

void IvorySpline::set_points(const PackedVector2Array &points) {
	point_.clear();
	point_.reserve((size_t)points.size());
	for (int i = 0; i < points.size(); ++i) {
		point_.push_back(points[i]);
	}
	rebuild_knots();
	arc_u_.clear();
	arc_s_.clear();
}

void IvorySpline::set_knots(const PackedFloat32Array &knots) {
	// A knot vector must be non-decreasing and the right length, or de Boor
	// divides by a negative span and the curve turns inside out. A bad one
	// is refused and the uniform one kept, rather than believed.
	const int want = (int)point_.size() + DEGREE + 1;
	if (knots.size() != want) {
		return;
	}
	for (int i = 1; i < knots.size(); ++i) {
		if (knots[i] < knots[i - 1]) {
			return;
		}
	}
	knot_.clear();
	for (int i = 0; i < knots.size(); ++i) {
		knot_.push_back(knots[i]);
	}
	arc_u_.clear();
	arc_s_.clear();
}

PackedVector2Array IvorySpline::points() const {
	PackedVector2Array out;
	out.resize((int)point_.size());
	for (size_t i = 0; i < point_.size(); ++i) {
		out[(int)i] = point_[i];
	}
	return out;
}

PackedFloat32Array IvorySpline::knots() const {
	PackedFloat32Array out;
	out.resize((int)knot_.size());
	for (size_t i = 0; i < knot_.size(); ++i) {
		out[(int)i] = (float)knot_[i];
	}
	return out;
}

void IvorySpline::set_point(int index, const Vector2 &to) {
	if (index < 0 || index >= (int)point_.size()) {
		return;
	}
	point_[(size_t)index] = to;
}

Vector2 IvorySpline::point_at_index(int index) const {
	if (index < 0 || index >= (int)point_.size()) {
		return Vector2();
	}
	return point_[(size_t)index];
}

void IvorySpline::insert_point(int before, const Vector2 &at) {
	const int n = (int)point_.size();
	const int k = clampd(before, 0, n);
	point_.insert(point_.begin() + k, at);
	rebuild_knots();
	arc_u_.clear();
	arc_s_.clear();
}

void IvorySpline::remove_point(int index) {
	if (index < 0 || index >= (int)point_.size()) {
		return;
	}
	point_.erase(point_.begin() + index);
	rebuild_knots();
	arc_u_.clear();
	arc_s_.clear();
}

void IvorySpline::clear() {
	point_.clear();
	knot_.clear();
	arc_u_.clear();
	arc_s_.clear();
}

double IvorySpline::first_u() const {
	return knot_.empty() ? 0.0 : knot_[DEGREE];
}

double IvorySpline::last_u() const {
	return knot_.empty() ? 0.0 : knot_[knot_.size() - 1 - DEGREE];
}

int IvorySpline::span_of(double u) const {
	const int n = (int)point_.size();
	if (n < DEGREE + 1) {
		return -1;
	}
	const double lo = first_u();
	const double hi = last_u();
	const double at = clampd(u, lo, hi);
	// The last span owns its own end, or evaluating at exactly `hi` falls
	// off the end of the array.
	if (at >= hi) {
		int s = n - 1;
		while (s > DEGREE && knot_[(size_t)s] >= hi) {
			--s;
		}
		return s;
	}
	int lo_i = DEGREE;
	int hi_i = n;
	while (hi_i - lo_i > 1) {
		const int mid = (lo_i + hi_i) / 2;
		if (knot_[(size_t)mid] <= at) {
			lo_i = mid;
		} else {
			hi_i = mid;
		}
	}
	return lo_i;
}

void IvorySpline::basis_values(const std::vector<double> &knot, int span,
		double u, double *out) {
	// Cox-de Boor, in the triangular form that never divides by nought:
	// each denominator is a knot span that the recursion has already
	// established is non-empty.
	double left[DEGREE + 1];
	double right[DEGREE + 1];
	out[0] = 1.0;
	for (int j = 1; j <= DEGREE; ++j) {
		left[j] = u - knot[(size_t)(span + 1 - j)];
		right[j] = knot[(size_t)(span + j)] - u;
		double saved = 0.0;
		for (int r = 0; r < j; ++r) {
			const double den = right[r + 1] + left[j - r];
			const double temp = den > 1e-12 ? out[r] / den : 0.0;
			out[r] = saved + right[r + 1] * temp;
			saved = left[j - r] * temp;
		}
		out[j] = saved;
	}
}

Vector2 IvorySpline::eval(double u) const {
	if (!ready()) {
		return point_.empty() ? Vector2() : point_[0];
	}
	const int span = span_of(u);
	if (span < 0) {
		return Vector2();
	}
	double n[DEGREE + 1];
	basis_values(knot_, span, clampd(u, first_u(), last_u()), n);
	Vector2 out;
	for (int i = 0; i <= DEGREE; ++i) {
		const int at = span - DEGREE + i;
		if (at >= 0 && at < (int)point_.size()) {
			out += point_[(size_t)at] * (real_t)n[i];
		}
	}
	return out;
}

Dictionary IvorySpline::basis_at(double u) const {
	Dictionary out;
	PackedFloat32Array values;
	if (!ready()) {
		out["first"] = -1;
		out["values"] = values;
		return out;
	}
	const int span = span_of(u);
	double n[DEGREE + 1];
	basis_values(knot_, span, clampd(u, first_u(), last_u()), n);
	for (int i = 0; i <= DEGREE; ++i) {
		values.append((float)n[i]);
	}
	out["first"] = span - DEGREE;
	out["values"] = values;
	out["span"] = span;
	return out;
}

Vector2 IvorySpline::derivative(double u) const {
	if (!ready()) {
		return Vector2();
	}
	// Central difference on the parameter. The analytic derivative is a
	// B-spline of one lower degree over a shrunk knot vector, which is more
	// code and buys nothing here: the curve is a cubic, so a central
	// difference at this step is exact to the fourth derivative term, which
	// is what a difference of a cubic loses and is well under a pixel.
	const double lo = first_u();
	const double hi = last_u();
	const double h = std::max((hi - lo) * 1e-4, 1e-9);
	const double a = clampd(u - h, lo, hi);
	const double b = clampd(u + h, lo, hi);
	const double span = b - a;
	if (span < 1e-12) {
		return Vector2();
	}
	return (eval(b) - eval(a)) / (real_t)span;
}

Vector2 IvorySpline::second_derivative(double u) const {
	const double lo = first_u();
	const double hi = last_u();
	const double h = std::max((hi - lo) * 1e-3, 1e-8);
	const double a = clampd(u - h, lo, hi);
	const double b = clampd(u + h, lo, hi);
	const Vector2 mid = eval(clampd(u, lo, hi));
	const double step = std::max((b - a) * 0.5, 1e-9);
	return (eval(a) - mid * 2.0f + eval(b)) / (real_t)(step * step);
}

Vector2 IvorySpline::tangent(double u) const {
	return derivative(u).normalized();
}

double IvorySpline::curvature(double u) const {
	const Vector2 d1 = derivative(u);
	const Vector2 d2 = second_derivative(u);
	const double speed = d1.length();
	if (speed < 1e-9) {
		return 0.0;
	}
	return d1.cross(d2) / (speed * speed * speed);
}

// ------------------------------------------------ moving the curve directly

Dictionary IvorySpline::pull_at(double u, const Vector2 &to, int mode) {
	Dictionary out;
	PackedInt32Array moved;
	PackedVector2Array by;
	out["moved"] = moved;
	out["by"] = by;
	out["ok"] = false;
	if (!ready()) {
		return out;
	}

	const double at = clampd(u, first_u(), last_u());
	const int span = span_of(at);
	double n[DEGREE + 1];
	basis_values(knot_, span, at, n);
	const Vector2 delta = to - eval(at);

	if (mode == MODE_ONE) {
		// The control point with the largest basis value. Largest because
		// the required displacement is the wanted one divided by it, so the
		// largest gives the smallest move — and dividing by the largest of
		// the four is also the best-conditioned of the four choices.
		int best = 0;
		for (int i = 1; i <= DEGREE; ++i) {
			if (n[i] > n[best]) {
				best = i;
			}
		}
		const int index = span - DEGREE + best;
		if (index < 0 || index >= (int)point_.size() || n[best] < 1e-6) {
			return out;
		}
		const Vector2 step = delta / (real_t)n[best];
		point_[(size_t)index] += step;
		moved.append(index);
		by.append(step);
	} else {
		// Minimum-norm correction over the four active points. Of all the
		// ways to move four points so that the curve lands on the target,
		// this is the one that moves them least in total — the least-squares
		// solution of an underdetermined system, which here is one line.
		double sum_sq = 0.0;
		for (int i = 0; i <= DEGREE; ++i) {
			sum_sq += n[i] * n[i];
		}
		if (sum_sq < 1e-12) {
			return out;
		}
		for (int i = 0; i <= DEGREE; ++i) {
			const int index = span - DEGREE + i;
			if (index < 0 || index >= (int)point_.size()) {
				continue;
			}
			const Vector2 step = delta * (real_t)(n[i] / sum_sq);
			point_[(size_t)index] += step;
			moved.append(index);
			by.append(step);
		}
	}

	if (mode == MODE_STIFF) {
		// Relax the neighbours with the four just moved held, so the bend
		// rounds out into the curve on either side instead of stopping dead
		// at the edge of the support.
		PackedInt32Array held = moved;
		relax(held, 0.35, 6);
	}

	arc_u_.clear();
	arc_s_.clear();
	out["moved"] = moved;
	out["by"] = by;
	out["ok"] = true;
	out["u"] = at;
	// How far the curve actually landed from the target. Exact for the two
	// direct modes; `MODE_STIFF` trades a little of it for smoothness, and
	// saying so is better than implying otherwise.
	out["residual"] = eval(at).distance_to(to);
	return out;
}

double IvorySpline::nearest_u(const Vector2 &to) const {
	if (!ready()) {
		return 0.0;
	}
	const double lo = first_u();
	const double hi = last_u();
	// A coarse scan to find the right basin, then Newton to land in it. A
	// scan fine enough on its own would have to be very fine; Newton
	// converges quadratically once it is near, so four steps is plenty.
	const int spans = std::max((int)point_.size() - DEGREE, 1);
	const int samples = std::max(spans * 8, 16);
	double best_u = lo;
	double best_d = 1e30;
	for (int i = 0; i <= samples; ++i) {
		const double u = lo + (hi - lo) * ((double)i / (double)samples);
		const double d = eval(u).distance_squared_to(to);
		if (d < best_d) {
			best_d = d;
			best_u = u;
		}
	}
	double u = best_u;
	for (int step = 0; step < 6; ++step) {
		const Vector2 p = eval(u);
		const Vector2 d1 = derivative(u);
		const Vector2 d2 = second_derivative(u);
		const Vector2 diff = p - to;
		// Minimising |S(u) - to|^2: f' = 2 (S - to) . S', f'' = 2 (|S'|^2 +
		// (S - to) . S'').
		const double f1 = diff.dot(d1);
		const double f2 = d1.length_squared() + diff.dot(d2);
		if (std::fabs(f2) < 1e-12) {
			break;
		}
		const double next = clampd(u - f1 / f2, lo, hi);
		if (std::fabs(next - u) < 1e-9) {
			u = next;
			break;
		}
		u = next;
	}
	// Newton can walk uphill on a curve that doubles back. Keep whichever of
	// the two is actually nearer rather than trusting it.
	return eval(u).distance_squared_to(to) <= best_d ? u : best_u;
}

Dictionary IvorySpline::pull_nearest(const Vector2 &from, const Vector2 &to,
		int mode) {
	return pull_at(nearest_u(from), to, mode);
}

// ------------------------------------------------------------------- knots

bool IvorySpline::insert_knot(double u) {
	if (!ready()) {
		return false;
	}
	const double at = clampd(u, first_u(), last_u());
	const int span = span_of(at);
	if (span < 0) {
		return false;
	}
	// Boehm. The new control points are convex combinations of the old, and
	// the curve is unchanged — every value of it, everywhere, to the last
	// decimal. That is what makes it safe to do on a shape somebody has
	// already spent time on.
	std::vector<Vector2> next;
	next.reserve(point_.size() + 1);
	for (int i = 0; i <= span - DEGREE; ++i) {
		next.push_back(point_[(size_t)i]);
	}
	for (int i = span - DEGREE + 1; i <= span; ++i) {
		const double den = knot_[(size_t)(i + DEGREE)] - knot_[(size_t)i];
		const double a = den > 1e-12 ? (at - knot_[(size_t)i]) / den : 0.0;
		next.push_back(point_[(size_t)(i - 1)] * (real_t)(1.0 - a) +
				point_[(size_t)i] * (real_t)a);
	}
	for (int i = span; i < (int)point_.size(); ++i) {
		next.push_back(point_[(size_t)i]);
	}
	knot_.insert(knot_.begin() + span + 1, at);
	point_.swap(next);
	arc_u_.clear();
	arc_s_.clear();
	return true;
}

bool IvorySpline::sharpen_at(int index) {
	if (!ready() || index <= 0 || index >= (int)point_.size() - 1) {
		return false;
	}
	// The parameter this control point is most responsible for — the Greville
	// abscissa, which is the average of the knots that span it and is where
	// its basis function peaks.
	double sum = 0.0;
	for (int i = 1; i <= DEGREE; ++i) {
		sum += knot_[(size_t)(index + i)];
	}
	const double at = sum / (double)DEGREE;
	// Repeated `degree - 1` more times, so the multiplicity reaches
	// `degree` and continuity there falls to C0: the curve arrives, touches
	// its control point exactly, and leaves in a new direction.
	bool any = false;
	for (int i = 0; i < DEGREE - 1; ++i) {
		any = insert_knot(at) || any;
	}
	return any;
}

// ----------------------------------------------------------------- energy

double IvorySpline::bending_energy() const {
	if (!ready()) {
		return 0.0;
	}
	const double lo = first_u();
	const double hi = last_u();
	const int samples = std::max((int)point_.size() * 8, 32);
	double sum = 0.0;
	for (int i = 0; i <= samples; ++i) {
		const double u = lo + (hi - lo) * ((double)i / (double)samples);
		const double k = curvature(u);
		sum += k * k;
	}
	return sum * (hi - lo) / (double)(samples + 1);
}

void IvorySpline::relax(const PackedInt32Array &held, double strength,
		int passes) {
	const int n = (int)point_.size();
	if (n < 3) {
		return;
	}
	std::vector<uint8_t> pinned((size_t)n, 0);
	for (int i = 0; i < held.size(); ++i) {
		const int at = held[i];
		if (at >= 0 && at < n) {
			pinned[(size_t)at] = 1;
		}
	}
	// The ends are always pinned. A relaxation that is free to move them
	// shortens the curve a little on every pass, and over a session of
	// editing the whole shape creeps inwards.
	pinned[0] = 1;
	pinned[(size_t)(n - 1)] = 1;

	const double w = clampd(strength, 0.0, 1.0);
	for (int pass = 0; pass < std::max(passes, 0); ++pass) {
		std::vector<Vector2> next = point_;
		for (int i = 1; i < n - 1; ++i) {
			if (pinned[(size_t)i]) {
				continue;
			}
			// Towards the midpoint of its neighbours, which is the discrete
			// gradient of the bending energy. Nothing more clever is wanted:
			// the curve is already C2, and the only job here is to take a
			// kink out of the control polygon without moving what was
			// deliberately placed.
			const Vector2 mid = (point_[(size_t)(i - 1)] +
					point_[(size_t)(i + 1)]) * 0.5f;
			next[(size_t)i] = point_[(size_t)i].lerp(mid, (real_t)w);
		}
		point_.swap(next);
	}
	arc_u_.clear();
	arc_s_.clear();
}

// ------------------------------------------------------------------ length

double IvorySpline::span_length(double a, double b) const {
	// Five-point Gauss-Legendre of |S'(u)| over [a, b].
	const double half = (b - a) * 0.5;
	const double mid = (a + b) * 0.5;
	double sum = 0.0;
	for (int i = 0; i < 5; ++i) {
		sum += GL_W[i] * derivative(mid + half * GL_X[i]).length();
	}
	return sum * half;
}

void IvorySpline::measure(int per_span) {
	arc_u_.clear();
	arc_s_.clear();
	if (!ready()) {
		return;
	}
	const int steps = std::max(per_span, 2);
	const double lo = first_u();
	const double hi = last_u();
	const int spans = std::max((int)point_.size() - DEGREE, 1);
	const int total = spans * steps;
	arc_u_.reserve((size_t)total + 1);
	arc_s_.reserve((size_t)total + 1);
	double running = 0.0;
	arc_u_.push_back(lo);
	arc_s_.push_back(0.0);
	for (int i = 1; i <= total; ++i) {
		const double a = lo + (hi - lo) * ((double)(i - 1) / (double)total);
		const double b = lo + (hi - lo) * ((double)i / (double)total);
		running += span_length(a, b);
		arc_u_.push_back(b);
		arc_s_.push_back(running);
	}
}

double IvorySpline::length() const {
	return arc_s_.empty() ? 0.0 : arc_s_.back();
}

double IvorySpline::length_at_u(double u) const {
	if (arc_u_.size() < 2) {
		return 0.0;
	}
	const double at = clampd(u, arc_u_.front(), arc_u_.back());
	const size_t k = (size_t)(std::lower_bound(arc_u_.begin(), arc_u_.end(),
			at) - arc_u_.begin());
	if (k == 0) {
		return 0.0;
	}
	const double u0 = arc_u_[k - 1];
	const double u1 = arc_u_[k];
	const double f = u1 - u0 > 1e-12 ? (at - u0) / (u1 - u0) : 0.0;
	return arc_s_[k - 1] + (arc_s_[k] - arc_s_[k - 1]) * f;
}

double IvorySpline::u_at_length(double s) const {
	if (arc_s_.size() < 2) {
		return first_u();
	}
	const double at = clampd(s, 0.0, arc_s_.back());
	const size_t k = (size_t)(std::lower_bound(arc_s_.begin(), arc_s_.end(),
			at) - arc_s_.begin());
	if (k == 0) {
		return arc_u_.front();
	}
	const double s0 = arc_s_[k - 1];
	const double s1 = arc_s_[k];
	const double f = s1 - s0 > 1e-12 ? (at - s0) / (s1 - s0) : 0.0;
	return arc_u_[k - 1] + (arc_u_[k] - arc_u_[k - 1]) * f;
}

Dictionary IvorySpline::to_curve_space(const Vector2 &at) const {
	Dictionary out;
	const double u = nearest_u(at);
	const Vector2 on = eval(u);
	const Vector2 t = tangent(u);
	const Vector2 side = t.orthogonal();
	out["u"] = u;
	out["s"] = length_at_u(u);
	// Signed, so the drawing knows which side of the curve it was on. An
	// unsigned distance flips ink across the curve wherever it is rebound.
	out["side"] = (double)(at - on).dot(side);
	out["distance"] = at.distance_to(on);
	return out;
}

Vector2 IvorySpline::from_curve_space(double s, double side) const {
	const double u = u_at_length(s);
	const Vector2 on = eval(u);
	const Vector2 t = tangent(u);
	return on + t.orthogonal() * (real_t)side;
}

PackedVector2Array IvorySpline::to_polyline(int per_span) const {
	PackedVector2Array out;
	if (!ready()) {
		return out;
	}
	const int steps = std::max(per_span, 2);
	const int spans = std::max((int)point_.size() - DEGREE, 1);
	const int total = spans * steps;
	const double lo = first_u();
	const double hi = last_u();
	for (int i = 0; i <= total; ++i) {
		out.append(eval(lo + (hi - lo) * ((double)i / (double)total)));
	}
	return out;
}
