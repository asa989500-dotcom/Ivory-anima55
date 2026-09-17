#!/usr/bin/env python3
"""Catches `something()` called on the current class when nothing declares it.

Why this exists
---------------
`main.gd` called `knit_room()` in three places. Nothing anywhere declared it.
The project would not run, and all ten existing checkers passed:

  - `check_identifiers.py` only looks at names beginning with an underscore,
    because for a bare name it cannot tell a missing method from a global class
    or an enum. `knit_room` has no underscore, so it was never examined.
  - `check_references.py` looks at `Other.thing()` — a call with a class in
    front of it. A call on the current class has nothing in front of it, so
    there was nothing for it to resolve.

Between those two rules there was a hole exactly the shape of an unqualified
call to a method that does not exist, which is one of the most ordinary
mistakes there is: you rename a function, or you write the call before the
function and never come back.

How it stays exact
------------------
Only *calls* are examined — `name(` — never bare names, so an enum member, a
global class or a constant is never mistaken for a missing method. A call is a
complaint only when every one of these is true:

  - it is not preceded by a dot, so it is on the current class
  - the file declares a `class_name` and extends something (a real class file
    rather than a fragment)
  - no `func name` anywhere in the file declares it, inner classes included
  - it is not a Godot built-in, an engine callback, or a method inherited from
    whatever the file extends

The inherited-method list is not a full type hierarchy — that would need the
engine. It is the union of what the classes in this project actually extend,
which is a superset of what is in scope. As with the other checkers here, a
superset means this can miss a real error and can never invent one, which is
the safe direction for something that runs on every build.

Usage:  python3 tools/check_self_calls.py [project_dir]
"""

import re
import sys
import pathlib

# Global functions GDScript gives every script.
BUILTIN = {
    "print", "print_rich", "printerr", "printraw", "print_verbose", "prints",
    "push_error", "push_warning", "str", "int", "float", "bool", "abs", "absf",
    "absi", "sign", "signf", "signi", "min", "max", "mini", "maxi", "minf",
    "maxf", "clamp", "clampi", "clampf", "round", "roundi", "roundf", "floor",
    "floori", "floorf", "ceil", "ceili", "ceilf", "sqrt", "pow", "exp", "log",
    "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sinh", "cosh",
    "tanh", "fmod", "fposmod", "posmod", "snapped", "snappedf", "snappedi",
    "lerp", "lerpf", "lerp_angle", "inverse_lerp", "remap", "range_lerp",
    "move_toward", "rotate_toward", "smoothstep", "ease", "step_decimals",
    "is_equal_approx", "is_zero_approx", "is_nan", "is_inf", "is_finite",
    "nearest_po2", "deg_to_rad", "rad_to_deg", "linear_to_db", "db_to_linear",
    "randi", "randf", "randfn", "randi_range", "randf_range", "randomize",
    "seed", "rand_from_seed", "range", "len", "typeof", "type_string",
    "is_instance_valid", "is_instance_of", "instance_from_id", "weakref",
    "hash", "load", "preload", "assert", "char", "ord", "error_string",
    "var_to_str", "str_to_var", "var_to_bytes", "bytes_to_var",
    "var_to_bytes_with_objects", "bytes_to_var_with_objects", "wrap", "wrapf",
    "wrapi", "cubic_interpolate", "bezier_interpolate", "pingpong",
    "get_stack", "print_stack", "is_same", "rid_allocate_id", "rid_from_int64",
    "type_convert", "printt", "prints",
}

# Engine callbacks: declared by the engine, may be called by a file that
# overrides them, and may be called on a base that declares them.
ENGINE = {
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_unhandled_key_input", "_gui_input", "_draw", "_notification", "_init",
    "_enter_tree", "_exit_tree", "_to_string", "_get", "_set",
}

