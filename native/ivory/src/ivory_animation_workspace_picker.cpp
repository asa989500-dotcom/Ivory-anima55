#include "ivory_animation_workspace_picker.h"

#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

void IvoryAnimationWorkspacePicker::_bind_methods() {
    ADD_SIGNAL(MethodInfo("workspace_selected",
            PropertyInfo(Variant::STRING, "workspace")));
    ClassDB::bind_method(D_METHOD("_choose_ivory"),
            &IvoryAnimationWorkspacePicker::choose_ivory);
    ClassDB::bind_method(D_METHOD("_choose_stretchy"),
            &IvoryAnimationWorkspacePicker::choose_stretchy);
}

void IvoryAnimationWorkspacePicker::_notification(int p_what) {
    if (p_what == NOTIFICATION_READY) {
        if (!built_) {
            build_ui();
        }
        layout_fixed();
    } else if (p_what == NOTIFICATION_RESIZED && built_) {
        layout_fixed();
    }
}

void IvoryAnimationWorkspacePicker::build_ui() {
    if (built_) {
        return;
    }
    built_ = true;

    // Guard 1-7: fixed panel identity, dimensions, clipping and input policy.
    set_custom_minimum_size(Vector2(PANEL_W, PANEL_H));
    set_size(Vector2(PANEL_W, PANEL_H));
    set_mouse_filter(Control::MOUSE_FILTER_STOP);
    set_clip_contents(false);
    set_z_index(PANEL_Z);
    set_z_as_relative(false);

    // A plain Control is used as the single PanelContainer child.  This avoids
    // VBox/Grid layout negotiation completely.  The two
    // buttons are positioned by C++ below and cannot be pushed below a list.
    surface_ = memnew(Control);
    surface_->set_anchors_and_offsets_preset(Control::PRESET_FULL_RECT);
    surface_->set_mouse_filter(Control::MOUSE_FILTER_IGNORE);
    surface_->set_clip_contents(false);
    surface_->set_z_index(PANEL_Z + 1);
    surface_->set_z_as_relative(false);
    add_child(surface_);

    Label *title = memnew(Label);
    title->set_text("Animation Project");
    title->add_theme_font_size_override("font_size", 20);
    title->set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER);
    title->set_mouse_filter(Control::MOUSE_FILTER_IGNORE);
    title->set_anchors_and_offsets_preset(Control::PRESET_TOP_WIDE);
    title->set_position(Vector2(PAD_X, PAD_TOP));
    title->set_size(Vector2(PANEL_W - PAD_X * 2.0f, 28.0f));
    title->set_z_index(PANEL_Z + 1);
    title->set_z_as_relative(false);
    surface_->add_child(title);

    // Exactly two real Button nodes.  No list, no scroll view, no generated
    // rows and no fallback button is allowed in this class.
    ivory_button_ = memnew(Button);
    ivory_button_->set_name("IvoryWorkspaceButton");
    ivory_button_->set_text("Ivory");
    ivory_button_->set_focus_mode(Control::FOCUS_NONE);
    ivory_button_->set_mouse_filter(Control::MOUSE_FILTER_STOP);
    ivory_button_->set_z_index(BUTTON_Z);
    ivory_button_->set_z_as_relative(false);
    ivory_button_->set_toggle_mode(false);
    ivory_button_->set_disabled(false);
    ivory_button_->set_visible(true);
    ivory_button_->set_custom_minimum_size(Vector2(PANEL_W - PAD_X * 2.0f, BUTTON_H));
    ivory_button_->connect("pressed", Callable(this, "_choose_ivory"));
    surface_->add_child(ivory_button_);

    stretchy_button_ = memnew(Button);
    stretchy_button_->set_name("StretchyWorkspaceButton");
    stretchy_button_->set_text("Stretchy Studio");
    stretchy_button_->set_focus_mode(Control::FOCUS_NONE);
    stretchy_button_->set_mouse_filter(Control::MOUSE_FILTER_STOP);
    stretchy_button_->set_z_index(BUTTON_Z);
    stretchy_button_->set_z_as_relative(false);
    stretchy_button_->set_toggle_mode(false);
    stretchy_button_->set_disabled(false);
    stretchy_button_->set_visible(true);
    stretchy_button_->set_custom_minimum_size(Vector2(PANEL_W - PAD_X * 2.0f, BUTTON_H));
    stretchy_button_->connect("pressed", Callable(this, "_choose_stretchy"));
    surface_->add_child(stretchy_button_);

    layout_fixed();
    guard_passed_ = safety_guard_29();
    if (!guard_passed_) {
        // Do not leave a half-built chooser active.  A broken geometry
        // contract is safer as a clearly empty native object than as buttons
        // placed somewhere the user cannot reliably reach.
        ivory_button_->hide();
        stretchy_button_->hide();
    }
}

