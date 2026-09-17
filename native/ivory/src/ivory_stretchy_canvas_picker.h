#ifndef IVORY_STRETCHY_CANVAS_PICKER_H
#define IVORY_STRETCHY_CANVAS_PICKER_H

#include <godot_cpp/classes/panel_container.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Native C++ first step for a Stretchy Studio animation project.
// The picker owns only the canvas-size decision. Project creation and the
// Stretchy room remain owned by the existing Ivory bridge.
class IvoryStretchyCanvasPicker : public PanelContainer {
    GDCLASS(IvoryStretchyCanvasPicker, PanelContainer)

protected:
    static void _bind_methods();
    void _notification(int p_what);

private:
    bool built_ = false;
    void build_ui();
    void choose_canvas(int width, int height, String key);
    void choose_back();

public:
    IvoryStretchyCanvasPicker() = default;
    ~IvoryStretchyCanvasPicker() = default;
};

} // namespace godot

#endif // IVORY_STRETCHY_CANVAS_PICKER_H
