#ifndef IVORY_BONEPOSE_H
#define IVORY_BONEPOSE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

// The quick bones on a layer: how a joint moves, what it drags with it, and
// what refuses to move at all.
//
// ## The three complaints this answers
//
// **"One of the points shivers."** With several joints placed, one of them
// would visibly jitter while a neighbour was dragged. The cause was that the
// chain was re-solved from scratch every frame with a fixed number of
// relaxation passes: whichever joint the sweep reached last inherited the
// leftover error of everything before it, and that error changed sign from
// frame to frame. Two changes fix it. The solve now runs until it stops moving
// rather than for a fixed count, and the pass order alternates direction each
// iteration, so no joint is permanently last. A joint that has settled stays
// settled, exactly, because the same input now produces the same output.
//
// **"Double-tap should freeze a joint."** `pin` marks a joint as immovable.
// A pinned joint is not solved for and is not carried by its parent; it holds
// its coordinates to the last bit. The one deliberate exception is written at
// `rotate_about`, and it is the one the artist asked for: an end bone — a hand
// or a foot — may still swing about a pinned joint, because that is the whole
// reason for pinning a wrist in the first place.
//
// **"A ring round each joint, to turn the bone in place."** `rotate_about`
// turns everything *below* a joint in the hierarchy about that joint, and
// nothing above it. Turning the elbow moves the forearm and the hand; it never
// moves the shoulder. That is the behaviour of every rig worth using, and it
// is what makes the ring a usable control rather than a way to detach a limb.
//
// **"The hand tears away from the arm on a fast drag."** `drag()` guards the
// finger's raw target with a deadband and a hard per-call step cap before it
// ever reaches the solve — but that guarded position has to be the one thing
// that actually moves: the joint, what it carries below it, and where the
// chain reaches for. Computing a guarded position and then solving towards
// the raw one anyway defeats the guard in exactly the moment it exists for,
// which is a jump too large to trust. And the guard is kept **per joint**:
// two joints dragged in the same session — two fingers, or one after the
// other — do not share a filter, because a shared one hands the second joint
// the first one's leftover state and makes it crawl toward its own target
// instead of arriving there.
//
// ## What is not here
//
// Skinning. This class moves joints; `IvorySkin` and the mesh solver decide
// what the drawing does about it. Keeping them apart is why a rig can be
// re-posed a thousand times a second while the pixels follow at their own
// pace.
class IvoryBonePose : public RefCounted {
	GDCLASS(IvoryBonePose, RefCounted)

protected:
	static void _bind_methods();

public:
	// The skeleton at rest. `parents` is one entry per joint, -1 for a root.
	// A cycle, a forward reference or an out-of-range parent is refused rather
	// than hung on.
	bool set_skeleton(const PackedVector2Array &rest, const PackedInt32Array &parents);

	int joint_count() const { return (int)rest_.size(); }
	PackedVector2Array positions() const;
	void set_positions(const PackedVector2Array &p);
	void reset();

	// Every joint below `joint` in the hierarchy, itself excluded. This is
	// what the ring turns and what a drag carries.
	PackedInt32Array descendants(int joint) const;
	int parent_of(int joint) const;
	bool is_end(int joint) const;   // no children: a hand, a foot, a tail tip

	// The double-tap. A pinned joint holds its coordinates exactly.
	void pin(int joint);
	void unpin(int joint);
	void unpin_all();
	bool is_pinned(int joint) const;
	int pinned_count() const;

	// Drag one joint to a point. Its descendants follow rigidly, then the
	// chain is relaxed so bone lengths come back to rest without any joint
	// snapping. Returns {ok, iterations, moved, max_step, blocked}.
	Dictionary drag(int joint, const Vector2 &to, int iterations);

	// The ring. Turns `joint`'s descendants about it by `radians`, leaving
	// `joint` and everything above it exactly where they are.
	//
	// Pinning changes what this does, deliberately:
	//   * a pinned joint inside the turned set does not move, and its own
	//     descendants do not move with it either — the limb turns around it;
	//   * unless that pinned joint is an end bone, which is allowed to swing,
	//     because pinning a wrist in order to swing the hand about it is the
	//     reason the artist pinned it.
	Dictionary rotate_about(int joint, double radians);

	// Bone lengths as drawn. The relaxation pulls back towards these.
	PackedFloat32Array rest_lengths() const;

	// How far the current pose is from having correct bone lengths. Zero means
	// every bone is exactly the length it was drawn.
	double length_error() const;

	// How much the pose changed between the last two solves. This is the
	// number that decides whether a joint appears to shiver, so it is reported
	// rather than assumed.
	double last_step() const { return last_step_; }

	void set_stiffness(double v);   // 0..1; how hard lengths are enforced
	double stiffness() const { return stiff_; }
	void configure_stability(double deadband_px, double follow_seconds, double max_step_px);
	Dictionary stability_report() const;

private:
	void carry_descendants(int joint, const Vector2 &by);
	void reach(int joint, const Vector2 &to, int rounds);
	double relax(int iterations);

	std::vector<Vector2> rest_;
	std::vector<Vector2> now_;
	std::vector<int> parent_;
	std::vector<std::vector<int>> child_;
	std::vector<double> length_;
	std::vector<uint8_t> pinned_;
	std::vector<int> order_;        // parents before children
	void invalidate_stability(int joint);

	double stiff_ = 0.85;
	double last_step_ = 0.0;
	double stable_deadband_ = 0.25;
	double stable_follow_ = 0.045;
	double stable_max_step_ = 240.0;
	// One filter *per joint*, not one shared filter for the whole rig. A
	// single shared filter meant that dragging joint A and then joint B
	// handed B the leftover target/velocity from A — two joints that are
	// nowhere near each other — and B would crawl towards its own finger
	// instead of arriving there. See the note on `drag()`.
	std::vector<Vector2> stable_target_;
	std::vector<uint8_t> stable_ready_;
	bool flip_ = false;
};

} // namespace godot
#endif
