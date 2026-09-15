#include "ivory_arap.h"

#include <algorithm>
#include <cmath>
#include <map>

namespace godot {

static constexpr double EPS = 1e-12;

void IvoryArapSolver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_mesh", "rest", "triangles"), &IvoryArapSolver::set_mesh);
	ClassDB::bind_method(D_METHOD("set_pins", "indices", "at"), &IvoryArapSolver::set_pins);
	ClassDB::bind_method(D_METHOD("freeze", "indices"), &IvoryArapSolver::freeze);
	ClassDB::bind_method(D_METHOD("thaw", "indices"), &IvoryArapSolver::thaw);
	ClassDB::bind_method(D_METHOD("thaw_all"), &IvoryArapSolver::thaw_all);
	ClassDB::bind_method(D_METHOD("is_frozen", "index"), &IvoryArapSolver::is_frozen);
	ClassDB::bind_method(D_METHOD("frozen_count"), &IvoryArapSolver::frozen_count);
	ClassDB::bind_method(D_METHOD("solve", "iterations"), &IvoryArapSolver::solve, DEFVAL(6));
	ClassDB::bind_method(D_METHOD("positions"), &IvoryArapSolver::positions);
	ClassDB::bind_method(D_METHOD("set_positions", "p"), &IvoryArapSolver::set_positions);
	ClassDB::bind_method(D_METHOD("reset"), &IvoryArapSolver::reset);
	ClassDB::bind_method(D_METHOD("energy"), &IvoryArapSolver::energy);
	ClassDB::bind_method(D_METHOD("triangle_stretch"), &IvoryArapSolver::triangle_stretch);
	ClassDB::bind_method(D_METHOD("triangle_area_ratio"), &IvoryArapSolver::triangle_area_ratio);
	ClassDB::bind_method(D_METHOD("set_relaxation", "omega"), &IvoryArapSolver::set_relaxation);
	ClassDB::bind_method(D_METHOD("relaxation"), &IvoryArapSolver::relaxation);
}

void IvoryArapSolver::set_relaxation(double omega) {
	// Below 1 it under-relaxes and crawls; at 2 Gauss-Seidel on this class of
	// system stops converging. 1.6 is the usual sweet spot for a 2D Laplacian.
	omega_ = std::clamp(omega, 0.5, 1.95);
}