void IvoryAnimationWorkspacePicker::layout_fixed() {
    if (!built_ || surface_ == nullptr || ivory_button_ == nullptr ||
            stretchy_button_ == nullptr) {
        return;
    }

    const float w = MAXF(get_size().x, PANEL_W);
    const float h = MAXF(get_size().y, PANEL_H);
    const float button_w = MAXF(1.0f, w - PAD_X * 2.0f);

    // The title is informational only; the two hit targets are the fixed
    // anchors of this panel.  Their positions are calculated from the panel,
    // never from viewport scrolling or a content-list length.
    const float first_y = PAD_TOP + 30.0f;
    const float second_y = first_y + BUTTON_H + GAP;

    surface_->set_size(Vector2(w, h));
    ivory_button_->set_position(Vector2(PAD_X, first_y));
    ivory_button_->set_size(Vector2(button_w, BUTTON_H));
    stretchy_button_->set_position(Vector2(PAD_X, second_y));
    stretchy_button_->set_size(Vector2(button_w, BUTTON_H));

    // Keep the visible touch targets in the panel even if an external parent
    // briefly supplies a larger size.  Never use a scroll offset to repair it.
    if (second_y + BUTTON_H > h) {
        const float safe_second = MAXF(PAD_TOP + 30.0f,
                h - BUTTON_H - PAD_TOP);
        const float safe_first = MAXF(PAD_TOP,
                safe_second - BUTTON_H - GAP);
        ivory_button_->set_position(Vector2(PAD_X, safe_first));
        stretchy_button_->set_position(Vector2(PAD_X, safe_second));
    }
}

bool IvoryAnimationWorkspacePicker::safety_guard_29() const {
    // 29 independent invariants.  They are intentionally boring: the point
    // is to make "the buttons are visible and touchable" a checked contract,
    // not a visual hope.
    int pass = 0;
    pass += built_;                                                       // 01
    pass += surface_ != nullptr;                                         // 02
    pass += ivory_button_ != nullptr;                                    // 03
    pass += stretchy_button_ != nullptr;                                 // 04
    pass += ivory_button_ != stretchy_button_;                           // 05
    pass += get_size().x >= PANEL_W - 0.5f;                              // 06
    pass += get_size().y >= PANEL_H - 0.5f;                              // 07
    pass += get_clip_contents() == false;                                // 08
    pass += get_mouse_filter() == Control::MOUSE_FILTER_STOP;             // 09
    pass += get_z_index() >= PANEL_Z;                                    // 10
    pass += surface_->get_parent() == this;                              // 11
    pass += ivory_button_->get_parent() == surface_;                     // 12
    pass += stretchy_button_->get_parent() == surface_;                 // 13
    pass += ivory_button_->is_visible();                                 // 14
    pass += stretchy_button_->is_visible();                              // 15
    pass += !ivory_button_->is_disabled();                               // 16
    pass += !stretchy_button_->is_disabled();                            // 17
    pass += ivory_button_->get_mouse_filter() == Control::MOUSE_FILTER_STOP; // 18
    pass += stretchy_button_->get_mouse_filter() == Control::MOUSE_FILTER_STOP; // 19
    pass += ivory_button_->get_z_index() >= BUTTON_Z;                    // 20
    pass += stretchy_button_->get_z_index() >= BUTTON_Z;                 // 21
    pass += !ivory_button_->is_toggle_mode();                            // 22
    pass += !stretchy_button_->is_toggle_mode();                         // 23
    pass += ivory_button_->get_size().x > 1.0f && ivory_button_->get_size().y >= BUTTON_H - 1.0f; // 24
    pass += stretchy_button_->get_size().x > 1.0f && stretchy_button_->get_size().y >= BUTTON_H - 1.0f; // 25
    pass += ivory_button_->get_position().y >= 0.0f && stretchy_button_->get_position().y >= 0.0f; // 26
    pass += ivory_button_->get_position().y + ivory_button_->get_size().y <= get_size().y + 1.0f; // 27
    pass += stretchy_button_->get_position().y + stretchy_button_->get_size().y <= get_size().y + 1.0f; // 28
    pass += ivory_button_->is_connected("pressed", Callable(this, "_choose_ivory")) &&
            stretchy_button_->is_connected("pressed", Callable(this, "_choose_stretchy")); // 29
    return pass == 29;
}

void IvoryAnimationWorkspacePicker::choose_ivory() {
    if (!guard_passed_ || ivory_button_ == nullptr || !ivory_button_->is_visible()) {
        return;
    }
    emit_signal("workspace_selected", String("ivory"));
}

void IvoryAnimationWorkspacePicker::choose_stretchy() {
    if (!guard_passed_ || stretchy_button_ == nullptr || !stretchy_button_->is_visible()) {
        return;
    }
    emit_signal("workspace_selected", String("stretchy"));
}
