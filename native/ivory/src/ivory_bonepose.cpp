#include "ivory_bonepose.h"

#include <algorithm>
#include <cmath>

namespace godot {

static constexpr double EPS = 1e-12;

void IvoryBonePose::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_skeleton", "rest", "parents"), &IvoryBonePose::set_skeleton);
	ClassDB::bind_method(D_METHOD("joint_count"), &IvoryBonePose::joint_count);
	ClassDB::bind_method(D_METHOD("positions"), &IvoryBonePose::positions);
	ClassDB::bind_method(D_METHOD("set_positions", "p"), &IvoryBonePose::set_positions);
	ClassDB::bind_method(D_METHOD("reset"), &IvoryBonePose::reset);
	ClassDB::bind_method(D_METHOD("descendants", "joint"), &IvoryBonePose::descendants);
	ClassDB::bind_method(D_METHOD("parent_of", "joint"), &IvoryBonePose::parent_of);
	ClassDB::bind_method(D_METHOD("is_end", "joint"), &IvoryBonePose::is_end);
	ClassDB::bind_method(D_METHOD("pin", "joint"), &IvoryBonePose::pin);
	ClassDB::bind_method(D_METHOD("unpin", "joint"), &IvoryBonePose::unpin);
	ClassDB::bind_method(D_METHOD("unpin_all"), &IvoryBonePose::unpin_all);
	ClassDB::bind_method(D_METHOD("is_pinned", "joint"), &IvoryBonePose::is_pinned);
	ClassDB::bind_method(D_METHOD("pinned_count"), &IvoryBonePose::pinned_count);
	ClassDB::bind_method(D_METHOD("drag", "joint", "to", "iterations"), &IvoryBonePose::drag, DEFVAL(24));
	ClassDB::bind_method(D_METHOD("rotate_about", "joint", "radians"), &IvoryBonePose::rotate_about);
	ClassDB::bind_method(D_METHOD("rest_lengths"), &IvoryBonePose::rest_lengths);
	ClassDB::bind_method(D_METHOD("length_error"), &IvoryBonePose::length_error);
	ClassDB::bind_method(D_METHOD("last_step"), &IvoryBonePose::last_step);
	ClassDB::bind_method(D_METHOD("set_stiffness", "v"), &IvoryBonePose::set_stiffness);
	ClassDB::bind_method(D_METHOD("stiffness"), &IvoryBonePose::stiffness);
	ClassDB::bind_method(D_METHOD("configure_stability", "deadband_px", "follow_seconds", "max_step_px"), &IvoryBonePose::configure_stability);
	ClassDB::bind_method(D_METHOD("stability_report"), &IvoryBonePose::stability_report);
}

void IvoryBonePose::set_stiffness(double v) { stiff_ = std::clamp(v, 0.05, 1.0); }

void IvoryBonePose::configure_stability(double deadband_px, double follow_seconds, double max_step_px) {
	stable_deadband_ = std::clamp(deadband_px, 0.0, 8.0);
	stable_follow_ = std::clamp(follow_seconds, 0.005, 0.18);
	stable_max_step_ = std::clamp(max_step_px, 1.0, 10000.0);
	// The guard's thresholds just changed, so any joint's remembered target
	// was measured against the old ones. Start every joint fresh rather than
	// have it re-use a target that no longer means what it did.
	std::fill(stable_ready_.begin(), stable_ready_.end(), (uint8_t)0);
}

// A joint's remembered drag target is only meaningful while that joint is
// moving under its own filtered drag. The instant it moves for any other
// reason — carried along by a parent's drag, turned by the ring, or written
// wholesale by `set_positions` — the remembered target is stale, and the
// next direct drag on that joint must snap cleanly to where it now sits
// rather than crawl there from a target that no longer applies.
void IvoryBonePose::invalidate_stability(int joint) {
	if (joint < 0 || joint >= (int)stable_ready_.size()) return;
	stable_ready_[(size_t)joint] = 0;
}

Dictionary IvoryBonePose::stability_report() const {
	Dictionary out;
	out["deadband_px"] = stable_deadband_;
	out["follow_seconds"] = stable_follow_;
	out["max_step_px"] = stable_max_step_;
	out["last_step"] = last_step_;
	out["length_error"] = length_error();
	out["pinned"] = pinned_count();
	out["stable"] = last_step_ <= 1.0e-4 && length_error() <= 1.0e-3;
	return out;
}