bool IvoryArapSolver::set_mesh(const PackedVector2Array &rest, const PackedInt32Array &triangles) {
	rest_.clear();
	now_.clear();
	tris_.clear();
	adj_.clear();
	adj_w_.clear();
	adj_start_.clear();
	diag_.clear();
	rot_c_.clear();
	rot_s_.clear();
	held_.clear();
	frozen_.clear();
	if (rest.size() < 3 || triangles.size() < 3) return false;

	rest_.reserve(rest.size());
	for (int i = 0; i < rest.size(); ++i) rest_.push_back(rest[i]);
	const int n = (int)rest_.size();

	for (int i = 0; i + 2 < triangles.size(); i += 3) {
		const int a = triangles[i], b = triangles[i + 1], c = triangles[i + 2];
		if (a < 0 || b < 0 || c < 0 || a >= n || b >= n || c >= n) return false;
		if (a == b || b == c || a == c) continue;
		tris_.push_back(a); tris_.push_back(b); tris_.push_back(c);
	}
	if (tris_.empty()) return false;

	// Cotangent weights. For an edge (i, j), the weight is the sum of the
	// cotangents of the two angles opposite it, halved. It is the weighting
	// that makes the discrete Laplacian agree with the continuous one, and
	// without it the mesh is stiffer wherever its triangles are smaller — so
	// the same drag would feel different in different parts of one drawing.
	std::map<std::pair<int, int>, double> w;
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		for (int k = 0; k < 3; ++k) {
			const int i = tris_[t + k];
			const int j = tris_[t + (k + 1) % 3];
			const int o = tris_[t + (k + 2) % 3];   // the vertex opposite edge (i, j)
			const Vector2 u = rest_[i] - rest_[o];
			const Vector2 v = rest_[j] - rest_[o];
			const double cross = (double)u.x * v.y - (double)u.y * v.x;
			const double dot = (double)u.x * v.x + (double)u.y * v.y;
			// cot(theta) = cos/sin = dot/|cross|. Clamped, because a sliver
			// triangle produces a cotangent that runs away and a single
			// enormous weight would dominate the whole solve.
			double cot = std::abs(cross) < 1e-12 ? 0.0 : dot / std::abs(cross);
			cot = std::clamp(cot, -4.0, 4.0);
			const int lo = std::min(i, j), hi = std::max(i, j);
			w[{ lo, hi }] += 0.5 * cot;
		}
	}

	// A negative total weight means a badly shaped pair of triangles, and a
	// negative weight in a Gauss-Seidel sweep pushes a vertex the wrong way.
	// Flooring at a small positive value keeps the system diagonally dominant,
	// which is what guarantees the sweep converges at all.
	std::vector<std::vector<std::pair<int, double>>> lists((size_t)n);
	for (auto &pair : w) {
		const double weight = std::max(pair.second, 0.02);
		lists[(size_t)pair.first.first].push_back({ pair.first.second, weight });
		lists[(size_t)pair.first.second].push_back({ pair.first.first, weight });
	}

	adj_start_.assign((size_t)n + 1, 0);
	for (int i = 0; i < n; ++i) adj_start_[(size_t)i + 1] = adj_start_[(size_t)i] + (int)lists[(size_t)i].size();
	adj_.resize((size_t)adj_start_[(size_t)n]);
	adj_w_.resize((size_t)adj_start_[(size_t)n]);
	diag_.assign((size_t)n, 0.0);
	for (int i = 0; i < n; ++i) {
		int at = adj_start_[(size_t)i];
		for (auto &pair : lists[(size_t)i]) {
			adj_[(size_t)at] = pair.first;
			adj_w_[(size_t)at] = pair.second;
			diag_[(size_t)i] += pair.second;
			++at;
		}
	}

	now_ = rest_;
	last_good_ = rest_;
	rot_c_.assign((size_t)n, 1.0);
	rot_s_.assign((size_t)n, 0.0);
	held_.assign((size_t)n, 0);
	frozen_.assign((size_t)n, 0);

	// One signed area per triangle, at rest, and the mean squared edge length
	// as the scale the degeneracy floor is judged against. Both are wanted
	// only by `prevent_foldover`, computed once here rather than every sweep.
	tri_rest_area_.clear();
	tri_rest_area_.reserve(tris_.size() / 3);
	double edge2_sum = 0.0;
	int edge2_count = 0;
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		const Vector2 &a = rest_[(size_t)tris_[t]];
		const Vector2 &b = rest_[(size_t)tris_[t + 1]];
		const Vector2 &c = rest_[(size_t)tris_[t + 2]];
		const double ux = (double)b.x - a.x, uy = (double)b.y - a.y;
		const double vx = (double)c.x - a.x, vy = (double)c.y - a.y;
		tri_rest_area_.push_back(0.5 * (ux * vy - uy * vx));
		edge2_sum += ux * ux + uy * uy;
		edge2_count++;
	}
	area_floor_span2_ = edge2_count > 0 ? std::max(edge2_sum / edge2_count, 1e-6) : 1.0;
	return true;
}

void IvoryArapSolver::set_pins(const PackedInt32Array &indices, const PackedVector2Array &at) {
	const int n = (int)now_.size();
	if (n == 0) return;
	// Frozen vertices survive a change of pins: freezing is the artist saying
	// "this part is finished", and it should not be undone by picking up a
	// different pin.
	for (int i = 0; i < n; ++i) held_[(size_t)i] = frozen_[(size_t)i];

	const int count = std::min(indices.size(), at.size());
	for (int k = 0; k < count; ++k) {
		const int i = indices[k];
		if (i < 0 || i >= n) continue;
		now_[(size_t)i] = at[k];
		held_[(size_t)i] = 1;
	}
}

void IvoryArapSolver::freeze(const PackedInt32Array &indices) {
	const int n = (int)now_.size();
	for (int k = 0; k < indices.size(); ++k) {
		const int i = indices[k];
		if (i < 0 || i >= n) continue;
		frozen_[(size_t)i] = 1;
		held_[(size_t)i] = 1;
	}
}

void IvoryArapSolver::thaw(const PackedInt32Array &indices) {
	const int n = (int)now_.size();
	for (int k = 0; k < indices.size(); ++k) {
		const int i = indices[k];
		if (i < 0 || i >= n) continue;
		frozen_[(size_t)i] = 0;
		held_[(size_t)i] = 0;
	}
}

