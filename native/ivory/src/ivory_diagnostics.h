#ifndef IVORY_DIAGNOSTICS_H
#define IVORY_DIAGNOSTICS_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

// Runtime integrity instruments for IVORY's native geometry boundary.
//
// This class deliberately does not repair data silently. It reports precise
// invariant failures so the GDScript layer can refuse a bad mesh/pose instead
// of letting one NaN or an invalid triangle poison the renderer.
class IvoryDiagnostics : public RefCounted {
	GDCLASS(IvoryDiagnostics, RefCounted)

protected:
	static void _bind_methods();

public:
	IvoryDiagnostics() = default;
	~IvoryDiagnostics() = default;

	Dictionary check_mesh(const PackedVector2Array &rest,
			const PackedInt32Array &neighbours, const PackedByteArray &rim,
			const PackedInt32Array &triangles, double min_area) const;

	Dictionary check_pose(const PackedVector2Array &rest,
			const PackedVector2Array &now, double max_displacement) const;

	Dictionary check_pins(const PackedVector2Array &rest_pins,
			const PackedVector2Array &now_pins, const PackedInt32Array &vertex,
			const PackedFloat32Array &turn, int vertex_count) const;

	Dictionary check_bounds(const PackedVector2Array &points,
			const Vector2 &min_corner, const Vector2 &max_corner,
			double epsilon) const;

	Dictionary check_frame(double elapsed_ms, double budget_ms,
			int vertex_count, int triangle_count) const;

	Dictionary health(const Dictionary &mesh, const Dictionary &pose,
			const Dictionary &pins, const Dictionary &bounds,
			const Dictionary &frame) const;

private:
	static bool finite(double value);
	static bool finite_vec(const Vector2 &value);
	static double area(const Vector2 &a, const Vector2 &b, const Vector2 &c);
	static Dictionary result(bool ok, int failures, const Array &issues);
	static void issue(Array &issues, const String &code, const String &detail,
			int index = -1);
};

} // namespace godot

#endif // IVORY_DIAGNOSTICS_H
