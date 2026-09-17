#include "ivory_rig360.h"
#include <godot_cpp/core/math_defs.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {

double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

const char *PART_WORDS[] = {
	"root", "head", "neck", "spine", "arm", "hand", "finger", "leg",
	"hair", "cloth",
};
const int PART_COUNT = 10;

} // namespace

void IvoryRig360::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_bone", "head", "tail", "parent", "part"),
			&IvoryRig360::add_bone);
	ClassDB::bind_method(D_METHOD("remove_bone", "index"),
			&IvoryRig360::remove_bone);
	ClassDB::bind_method(D_METHOD("clear"), &IvoryRig360::clear);
	ClassDB::bind_method(D_METHOD("bone_count"), &IvoryRig360::bone_count);
	ClassDB::bind_method(D_METHOD("suggest_from", "at", "kind"),
			&IvoryRig360::suggest_from);
	ClassDB::bind_method(D_METHOD("add_finger_set", "hand_bone", "finger_length", "palm_width"),
			&IvoryRig360::add_finger_set);
	ClassDB::bind_method(D_METHOD("rest_head", "index"),
			&IvoryRig360::rest_head);
	ClassDB::bind_method(D_METHOD("rest_tail", "index"),
			&IvoryRig360::rest_tail);
	ClassDB::bind_method(D_METHOD("posed_head", "index"),
			&IvoryRig360::posed_head);
	ClassDB::bind_method(D_METHOD("posed_tail", "index"),
			&IvoryRig360::posed_tail);
	ClassDB::bind_method(D_METHOD("parent_of", "index"),
			&IvoryRig360::parent_of);
	ClassDB::bind_method(D_METHOD("part_of", "index"), &IvoryRig360::part_of);
	ClassDB::bind_method(D_METHOD("name_of", "index"), &IvoryRig360::name_of);
	ClassDB::bind_method(D_METHOD("set_angle", "index", "radians"),
			&IvoryRig360::set_angle);
	ClassDB::bind_method(D_METHOD("set_angle_limits", "index", "min_radians", "max_radians"),
			&IvoryRig360::set_angle_limits);
	ClassDB::bind_method(D_METHOD("angle_limits", "index"),
			&IvoryRig360::angle_limits);
	ClassDB::bind_method(D_METHOD("angle_of", "index"),
			&IvoryRig360::angle_of);
	ClassDB::bind_method(D_METHOD("angles"), &IvoryRig360::angles);
	ClassDB::bind_method(D_METHOD("rest_all"), &IvoryRig360::rest_all);
	ClassDB::bind_method(D_METHOD("solve_ik", "end_bone", "target", "iterations", "tolerance"), &IvoryRig360::solve_ik);
	ClassDB::bind_method(D_METHOD("drag_to", "at", "reach", "target", "iterations", "tolerance"), &IvoryRig360::drag_to);
	ClassDB::bind_method(D_METHOD("pick", "at", "reach"), &IvoryRig360::pick);
	ClassDB::bind_method(D_METHOD("bind_stroke", "layer", "points"),
			&IvoryRig360::bind_stroke);
	ClassDB::bind_method(D_METHOD("bind_stroke_spread", "layer", "points"),
			&IvoryRig360::bind_stroke_spread);
	ClassDB::bind_method(D_METHOD("bind_stroke_to", "layer", "points", "bone"),
			&IvoryRig360::bind_stroke_to);
	ClassDB::bind_method(D_METHOD("unbind_stroke", "id"),
			&IvoryRig360::unbind_stroke);
	ClassDB::bind_method(D_METHOD("stroke_count"), &IvoryRig360::stroke_count);
	ClassDB::bind_method(D_METHOD("stroke_now", "id"),
			&IvoryRig360::stroke_now);
	ClassDB::bind_method(D_METHOD("stroke_layer", "id"),
			&IvoryRig360::stroke_layer);
	ClassDB::bind_method(D_METHOD("record_action", "driver", "angle", "target",
			"value"), &IvoryRig360::record_action);
	ClassDB::bind_method(D_METHOD("clear_actions", "driver"),
			&IvoryRig360::clear_actions);
	ClassDB::bind_method(D_METHOD("action_count", "driver"),
			&IvoryRig360::action_count);
	ClassDB::bind_method(D_METHOD("apply_actions"),
			&IvoryRig360::apply_actions);
	ClassDB::bind_method(D_METHOD("next_layer_name"),
			&IvoryRig360::next_layer_name);
	ClassDB::bind_method(D_METHOD("add_layer"), &IvoryRig360::add_layer);
	ClassDB::bind_method(D_METHOD("ensure_motion_layer"), &IvoryRig360::ensure_motion_layer);
	ClassDB::bind_method(D_METHOD("motion_layer_index"), &IvoryRig360::motion_layer_index);
	ClassDB::bind_method(D_METHOD("remove_layer", "layer"),
			&IvoryRig360::remove_layer);
	ClassDB::bind_method(D_METHOD("layer_names"), &IvoryRig360::layer_names);
	ClassDB::bind_method(D_METHOD("layer_count"), &IvoryRig360::layer_count);
	ClassDB::bind_method(D_METHOD("to_project"), &IvoryRig360::to_project);
	ClassDB::bind_method(D_METHOD("summary"), &IvoryRig360::summary);
	ClassDB::bind_method(D_METHOD("undo_last"), &IvoryRig360::undo_last);
	ClassDB::bind_method(D_METHOD("undo_depth"), &IvoryRig360::undo_depth);
	ClassDB::bind_method(D_METHOD("forget_undo"), &IvoryRig360::forget_undo);
	ClassDB::bind_static_method("IvoryRig360", D_METHOD("base_layer_name"),
			&IvoryRig360::base_layer_name);

	BIND_ENUM_CONSTANT(PART_ROOT);
	BIND_ENUM_CONSTANT(PART_HEAD);
	BIND_ENUM_CONSTANT(PART_NECK);
	BIND_ENUM_CONSTANT(PART_SPINE);
	BIND_ENUM_CONSTANT(PART_ARM);
	BIND_ENUM_CONSTANT(PART_HAND);
	BIND_ENUM_CONSTANT(PART_FINGER);
	BIND_ENUM_CONSTANT(PART_LEG);
	BIND_ENUM_CONSTANT(PART_HAIR);
	BIND_ENUM_CONSTANT(PART_CLOTH);
}

