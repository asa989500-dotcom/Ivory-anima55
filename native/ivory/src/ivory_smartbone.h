#ifndef IVORY_SMARTBONE_H
#define IVORY_SMARTBONE_H

// Smart bones. The thing Moho calls a Smart Bone Dial, in C++.
//
// ================================================================
// What a smart bone actually is, because the name is misleading
// ================================================================
//
// A smart bone is not a cleverer bone. It is a **dial**: one bone whose angle
// drives a stored correction to the rest of the rig.
//
// The problem it solves is the oldest one in character rigging. Bend an elbow
// ninety degrees with any skinning method at all and the inside of the joint
// pinches — the weights on either side disagree and the flesh between them
// gets squeezed into a crease. You can fight it with better weights for a
// while and then you cannot, because the shape the artist wants at ninety
// degrees is not a smooth function of the shape at zero. It is a *different
// drawing*, and no interpolation of transforms will invent it.
//
// So Moho's answer, and this one: let the artist pose the joint at ninety
// degrees, fix it by hand, and store that fix. Then, whenever the elbow
// passes through ninety degrees on its way anywhere, the fix is faded in by
// exactly how far through it is. The rig is doing ordinary skinning plus a
// correction the artist authored, and the correction is what makes the
// difference between a rig that is impressive and a rig that is usable.
//
// ## The four decisions in here, and why each is the way it is
//
// ### 1. A dial holds keys at driver angles, not at frames
//
// This is the whole point and it is easy to get wrong. If the correction were
// keyed on the timeline it would only be right on the shot it was authored
// for. Keyed on the *driver's angle*, it is right every time the elbow passes
// through that angle, in every shot, forever, including in shots animated
// years later by somebody else. That is what makes it worth authoring.
//
// ### 2. Corrections are added, never substituted
//
// `bone_turns` and `point_offsets` return **deltas**. The base skinning result
// is computed as it always was and the correction is added on top. Two
// reasons. A build of the app without this library still poses correctly, only
// without the corrections — which is the rule the whole native layer follows.
// And an artist can delete every dial and get back exactly the rig they had.
//
// ### 3. Between keys it interpolates, and past the ends it holds
//
// Interpolation is Catmull–Rom, which passes exactly through every key: at the
// angle the artist authored, they get the shape they authored, not a smoothed
// approximation of it. That matters — an artist who fixes an elbow at ninety
// degrees and then sees something slightly different at ninety degrees stops
// trusting the tool.
//
// Past the last key it **holds the last key** and does not extrapolate. A
// cubic run past its data grows without bound, and a correction growing
// without bound is a limb turning inside out the moment somebody drags a
// little further than the artist tested. Holding is occasionally
// unambitious. Exploding is never acceptable.
//
// Catmull–Rom does overshoot *between* keys, by design, and mild overshoot is
// what makes a correction read as flesh rather than as a lookup table. When
// that is not wanted — a mechanical joint, a prop — `set_overshoot(false)`
// clamps each result to the range of the two keys bracketing it, which costs
// two comparisons and gives back the monotone answer.
//
// ### 4. A dial may not drive its own driver, at any remove
//
// A dial that corrects the bone that drives it is a feedback loop: the
// correction changes the angle, the angle changes the correction. It does not
// converge, it oscillates, and it does so at the frame rate — which on screen
// looks like the rig has started shaking for no reason. `add_key_bone`
// refuses it outright, including through a chain of dials, by walking the
// dial graph. Refusing at the moment of authoring is the only place this can
// be explained; refusing at solve time is a shake with no message attached.
//
// ## Cost
//
// A dial resolve is a binary search over its keys and one cubic per affected
// bone. A rig with thirty dials and eighty bones resolves in a few
// microseconds, which is the point: this runs on every touch event, in front
// of the finger, and it may not be the reason a drag drops a frame.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvorySmartBone : public RefCounted {
	GDCLASS(IvorySmartBone, RefCounted)

protected:
	static void _bind_methods();

public:
	IvorySmartBone() = default;
	~IvorySmartBone() = default;

	// --- dials ---

	// A new dial driven by `driver_bone`. Returns its index.
	int add_dial(int driver_bone);
	void remove_dial(int dial);
	void clear();
	int dial_count() const { return (int)dial_.size(); }
	int dial_driver(int dial) const;

	// Whether a dial fades out again past its last key (`false`, the
	// default: it holds) — see the note above.
	void set_overshoot(bool on) { overshoot_ = on; }
	bool overshoot() const { return overshoot_; }

	// --- keys ---

	// A key at `angle` radians of the driver, measured from the driver's
	// rest angle. Keys may be added in any order; they are kept sorted.
	// Adding a key at an angle that already has one replaces it, which is
	// what re-posing the same dial position means.
	int add_key(int dial, double angle);
	int key_count(int dial) const;
	double key_angle(int dial, int key) const;
	void remove_key(int dial, int key);

	// The correction this key applies to one bone: an extra turn in radians
	// and a length multiplier. A bone with no entry on a key is corrected by
	// nothing there, which is the identity — so an artist only stores the
	// bones they actually touched.
	//
	// Returns false when the bone is refused: driving the dial's own driver,
	// directly or through another dial, is a feedback loop and is not
	// allowed. See the note above.
	bool set_key_bone(int dial, int key, int bone, double turn, double stretch);
	void clear_key_bone(int dial, int key, int bone);

	// The correction this key applies to one mesh point, in page units, in
	// the rest frame. Added after skinning.
	void set_key_offset(int dial, int key, int point, const Vector2 &offset);
	void clear_key_offset(int dial, int key, int point);

	// --- driving ---

	// Where the driver bone is now, in radians from its rest angle.
	void set_driver_angle(int dial, double angle);
	double driver_angle(int dial) const;

	// Every dial's contribution to every bone, resolved and summed.
	// `bone_count` sizes the answer; bones nothing touches come back at the
	// identity — nought turn, one stretch.
	PackedFloat32Array bone_turns(int bone_count) const;
	PackedFloat32Array bone_stretches(int bone_count) const;

	// Every dial's contribution to every mesh point, resolved and summed.
	PackedVector2Array point_offsets(int point_count) const;

	// One dial's weight on each of its keys at the current driver angle.
	// Sums to one. Exposed because it is the thing to look at when a
	// correction is not appearing where the artist expects, and because
	// every test in `test_smartbone.cpp` leans on it.
	PackedFloat32Array key_weights(int dial) const;

	// --- saving ---

	Dictionary to_project() const;
	void from_project(const Dictionary &state);

private:
	// One bone's correction on one key.
	struct BoneFix {
		int32_t bone = 0;
		float turn = 0.0f;
		float stretch = 1.0f;
	};
	// One mesh point's correction on one key.
	struct PointFix {
		int32_t point = 0;
		Vector2 offset;
	};
	struct Key {
		float angle = 0.0f;
		std::vector<BoneFix> bone;
		std::vector<PointFix> point;
	};
	struct Dial {
		int32_t driver = -1;
		float angle = 0.0f;   // where the driver is now
		bool live = true;
		std::vector<Key> key; // sorted by angle
	};

	std::vector<Dial> dial_;
	bool overshoot_ = true;

	bool dial_ok(int dial) const {
		return dial >= 0 && dial < (int)dial_.size() && dial_[dial].live;
	}
	// Catmull-Rom weights over the keys of `d` at `angle`, into `out`.
	void weights_for(const Dial &d, double angle, std::vector<float> &out) const;
	// True when `bone` drives `dial`, directly or through another dial.
	bool feeds_back(int dial, int bone) const;
};

} // namespace godot

#endif // IVORY_SMARTBONE_H
