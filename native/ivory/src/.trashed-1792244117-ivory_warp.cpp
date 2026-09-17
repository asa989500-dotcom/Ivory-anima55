#include "ivory_warp.h"

#include <algorithm>
#include <cmath>
#include <queue>
#include <unordered_map>

using namespace godot;

// Unreachable: a piece of drawing no path connects to this pin.
static const float FAR_AWAY = 1.0e20f;
// What a piece of drawing no path reaches is treated as costing, on top of the
// straight-line distance to it. Matches `PuppetWarp.BRIDGE`.
static const float BRIDGE = 240.0f;
// How much more the outward smoothing pass gives back than the inward one
// took. Matches `PuppetWarp.INFLATE`.
static const float INFLATE = 1.03f;
// Below this many pins there is no rotation to find, so the drawing is carried.
static const int RIGID_FROM = 2;

void IvoryWarp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_mesh", "rest", "neighbours", "rim",
								 "cell_span", "triangles"),
			&IvoryWarp::set_mesh);
	ClassDB::bind_method(D_METHOD("set_params", "stiffness", "softness",
								 "rigid", "smoothing", "omega"),
			&IvoryWarp::set_params);
	ClassDB::bind_method(D_METHOD("set_bounds", "min_corner", "max_corner"),
			&IvoryWarp::set_bounds);
	ClassDB::bind_method(D_METHOD("set_pins", "rest_pins", "now_pins",
								 "vertex", "turn"),
			&IvoryWarp::set_pins);
	ClassDB::bind_method(D_METHOD("move_pins", "now_pins", "turn"),
			&IvoryWarp::move_pins);
	ClassDB::bind_method(D_METHOD("set_mode", "mode"), &IvoryWarp::set_mode);
	ClassDB::bind_method(D_METHOD("solve", "settle"), &IvoryWarp::solve);
	ClassDB::bind_method(D_METHOD("pose"), &IvoryWarp::pose);
	ClassDB::bind_method(D_METHOD("set_pose", "now"), &IvoryWarp::set_pose);
	ClassDB::bind_method(D_METHOD("ready"), &IvoryWarp::ready);
	ClassDB::bind_method(D_METHOD("vertex_count"), &IvoryWarp::vertex_count);
}

void IvoryWarp::set_mode(int mode) {
	mode_ = mode < 0 ? 0 : (mode > 2 ? 2 : mode);
}

IvoryWarp::IvoryWarp() {}
IvoryWarp::~IvoryWarp() {}

bool IvoryWarp::ready() const {
	return !rest_.empty() && near_.size() == rest_.size() * 4;
}

int IvoryWarp::vertex_count() const {
	return (int)rest_.size();
}

void IvoryWarp::set_mesh(const PackedVector2Array &rest,
		const PackedInt32Array &neighbours, const PackedByteArray &rim,
		double cell_span, const PackedInt32Array &triangles) {
	const int n = rest.size();
	rest_.resize(n);
	for (int i = 0; i < n; i++) {
		rest_[i] = rest[i];
	}
	near_.resize(neighbours.size());
	for (int i = 0; i < neighbours.size(); i++) {
		near_[i] = neighbours[i];
	}
	rim_.assign(n, 0);
	for (int i = 0; i < rim.size() && i < n; i++) {
		rim_[i] = rim[i];
	}
	cell_span_ = cell_span > 0.0001 ? cell_span : 1.0;

	now_ = rest_;
	last_good_ = rest_;
	triangles_.clear();
	rest_area_.clear();
	hold_.assign(n, 0.0f);
	rot_c_.assign(n, 1.0f);
	rot_s_.assign(n, 0.0f);
	pinned_.assign(n, 0);
	spare_.assign(n, Vector2());
	build_edges(triangles);
	reach_.clear();
	reach_dirty_ = true;
}

void IvoryWarp::set_params(double stiffness, double softness, double rigid,
		double smoothing, double omega) {
	stiffness_ = stiffness;
	softness_ = softness < 0.001 ? 0.001 : softness;
	rigid_ = std::min(std::max(rigid, 0.0), 1.0);
	smoothing_ = std::min(std::max(smoothing, 0.0), 1.0);
	// Under one is under-relaxation, which only ever slows it down; at two it
	// stops converging at all. The useful band is narrow and this is inside
	// it at both ends.
	omega_ = std::min(std::max(omega, 1.0), 1.9);
}

void IvoryWarp::set_bounds(const Vector2 &min_corner, const Vector2 &max_corner) {
	bounds_min_ = Vector2(std::min(min_corner.x, max_corner.x),
			std::min(min_corner.y, max_corner.y));
	bounds_max_ = Vector2(std::max(min_corner.x, max_corner.x),
			std::max(min_corner.y, max_corner.y));
	bounded_ = bounds_max_.x > bounds_min_.x && bounds_max_.y > bounds_min_.y;
}


