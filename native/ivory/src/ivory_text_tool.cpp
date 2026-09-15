#include "ivory_text_tool.h"

#include <algorithm>
#include <cmath>

using namespace godot;

const double IvoryTextTool::LEAST_SIZE = 12.0;

void IvoryTextTool::_bind_methods() {
    ClassDB::bind_method(D_METHOD("hit_test", "box", "turn", "at", "reach"),
            &IvoryTextTool::hit_test);
    ClassDB::bind_method(D_METHOD("moved", "box", "from", "to"),
            &IvoryTextTool::moved);
    ClassDB::bind_method(D_METHOD("turned", "box", "from", "to"),
            &IvoryTextTool::turned);
    ClassDB::bind_method(D_METHOD("sized", "box", "turn", "part", "from", "to", "even"),
            &IvoryTextTool::sized);
    ClassDB::bind_method(D_METHOD("preview_transform", "center", "new_center",
            "delta_turn", "relative_scale"), &IvoryTextTool::preview_transform);
    ClassDB::bind_method(D_METHOD("clamp_scale", "value", "minimum", "maximum"),
            &IvoryTextTool::clamp_scale);
}

Vector2 IvoryTextTool::corner(const Rect2 &box, double turn, int index) {
    const Vector2 mid = box.get_center();
    // godot-cpp's Rect2 exposes get_end(); `box.end` is GDScript-only syntax
    // and would not compile against the real headers.
    const Vector2 far = box.get_end();
    Vector2 p;
    switch (index) {
        case 0: p = box.position; break;
        case 1: p = Vector2(far.x, box.position.y); break;
        case 2: p = far; break;
        default: p = Vector2(box.position.x, far.y); break;
    }
    return mid + (p - mid).rotated((real_t)turn);
}

int IvoryTextTool::corner_index(int part) {
    switch (part) {
        case TOP_RIGHT: return 1;
        case BOTTOM_RIGHT: return 2;
        case BOTTOM_LEFT: return 3;
        default: return 0;
    }
}

int IvoryTextTool::opposite(int part) {
    switch (part) {
        case TOP_LEFT: return BOTTOM_RIGHT;
        case TOP_RIGHT: return BOTTOM_LEFT;
        case BOTTOM_RIGHT: return TOP_LEFT;
        case BOTTOM_LEFT: return TOP_RIGHT;
        default: return NOTHING;
    }
}

int IvoryTextTool::hit_test(const Rect2 &box, double turn,
        const Vector2 &at, double reach) const {
    if (box.size.x < 1.0 || box.size.y < 1.0) {
        return NOTHING;
    }
    const Vector2 mid = box.get_center();
    const Vector2 grip = mid + Vector2(0.0,
            (real_t)(-box.size.y * 0.5 - 34.0)).rotated((real_t)turn);
    if (at.distance_to(grip) <= reach) {
        return TURN;
    }
    for (int i = 0; i < 4; ++i) {
        if (at.distance_to(corner(box, turn, i)) <= reach) {
            return i == 0 ? TOP_LEFT : i == 1 ? TOP_RIGHT :
                    i == 2 ? BOTTOM_RIGHT : BOTTOM_LEFT;
        }
    }
    const Vector2 local = mid + (at - mid).rotated((real_t)-turn);
    if (box.grow((real_t)(reach * 0.4)).has_point(local)) {
        return MOVE;
    }
    return NOTHING;
}

Rect2 IvoryTextTool::moved(const Rect2 &box, const Vector2 &from,
        const Vector2 &to) const {
    return Rect2(box.position + (to - from), box.size);
}

double IvoryTextTool::turned(const Rect2 &box, const Vector2 &from,
        const Vector2 &to) const {
    const Vector2 mid = box.get_center();
    return (to - mid).angle() - (from - mid).angle();
}

Rect2 IvoryTextTool::sized(const Rect2 &box, double turn, int part,
        const Vector2 &from, const Vector2 &to, bool even) const {
    const int pinned = opposite(part);
    if (pinned == NOTHING) {
        return box;
    }
    const Vector2 grabbed = corner(box, turn, corner_index(part));
    const Vector2 anchor = corner(box, turn, corner_index(pinned));
    // Preserve exactly where the fingertip caught the handle. This eliminates
    // the first-frame jump caused by assuming the finger landed on its centre.
    const Vector2 carried = to + (grabbed - from);
    const Vector2 was = (grabbed - anchor).rotated((real_t)-turn);
    const Vector2 now = (carried - anchor).rotated((real_t)-turn);
    if (std::abs(was.x) < 0.001 || std::abs(was.y) < 0.001) {
        return box;
    }

    double kx = now.x / was.x;
    double ky = now.y / was.y;
    if (even) {
        const double k = std::max(std::abs(kx), std::abs(ky));
        kx = k;
        ky = k;
    } else {
        kx = std::abs(kx);
        ky = std::abs(ky);
    }

    const Vector2 wide(
            (real_t)std::max(box.size.x * kx, LEAST_SIZE),
            (real_t)std::max(box.size.y * ky, LEAST_SIZE));
    const double sx = (pinned == TOP_RIGHT || pinned == BOTTOM_RIGHT) ? -1.0 : 1.0;
    const double sy = (pinned == BOTTOM_LEFT || pinned == BOTTOM_RIGHT) ? -1.0 : 1.0;
    const Vector2 far = anchor + Vector2((real_t)(wide.x * sx),
            (real_t)(wide.y * sy)).rotated((real_t)turn);
    const Vector2 mid = (anchor + far) * 0.5;
    return Rect2(mid - wide * 0.5, wide);
}

Dictionary IvoryTextTool::preview_transform(const Vector2 &center,
        const Vector2 &new_center, double delta_turn,
        double relative_scale) const {
    const double s = std::max(relative_scale, 0.001);
    // Node2D transforms around its local origin. Choose the translation so
    // that the old text centre lands exactly on the new centre. This lets the
    // raster stay untouched during the gesture while the whole text object
    // follows the finger at display rate.
    const Vector2 pos = new_center - center.rotated((real_t)delta_turn) * (real_t)s;
    Dictionary out;
    out["position"] = pos;
    out["rotation"] = delta_turn;
    out["scale"] = s;
    return out;
}

double IvoryTextTool::clamp_scale(double value, double minimum,
        double maximum) const {
    const double lo = std::max(std::min(minimum, maximum), 0.001);
    const double hi = std::max(std::max(minimum, maximum), lo);
    return std::min(std::max(value, lo), hi);
}
