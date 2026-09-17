#ifndef IVORY_ANIMATION_LAUNCHER_H
#define IVORY_ANIMATION_LAUNCHER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Native launch contract for the Animation-project entry point.
//
// UI code is intentionally kept outside this class. This class owns the
// decision that matters at project creation time: which animation workspace
// was chosen and which canvas presets that workspace may start with. The
// GDScript side only renders the returned data and forwards the user's choice
// back into the existing ProjectManager/Stretchy room.
class IvoryAnimationLauncher : public RefCounted {
    GDCLASS(IvoryAnimationLauncher, RefCounted)

protected:
    static void _bind_methods();

public:
    IvoryAnimationLauncher() = default;
    ~IvoryAnimationLauncher() = default;

    // Exactly the two first-class animation project workspaces.
    Array workspace_modes() const;

    // A compact, deliberate canvas list for the first Stretchy step. No FPS,
    // colour, page count, export or other project settings leak into this
    // list: Stretchy owns those after the room opens.
    Array stretchy_canvas_presets() const;

    // Stable native validation so a malformed UI value cannot create a third
    // hidden animation workspace.
    int workspace_mode_count() const;

    bool valid_workspace(const String &workspace) const;

    // Defaults used only for the hand-off into the existing animation model.
    String default_workspace() const;
    int default_fps() const;
};

} // namespace godot

#endif // IVORY_ANIMATION_LAUNCHER_H
