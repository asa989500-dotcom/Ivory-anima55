#ifndef IVORY_ANIMATION_WORKSPACE_PICKER_H
#define IVORY_ANIMATION_WORKSPACE_PICKER_H

#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/panel_container.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

// Stage 179: the Animation workspace decision is a deliberately tiny native
// surface.  It contains exactly two real Button nodes, is fixed with no
// scrolling mechanism, and owns its geometry instead of asking a Container to
// redistribute the two touch targets.
class IvoryAnimationWorkspacePicker : public PanelContainer {
    GDCLASS(IvoryAnimationWorkspacePicker, PanelContainer)

protected:
    static void _bind_methods();
    void _notification(int p_what);

private:
    static constexpr float PANEL_W = 430.0f;
    static constexpr float PANEL_H = 236.0f;
    static constexpr float PAD_X = 20.0f;
    static constexpr float PAD_TOP = 18.0f;
    static constexpr float GAP = 12.0f;
    static constexpr float BUTTON_H = 78.0f;
    static constexpr int PANEL_Z = 20000;
    static constexpr int BUTTON_Z = 20002;

    bool built_ = false;
    bool guard_passed_ = false;
    Control *surface_ = nullptr;
    Button *ivory_button_ = nullptr;
    Button *stretchy_button_ = nullptr;

    void build_ui();
    void layout_fixed();
    bool safety_guard_29() const;
    void choose_ivory();
    void choose_stretchy();

public:
    IvoryAnimationWorkspacePicker() = default;
    ~IvoryAnimationWorkspacePicker() = default;
};

} // namespace godot

#endif // IVORY_ANIMATION_WORKSPACE_PICKER_H
