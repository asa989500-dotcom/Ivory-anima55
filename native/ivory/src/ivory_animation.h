#ifndef IVORY_ANIMATION_H
#define IVORY_ANIMATION_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <vector>
#include <cstdint>

namespace godot {

// Small native animation kernel kept separate from the timeline UI.
// It does not own drawings; it only interpolates numeric pose channels and
// reports timeline events crossed by a playhead. The GDScript timeline remains
// the source of truth for project data.
class IvoryAnimation : public RefCounted {
    GDCLASS(IvoryAnimation, RefCounted)
protected:
    static void _bind_methods();

public:
    IvoryAnimation() = default;
    ~IvoryAnimation() = default;

    void begin_angle_blend(const PackedFloat32Array &from,
            const PackedFloat32Array &to, double duration);
    PackedFloat32Array update(double delta);

    // Stable normalized progress between two timeline keys. Clamped and finite;
    // intended for the playhead's exact point and scrubbing.
    double key_progress(double frame, int from_frame, int to_frame) const;
    PackedFloat32Array sample(double normalized) const;
    bool blending() const;
    double progress() const;
    void cancel_blend();

    // Events are data-only so the native side never retains a Callable or a
    // scene-node reference. `events_between` handles forward playback and
    // looping in deterministic frame space.
    void clear_events();
    bool add_event(int frame, const String &type, const Dictionary &data);
    Array events_between(int previous_frame, int current_frame, int first_frame,
            int last_frame, bool looped) const;

private:
    PackedFloat32Array from_;
    PackedFloat32Array to_;
    double elapsed_ = 0.0;
    double duration_ = 0.0;
    std::vector<int32_t> event_frame_;
    std::vector<String> event_type_;
    std::vector<Dictionary> event_data_;

    static double clamp01(double v);
    static double smoothstep(double v);
    static double angle_delta(double from, double to);
    static float finite_angle(float v);
    Array collect_range(int lo, int hi) const;
};

} // namespace godot

#endif // IVORY_ANIMATION_H
