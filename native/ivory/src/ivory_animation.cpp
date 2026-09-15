#include "ivory_animation.h"

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

static constexpr double PI_D = 3.1415926535897932384626433832795;
static constexpr double TAU_D = 6.283185307179586476925286766559;

void IvoryAnimation::_bind_methods() {
    ClassDB::bind_method(D_METHOD("key_progress", "frame", "from_frame", "to_frame"), &IvoryAnimation::key_progress);
    ClassDB::bind_method(D_METHOD("begin_angle_blend", "from", "to", "duration"),
            &IvoryAnimation::begin_angle_blend);
    ClassDB::bind_method(D_METHOD("update", "delta"), &IvoryAnimation::update);
    ClassDB::bind_method(D_METHOD("sample", "normalized"), &IvoryAnimation::sample);
    ClassDB::bind_method(D_METHOD("blending"), &IvoryAnimation::blending);
    ClassDB::bind_method(D_METHOD("progress"), &IvoryAnimation::progress);
    ClassDB::bind_method(D_METHOD("cancel_blend"), &IvoryAnimation::cancel_blend);
    ClassDB::bind_method(D_METHOD("clear_events"), &IvoryAnimation::clear_events);
    ClassDB::bind_method(D_METHOD("add_event", "frame", "type", "data"),
            &IvoryAnimation::add_event);
    ClassDB::bind_method(D_METHOD("events_between", "previous_frame", "current_frame",
            "first_frame", "last_frame", "looped"), &IvoryAnimation::events_between);
}

double IvoryAnimation::clamp01(double v) {
    if (!std::isfinite(v)) return 0.0;
    return std::clamp(v, 0.0, 1.0);
}

double IvoryAnimation::smoothstep(double v) {
    v = clamp01(v);
    return v * v * (3.0 - 2.0 * v);
}

double IvoryAnimation::angle_delta(double from, double to) {
    double d = to - from;
    if (!std::isfinite(d)) return 0.0;
    d = std::fmod(d + PI_D, TAU_D);
    if (d < 0.0) d += TAU_D;
    return d - PI_D;
}

float IvoryAnimation::finite_angle(float v) {
    if (!std::isfinite(v)) return 0.0f;
    double d = std::fmod((double)v + PI_D, TAU_D);
    if (d < 0.0) d += TAU_D;
    d -= PI_D;
    // Canonicalize the exact wrap boundary to +pi. This avoids a visually
    // ambiguous -pi/+pi seam when sampling a shortest-path blend.
    if (d <= -PI_D + 1.0e-7) d = PI_D;
    return (float)d;
}

double IvoryAnimation::key_progress(double frame, int from_frame, int to_frame) const {
    if (!std::isfinite(frame) || to_frame <= from_frame) return 1.0;
    const double t = (frame - (double)from_frame) / (double)(to_frame - from_frame);
    return clamp01(t);
}

void IvoryAnimation::begin_angle_blend(const PackedFloat32Array &from,
        const PackedFloat32Array &to, double duration) {
    const int n = std::min(from.size(), to.size());
    from_.resize(n);
    to_.resize(n);
    for (int i = 0; i < n; ++i) {
        from_[i] = finite_angle(from[i]);
        to_[i] = finite_angle(to[i]);
    }
    elapsed_ = 0.0;
    duration_ = std::max(0.0, std::isfinite(duration) ? duration : 0.0);
    if (duration_ == 0.0) elapsed_ = duration_;
}

PackedFloat32Array IvoryAnimation::sample(double normalized) const {
    PackedFloat32Array out;
    const double t = smoothstep(normalized);
    out.resize(from_.size());
    for (int i = 0; i < from_.size(); ++i) {
        const double a = (double)from_[i];
        const double b = a + angle_delta(a, (double)to_[i]);
        out[i] = finite_angle((float)(a + (b - a) * t));
    }
    return out;
}

PackedFloat32Array IvoryAnimation::update(double delta) {
    if (duration_ <= 0.0) {
        elapsed_ = duration_;
        return sample(1.0);
    }
    if (std::isfinite(delta) && delta > 0.0) {
        elapsed_ = std::min(duration_, elapsed_ + delta);
    }
    return sample(elapsed_ / duration_);
}

bool IvoryAnimation::blending() const {
    return duration_ > 0.0 && elapsed_ < duration_ - 1.0e-9;
}

double IvoryAnimation::progress() const {
    if (duration_ <= 0.0) return 1.0;
    return clamp01(elapsed_ / duration_);
}

void IvoryAnimation::cancel_blend() {
    elapsed_ = duration_;
}

void IvoryAnimation::clear_events() {
    event_frame_.clear();
    event_type_.clear();
    event_data_.clear();
}

bool IvoryAnimation::add_event(int frame, const String &type, const Dictionary &data) {
    if (frame < 0 || type.is_empty()) return false;
    event_frame_.push_back((int32_t)frame);
    event_type_.push_back(type);
    event_data_.push_back(data);

    // Keep the three parallel arrays ordered together. Event counts are tiny
    // compared with mesh data, so a stable sort is more robust than a custom
    // index structure and preserves authored order for same-frame events.
    std::vector<int32_t> order(event_frame_.size());
    for (size_t i = 0; i < order.size(); ++i) order[i] = (int32_t)i;
    std::stable_sort(order.begin(), order.end(), [&](int32_t a, int32_t b) {
        return event_frame_[(size_t)a] < event_frame_[(size_t)b];
    });

    std::vector<int32_t> nf;
    std::vector<String> nt;
    std::vector<Dictionary> nd;
    nf.reserve(order.size()); nt.reserve(order.size()); nd.reserve(order.size());
    for (int32_t i : order) {
        nf.push_back(event_frame_[(size_t)i]);
        nt.push_back(event_type_[(size_t)i]);
        nd.push_back(event_data_[(size_t)i]);
    }
    event_frame_.swap(nf);
    event_type_.swap(nt);
    event_data_.swap(nd);
    return true;
}

Array IvoryAnimation::collect_range(int lo, int hi) const {
    Array out;
    if (hi < lo) return out;
    for (size_t i = 0; i < event_frame_.size(); ++i) {
        const int f = event_frame_[i];
        if (f < lo) continue;
        if (f > hi) break;
        Dictionary d;
        d["frame"] = f;
        d["type"] = event_type_[i];
        d["data"] = event_data_[i];
        out.append(d);
    }
    return out;
}

Array IvoryAnimation::events_between(int previous_frame, int current_frame,
        int first_frame, int last_frame, bool looped) const {
    Array out;
    if (event_frame_.empty()) return out;
    if (first_frame > last_frame) std::swap(first_frame, last_frame);
    previous_frame = std::clamp(previous_frame, first_frame, last_frame);
    current_frame = std::clamp(current_frame, first_frame, last_frame);

    if (!looped || current_frame >= previous_frame) {
        return collect_range(previous_frame + 1, current_frame);
    }

    // A looped advance crosses the tail and then resumes at the head.
    // Include only frames strictly after the previous position and including
    // the new position, matching ordinary forward transport semantics.
    Array tail = collect_range(previous_frame + 1, last_frame);
    Array head = collect_range(first_frame, current_frame);
    for (int i = 0; i < tail.size(); ++i) out.append(tail[i]);
    for (int i = 0; i < head.size(); ++i) out.append(head[i]);
    return out;
}
