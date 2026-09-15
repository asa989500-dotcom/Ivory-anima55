#ifndef IVORY_POSE_H
#define IVORY_POSE_H

// Posing a skeleton: what is allowed to move, how steadily it moves, and what
// the timeline is told about it afterwards.
//
// ## Locking what is above
//
// The request: pressing the circle on a bone should hold **everything above it
// completely still**, so that only that bone and the chain hanging below it
// can be moved.
//
// This is not a convenience. Every inverse-kinematics solver in the app —
// FABRIK, the two-bone closed form — reaches a target by *distributing* the
// bend over the whole chain up to the root. That is the right default and it
// is exactly wrong when somebody is trying to place a hand: they pull the
// hand, and the shoulder and the spine drift, and the drawing they had spent
// ten minutes on is now standing differently. Every one of those small drifts
// is correct arithmetic and all of them together are a ruined pose.
//
// So a frozen bone is treated as a **root**. Chain collection stops there,
// the solver is handed a shorter chain, and the arithmetic above the freeze is
// not merely undone afterwards — it never runs. Undoing it afterwards would
// leave the joints a rounding error apart, and a rig whose joints are a
// rounding error apart is a rig that visibly opens gaps when it is moved
// quickly.
//
// ## The cascade
//
// The other half of the request: after the bones have been placed, tapping
// twice gives a *sequential* lock over the whole skeleton — everything held,
// and only the part below whatever is touched free to move.
//
// So `cascade` freezes every bone, and `open_below` then releases one bone and
// its descendants. The two together are the mode: pick a joint, and only it
// and what hangs off it answer to the finger. Picking a different joint moves
// the opening rather than adding a second one, because two openings in a
// cascade is not a cascade, it is the unlocked rig with extra steps.
//
// ## Whole parts, never distortion
//
// A bone moves its subtree by **one rigid transform**: one rotation about one
// pivot, applied to every point below. Not re-solved per bone, not re-fitted —
// carried. The test for it is direct and is in `test_pose.cpp`: the distance
// between any two points of a moved subtree is the same afterwards as before,
// to the last bit a float can hold. Anything that is not a rigid transform
// fails that, and anything that fails it is a distortion however small.
//
// ## Why it stopped shuddering
//
// A joint grabbed and held still used to twitch. The cause is not noise alone;
// it is noise **through a solver**. A pixel of jitter at the fingertip is a
// pixel of jitter in the target, the solver honours it, the whole chain bends
// a little to serve it, and a whole limb visibly shivers in answer to
// something nobody did.
//
// Filtering harder is the obvious answer and it is the wrong one, because a
// filter strong enough to kill the twitch is a filter that lags the drag.
//
// What is used instead is a **Schmitt trigger on the intent to move**: while
// the joint is still, it takes a real movement to start it going; once going,
// a much smaller one keeps it going. Two thresholds, not one. One threshold
// puts the decision boundary somewhere, the hand sits on it, and the answer
// flickers several times a second — which is precisely the shudder. Two
// thresholds mean there is no single boundary to sit on.
//
// ## What the timeline is told
//
// One layer has to carry three kinds of motion at once, without any of them
// pushing the others out:
//
//   * **`TRACK_DRAW`** — frames drawn one at a time, and everything derived
//     from that: duplicate-after, holds, and so on.
//   * **`TRACK_WARP`** — puppet warp pins.
//   * **`TRACK_RIG`** — this skeleton.
//
// They coexist because they answer different questions. Draw says *what the
// picture is* on this frame; rig says *how its parts are arranged*; warp says
// *how that arrangement is bent*. So the order is fixed and is not a
// preference: **draw, then rig, then warp.** Warping first and then posing
// would move the pins away from the ink they were placed on, and the drawing
// would come apart in a way that looks like a bug and is a definition
// problem.
//
// A frame is made — and the onion skin and the frame dot appear — when the
// pose has actually moved past a threshold since the last key. Not when the
// finger goes down, because a tap that moves nothing would litter the
// timeline with identical keys, and a timeline full of keys that change
// nothing is worse than an empty one: it cannot be scrubbed.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvoryPose : public RefCounted {
	GDCLASS(IvoryPose, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryPose() = default;
	~IvoryPose() = default;

	enum Track {
		TRACK_DRAW = 1,
		TRACK_RIG = 2,
		TRACK_WARP = 4,
	};

	// --- the skeleton ---

	void set_skeleton(const PackedVector2Array &head,
			const PackedVector2Array &tail, const PackedInt32Array &parent);
	int bone_count() const { return (int)head_.size(); }
	PackedVector2Array head() const;
	PackedVector2Array tail() const;

	// --- freezing ---

	// Holds every bone from `index` up to its root. Only `index` and what
	// hangs below it can move afterwards.
	void lock_above(int index);
	// Holds everything. The state the double tap puts the rig into.
	void cascade();
	// Releases one bone and its descendants, and freezes everything else.
	// Moving the opening rather than adding one, on purpose: see the header.
	void open_below(int index);
	void unlock_all();

	bool frozen(int index) const;
	PackedInt32Array frozen_bones() const;
	int frozen_count() const;
	// Whether the rig is in the cascade mode at all, which is what the
	// interface shows on the circle.
	bool cascading() const { return cascading_; }

	// Which bones a drag of `index` is actually allowed to alter. Exposed
	// because a person should be able to see what they are about to move
	// before they move it.
	PackedInt32Array movable_from(int index) const;

	// --- the double tap that turns the cascade on ---

	// A tap on a bone's circle. `now` is a timestamp in seconds.
	//
	// Returns what the tap meant: the first one selects, a second on the
	// same circle within the window turns the cascade on and opens below
	// that bone, and a third turns it off again — so the same circle is the
	// way in and the way out.
	Dictionary tap(int index, double now);

	// --- dragging ---

	// Begins a drag on a joint: `index * 2 + which`, matching `IvoryBone`.
	void begin_drag(int handle);
	bool dragging() const { return drag_bone_ >= 0; }

	// One frame of the drag. Returns whether the rig actually moved, which
	// is the Schmitt trigger's answer and not simply whether the finger did.
	Dictionary drag(const Vector2 &to);
	Dictionary end_drag();

	// How far the finger must move to start the rig moving, and how far to
	// keep it moving. The second must be the smaller of the two or there is
	// no hysteresis and the shudder comes back; that is enforced here rather
	// than trusted to the caller.
	void set_steadiness(double start_px, double keep_px);

	// --- the timeline ---

	// Which kinds of motion this layer carries.
	void set_tracks(int mask);
	int tracks() const { return tracks_; }
	// Adds a kind without disturbing the others. This is the whole of "one
	// layer takes frame-by-frame and puppet warp and a bone rig".
	void allow_track(int kind);
	bool allows(int kind) const;

	// The order the tracks are applied in at a frame, and which of them have
	// something to say there. Returns `order` as an array of `Track` values.
	Dictionary plan_at(int frame) const;

	// Records that a track has a key on a frame.
	void put_key(int kind, int frame);
	void clear_keys();
	bool has_key(int kind, int frame) const;
	PackedInt32Array keys_of(int kind) const;

	// How far the pose has moved since the last key was taken.
	double drift() const;
	// Whether that is enough to be worth a frame of its own.
	bool wants_key() const;
	// Takes one: remembers the pose, records the key, and says what the
	// interface should now show.
	Dictionary make_key(int frame);
	void set_key_threshold(double px);

	// What the timeline should be showing right now: whether the bone layer
	// has just built a frame, whether the onion skin should be on, and where
	// the frame dot goes.
	Dictionary timeline_state(int frame) const;

private:
	std::vector<Vector2> head_;
	std::vector<Vector2> tail_;
	std::vector<int32_t> parent_;
	std::vector<float> length_;
	std::vector<uint8_t> frozen_;
	std::vector<int32_t> kids_;
	std::vector<int32_t> kid_at_;

	bool cascading_ = false;
	int opened_ = -1;

	int tap_bone_ = -1;
	double tap_at_ = -1.0e30;
	static constexpr double TAP_WINDOW = 0.55;

	int drag_bone_ = -1;
	int drag_which_ = 0;
	bool moving_ = false;
	Vector2 drag_from_;
	Vector2 last_target_;

	double start_px_ = 3.0;
	double keep_px_ = 0.7;

	int tracks_ = TRACK_DRAW;
	std::vector<int32_t> draw_keys_;
	std::vector<int32_t> rig_keys_;
	std::vector<int32_t> warp_keys_;

	std::vector<Vector2> keyed_head_;
	std::vector<Vector2> keyed_tail_;
	bool have_key_pose_ = false;
	int last_key_frame_ = -1;
	bool just_made_ = false;
	double key_px_ = 2.5;

	void rebuild_kids();
	void carry(int index, const Vector2 &pivot, double turn);
	void gather_below(int index, std::vector<int32_t> &into) const;
	const std::vector<int32_t> *bucket(int kind) const;
	std::vector<int32_t> *bucket(int kind);
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryPose::Track);

#endif // IVORY_POSE_H
