#include "ivory_mass_keeper.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace godot {
static constexpr double EPS = 1.0e-9;

static inline double area2(const Vector2 &a, const Vector2 &b, const Vector2 &c) {
    return std::abs((double)(b-a).cross(c-a));
}

void IvoryMassKeeper::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "joint_radius_ratio", "joint_radius_px",
            "max_linear_ratio", "min_linear_ratio"), &IvoryMassKeeper::configure,
            DEFVAL(0.30), DEFVAL(10.0), DEFVAL(1.35), DEFVAL(0.74));
    ClassDB::bind_method(D_METHOD("preserve_joint_mass", "now_points", "rest_points",
            "triangles", "rest_a", "rest_b", "strength", "iterations"),
            &IvoryMassKeeper::preserve_joint_mass, DEFVAL(0.72), DEFVAL(2));
    ClassDB::bind_method(D_METHOD("sanitize_weights", "bones", "weights", "point_count",
            "max_influences"), &IvoryMassKeeper::sanitize_weights, DEFVAL(2));
    ClassDB::bind_method(D_METHOD("inspect", "now_points", "rest_points", "triangles"),
            &IvoryMassKeeper::inspect);
    ClassDB::bind_method(D_METHOD("within_stretch", "current", "rest", "min_ratio",
            "max_ratio"), &IvoryMassKeeper::within_stretch, DEFVAL(0.74), DEFVAL(1.35));
}

void IvoryMassKeeper::configure(double joint_radius_ratio, double joint_radius_px,
        double max_linear_ratio, double min_linear_ratio) {
    joint_radius_ratio_ = std::clamp(std::isfinite(joint_radius_ratio) ? joint_radius_ratio : 0.30, 0.05, 0.80);
    joint_radius_px_ = std::clamp(std::isfinite(joint_radius_px) ? joint_radius_px : 10.0, 0.0, 128.0);
    min_linear_ratio_ = std::clamp(std::isfinite(min_linear_ratio) ? min_linear_ratio : 0.74, 0.50, 1.0);
    max_linear_ratio_ = std::clamp(std::isfinite(max_linear_ratio) ? max_linear_ratio : 1.35, 1.0, 2.0);
    if (min_linear_ratio_ > max_linear_ratio_) std::swap(min_linear_ratio_, max_linear_ratio_);
}

static double point_segment_dist(const Vector2 &p, const Vector2 &a, const Vector2 &b) {
    const Vector2 d = b - a;
    const double len2 = (double)d.length_squared();
    if (len2 <= EPS) return (double)p.distance_to(a);
    const double t = std::clamp((double)(p-a).dot(d) / len2, 0.0, 1.0);
    return (double)p.distance_to(a + d * (real_t)t);
}