void IvoryArapSolver::thaw_all() {
	std::fill(frozen_.begin(), frozen_.end(), 0);
	std::fill(held_.begin(), held_.end(), 0);
}

bool IvoryArapSolver::is_frozen(int index) const {
	if (index < 0 || index >= (int)frozen_.size()) return false;
	return frozen_[(size_t)index] != 0;
}

int IvoryArapSolver::frozen_count() const {
	int n = 0;
	for (uint8_t f : frozen_) n += f ? 1 : 0;
	return n;
}

// The local step. For each vertex, the rotation that best explains how its
// own one-ring has moved. In 2D this is closed form: accumulate the
// weighted covariance and take its angle. No iteration, no matrix library.
void IvoryArapSolver::fit_rotations() {
	const int n = (int)now_.size();
	for (int i = 0; i < n; ++i) {
		double along = 0.0, across = 0.0;
		for (int k = adj_start_[(size_t)i]; k < adj_start_[(size_t)i + 1]; ++k) {
			const int j = adj_[(size_t)k];
			const double weight = adj_w_[(size_t)k];
			const double ex = (double)rest_[i].x - rest_[j].x;
			const double ey = (double)rest_[i].y - rest_[j].y;
			const double fx = (double)now_[i].x - now_[j].x;
			const double fy = (double)now_[i].y - now_[j].y;
			along += weight * (ex * fx + ey * fy);
			across += weight * (ex * fy - ey * fx);
		}
		const double mag = std::sqrt(along * along + across * across);
		if (mag < EPS) {
			// A neighbourhood that has collapsed to a point has no rotation
			// to find. The honest answer is "none", not an arbitrary one.
			rot_c_[(size_t)i] = 1.0;
			rot_s_[(size_t)i] = 0.0;
		} else {
			rot_c_[(size_t)i] = along / mag;
			rot_s_[(size_t)i] = across / mag;
		}
	}
}

// The global step. One over-relaxed Gauss-Seidel sweep of the ARAP normal
// equations. Held vertices are skipped entirely — that is what makes a pin
// exact rather than merely heavy.
double IvoryArapSolver::sweep() {
	const int n = (int)now_.size();
	double biggest = 0.0;
	for (int i = 0; i < n; ++i) {
		if (held_[(size_t)i]) continue;
		if (diag_[(size_t)i] < EPS) continue;
		double bx = 0.0, by = 0.0;
		for (int k = adj_start_[(size_t)i]; k < adj_start_[(size_t)i + 1]; ++k) {
			const int j = adj_[(size_t)k];
			const double weight = adj_w_[(size_t)k];
			const double ex = (double)rest_[i].x - rest_[j].x;
			const double ey = (double)rest_[i].y - rest_[j].y;
			// The average of the two endpoints' rotations applied to the rest
			// edge. Using both, rather than only vertex i's, is what keeps the
			// solve symmetric and stops a seam appearing between a rotated
			// region and a still one.
			const double cx = 0.5 * (rot_c_[(size_t)i] + rot_c_[(size_t)j]);
			const double sx = 0.5 * (rot_s_[(size_t)i] + rot_s_[(size_t)j]);
			bx += weight * ((double)now_[j].x + cx * ex - sx * ey);
			by += weight * ((double)now_[j].y + sx * ex + cx * ey);
		}
		const double tx = bx / diag_[(size_t)i];
		const double ty = by / diag_[(size_t)i];
		const double nx = (1.0 - omega_) * (double)now_[i].x + omega_ * tx;
		const double ny = (1.0 - omega_) * (double)now_[i].y + omega_ * ty;
		biggest = std::max(biggest, std::abs(nx - (double)now_[i].x));
		biggest = std::max(biggest, std::abs(ny - (double)now_[i].y));
		now_[(size_t)i] = Vector2((real_t)nx, (real_t)ny);
	}
	return biggest;
}

