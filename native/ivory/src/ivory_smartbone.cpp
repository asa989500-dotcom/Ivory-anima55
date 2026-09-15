#include "ivory_smartbone.h"

#include <algorithm>
#include <cmath>

using namespace godot;

// The angle two keys have to differ by before they count as two keys. A dial
// dragged by a finger produces angles a ten-thousandth of a radian apart, and
// two keys that close are one key with a division by nearly nought between
// them.
static const double SAME_ANGLE = 1e-4;

int IvorySmartBone::add_dial(int driver_bone) {
	Dial d;
	d.driver = driver_bone;
	d.live = true;
	// A slot that a previous `remove_dial` retired is reused, so indices
	// handed out earlier keep meaning what they meant. Compacting the vector
	// would renumber every dial above the removed one, and every key the
	// artist authored refers to dials by index.
	for (int i = 0; i < (int)dial_.size(); ++i) {
		if (!dial_[i].live) {
			dial_[i] = d;
			return i;
		}
	}
	dial_.push_back(d);
	return (int)dial_.size() - 1;
}

void IvorySmartBone::remove_dial(int dial) {
	if (dial < 0 || dial >= (int)dial_.size()) {
		return;
	}
	dial_[dial] = Dial();
	dial_[dial].live = false;
}

void IvorySmartBone::clear() {
	dial_.clear();
}

int IvorySmartBone::dial_driver(int dial) const {
	return dial_ok(dial) ? dial_[dial].driver : -1;
}

// --------------------------------------------------------------------- keys

int IvorySmartBone::add_key(int dial, double angle) {
	if (!dial_ok(dial)) {
		return -1;
	}
	Dial &d = dial_[dial];
	for (int i = 0; i < (int)d.key.size(); ++i) {
		if (std::fabs((double)d.key[i].angle - angle) < SAME_ANGLE) {
			// Re-posing the dial where it already has a key means replacing
			// that key, not stacking a second one a hair away from it.
			return i;
		}
	}
	Key k;
	k.angle = (float)angle;
	d.key.push_back(k);
	std::sort(d.key.begin(), d.key.end(),
			[](const Key &a, const Key &b) { return a.angle < b.angle; });
	for (int i = 0; i < (int)d.key.size(); ++i) {
		if (std::fabs((double)d.key[i].angle - angle) < SAME_ANGLE) {
			return i;
		}
	}
	return -1;
}

int IvorySmartBone::key_count(int dial) const {
	return dial_ok(dial) ? (int)dial_[dial].key.size() : 0;
}

double IvorySmartBone::key_angle(int dial, int key) const {
	if (!dial_ok(dial) || key < 0 || key >= (int)dial_[dial].key.size()) {
		return 0.0;
	}
	return dial_[dial].key[key].angle;
}

void IvorySmartBone::remove_key(int dial, int key) {
	if (!dial_ok(dial) || key < 0 || key >= (int)dial_[dial].key.size()) {
		return;
	}
	dial_[dial].key.erase(dial_[dial].key.begin() + key);
}

bool IvorySmartBone::feeds_back(int dial, int bone) const {
	// Walk out from `bone`: if it drives this dial, or drives a dial that
	// corrects a bone that drives this dial, and so on, we have a loop.
	//
	// Written breadth-first over a small explicit list rather than
	// recursively, because a malformed saved file could otherwise be a
	// stack overflow rather than a refused key.
	if (!dial_ok(dial)) {
		return false;
	}
	std::vector<int32_t> front;
	std::vector<int32_t> seen;
	front.push_back(bone);
	for (int guard = 0; guard < 4096 && !front.empty(); ++guard) {
		const int32_t b = front.back();
		front.pop_back();
		if (std::find(seen.begin(), seen.end(), b) != seen.end()) {
			continue;
		}
		seen.push_back(b);
		if (b == dial_[dial].driver) {
			return true;
		}
		// Anything `b` drives is one step further out.
		for (const Dial &other : dial_) {
			if (!other.live || other.driver != b) {
				continue;
			}
			for (const Key &k : other.key) {
				for (const BoneFix &f : k.bone) {
					front.push_back(f.bone);
				}
			}
		}
	}
	return false;
}

