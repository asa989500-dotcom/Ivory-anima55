#ifndef IVORY_DISTORT_H
#define IVORY_DISTORT_H
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/image.hpp>
namespace godot {
class IvoryDistort : public RefCounted {
	GDCLASS(IvoryDistort, RefCounted)
protected:
	static void _bind_methods();
public:
	enum Kind { LEAN, ARCH, SWELL, TWIST, PINCH };
	Ref<Image> apply(const Ref<Image> &image, int kind, double amount) const;
};
}
VARIANT_ENUM_CAST(godot::IvoryDistort::Kind);
#endif