void IvoryWarp::set_pins(const PackedVector2Array &rest_pins,
		const PackedVector2Array &now_pins, const PackedInt32Array &vertex,
		const PackedFloat32Array &turn) {
	const int n = rest_pins.size();
	pin_rest_.resize(n);
	pin_now_.resize(n);
	pin_vertex_.resize(n);
	pin_turn_.resize(n);
	any_turn_ = false;
	for (int i = 0; i < n; i++) {
		pin_rest_[i] = rest_pins[i];
		pin_now_[i] = i < now_pins.size() ? now_pins[i] : rest_pins[i];
		pin_vertex_[i] = i < vertex.size() ? vertex[i] : -1;
		pin_turn_[i] = i < turn.size() ? turn[i] : 0.0f;
		if (std::fabs(pin_turn_[i]) > 0.0001f) {
			any_turn_ = true;
		}
	}
	weight_.assign(n, 0.0);
	reach_dirty_ = true;
}

void IvoryWarp::move_pins(const PackedVector2Array &now_pins,
		const PackedFloat32Array &turn) {
	const int n = (int)pin_rest_.size();
	any_turn_ = false;
	for (int i = 0; i < n; i++) {
		if (i < now_pins.size()) {
			pin_now_[i] = now_pins[i];
		}
		if (i < turn.size()) {
			pin_turn_[i] = turn[i];
		}
		if (std::fabs(pin_turn_[i]) > 0.0001f) {
			any_turn_ = true;
		}
	}
}

PackedVector2Array IvoryWarp::pose() const {
	PackedVector2Array out;
	out.resize((int)now_.size());
	for (int i = 0; i < (int)now_.size(); i++) {
		out[i] = now_[i];
	}
	return out;
}

void IvoryWarp::set_pose(const PackedVector2Array &now) {
	for (int i = 0; i < now.size() && i < (int)now_.size(); i++) {
		now_[i] = now[i];
	}
	// A caller handing over a pose outright is warm-starting after a rebuild
	// and asserting it is sound. If it is not, the next `solve()` finds that
	// out through the guard rather than trusting a fold silently.
	if (mesh_is_valid(now_)) {
		last_good_ = now_;
	}
}

// --------------------------------------------------------------- mesh edges

// Build the solver graph from the *actual triangles*, not just the raster grid.
// This is important for Puppet Warp: every cell has a diagonal, and an ARAP
// solve that ignores those diagonals has a preferred horizontal/vertical
// direction. The diagonal alternates in GDScript specifically to remove that
// bias, so the native solver must see the same topology.
//
// Cotangent weights are the standard discretisation of the membrane/ARAP
// energy. For an edge shared by two triangles we use half the sum of the two
// opposite cotangents. Boundary edges get the one cotangent they have. Tiny
// negative/zero values are floored for numerical stability on nearly right or
// obtuse pixels; the topology is never changed.
void IvoryWarp::build_edges(const PackedInt32Array &triangles) {
	const int n = (int)rest_.size();
	edges_.assign(n, std::vector<std::pair<int32_t, double>>());
	if (n == 0) {
		return;
	}

	struct EdgeAccum {
		double cot = 0.0;
		int count = 0;
	};
	std::unordered_map<unsigned long long, EdgeAccum> acc;
	// `near_.size()` is a `size_t` and the floor is an `int`; on a toolchain
	// where they are different types `std::max` cannot deduce one and the
	// build stops. Both sides are made `size_t` here rather than casting the
	// result, which is the version that is right on 32-bit as well.
	acc.reserve(std::max(near_.size() / 2, (size_t)16));

	auto key_of = [](int a, int b) -> unsigned long long {
		const unsigned int lo = (unsigned int)std::min(a, b);
		const unsigned int hi = (unsigned int)std::max(a, b);
		return (static_cast<unsigned long long>(lo) << 32) | hi;
	};

	auto add_cot = [&](int a, int b, int opposite) {
		if (a < 0 || b < 0 || opposite < 0 || a >= n || b >= n || opposite >= n ||
				a == b || a == opposite || b == opposite) {
			return;
		}
		const Vector2 va = rest_[a] - rest_[opposite];
		const Vector2 vb = rest_[b] - rest_[opposite];
		const double cross = std::fabs((double)va.x * vb.y - (double)va.y * vb.x);
		if (cross < 1.0e-12) {
			return;
		}
		const double dot = (double)va.x * vb.x + (double)va.y * vb.y;
		// A negative cotangent is mathematically valid for an obtuse triangle,
		// but a tiny negative weight on a pixel mesh can destabilise an Android
		// drag. Keep the energy positive while retaining the geometric weight.
		const double cot = std::max(dot / cross, 0.02);
		EdgeAccum &e = acc[key_of(a, b)];
		e.cot += cot;
		e.count++;
	};

	if (triangles.size() >= 3) {
		const int tc = triangles.size() / 3;
		triangles_.reserve(tc);
		rest_area_.reserve(tc);
		for (int t = 0; t < tc; t++) {
			const int a = triangles[t * 3];
			const int b = triangles[t * 3 + 1];
			const int c = triangles[t * 3 + 2];
			if (a < 0 || b < 0 || c < 0 || a >= n || b >= n || c >= n ||
					a == b || b == c || c == a) {
				continue;
			}
			const Vector2 ab = rest_[b] - rest_[a];
			const Vector2 ac = rest_[c] - rest_[a];
			const double area2 = (double)ab.x * ac.y - (double)ab.y * ac.x;
			if (std::fabs(area2) < 1.0e-12) {
				continue;
			}
			triangles_.push_back({(int32_t)a, (int32_t)b, (int32_t)c});
			rest_area_.push_back(area2);
			add_cot(b, c, a);
			add_cot(c, a, b);
			add_cot(a, b, c);
		}
	}

	// Empty/invalid triangle data should never make native warp unusable. Fall
	// back to the exact grid graph used for distances.
	if (acc.empty()) {
		for (int i = 0; i < n; i++) {
			const int base = i * 4;
			for (int k = 0; k < 4; k++) {
				const int j = near_[base + k];
				if (j >= 0 && j < n) {
					edges_[i].push_back(std::make_pair(j, 1.0));
				}
			}
		}
		return;
	}

	for (const auto &it : acc) {
		const unsigned long long key = it.first;
		const int a = (int)(key >> 32);
		const int b = (int)(key & 0xffffffffu);
		const EdgeAccum &e = it.second;
		const double w = std::max(e.cot / (double)e.count, 0.02);
		edges_[a].push_back(std::make_pair(b, w));
		edges_[b].push_back(std::make_pair(a, w));
	}

	// Stable adjacency order keeps floating-point accumulation deterministic
	// across runs and makes touch-to-touch motion reproducible on Android.
	for (auto &list : edges_) {
		std::sort(list.begin(), list.end(), [](const auto &a, const auto &b) {
			return a.first < b.first;
		});
	}
}

