#include "ivory_arbiter.h"

#include <algorithm>
#include <cmath>

using namespace godot;

void IvoryArbiter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("offer", "id", "kind"), &IvoryArbiter::offer);
	ClassDB::bind_method(D_METHOD("forget", "id"), &IvoryArbiter::forget);
	ClassDB::bind_method(D_METHOD("known", "id"), &IvoryArbiter::known);
	ClassDB::bind_method(D_METHOD("kind_of", "id"), &IvoryArbiter::kind_of);
	ClassDB::bind_method(D_METHOD("offered"), &IvoryArbiter::offered);
	ClassDB::bind_method(D_METHOD("choose", "id"), &IvoryArbiter::choose);
	ClassDB::bind_method(D_METHOD("clear"), &IvoryArbiter::clear);
	ClassDB::bind_method(D_METHOD("live"), &IvoryArbiter::live);
	ClassDB::bind_method(D_METHOD("anything_live"),
			&IvoryArbiter::anything_live);
	ClassDB::bind_method(D_METHOD("standing", "id"), &IvoryArbiter::standing);
	ClassDB::bind_method(D_METHOD("standing_now"), &IvoryArbiter::standing_now);
	ClassDB::bind_method(D_METHOD("raise", "id"), &IvoryArbiter::raise);
	ClassDB::bind_method(D_METHOD("lower", "id"), &IvoryArbiter::lower);
	ClassDB::bind_method(D_METHOD("finger_down", "id", "at", "now"),
			&IvoryArbiter::finger_down);
	ClassDB::bind_method(D_METHOD("finger_moved", "id", "at"),
			&IvoryArbiter::finger_moved);
	ClassDB::bind_method(D_METHOD("finger_up", "id", "now"),
			&IvoryArbiter::finger_up);
	ClassDB::bind_method(D_METHOD("fingers_down"), &IvoryArbiter::fingers_down);
	ClassDB::bind_method(D_METHOD("set_gesture", "slop_px", "gather_s",
			"hold_s"), &IvoryArbiter::set_gesture);
	ClassDB::bind_method(D_METHOD("cancels"), &IvoryArbiter::cancels);
}

// -------------------------------------------------------------- the roster

void IvoryArbiter::offer(const String &id, int kind) {
	if (id.is_empty()) {
		return;
	}
	kind_[id] = kind == KIND_STANDING ? KIND_STANDING : KIND_MODE;
	if (kind_[id] == KIND_STANDING && up_.find(id) == up_.end()) {
		up_[id] = false;
	}
	// A tool that has just become structure cannot go on being the live
	// mode: those are different things and it can only be one of them.
	if (kind_[id] == KIND_STANDING && live_ == id) {
		live_ = String();
	}
}

void IvoryArbiter::forget(const String &id) {
	kind_.erase(id);
	up_.erase(id);
	if (live_ == id) {
		live_ = String();
	}
}

bool IvoryArbiter::known(const String &id) const {
	return kind_.find(id) != kind_.end();
}

int IvoryArbiter::kind_of(const String &id) const {
	auto it = kind_.find(id);
	return it == kind_.end() ? -1 : it->second;
}

PackedStringArray IvoryArbiter::offered() const {
	PackedStringArray out;
	for (const auto &kv : kind_) {
		out.append(kv.first);
	}
	return out;
}

// --------------------------------------------------------------- choosing

Dictionary IvoryArbiter::choose(const String &id) {
	Dictionary out;
	out["chosen"] = id;
	out["dropped"] = String();
	out["live"] = live_;

	auto it = kind_.find(id);
	if (it == kind_.end()) {
		// An unknown tool is refused rather than made live. Making it live
		// would mean the next `choose` reports having dropped something the
		// caller never turned on, and the caller would try to tear it down.
		out["ok"] = false;
		out["reason"] = String("unknown");
		return out;
	}

	if (it->second == KIND_STANDING) {
		// Structure. It does not become the live mode and it does not
		// disturb the live mode.
		const bool was = standing(id);
		up_[id] = !was;
		out["ok"] = true;
		out["standing"] = !was;
		out["live"] = live_;
		out["reason"] = String(was ? "lowered" : "raised");
		return out;
	}

	if (live_ == id) {
		out["dropped"] = live_;
		live_ = String();
		out["ok"] = true;
		out["live"] = live_;
		out["reason"] = String("toggled_off");
		return out;
	}

	out["dropped"] = live_;
	live_ = id;
	out["ok"] = true;
	out["live"] = live_;
	out["reason"] = String(((String)out["dropped"]).is_empty() ? "taken"
			: "replaced");
	return out;
}