bool IvorySmartBone::set_key_bone(int dial, int key, int bone, double turn,
		double stretch) {
	if (!dial_ok(dial) || key < 0 || key >= (int)dial_[dial].key.size()) {
		return false;
	}
	if (bone < 0) {
		return false;
	}
	if (feeds_back(dial, bone)) {
		// The loop this refuses does not fail loudly at solve time. It
		// oscillates at the frame rate, which reads as the rig shaking, and
		// there is nowhere at solve time to say why.
		return false;
	}
	// A stretch of nought or less is a bone of no length, and a rig with a
	// zero-length bone has a joint with no direction: every angle off it
	// becomes undefined and the limb below it spins. Held above a hair.
	const double s = stretch < 0.01 ? 0.01 : (stretch > 100.0 ? 100.0 : stretch);
	Key &k = dial_[dial].key[key];
	for (BoneFix &f : k.bone) {
		if (f.bone == bone) {
			f.turn = (float)turn;
			f.stretch = (float)s;
			return true;
		}
	}
	BoneFix f;
	f.bone = (int32_t)bone;
	f.turn = (float)turn;
	f.stretch = (float)s;
	k.bone.push_back(f);
	return true;
}

void IvorySmartBone::clear_key_bone(int dial, int key, int bone) {
	if (!dial_ok(dial) || key < 0 || key >= (int)dial_[dial].key.size()) {
		return;
	}
	std::vector<BoneFix> &v = dial_[dial].key[key].bone;
	for (int i = 0; i < (int)v.size(); ++i) {
		if (v[i].bone == bone) {
			v.erase(v.begin() + i);
			return;
		}
	}
}

void IvorySmartBone::set_key_offset(int dial, int key, int point,
		const Vector2 &offset) {
	if (!dial_ok(dial) || key < 0 || key >= (int)dial_[dial].key.size()) {
		return;
	}
	if (point < 0) {
		return;
	}
	Key &k = dial_[dial].key[key];
	for (PointFix &f : k.point) {
		if (f.point == point) {
			f.offset = offset;
			return;
		}
	}
	PointFix f;
	f.point = (int32_t)point;
	f.offset = offset;
	k.point.push_back(f);
}

void IvorySmartBone::clear_key_offset(int dial, int key, int point) {
	if (!dial_ok(dial) || key < 0 || key >= (int)dial_[dial].key.size()) {
		return;
	}
	std::vector<PointFix> &v = dial_[dial].key[key].point;
	for (int i = 0; i < (int)v.size(); ++i) {
		if (v[i].point == point) {
			v.erase(v.begin() + i);
			return;
		}
	}
}

// ------------------------------------------------------------------ driving

void IvorySmartBone::set_driver_angle(int dial, double angle) {
	if (!dial_ok(dial)) {
		return;
	}
	// Not wrapped. A dial's range is measured from the driver's rest angle
	// and an elbow does not go round; wrapping at pi would make a dial keyed
	// at 3.0 and one keyed at -3.0 fight over an angle six tenths of a
	// radian from either, which is the wrong answer by a long way.
	dial_[dial].angle = (float)angle;
}

double IvorySmartBone::driver_angle(int dial) const {
	return dial_ok(dial) ? dial_[dial].angle : 0.0;
}

