#include "ivory_bone.h"
#include <godot_cpp/core/math_defs.hpp>

#include <godot_cpp/variant/packed_byte_array.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

void IvoryBone::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_skeleton", "head", "tail", "parent"),
			&IvoryBone::set_skeleton);
	ClassDB::bind_method(D_METHOD("set_limits", "min_arc", "max_arc"),
			&IvoryBone::set_limits);
	ClassDB::bind_method(D_METHOD("head"), &IvoryBone::head);
	ClassDB::bind_method(D_METHOD("tail"), &IvoryBone::tail);
	ClassDB::bind_method(D_METHOD("pick", "at", "reach"), &IvoryBone::pick);
	ClassDB::bind_method(D_METHOD("swing", "index", "which", "to"),
			&IvoryBone::swing);
	ClassDB::bind_method(D_METHOD("reach", "index", "to", "passes"),
			&IvoryBone::reach);
	ClassDB::bind_method(D_METHOD("reach_pole", "index", "to", "pole", "passes"),
			&IvoryBone::reach_pole);
	ClassDB::bind_method(D_METHOD("limit_all"), &IvoryBone::limit_all);
	ClassDB::bind_method(D_METHOD("bone_count"), &IvoryBone::bone_count);
	ClassDB::bind_method(D_METHOD("lengths"), &IvoryBone::lengths);
	ClassDB::bind_method(D_METHOD("span_across", "ink", "cols", "rows",
			"origin", "cell", "a", "b"), &IvoryBone::span_across);
}

// ------------------------------------------------------------ the skeleton

void IvoryBone::set_skeleton(const PackedVector2Array &head,
		const PackedVector2Array &tail, const PackedInt32Array &parent) {
	const int n = std::min((int)head.size(), (int)tail.size());
	head_.resize(n);
	tail_.resize(n);
	parent_.resize(n);
	length_.resize(n);
	for (int i = 0; i < n; i++) {
		head_[i] = head[i];
		tail_[i] = tail[i];
		int p = i < parent.size() ? parent[i] : -1;
		// A bone may not hang from itself or from something that does not
		// exist. Both are cheap to check here and expensive to discover half
		// way down a recursive carry.
		if (p == i || p < -1 || p >= n) {
			p = -1;
		}
		parent_[i] = p;
		length_[i] = (float)(tail_[i] - head_[i]).length();
	}
	// Any parent chain that loops is cut. A loop is not a skeleton and the
	// only thing to do with one is refuse it, because every walk over it
	// otherwise runs for ever.
	for (int i = 0; i < n; i++) {
		int walk = parent_[i];
		int steps = 0;
		while (walk >= 0 && steps <= n) {
			if (walk == i) {
				parent_[i] = -1;
				break;
			}
			walk = parent_[walk];
			steps++;
		}
		if (steps > n) {
			parent_[i] = -1;
		}
	}
	if ((int)min_arc_.size() != n) {
		min_arc_.assign(n, (float)-Math_TAU);
		max_arc_.assign(n, (float)Math_TAU);
	}
	rebuild_kids();
}

void IvoryBone::set_limits(const PackedFloat32Array &min_arc,
		const PackedFloat32Array &max_arc) {
	const int n = (int)head_.size();
	min_arc_.assign(n, (float)-Math_TAU);
	max_arc_.assign(n, (float)Math_TAU);
	for (int i = 0; i < n; i++) {
		if (i < min_arc.size()) {
			min_arc_[i] = min_arc[i];
		}
		if (i < max_arc.size()) {
			max_arc_[i] = max_arc[i];
		}
	}
}

void IvoryBone::rebuild_kids() {
	const int n = (int)head_.size();
	kid_at_.assign(n + 1, 0);
	kids_.clear();
	if (n == 0) {
		return;
	}
	// Counting sort by parent: one pass to count, one to place. This is the
	// whole reason children are free to look up during a drag.
	std::vector<int32_t> count(n, 0);
	for (int i = 0; i < n; i++) {
		if (parent_[i] >= 0) {
			count[parent_[i]]++;
		}
	}
	int running = 0;
	for (int i = 0; i < n; i++) {
		kid_at_[i] = running;
		running += count[i];
	}
	kid_at_[n] = running;
	kids_.assign(running, -1);
	std::vector<int32_t> fill = count;
	for (int i = 0; i < n; i++) {
		fill[i] = kid_at_[i];
	}
	for (int i = 0; i < n; i++) {
		const int p = parent_[i];
		if (p >= 0) {
			kids_[fill[p]++] = i;
		}
	}
}

