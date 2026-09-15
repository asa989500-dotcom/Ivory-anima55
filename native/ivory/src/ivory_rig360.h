#ifndef IVORY_RIG360_H
#define IVORY_RIG360_H

// Character 360 rig: bones for the head, hands and fingers, anything drawn
// on top bound to them, and a way out to the project.
//
// ## Rest coordinates, and why they are the whole thing
//
// "The bones must hold their coordinates in the character, firmly." That is
// one sentence and it is the load-bearing requirement of the entire file.
//
// A bone has two poses at all times: the one it was **drawn** in, and the one
// it is **in now**. Everything bound to it is stored against the first and
// only ever displayed through the second. Store against the second and the
// binding drifts: pose the arm, save, reopen, pose it again, and the sleeve
// has moved a little further down the arm each time, because each pose was
// measured from the last one rather than from the truth.
//
// So the rest pose is written once, when the bone is laid, and is never
// touched again by posing. `pose_of` composes from rest every time. It is a
// little more arithmetic per frame and it means a rig can be posed ten
// thousand times and come back to exactly where it started — which
// `test_rig360.cpp` does, and checks on the raw floats.
//
// ## Drawing on top of the character
//
// A person draws hair, or a robe, over a figure that is already rigged. That
// drawing has to move with the figure, and the awkward part is that it was
// drawn **while the figure was posed**, not in its rest pose.
//
// The answer: bind at the pose it was drawn in. Each point of the new stroke
// is turned into the rest frame of whichever bone owns it — `rest_of` is the
// inverse of the transform that was live when the ink landed — and stored
// there. From then on it is the same as everything else. This is what "the
// drawing rotates from the place where it started moving" means, exactly, and
// it is why a lock of hair drawn on a tilted head does not jump upright the
// moment the head is straightened.
//
// Which bone owns a point is decided by distance to the bone's *segment*, not
// to its head — a long bone is a line, and measuring to one end gives the
// shoulder ownership of the wrist.
//
// ## Smart bones
//
// Moho's idea, and the reason its rigs bend properly at an elbow. A bone's
// angle drives *other things*: the artist poses the arm at ninety degrees,
// fixes the elbow up by hand, and records that as an action. Afterwards, every
// angle between nought and ninety is interpolated between the two recorded
// states, so the fix is applied smoothly and in proportion.
//
// The interpolation is **Catmull-Rom through the recorded angles**, not
// linear. A linear blend between three recorded poses has a corner at each
// one: the correction arrives, changes rate abruptly, and the limb visibly
// ticks as it passes the recorded angle. Catmull-Rom is C1 and has no corner,
// and — because it is the centripetal parameterisation — it cannot overshoot
// into a fold when two recordings are close together in angle.
//
// ## Character 360 layers
//
// The file holds the body on a layer called `character 360`. Adding another
// layer in that file does not make an ordinary layer: it makes
// `character 360 (2)`, then `(3)`, and each is bound to the same rig. Naming
// is done here rather than in the interface so that the number is chosen
// against the layers that actually exist — the interface counting them itself
// is how two layers end up both called `(3)` after a delete.
//
// ## Cancel, everywhere
//
// Every operation that changes anything is recorded, and `undo_last` reverses
// exactly it. Not a snapshot of the whole rig — a snapshot is large, and on a
// figure with a few hundred bound strokes taking one per bone drag is enough
// memory to matter on a phone. Each record holds only what that one operation
// touched.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvoryRig360 : public RefCounted {
	GDCLASS(IvoryRig360, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryRig360() = default;
	~IvoryRig360() = default;

	// What a bone is for. The kind is not decoration: it decides the default
	// reach, whether the bone is offered a smart action, and what the
	// interface calls it.
	enum Part {
		PART_ROOT,
		PART_HEAD,
		PART_NECK,
		PART_SPINE,
		PART_ARM,
		PART_HAND,
		PART_FINGER,
		PART_LEG,
		PART_HAIR,
		PART_CLOTH,
	};

	// --- bones ---

	// Lays a bone in its rest pose. This is the only time the rest pose is
	// ever written.
	int add_bone(const Vector2 &head, const Vector2 &tail, int parent,
			int part);
	bool remove_bone(int index);
	void clear();
	int bone_count() const { return (int)bone_.size(); }

	// Builds a starting rig from the supplied feature points: a head, a spine
	// down the body, and a chain out to each extremity.
	int suggest_from(const PackedVector2Array &at, const PackedInt32Array &kind);

	// Builds a complete five-finger hand rig under an existing hand bone.
	// Four fingers fan from the palm axis and the thumb gets its own opposing
	// direction. Each digit has three constrained phalanges.
	int add_finger_set(int hand_bone, double finger_length = 18.0,
			double palm_width = 24.0);

	Vector2 rest_head(int index) const;
	Vector2 rest_tail(int index) const;
	Vector2 posed_head(int index) const;
	Vector2 posed_tail(int index) const;
	int parent_of(int index) const;
	int part_of(int index) const;
	String name_of(int index) const;

	// --- posing ---

	// Low-latency touch posing: constrained CCD IK from an end bone toward a
	// screen-space target. The solve starts at the parent of the end bone,
	// composes from the immutable rest pose, and never changes bone lengths.
	bool solve_ik(int end_bone, const Vector2 &target, int iterations = 6,
			double tolerance = 0.5);
	// Convenience for touch handlers: pick the nearest posed bone and solve
	// toward the finger position in one call.
	bool drag_to(const Vector2 &at, double reach, const Vector2 &target,
			int iterations = 5, double tolerance = 0.75);

	// Turns a bone by `radians` from its rest angle. Descendants follow,
	// rigidly.
	void set_angle(int index, double radians);
	// Optional local joint limits. Unlimited by default. The limits are
	// enforced at write time so a touch, IK solve, or smart bone cannot leave
	// the rig in an invalid intermediate pose.
	void set_angle_limits(int index, double min_radians, double max_radians);
	Dictionary angle_limits(int index) const;
	double angle_of(int index) const;
	PackedFloat32Array angles() const;
	// Everything back to how it was drawn. Exact, because the rest pose was
	// never written to.
	void rest_all();

	// Which bone a touch means. Distance to the bone's segment, not to its
	// head: a long bone is a line, and measuring to one end gives the
	// shoulder ownership of the wrist.
	int pick(const Vector2 &at, double reach) const;

	// --- ink bound to the rig ---

	// Binds a stroke drawn **at the current pose**. Returns its id.
	//
	// The stroke is turned into the rest frame of **one** bone — the one
	// that owns most of it — and carried by that bone alone.
	//
	// One bone, and not one per point, and the reason is worth stating
	// because the other way looks more sophisticated and is worse. Binding
	// each point to its own nearest bone means a stroke lying across a joint
	// has its two halves carried by two different rotations, and at the
	// joint they separate: the lock of hair tears in the middle, by exactly
	// the amount the joint bent. There is no setting that fixes it, because
	// the discontinuity is in the assignment itself.
	//
	// A decorative stroke is one thing. A lock of hair is a lock of hair, a
	// belt is a belt, and moving as one rigid thing is not a limitation — it
	// is what they do. `bind_stroke_spread` is there for the case where a
	// stroke really should follow several bones, and it carries the tearing
	// with it, which is why it is not the default.
	int bind_stroke(int layer, const PackedVector2Array &points);

	// The same, but each point follows its own nearest bone. For a robe or a
	// cloak drawn across several parts, where following the shape matters
	// more than staying rigid. See the note on `bind_stroke`: this one can
	// separate at a joint, and that is inherent rather than a fault.
	int bind_stroke_spread(int layer, const PackedVector2Array &points);

	// Binds to a bone the caller names, whatever is nearest. What the
	// interface uses when somebody has selected a bone and then drawn.
	int bind_stroke_to(int layer, const PackedVector2Array &points, int bone);
	bool unbind_stroke(int id);
	int stroke_count() const { return (int)stroke_.size(); }
	// Where a bound stroke is now.
	PackedVector2Array stroke_now(int id) const;
	int stroke_layer(int id) const;

	// --- smart bones ---

	// Records that when `driver` is at `angle`, `target` should be at
	// `value`. Several recordings on one pair are interpolated between.
	void record_action(int driver, double angle, int target, double value);
	bool clear_actions(int driver);
	int action_count(int driver) const;
	// Applies every recorded action for the current pose. Called after a
	// bone is turned.
	void apply_actions();

	// --- layers ---

	// The name the next layer in this file should have. Chosen against the
	// layers that exist rather than by counting, so a delete cannot produce
	// two layers with the same number.
	String next_layer_name() const;
	int add_layer();
	// A dedicated Character 360 motion layer. It carries pose/controller
	// data only and is never treated as ordinary drawing ink.
	int ensure_motion_layer();
	int motion_layer_index() const;
	bool remove_layer(int layer);
	PackedStringArray layer_names() const;
	int layer_count() const { return (int)layer_.size(); }
	static String base_layer_name() { return String("character 360"); }

	// --- out ---

	// Everything the project needs to carry this rig: the bones in rest and
	// in pose, the layers, the bound strokes and the actions. One dictionary
	// rather than a file, because where it is written is not this class's
	// business.
	Dictionary to_project() const;
	Dictionary summary() const;

	// --- cancel ---

	// Reverses exactly the last operation that changed anything, and says
	// what it was.
	Dictionary undo_last();
	int undo_depth() const { return (int)undo_.size(); }
	void forget_undo();

private:
	struct Bone {
		Vector2 rest_head;
		Vector2 rest_tail;
		int32_t parent = -1;
		int32_t part = PART_ROOT;
		double angle = 0.0;
	};

	struct Stroke {
		int32_t id = 0;
		int32_t layer = 0;
		std::vector<int32_t> owner;
		std::vector<Vector2> local;
	};

	struct Action {
		int32_t driver = 0;
		int32_t target = 0;
		double angle = 0.0;
		double value = 0.0;
	};

	struct Undo {
		String what;
		int32_t bone = -1;
		int32_t stroke = -1;
		int32_t layer = -1;
		double before = 0.0;
	};

	std::vector<Bone> bone_;
	std::vector<Stroke> stroke_;
	std::vector<Action> action_;
	std::vector<float> min_angle_;
	std::vector<float> max_angle_;
	std::vector<String> layer_;
	std::vector<Undo> undo_;
	int32_t next_stroke_ = 1;

	static const int UNDO_DEPTH = 64;

	void note(const Undo &u);
	// The rest angle of a bone, and the sum of angles from the root down.
	double rest_angle(int index) const;
	double chain_angle(int index) const;
	Vector2 pose_point(int index, const Vector2 &rest) const;
	Vector2 rest_point(int index, const Vector2 &now) const;
	int owner_of(const Vector2 &at) const;
	static double segment_distance(const Vector2 &p, const Vector2 &a,
			const Vector2 &b);
	double action_value(int driver, int target, double angle,
			bool &found) const;
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryRig360::Part);

#endif // IVORY_RIG360_H