// -------------------------------------------------------------------- bones

int IvoryRig360::add_bone(const Vector2 &head, const Vector2 &tail,
		int parent, int part) {
	Bone b;
	b.rest_head = head;
	b.rest_tail = tail;
	// A parent that is not there, is the bone itself, or comes later is
	// refused. Any of the three makes the chain walk loop for ever.
	b.parent = (parent >= 0 && parent < (int)bone_.size()) ? (int32_t)parent
			: -1;
	b.part = (int32_t)clampd(part, 0, PART_COUNT - 1);
	b.angle = 0.0;
	bone_.push_back(b);
	min_angle_.push_back((float)-TAU);
	max_angle_.push_back((float)TAU);
	Undo u;
	u.what = String("add_bone");
	u.bone = (int32_t)bone_.size() - 1;
	note(u);
	return (int)bone_.size() - 1;
}

bool IvoryRig360::remove_bone(int index) {
	if (index < 0 || index >= (int)bone_.size()) {
		return false;
	}
	// Children are re-hung on the grandparent rather than deleted with it.
	// Deleting a shoulder should not silently delete the hand — the person
	// asked for one thing to go.
	for (size_t i = 0; i < bone_.size(); ++i) {
		if (bone_[i].parent == index) {
			bone_[i].parent = bone_[(size_t)index].parent;
		}
	}
	bone_.erase(bone_.begin() + index);
	if (index < (int)min_angle_.size()) min_angle_.erase(min_angle_.begin() + index);
	if (index < (int)max_angle_.size()) max_angle_.erase(max_angle_.begin() + index);
	for (size_t i = 0; i < bone_.size(); ++i) {
		if (bone_[i].parent > index) {
			--bone_[i].parent;
		}
	}
	for (Stroke &s : stroke_) {
		for (int32_t &o : s.owner) {
			if (o == index) {
				o = -1;
			} else if (o > index) {
				--o;
			}
		}
	}
	std::vector<Action> kept;
	for (const Action &a : action_) {
		if (a.driver == index || a.target == index) {
			continue;
		}
		Action b = a;
		if (b.driver > index) --b.driver;
		if (b.target > index) --b.target;
		kept.push_back(b);
	}
	action_.swap(kept);
	// Indices moved, so an undo record naming one is no longer meaningful.
	// Said plainly rather than left to produce a wrong reversal later.
	undo_.clear();
	return true;
}

void IvoryRig360::clear() {
	bone_.clear();
	min_angle_.clear();
	max_angle_.clear();
	stroke_.clear();
	action_.clear();
	layer_.clear();
	undo_.clear();
	next_stroke_ = 1;
}

