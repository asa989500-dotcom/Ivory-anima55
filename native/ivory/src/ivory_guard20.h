#ifndef IVORY_GUARD20_H
#define IVORY_GUARD20_H

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

// Twenty narrow, deterministic runtime guards. Each returns {ok, failures,
// issues} and never repairs data implicitly.
class IvoryGuard20 : public RefCounted {
	GDCLASS(IvoryGuard20, RefCounted)
protected:
	static void _bind_methods();
public:
	Dictionary mesh_topology(const PackedVector2Array &, const PackedInt32Array &, const PackedInt32Array &) const;
	Dictionary finite_geometry(const PackedVector2Array &) const;
	Dictionary triangle_area(const PackedVector2Array &, const PackedInt32Array &, double) const;
	Dictionary pose_displacement(const PackedVector2Array &, const PackedVector2Array &, double) const;
	Dictionary pin_binding(const PackedInt32Array &, int) const;
	Dictionary pin_finite(const PackedVector2Array &) const;
	Dictionary bounds(const PackedVector2Array &, const Vector2 &, const Vector2 &, double) const;
	Dictionary skin_weights(const PackedFloat32Array &, int, double) const;
	Dictionary bone_hierarchy(const PackedInt32Array &) const;
	Dictionary transform_finite(const PackedVector2Array &) const;
	Dictionary symmetry(double, int) const;
	Dictionary timeline(const PackedInt32Array &, int) const;
	Dictionary frame_budget(double, double) const;
	Dictionary texture_extent(int, int, int) const;
	Dictionary pixel_buffer(const PackedByteArray &, int, int, int) const;
	Dictionary touch_stream(const PackedVector2Array &, double) const;
	Dictionary audio_sync(double, double) const;
	Dictionary export_settings(int, int, int, int) const;
	Dictionary memory_budget(int64_t, int64_t) const;
	Dictionary aggregate(const Array &) const;
private:
	static Dictionary result(bool, int, const Array &);
	static void issue(Array &, const String &, const String &, int index = -1);
	static bool finite(double);
	static bool finite_vec(const Vector2 &);
	static double tri_area(const Vector2 &, const Vector2 &, const Vector2 &);
};

} // namespace godot
#endif