// --------------------------------------------------------------- distances

// How far every part of the drawing is from every pin, walking the mesh.
//
// ## Why the walk and not the straight line
//
// Across the mouth of a U it is a few pixels from one arm to the other, so
// each arm gets weighted as though it were sitting on top of the other and
// pulling one drags ink that nothing connects it to. Walked through the mesh
// the same two points are the whole length of the bend apart.
//
// ## Why Dijkstra and not the sweeps
//
// The GDScript version relaxes: every vertex offers each neighbour a route
// through itself, and the passes repeat until no route improves. That
// converges to the right answer and stops when it is close enough, and how
// close depends on how many passes were affordable.
//
// Dijkstra settles each vertex exactly once, in order of distance, and the
// distance it settles on is final — there is no "close enough" in it. A
// binary heap over a mesh of a few thousand vertices costs less than the
// sweeps it replaces, so this is faster *and* exact, which is not a trade
// that comes up often.
void IvoryWarp::build_reach() {
	const int n = (int)rest_.size();
	const int pins = (int)pin_rest_.size();
	reach_.assign(pins, std::vector<float>());

	typedef std::pair<float, int> Step;
	std::priority_queue<Step, std::vector<Step>, std::greater<Step>> queue;

	for (int p = 0; p < pins; p++) {
		std::vector<float> &far = reach_[p];
		far.assign(n, FAR_AWAY);
		const int seed = pin_vertex_[p];
		if (seed < 0 || seed >= n) {
			continue;
		}
		while (!queue.empty()) {
			queue.pop();
		}
		far[seed] = 0.0f;
		queue.push(Step(0.0f, seed));
		while (!queue.empty()) {
			const Step top = queue.top();
			queue.pop();
			const int at = top.second;
			// A vertex reached again by a longer route was already settled.
			if (top.first > far[at]) {
				continue;
			}
			const Vector2 here = rest_[at];
			const int base = at * 4;
			for (int k = 0; k < 4; k++) {
				const int j = near_[base + k];
				if (j < 0) {
					continue;
				}
				const float step = (float)here.distance_to(rest_[j]);
				const float cost = top.first + step;
				if (cost < far[j]) {
					far[j] = cost;
					queue.push(Step(cost, j));
				}
			}
		}

		// --- islands the walk never reached ---
		//
		// A piece of drawing with no path to this pin would otherwise be left
		// standing still while everything around it moved, which takes the
		// picture apart. It is given the straight-line distance plus a fixed
		// toll, so it still answers to the pin but always less than anything
		// the pin is actually joined to.
		for (int i = 0; i < n; i++) {
			if (far[i] < FAR_AWAY) {
				continue;
			}
			far[i] = (float)rest_[i].distance_to(pin_rest_[p]) + BRIDGE;
		}
	}
	reach_dirty_ = false;
}

