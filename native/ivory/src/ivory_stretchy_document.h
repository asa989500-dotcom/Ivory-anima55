#ifndef IVORY_STRETCHY_DOCUMENT_H
#define IVORY_STRETCHY_DOCUMENT_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

// Native data/operation core for the active Stretchy Studio document.
// The Godot control layer may render this dictionary, but mutations and
// document defaults live here so the authoring state is not implemented twice.
class IvoryStretchyDocument : public RefCounted {
    GDCLASS(IvoryStretchyDocument, RefCounted)

protected:
    static void _bind_methods();

private:
    Dictionary document_;

    Dictionary layer_at(int layer_index) const;
    static Array points_of(const Dictionary &layer);
    static Array triangles_of(const Dictionary &layer);

public:
    IvoryStretchyDocument() = default;
    ~IvoryStretchyDocument() = default;

    Dictionary create_document() const;
    void set_document(const Dictionary &document);
    Dictionary document() const;

    Dictionary clear_mesh(int layer_index);
    Dictionary add_point(int layer_index, const Vector2 &point);
    Dictionary move_point(int layer_index, int point_index, const Vector2 &point);
    Dictionary finish_triangle(int layer_index, const Array &point_indices);
    Dictionary add_layer(const String &id, const String &name, const String &texture_path);
    Dictionary add_bone(const Vector2 &start, const Vector2 &end);
    Dictionary rotate_bone(int bone_index, const Vector2 &tip);
    Dictionary set_parameter_value(int parameter_index, double value);
};

} // namespace godot

#endif // IVORY_STRETCHY_DOCUMENT_H
