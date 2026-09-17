#include "ivory_pose_deformer.h"

#include <algorithm>
#include <cmath>
#include <numeric>

namespace godot {

static constexpr double FULL_DEG = 360.0;
static constexpr double EPS = 1e-7;

void IvoryPoseDeformer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("clear"), &IvoryPoseDeformer::clear);
    ClassDB::bind_method(D_METHOD("add_reference", "angle_degrees"),
            &IvoryPoseDeformer::add_reference);
    ClassDB::bind_method(D_METHOD("set_reference_angles", "angles_degrees"),
            &IvoryPoseDeformer::set_reference_angles);
    ClassDB::bind_method(D_METHOD("reference_angles"),
            &IvoryPoseDeformer::reference_angles);
    ClassDB::bind_method(D_METHOD("reference_weights", "angle_degrees", "softness"),
            &IvoryPoseDeformer::reference_weights, DEFVAL(0.85));
    ClassDB::bind_method(D_METHOD("set_corrective", "reference", "deltas"),
            &IvoryPoseDeformer::set_corrective);
    ClassDB::bind_method(D_METHOD("clear_correctives"),
            &IvoryPoseDeformer::clear_correctives);
    ClassDB::bind_method(D_METHOD("set_volume_mesh", "rest_points", "edges"),
            &IvoryPoseDeformer::set_volume_mesh);
    ClassDB::bind_method(D_METHOD("deform", "points", "angle_degrees",
            "corrective_strength", "volume_strength", "volume_passes"),
            &IvoryPoseDeformer::deform, DEFVAL(1.0), DEFVAL(0.55), DEFVAL(2));
    ClassDB::bind_method(D_METHOD("report"), &IvoryPoseDeformer::report);
}

double IvoryPoseDeformer::wrap_degrees(double degrees) {
    double out = std::fmod(degrees, FULL_DEG);
    if (out < 0.0) out += FULL_DEG;
    return out;
}

double IvoryPoseDeformer::circular_distance(double a, double b) {
    double d = std::abs(wrap_degrees(a) - wrap_degrees(b));
    return std::min(d, FULL_DEG - d);
}