// How much of each vertex belongs to a pin rather than to the mesh.
//
// The relaxation passes move vertices for reasons that have nothing to do with
// where the pins are. Near a pin that is exactly wrong — a pin has to mean the
// place it sits on — so near a pin they are turned off, and they fade back in
// with distance.
void IvoryWarp::measure_hold() {
	const int n = (int)rest_.size();
	const double span = std::max(cell_span_ * 1.6, softness_);
	const double span2 = span * span;
	for (int i = 0; i < n; i++) {
		// Combine pin ownership as a probabilistic union. `max()` made two
		// nearby pins fight for the same vertex: whichever was slightly closer
		// completely hid the other's influence. The union keeps the strong local
		// hold of either pin while allowing their overlap to form one continuous
		// protected region.
		double free = 1.0;
		for (size_t p = 0; p < reach_.size(); p++) {
			if (reach_[p].empty()) {
				continue;
			}
			const double d = reach_[p][i];
			if (d >= FAR_AWAY) {
				continue;
			}
			const double got = std::exp(-(d * d) / span2);
			free *= (1.0 - std::clamp(got, 0.0, 1.0));
		}
		const double hold = 1.0 - free;
		hold_[i] = (float)std::clamp(hold, 0.0, 1.0);
	}
}

void IvoryWarp::mark_pinned() {
	std::fill(pinned_.begin(), pinned_.end(), (uint8_t)0);
	for (size_t p = 0; p < pin_vertex_.size(); p++) {
		const int v = pin_vertex_[p];
		if (v >= 0 && v < (int)pinned_.size()) {
			pinned_[v] = 1;
		}
	}
}

// ---------------------------------------------------------------------- MLS

