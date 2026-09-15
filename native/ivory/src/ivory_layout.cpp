#include "ivory_layout.h"

#include <algorithm>
#include <cmath>

using namespace godot;

void IvoryLayout::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_boxes", "boxes", "pinned"),
			&IvoryLayout::set_boxes);
	ClassDB::bind_method(D_METHOD("set_margin", "margin"),
			&IvoryLayout::set_margin);
	ClassDB::bind_method(D_METHOD("set_bounds", "bounds"),
			&IvoryLayout::set_bounds);
	ClassDB::bind_method(D_METHOD("resolve", "rounds"),
			&IvoryLayout::resolve);
	ClassDB::bind_method(D_METHOD("boxes"), &IvoryLayout::boxes);
	ClassDB::bind_method(D_METHOD("box", "index"), &IvoryLayout::box);
	ClassDB::bind_method(D_METHOD("collisions"), &IvoryLayout::collisions);
	ClassDB::bind_method(D_METHOD("tangled"), &IvoryLayout::tangled);
	ClassDB::bind_method(D_METHOD("touched", "at", "slop"),
			&IvoryLayout::touched);
}

void IvoryLayout::set_boxes(const Array &boxes,
		const PackedInt32Array &pinned) {
	boxes_.clear();
	pinned_.clear();
	for (int i = 0; i < boxes.size(); i++) {
		boxes_.push_back((Rect2)boxes[i]);
		pinned_.push_back(false);
	}
	for (int i = 0; i < pinned.size(); i++) {
		const int at = pinned[i];
		if (at >= 0 && at < (int)pinned_.size()) {
			pinned_[at] = true;
		}
	}
}

void IvoryLayout::set_margin(double margin) {
	margin_ = margin < 0.0 ? 0.0 : margin;
}

void IvoryLayout::set_bounds(const Rect2 &bounds) {
	bounds_ = bounds;
	bounded_ = bounds.size.x > 0.0f && bounds.size.y > 0.0f;
}

Array IvoryLayout::boxes() const {
	Array out;
	for (size_t i = 0; i < boxes_.size(); i++) {
		out.append(boxes_[i]);
	}
	return out;
}

Rect2 IvoryLayout::box(int index) const {
	if (index < 0 || index >= (int)boxes_.size()) {
		return Rect2();
	}
	return boxes_[index];
}

bool IvoryLayout::overlaps(int a, int b) const {
	// Grown by the margin before the test, so "overlapping" means "closer
	// than a fingertip can reliably separate" rather than "actually
	// intersecting". Two buttons exactly touching pass a strict test and fail
	// a person: a fingertip is around nine millimetres and lands with a
	// spread of several pixels either way, so the boundary between two
	// targets has to be wider than that spread to be missable.
	const Rect2 &x = boxes_[a];
	const Rect2 &y = boxes_[b];
	const double m = margin_;
	return (double)x.position.x < (double)y.position.x + y.size.x + m
			&& (double)x.position.x + x.size.x + m > (double)y.position.x
			&& (double)x.position.y < (double)y.position.y + y.size.y + m
			&& (double)x.position.y + x.size.y + m > (double)y.position.y;
}

void IvoryLayout::hold_inside(int i) {
	if (!bounded_) {
		return;
	}
	Rect2 &r = boxes_[i];
	// Clamped rather than resized. A control pushed off the edge is a control
	// somebody cannot press, and shrinking it instead would make its label
	// wrong — better a slightly crowded layout than a button that is half
	// there.
	if (r.size.x <= bounds_.size.x) {
		if (r.position.x < bounds_.position.x) {
			r.position.x = bounds_.position.x;
		}
		const real_t right = bounds_.position.x + bounds_.size.x;
		if (r.position.x + r.size.x > right) {
			r.position.x = right - r.size.x;
		}
	}
	if (r.size.y <= bounds_.size.y) {
		if (r.position.y < bounds_.position.y) {
			r.position.y = bounds_.position.y;
		}
		const real_t bottom = bounds_.position.y + bounds_.size.y;
		if (r.position.y + r.size.y > bottom) {
			r.position.y = bottom - r.size.y;
		}
	}
}