void IvorySmartBone::weights_for(const Dial &d, double angle,
		std::vector<float> &out) const {
	const int n = (int)d.key.size();
	out.assign(n < 0 ? 0 : n, 0.0f);
	if (n == 0) {
		return;
	}
	if (n == 1) {
		out[0] = 1.0f;
		return;
	}
	// Past either end: hold. Not extrapolate. See the header.
	if (angle <= d.key[0].angle) {
		out[0] = 1.0f;
		return;
	}
	if (angle >= d.key[n - 1].angle) {
		out[n - 1] = 1.0f;
		return;
	}

	// The bracketing pair. Binary search rather than a walk, because a dial
	// with a key every two degrees over a full bend has ninety of them and
	// this runs per dial per touch event.
	int lo = 0;
	int hi = n - 1;
	while (hi - lo > 1) {
		const int mid = (lo + hi) / 2;
		if (d.key[mid].angle <= angle) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	const double span = (double)d.key[hi].angle - (double)d.key[lo].angle;
	// Two keys closer together than SAME_ANGLE cannot both exist — add_key
	// merges them — so this is belt and braces against a hand-edited file.
	const double t = span > SAME_ANGLE
			? ((angle - (double)d.key[lo].angle) / span)
			: 0.0;

	if (!overshoot_) {
		// Monotone: a smoothstep between the two, and nothing from the
		// neighbours. Exactly on a key it is exactly that key.
		const double s = t * t * (3.0 - 2.0 * t);
		out[lo] = (float)(1.0 - s);
		out[hi] = (float)s;
		return;
	}

	// Catmull-Rom. The neighbours outside the segment are clamped to the
	// ends, which is the standard natural end condition and means a dial
	// with two keys behaves as a plain smooth blend rather than as a cubic
	// with nothing to hold its ends down.
	const int a = lo - 1 < 0 ? 0 : lo - 1;
	const int b = lo;
	const int c = hi;
	const int e = hi + 1 > n - 1 ? n - 1 : hi + 1;

	const double t2 = t * t;
	const double t3 = t2 * t;
	// The standard basis, written out. These sum to one at every t, which
	// is what makes the correction a blend rather than a scaling.
	const double wa = -0.5 * t + t2 - 0.5 * t3;
	const double wb = 1.0 - 2.5 * t2 + 1.5 * t3;
	const double wc = 0.5 * t + 2.0 * t2 - 1.5 * t3;
	const double we = -0.5 * t2 + 0.5 * t3;

	out[a] += (float)wa;
	out[b] += (float)wb;
	out[c] += (float)wc;
	out[e] += (float)we;
}

PackedFloat32Array IvorySmartBone::key_weights(int dial) const {
	PackedFloat32Array out;
	if (!dial_ok(dial)) {
		return out;
	}
	std::vector<float> w;
	weights_for(dial_[dial], dial_[dial].angle, w);
	out.resize((int)w.size());
	for (int i = 0; i < (int)w.size(); ++i) {
		out[i] = w[i];
	}
	return out;
}

PackedFloat32Array IvorySmartBone::bone_turns(int bone_count) const {
	PackedFloat32Array out;
	if (bone_count <= 0) {
		return out;
	}
	out.resize(bone_count);
	for (int i = 0; i < bone_count; ++i) {
		out[i] = 0.0f;
	}
	std::vector<float> w;
	for (const Dial &d : dial_) {
		if (!d.live || d.key.empty()) {
			continue;
		}
		weights_for(d, d.angle, w);
		for (int k = 0; k < (int)d.key.size(); ++k) {
			const float kw = w[k];
			if (kw == 0.0f) {
				continue;
			}
			for (const BoneFix &f : d.key[k].bone) {
				if (f.bone >= 0 && f.bone < bone_count) {
					out[f.bone] += kw * f.turn;
				}
			}
		}
	}
	return out;
}

PackedFloat32Array IvorySmartBone::bone_stretches(int bone_count) const {
	PackedFloat32Array out;
	if (bone_count <= 0) {
		return out;
	}
	out.resize(bone_count);
	for (int i = 0; i < bone_count; ++i) {
		out[i] = 1.0f;
	}
	// Stretches are blended in the log, and multiplied together across
	// dials. Two dials each halving a bone give a quarter, which is what
	// multiplying means; averaging them would give a half and the second
	// dial would have done nothing.
	//
	// The log matters for the same reason it matters everywhere else in
	// this app: the midpoint between half and double is one, not 1.25.
	std::vector<float> w;
	std::vector<double> log_sum;
	log_sum.assign(bone_count, 0.0);
	for (const Dial &d : dial_) {
		if (!d.live || d.key.empty()) {
			continue;
		}
		weights_for(d, d.angle, w);
		for (int k = 0; k < (int)d.key.size(); ++k) {
			const float kw = w[k];
			if (kw == 0.0f) {
				continue;
			}
			for (const BoneFix &f : d.key[k].bone) {
				if (f.bone >= 0 && f.bone < bone_count) {
					log_sum[f.bone] += (double)kw * std::log((double)f.stretch);
				}
			}
		}
	}
	for (int i = 0; i < bone_count; ++i) {
		double s = std::exp(log_sum[i]);
		if (s < 0.01) {
			s = 0.01;
		} else if (s > 100.0) {
			s = 100.0;
		}
		out[i] = (float)s;
	}
	return out;
}

PackedVector2Array IvorySmartBone::point_offsets(int point_count) const {
	PackedVector2Array out;
	if (point_count <= 0) {
		return out;
	}
	out.resize(point_count);
	for (int i = 0; i < point_count; ++i) {
		out[i] = Vector2();
	}
	std::vector<float> w;
	for (const Dial &d : dial_) {
		if (!d.live || d.key.empty()) {
			continue;
		}
		weights_for(d, d.angle, w);
		for (int k = 0; k < (int)d.key.size(); ++k) {
			const float kw = w[k];
			if (kw == 0.0f) {
				continue;
			}
			for (const PointFix &f : d.key[k].point) {
				if (f.point >= 0 && f.point < point_count) {
					out[f.point] += f.offset * kw;
				}
			}
		}
	}
	return out;
}

// ------------------------------------------------------------------- saving

Dictionary IvorySmartBone::to_project() const {
	Dictionary out;
	out["format"] = String("ivory.smartbone.v1");
	out["overshoot"] = overshoot_;
	Array dials;
	for (const Dial &d : dial_) {
		Dictionary dd;
		dd["live"] = d.live;
		dd["driver"] = (int)d.driver;
		dd["angle"] = (double)d.angle;
		Array keys;
		for (const Key &k : d.key) {
			Dictionary kk;
			kk["angle"] = (double)k.angle;
			PackedInt32Array bones;
			PackedFloat32Array turns;
			PackedFloat32Array stretches;
			for (const BoneFix &f : k.bone) {
				bones.append(f.bone);
				turns.append(f.turn);
				stretches.append(f.stretch);
			}
			kk["bone"] = bones;
			kk["turn"] = turns;
			kk["stretch"] = stretches;
			PackedInt32Array pts;
			PackedVector2Array offs;
			for (const PointFix &f : k.point) {
				pts.append(f.point);
				offs.append(f.offset);
			}
			kk["point"] = pts;
			kk["offset"] = offs;
			keys.append(kk);
		}
		dd["key"] = keys;
		dials.append(dd);
	}
	out["dial"] = dials;
	return out;
}

void IvorySmartBone::from_project(const Dictionary &state) {
	dial_.clear();
	overshoot_ = (bool)state.get("overshoot", true);
	const Array dials = state.get("dial", Array());
	for (int i = 0; i < dials.size(); ++i) {
		const Dictionary dd = dials[i];
		Dial d;
		d.live = (bool)dd.get("live", true);
		d.driver = (int)dd.get("driver", -1);
		d.angle = (float)(double)dd.get("angle", 0.0);
		const Array keys = dd.get("key", Array());
		for (int j = 0; j < keys.size(); ++j) {
			const Dictionary kk = keys[j];
			Key k;
			k.angle = (float)(double)kk.get("angle", 0.0);
			const PackedInt32Array bones = kk.get("bone", PackedInt32Array());
			const PackedFloat32Array turns = kk.get("turn", PackedFloat32Array());
			const PackedFloat32Array stretches =
					kk.get("stretch", PackedFloat32Array());
			for (int b = 0; b < bones.size(); ++b) {
				BoneFix f;
				f.bone = bones[b];
				f.turn = b < turns.size() ? turns[b] : 0.0f;
				f.stretch = b < stretches.size() ? stretches[b] : 1.0f;
				if (f.stretch < 0.01f) {
					f.stretch = 0.01f;
				}
				k.bone.push_back(f);
			}
			const PackedInt32Array pts = kk.get("point", PackedInt32Array());
			const PackedVector2Array offs =
					kk.get("offset", PackedVector2Array());
			for (int b = 0; b < pts.size(); ++b) {
				PointFix f;
				f.point = pts[b];
				f.offset = b < offs.size() ? offs[b] : Vector2();
				k.point.push_back(f);
			}
			d.key.push_back(k);
		}
		// A file could have been hand-edited, or written by a version that
		// sorted differently. Everything downstream assumes sorted keys, so
		// this is the one place to make that true rather than to hope.
		std::sort(d.key.begin(), d.key.end(),
				[](const Key &a, const Key &b) { return a.angle < b.angle; });
		dial_.push_back(d);
	}
}

void IvorySmartBone::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_dial", "driver_bone"),
			&IvorySmartBone::add_dial);
	ClassDB::bind_method(D_METHOD("remove_dial", "dial"),
			&IvorySmartBone::remove_dial);
	ClassDB::bind_method(D_METHOD("clear"), &IvorySmartBone::clear);
	ClassDB::bind_method(D_METHOD("dial_count"), &IvorySmartBone::dial_count);
	ClassDB::bind_method(D_METHOD("dial_driver", "dial"),
			&IvorySmartBone::dial_driver);
	ClassDB::bind_method(D_METHOD("set_overshoot", "on"),
			&IvorySmartBone::set_overshoot);
	ClassDB::bind_method(D_METHOD("overshoot"), &IvorySmartBone::overshoot);
	ClassDB::bind_method(D_METHOD("add_key", "dial", "angle"),
			&IvorySmartBone::add_key);
	ClassDB::bind_method(D_METHOD("key_count", "dial"),
			&IvorySmartBone::key_count);
	ClassDB::bind_method(D_METHOD("key_angle", "dial", "key"),
			&IvorySmartBone::key_angle);
	ClassDB::bind_method(D_METHOD("remove_key", "dial", "key"),
			&IvorySmartBone::remove_key);
	ClassDB::bind_method(
			D_METHOD("set_key_bone", "dial", "key", "bone", "turn", "stretch"),
			&IvorySmartBone::set_key_bone);
	ClassDB::bind_method(D_METHOD("clear_key_bone", "dial", "key", "bone"),
			&IvorySmartBone::clear_key_bone);
	ClassDB::bind_method(
			D_METHOD("set_key_offset", "dial", "key", "point", "offset"),
			&IvorySmartBone::set_key_offset);
	ClassDB::bind_method(D_METHOD("clear_key_offset", "dial", "key", "point"),
			&IvorySmartBone::clear_key_offset);
	ClassDB::bind_method(D_METHOD("set_driver_angle", "dial", "angle"),
			&IvorySmartBone::set_driver_angle);
	ClassDB::bind_method(D_METHOD("driver_angle", "dial"),
			&IvorySmartBone::driver_angle);
	ClassDB::bind_method(D_METHOD("bone_turns", "bone_count"),
			&IvorySmartBone::bone_turns);
	ClassDB::bind_method(D_METHOD("bone_stretches", "bone_count"),
			&IvorySmartBone::bone_stretches);
	ClassDB::bind_method(D_METHOD("point_offsets", "point_count"),
			&IvorySmartBone::point_offsets);
	ClassDB::bind_method(D_METHOD("key_weights", "dial"),
			&IvorySmartBone::key_weights);
	ClassDB::bind_method(D_METHOD("to_project"), &IvorySmartBone::to_project);
	ClassDB::bind_method(D_METHOD("from_project", "state"),
			&IvorySmartBone::from_project);
}
