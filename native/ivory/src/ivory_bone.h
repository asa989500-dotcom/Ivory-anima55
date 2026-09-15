#ifndef IVORY_BONE_H
#define IVORY_BONE_H

// The skeleton itself, in C++.
//
// ## Why this exists, when `bone_solver.gd` already worked
//
// It did work, and it stays. What it could not do was answer *fast enough to
// be dragged*. A pose is not one calculation, it is one calculation per touch
// event — sixty to a hundred and twenty a second on a modern panel — and each
// one walks the chain, solves it, walks the descendants and re-hangs them.
// In GDScript every step of that is a bound call returning a Variant, and by
// the time a figure had a dozen bones on it the solve was arriving after the
// frame that wanted it. A joint that answers late does not read as slow. It
// reads as **not moving**, because the finger has already gone somewhere else
// by the time the drawing catches up, and the drawing appears to be resisting.
//
// So the arithmetic moved here. Not a different method — the same FABRIK, the
// same two-bone closed form, the same rigid re-hang of the children — but with
// the inner loops over plain floats in contiguous memory.
//
// ## What the skeleton is, here
//
// Five flat arrays and nothing else:
//
//   * `head_` and `tail_` — the two ends of each bone, in page coordinates.
//   * `parent_` — which bone each hangs from, or -1 for a root.
//   * `min_arc_` / `max_arc_` — how far each joint may bend from the angle it
//     was drawn at. A joint with no limit carries a span of a full turn, and
//     `limit_all` then costs one comparison for it.
//
// There is no tree structure and no pointers. Children are found by one pass
// over `parent_`, cached in `kids_` as a flat adjacency, and the whole thing
// is rebuilt whenever the skeleton is handed over. A skeleton is handed over
// once per grab and read hundreds of times per grab, so that trade is not
// close.
//
// ## The one rule that keeps a rig from tearing
//
// **A bone's descendants move with it rigidly.** When a bone turns, every bone
// hanging off it is carried by exactly the same rotation about exactly the
// same pivot — not re-solved, not re-fitted, *carried*. The moment descendants
// are recomputed independently, floating point disagreement between the parent
// and the child opens a gap at the joint, and a rig that opens gaps at the
// joints is a rig that visibly comes apart when you move it quickly.
//
// See `carry`, which is four lines and is the whole of that guarantee.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

class IvoryBone : public RefCounted {
	GDCLASS(IvoryBone, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryBone() = default;
	~IvoryBone() = default;

	// Hands the whole skeleton over. Cheap to call and safe to call often —
	// the adjacency is rebuilt here so that nothing else ever has to wonder
	// whether it is stale.
	void set_skeleton(const PackedVector2Array &head,
			const PackedVector2Array &tail, const PackedInt32Array &parent);

	// The bend each joint is allowed, measured from the angle the bone was
	// drawn at. Both arrays may be shorter than the skeleton or empty, and a
	// bone with no entry is simply unlimited.
	void set_limits(const PackedFloat32Array &min_arc,
			const PackedFloat32Array &max_arc);

	PackedVector2Array head() const;
	PackedVector2Array tail() const;

	// Which joint is under a finger: `bone * 2 + which`, where `which` is 0
	// for the head and 1 for the tail, or -1 when nothing is near enough.
	//
	// Tails win ties. A chained skeleton puts a child's head on its parent's
	// tail, and the tail is the end a person means when they reach for the
	// place two bones meet — grabbing the head would swing the child while
	// leaving the parent behind, which looks like the joint came apart.
	int pick(const Vector2 &at, double reach) const;

	// Turns one bone so the given end lands on `to`, carrying everything
	// hanging off it.
	void swing(int index, int which, const Vector2 &to);

	// Reaches the tail of `index` towards `to` by bending the whole chain
	// above it. Two bones are solved exactly; three or more get FABRIK.
	//
	// Returns true when it did something, false when there was no chain to
	// bend and the caller should fall back to a plain swing.
	bool reach(int index, const Vector2 &to, int passes);
	// Pole-aware touch reach. The pole selects the bend side only; lengths and
	// child attachment remain rigid. Near the straight singularity the previous
	// elbow side wins until the pole has moved far enough to be intentional.
	bool reach_pole(int index, const Vector2 &to, const Vector2 &pole, int passes);

	// Holds every joint inside the arc it is allowed. Called after any solve,
	// because both solvers are free to fold an elbow through a shoulder to
	// satisfy a distance and neither of them knows the joint has a front.
	void limit_all();

	int bone_count() const { return (int)head_.size(); }

	// How long each bone is right now. Length is a property of a bone and is
	// never changed by posing — this is here so the GDScript side can assert
	// that, and so a rig loaded from disk can be checked rather than trusted.
	PackedFloat32Array lengths() const;

	// --- adaptive sizing, for the moment a bone is laid ---
	//
	// How wide the drawing is across the line from `a` to `b`, measured on an
	// ink mask. This is what lets a bone drawn down an arm come out the width
	// of the arm and one drawn down a finger come out the width of the finger,
	// instead of every bone being the same size and a thin limb wearing a
	// spindle wider than itself.
	//
	// `ink` is one byte per cell, non-zero where the drawing is; `cols` and
	// `rows` describe it; `origin` and `cell` map page coordinates onto it.
	// Returns the median half-width in page units, or zero when the line
	// crosses no ink at all.
	double span_across(const PackedByteArray &ink, int cols, int rows,
			const Vector2 &origin, const Vector2 &cell, const Vector2 &a,
			const Vector2 &b) const;

private:
	std::vector<Vector2> head_;
	std::vector<Vector2> tail_;
	std::vector<int32_t> parent_;
	std::vector<float> length_;
	std::vector<float> min_arc_;
	std::vector<float> max_arc_;
	// Flat child adjacency: `kids_` holds child indices, `kid_at_` holds the
	// first index for each bone and `kid_at_[n]` closes the last row.
	std::vector<int32_t> kids_;
	std::vector<int32_t> kid_at_;
	// Scratch, kept between calls so a drag allocates nothing.
	mutable std::vector<int32_t> chain_;
	mutable std::vector<Vector2> joint_;
	mutable std::vector<float> link_;
	mutable std::vector<int32_t> stack_;

	void rebuild_kids();
	// Rotates `index` and everything below it about `pivot`.
	void carry(int index, const Vector2 &pivot, double turn);
	// The bones from the root down to `index`, into `chain_`.
	void collect_chain(int index) const;
	void fabrik(int index, const Vector2 &to, int passes);
	void two_bone(int upper, int lower, const Vector2 &to, const Vector2 &pole = Vector2(INFINITY, INFINITY));
	// Puts every descendant of `index` back onto the end of its parent.
	void reseat(int index);
};

} // namespace godot

#endif // IVORY_BONE_H
