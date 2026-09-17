#ifndef IVORY_TEXT_TOOL_H
#define IVORY_TEXT_TOOL_H

// Native text-object interaction kernel.
//
// The rasterizer stays in Godot's TextServer because shaping belongs there.
// This class owns only the hot interaction math: hit testing, move/resize/
// rotate geometry, scale clamping, and the transform used to preview the
// object without touching its pixels. That keeps a finger drag allocation-
// free and avoids re-rendering text on every motion event.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class IvoryTextTool : public RefCounted {
    GDCLASS(IvoryTextTool, RefCounted)

protected:
    static void _bind_methods();

public:
    enum Part {
        NOTHING = 0,
        MOVE = 1,
        TURN = 2,
        TOP_LEFT = 3,
        TOP_RIGHT = 4,
        BOTTOM_RIGHT = 5,
        BOTTOM_LEFT = 6,
    };

    int hit_test(const Rect2 &box, double turn, const Vector2 &at,
            double reach) const;
    Rect2 moved(const Rect2 &box, const Vector2 &from,
            const Vector2 &to) const;
    double turned(const Rect2 &box, const Vector2 &from,
            const Vector2 &to) const;
    Rect2 sized(const Rect2 &box, double turn, int part,
            const Vector2 &from, const Vector2 &to, bool even) const;

    // Returns the non-destructive Node2D preview transform for the current
    // drag. `center` and `new_center` are in the same canvas space as the
    // text pixels. `relative_scale` is against the pixels already rendered.
    // The result has `position`, `rotation`, and `scale` keys.
    Dictionary preview_transform(const Vector2 &center,
            const Vector2 &new_center, double delta_turn,
            double relative_scale) const;

    double clamp_scale(double value, double minimum,
            double maximum) const;

    static const double LEAST_SIZE;

private:
    static Vector2 corner(const Rect2 &box, double turn, int index);
    static int opposite(int part);
    static int corner_index(int part);
};

} // namespace godot

VARIANT_ENUM_CAST(IvoryTextTool::Part);

#endif // IVORY_TEXT_TOOL_H
