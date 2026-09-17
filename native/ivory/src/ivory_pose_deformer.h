#ifndef IVORY_POSE_DEFORMER_H
#define IVORY_POSE_DEFORMER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <vector>

namespace godot {

// Circular multi-view pose deformation for authored 0..360 degree references.
// This is an optional kernel: it does not replace BoneRig or RigSkin.
class IvoryPoseDeformer : public RefCounted {
    GDCLASS(IvoryPoseDeformer, RefCounted)

protected:
    static void _bind_methods();

public:
    void clear();
    int add_reference(double angle_degrees);
    void set_reference_angles(const PackedFloat32Array &angles_degrees);
    PackedFloat32Array reference_angles() const;
    PackedFloat32Array reference_weights(double angle_degrees,
            double softness = 0.85) const;

    // A correction is a per-vertex delta authored for one reference pose.
    bool set_corrective(int reference, const PackedVector2Array &deltas);
    void clear_correctives();

    // Edges are a flat [a,b,a,b,...] list used by the volume-preservation pass.
    void set_volume_mesh(const PackedVector2Array &rest_points,
            const PackedInt32Array &edges);

    // Applies circular corrective deltas and optional edge-length repair.
    PackedVector2Array deform(const PackedVector2Array &points,
            double angle_degrees, double corrective_strength = 1.0,
            double volume_strength = 0.55, int volume_passes = 2) const;

    Dictionary report() const;

private:
    struct RefPose {
        double angle = 0.0;
        PackedVector2Array delta;
    };
    std::vector<RefPose> refs_;
    PackedVector2Array rest_points_;
    PackedInt32Array edges_;

    static double wrap_degrees(double degrees);
    static double circular_distance(double a, double b);
    static double smooth5(double t);
    PackedFloat32Array weights_impl(double angle_degrees, double softness) const;
};

} // namespace godot
#endif
