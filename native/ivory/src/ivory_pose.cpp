#include "ivory_pose.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

} // namespace

void IvoryPose::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_skeleton", "head", "tail", "parent"),
			&IvoryPose::set_skeleton);
	ClassDB::bind_method(D_METHOD("bone_count"), &IvoryPose::bone_count);
	ClassDB::bind_method(D_METHOD("head"), &IvoryPose::head);
	ClassDB::bind_method(D_METHOD("tail"), &IvoryPose::tail);
	ClassDB::bind_method(D_METHOD("lock_above", "index"),
			&IvoryPose::lock_above);
	ClassDB::bind_method(D_METHOD("cascade"), &IvoryPose::cascade);
	ClassDB::bind_method(D_METHOD("open_below", "index"),
			&IvoryPose::open_below);
	ClassDB::bind_method(D_METHOD("unlock_all"), &IvoryPose::unlock_all);
	ClassDB::bind_method(D_METHOD("frozen", "index"), &IvoryPose::frozen);
	ClassDB::bind_method(D_METHOD("frozen_bones"), &IvoryPose::frozen_bones);
	ClassDB::bind_method(D_METHOD("frozen_count"), &IvoryPose::frozen_count);
	ClassDB::bind_method(D_METHOD("cascading"), &IvoryPose::cascading);
	ClassDB::bind_method(D_METHOD("movable_from", "index"),
			&IvoryPose::movable_from);
	ClassDB::bind_method(D_METHOD("tap", "index", "now"), &IvoryPose::tap);
	ClassDB::bind_method(D_METHOD("begin_drag", "handle"),
			&IvoryPose::begin_drag);
	ClassDB::bind_method(D_METHOD("dragging"), &IvoryPose::dragging);
	ClassDB::bind_method(D_METHOD("drag", "to"), &IvoryPose::drag);
	ClassDB::bind_method(D_METHOD("end_drag"), &IvoryPose::end_drag);
	ClassDB::bind_method(D_METHOD("set_steadiness", "start_px", "keep_px"),
			&IvoryPose::set_steadiness);
	ClassDB::bind_method(D_METHOD("set_tracks", "mask"), &IvoryPose::set_tracks);
	ClassDB::bind_method(D_METHOD("tracks"), &IvoryPose::tracks);
	ClassDB::bind_method(D_METHOD("allow_track", "kind"),
			&IvoryPose::allow_track);
	ClassDB::bind_method(D_METHOD("allows", "kind"), &IvoryPose::allows);
	ClassDB::bind_method(D_METHOD("plan_at", "frame"), &IvoryPose::plan_at);
	ClassDB::bind_method(D_METHOD("put_key", "kind", "frame"),
			&IvoryPose::put_key);
	ClassDB::bind_method(D_METHOD("clear_keys"), &IvoryPose::clear_keys);
	ClassDB::bind_method(D_METHOD("has_key", "kind", "frame"),
			&IvoryPose::has_key);
	ClassDB::bind_method(D_METHOD("keys_of", "kind"), &IvoryPose::keys_of);
	ClassDB::bind_method(D_METHOD("drift"), &IvoryPose::drift);
	ClassDB::bind_method(D_METHOD("wants_key"), &IvoryPose::wants_key);
	ClassDB::bind_method(D_METHOD("make_key", "frame"), &IvoryPose::make_key);
	ClassDB::bind_method(D_METHOD("set_key_threshold", "px"),
			&IvoryPose::set_key_threshold);
	ClassDB::bind_method(D_METHOD("timeline_state", "frame"),
			&IvoryPose::timeline_state);
}

// ---------------------------------------------------------------- skeleton

void IvoryPose::set_skeleton(const PackedVector2Array &head,
		const PackedVector2Array &tail, const PackedInt32Array &parent) {
	const int n = std::min((int)head.size(), (int)tail.size());
	head_.clear();
	tail_.clear();
	parent_.clear();
	length_.clear();
	head_.reserve((size_t)n);
	tail_.reserve((size_t)n);
	for (int i = 0; i < n; ++i) {
		head_.push_back(head[i]);
		tail_.push_back(tail[i]);
		int32_t up = i < parent.size() ? parent[i] : -1;
		// A parent that is not in the list, or that is the bone itself, or
		// that comes later than its child, is refused rather than trusted.
		// Any of the three makes the descendant walk loop for ever, and a
		// rig loaded from an older file is exactly where they come from.
		if (up < 0 || up >= n || up == i) {
			up = -1;
		}
		parent_.push_back(up);
		length_.push_back((float)head_[(size_t)i].distance_to(tail_[(size_t)i]));
	}
	frozen_.assign(head_.size(), 0);
	cascading_ = false;
	opened_ = -1;
	drag_bone_ = -1;
	have_key_pose_ = false;
	rebuild_kids();
}