// Where one vertex of the rest drawing ends up.
//
// Weigh every pin by how far it is through the mesh; find the weighted centre
// of the pins as they were and as they are now; then find the single rotation
// that best carries the first arrangement onto the second, as weighted from
// this vertex. Because only a rotation is fitted — never a stretch — the
// drawing keeps its proportions.
//
// Every sum here is a double. The weights are `1 / (d^2 + s^2)^k`, which over
// one vertex spans several orders of magnitude between a pin under the finger
// and one across the drawing; in single precision adding the far pin to the
// near one discards it entirely, and a pin that contributes nothing is a pin
// whose share of the rotation silently went to its neighbours.
Vector2 IvoryWarp::warp_vertex(int at) {
	const Vector2 v = rest_[at];
	const int count = (int)pin_rest_.size();
	double total = 0.0;
	double px = 0.0, py = 0.0, qx = 0.0, qy = 0.0;
	const double soft2 = softness_ * softness_;
	const bool plain = std::fabs(stiffness_ - 1.0) < 0.0001;

	for (int i = 0; i < count; i++) {
		const double d = reach_[i].empty() ? FAR_AWAY : reach_[i][at];
		if (d >= FAR_AWAY) {
			weight_[i] = 0.0;
			continue;
		}
		const double d2 = d * d;
		if (d2 < 0.000001) {
			return pin_now_[i];
		}
		const double den = d2 + soft2;
		const double w = plain ? 1.0 / den : 1.0 / std::pow(den, stiffness_);
		weight_[i] = w;
		total += w;
		px += (double)pin_rest_[i].x * w;
		py += (double)pin_rest_[i].y * w;
		qx += (double)pin_now_[i].x * w;
		qy += (double)pin_now_[i].y * w;
	}
	if (total <= 0.0) {
		return v;
	}
	px /= total;
	py /= total;
	qx /= total;
	qy /= total;

	const double ux = (double)v.x - px;
	const double uy = (double)v.y - py;
	double frx = 0.0, fry = 0.0;
	for (int i = 0; i < count; i++) {
		const double w = weight_[i];
		if (w <= 0.0) {
			continue;
		}
		const double phx = (double)pin_rest_[i].x - px;
		const double phy = (double)pin_rest_[i].y - py;
		const double qhx = (double)pin_now_[i].x - qx;
		const double qhy = (double)pin_now_[i].y - qy;
		// The two halves of a rotation, read off the rest offset against this
		// vertex: how much it lies along it, and how much across it.
		const double along = phx * ux + phy * uy;
		const double across = phx * uy - phy * ux;
		frx += w * (qhx * along - qhy * across);
		fry += w * (qhx * across + qhy * along);
	}

	double outx = qx;
	double outy = qy;

	if (mode_ == 2) {
		// --- affine ---
		//
		// The exact least-squares linear map from the rest offsets to the
		// moved ones, weighted:
		//
		//     M = (sum w p^T p)^-1 (sum w p^T q),   f(v) = (v - p*) M + q*
		//
		// A two by two inverse is written out rather than solved, because at
		// this size a general solver is slower and less accurate than the
		// closed form.
		//
		// This is the mode that squashes. Two pins pulled together compress
		// the material along the line joining them and leave what is square
		// to it alone, which is what a two-dimensional drawing being
		// shortened looks like. A rigid fit cannot express that at all: it is
		// only allowed to turn and slide, so the material has to go
		// *somewhere*, and where it goes is sideways.
		double sxx = 0.0, sxy = 0.0, syy = 0.0;
		double txx = 0.0, txy = 0.0, tyx = 0.0, tyy = 0.0;
		for (int i = 0; i < count; i++) {
			const double w = weight_[i];
			if (w <= 0.0) {
				continue;
			}
			const double phx = (double)pin_rest_[i].x - px;
			const double phy = (double)pin_rest_[i].y - py;
			const double qhx = (double)pin_now_[i].x - qx;
			const double qhy = (double)pin_now_[i].y - qy;
			sxx += w * phx * phx;
			sxy += w * phx * phy;
			syy += w * phy * phy;
			txx += w * phx * qhx;
			txy += w * phx * qhy;
			tyx += w * phy * qhx;
			tyy += w * phy * qhy;
		}
		const double det = sxx * syy - sxy * sxy;
		// Degenerate: every pin on one line through the centre, or only one
		// pin. There is no affine map to find — the system is rank deficient
		// and inverting it would amplify noise without limit — so the rigid
		// answer below is used instead. One pin dragged should carry the
		// drawing, not tear it.
		if (std::fabs(det) > 1.0e-9) {
			const double ixx = syy / det;
			const double ixy = -sxy / det;
			const double iyy = sxx / det;
			// M = S^-1 T, then (u) M.
			const double m00 = ixx * txx + ixy * tyx;
			const double m01 = ixx * txy + ixy * tyy;
			double m10 = ixy * txx + iyy * tyx;
			double m11 = ixy * txy + iyy * tyy;

			// --- the shear, taken out ---
			//
			// A full affine fit is scale *and shear*, and shear is the part
			// nobody wants. Pull one pin and a plain affine map does not only
			// squash the drawing along that line — it slides the far side
			// past the near side, so a rectangle becomes a parallelogram and
			// a face pulled by the chin comes out leaning. It reads as the
			// drawing sliding rather than compressing, which is the exact
			// complaint the affine mode was brought in to answer.
			//
			// So the matrix is decomposed and rebuilt without the skew. Gram-
			// Schmidt: keep the first column's direction, take the part of
			// the second that is square to it, and keep each one's own
			// length. What survives is a rotation and an independent scale on
			// each axis — which is stretching and squashing, exactly, and
			// nothing else.
			//
			// Blended rather than replaced outright. At full strength the
			// result is a little stiff where several pins disagree, because
			// some shear genuinely is the least-wrong answer there; three
			// quarters keeps the squash clean and leaves the fit some room.
			const double c0len = std::sqrt(m00 * m00 + m01 * m01);
			if (c0len > 1.0e-9) {
				const double e0x = m00 / c0len;
				const double e0y = m01 / c0len;
				// How much of the second column lies along the first — this
				// number *is* the shear.
				const double lean = m10 * e0x + m11 * e0y;
				double p1x = m10 - lean * e0x;
				double p1y = m11 - lean * e0y;
				const double c1len = std::sqrt(p1x * p1x + p1y * p1y);
				if (c1len > 1.0e-9) {
					// The second axis keeps the length it had, so the scale
					// on it is preserved; only its lean is discarded.
					const double want = std::sqrt(m10 * m10 + m11 * m11);
					p1x = p1x / c1len * want;
					p1y = p1y / c1len * want;
					const double keep = 0.75;
					m10 = m10 * (1.0 - keep) + p1x * keep;
					m11 = m11 * (1.0 - keep) + p1y * keep;
				}
			}

			outx = qx + ux * m00 + uy * m10;
			outy = qy + ux * m01 + uy * m11;
			// The turns the pins carry are applied below exactly as they are
			// for the other two modes, so a stretched drawing can still be
			// spun by a pin's ring.
			if (!any_turn_) {
				return Vector2((real_t)outx, (real_t)outy);
			}
			return turned_about(outx, outy);
		}
	}

	const double span = std::sqrt(frx * frx + fry * fry);
	if (span >= 1.0e-9) {
		if (mode_ == 1) {
			// --- similarity ---
			//
			// The same fit, divided by the weighted sum of the squared rest
			// offsets rather than renormalised to the vertex's old distance.
			// That single division is where the scale comes from: pins that
			// have spread further than they were give a number above one and
			// the neighbourhood grows with them.
			double mu = 0.0;
			for (int i = 0; i < count; i++) {
				const double w = weight_[i];
				if (w <= 0.0) {
					continue;
				}
				const double phx = (double)pin_rest_[i].x - px;
				const double phy = (double)pin_rest_[i].y - py;
				mu += w * (phx * phx + phy * phy);
			}
			if (mu > 1.0e-9) {
				outx = qx + frx / mu;
				outy = qy + fry / mu;
			} else {
				const double reach = std::sqrt(ux * ux + uy * uy) / span;
				outx = qx + frx * reach;
				outy = qy + fry * reach;
			}
		} else {
			// Only the direction of the fit is kept; the distance from the
			// centre is the one the vertex already had. That is the whole of
			// "rigid".
			const double reach = std::sqrt(ux * ux + uy * uy) / span;
			outx = qx + frx * reach;
			outy = qy + fry * reach;
		}
	}
	if (!any_turn_) {
		return Vector2((real_t)outx, (real_t)outy);
	}
	return turned_about(outx, outy);
}