bool IvoryBonePose::set_skeleton(const PackedVector2Array &rest, const PackedInt32Array &parents) {
	rest_.clear();
	now_.clear();
	parent_.clear();
	child_.clear();
	length_.clear();
	pinned_.clear();
	order_.clear();
	const int n = rest.size();
	if (n < 1 || parents.size() != n) return false;

	for (int i = 0; i < n; ++i) {
		const int p = parents[i];
		if (p < -1 || p >= n || p == i) return false;
	}
	// No cycles. A cycle would make the descendant walk below run for ever,
	// and a rig arriving from a file cannot be assumed to be sound.
	for (int i = 0; i < n; ++i) {
		int walk = parents[i];
		int steps = 0;
		while (walk >= 0) {
			if (walk == i) return false;
			walk = parents[walk];
			if (++steps > n) return false;
		}
	}

	for (int i = 0; i < n; ++i) {
		rest_.push_back(rest[i]);
		parent_.push_back(parents[i]);
	}
	now_ = rest_;
	child_.assign((size_t)n, {});
	for (int i = 0; i < n; ++i) {
		if (parent_[(size_t)i] >= 0) child_[(size_t)parent_[(size_t)i]].push_back(i);
	}
	length_.assign((size_t)n, 0.0);
	for (int i = 0; i < n; ++i) {
		const int p = parent_[(size_t)i];
		if (p >= 0) length_[(size_t)i] = (double)rest_[i].distance_to(rest_[p]);
	}
	pinned_.assign((size_t)n, 0);
	stable_target_.assign((size_t)n, Vector2());
	stable_ready_.assign((size_t)n, 0);

	// Parents before children, so a single pass down the list can carry a
	// transform through the whole hierarchy without revisiting anything.
	std::vector<int> stack;
	for (int i = 0; i < n; ++i) {
		if (parent_[(size_t)i] < 0) stack.push_back(i);
	}
	while (!stack.empty()) {
		const int j = stack.back();
		stack.pop_back();
		order_.push_back(j);
		for (int c : child_[(size_t)j]) stack.push_back(c);
	}
	return (int)order_.size() == n;
}

PackedVector2Array IvoryBonePose::positions() const {
	PackedVector2Array out;
	for (const Vector2 &v : now_) out.append(v);
	return out;
}

void IvoryBonePose::set_positions(const PackedVector2Array &p) {
	const int n = std::min((int)now_.size(), (int)p.size());
	for (int i = 0; i < n; ++i) now_[(size_t)i] = p[i];
	// Written wholesale from outside — every joint's drag filter is stale.
	std::fill(stable_ready_.begin(), stable_ready_.end(), (uint8_t)0);
}

void IvoryBonePose::reset() {
	now_ = rest_;
	last_step_ = 0.0;
	std::fill(stable_ready_.begin(), stable_ready_.end(), (uint8_t)0);
	std::fill(stable_target_.begin(), stable_target_.end(), Vector2());
}

PackedInt32Array IvoryBonePose::descendants(int joint) const {
	PackedInt32Array out;
	if (joint < 0 || joint >= (int)now_.size()) return out;
	std::vector<int> stack(child_[(size_t)joint].begin(), child_[(size_t)joint].end());
	while (!stack.empty()) {
		const int j = stack.back();
		stack.pop_back();
		out.append(j);
		for (int c : child_[(size_t)j]) stack.push_back(c);
	}
	return out;
}

int IvoryBonePose::parent_of(int joint) const {
	if (joint < 0 || joint >= (int)parent_.size()) return -1;
	return parent_[(size_t)joint];
}

bool IvoryBonePose::is_end(int joint) const {
	if (joint < 0 || joint >= (int)child_.size()) return false;
	return child_[(size_t)joint].empty();
}

void IvoryBonePose::pin(int joint) {
	if (joint < 0 || joint >= (int)pinned_.size()) return;
	pinned_[(size_t)joint] = 1;
}

void IvoryBonePose::unpin(int joint) {
	if (joint < 0 || joint >= (int)pinned_.size()) return;
	pinned_[(size_t)joint] = 0;
}

void IvoryBonePose::unpin_all() { std::fill(pinned_.begin(), pinned_.end(), 0); }