PackedVector2Array IvoryMassKeeper::preserve_joint_mass(
        const PackedVector2Array &now_points,
        const PackedVector2Array &rest_points,
        const PackedInt32Array &triangles,
        const PackedVector2Array &rest_a,
        const PackedVector2Array &rest_b,
        double strength, int iterations) const {
    PackedVector2Array out = now_points;
    const int n = now_points.size();
    const int bones = std::min(rest_a.size(), rest_b.size());
    if (n == 0 || n != rest_points.size() || triangles.size() < 3 || bones < 2) return out;
    strength = std::clamp(std::isfinite(strength) ? strength : 0.72, 0.0, 1.0);
    iterations = std::clamp(iterations, 0, 6);
    if (strength <= 0.0 || iterations <= 0) return out;

    std::vector<std::vector<int>> neighbours((size_t)n);
    std::vector<std::vector<int>> touching((size_t)n);
    const int tc = triangles.size() / 3;
    for (int t = 0; t < tc; ++t) {
        const int a = triangles[t*3], b = triangles[t*3+1], c = triangles[t*3+2];
        if (a < 0 || b < 0 || c < 0 || a >= n || b >= n || c >= n || a==b || b==c || a==c) continue;
        touching[(size_t)a].push_back(t); touching[(size_t)b].push_back(t); touching[(size_t)c].push_back(t);
        neighbours[(size_t)a].push_back(b); neighbours[(size_t)a].push_back(c);
        neighbours[(size_t)b].push_back(a); neighbours[(size_t)b].push_back(c);
        neighbours[(size_t)c].push_back(a); neighbours[(size_t)c].push_back(b);
    }
    for (auto &v : neighbours) {
        std::sort(v.begin(), v.end());
        v.erase(std::unique(v.begin(), v.end()), v.end());
    }

    // A point is flexible only when two different bones are both nearby. The
    // radius is deliberately local so the arm and forearm stay rigid right up
    // until the elbow region.
    std::vector<float> jointness((size_t)n, 0.0f);
    for (int p = 0; p < n; ++p) {
        double first = std::numeric_limits<double>::infinity();
        double second = std::numeric_limits<double>::infinity();
        for (int b = 0; b < bones; ++b) {
            double d = point_segment_dist(rest_points[p], rest_a[b], rest_b[b]);
            if (d < first) { second = first; first = d; }
            else if (d < second) second = d;
        }
        const double typical = std::max(1.0, second);
        const double radius = std::max(joint_radius_px_, typical * joint_radius_ratio_);
        if (second < radius) {
            const double u = std::clamp(1.0 - second / std::max(radius, EPS), 0.0, 1.0);
            jointness[(size_t)p] = (float)(u*u*(3.0-2.0*u));
        }
    }

    std::vector<double> rest_area((size_t)n, 0.0), now_area((size_t)n, 0.0);
    for (int p = 0; p < n; ++p) {
        if (touching[(size_t)p].empty()) continue;
        double ra = 0.0, na = 0.0;
        for (int t : touching[(size_t)p]) {
            const int a = triangles[t*3], b = triangles[t*3+1], c = triangles[t*3+2];
            ra += area2(rest_points[a], rest_points[b], rest_points[c]);
            na += area2(now_points[a], now_points[b], now_points[c]);
        }
        rest_area[(size_t)p] = ra / 3.0;
        now_area[(size_t)p] = na / 3.0;
    }

    std::vector<Vector2> cur((size_t)n), next((size_t)n);
    for (int i = 0; i < n; ++i) cur[(size_t)i] = now_points[i];
    for (int pass = 0; pass < iterations; ++pass) {
        for (int i = 0; i < n; ++i) {
            if (jointness[(size_t)i] <= 0.001f || rest_area[(size_t)i] <= EPS || neighbours[(size_t)i].empty()) {
                next[(size_t)i] = cur[(size_t)i];
                continue;
            }
            double ratio = now_area[(size_t)i] / rest_area[(size_t)i];
            if (!std::isfinite(ratio) || ratio <= EPS) ratio = 1.0;
            ratio = std::clamp(ratio, 0.55, 1.80);
            const double linear = std::clamp(1.0 / std::sqrt(ratio), min_linear_ratio_, max_linear_ratio_);
            const double amount = 1.0 + (linear - 1.0) * strength * (double)jointness[(size_t)i];
            double cx = 0.0, cy = 0.0;
            for (int j : neighbours[(size_t)i]) { cx += cur[(size_t)j].x; cy += cur[(size_t)j].y; }
            cx /= (double)neighbours[(size_t)i].size();
            cy /= (double)neighbours[(size_t)i].size();
            const Vector2 delta = cur[(size_t)i] - Vector2((real_t)cx, (real_t)cy);
            // Hardly move a point whose correction would imply an internal bend
            // farther than the joint neighbourhood itself.
            next[(size_t)i] = Vector2((real_t)(cx + delta.x * amount),
                    (real_t)(cy + delta.y * amount));
        }
        cur.swap(next);
    }
    for (int i = 0; i < n; ++i) out[i] = cur[(size_t)i];
    return out;
}