int IvoryLayout::resolve(int rounds) {
	const int n = (int)boxes_.size();
	if (n < 2) {
		return 0;
	}
	const int passes = std::min(std::max(rounds, 1), 24);
	int moved_any = 0;
	std::vector<bool> moved(n, false);

	// --- displacements are gathered, then applied ---
	//
	// The first version moved each rectangle the instant a collision was
	// found, and the test bench caught what that costs. Sweep and prune
	// depends on the list being **sorted by left edge**, and on `a_right`
	// being the right edge of the rectangle currently being swept. Moving a
	// rectangle mid-sweep invalidates both: the sort order is no longer the
	// order on screen, and the early `break` — which is only sound because
	// everything after this point starts further right — starts skipping
	// pairs that really do overlap. The pass then reports itself settled
	// while rectangles are still on top of each other.
	//
	// So a pass reads positions and writes nothing; every push is added to
	// `shift`, and the whole set is applied at the end. Positions are then
	// stable for the entire sweep and both invariants hold.
	//
	// It also makes the result symmetric — two rectangles that collide push
	// each other by the same amount in the same pass, rather than the earlier
	// one in the list being moved and the later one then reacting to a
	// position that has already changed.
	std::vector<Vector2> shift(n);
	std::vector<int> order(n);
	for (int pass = 0; pass < passes; pass++) {
		for (int i = 0; i < n; i++) {
			order[i] = i;
			shift[i] = Vector2();
		}
		std::sort(order.begin(), order.end(), [&](int a, int b) {
			return boxes_[a].position.x < boxes_[b].position.x;
		});

		bool touched_this_pass = false;
		for (int oi = 0; oi < n; oi++) {
			const int a = order[oi];
			const double a_right = (double)boxes_[a].position.x
					+ boxes_[a].size.x + margin_;
			for (int oj = oi + 1; oj < n; oj++) {
				const int b = order[oj];
				if ((double)boxes_[b].position.x > a_right) {
					break;
				}
				if (!overlaps(a, b)) {
					continue;
				}

				// --- how far apart, and which way ---
				//
				// The two overlaps are measured and the *smaller* one is
				// closed. Two buttons overlapping by two pixels horizontally
				// and forty vertically are a horizontal problem; pushing them
				// apart vertically would move them forty pixels to fix a
				// two-pixel fault, and would look like the layout exploding.
				const Rect2 &x = boxes_[a];
				const Rect2 &y = boxes_[b];
				const double dx = std::min(
						(double)x.position.x + x.size.x + margin_
								- (double)y.position.x,
						(double)y.position.x + y.size.x + margin_
								- (double)x.position.x);
				const double dy = std::min(
						(double)x.position.y + x.size.y + margin_
								- (double)y.position.y,
						(double)y.position.y + y.size.y + margin_
								- (double)x.position.y);

				const bool a_free = !pinned_[a];
				const bool b_free = !pinned_[b];
				if (!a_free && !b_free) {
					// Both pinned. Nothing can be done and saying so is
					// better than moving one anyway — a pinned control that
					// moves is a panel that has drifted away from the button
					// it belongs to, which is worse than an overlap.
					continue;
				}
				// --- how much of the gap each one takes ---
				//
				// Split evenly when both may move, so neither is singled out,
				// and taken entirely by the free one when the other is
				// pinned.
				//
				// **Exactly** even, plus a fixed hair. The first version used
				// a percentage over half — 0.52 and 1.04 — to clear the
				// margin rather than landing precisely on it, and the bench
				// caught what that costs: a four percent overshoot means each
				// pass pushes a pair slightly too far apart, the next pass
				// finds them overlapping something else and pushes back, and
				// the layout oscillates for ever without ever settling. It
				// looked like convergence failing; it was over-relaxation.
				//
				// A fixed absolute hair does the same job — the pair ends up
				// clear of the margin rather than exactly on it, where
				// floating-point equality would leave `overlaps` true — and
				// cannot overshoot, because it does not scale with the
				// distance being closed.
				const double share = (a_free && b_free) ? 0.5 : 1.0;
				const double hair = 0.02;

				if (dx < dy) {
					const double push = (dx + hair) * share;
					const bool a_left = x.position.x <= y.position.x;
					if (a_free) {
						shift[a].x += (real_t)(a_left ? -push : push);
					}
					if (b_free) {
						shift[b].x += (real_t)(a_left ? push : -push);
					}
				} else {
					const double push = (dy + hair) * share;
					const bool a_above = x.position.y <= y.position.y;
					if (a_free) {
						shift[a].y += (real_t)(a_above ? -push : push);
					}
					if (b_free) {
						shift[b].y += (real_t)(a_above ? push : -push);
					}
				}
				touched_this_pass = true;
			}
		}

		if (!touched_this_pass) {
			// Settled. Running the remaining passes would cost the same and
			// change nothing.
			break;
		}
		for (int i = 0; i < n; i++) {
			if (pinned_[i]) {
				continue;
			}
			if (shift[i].x == 0.0f && shift[i].y == 0.0f) {
				continue;
			}
			boxes_[i].position += shift[i];
			hold_inside(i);
			if (!moved[i]) {
				moved[i] = true;
				moved_any++;
			}
		}
	}
	return moved_any;
}