bool IvoryBonePose::is_pinned(int joint) const {
	if (joint < 0 || joint >= (int)pinned_.size()) return false;
	return pinned_[(size_t)joint] != 0;
}

int IvoryBonePose::pinned_count() const {
	int n = 0;
	for (uint8_t p : pinned_) n += p ? 1 : 0;
	return n;
}

void IvoryBonePose::carry_descendants(int joint, const Vector2 &by) {
	PackedInt32Array kids = descendants(joint);
	for (int k = 0; k < kids.size(); ++k) {
		const int j = kids[k];
		if (pinned_[(size_t)j]) continue;
		now_[(size_t)j] += by;
		// Moved passively, by its parent's drag — not by a drag of its own.
		invalidate_stability(j);
	}
}

// The relaxation. Every bone is pulled back towards its rest length by moving
// its two ends towards or away from each other, with a pinned end taking none
// of the movement.
//
// ## Why the direction alternates
//
// This is the shivering joint, and it is worth being precise about.
//
// A single pass over the bones in a fixed order leaves the last bone carrying
// whatever error the ones before it did not absorb. With a fixed pass count
// that residue never reaches zero, and its size depends on where the drag
// started — so between one frame and the next, the last joint in the list is
// pushed a little one way and then a little the other. On screen that is a
// joint that will not sit still.
//
// Alternating the direction each iteration means no bone is permanently last;
// the error is shared out instead of accumulating at one end. Running until
// the largest movement falls below a threshold, rather than for a fixed count,
// means the residue is actually gone rather than merely small. Together they
// make the same input produce the same output, which is what "it stopped
// shivering" means in arithmetic.
double IvoryBonePose::relax(int iterations) {
	const int n = (int)now_.size();
	double biggest = 0.0;
	for (int it = 0; it < iterations; ++it) {
		double step = 0.0;
		flip_ = !flip_;
		for (int idx = 0; idx < n; ++idx) {
			const int i = flip_ ? order_[(size_t)idx] : order_[(size_t)(n - 1 - idx)];
			const int p = parent_[(size_t)i];
			if (p < 0) continue;
			const double want = length_[(size_t)i];
			if (want < EPS) continue;
			Vector2 d = now_[(size_t)i] - now_[(size_t)p];
			const double have = d.length();
			if (have < EPS) {
				// Two joints exactly on top of each other have no direction to
				// separate along. The rest direction is the only honest guess.
				d = rest_[(size_t)i] - rest_[(size_t)p];
				if (d.length() < EPS) continue;
			}
			const double err = (have - want) / std::max(have, EPS);
			const Vector2 fix = d * (real_t)(err * stiff_);

			const bool hold_i = pinned_[(size_t)i] != 0;
			const bool hold_p = pinned_[(size_t)p] != 0;
			if (hold_i && hold_p) continue;
			if (hold_i) {
				now_[(size_t)p] += fix;
				step = std::max(step, (double)fix.length());
			} else if (hold_p) {
				now_[(size_t)i] -= fix;
				step = std::max(step, (double)fix.length());
			} else {
				now_[(size_t)i] -= fix * 0.5f;
				now_[(size_t)p] += fix * 0.5f;
				step = std::max(step, (double)fix.length() * 0.5);
			}
		}
		biggest = step;
		// Settled. The threshold is a ten-millionth of a pixel rather than
		// something merely invisible, and that is deliberate: a drag is
		// re-solved every frame from wherever the last one left off, so a
		// residue of a hundred-thousandth is not a rounding error that stays
		// put — it is a difference between one frame's answer and the next,
		// which is exactly what a joint that will not sit still looks like.
		// Since the reaching pass above does the real work, the extra
		// tightness costs a handful of passes over a short list.
		if (step < 1e-9) break;
	}
	return biggest;
}

