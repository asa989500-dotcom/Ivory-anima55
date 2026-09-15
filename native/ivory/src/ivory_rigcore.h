#ifndef IVORY_RIGCORE_H
#define IVORY_RIGCORE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <vector>
#include <cstdint>

namespace godot {

// Production rigging kernel. All solver/deformation arithmetic lives here;
// GDScript is only a UI/serialization adapter.
class IvoryRigCore : public RefCounted {
    GDCLASS(IvoryRigCore, RefCounted)
protected:
    static void _bind_methods();
public:
    enum Space { SPACE_WORLD=0, SPACE_PARENT=1, SPACE_LOCAL=2, SPACE_BONE=3, SPACE_SCREEN=4, SPACE_CHARACTER=5 };

    bool set_skeleton(const PackedVector2Array &head, const PackedVector2Array &tail,
            const PackedInt32Array &parent);
    void set_rest_pose();
    void reset_pose();

    void set_local_angles(const PackedFloat32Array &angles);
    PackedFloat32Array local_angles() const;
    void set_local_scales(const PackedVector2Array &scales);
    PackedVector2Array local_scales() const;
    void set_depths(const PackedFloat32Array &depths);
    PackedFloat32Array depths() const;

    // Optional joint limits, radians relative to rest/local frame.
    void set_angle_limits(const PackedFloat32Array &min_angle, const PackedFloat32Array &max_angle);
    // Exact rest-length constraints. Stretch is opt-in through set_stretch.
    void set_stretch(int bone, double min_ratio, double max_ratio);

    // IK targets are world/page-space points. Pole controls bend side.
    bool set_ik_target(int end_bone, const Vector2 &target, const Vector2 &pole,
            double weight, bool stretch, double soft);
    void clear_ik(int end_bone);
    void clear_ik_all();
    void set_ik_fk_blend(int bone, double ik_weight);

    // Deterministic solve. No persistent solver state is used by solve().
    Dictionary solve(int iterations=16);

    PackedVector2Array heads() const;
    PackedVector2Array tails() const;
    PackedFloat32Array world_angles() const;
    PackedFloat32Array world_depth() const;
    PackedInt32Array parents() const;
    PackedFloat32Array lengths() const;

    // Stable transform-space conversion for editor handles.
    Vector2 to_space(int bone, const Vector2 &world, int space) const;
    Vector2 from_space(int bone, const Vector2 &value, int space) const;

    // Weight table: point-major, max influences per point.
    bool set_weights(const PackedInt32Array &bones, const PackedFloat32Array &weights,
            int point_count, int max_influences=4);
    PackedVector2Array skin(const PackedVector2Array &rest_points) const;
    void normalize_weights();

    // Per-point corrective offsets, keyed by correction id. Blended by weight.
    bool set_corrective(const PackedVector2Array &offsets, double weight);
    PackedVector2Array corrected_points() const;

    // Numerical firewall / diagnostics.
    Dictionary validate() const;
    Dictionary stress_test(int bones=100, int operations=10000, int seed=1) const;

private:
    struct IK { bool active=false, stretch=false; Vector2 target, pole=Vector2(0,-1); double weight=1.0, soft=0.0; };
    struct Stretch { double lo=1.0, hi=1.0; };
    std::vector<Vector2> rest_h_, rest_t_, h_, t_;
    std::vector<int32_t> parent_;
    std::vector<float> rest_len_, local_ang_, world_ang_, depth_;
    std::vector<Vector2> local_scale_;
    std::vector<float> min_ang_, max_ang_, ik_blend_;
    std::vector<Stretch> stretch_;
    std::vector<IK> ik_;
    std::vector<int32_t> order_, kids_, kid_start_;
    std::vector<int32_t> weight_bone_;
    std::vector<float> weight_;
    int point_count_=0, max_inf_=4;
    std::vector<Vector2> corrective_;
    double corrective_weight_=0.0;

    void rebuild();
    void fk();
    void solve_ik_chain(int end, int iterations);
    void two_bone(int upper, int lower, const Vector2 &target, const Vector2 &pole, bool stretch, double soft);
    void chain_ik(int end, const Vector2 &target, const Vector2 &pole, int iterations, bool stretch, double soft);
    void apply_limits();
    void project_lengths();
    void sanitize();
    static double finite(double v, double fallback=0.0);
    static Vector2 finite_vec(const Vector2 &v, const Vector2 &fallback=Vector2());
    static double wrap(double a);
    Vector2 rest_dir(int bone) const;
};

} // namespace godot
#endif