PackedInt32Array IvoryLayout::collisions() const {
	PackedInt32Array out;
	const int n = (int)boxes_.size();
	for (int i = 0; i < n; i++) {
		for (int j = i + 1; j < n; j++) {
			if (overlaps(i, j)) {
				out.append(i);
				out.append(j);
			}
		}
	}
	return out;
}

bool IvoryLayout::tangled() const {
	const int n = (int)boxes_.size();
	for (int i = 0; i < n; i++) {
		for (int j = i + 1; j < n; j++) {
			if (overlaps(i, j)) {
				return true;
			}
		}
	}
	return false;
}

int IvoryLayout::touched(const Vector2 &at, double slop) const {
	// --- which control a finger meant ---
	//
	// Not "the first rectangle containing the point", which is what a naive
	// hit test does and which has two failures worth fixing:
	//
	//   * A touch landing in the gap between two controls hits nothing, and
	//     the person presses again harder. Within `slop` it should go to the
	//     nearer one.
	//   * A touch landing inside two overlapping controls goes to whichever
	//     happens to be earlier in the list, which is an accident of
	//     construction order rather than anything the person could predict.
	//     It should go to the one whose centre it is nearest.
	//
	// So every candidate is scored by distance to its centre and the best
	// wins. Rectangles actually containing the point always beat ones merely
	// near it, however the distances compare — being inside a control is not
	// a matter of degree.
	int best = -1;
	double best_score = 1.0e18;
	bool found_inside = false;
	for (int i = 0; i < (int)boxes_.size(); i++) {
		const Rect2 &r = boxes_[i];
		const double cx = (double)r.position.x + r.size.x * 0.5;
		const double cy = (double)r.position.y + r.size.y * 0.5;
		const bool inside = (double)at.x >= (double)r.position.x
				&& (double)at.y >= (double)r.position.y
				&& (double)at.x <= (double)r.position.x + r.size.x
				&& (double)at.y <= (double)r.position.y + r.size.y;
		if (!inside) {
			if (found_inside || slop <= 0.0) {
				continue;
			}
			// Distance to the rectangle itself, not to its centre: a wide
			// button should be reachable from just past either end, and
			// scoring by centre distance would favour a small button further
			// away over a long one right beside the finger.
			const double gx = std::max(std::max(
					(double)r.position.x - at.x,
					(double)at.x - ((double)r.position.x + r.size.x)), 0.0);
			const double gy = std::max(std::max(
					(double)r.position.y - at.y,
					(double)at.y - ((double)r.position.y + r.size.y)), 0.0);
			const double away = std::sqrt(gx * gx + gy * gy);
			if (away > slop) {
				continue;
			}
			if (away < best_score) {
				best_score = away;
				best = i;
			}
			continue;
		}
		const double dx = (double)at.x - cx;
		const double dy = (double)at.y - cy;
		const double score = std::sqrt(dx * dx + dy * dy);
		if (!found_inside) {
			found_inside = true;
			best_score = score;
			best = i;
			continue;
		}
		if (score < best_score) {
			best_score = score;
			best = i;
		}
	}
	return best;
}