// Forward-and-backward reaching along the chain from the dragged joint to its
// anchor, before the general relaxation runs.
//
// ## Why this and not more relaxation
//
// Projecting each bone back to its rest length, one bone at a time, is the
// obvious way to keep a chain together and it is what this class did. It is
// also, on a long chain, very slow to converge: each pass moves information
// one bone along, so a twenty-joint arm needs on the order of twenty passes
// just to hear about the drag at the far end, and hundreds to settle. Two
// hundred passes left the chain visibly wrong — half a pixel of length error
// and still moving a third of a pixel per pass.
//
// Reaching solves the same chain in two passes and a handful of rounds,
// because each pass walks the whole chain rather than one bone. Backward: put
// the dragged joint on the finger and lay the chain out behind it at correct
// lengths. Forward: put the anchor back where it belongs and lay the chain out
// again. Repeat until it stops moving, which for a chain is three or four
// rounds rather than hundreds.
//
// The anchor is the root, or the first pinned joint on the way to it —
// whichever comes first. That is what makes a pin further up the arm behave
// the way an artist expects: everything between the finger and the pin
// arranges itself, and nothing beyond the pin moves at all.
void IvoryBonePose::reach(int joint, const Vector2 &to, int rounds) {
	std::vector<int> path;
	int walk = joint;
	while (walk >= 0) {
		path.push_back(walk);
		if (pinned_[(size_t)walk] && walk != joint) break;
		walk = parent_[(size_t)walk];
	}
	if (path.size() < 2) return;
	const int anchor = path.back();
	const Vector2 anchor_home = now_[(size_t)anchor];

	for (int r = 0; r < rounds; ++r) {
		// Backward: from the finger towards the anchor.
		now_[(size_t)path[0]] = to;
		for (size_t k = 1; k < path.size(); ++k) {
			const int child = path[k - 1];
			const int up = path[k];
			const double want = length_[(size_t)child];
			Vector2 d = now_[(size_t)up] - now_[(size_t)child];
			double have = d.length();
			if (have < EPS) {
				d = rest_[(size_t)up] - rest_[(size_t)child];
				have = d.length();
				if (have < EPS) continue;
			}
			now_[(size_t)up] = now_[(size_t)child] + d * (real_t)(want / have);
		}
		// Forward: the anchor is not negotiable, so put it back and lay the
		// chain out from there.
		now_[(size_t)anchor] = anchor_home;
		for (size_t k = path.size() - 1; k > 0; --k) {
			const int up = path[k];
			const int child = path[k - 1];
			const double want = length_[(size_t)child];
			Vector2 d = now_[(size_t)child] - now_[(size_t)up];
			double have = d.length();
			if (have < EPS) {
				d = rest_[(size_t)child] - rest_[(size_t)up];
				have = d.length();
				if (have < EPS) continue;
			}
			now_[(size_t)child] = now_[(size_t)up] + d * (real_t)(want / have);
		}
	}
}

Dictionary IvoryBonePose::drag(int joint, const Vector2 &to, int iterations) {
	Dictionary out;
	out["ok"] = false;
	out["blocked"] = false;
	if (joint < 0 || joint >= (int)now_.size()) return out;

	if (pinned_[(size_t)joint]) {
		// Pinned means pinned. Reporting it rather than quietly ignoring the
		// drag lets the room say so instead of appearing not to respond.
		out["ok"] = true;
		out["blocked"] = true;
		out["iterations"] = 0;
		out["max_step"] = 0.0;
		return out;
	}

	const Vector2 was = now_[(size_t)joint];

	// The guard: a deadband against sub-pixel jitter, and a hard cap on how
	// far one call may move the remembered target. `goal`, not the raw
	// finger position `to`, is what actually moves from here on — carrying
	// the descendants, reaching the chain, and the final placement all use
	// it, or the guard would be computed and then ignored, which is the same
	// as not having it.
	if (!stable_ready_[(size_t)joint]) {
		stable_target_[(size_t)joint] = to;
		stable_ready_[(size_t)joint] = 1;
	}
	Vector2 delta = to - stable_target_[(size_t)joint];
	if ((double)delta.length() > stable_deadband_) {
		const double dl = delta.length();
		if (dl > stable_max_step_) stable_target_[(size_t)joint] += delta * (real_t)(stable_max_step_ / dl);
		else stable_target_[(size_t)joint] = to;
	}
	const Vector2 goal = stable_target_[(size_t)joint];

	now_[(size_t)joint] = goal;
	// The limb below travels with the joint, by the same guarded amount,
	// before anything is relaxed. Carrying it by the raw finger delta while
	// the joint itself only moved by the guarded amount would tear the limb
	// away from the joint by exactly whatever the guard just held back —
	// worst on the very jumps the guard exists to catch.
	carry_descendants(joint, goal - was);

	// The dragged joint is held for the duration of the solve, so the
	// (guarded) target wins and the chain arranges itself around it.
	// Rounds, not passes: each round is a full walk up the chain and back, so
	// twenty-four of them settle a twenty-joint arm to below what a float can
	// represent. Eight left a thousandth of a pixel of residue, and a residue
	// that changes between frames is the thing that trembles.
	reach(joint, goal, 24);
	// Reaching ends with a forward pass from the anchor, which leaves the
	// dragged joint a hair off its target — the chain may simply be too short
	// to arrive. The target is what the joint is meant to be sitting on, so
	// it wins: the joint is put exactly on it and the relaxation below
	// arranges the rest around that.
	now_[(size_t)joint] = goal;
	const bool was_pinned = pinned_[(size_t)joint] != 0;
	pinned_[(size_t)joint] = 1;
	// Deterministic from here. `flip_` decides which end of the list a pass
	// starts from, and left as it was between calls it made two identical
	// drags produce answers a few millionths of a pixel apart — enough for a
	// joint to be seen to twitch while a finger was held perfectly still.
	flip_ = false;
	last_step_ = relax(std::clamp(iterations, 1, 400));
	pinned_[(size_t)joint] = was_pinned ? 1 : 0;

	out["ok"] = true;
	out["iterations"] = iterations;
	out["max_step"] = last_step_;
	out["length_error"] = length_error();
	return out;
}