double IvoryPoseDeformer::smooth5(double t) {
    t = std::clamp(t, 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

void IvoryPoseDeformer::clear() {
    refs_.clear();
    rest_points_ = PackedVector2Array();
    edges_ = PackedInt32Array();
}

int IvoryPoseDeformer::add_reference(double angle_degrees) {
    if (!std::isfinite(angle_degrees)) return -1;
    RefPose pose;
    pose.angle = wrap_degrees(angle_degrees);
    refs_.push_back(pose);
    std::sort(refs_.begin(), refs_.end(), [](const RefPose &a, const RefPose &b) {
        return a.angle < b.angle;
    });
    for (int i = 0; i < (int)refs_.size(); ++i) {
        if (std::abs(refs_[(size_t)i].angle - pose.angle) < 1e-6) return i;
    }
    return -1;
}

void IvoryPoseDeformer::set_reference_angles(const PackedFloat32Array &angles_degrees) {
    refs_.clear();
    for (int i = 0; i < angles_degrees.size(); ++i) {
        if (!std::isfinite((double)angles_degrees[i])) continue;
        RefPose pose;
        pose.angle = wrap_degrees((double)angles_degrees[i]);
        refs_.push_back(pose);
    }
    std::sort(refs_.begin(), refs_.end(), [](const RefPose &a, const RefPose &b) {
        return a.angle < b.angle;
    });
}

PackedFloat32Array IvoryPoseDeformer::reference_angles() const {
    PackedFloat32Array out;
    for (const RefPose &pose : refs_) out.append((float)pose.angle);
    return out;
}

PackedFloat32Array IvoryPoseDeformer::weights_impl(double angle_degrees, double softness) const {
    PackedFloat32Array out;
    out.resize((int)refs_.size());
    for (int i = 0; i < out.size(); ++i) out[i] = 0.0f;
    if (refs_.empty()) return out;
    const double angle = wrap_degrees(angle_degrees);
    if (refs_.size() == 1) {
        out[0] = 1.0f;
        return out;
    }
    int right = 0;
    while (right < (int)refs_.size() && refs_[(size_t)right].angle < angle) ++right;
    if (right == (int)refs_.size()) right = 0;
    const int left = right == 0 ? (int)refs_.size() - 1 : right - 1;
    const double left_angle = refs_[(size_t)left].angle;
    const double right_angle = refs_[(size_t)right].angle + (right == 0 ? FULL_DEG : 0.0);
    double query = angle + (right == 0 && angle < refs_[(size_t)left].angle ? FULL_DEG : 0.0);
    if (left == right || std::abs(right_angle - left_angle) < EPS) {
        out[right] = 1.0f;
        return out;
    }
    double t = (query - left_angle) / (right_angle - left_angle);
    t = smooth5(t);
    const double curve = std::clamp(softness, 0.0, 1.0);
    const double blend = t * curve + ((query - left_angle) /
            (right_angle - left_angle)) * (1.0 - curve);
    out[left] = (float)(1.0 - blend);
    out[right] = (float)blend;
    return out;
}

PackedFloat32Array IvoryPoseDeformer::reference_weights(double angle_degrees,
        double softness) const {
    return weights_impl(angle_degrees, softness);
}

bool IvoryPoseDeformer::set_corrective(int reference, const PackedVector2Array &deltas) {
    if (reference < 0 || reference >= (int)refs_.size()) return false;
    if (!rest_points_.is_empty() && deltas.size() != rest_points_.size()) return false;
    refs_[(size_t)reference].delta = deltas;
    return true;
}

void IvoryPoseDeformer::clear_correctives() {
    for (RefPose &pose : refs_) pose.delta = PackedVector2Array();
}

void IvoryPoseDeformer::set_volume_mesh(const PackedVector2Array &rest_points,
        const PackedInt32Array &edges) {
    rest_points_ = rest_points;
    edges_ = edges;
}

PackedVector2Array IvoryPoseDeformer::deform(const PackedVector2Array &points,
        double angle_degrees, double corrective_strength, double volume_strength,
        int volume_passes) const {
    PackedVector2Array out = points;
    if (refs_.empty() || points.is_empty()) return out;
    const PackedFloat32Array weights = weights_impl(angle_degrees, 0.85);
    const double strength = std::clamp(corrective_strength, 0.0, 1.0);
    for (int p = 0; p < points.size(); ++p) {
        Vector2 delta;
        for (int r = 0; r < weights.size(); ++r) {
            if (weights[r] <= 0.0f || refs_[(size_t)r].delta.size() <= p) continue;
            delta += refs_[(size_t)r].delta[p] * (real_t)weights[r];
        }
        out[p] += delta * (real_t)strength;
    }
    if (rest_points_.size() != out.size() || edges_.size() < 2) return out;
    const double repair = std::clamp(volume_strength, 0.0, 1.0);
    const int passes = std::clamp(volume_passes, 0, 16);
    for (int pass = 0; pass < passes; ++pass) {
        PackedVector2Array correction;
        correction.resize(out.size());
        PackedInt32Array degree;
        degree.resize(out.size());
        for (int i = 0; i < degree.size(); ++i) degree[i] = 0;
        for (int e = 0; e + 1 < edges_.size(); e += 2) {
            const int a = edges_[e];
            const int b = edges_[e + 1];
            if (a < 0 || b < 0 || a >= out.size() || b >= out.size()) continue;
            const Vector2 rest = rest_points_[b] - rest_points_[a];
            const Vector2 now = out[b] - out[a];
            const double wanted = rest.length();
            const double got = now.length();
            if (wanted < EPS || got < EPS) continue;
            const Vector2 fix = now * (real_t)((wanted - got) / got * 0.5 * repair);
            correction[a] -= fix;
            correction[b] += fix;
            degree[a] += 1;
            degree[b] += 1;
        }
        for (int p = 0; p < out.size(); ++p) {
            if (degree[p] > 0) out[p] += correction[p] / (real_t)degree[p];
        }
    }
    return out;
}

Dictionary IvoryPoseDeformer::report() const {
    Dictionary out;
    out["references"] = (int)refs_.size();
    out["vertices"] = rest_points_.size();
    out["edges"] = edges_.size() / 2;
    out["circular"] = true;
    out["supports_0_360_wrap"] = true;
    out["supports_pose_correctives"] = true;
    out["supports_volume_repair"] = true;
    return out;
}

} // namespace godot