// ------------------------------------------------------------ fold-over guard
//
// Nothing above this line stops a triangle passing through zero area and
// coming back with the opposite winding. Gauss-Seidel does not know the mesh
// is a drawing; it only knows it is trying to satisfy a linear system, and a
// pin dragged through another part of the artwork is a perfectly good place
// for that system's minimum to sit with a triangle turned inside out. The
// picture then looks torn rather than bent.
//
// This is the same guard `IvoryWarp` runs, for the same reason: a feasibility
// projection, not a smoothing pass. If a step would cross out of the set of
// windings the mesh started with, a binary search takes the largest fraction
// of that exact step that stays inside it — so a pin visibly stops at the
// limit of what the drawing can do instead of tearing.
bool IvoryArapSolver::mesh_is_valid(const std::vector<Vector2> &points) const {
	if (points.size() != now_.size()) return true;
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		const Vector2 &a = points[(size_t)tris_[t]];
		const Vector2 &b = points[(size_t)tris_[t + 1]];
		const Vector2 &c = points[(size_t)tris_[t + 2]];
		const double ux = (double)b.x - a.x, uy = (double)b.y - a.y;
		const double vx = (double)c.x - a.x, vy = (double)c.y - a.y;
		const double area = 0.5 * (ux * vy - uy * vx);
		const double rest_area = tri_rest_area_[t / 3];
		// 1.5% of the rest area, with a tiny scale-relative floor — enough to
		// stay clear of the singular zero-area configuration without making
		// ordinary pin motion feel stiff.
		const double floor_area = std::max(std::abs(rest_area) * 0.015, area_floor_span2_ * 1e-6);
		if (rest_area > 0.0) {
			if (area < floor_area) return false;
		} else {
			if (area > -floor_area) return false;
		}
	}
	return true;
}

void IvoryArapSolver::prevent_foldover(const std::vector<Vector2> &before) {
	if (tris_.empty() || before.size() != now_.size()) return;
	if (mesh_is_valid(now_)) {
		last_good_ = now_;
		return;
	}
	// `before` is expected to already be feasible — it is either the last
	// good pose or the state after an earlier guard already ran this frame.
	// If it is not (a pin jumped so far in one step that even the starting
	// point cannot be trusted), fall back to the last configuration that was
	// actually verified sound, never all the way to rest: rest throws away
	// every pin's work for a fault that touched one triangle.
	if (!mesh_is_valid(before)) {
		if (last_good_.size() == now_.size()) {
			now_ = last_good_;
		}
		return;
	}
	const std::vector<Vector2> target = now_;
	std::vector<Vector2> candidate(now_.size());
	double lo = 0.0, hi = 1.0;
	for (int iter = 0; iter < 10; ++iter) {
		const double mid = (lo + hi) * 0.5;
		for (size_t i = 0; i < candidate.size(); ++i) {
			candidate[i] = before[i] + (target[i] - before[i]) * mid;
		}
		if (mesh_is_valid(candidate)) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	for (size_t i = 0; i < now_.size(); ++i) {
		now_[i] = before[i] + (target[i] - before[i]) * lo;
	}
	last_good_ = now_;
}

Dictionary IvoryArapSolver::solve(int iterations) {
	Dictionary out;
	out["ok"] = false;
	out["iterations"] = 0;
	if (now_.empty()) return out;

	iterations = std::clamp(iterations, 1, 200);
	int done = 0;
	double step = 0.0;
	for (int it = 0; it < iterations; ++it) {
		fit_rotations();
		// Several sweeps per rotation fit. The rotations change slowly and
		// cost a full pass over the neighbour lists; the sweeps are what
		// actually move the mesh, so this is where the time is best spent.
		step = 0.0;
		for (int s = 0; s < 8; ++s) {
			const std::vector<Vector2> before = now_;
			step = sweep();
			prevent_foldover(before);
		}
		++done;
		// Converged: another iteration would move nothing anyone can see.
		if (step < 1e-4) break;
	}

	out["ok"] = true;
	out["iterations"] = done;
	out["max_step"] = step;
	out["energy"] = energy();
	out["held"] = (int)std::count(held_.begin(), held_.end(), (uint8_t)1);
	out["mesh_valid"] = mesh_is_valid(now_);
	return out;
}

double IvoryArapSolver::energy() const {
	double e = 0.0;
	const int n = (int)now_.size();
	for (int i = 0; i < n; ++i) {
		for (int k = adj_start_[(size_t)i]; k < adj_start_[(size_t)i + 1]; ++k) {
			const int j = adj_[(size_t)k];
			if (j < i) continue;
			const double weight = adj_w_[(size_t)k];
			const double ex = (double)rest_[i].x - rest_[j].x;
			const double ey = (double)rest_[i].y - rest_[j].y;
			const double rx = rot_c_[(size_t)i] * ex - rot_s_[(size_t)i] * ey;
			const double ry = rot_s_[(size_t)i] * ex + rot_c_[(size_t)i] * ey;
			const double dx = ((double)now_[i].x - now_[j].x) - rx;
			const double dy = ((double)now_[i].y - now_[j].y) - ry;
			e += weight * (dx * dx + dy * dy);
		}
	}
	return e;
}

PackedFloat32Array IvoryArapSolver::triangle_stretch() const {
	PackedFloat32Array out;
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		const Vector2 &a0 = rest_[tris_[t]], &b0 = rest_[tris_[t + 1]], &c0 = rest_[tris_[t + 2]];
		const Vector2 &a1 = now_[tris_[t]], &b1 = now_[tris_[t + 1]], &c1 = now_[tris_[t + 2]];
		// The affine map taking the rest triangle to the current one, then its
		// largest singular value: how much the triangle has been stretched
		// along its most stretched direction.
		const double e0x = b0.x - a0.x, e0y = b0.y - a0.y;
		const double e1x = c0.x - a0.x, e1y = c0.y - a0.y;
		const double det = e0x * e1y - e0y * e1x;
		if (std::abs(det) < 1e-12) { out.append(1.0f); continue; }
		const double f0x = b1.x - a1.x, f0y = b1.y - a1.y;
		const double f1x = c1.x - a1.x, f1y = c1.y - a1.y;
		// F = [f0 f1] * [e0 e1]^-1
		const double i00 = e1y / det, i01 = -e1x / det;
		const double i10 = -e0y / det, i11 = e0x / det;
		const double m00 = f0x * i00 + f1x * i10;
		const double m01 = f0x * i01 + f1x * i11;
		const double m10 = f0y * i00 + f1y * i10;
		const double m11 = f0y * i01 + f1y * i11;
		// Singular values of a 2x2, without an eigen solver.
		const double e = (m00 + m11) * 0.5, f = (m00 - m11) * 0.5;
		const double g = (m10 + m01) * 0.5, hh = (m10 - m01) * 0.5;
		const double q = std::sqrt(e * e + hh * hh);
		const double r = std::sqrt(f * f + g * g);
		out.append((float)(q + r));
	}
	return out;
}