int IvoryRig360::suggest_from(const PackedVector2Array &at,
		const PackedInt32Array &kind) {
	const int n = std::min((int)at.size(), (int)kind.size());
	if (n == 0) {
		return 0;
	}
	// The head first, so it is the root and everything hangs from it in the
	// order a person expects to see in a list.
	int head_at = -1;
	for (int i = 0; i < n; ++i) {
		if (kind[i] == 0) {
			head_at = i;
			break;
		}
	}
	if (head_at < 0) {
		head_at = 0;
	}

	const Vector2 head = at[head_at];
	// The body joints, sorted down the page, make the spine.
	std::vector<int> body;
	for (int i = 0; i < n; ++i) {
		if (i != head_at && kind[i] == 1) {
			body.push_back(i);
		}
	}
	std::sort(body.begin(), body.end(), [&](int a, int b) {
		return at[a].y < at[b].y;
	});

	const int before = (int)bone_.size();
	int spine = add_bone(head, body.empty() ? head + Vector2(0, 40)
			: at[body[0]], -1, PART_HEAD);
	int last = spine;
	for (size_t i = 0; i + 1 < body.size(); ++i) {
		last = add_bone(at[body[i]], at[body[i + 1]], last, PART_SPINE);
	}

	// Each extremity gets a bone from the nearest spine joint out to it.
	for (int i = 0; i < n; ++i) {
		if (kind[i] != 2) {
			continue;
		}
		int nearest = spine;
		double best = 1e30;
		for (int b = before; b < (int)bone_.size(); ++b) {
			const double d = bone_[(size_t)b].rest_tail.distance_to(at[i]);
			if (d < best) {
				best = d;
				nearest = b;
			}
		}
		// Below the spine's lowest joint it is a leg, otherwise an arm. A
		// heuristic, and one the artist can change with one tap on the kind.
		const bool low = at[i].y > bone_[(size_t)last].rest_tail.y;
		add_bone(bone_[(size_t)nearest].rest_tail, at[i], nearest,
				low ? PART_LEG : PART_ARM);
	}
	return (int)bone_.size() - before;
}


int IvoryRig360::add_finger_set(int hand_bone, double finger_length, double palm_width) {
	if (hand_bone < 0 || hand_bone >= (int)bone_.size()) return 0;
	finger_length = clampd(finger_length, 2.0, 1000.0);
	palm_width = clampd(palm_width, 2.0, 1000.0);
	const Vector2 wrist = bone_[(size_t)hand_bone].rest_head;
	const Vector2 palm = bone_[(size_t)hand_bone].rest_tail;
	Vector2 axis = palm - wrist;
	if (axis.length_squared() < 1e-8) axis = Vector2(1, 0);
	axis = axis.normalized();
	const Vector2 side(-axis.y, axis.x);
	int created = 0;

	// Index/middle/ring/little: a compact fan. The offset is along the palm,
	// while the small angular fan prevents the five tips from collapsing into
	// one line. The geometry is deterministic and can be edited afterwards.
	const double offsets[4] = {-0.33, -0.11, 0.11, 0.33};
	const double fans[4] = {-0.11, -0.035, 0.035, 0.11};
	for (int f = 0; f < 4; ++f) {
		Vector2 root = palm + side * (real_t)(offsets[f] * palm_width);
		Vector2 dir = (axis + side * (real_t)fans[f]).normalized();
		Vector2 a = root;
		int parent = hand_bone;
		for (int ph = 0; ph < 3; ++ph) {
			const double scale = ph == 0 ? 0.38 : (ph == 1 ? 0.33 : 0.29);
			Vector2 b = a + dir * (real_t)(finger_length * scale);
			const int idx = add_bone(a, b, parent, PART_FINGER);
			set_angle_limits(idx, -1.35, 1.35);
			parent = idx;
			a = b;
			++created;
		}
	}

	// Thumb: opposing sweep from the side of the palm. Its limits are a bit
	// wider because a thumb naturally has a different rest direction.
	Vector2 thumb_root = palm + side * (real_t)(-0.42 * palm_width);
	Vector2 thumb_dir = (axis * 0.42 - side * 0.82).normalized();
	Vector2 a = thumb_root;
	int parent = hand_bone;
	for (int ph = 0; ph < 3; ++ph) {
		const double scale = ph == 0 ? 0.42 : (ph == 1 ? 0.34 : 0.28);
		Vector2 b = a + thumb_dir * (real_t)(finger_length * scale);
		const int idx = add_bone(a, b, parent, PART_FINGER);
		set_angle_limits(idx, -1.55, 1.55);
		parent = idx;
		a = b;
		++created;
	}
	return created;
}

Vector2 IvoryRig360::rest_head(int index) const {
	return index >= 0 && index < (int)bone_.size()
			? bone_[(size_t)index].rest_head : Vector2();
}

Vector2 IvoryRig360::rest_tail(int index) const {
	return index >= 0 && index < (int)bone_.size()
			? bone_[(size_t)index].rest_tail : Vector2();
}

int IvoryRig360::parent_of(int index) const {
	return index >= 0 && index < (int)bone_.size()
			? bone_[(size_t)index].parent : -1;
}

int IvoryRig360::part_of(int index) const {
	return index >= 0 && index < (int)bone_.size()
			? bone_[(size_t)index].part : -1;
}