Dictionary IvoryMassKeeper::sanitize_weights(const PackedInt32Array &bones,
        const PackedFloat32Array &weights, int point_count, int max_influences) const {
    Dictionary out;
    if (point_count < 0 || max_influences < 1) { out["ok"] = false; return out; }
    max_influences = std::clamp(max_influences, 1, 8);
    if (weights.size() == 0) { out["ok"] = false; return out; }
    const int slots = weights.size();
    std::vector<int> ib;
    std::vector<float> iw;
    for (int i = 0; i < slots; ++i) {
        const int b = i < bones.size() ? bones[i] : -1;
        const double w = i < weights.size() ? weights[i] : 0.0;
        if (b < 0 || !std::isfinite(w) || w <= 0.0) continue;
        ib.push_back(b); iw.push_back((float)w);
    }
    std::vector<int> order(ib.size());
    for (size_t i=0;i<order.size();++i) order[i]=(int)i;
    std::stable_sort(order.begin(), order.end(), [&](int a,int b){ return iw[(size_t)a] > iw[(size_t)b]; });
    if ((int)order.size() > max_influences) order.resize((size_t)max_influences);
    double sum = 0.0; for (int k : order) sum += iw[(size_t)k];
    PackedInt32Array sb; PackedFloat32Array sw;
    if (sum > EPS) for (int k : order) { sb.append(ib[(size_t)k]); sw.append((float)(iw[(size_t)k]/sum)); }
    out["ok"] = sum > EPS;
    out["bones"] = sb; out["weights"] = sw; out["count"] = sw.size();
    out["point_count"] = point_count;
    return out;
}

Dictionary IvoryMassKeeper::inspect(const PackedVector2Array &now_points,
        const PackedVector2Array &rest_points, const PackedInt32Array &triangles) const {
    Dictionary out; int valid = 0, folded = 0; double worst_stretch = 1.0e30, min_area = 1.0e30, max_area = 0.0;
    if (now_points.size() != rest_points.size() || triangles.size() < 3) { out["ok"] = false; return out; }
    const int tc = triangles.size()/3;
    for (int t=0;t<tc;++t) {
        int a=triangles[t*3],b=triangles[t*3+1],c=triangles[t*3+2];
        if (a<0||b<0||c<0||a>=now_points.size()||b>=now_points.size()||c>=now_points.size()) continue;
        double ra=area2(rest_points[a],rest_points[b],rest_points[c]);
        double na=area2(now_points[a],now_points[b],now_points[c]);
        if (ra<EPS) continue;
        double ratio=na/ra;
        min_area=std::min(min_area,ratio); max_area=std::max(max_area,ratio);
        if (ratio < min_linear_ratio_*min_linear_ratio_*0.85) ++folded;
        const int ea[3]={a,b,c}, eb[3]={b,c,a};
        for(int e=0;e<3;++e){ double rr=rest_points[ea[e]].distance_to(rest_points[eb[e]]); double nn=now_points[ea[e]].distance_to(now_points[eb[e]]); if(rr>EPS) worst_stretch=std::min(worst_stretch, nn/rr); }
        ++valid;
    }
    out["ok"] = valid > 0 && folded == 0;
    out["triangles"] = valid; out["folded_like"] = folded;
    out["min_area_ratio"] = valid ? min_area : 1.0;
    out["max_area_ratio"] = valid ? max_area : 1.0;
    out["min_edge_ratio"] = (worst_stretch < 1.0e20) ? worst_stretch : 1.0;
    return out;
}

bool IvoryMassKeeper::within_stretch(double current, double rest, double min_ratio, double max_ratio) const {
    if (!std::isfinite(current) || !std::isfinite(rest) || rest <= EPS) return false;
    min_ratio = std::clamp(std::isfinite(min_ratio) ? min_ratio : min_linear_ratio_, 0.5, 1.0);
    max_ratio = std::clamp(std::isfinite(max_ratio) ? max_ratio : max_linear_ratio_, 1.0, 2.0);
    if (min_ratio > max_ratio) std::swap(min_ratio, max_ratio);
    const double r = current / rest;
    return r >= min_ratio && r <= max_ratio;
}

} // namespace godot
