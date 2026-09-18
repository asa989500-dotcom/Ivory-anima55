#include "ivory_stretchy_canvas_picker.h"

#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/grid_container.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/margin_container.hpp>
#include <godot_cpp/classes/text_server.hpp>
#include <godot_cpp/classes/v_box_container.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

void IvoryStretchyCanvasPicker::_bind_methods() {
    ADD_SIGNAL(MethodInfo("canvas_selected",
            PropertyInfo(Variant::INT, "width"),
            PropertyInfo(Variant::INT, "height"),
            PropertyInfo(Variant::STRING, "key")));
    ADD_SIGNAL(MethodInfo("back_requested"));
    ClassDB::bind_method(D_METHOD("_choose_canvas", "width", "height", "key"),
            &IvoryStretchyCanvasPicker::choose_canvas);
    ClassDB::bind_method(D_METHOD("_choose_back"),
            &IvoryStretchyCanvasPicker::choose_back);
}

void IvoryStretchyCanvasPicker::_notification(int p_what) {
    if (p_what == NOTIFICATION_READY && !built_) {
        build_ui();
    }
}

void IvoryStretchyCanvasPicker::build_ui() {
    built_ = true;
    set_custom_minimum_size(Vector2(410.0, 430.0));
    set_size(Vector2(410.0, 430.0));

    MarginContainer *margin = memnew(MarginContainer);
    margin->add_theme_constant_override("margin_left", 20);
    margin->add_theme_constant_override("margin_right", 20);
    margin->add_theme_constant_override("margin_top", 18);
    margin->add_theme_constant_override("margin_bottom", 18);
    add_child(margin);

    VBoxContainer *column = memnew(VBoxContainer);
    column->add_theme_constant_override("separation", 10);
    margin->add_child(column);

    Button *back = memnew(Button);
    back->set_text("Back  /  رجوع");
    back->set_custom_minimum_size(Vector2(0.0, 48.0));
    back->set_focus_mode(Control::FOCUS_NONE);
    back->connect("pressed", Callable(this, StringName("_choose_back")));
    column->add_child(back);

    Label *title = memnew(Label);
    title->set_text("Stretchy Studio  /  Canvas");
    title->add_theme_font_size_override("font_size", 22);
    title->set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER);
    column->add_child(title);

    Label *note = memnew(Label);
    note->set_text("Choose a starting canvas. Stretchy Studio owns the rest.");
    note->set_autowrap_mode(TextServer::AUTOWRAP_WORD_SMART);
    note->set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER);
    column->add_child(note);

    GridContainer *grid = memnew(GridContainer);
    grid->set_columns(2);
    grid->add_theme_constant_override("h_separation", 8);
    grid->add_theme_constant_override("v_separation", 8);
    column->add_child(grid);

    struct Preset {
        const char *key;
        int width;
        int height;
    };
    static constexpr Preset presets[] = {
        {"Full HD", 1920, 1080},
        {"Vertical HD", 1080, 1920},
        {"4K UHD", 3840, 2160},
        {"Square 2K", 2048, 2048},
        {"A4 300", 2480, 3508},
        {"Comic page", 1988, 3056},
    };

    for (const Preset &preset : presets) {
        Button *button = memnew(Button);
        button->set_text(String(preset.key) + "\n" +
                String::num_int64(preset.width) + " × " +
                String::num_int64(preset.height));
        button->set_custom_minimum_size(Vector2(0.0, 68.0));
        button->set_h_size_flags(Control::SIZE_EXPAND_FILL);
        button->set_focus_mode(Control::FOCUS_NONE);
        button->connect("pressed", Callable(this, StringName("_choose_canvas")).bind(
                preset.width, preset.height, String(preset.key)));
        grid->add_child(button);
    }
}

void IvoryStretchyCanvasPicker::choose_canvas(int width, int height, String key) {
    if (width <= 0 || height <= 0 || key.is_empty()) {
        return;
    }
    emit_signal("canvas_selected", width, height, key);
}

void IvoryStretchyCanvasPicker::choose_back() {
    emit_signal("back_requested");
}