void IvoryPose::rebuild_kids() {
	const int n = (int)head_.size();
	kid_at_.assign((size_t)n + 1, 0);
	kids_.assign((size_t)n, 0);
	std::vector<int32_t> count((size_t)n + 1, 0);
	for (int i = 0; i < n; ++i) {
		if (parent_[(size_t)i] >= 0) {
			++count[(size_t)parent_[(size_t)i]];
		}
	}
	int running = 0;
	for (int i = 0; i < n; ++i) {
		kid_at_[(size_t)i] = running;
		running += count[(size_t)i];
	}
	kid_at_[(size_t)n] = running;
	std::vector<int32_t> at = kid_at_;
	kids_.assign((size_t)running, 0);
	for (int i = 0; i < n; ++i) {
		const int up = parent_[(size_t)i];
		if (up >= 0) {
			kids_[(size_t)at[(size_t)up]++] = (int32_t)i;
		}
	}
}

PackedVector2Array IvoryPose::head() const {
	PackedVector2Array out;
	out.resize((int)head_.size());
	for (size_t i = 0; i < head_.size(); ++i) {
		out[(int)i] = head_[i];
	}
	return out;
}

PackedVector2Array IvoryPose::tail() const {
	PackedVector2Array out;
	out.resize((int)tail_.size());
	for (size_t i = 0; i < tail_.size(); ++i) {
		out[(int)i] = tail_[i];
	}
	return out;
}

// ---------------------------------------------------------------- freezing

void IvoryPose::gather_below(int index, std::vector<int32_t> &into) const {
	if (index < 0 || index >= (int)head_.size()) {
		return;
	}
	std::vector<int32_t> stack;
	stack.push_back((int32_t)index);
	// A visited mark as well as the parent sanitising in `set_skeleton`.
	// Belt and braces on purpose: this loop is what hangs the app if a rig
	// ever does contain a cycle, and hanging is the one failure a person
	// cannot recover from.
	std::vector<uint8_t> seen(head_.size(), 0);
	while (!stack.empty()) {
		const int32_t at = stack.back();
		stack.pop_back();
		if (seen[(size_t)at]) {
			continue;
		}
		seen[(size_t)at] = 1;
		into.push_back(at);
		for (int k = kid_at_[(size_t)at]; k < kid_at_[(size_t)at + 1]; ++k) {
			stack.push_back(kids_[(size_t)k]);
		}
	}
}

void IvoryPose::lock_above(int index) {
	if (index < 0 || index >= (int)head_.size()) {
		return;
	}
	std::vector<uint8_t> keep(head_.size(), 0);
	std::vector<int32_t> below;
	gather_below(index, below);
	for (int32_t b : below) {
		keep[(size_t)b] = 1;
	}
	for (size_t i = 0; i < frozen_.size(); ++i) {
		frozen_[i] = keep[i] ? 0 : 1;
	}
	opened_ = index;
}

void IvoryPose::cascade() {
	frozen_.assign(head_.size(), 1);
	cascading_ = true;
	opened_ = -1;
}

void IvoryPose::open_below(int index) {
	cascading_ = true;
	lock_above(index);
}

void IvoryPose::unlock_all() {
	frozen_.assign(head_.size(), 0);
	cascading_ = false;
	opened_ = -1;
}

bool IvoryPose::frozen(int index) const {
	if (index < 0 || index >= (int)frozen_.size()) {
		return false;
	}
	return frozen_[(size_t)index] != 0;
}

PackedInt32Array IvoryPose::frozen_bones() const {
	PackedInt32Array out;
	for (size_t i = 0; i < frozen_.size(); ++i) {
		if (frozen_[i]) {
			out.append((int32_t)i);
		}
	}
	return out;
}

int IvoryPose::frozen_count() const {
	int n = 0;
	for (uint8_t f : frozen_) {
		n += f ? 1 : 0;
	}
	return n;
}

PackedInt32Array IvoryPose::movable_from(int index) const {
	PackedInt32Array out;
	if (index < 0 || index >= (int)head_.size()) {
		return out;
	}
	std::vector<int32_t> below;
	gather_below(index, below);
	std::sort(below.begin(), below.end());
	for (int32_t b : below) {
		if (!frozen((int)b)) {
			out.append(b);
		}
	}
	return out;
}