String IvoryRig360::name_of(int index) const {
	if (index < 0 || index >= (int)bone_.size()) {
		return String();
	}
	return String(PART_WORDS[bone_[(size_t)index].part]) + String(" ") +
			String::num_int64(index);
}

// -------------------------------------------------------------------- posing

double IvoryRig360::rest_angle(int index) const {
	const Bone &b = bone_[(size_t)index];
	return (b.rest_tail - b.rest_head).angle();
}

double IvoryRig360::chain_angle(int index) const {
	// The sum of the angles from the root down. Walked with a guard, because
	// a rig loaded from a file is not to be trusted with the shape of its
	// own parent list.
	double sum = 0.0;
	int at = index;
	int guard = 0;
	while (at >= 0 && guard++ < (int)bone_.size() + 1) {
		sum += bone_[(size_t)at].angle;
		at = bone_[(size_t)at].parent;
	}
	return sum;
}

Vector2 IvoryRig360::pose_point(int index, const Vector2 &rest) const {
	// **Composed from the rest pose every time, never from the last pose.**
	// See the header: measuring from the last pose is what makes a sleeve
	// creep down an arm over a session.
	if (index < 0 || index >= (int)bone_.size()) {
		return rest;
	}
	Vector2 at = rest;
	int cursor = index;
	int guard = 0;
	while (cursor >= 0 && guard++ < (int)bone_.size() + 1) {
		const Bone &b = bone_[(size_t)cursor];
		if (b.angle != 0.0) {
			const double c = std::cos(b.angle);
			const double s = std::sin(b.angle);
			const double dx = (double)at.x - b.rest_head.x;
			const double dy = (double)at.y - b.rest_head.y;
			at = Vector2((real_t)(b.rest_head.x + dx * c - dy * s),
					(real_t)(b.rest_head.y + dx * s + dy * c));
		}
		cursor = b.parent;
	}
	return at;
}

Vector2 IvoryRig360::rest_point(int index, const Vector2 &now) const {
	// The exact inverse of `pose_point`: the same rotations, negated, in the
	// opposite order. This is what lets a stroke drawn on a posed figure be
	// stored as though it had been drawn on the rest one.
	if (index < 0 || index >= (int)bone_.size()) {
		return now;
	}
	std::vector<int> chain;
	int cursor = index;
	int guard = 0;
	while (cursor >= 0 && guard++ < (int)bone_.size() + 1) {
		chain.push_back(cursor);
		cursor = bone_[(size_t)cursor].parent;
	}
	Vector2 at = now;
	for (int i = (int)chain.size() - 1; i >= 0; --i) {
		const Bone &b = bone_[(size_t)chain[(size_t)i]];
		if (b.angle == 0.0) {
			continue;
		}
		const double c = std::cos(-b.angle);
		const double s = std::sin(-b.angle);
		const double dx = (double)at.x - b.rest_head.x;
		const double dy = (double)at.y - b.rest_head.y;
		at = Vector2((real_t)(b.rest_head.x + dx * c - dy * s),
				(real_t)(b.rest_head.y + dx * s + dy * c));
	}
	return at;
}

Vector2 IvoryRig360::posed_head(int index) const {
	return pose_point(index, rest_head(index));
}

Vector2 IvoryRig360::posed_tail(int index) const {
	return pose_point(index, rest_tail(index));
}

void IvoryRig360::set_angle(int index, double radians) {
	if (index < 0 || index >= (int)bone_.size()) {
		return;
	}
	const double lo = index < (int)min_angle_.size() ? min_angle_[(size_t)index] : -TAU;
	const double hi = index < (int)max_angle_.size() ? max_angle_[(size_t)index] : TAU;
	const double clamped = clampd(radians, std::min(lo, hi), std::max(lo, hi));
	if (std::fabs(clamped - bone_[(size_t)index].angle) < 1.0e-12) return;
	Undo u;
	u.what = String("angle");
	u.bone = (int32_t)index;
	u.before = bone_[(size_t)index].angle;
	note(u);
	bone_[(size_t)index].angle = clamped;
}

void IvoryRig360::set_angle_limits(int index, double min_radians, double max_radians) {
	if (index < 0 || index >= (int)bone_.size()) return;
	if (min_radians > max_radians) std::swap(min_radians, max_radians);
	min_angle_[(size_t)index] = (float)clampd(min_radians, -TAU, TAU);
	max_angle_[(size_t)index] = (float)clampd(max_radians, -TAU, TAU);
	set_angle(index, bone_[(size_t)index].angle);
}

Dictionary IvoryRig360::angle_limits(int index) const {
	Dictionary out;
	if (index < 0 || index >= (int)bone_.size()) return out;
	out["min"] = index < (int)min_angle_.size() ? min_angle_[(size_t)index] : -TAU;
	out["max"] = index < (int)max_angle_.size() ? max_angle_[(size_t)index] : TAU;
	return out;
}