PackedVector2Array IvoryBone::head() const {
	PackedVector2Array out;
	out.resize((int)head_.size());
	for (int i = 0; i < (int)head_.size(); i++) {
		out[i] = head_[i];
	}
	return out;
}

PackedVector2Array IvoryBone::tail() const {
	PackedVector2Array out;
	out.resize((int)tail_.size());
	for (int i = 0; i < (int)tail_.size(); i++) {
		out[i] = tail_[i];
	}
	return out;
}

PackedFloat32Array IvoryBone::lengths() const {
	PackedFloat32Array out;
	out.resize((int)length_.size());
	for (int i = 0; i < (int)length_.size(); i++) {
		out[i] = length_[i];
	}
	return out;
}

// ------------------------------------------------------------------ picking

int IvoryBone::pick(const Vector2 &at, double reach) const {
	const double limit = reach * reach;
	double best = limit;
	int found = -1;
	for (int i = 0; i < (int)head_.size(); i++) {
		// Tails first, so a tie at a joint two bones share resolves onto the
		// parent's tail. See the header for why that is the end a person
		// means.
		const double dt = (double)(tail_[i] - at).length_squared();
		if (dt <= best) {
			best = dt;
			found = i * 2 + 1;
		}
	}
	for (int i = 0; i < (int)head_.size(); i++) {
		const double dh = (double)(head_[i] - at).length_squared();
		if (dh < best) {
			best = dh;
			found = i * 2 + 0;
		}
	}
	return found;
}

// ----------------------------------------------------------------- carrying

void IvoryBone::carry(int index, const Vector2 &pivot, double turn) {
	if (std::fabs(turn) < 1.0e-9) {
		return;
	}
	const double c = std::cos(turn);
	const double s = std::sin(turn);
	stack_.clear();
	stack_.push_back(index);
	while (!stack_.empty()) {
		const int at = stack_.back();
		stack_.pop_back();
		Vector2 h = head_[at] - pivot;
		Vector2 t = tail_[at] - pivot;
		head_[at] = pivot + Vector2((real_t)(h.x * c - h.y * s),
				(real_t)(h.x * s + h.y * c));
		tail_[at] = pivot + Vector2((real_t)(t.x * c - t.y * s),
				(real_t)(t.x * s + t.y * c));
		for (int k = kid_at_[at]; k < kid_at_[at + 1]; k++) {
			stack_.push_back(kids_[k]);
		}
	}
}

void IvoryBone::reseat(int index) {
	// Children hang off their parent's tail. After a solve has moved the
	// parents, each child is translated so its head sits back on that tail —
	// translated, not re-solved, so the joint closes exactly.
	stack_.clear();
	for (int k = kid_at_[index]; k < kid_at_[index + 1]; k++) {
		stack_.push_back(kids_[k]);
	}
	while (!stack_.empty()) {
		const int at = stack_.back();
		stack_.pop_back();
		const Vector2 want = tail_[parent_[at]];
		const Vector2 shift = want - head_[at];
		if (shift.length_squared() > 1.0e-12) {
			head_[at] += shift;
			tail_[at] += shift;
		}
		for (int k = kid_at_[at]; k < kid_at_[at + 1]; k++) {
			stack_.push_back(kids_[k]);
		}
	}
}

// ----------------------------------------------------------------- swinging

