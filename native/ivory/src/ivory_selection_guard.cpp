#include "ivory_selection_guard.h"

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

namespace {

static bool finite_value(double v) {
	return std::isfinite(v);
}

static bool finite_vec(const Vector2 &v) {
	return finite_value((double)v.x) && finite_value((double)v.y);
}

static Dictionary result(bool ok, const char *reason) {
	Dictionary d;
	d["ok"] = ok;
	d["reason"] = String(reason);
	return d;
}

} // namespace

void IvorySelectionGuard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("validate_mark", "points", "shape", "max_lift"),
			&IvorySelectionGuard::validate_mark);
	ClassDB::bind_method(D_METHOD("validate_transform", "center", "size",
				"scale", "rotation", "max_lift"),
			&IvorySelectionGuard::validate_transform);
	ClassDB::bind_method(D_METHOD("finite_point", "point"),
			&IvorySelectionGuard::finite_point);
	ClassDB::bind_method(D_METHOD("finite_scalar", "value"),
			&IvorySelectionGuard::finite_scalar);
}

bool IvorySelectionGuard::finite_point(const Vector2 &point) const {
	return finite_vec(point);
}

bool IvorySelectionGuard::finite_scalar(double value) const {
	return finite_value(value);
}

Dictionary IvorySelectionGuard::validate_mark(const PackedVector2Array &points,
		int shape, int max_lift) const {
	if (max_lift < 2) {
		return result(false, "invalid_selection_limit");
	}
	if (points.size() < 2) {
		return result(false, "selection_needs_two_points");
	}

	double min_x = std::numeric_limits<double>::infinity();
	double min_y = std::numeric_limits<double>::infinity();
	double max_x = -std::numeric_limits<double>::infinity();
	double max_y = -std::numeric_limits<double>::infinity();
	for (int i = 0; i < points.size(); ++i) {
		const Vector2 p = points[i];
		if (!finite_vec(p)) {
			return result(false, "selection_contains_non_finite_point");
		}
		min_x = std::min(min_x, (double)p.x);
		min_y = std::min(min_y, (double)p.y);
		max_x = std::max(max_x, (double)p.x);
		max_y = std::max(max_y, (double)p.y);
	}

	// Bounds are measured with the same one-pixel safety expansion used by
	// SelectionMask::bounds_of. Do the arithmetic in double so a huge touch
	// coordinate cannot overflow an int before the limit is checked.
	const double width = std::ceil(max_x) + 1.0 - (std::floor(min_x) - 1.0);
	const double height = std::ceil(max_y) + 1.0 - (std::floor(min_y) - 1.0);
	if (!finite_value(width) || !finite_value(height) || width < 2.0 || height < 2.0) {
		return result(false, "selection_has_no_area");
	}
	if (width > (double)max_lift || height > (double)max_lift) {
		return result(false, "selection_exceeds_safe_size");
	}

	Dictionary out = result(true, "ok");
	out["x"] = (int)std::floor(min_x) - 1;
	out["y"] = (int)std::floor(min_y) - 1;
	out["width"] = (int)std::ceil(width);
	out["height"] = (int)std::ceil(height);
	out["points"] = points.size();
	out["shape"] = shape;
	return out;
}

Dictionary IvorySelectionGuard::validate_transform(const Vector2 &center,
		const Vector2 &size, double scale, double rotation, int max_lift) const {
	if (max_lift < 2) {
		return result(false, "invalid_selection_limit");
	}
	if (!finite_vec(center) || !finite_vec(size) || !finite(scale)
			|| !finite(rotation)) {
		return result(false, "selection_transform_non_finite");
	}
	if (size.x <= 0.0f || size.y <= 0.0f) {
		return result(false, "selection_size_invalid");
	}
	if (scale < 0.02 || scale > 40.0) {
		return result(false, "selection_scale_out_of_range");
	}

	const double w = (double)size.x * scale;
	const double h = (double)size.y * scale;
	const double c = std::fabs(std::cos(rotation));
	const double s = std::fabs(std::sin(rotation));
	const double bound_w = w * c + h * s;
	const double bound_h = w * s + h * c;
	if (!finite_value(w) || !finite_value(h) || !finite_value(bound_w)
			|| !finite_value(bound_h) || bound_w > (double)max_lift
			|| bound_h > (double)max_lift) {
		return result(false, "selection_transform_exceeds_safe_size");
	}

	Dictionary out = result(true, "ok");
	out["scaled_width"] = w;
	out["scaled_height"] = h;
	out["rotated_width"] = bound_w;
	out["rotated_height"] = bound_h;
	return out;
}
