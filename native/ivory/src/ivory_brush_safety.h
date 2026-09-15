#ifndef IVORY_BRUSH_SAFETY_H
#define IVORY_BRUSH_SAFETY_H

#include <cmath>
#include <cstddef>
#include <limits>

namespace ivory {

// Small, dependency-free invariants used at the native brush boundary.
// Each guard is deterministic and rejects unsafe input instead of repairing it.
class BrushSafety13 {
public:
    static bool finite(double v) { return std::isfinite(v); }
    static bool finite_point(double x, double y) { return finite(x) && finite(y); }
    static bool positive_size(int px) { return px >= 8 && px <= 2048; }
    static bool valid_variant(int variant) { return variant >= 0 && variant < 5; }
    static bool valid_opacity(double v) { return finite(v) && v >= 0.0 && v <= 1.0; }
    static bool valid_pressure(double v) { return finite(v) && v >= 0.0 && v <= 1.0; }
    static bool valid_spacing(double v) { return finite(v) && v >= 0.1 && v <= 4096.0; }
    static bool valid_radius(double v) { return finite(v) && v > 0.0 && v <= 4096.0; }
    static bool inside_page(double x, double y, double w, double h) {
        return finite_point(x, y) && finite(w) && finite(h) &&
            w > 0.0 && h > 0.0 && x >= 0.0 && y >= 0.0 && x <= w && y <= h;
    }
    static bool bounded_count(std::size_t n) { return n > 0 && n <= 1000000; }
    static bool monotonic_time(double previous, double current) {
        return finite(previous) && finite(current) && current >= previous;
    }
    static bool no_reentry(bool drawing, bool starting) { return !drawing || !starting; }
    static bool paintable_layer(bool visible, bool locked, bool surface) {
        return visible && !locked && surface;
    }
    static bool valid_stamp_request(int px, int variant) {
        return positive_size(px) && valid_variant(variant);
    }
};

} // namespace ivory
#endif