PackedFloat32Array IvoryRig360::angles() const {
	PackedFloat32Array out;
	out.resize((int)bone_.size());
	for (int i = 0; i < (int)bone_.size(); ++i) out[i] = (float)bone_[(size_t)i].angle;
	return out;
}

double IvoryRig360::angle_of(int index) const {
	return index >= 0 && index < (int)bone_.size()
			? bone_[(size_t)index].angle : 0.0;
}

void IvoryRig360::rest_all() {
	for (Bone &b : bone_) {
		b.angle = 0.0;
	}
}


bool IvoryRig360::solve_ik(int end_bone, const Vector2 &target, int iterations, double tolerance) {
	if (end_bone < 0 || end_bone >= (int)bone_.size()) return false;
	iterations = std::clamp(iterations, 1, 12);
	tolerance = std::max(0.01, tolerance);
	const int root_guard = (int)bone_.size() + 1;
	for (int it = 0; it < iterations; ++it) {
		Vector2 tip = posed_tail(end_bone);
		if (tip.distance_to(target) <= tolerance) return true;
		int cursor = bone_[(size_t)end_bone].parent;
		int guard = 0;
		while (cursor >= 0 && guard++ < root_guard) {
			const Vector2 joint = posed_head(cursor);
			const Vector2 a = tip - joint;
			const Vector2 b = target - joint;
			if (a.length_squared() > 1e-10 && b.length_squared() > 1e-10) {
				double delta = std::atan2((double)a.cross(b), (double)a.dot(b));
				// Never introduce a giant one-frame jump from a noisy touch sample.
				delta = clampd(delta, -0.45, 0.45);
				set_angle(cursor, angle_of(cursor) + delta);
			}
			tip = posed_tail(end_bone);
			if (tip.distance_to(target) <= tolerance) return true;
			cursor = bone_[(size_t)cursor].parent;
		}
	}
	return posed_tail(end_bone).distance_to(target) <= tolerance;
}

bool IvoryRig360::drag_to(const Vector2 &at, double reach, const Vector2 &target,
		int iterations, double tolerance) {
	const int bone = pick(at, reach);
	if (bone < 0) return false;
	return solve_ik(bone, target, iterations, tolerance);
}

double IvoryRig360::segment_distance(const Vector2 &p, const Vector2 &a,
		const Vector2 &b) {
	const Vector2 ab = b - a;
	const double len2 = ab.length_squared();
	if (len2 < 1e-12) {
		return p.distance_to(a);
	}
	const double t = clampd(((p - a).dot(ab)) / len2, 0.0, 1.0);
	return p.distance_to(a + ab * (real_t)t);
}

int IvoryRig360::pick(const Vector2 &at, double reach) const {
	int best = -1;
	double best_d = std::max(reach, 0.0);
	for (size_t i = 0; i < bone_.size(); ++i) {
		// Against the posed bone, because that is what is under the finger.
		const double d = segment_distance(at, posed_head((int)i),
				posed_tail((int)i));
		if (d <= best_d) {
			best_d = d;
			best = (int)i;
		}
	}
	return best;
}

int IvoryRig360::owner_of(const Vector2 &at) const {
	// To the bone's *segment*, not its head. A long bone is a line, and
	// measuring to one end gives the shoulder ownership of the wrist.
	int best = -1;
	double best_d = 1e30;
	for (size_t i = 0; i < bone_.size(); ++i) {
		const double d = segment_distance(at, posed_head((int)i),
				posed_tail((int)i));
		if (d < best_d) {
			best_d = d;
			best = (int)i;
		}
	}
	return best;
}

// ----------------------------------------------------------- ink on the rig

int IvoryRig360::bind_stroke_to(int layer, const PackedVector2Array &points,
		int bone) {
	Stroke s;
	s.id = next_stroke_++;
	s.layer = (int32_t)std::max(layer, 0);
	const int owner = (bone >= 0 && bone < (int)bone_.size()) ? bone : -1;
	s.owner.reserve((size_t)points.size());
	s.local.reserve((size_t)points.size());
	for (int i = 0; i < points.size(); ++i) {
		s.owner.push_back((int32_t)owner);
		// Into the rest frame of its owner. This is the whole of "the
		// drawing rotates from the place where it started moving".
		s.local.push_back(rest_point(owner, points[i]));
	}
	stroke_.push_back(s);
	Undo u;
	u.what = String("bind_stroke");
	u.stroke = s.id;
	note(u);
	return s.id;
}