void IvoryBone::swing(int index, int which, const Vector2 &to) {
	if (index < 0 || index >= (int)head_.size()) {
		return;
	}
	if (which == 0) {
		// The head is being dragged, and a bone with a parent cannot move its
		// head independently — that end belongs to the joint. So the whole
		// bone is translated only when it is a root; otherwise the drag is
		// read as a swing of the parent, which is what the finger meant.
		if (parent_[index] >= 0) {
			swing(parent_[index], 1, to);
			return;
		}
		const Vector2 shift = to - head_[index];
		stack_.clear();
		stack_.push_back(index);
		while (!stack_.empty()) {
			const int at = stack_.back();
			stack_.pop_back();
			head_[at] += shift;
			tail_[at] += shift;
			for (int k = kid_at_[at]; k < kid_at_[at + 1]; k++) {
				stack_.push_back(kids_[k]);
			}
		}
		return;
	}
	const Vector2 pivot = head_[index];
	const Vector2 was = tail_[index] - pivot;
	const Vector2 want = to - pivot;
	if (was.length_squared() < 1.0e-12 || want.length_squared() < 1.0e-12) {
		return;
	}
	// The bone keeps its length. Only the direction is taken from the finger,
	// which is what makes a drag a rotation rather than a stretch — a bone
	// that changed length under the finger would change the drawing's
	// proportions every time it was posed.
	const double turn = (double)want.angle() - (double)was.angle();
	carry(index, pivot, turn);
}

// ------------------------------------------------------------------ reaching

void IvoryBone::collect_chain(int index) const {
	chain_.clear();
	int at = index;
	int guard = 0;
	while (at >= 0 && guard <= (int)head_.size()) {
		chain_.push_back(at);
		at = parent_[at];
		guard++;
	}
	std::reverse(chain_.begin(), chain_.end());
}

bool IvoryBone::reach(int index, const Vector2 &to, int passes) {
	if (index < 0 || index >= (int)head_.size()) {
		return false;
	}
	if (parent_[index] < 0) {
		return false;
	}
	collect_chain(index);
	if (chain_.size() < 2) {
		return false;
	}
	if (chain_.size() == 2) {
		two_bone(chain_[0], chain_[1], to);
	} else {
		fabrik(index, to, passes);
	}
	reseat(chain_[0]);
	return true;
}

bool IvoryBone::reach_pole(int index, const Vector2 &to, const Vector2 &pole, int passes) {
	if (index < 0 || index >= (int)head_.size() || parent_[index] < 0) return false;
	collect_chain(index);
	if (chain_.size() < 2) return false;
	if (chain_.size() == 2) {
		two_bone(chain_[0], chain_[1], to, pole);
	} else {
		fabrik(index, to, passes);
		// FABRIK is kept for long chains. A pole is applied only as a stable
		// side hint to the first bend; the rigid chain remains length-preserving.
		const int upper = chain_[0], lower = chain_[1];
		const Vector2 root = head_[upper];
		const Vector2 axis = to - root;
		const double al2 = axis.length_squared();
		if (al2 > 1.0e-8 && std::isfinite(pole.x) && std::isfinite(pole.y)) {
			const double desired = (double)axis.cross(pole - root);
			const double current = (double)axis.cross(tail_[upper] - root);
			const double band = std::sqrt(al2) * 0.0025;
			if (std::abs(desired) > band && std::abs(current) > band &&
					((desired > 0.0) != (current > 0.0))) {
				// Do not mirror a single joint. Carrying the complete descendant
				// chain preserves every attachment and prevents a visible crack.
				const Vector2 u = axis / (real_t)std::sqrt(al2);
				for (size_t ci = 1; ci < chain_.size(); ++ci) {
					const int b = chain_[ci];
					Vector2 h = head_[b] - root, t = tail_[b] - root;
					double ha = h.dot(u), ta = t.dot(u);
					Vector2 hp = root + u * (real_t)ha, tp = root + u * (real_t)ta;
					head_[b] = hp + (hp - head_[b]);
					tail_[b] = tp + (tp - tail_[b]);
				}
			}
		}
	}
	reseat(chain_[0]);
	return true;
}

