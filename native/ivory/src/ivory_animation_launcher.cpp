#include "ivory_animation_launcher.h"

using namespace godot;

void IvoryAnimationLauncher::_bind_methods() {
    ClassDB::bind_method(D_METHOD("workspace_modes"),
            &IvoryAnimationLauncher::workspace_modes);
    ClassDB::bind_method(D_METHOD("stretchy_canvas_presets"),
            &IvoryAnimationLauncher::stretchy_canvas_presets);
    ClassDB::bind_method(D_METHOD("valid_workspace", "workspace"),
            &IvoryAnimationLauncher::valid_workspace);
    ClassDB::bind_method(D_METHOD("workspace_mode_count"),
            &IvoryAnimationLauncher::workspace_mode_count);
    ClassDB::bind_method(D_METHOD("default_workspace"),
            &IvoryAnimationLauncher::default_workspace);
    ClassDB::bind_method(D_METHOD("default_fps"),
            &IvoryAnimationLauncher::default_fps);
}

Array IvoryAnimationLauncher::workspace_modes() const {
    Array out;
    Dictionary ivory;
    ivory["id"] = "ivory";
    ivory["title"] = "Ivory";
    ivory["title_ar"] = "إيفوري";
    ivory["description"] = "Normal Ivory animation project";
    ivory["description_ar"] = "مشروع رسوم متحركة عادي في إيفوري";
    out.append(ivory);

    Dictionary stretchy;
    stretchy["id"] = "stretchy";
    stretchy["title"] = "Stretchy Studio";
    stretchy["title_ar"] = "Stretchy Studio";
    stretchy["description"] = "Professional animation workspace";
    stretchy["description_ar"] = "غرفة الرسوم الاحترافية Stretchy Studio";
    out.append(stretchy);
    return out;
}

Array IvoryAnimationLauncher::stretchy_canvas_presets() const {
    Array out;

    // Deliberately short: the user should choose only the starting canvas
    // here. Everything else is configured after Stretchy opens.
    struct Preset { const char *key; int w; int h; const char *group; };
    static constexpr Preset PRESETS[] = {
        {"Full HD", 1920, 1080, "screen"},
        {"Vertical HD", 1080, 1920, "screen"},
        {"4K UHD", 3840, 2160, "screen"},
        {"Square 2K", 2048, 2048, "square"},
        {"A4 300", 2480, 3508, "print"},
        {"Comic page", 1988, 3056, "print"},
    };

    for (const Preset &p : PRESETS) {
        Dictionary row;
        row["key"] = String(p.key);
        row["w"] = p.w;
        row["h"] = p.h;
        row["group"] = String(p.group);
        out.append(row);
    }
    return out;
}

int IvoryAnimationLauncher::workspace_mode_count() const {
    return 2;
}

bool IvoryAnimationLauncher::valid_workspace(const String &workspace) const {
    return workspace == "ivory" || workspace == "stretchy";
}

String IvoryAnimationLauncher::default_workspace() const {
    return "ivory";
}

int IvoryAnimationLauncher::default_fps() const {
    return 24;
}