// The turns the pins were given, laid on top of whichever fit produced
// `outx, outy`.
//
// Lifted out of `warp_vertex` when the affine fit arrived, so that all three
// modes share one implementation of spin rather than the two later ones
// quietly losing it.
Vector2 IvoryWarp::turned_about(double outx, double outy) {
	const int count = (int)pin_rest_.size();

	// The turns the pins were given, laid on top of the fit above. Averaged as
	// *directions* — unit vectors summed and the angle of the sum taken —
	// which is the only correct mean for angles, and about the pins that were
	// actually turned rather than about the weighted centre of all of them.
	double spinx = 0.0, spiny = 0.0;
	double pivx = 0.0, pivy = 0.0, pivw = 0.0;
	for (int i = 0; i < count; i++) {
		const double w = weight_[i];
		if (w <= 0.0) {
			continue;
		}
		const double a = pin_turn_[i];
		spinx += std::cos(a) * w;
		spiny += std::sin(a) * w;
		if (std::fabs(a) > 0.0001) {
			const double share = w * std::fabs(a);
			pivx += (double)pin_now_[i].x * share;
			pivy += (double)pin_now_[i].y * share;
			pivw += share;
		}
	}
	const double mag = std::sqrt(spinx * spinx + spiny * spiny);
	if (mag < 1.0e-9 || pivw <= 0.0) {
		return Vector2((real_t)outx, (real_t)outy);
	}
	spinx /= mag;
	spiny /= mag;
	pivx /= pivw;
	pivy /= pivw;
	const double offx = outx - pivx;
	const double offy = outy - pivy;
	return Vector2((real_t)(pivx + offx * spinx - offy * spiny),
			(real_t)(pivy + offx * spiny + offy * spinx));
}

// --------------------------------------------------------------------- ARAP

// The local step: the rotation that best explains how each vertex's own
// neighbourhood has moved. Closed form in two dimensions — the normalised sums
// *are* the cosine and sine, so the angle is never formed and no SVD is needed.
void IvoryWarp::fit() {
	const int n = (int)rest_.size();
	for (int i = 0; i < n; i++) {
		double along = 0.0;
		double across = 0.0;
		const Vector2 rest_i = rest_[i];
		const Vector2 now_i = now_[i];
		for (const auto &edge : edges_[i]) {
			const int j = edge.first;
			const double ew = edge.second;
			const double e0x = rest_i.x - rest_[j].x;
			const double e0y = rest_i.y - rest_[j].y;
			const double e1x = now_i.x - now_[j].x;
			const double e1y = now_i.y - now_[j].y;
			along += ew * (e0x * e1x + e0y * e1y);
			across += ew * (e0x * e1y - e0y * e1x);
		}
		const double mag = std::sqrt(along * along + across * across);
		if (mag < 1.0e-9) {
			rot_c_[i] = 1.0f;
			rot_s_[i] = 0.0f;
		} else {
			rot_c_[i] = (float)(along / mag);
			rot_s_[i] = (float)(across / mag);
		}
	}
}

// The global step: one over-relaxed sweep of `L p = b`.
//
// ## Why over-relaxation
//
// Gauss-Seidel moves each vertex exactly to the average its neighbours ask
// for, which is correct and slow: information travels one vertex per sweep and
// the error falls by a factor set by the mesh's spectral radius. Successive
// over-relaxation takes the same step and then some — `omega` times it, with
// `omega` between one and two — which for a Laplace system on a regular grid
// is the textbook accelerator and reaches the same fixed point in roughly a
// third of the sweeps.
//
// It is the *same* fixed point. Over-relaxation changes how fast the iteration
// arrives, not where it arrives, so the pose is the pose the energy asks for
// either way.
//
// `pull` is scaled down by `hold_` — how completely a pin owns this vertex.
// Right under a pin, MLS is exact and ARAP has nothing to add; out in the
// ground between pins, `hold_` is nothing and ARAP governs entirely. That one
// multiplication is what keeps the two solvers from arguing.
void IvoryWarp::sweep(bool backwards, double pull) {
	const int n = (int)rest_.size();
	for (int step = 0; step < n; step++) {
		const int i = backwards ? (n - 1 - step) : step;
		if (pinned_[i] || edges_[i].empty()) {
			continue;
		}
		const double share = pull * (1.0 - (double)hold_[i]);
		if (share <= 0.001) {
			continue;
		}
		const double c_i = rot_c_[i];
		const double s_i = rot_s_[i];
		const Vector2 rest_i = rest_[i];
		double wantx = 0.0, wanty = 0.0;
		double weight_sum = 0.0;
		for (const auto &edge : edges_[i]) {
			const int j = edge.first;
			const double ew = edge.second;
			const double e0x = rest_i.x - rest_[j].x;
			const double e0y = rest_i.y - rest_[j].y;
			const double cm = (c_i + rot_c_[j]) * 0.5;
			const double sm = (s_i + rot_s_[j]) * 0.5;
			wantx += ew * (now_[j].x + e0x * cm - e0y * sm);
			wanty += ew * (now_[j].y + e0x * sm + e0y * cm);
			weight_sum += ew;
		}
		if (weight_sum <= 1.0e-12) {
			continue;
		}
		wantx /= weight_sum;
		wanty /= weight_sum;
		double t = omega_ * share;
		if (t > 1.9) {
			t = 1.9;
		}
		now_[i].x = (real_t)(now_[i].x + (wantx - now_[i].x) * t);
		now_[i].y = (real_t)(now_[i].y + (wanty - now_[i].y) * t);
	}
}

