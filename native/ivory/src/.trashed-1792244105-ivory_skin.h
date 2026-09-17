#ifndef IVORY_SKIN_H
#define IVORY_SKIN_H

// The skeleton's arithmetic, in C++.
//
// Two things live here, and both are loops that GDScript runs once per point
// per bone on every frame of a pose.
//
//   * **`read_islands`** — which separate drawing each part of a layer belongs
//     to. This is what stops a skeleton drawn on one figure taking hold of the
//     prop beside it. In GDScript it is `Image.get_pixel` sixteen thousand
//     times before a single bone appears; here it is one pass over the bytes.
//
//   * **`deform`** — where every point of the skin goes. The arithmetic is
//     exactly what `RigSkin.bone_rule` does and is documented there at length:
//     anchors averaged as positions, turns averaged as *directions*, and the
//     flesh keeping its offset from the anchor. Averaging the positions each
//     bone would put the point at is the famous mistake, and it is the one
//     that collapses an elbow at a hundred and eighty degrees.
//
// Nothing here changes the result. What changes is that a thousand-point skin
// over a dozen bones is twelve thousand inner iterations a frame, and in
// GDScript every one of them is a Variant.

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {

class IvorySkin : public RefCounted {
	GDCLASS(IvorySkin, RefCounted)

protected:
	static void _bind_methods();

public:
	IvorySkin();
	~IvorySkin();

	// Which drawing each corner of the mesh sits on. Nought is empty paper.
	PackedInt32Array read_islands(const Ref<Image> &art, int cells);

	// Every point of the skin, moved by the bones nearest it.
	//
	// `bone_island` may be empty, in which case no bone is confined to a
	// drawing and every one of them can move anything within its reach.
	PackedVector2Array deform(const PackedVector2Array &rest_points,
			const PackedInt32Array &point_island,
			const PackedVector2Array &rest_a, const PackedVector2Array &rest_b,
			const PackedVector2Array &now_a, const PackedVector2Array &now_b,
			const PackedInt32Array &bone_island);

	// A correction pass run after `deform`, for the residual thinning that
	// the rotation-preserving blend above does not by itself remove.
	//
	// `deform` makes a single bone's influence exact — an offset turned by
	// one rotation cannot change length. It does not make the *blend between
	// two bones* volume-preserving: where two influence regions overlap, the
	// anchor each point is measured from is itself a weighted average of two
	// moving anchors, and that average can drift closer together than either
	// anchor moved on its own (the same way the midpoint of two people
	// walking toward each other closes faster than either of them). The
	// flesh keeps its exact offset from that anchor, so it follows the
	// anchor in — a local thinning at the seam between two bones, worst at a
	// sharply bent joint where both anchors are converging. It is smaller
	// than the fault `deform` already fixed and it is real.
	//
	// This is a local area correction, not a second full solve: pull each
	// point toward or away from the current centroid of its mesh neighbours
	// by however much its own local area has shrunk or grown relative to
	// rest, and repeat a few times so the correction spreads. See the .cpp
	// for the derivation and `triangle_area_ratio` in `ivory_arap.h` for the
	// same measurement used to validate the puppet warp.
	//
	// `point_island` again keeps one drawing from correcting into another —
	// a neighbour on a different island is excluded from the centroid a
	// point is pulled toward, exactly as it is excluded from bone influence
	// in `deform`.
	PackedVector2Array preserve_volume(const PackedVector2Array &now_points,
			const PackedVector2Array &rest_points,
			const PackedInt32Array &triangles,
			const PackedInt32Array &point_island, double strength,
			int iterations);
};

} // namespace godot

#endif // IVORY_SKIN_H