int IvoryRig360::bind_stroke(int layer, const PackedVector2Array &points) {
	// Whichever bone owns most of the stroke. Length-weighted rather than
	// counted, because a touch reports points as fast as the finger moves
	// and a slow start would otherwise outvote a long tail.
	std::vector<double> weight(bone_.size() + 1, 0.0);
	for (int i = 0; i < points.size(); ++i) {
		const int owner = owner_of(points[i]);
		const double run = i > 0 ? points[i].distance_to(points[i - 1]) : 1.0;
		weight[(size_t)(owner < 0 ? bone_.size() : owner)] += run + 0.001;
	}
	int best = -1;
	double best_w = 0.0;
	for (size_t i = 0; i < bone_.size(); ++i) {
		if (weight[i] > best_w) {
			best_w = weight[i];
			best = (int)i;
		}
	}
	return bind_stroke_to(layer, points, best);
}

int IvoryRig360::bind_stroke_spread(int layer,
		const PackedVector2Array &points) {
	Stroke s;
	s.id = next_stroke_++;
	s.layer = (int32_t)std::max(layer, 0);
	s.owner.reserve((size_t)points.size());
	s.local.reserve((size_t)points.size());
	for (int i = 0; i < points.size(); ++i) {
		const int owner = owner_of(points[i]);
		s.owner.push_back((int32_t)owner);
		s.local.push_back(rest_point(owner, points[i]));
	}
	stroke_.push_back(s);
	Undo u;
	u.what = String("bind_stroke");
	u.stroke = s.id;
	note(u);
	return s.id;
}

bool IvoryRig360::unbind_stroke(int id) {
	for (size_t i = 0; i < stroke_.size(); ++i) {
		if (stroke_[i].id == id) {
			stroke_.erase(stroke_.begin() + i);
			return true;
		}
	}
	return false;
}

PackedVector2Array IvoryRig360::stroke_now(int id) const {
	PackedVector2Array out;
	for (const Stroke &s : stroke_) {
		if (s.id != id) {
			continue;
		}
		out.resize((int)s.local.size());
		for (size_t i = 0; i < s.local.size(); ++i) {
			out[(int)i] = pose_point(s.owner[i], s.local[i]);
		}
		return out;
	}
	return out;
}

int IvoryRig360::stroke_layer(int id) const {
	for (const Stroke &s : stroke_) {
		if (s.id == id) {
			return s.layer;
		}
	}
	return -1;
}

// -------------------------------------------------------------- smart bones

void IvoryRig360::record_action(int driver, double angle, int target,
		double value) {
	if (driver < 0 || driver >= (int)bone_.size() || target < 0 ||
			target >= (int)bone_.size() || driver == target) {
		return;
	}
	// A second recording at the same angle replaces the first. Keeping both
	// would leave the interpolation with two answers at one place, and which
	// it picked would depend on the order they happened to be stored in.
	for (Action &a : action_) {
		if (a.driver == driver && a.target == target &&
				std::fabs(a.angle - angle) < 1e-4) {
			a.value = value;
			return;
		}
	}
	Action a;
	a.driver = (int32_t)driver;
	a.target = (int32_t)target;
	a.angle = angle;
	a.value = value;
	action_.push_back(a);
	std::sort(action_.begin(), action_.end(),
			[](const Action &x, const Action &y) {
				if (x.driver != y.driver) return x.driver < y.driver;
				if (x.target != y.target) return x.target < y.target;
				return x.angle < y.angle;
			});
	Undo u;
	u.what = String("record_action");
	u.bone = (int32_t)driver;
	note(u);
}

bool IvoryRig360::clear_actions(int driver) {
	const size_t was = action_.size();
	std::vector<Action> kept;
	for (const Action &a : action_) {
		if (a.driver != driver) {
			kept.push_back(a);
		}
	}
	action_.swap(kept);
	return action_.size() != was;
}

int IvoryRig360::action_count(int driver) const {
	int n = 0;
	for (const Action &a : action_) {
		if (a.driver == driver) {
			++n;
		}
	}
	return n;
}

