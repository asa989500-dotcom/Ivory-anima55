#ifndef IVORY_MASS_KEEPER_H
#define IVORY_MASS_KEEPER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {

// Drawing-safe mass/weight keeper.
//
// The important distinction is between a rigid bone segment and a joint.
// A segment should not bend internally: one bone produces one rigid transform.
// Only a small neighbourhood where two bones share influence is allowed to
// change shape. This class therefore repairs local area loss only in those
// joint neighbourhoods and refuses unsafe weight/stretch data before it can
// enter the skinning path.
class IvoryMassKeeper : public RefCounted {
    GDCLASS(IvoryMassKeeper, RefCounted)
protected:
    static void _bind_methods();
public:
    void configure(double joint_radius_ratio = 0.30,
                   double joint_radius_px = 10.0,
                   double max_linear_ratio = 1.35,
                   double min_linear_ratio = 0.74);

    // Keeps local mass/area close to rest, but only where the point is near a
    // real joint (two bones are present). Single-bone regions are left rigid.
    PackedVector2Array preserve_joint_mass(
            const PackedVector2Array &now_points,
            const PackedVector2Array &rest_points,
            const PackedInt32Array &triangles,
            const PackedVector2Array &rest_a,
            const PackedVector2Array &rest_b,
            double strength = 0.72,
            int iterations = 2) const;

    // Sanitises point-major skinning weights. Invalid indices, negative/NaN
    // weights and excess influences are removed; the strongest joint overlap
    // is retained so a point does not bend under unrelated bones.
    Dictionary sanitize_weights(const PackedInt32Array &bones,
            const PackedFloat32Array &weights, int point_count,
            int max_influences = 2) const;

    // Reports geometric quality, including area retention and edge stretch.
    Dictionary inspect(const PackedVector2Array &now_points,
            const PackedVector2Array &rest_points,
            const PackedInt32Array &triangles) const;

    // Tests a single bone's current length against the intended rest length.
    bool within_stretch(double current, double rest,
            double min_ratio = 0.74, double max_ratio = 1.35) const;

private:
    double joint_radius_ratio_ = 0.30;
    double joint_radius_px_ = 10.0;
    double max_linear_ratio_ = 1.35;
    double min_linear_ratio_ = 0.74;
};

} // namespace godot
#endif
