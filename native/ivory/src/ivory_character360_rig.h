#ifndef IVORY_CHARACTER360_RIG_H
#define IVORY_CHARACTER360_RIG_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <vector>

namespace godot {

// Native controller for the Character 360 room.  It deliberately does not own
// textures or scene nodes: those stay in Godot/GPU land.  This object owns the
// small, deterministic math state that must be identical on Android and
// desktop: multi-disc weights, IK/FK, constraints, pins, paintable weights,
// FFD and an undo ring.
class IvoryCharacter360Rig : public RefCounted {
	GDCLASS(IvoryCharacter360Rig, RefCounted)

public:
	enum PinType { PIN_FIXED = 0, PIN_BONE = 1, PIN_ROTATION = 2, PIN_STRETCH = 3, PIN_ATTRIBUTE = 4 };

	struct Disc { float angle = 0.0f; bool live = true; };
	struct Pin { Vector2 rest; Vector2 value; int bone = -1; PinType type = PIN_FIXED; float amount = 1.0f; };
	struct Constraint { int bone = -1; float min_angle = -3.14159265f; float max_angle = 3.14159265f; float spring = 0.0f; int target_bone = -1; };
	struct Snapshot { PackedVector2Array points; PackedFloat32Array weights; PackedFloat32Array turns; };

protected:
	static void _bind_methods();

public:
	IvoryCharacter360Rig() = default;
	~IvoryCharacter360Rig() = default;

	// Multi-disc / smart-bone style angle blending.
	int add_disc(double angle);
	void remove_disc(int index);
	void clear_discs();
	void set_disc_angle(int index, double angle);
	double disc_angle(int index) const;
	int disc_count() const;
	PackedFloat32Array disc_weights(double angle) const;
	Dictionary blend_window(double angle) const;

	// Dangle / secondary motion is integrated here so the room can solve the
	// same controller whether the timeline or the live canvas drives it.
	PackedFloat32Array settle(PackedFloat32Array values, PackedFloat32Array velocity,
			double delta, double frequency, double damping, double amount) const;

	// IK/FK. FK is the default; set_ik_target enables a chain for one solve.
	void set_ik_enabled(bool enabled);
	bool ik_enabled() const;
	PackedVector2Array solve_ik(const PackedVector2Array &points, const PackedInt32Array &parent,
			const PackedFloat32Array &lengths, int tip, const Vector2 &target,
			int passes = 8) const;
	PackedVector2Array solve_ik_pole(const PackedVector2Array &points, const PackedInt32Array &parent,
			const PackedFloat32Array &lengths, int tip, const Vector2 &target,
			const Vector2 &pole, int passes = 8) const;
	void fk_pose(PackedVector2Array &points, const PackedFloat32Array &turns,
			const PackedInt32Array &parent, const PackedFloat32Array &lengths) const;

	// Bone constraints: angle limits, spring amount and look-at target bone.
	int add_constraint(int bone);
	void set_constraint(int id, double min_angle, double max_angle, double spring, int target_bone = -1);
	void clear_constraints();
	PackedFloat32Array apply_constraints(PackedFloat32Array turns, double delta = 0.0) const;

	// Five explicit pin types.
	int add_pin(const Vector2 &rest, int type, int bone = -1, double amount = 1.0);
	void set_pin_value(int id, const Vector2 &value);
	void remove_pin(int id);
	void clear_pins();
	Dictionary pin(int id) const;

	// Normalized paintable weights. vertex_count * bone_count.
	void resize_weights(int vertex_count, int bone_count);
	PackedFloat32Array weights() const;
	void paint_weights(int vertex, int bone, double strength, double radius = 0.0);
	void normalize_weights();
	PackedFloat32Array vertex_weights(int vertex) const;

	// Independent FFD lattice. The rig never owns this deformation in its bone
	// solve, so it can be enabled/disabled without changing the skeleton.
	void set_ffd(int cols, int rows, const PackedVector2Array &rest,
			const PackedVector2Array &live);
	PackedVector2Array ffd_deform(const PackedVector2Array &points) const;
	void clear_ffd();
	bool ffd_enabled() const;

	// Compact, operation-level history. Snapshots are small and are committed
	// only after a completed gesture, not per touch sample.
	void begin_history(const PackedVector2Array &points,
			const PackedFloat32Array &weights, const PackedFloat32Array &turns);
	void commit_history(const PackedVector2Array &points,
			const PackedFloat32Array &weights, const PackedFloat32Array &turns);
	Dictionary undo();
	Dictionary redo();
	int undo_count() const;
	int redo_count() const;

	Dictionary diagnostics() const;

private:
	std::vector<Disc> discs_;
	std::vector<Pin> pins_;
	std::vector<Constraint> constraints_;
	bool ik_enabled_ = false;
	int wcols_ = 0, wbones_ = 0;
	std::vector<float> weights_;
	int ffd_cols_ = 0, ffd_rows_ = 0;
	PackedVector2Array ffd_rest_;
	PackedVector2Array ffd_live_;
	std::vector<Snapshot> history_;
	int history_pos_ = -1;
	Snapshot make_snapshot(const PackedVector2Array&, const PackedFloat32Array&, const PackedFloat32Array&) const;
	Dictionary snapshot_dict(const Snapshot&) const;
	static double wrap_angle(double a);
};

VARIANT_ENUM_CAST(IvoryCharacter360Rig::PinType);

} // namespace godot
#endif