Dictionary IvoryPose::tap(int index, double now) {
	Dictionary out;
	out["bone"] = index;
	if (index < 0 || index >= (int)head_.size()) {
		out["action"] = String("none");
		return out;
	}

	const bool same = index == tap_bone_;
	const bool soon = now - tap_at_ <= TAP_WINDOW;
	tap_bone_ = index;
	tap_at_ = now;

	if (same && soon) {
		if (cascading_ && opened_ == index) {
			// The third tap. The same circle is the way out as well as the
			// way in, because a mode with a different exit is a mode people
			// get stuck in.
			unlock_all();
			out["action"] = String("released");
			out["cascading"] = false;
			return out;
		}
		open_below(index);
		out["action"] = String("cascaded");
		out["cascading"] = true;
		out["frozen"] = frozen_count();
		out["movable"] = movable_from(index);
		return out;
	}

	out["action"] = String("selected");
	out["cascading"] = cascading_;
	return out;
}

// ---------------------------------------------------------------- dragging

void IvoryPose::carry(int index, const Vector2 &pivot, double turn) {
	// One rotation, one pivot, applied to the whole subtree. See the header:
	// this is the whole of "a part moves, nothing is distorted".
	const double c = std::cos(turn);
	const double s = std::sin(turn);
	auto spin = [&](Vector2 &p) {
		const double dx = p.x - pivot.x;
		const double dy = p.y - pivot.y;
		p.x = (real_t)(pivot.x + dx * c - dy * s);
		p.y = (real_t)(pivot.y + dx * s + dy * c);
	};
	std::vector<int32_t> below;
	gather_below(index, below);
	for (int32_t b : below) {
		spin(head_[(size_t)b]);
		spin(tail_[(size_t)b]);
	}
}

void IvoryPose::begin_drag(int handle) {
	const int index = handle >> 1;
	if (index < 0 || index >= (int)head_.size() || frozen(index)) {
		drag_bone_ = -1;
		return;
	}
	drag_bone_ = index;
	drag_which_ = handle & 1;
	moving_ = false;
	drag_from_ = drag_which_ ? tail_[(size_t)index] : head_[(size_t)index];
	last_target_ = drag_from_;
}

void IvoryPose::set_steadiness(double start_px, double keep_px) {
	start_px_ = std::max(start_px, 0.0);
	// Enforced, not trusted. Equal thresholds are one threshold, and one
	// threshold is the shudder.
	keep_px_ = clampd(keep_px, 0.0, std::max(start_px_ * 0.75, 0.0));
}

Dictionary IvoryPose::drag(const Vector2 &to) {
	Dictionary out;
	out["moved"] = false;
	if (drag_bone_ < 0) {
		return out;
	}

	const double step = to.distance_to(last_target_);
	const double gate = moving_ ? keep_px_ : start_px_;
	if (step < gate) {
		// Below the gate the finger is holding still, whatever the panel
		// reported. Nothing happens, so nothing shivers.
		out["bone"] = drag_bone_;
		out["still"] = true;
		return out;
	}
	moving_ = true;
	last_target_ = to;

	// The pivot is the far end of the bone, or the parent's tail when the
	// head is the end being pulled — which is the joint the bone actually
	// turns about.
	const int index = drag_bone_;
	const Vector2 pivot = drag_which_ ? head_[(size_t)index]
			: tail_[(size_t)index];
	const Vector2 was = drag_which_ ? tail_[(size_t)index]
			: head_[(size_t)index];

	const Vector2 from_dir = was - pivot;
	const Vector2 to_dir = to - pivot;
	if (from_dir.length() < 1e-6 || to_dir.length() < 1e-6) {
		out["bone"] = index;
		out["still"] = true;
		return out;
	}
	const double turn = std::atan2(from_dir.cross(to_dir),
			from_dir.dot(to_dir));
	carry(index, pivot, turn);

	out["moved"] = true;
	out["still"] = false;
	out["bone"] = index;
	out["turn"] = turn;
	out["pivot"] = pivot;
	out["drift"] = drift();
	out["wants_key"] = wants_key();
	return out;
}

Dictionary IvoryPose::end_drag() {
	Dictionary out;
	out["bone"] = drag_bone_;
	out["moved"] = moving_;
	out["drift"] = drift();
	out["wants_key"] = wants_key();
	drag_bone_ = -1;
	moving_ = false;
	return out;
}

// ---------------------------------------------------------------- timeline

void IvoryPose::set_tracks(int mask) {
	// Draw is always there. A layer with no frames is not a layer.
	tracks_ = mask | TRACK_DRAW;
}

void IvoryPose::allow_track(int kind) {
	tracks_ |= kind;
}

bool IvoryPose::allows(int kind) const {
	return (tracks_ & kind) != 0;
}