Dictionary IvoryArbiter::clear() {
	Dictionary out;
	out["dropped"] = live_;
	out["was_live"] = !live_.is_empty();
	live_ = String();
	return out;
}

bool IvoryArbiter::standing(const String &id) const {
	auto it = up_.find(id);
	return it != up_.end() && it->second;
}

PackedStringArray IvoryArbiter::standing_now() const {
	PackedStringArray out;
	for (const auto &kv : up_) {
		if (kv.second) {
			out.append(kv.first);
		}
	}
	return out;
}

void IvoryArbiter::raise(const String &id) {
	if (kind_of(id) == KIND_STANDING) {
		up_[id] = true;
	}
}

void IvoryArbiter::lower(const String &id) {
	if (kind_of(id) == KIND_STANDING) {
		up_[id] = false;
	}
}

// -------------------------------------------------------------- the gesture

void IvoryArbiter::set_gesture(double slop_px, double gather_s,
		double hold_s) {
	slop_ = std::max(slop_px, 0.0);
	gather_ = std::max(gather_s, 0.01);
	hold_ = std::max(hold_s, gather_);
}

void IvoryArbiter::reset_gesture() {
	peak_ = 0;
	spoiled_ = false;
	first_down_ = 0.0;
}

void IvoryArbiter::finger_down(int id, const Vector2 &at, double now) {
	if (touch_.empty()) {
		reset_gesture();
		first_down_ = now;
	}
	Touch t;
	t.down = at;
	t.at = at;
	t.when = now;
	touch_[id] = t;
	peak_ = std::max(peak_, (int)touch_.size());

	// More than four is a palm or a hand put down flat. Not a gesture.
	if ((int)touch_.size() > 4) {
		spoiled_ = true;
	}
	// Four that did not arrive together are four separate touches that
	// happen to overlap.
	if (now - first_down_ > gather_) {
		spoiled_ = true;
	}
}

void IvoryArbiter::finger_moved(int id, const Vector2 &at) {
	auto it = touch_.find(id);
	if (it == touch_.end()) {
		return;
	}
	it->second.travelled += it->second.at.distance_to(at);
	it->second.at = at;
	// Travelled, not displacement from where it started. A finger that goes
	// out and comes back has still been dragged, and a pan that returns to
	// its start must not be read as a tap.
	if (it->second.travelled > slop_) {
		spoiled_ = true;
	}
}

Dictionary IvoryArbiter::finger_up(int id, double now) {
	Dictionary out;
	out["fired"] = false;

	auto it = touch_.find(id);
	const double held = it == touch_.end() ? 0.0 : now - it->second.when;
	if (held > hold_) {
		spoiled_ = true;
	}
	touch_.erase(id);

	if (!touch_.empty()) {
		// Still fingers down; nothing is decided until they are all gone.
		out["remaining"] = (int)touch_.size();
		return out;
	}

	const bool fire = peak_ == 4 && !spoiled_;
	out["peak"] = peak_;
	out["spoiled"] = spoiled_;
	reset_gesture();

	if (!fire) {
		return out;
	}

	// It fired. Standing tools are deliberately untouched: a skeleton is
	// part of the layer, and cancelling it would be deleting work.
	Dictionary gone = clear();
	++cancels_;
	out["fired"] = true;
	out["cancelled"] = gone["dropped"];
	out["was_live"] = gone["was_live"];
	out["kept_standing"] = standing_now();
	return out;
}