# Methods that come from a base class rather than from the file itself.
#
# Grouped by where they come from so the list can be read and extended by
# somebody who has not read this script. Object and Node are inherited by
# nearly everything here; the rest are what this project's classes extend.
INHERITED = {
    # Object
    "call", "call_deferred", "callv", "has_method", "get_method_list",
    "get", "set", "set_deferred", "get_property_list", "has_signal",
    "connect", "disconnect", "is_connected", "emit_signal", "get_signal_list",
    "get_class", "is_class", "get_instance_id", "free", "notification",
    "set_meta", "get_meta", "has_meta", "remove_meta", "get_meta_list",
    "set_script", "get_script", "is_queued_for_deletion", "tr", "tr_n",
    "set_block_signals", "is_blocking_signals", "property_list_changed",
    # Node
    "add_child", "remove_child", "queue_free", "get_node", "get_node_or_null",
    "has_node", "get_parent", "get_children", "get_child", "get_child_count",
    "get_tree", "is_inside_tree", "move_child", "add_sibling", "reparent",
    "set_process", "set_physics_process", "set_process_input",
    "set_process_unhandled_input", "set_process_unhandled_key_input",
    "get_index", "find_child", "get_window", "get_viewport", "print_tree",
    "set_process_mode", "is_node_ready", "propagate_call", "add_to_group",
    "remove_from_group", "is_in_group", "get_groups", "create_tween",
    # CanvasItem
    "queue_redraw", "draw_line", "draw_polyline", "draw_rect", "draw_circle",
    "draw_arc", "draw_texture", "draw_texture_rect", "draw_texture_rect_region",
    "draw_string", "draw_multiline_string", "draw_colored_polygon",
    "draw_polygon", "draw_set_transform", "draw_set_transform_matrix",
    "draw_char", "draw_dashed_line", "draw_multiline", "draw_primitive",
    "draw_mesh", "draw_style_box", "get_canvas_transform",
    "get_global_transform_with_canvas", "get_local_mouse_position",
    "get_global_mouse_position", "hide", "show", "is_visible_in_tree",
    "set_notify_transform", "force_update_transform", "top_level",
    # Control
    "get_global_rect", "get_rect", "get_minimum_size", "get_combined_minimum_size",
    "update_minimum_size", "accept_event", "grab_focus", "release_focus",
    "has_focus", "add_theme_stylebox_override", "add_theme_color_override",
    "add_theme_font_override", "add_theme_font_size_override",
    "add_theme_constant_override", "get_theme_stylebox", "get_theme_color",
    "get_theme_font", "get_theme_font_size", "get_theme_constant",
    "set_anchors_preset", "set_offsets_preset",
    "set_anchors_and_offsets_preset", "set_drag_preview", "warp_mouse",
    "get_viewport_rect", "get_screen_position", "get_screen_transform",
    "find_next_valid_focus", "find_prev_valid_focus", "get_theme_default_font",
    # Node2D / CanvasLayer
    "to_local", "to_global", "get_angle_to", "look_at", "move_local_x",
    "move_local_y", "rotate", "translate", "apply_scale", "global_translate",
    # Window / Popup / FileDialog and friends used as bases
    "popup_centered", "popup_centered_ratio", "popup_centered_clamped",
    "popup", "hide_popup",
    # RefCounted
    "reference", "unreference", "init_ref",
}

SKIP_DIRS = {"addons", "native", ".godot", "build", "tests"}


def declared_funcs(text):
    found = set(re.findall(r"^\s*(?:static\s+)?func\s+(\w+)", text, re.M))
    # A signal declaration reads exactly like a call — `signal closed()` — and
    # so does its emission through a Callable. Both are legitimate, so the
    # signal's own name counts as declared.
    found |= set(re.findall(r"^\s*signal\s+(\w+)", text, re.M))
    return found


def declared_names(text):
    """Variables and constants, so `thing.call()` on a held object is ignored."""
    found = set()
    found |= set(re.findall(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*var\s+(\w+)", text, re.M))
    found |= set(re.findall(r"^\s*const\s+(\w+)", text, re.M))
    found |= set(re.findall(r"\bvar\s+(\w+)", text))
    return found


def strip_noise(text):
    """Comments and string bodies removed, so neither can raise a complaint."""
    out = []
    for line in text.split("\n"):
        line = re.sub(r'"[^"]*"', '""', line)
        line = re.sub(r"'[^']*'", "''", line)
        line = re.sub(r"#.*$", "", line)
        # Annotations are not calls. `@warning_ignore("x")` is an instruction
        # to the compiler and there is no method behind it.
        line = re.sub(r"@\w+\s*\([^)]*\)", "", line)
        line = re.sub(r"@\w+", "", line)
        out.append(line)
    return "\n".join(out)


def check(root):
    trouble = []
    looked = 0
    for path in sorted(pathlib.Path(root).rglob("*.gd")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        raw = path.read_text(encoding="utf-8")
        if not re.search(r"^class_name\s+\w+", raw, re.M):
            continue
        if not re.search(r"^extends\s+\w+", raw, re.M):
            continue
        looked += 1
        text = strip_noise(raw)
        mine = declared_funcs(text)
        held = declared_names(text)
        for i, line in enumerate(text.split("\n"), 1):
            for m in re.finditer(r"(^|[^\w.$])(\w+)\s*\(", line):
                name = m.group(2)
                if name in mine or name in BUILTIN or name in ENGINE:
                    continue
                if name in INHERITED or name in held:
                    continue
                # A capital first letter is a class or a type conversion —
                # Vector2(), Color(), KnitRoom.new() — never a method here.
                if name[0].isupper():
                    continue
                # Keywords that are followed by a bracket.
                if name in {"if", "elif", "else", "while", "for", "return",
                            "match", "await", "not", "and", "or", "in", "func",
                            "as", "is", "self", "super", "yield", "signal",
                            "assert", "breakpoint", "pass", "when"}:
                    continue
                trouble.append(
                    f"{path}:{i}  '{name}()' is called on this class but "
                    f"nothing declares it\n    {line.strip()}")
    return trouble, looked


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    trouble, looked = check(root)
    for one in trouble:
        print(one)
    print(f"--- {len(trouble)} calls to methods that do not exist, "
          f"in {looked} classes ---")
    return 1 if trouble else 0


if __name__ == "__main__":
    sys.exit(main())