// One pass of Laplacian smoothing. A negative amount pushes outward instead,
// which is the whole of Taubin's trick: plain Laplacian does not only smooth,
// it contracts, and an outward pass that gives back slightly more than the
// inward one took cancels the shrinkage without cancelling the smoothing.
//
// Outline vertices are averaged only against other outline vertices, never
// inward — a silhouette relaxed towards the middle of the drawing would slowly
// eat itself.
void IvoryWarp::smooth_by(double amount) {
	const int n = (int)rest_.size();
	for (int i = 0; i < n; i++) {
		spare_[i] = Vector2();
		if (pinned_[i]) {
			continue;
		}
		const double share = amount * (1.0 - (double)hold_[i]);
		if (std::fabs(share) < 0.0005) {
			continue;
		}
		const bool edge = rim_[i] != 0;
		double sx = 0.0, sy = 0.0, weight_sum = 0.0;
		for (const auto &edge_pair : edges_[i]) {
			const int j = edge_pair.first;
			const double ew = edge_pair.second;
			if (j < 0 || j >= n) {
				continue;
			}
			// The outline must stay on the outline. Unlike the old four-neighbour
			// grid, the forged mesh can have irregular valence, so use its actual
			// triangle edges rather than silently dropping diagonal/adaptive links.
			if (edge && rim_[j] == 0) {
				continue;
			}
			sx += now_[j].x * ew;
			sy += now_[j].y * ew;
			weight_sum += ew;
		}
		if (weight_sum <= 1.0e-12) {
			continue;
		}
		spare_[i] = Vector2((real_t)((sx / weight_sum - now_[i].x) * share),
				(real_t)((sy / weight_sum - now_[i].y) * share));
	}
	for (int i = 0; i < n; i++) {
		now_[i] += spare_[i];
	}
}

// Pins are hard constraints. MLS interpolates them analytically, but the
// sweeps that follow are free to drift off them by a fraction of a pixel, and
// a pin the drawing is not quite nailed to is a pin that does not feel nailed.
void IvoryWarp::enforce_pins() {
	for (size_t p = 0; p < pin_vertex_.size(); p++) {
		const int v = pin_vertex_[p];
		if (v >= 0 && v < (int)now_.size()) {
			now_[v] = pin_now_[p];
			if (bounded_) {
				now_[v].x = std::min(std::max(now_[v].x, bounds_min_.x), bounds_max_.x);
				now_[v].y = std::min(std::max(now_[v].y, bounds_min_.y), bounds_max_.y);
			}
		}
	}
}

void IvoryWarp::enforce_bounds() {
	if (!bounded_) {
		return;
	}
	for (Vector2 &p : now_) {
		p.x = std::min(std::max(p.x, bounds_min_.x), bounds_max_.x);
		p.y = std::min(std::max(p.y, bounds_min_.y), bounds_max_.y);
	}
}