double IvoryRig360::action_value(int driver, int target, double angle,
		bool &found) const {
	std::vector<const Action *> row;
	for (const Action &a : action_) {
		if (a.driver == driver && a.target == target) row.push_back(&a);
	}
	found = !row.empty();
	if (row.empty()) return 0.0;
	if (row.size() == 1) {
		const double at = row[0]->angle;
		if (std::fabs(at) < 1e-9) return row[0]->value;
		return row[0]->value * clampd(angle / at, -2.0, 2.0);
	}
	if (angle <= row.front()->angle) return row.front()->value;
	if (angle >= row.back()->angle) return row.back()->value;
	size_t k = 0;
	while (k + 1 < row.size() && row[k + 1]->angle < angle) ++k;
	const size_t km1 = k > 0 ? k - 1 : k;
	const size_t kp2 = k + 2 < row.size() ? k + 2 : k + 1;
	const double x0 = row[km1]->angle, x1 = row[k]->angle;
	const double x2 = row[k + 1]->angle, x3 = row[kp2]->angle;
	const double y0 = row[km1]->value, y1 = row[k]->value;
	const double y2 = row[k + 1]->value, y3 = row[kp2]->value;
	const double h = std::max(x2 - x1, 1e-9);
	// Fritsch-Carlson style monotone cubic slopes. Unlike Catmull-Rom this
	// cannot overshoot a recorded correction, so a smart bone never invents
	// a spike between artist-authored poses.
	auto slope = [](double xa, double xb, double ya, double yb) {
		const double h = xb - xa;
		return std::fabs(h) < 1e-12 ? 0.0 : (yb - ya) / h;
	};
	const double d0 = slope(x0, x1, y0, y1);
	const double d1 = slope(x1, x2, y1, y2);
	const double d2 = slope(x2, x3, y2, y3);
	auto tangent = [](double left, double right) {
		if (left * right <= 0.0) return 0.0;
		return (2.0 * left * right) / (left + right);
	};
	const double m1 = tangent(d0, d1);
	const double m2 = tangent(d1, d2);
	const double t = clampd((angle - x1) / h, 0.0, 1.0);
	const double t2 = t * t, t3 = t2 * t;
	const double H00 = 2*t3 - 3*t2 + 1;
	const double H10 = t3 - 2*t2 + t;
	const double H01 = -2*t3 + 3*t2;
	const double H11 = t3 - t2;
	return H00*y1 + H10*h*m1 + H01*y2 + H11*h*m2;
}

void IvoryRig360::apply_actions() {
	if (action_.empty()) {
		return;
	}
	// The driver angles are read first, all of them, before anything is
	// written. Reading and writing in one pass would let one action's answer
	// depend on whether another had already run, and the rig would settle
	// differently depending on the order the bones happened to be stored in.
	std::vector<double> driver_angle(bone_.size(), 0.0);
	for (size_t i = 0; i < bone_.size(); ++i) {
		driver_angle[i] = bone_[i].angle;
	}
	std::vector<double> next = driver_angle;
	std::vector<double> sum(bone_.size(), 0.0);
	std::vector<int> count(bone_.size(), 0);
	for (const Action &a : action_) {
		bool found = false;
		const double v = action_value(a.driver, a.target,
				driver_angle[(size_t)a.driver], found);
		if (found) { sum[(size_t)a.target] += v; ++count[(size_t)a.target]; }
	}
	for (size_t i = 0; i < bone_.size(); ++i) {
		if (count[i] > 0) {
			next[i] = sum[i] / (double)count[i];
			const double lo = min_angle_.empty() ? -TAU : min_angle_[i];
			const double hi = max_angle_.empty() ? TAU : max_angle_[i];
			next[i] = clampd(next[i], std::min(lo, hi), std::max(lo, hi));
		}
	}
	for (size_t i = 0; i < bone_.size(); ++i) {
		if (count[i] > 0) bone_[i].angle = next[i];
	}
}

// -------------------------------------------------------------------- layers

String IvoryRig360::next_layer_name() const {
	if (layer_.empty()) {
		return base_layer_name();
	}
	// Chosen against the names that exist, not by counting. Counting is how
	// two layers end up both called "(3)" after one is deleted.
	for (int n = 2; n < 10000; ++n) {
		String want = base_layer_name() + String(" (") +
				String::num_int64(n) + String(")");
		bool taken = false;
		for (const String &had : layer_) {
			if (had == want) {
				taken = true;
				break;
			}
		}
		if (!taken) {
			return want;
		}
	}
	return base_layer_name();
}

int IvoryRig360::add_layer() {
	// The first layer is the body, and it takes the plain name. Everything
	// after it is numbered — and it is still a Character 360 layer, not an
	// ordinary one, which is the whole point: a layer added in this file is
	// bound to the same rig without anybody having to ask for it.
	bool has_base = false;
	for (const String &had : layer_) {
		if (had == base_layer_name()) {
			has_base = true;
		}
	}
	layer_.push_back(has_base ? next_layer_name() : base_layer_name());
	Undo u;
	u.what = String("add_layer");
	u.layer = (int32_t)layer_.size() - 1;
	note(u);
	return (int)layer_.size() - 1;
}

bool IvoryRig360::remove_layer(int layer) {
	if (layer < 0 || layer >= (int)layer_.size()) {
		return false;
	}
	layer_.erase(layer_.begin() + layer);
	// Strokes on it go with it, and strokes above it shift down.
	std::vector<Stroke> kept;
	for (const Stroke &s : stroke_) {
		if (s.layer == layer) {
			continue;
		}
		Stroke t = s;
		if (t.layer > layer) {
			--t.layer;
		}
		kept.push_back(t);
	}
	stroke_.swap(kept);
	undo_.clear();
	return true;
}


