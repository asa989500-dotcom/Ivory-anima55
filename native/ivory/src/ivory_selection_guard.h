#ifndef IVORY_SELECTION_GUARD_H
#define IVORY_SELECTION_GUARD_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

// Native safety boundary for the floating-selection pipeline.
//
// This class does not own selection state and does not move pixels. It only
// validates the numerical contract before expensive Image work or a transform
// is allowed to proceed. Keeping this contract in C++ makes the dangerous
// arithmetic independent from the UI/event path and gives Android the same
// finite/bounded rules as desktop.
class IvorySelectionGuard : public RefCounted {
	GDCLASS(IvorySelectionGuard, RefCounted)

protected:
	static void _bind_methods();

public:
	Dictionary validate_mark(const PackedVector2Array &points, int shape,
			int max_lift) const;
	Dictionary validate_transform(const Vector2 &center, const Vector2 &size,
			double scale, double rotation, int max_lift) const;
	bool finite_point(const Vector2 &point) const;
	bool finite_scalar(double value) const;
};

} // namespace godot

#endif // IVORY_SELECTION_GUARD_H