// ----------------------------------------------------------- fold-over guard
//
// A perfectly plausible ARAP step can still become impossible when a pin is
// dragged through another part of the drawing: a triangle can pass through
// zero area and come back with the opposite winding. The picture then looks
// as though the mesh has turned inside-out. Clamping the vertices to a
// rectangle cannot prevent this because the inversion happens *inside* the
// rectangle.
//
// The guard keeps the winding of every source triangle and reserves a small
// positive area floor. It is deliberately a feasibility projection, not a
// smoothing heuristic: if a proposed iteration would cross the boundary of
// the valid set, a binary line search takes the largest valid fraction of
// that exact solver step. This preserves as much of the requested motion as
// mathematics allows and never tears a triangle through itself.
bool IvoryWarp::mesh_is_valid(const std::vector<Vector2> &points) const {
	if (triangles_.empty() || points.size() != rest_.size()) {
		return true;
	}
	const double span2 = std::max(cell_span_ * cell_span_, 1.0e-6);
	for (size_t t = 0; t < triangles_.size(); t++) {
		const auto &tri = triangles_[t];
		const Vector2 ab = points[tri[1]] - points[tri[0]];
		const Vector2 ac = points[tri[2]] - points[tri[0]];
		const double area2 = (double)ab.x * ac.y - (double)ab.y * ac.x;
		const double source = std::fabs(rest_area_[t]);
		// 1.5% of source area, with a tiny cell-relative floor. This is enough
		// to keep a triangle away from the singular zero-area configuration
		// without making ordinary pin motion visibly stiff.
		const double floor2 = std::max(source * min_area_ratio_, span2 * 1.0e-6);
		if (rest_area_[t] > 0.0) {
			if (area2 < floor2) return false;
		} else {
			if (area2 > -floor2) return false;
		}
	}
	return true;
}

void IvoryWarp::prevent_foldover(const std::vector<Vector2> &before) {
	if (triangles_.empty() || before.size() != now_.size()) {
		return;
	}
	if (mesh_is_valid(now_)) {
		last_good_ = now_;
		return;
	}
	// `before` should already be feasible. If a caller supplied a bad warm
	// start, restore the last pose actually verified sound — never the rest
	// pose outright, which would throw every pin's work away for a fault
	// that touched one triangle and make the whole artwork visibly jump.
	if (!mesh_is_valid(before)) {
		if (last_good_.size() == now_.size()) {
			now_ = last_good_;
		}
		return;
	}
	std::vector<Vector2> candidate(now_.size());
	const std::vector<Vector2> target = now_;
	double lo = 0.0;
	double hi = 1.0;
	// Ten bisection steps leave <0.1% uncertainty in the amount of the solver
	// step that can safely be taken. The check is only on the exceptional path
	// where an iteration actually threatens to invert a triangle.
	for (int iter = 0; iter < 10; iter++) {
		const double mid = (lo + hi) * 0.5;
		for (size_t i = 0; i < candidate.size(); i++) {
			candidate[i] = before[i] + (target[i] - before[i]) * mid;
		}
		if (mesh_is_valid(candidate)) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	for (size_t i = 0; i < now_.size(); i++) {
		now_[i] = before[i] + (target[i] - before[i]) * lo;
	}
	last_good_ = now_;
}

// ---------------------------------------------------------------- the solve

PackedVector2Array IvoryWarp::solve(bool settle) {
	if (!ready()) {
		return pose();
	}
	const int n = (int)rest_.size();
	const int count = (int)pin_rest_.size();

	if (count == 0) {
		now_ = rest_;
		return pose();
	}
	if (reach_dirty_) {
		build_reach();
		measure_hold();
	}
	if (count < RIGID_FROM) {
		// One pin cannot describe a rotation, so it carries the drawing — all
		// of it, including pieces with no path to the pin, which have already
		// been given a finite distance above.
		const Vector2 shift = pin_now_[0] - pin_rest_[0];
		for (int i = 0; i < n; i++) {
			now_[i] = rest_[i] + shift;
		}
		enforce_bounds();
		return pose();
	}

	for (int i = 0; i < n; i++) {
		now_[i] = warp_vertex(i);
	}

	mark_pinned();
	if (rigid_ > 0.001) {
		// ARAP is handed the MLS answer as its starting point rather than the
		// rest pose, which is the whole reason a couple of rounds is enough
		// where a cold start would need dozens. Sweeps alternate direction so
		// information does not have to travel one vertex per pass against the
		// order they are stored in.
		// Native can afford a few more local/global rounds than the fallback.
		// Three rounds during a drag remove most visible lag while eight on
		// release give the pose a proper final convergence.
		const int rounds = settle ? 8 : 3;
		for (int r = 0; r < rounds; r++) {
			fit();
			spare_ = now_;
			sweep(false, rigid_);
			prevent_foldover(spare_);
			spare_ = now_;
			sweep(true, rigid_);
			prevent_foldover(spare_);
			std::vector<Vector2> before_pins = now_;
			enforce_pins();
			// A pin is a hard control only while the requested position is
			// geometrically feasible. If it would turn a triangle inside-out,
			// project the whole last step back to the nearest safe position.
			// This makes the pin visibly stop at the deformation limit instead
			// of allowing a fold or snapping the whole artwork to the rest pose.
			prevent_foldover(before_pins);
		}
	}
	if (smoothing_ > 0.001) {
		spare_ = now_;
		smooth_by(smoothing_ * 0.5);
		smooth_by(-smoothing_ * 0.5 * INFLATE);
		prevent_foldover(spare_);
	}
	std::vector<Vector2> before_final_pins = now_;
	enforce_pins();
	prevent_foldover(before_final_pins);
	enforce_bounds();
	return pose();
}