PackedFloat32Array IvoryArapSolver::triangle_area_ratio() const {
	PackedFloat32Array out;
	for (size_t t = 0; t + 2 < tris_.size(); t += 3) {
		const Vector2 &a0 = rest_[tris_[t]], &b0 = rest_[tris_[t + 1]], &c0 = rest_[tris_[t + 2]];
		const Vector2 &a1 = now_[tris_[t]], &b1 = now_[tris_[t + 1]], &c1 = now_[tris_[t + 2]];
		const double was = (double)(b0.x - a0.x) * (c0.y - a0.y) - (double)(b0.y - a0.y) * (c0.x - a0.x);
		const double now = (double)(b1.x - a1.x) * (c1.y - a1.y) - (double)(b1.y - a1.y) * (c1.x - a1.x);
		out.append(std::abs(was) < 1e-12 ? 1.0f : (float)(now / was));
	}
	return out;
}

PackedVector2Array IvoryArapSolver::positions() const {
	PackedVector2Array out;
	for (const Vector2 &v : now_) out.append(v);
	return out;
}

void IvoryArapSolver::set_positions(const PackedVector2Array &p) {
	const int n = std::min((int)now_.size(), p.size());
	for (int i = 0; i < n; ++i) now_[(size_t)i] = p[i];
	// A caller setting the pose outright — warm-starting after a rebuild —
	// is asserting this is a good pose, so it becomes the guard's fallback
	// too. If it is not actually valid, the next `solve()` finds that out
	// and repairs it rather than trusting a fold silently.
	if (mesh_is_valid(now_)) last_good_ = now_;
}

void IvoryArapSolver::reset() {
	now_ = rest_;
	last_good_ = rest_;
	std::fill(rot_c_.begin(), rot_c_.end(), 1.0);
	std::fill(rot_s_.begin(), rot_s_.end(), 0.0);
}

} // namespace godot