int IvoryRig360::motion_layer_index() const {
	const String wanted = String("character 360 motion");
	for (int i = 0; i < (int)layer_.size(); ++i) {
		if (layer_[(size_t)i] == wanted) return i;
	}
	return -1;
}

int IvoryRig360::ensure_motion_layer() {
	const int existing = motion_layer_index();
	if (existing >= 0) return existing;
	layer_.push_back(String("character 360 motion"));
	return (int)layer_.size() - 1;
}

PackedStringArray IvoryRig360::layer_names() const {
	PackedStringArray out;
	for (const String &s : layer_) {
		out.append(s);
	}
	return out;
}

// ----------------------------------------------------------------------- out

Dictionary IvoryRig360::to_project() const {
	Dictionary out;
	PackedVector2Array rh, rt, ph, pt;
	PackedInt32Array parent, part;
	PackedFloat32Array angle;
	for (size_t i = 0; i < bone_.size(); ++i) {
		rh.append(bone_[i].rest_head);
		rt.append(bone_[i].rest_tail);
		ph.append(posed_head((int)i));
		pt.append(posed_tail((int)i));
		parent.append(bone_[i].parent);
		part.append(bone_[i].part);
		angle.append((float)bone_[i].angle);
	}
	out["format"] = String("ivory-character-360");
	out["version"] = 1;
	// Rest **and** pose. The rest pose is what the rig is; the pose is where
	// it happens to be. A file with only the pose cannot be re-posed, and a
	// file with only the rest cannot show what the person was looking at
	// when they pressed the button.
	out["rest_head"] = rh;
	out["rest_tail"] = rt;
	out["posed_head"] = ph;
	out["posed_tail"] = pt;
	out["parent"] = parent;
	out["part"] = part;
	out["angle"] = angle;
	out["layers"] = layer_names();
	out["motion_layer"] = motion_layer_index();
	out["controller_only"] = motion_layer_index() >= 0;

	Array strokes;
	for (const Stroke &s : stroke_) {
		Dictionary one;
		PackedVector2Array local;
		PackedInt32Array owner;
		for (size_t i = 0; i < s.local.size(); ++i) {
			local.append(s.local[i]);
			owner.append(s.owner[i]);
		}
		one["id"] = s.id;
		one["layer"] = s.layer;
		one["local"] = local;
		one["owner"] = owner;
		strokes.append(one);
	}
	out["strokes"] = strokes;

	Array actions;
	for (const Action &a : action_) {
		Dictionary one;
		one["driver"] = a.driver;
		one["target"] = a.target;
		one["angle"] = a.angle;
		one["value"] = a.value;
		actions.append(one);
	}
	out["actions"] = actions;
	return out;
}

Dictionary IvoryRig360::summary() const {
	Dictionary out;
	out["bones"] = bone_count();
	out["strokes"] = stroke_count();
	out["layers"] = layer_count();
	out["actions"] = (int)action_.size();
	int posed = 0;
	for (const Bone &b : bone_) {
		if (b.angle != 0.0) {
			++posed;
		}
	}
	out["posed"] = posed;
	int fingers = 0;
	for (const Bone &b : bone_) if (b.part == PART_FINGER) ++fingers;
	out["fingers"] = fingers;
	out["motion_layer"] = motion_layer_index();
	return out;
}

// -------------------------------------------------------------------- cancel

void IvoryRig360::note(const Undo &u) {
	undo_.push_back(u);
	if ((int)undo_.size() > UNDO_DEPTH) {
		undo_.erase(undo_.begin());
	}
}

Dictionary IvoryRig360::undo_last() {
	Dictionary out;
	out["ok"] = false;
	if (undo_.empty()) {
		return out;
	}
	const Undo u = undo_.back();
	undo_.pop_back();
	out["what"] = u.what;

	if (u.what == String("angle")) {
		if (u.bone >= 0 && u.bone < (int32_t)bone_.size()) {
			bone_[(size_t)u.bone].angle = u.before;
			out["ok"] = true;
		}
	} else if (u.what == String("add_bone")) {
		if (u.bone >= 0 && u.bone == (int32_t)bone_.size() - 1) {
			// Only the most recent bone, and only if it is still the most
			// recent. Anything else and the indices below it have moved.
			bone_.pop_back();
			out["ok"] = true;
		}
	} else if (u.what == String("bind_stroke")) {
		out["ok"] = unbind_stroke(u.stroke);
	} else if (u.what == String("add_layer")) {
		if (u.layer >= 0 && u.layer == (int32_t)layer_.size() - 1) {
			layer_.pop_back();
			out["ok"] = true;
		}
	} else if (u.what == String("record_action")) {
		if (!action_.empty()) {
			action_.pop_back();
			out["ok"] = true;
		}
	}
	return out;
}

void IvoryRig360::forget_undo() {
	undo_.clear();
}