// The ring: turn everything below this joint about it.
Dictionary IvoryBonePose::rotate_about(int joint, double radians) {
	Dictionary out;
	out["ok"] = false;
	out["turned"] = 0;
	if (joint < 0 || joint >= (int)now_.size()) return out;
	if (!std::isfinite(radians)) return out;

	const Vector2 centre = now_[(size_t)joint];
	const double c = std::cos(radians), s = std::sin(radians);

	// Only descendants. Nothing above the joint moves, ever — turning an elbow
	// must not move the shoulder, and a ring that did would be a way to pull a
	// limb off rather than a way to pose one.
	PackedInt32Array kids = descendants(joint);

	// A pinned joint inside the turned set stops the turn there: it does not
	// move, and neither does anything hanging off it. The limb turns around
	// it, which is the point of having pinned it.
	//
	// The exception the artist asked for: an end bone — a hand, a foot — may
	// still swing about its own pin. Pinning a wrist so the hand can be turned
	// about it is the commonest reason to pin anything, and a rule that
	// forbade it would make pinning useless where it is most wanted.
	std::vector<uint8_t> blocked(now_.size(), 0);
	for (int k = 0; k < kids.size(); ++k) {
		const int j = kids[k];
		if (pinned_[(size_t)j] && !is_end(j)) blocked[(size_t)j] = 1;
	}
	// Blocking is inherited: everything below a blocked joint is blocked too.
	for (int j : order_) {
		const int p = parent_[(size_t)j];
		if (p >= 0 && blocked[(size_t)p]) blocked[(size_t)j] = 1;
	}

	int turned = 0;
	for (int k = 0; k < kids.size(); ++k) {
		const int j = kids[k];
		if (blocked[(size_t)j]) continue;
		const double dx = (double)now_[(size_t)j].x - centre.x;
		const double dy = (double)now_[(size_t)j].y - centre.y;
		now_[(size_t)j] = Vector2((real_t)(centre.x + dx * c - dy * s),
				(real_t)(centre.y + dx * s + dy * c));
		// Turned by the ring, not by its own drag — its filter is stale.
		invalidate_stability(j);
		++turned;
	}

	out["ok"] = true;
	out["turned"] = turned;
	out["blocked"] = (int)kids.size() - turned;
	// A rotation about a joint preserves every bone length below it exactly,
	// so there is nothing to relax and nothing to drift. Reported so a caller
	// can assert it rather than trust it.
	out["length_error"] = length_error();
	return out;
}

PackedFloat32Array IvoryBonePose::rest_lengths() const {
	PackedFloat32Array out;
	for (double l : length_) out.append((float)l);
	return out;
}

double IvoryBonePose::length_error() const {
	double worst = 0.0;
	for (size_t i = 0; i < now_.size(); ++i) {
		const int p = parent_[i];
		if (p < 0) continue;
		const double have = (double)now_[i].distance_to(now_[(size_t)p]);
		worst = std::max(worst, std::abs(have - length_[i]));
	}
	return worst;
}

} // namespace godot