void IvoryBone::two_bone(int upper, int lower, const Vector2 &to, const Vector2 &pole) {
	// Closed form. Two links and a target is a triangle, and a triangle has
	// an exact answer — no iteration, no tuning, and the same answer every
	// time for the same input. This is most of what anybody ever rigs: an
	// upper arm and a forearm, a thigh and a shin.
	const Vector2 root = head_[upper];
	const double l1 = (double)length_[upper];
	const double l2 = (double)length_[lower];
	Vector2 span = to - root;
	double dist = (double)span.length();
	if (dist < 1.0e-6) {
		return;
	}
	// Out of range in either direction: the arm goes straight at it, or folds
	// as far as it can. Both are what a real limb does and both are better
	// than refusing to move.
	dist = std::min(std::max(dist, std::fabs(l1 - l2) + 1.0e-4),
			l1 + l2 - 1.0e-4);
	const Vector2 dir = span / (real_t)span.length();
	// Which side the elbow was on before, so it stays on that side. Losing
	// this is the classic inverse-kinematics flip: the elbow snaps through
	// the shoulder the first time the target crosses the line.
	const Vector2 was_elbow = tail_[upper] - root;
	const double old_side = (double)(dir.x * was_elbow.y - dir.y * was_elbow.x);
	const bool have_pole = std::isfinite(pole.x) && std::isfinite(pole.y);
	const double pole_side = have_pole ? (double)(dir.x * (pole - root).y - dir.y * (pole - root).x) : 0.0;
	// The pole is authoritative only when it is meaningfully off the target
	// axis. Around the straight pose the cross product approaches zero and a
	// single digitizer pixel can change its sign; using it there is exactly the
	// midpoint/two-pole tremor that breaks a drawing. Keep the previous elbow
	// side inside a hysteresis band, then allow an intentional pole change.
	const double hysteresis = std::max(0.75, dist * 0.0125);
	double side = old_side;
	if (have_pole && std::abs(pole_side) > hysteresis) side = pole_side;
	if (std::abs(side) < 1.0e-7) side = 1.0;
	const double sign = side < 0.0 ? -1.0 : 1.0;
	const double cos_a = std::min(std::max(
			(l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0), 1.0);
	const double a = std::acos(cos_a) * sign;
	const double base = (double)dir.angle();
	const Vector2 elbow = root + Vector2(
			(real_t)(std::cos(base + a) * l1),
			(real_t)(std::sin(base + a) * l1));

	// Applied as turns rather than as positions, so that everything hanging
	// off either bone is carried by the same rotation and no joint opens.
	const double up_was = (double)(tail_[upper] - head_[upper]).angle();
	const double up_now = (double)(elbow - root).angle();
	carry(upper, root, up_now - up_was);
	const Vector2 hand = root + dir * (real_t)dist;
	const double low_was = (double)(tail_[lower] - head_[lower]).angle();
	const double low_now = (double)(hand - head_[lower]).angle();
	carry(lower, head_[lower], low_now - low_was);
}

void IvoryBone::fabrik(int p_index, const Vector2 &to, int passes) {
	// The chain was collected by the caller, so the index is not read again
	// here. Named and discarded rather than left unnamed, because the
	// signature is part of the class's story and losing the name loses it.
	(void)p_index;
	// Forward And Backward Reaching Inverse Kinematics (Aristidou & Lasenby,
	// 2011). Positions only, no angles, no Jacobian, no matrix: walk down the
	// chain putting each joint on the line to the last one at its own link's
	// distance, then walk back up doing the same from the fixed root. It
	// converges in a handful of passes and it never produces the wild
	// overshoot that a Jacobian solver does near a singularity.
	const int links = (int)chain_.size();
	joint_.resize(links + 1);
	link_.resize(links);
	for (int i = 0; i < links; i++) {
		joint_[i] = head_[chain_[i]];
		link_[i] = length_[chain_[i]];
	}
	joint_[links] = tail_[chain_[links - 1]];
	const Vector2 anchor = joint_[0];

	double total = 0.0;
	for (int i = 0; i < links; i++) {
		total += (double)link_[i];
	}
	const double away = (double)(to - anchor).length();
	if (away > total) {
		// Beyond reach: the chain simply straightens at it. Iterating would
		// spend passes converging on exactly this.
		const Vector2 dir = (to - anchor).normalized();
		for (int i = 1; i <= links; i++) {
			joint_[i] = joint_[i - 1] + dir * link_[i - 1];
		}
	} else {
		const int rounds = std::min(std::max(passes, 1), 8);
		for (int r = 0; r < rounds; r++) {
			// Backwards: the end goes to the target, everything follows.
			joint_[links] = to;
			for (int i = links - 1; i >= 0; i--) {
				Vector2 span = joint_[i] - joint_[i + 1];
				const double len = (double)span.length();
				if (len < 1.0e-9) {
					span = Vector2(1.0f, 0.0f);
				} else {
					span /= (real_t)len;
				}
				joint_[i] = joint_[i + 1] + span * link_[i];
			}
			// Forwards: the root goes back where it belongs, everything
			// follows. After both halves the chain has the right link lengths
			// and both ends where they should be.
			joint_[0] = anchor;
			for (int i = 0; i < links; i++) {
				Vector2 span = joint_[i + 1] - joint_[i];
				const double len = (double)span.length();
				if (len < 1.0e-9) {
					span = Vector2(1.0f, 0.0f);
				} else {
					span /= (real_t)len;
				}
				joint_[i + 1] = joint_[i] + span * link_[i];
			}
			if ((double)(joint_[links] - to).length() < 0.05) {
				break;
			}
		}
	}

	// --- the bend each joint had, restored ---
	//
	// FABRIK solves positions and knows nothing about which side a joint
	// bends to. For two links the closed form above keeps the elbow where it
	// was; for three or more, nothing did, and a long chain would flip a
	// joint inside out partway through a drag — a knee bending backwards for
	// one frame and then staying there. It is the single worst-looking thing
	// a rig can do and it happened whenever the target crossed the line the
	// chain was straight along.
	//
	// The fix is not to constrain the solve, which would fight it. It is to
	// notice afterwards: each joint's bend has a sign, the sign is the cross
	// product of the two links meeting at it, and a sign that has flipped is
	// a joint that has turned through straight. Reflecting that joint back
	// across the line joining its neighbours restores the side without
	// changing either link's length or where the chain ends — so the solve is
	// preserved exactly and only the choice between its two mirror answers is
	// corrected.
	for (int i = 1; i < links; i++) {
		const Vector2 &before = joint_[i - 1];
		const Vector2 &after = joint_[i + 1];
		const Vector2 &at = joint_[i];
		const Vector2 in_dir = at - before;
		const Vector2 out_dir = after - at;
		const double now_side = (double)in_dir.x * (double)out_dir.y
				- (double)in_dir.y * (double)out_dir.x;
		// What it was, from the skeleton as it stands before this write-back.
		const int b = chain_[i];
		const int p = chain_[i - 1];
		const Vector2 was_in = tail_[p] - head_[p];
		const Vector2 was_out = tail_[b] - head_[b];
		const double was_side = (double)was_in.x * (double)was_out.y
				- (double)was_in.y * (double)was_out.x;
		// A joint that was straight has no side to preserve, and forcing one
		// on it would introduce a bend nobody asked for.
		if (std::fabs(was_side) < 1.0e-6 || std::fabs(now_side) < 1.0e-6) {
			continue;
		}
		if ((was_side > 0.0) == (now_side > 0.0)) {
			continue;
		}
		// Reflected across the line from `before` to `after`.
		Vector2 axis = after - before;
		const double len = (double)axis.length();
		if (len < 1.0e-9) {
			continue;
		}
		axis /= (real_t)len;
		const Vector2 gap = at - before;
		const double along = (double)gap.x * (double)axis.x
				+ (double)gap.y * (double)axis.y;
		const Vector2 on_axis = before + axis * (real_t)along;
		joint_[i] = on_axis + (on_axis - at);
	}

	// Written back as rotations, from the root down, so descendants that are
	// not on this chain are carried with the bone they hang from.
	for (int i = 0; i < links; i++) {
		const int b = chain_[i];
		const double was = (double)(tail_[b] - head_[b]).angle();
		const double now = (double)(joint_[i + 1] - joint_[i]).angle();
		carry(b, head_[b], now - was);
		// The head is put exactly on the solved joint. It will already be
		// within floating point of it; setting it removes the drift that
		// otherwise accumulates over a long drag.
		const Vector2 fix = joint_[i] - head_[b];
		if (fix.length_squared() > 1.0e-12) {
			stack_.clear();
			stack_.push_back(b);
			while (!stack_.empty()) {
				const int at = stack_.back();
				stack_.pop_back();
				head_[at] += fix;
				tail_[at] += fix;
				for (int k = kid_at_[at]; k < kid_at_[at + 1]; k++) {
					stack_.push_back(kids_[k]);
				}
			}
		}
	}
}

// ------------------------------------------------------------------- limits

void IvoryBone::limit_all() {
	const int n = (int)head_.size();
	for (int i = 0; i < n; i++) {
		const int p = parent_[i];
		if (p < 0) {
			continue;
		}
		const float lo = i < (int)min_arc_.size() ? min_arc_[i]
				: (float)-Math_TAU;
		const float hi = i < (int)max_arc_.size() ? max_arc_[i]
				: (float)Math_TAU;
		if (lo <= (float)-Math_TAU + 0.001f && hi >= (float)Math_TAU - 0.001f) {
			continue;
		}
		double rel = (double)(tail_[i] - head_[i]).angle()
				- (double)(tail_[p] - head_[p]).angle();
		while (rel > PI) {
			rel -= Math_TAU;
		}
		while (rel < -PI) {
			rel += Math_TAU;
		}
		const double held = std::min(std::max(rel, (double)lo), (double)hi);
		if (std::fabs(held - rel) > 1.0e-6) {
			carry(i, head_[i], held - rel);
		}
	}
}

// -------------------------------------------------------- adaptive sizing

double IvoryBone::span_across(const PackedByteArray &ink, int cols, int rows,
		const Vector2 &origin, const Vector2 &cell, const Vector2 &a,
		const Vector2 &b) const {
	if (cols <= 0 || rows <= 0 || ink.size() < cols * rows) {
		return 0.0;
	}
	if (cell.x <= 0.0f || cell.y <= 0.0f) {
		return 0.0;
	}
	Vector2 run = b - a;
	const double len = (double)run.length();
	if (len < 1.0e-6) {
		return 0.0;
	}
	run /= (real_t)len;
	const Vector2 side(-run.y, run.x);
	// How far out to look: half the drawing's own diagonal is always enough
	// and costs nothing when the ink stops before then.
	const double furthest = std::sqrt((double)(cols * cell.x) * (cols * cell.x)
			+ (double)(rows * cell.y) * (rows * cell.y)) * 0.5;
	const double step = std::max((double)std::min(cell.x, cell.y), 0.5);

	// Sampled at a fixed number of stations along the bone and the *median*
	// taken, not the mean. A limb that overlaps the body at one end would
	// drag a mean out to the width of the body; the median ignores a minority
	// of wide readings, which is exactly the shape of that error.
	const int stations = 11;
	std::vector<double> widths;
	widths.reserve(stations);
	for (int s = 0; s < stations; s++) {
		const double t = (double)(s + 1) / (double)(stations + 1);
		const Vector2 mid = a + run * (real_t)(len * t);
		double out[2] = { 0.0, 0.0 };
		for (int way = 0; way < 2; way++) {
			const double sign = way == 0 ? 1.0 : -1.0;
			double gone = 0.0;
			double last_ink = 0.0;
			// A short gap in the ink — a highlight, a gap between two
			// strokes — is stepped over rather than treated as the edge.
			double gap = 0.0;
			while (gone <= furthest) {
				const Vector2 at = mid + side * (real_t)(sign * gone);
				const int cx = (int)std::floor((double)(at.x - origin.x)
						/ (double)cell.x);
				const int cy = (int)std::floor((double)(at.y - origin.y)
						/ (double)cell.y);
				if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) {
					break;
				}
				if (ink[cy * cols + cx] != 0) {
					last_ink = gone;
					gap = 0.0;
				} else {
					gap += step;
					if (gap > step * 3.0) {
						break;
					}
				}
				gone += step;
			}
			out[way] = last_ink;
		}
		const double here = out[0] + out[1];
		if (here > 0.0) {
			widths.push_back(here * 0.5);
		}
	}
	if (widths.empty()) {
		return 0.0;
	}
	std::sort(widths.begin(), widths.end());
	return widths[widths.size() / 2];
}