const std::vector<int32_t> *IvoryPose::bucket(int kind) const {
	switch (kind) {
		case TRACK_DRAW: return &draw_keys_;
		case TRACK_RIG: return &rig_keys_;
		case TRACK_WARP: return &warp_keys_;
		default: return nullptr;
	}
}

std::vector<int32_t> *IvoryPose::bucket(int kind) {
	switch (kind) {
		case TRACK_DRAW: return &draw_keys_;
		case TRACK_RIG: return &rig_keys_;
		case TRACK_WARP: return &warp_keys_;
		default: return nullptr;
	}
}

void IvoryPose::put_key(int kind, int frame) {
	std::vector<int32_t> *at = bucket(kind);
	if (at == nullptr || frame < 0) {
		return;
	}
	allow_track(kind);
	if (std::find(at->begin(), at->end(), (int32_t)frame) == at->end()) {
		at->push_back((int32_t)frame);
		std::sort(at->begin(), at->end());
	}
}

void IvoryPose::clear_keys() {
	draw_keys_.clear();
	rig_keys_.clear();
	warp_keys_.clear();
	last_key_frame_ = -1;
	just_made_ = false;
	have_key_pose_ = false;
}

bool IvoryPose::has_key(int kind, int frame) const {
	const std::vector<int32_t> *at = bucket(kind);
	if (at == nullptr) {
		return false;
	}
	return std::find(at->begin(), at->end(), (int32_t)frame) != at->end();
}

PackedInt32Array IvoryPose::keys_of(int kind) const {
	PackedInt32Array out;
	const std::vector<int32_t> *at = bucket(kind);
	if (at == nullptr) {
		return out;
	}
	for (int32_t f : *at) {
		out.append(f);
	}
	return out;
}

Dictionary IvoryPose::plan_at(int frame) const {
	Dictionary out;
	PackedInt32Array order;
	PackedInt32Array carries;
	// Draw, then rig, then warp. Fixed, and not a preference — see the
	// header for why warping before posing takes the drawing apart.
	const int fixed[3] = { TRACK_DRAW, TRACK_RIG, TRACK_WARP };
	for (int kind : fixed) {
		if (allows(kind)) {
			order.append(kind);
			if (has_key(kind, frame)) {
				carries.append(kind);
			}
		}
	}
	out["order"] = order;
	out["keyed"] = carries;
	out["frame"] = frame;
	// Three kinds of motion on one layer, and the timeline stays balanced
	// because none of them can displace another: the mask is a union.
	out["mixed"] = order.size() > 1;
	return out;
}

void IvoryPose::set_key_threshold(double px) {
	key_px_ = std::max(px, 0.0);
}

double IvoryPose::drift() const {
	if (!have_key_pose_ || keyed_head_.size() != head_.size()) {
		return 0.0;
	}
	// The furthest any joint has travelled, not the average. An average
	// hides one hand moving a long way among twenty bones that did not, and
	// one hand moving is exactly the thing that deserves a frame.
	double worst = 0.0;
	for (size_t i = 0; i < head_.size(); ++i) {
		worst = std::max(worst, head_[i].distance_to(keyed_head_[i]));
		worst = std::max(worst, tail_[i].distance_to(keyed_tail_[i]));
	}
	return worst;
}

bool IvoryPose::wants_key() const {
	if (!have_key_pose_) {
		return true;
	}
	return drift() > key_px_;
}

Dictionary IvoryPose::make_key(int frame) {
	Dictionary out;
	const bool first = !have_key_pose_;
	const double moved = drift();
	keyed_head_ = head_;
	keyed_tail_ = tail_;
	have_key_pose_ = true;
	last_key_frame_ = frame;
	just_made_ = true;
	put_key(TRACK_RIG, frame);

	out["frame"] = frame;
	out["first"] = first;
	out["moved"] = moved;
	// The two things the interface is asked to show the moment a bone layer
	// builds a frame.
	out["onion"] = true;
	out["dot"] = true;
	return out;
}

Dictionary IvoryPose::timeline_state(int frame) const {
	Dictionary out;
	out["frame"] = frame;
	out["last_key"] = last_key_frame_;
	out["built"] = just_made_ && last_key_frame_ == frame;
	// The onion skin comes on once there is a previous pose to see through.
	// Before that it would be a picture of the drawing over itself, which
	// tells nobody anything and only dims the page.
	out["onion"] = have_key_pose_ && !rig_keys_.empty();
	out["dot"] = has_key(TRACK_RIG, frame);
	out["drift"] = drift();
	out["cascading"] = cascading_;
	out["frozen"] = frozen_count();
	out["tracks"] = tracks_;
	return out;
}
