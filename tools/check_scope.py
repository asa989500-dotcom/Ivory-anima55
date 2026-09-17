#!/usr/bin/env python3
"""Every bare name in a plain class must resolve to something.

Why this exists
---------------
`canvas_marks.gd` shipped with this line in it:

    p._sel_center = p.screen_to_canvas(size * 0.5)

`size` is the canvas's own width and height — a property `CanvasView`
inherits from `Control`. When that code lived inside `canvas_view.gd` the bare
name was correct. Lifted into a module it means nothing, and Godot said so:
`Identifier "size" not declared in the current scope`.

Seven checkers read that file and called it clean. `check_identifiers` only
follows names beginning with an underscore, and `size` does not begin with
one. `check_references` only follows `Something.member`, and this is a bare
name. Nothing was looking at plain identifiers at all.

The reason nothing was is that in most of this project the question is
unanswerable: a class extending `Control` inherits several hundred names from
the engine, and no checker running without Godot can know them.

But it *is* answerable for a class whose ancestry ends at `RefCounted` or
`Object` — which inherits almost nothing, and which is what every module
lifted out of a big file is. Those are exactly the files where this mistake
happens, because they are the ones holding code that used to live somewhere
with a richer scope.

So: for those files only, every bare identifier must be a local, a parameter,
something the file declares, a class in this project, an autoload, or one of
the language's own globals. Anything else is reported.

The built-in list below is written by hand and is therefore incomplete by
construction. That is fine, and it is the safe direction: a missing entry
produces a false alarm that gets read and fixed in a minute, while a missing
*check* produces a broken build on somebody's tablet.

Usage:  python3 tools/check_scope.py [project_dir]
"""

import re
import sys
import pathlib

ROOTS = {"RefCounted", "Object"}

# The language's own globals: types, functions, constants and enums that are
# in scope everywhere without being declared. Only the ones this project
# actually uses — the list grows when a real one is met, never to silence a
# real fault.
BUILTIN = {
    # keywords and literals
    "var", "const", "func", "static", "return", "if", "elif", "else", "for",
    "while", "in", "and", "or", "not", "true", "false", "null", "self",
    "break", "continue", "pass", "as", "is", "match", "await", "super",
    "extends", "class_name", "class", "signal", "enum", "void", "when",
    "breakpoint", "assert", "yield", "preload", "load",
    # built-in types
    "bool", "int", "float", "String", "StringName", "NodePath", "Variant",
    "Array", "Dictionary", "Callable", "Signal", "RID", "Object",
    "RefCounted", "Resource", "Node", "Node2D", "CanvasItem", "Control",
    "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Rect2",
    "Rect2i", "Transform2D", "Transform3D", "Basis", "Quaternion", "Plane",
    "AABB", "Color", "Projection",
    "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
    "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
    "PackedVector2Array", "PackedVector3Array", "PackedColorArray",
    # engine classes used here
    "Image", "ImageTexture", "Texture2D", "AtlasTexture", "SubViewport",
    "Viewport", "Window", "Font", "FontFile", "SystemFont", "Theme",
    "StyleBox", "StyleBoxFlat", "StyleBoxEmpty", "StyleBoxTexture",
    "Button", "BaseButton", "CheckBox", "CheckButton", "Label", "LineEdit",
    "TextEdit", "RichTextLabel", "TextureRect", "ColorRect", "Panel",
    "PanelContainer", "MarginContainer", "VBoxContainer", "HBoxContainer",
    "BoxContainer", "GridContainer", "ScrollContainer", "Container",
    "HSeparator", "VSeparator", "HSlider", "VSlider", "Slider", "Range",
    "OptionButton", "PopupMenu", "FileDialog", "AcceptDialog", "CanvasLayer",
    "Timer", "Tween", "SceneTree", "MainLoop", "GDScript", "Script",
    "Shader", "ShaderMaterial", "Material", "CanvasItemMaterial",
    "InputEvent", "InputEventKey", "InputEventMouseButton",
    "InputEventMouseMotion", "InputEventScreenTouch",
    "InputEventScreenDrag", "InputEventPanGesture", "InputEventMagnifyGesture",
    "AudioStream", "AudioStreamPlayer", "AudioStreamWAV",
    "AudioStreamMP3", "AudioStreamOggVorbis", "AudioStreamPlayback",
    "Thread", "Mutex", "Semaphore", "WorkerThreadPool",
    "HTTPRequest", "HTTPClient", "MultiplayerAPI",
    "MeshInstance2D", "ArrayMesh", "SurfaceTool", "Mesh",
    "RandomNumberGenerator", "FastNoiseLite", "Noise", "Gradient",
    "HFlowContainer", "VFlowContainer", "FlowContainer", "ThemeDB",
    "ZIPPacker", "ZIPReader", "PCKPacker", "Curve", "Curve2D",
    # singletons
    "OS", "Engine", "Input", "Time", "JSON", "Marshalls", "FileAccess",
    "DirAccess", "ResourceLoader", "ResourceSaver", "ProjectSettings",
    "DisplayServer", "RenderingServer", "TextServer", "TextServerManager",
    "Performance", "Geometry2D", "IP", "ClassDB", "EditorInterface",
    "AudioServer", "InputMap", "Physics2DServer",
    # global functions
    "abs", "absf", "absi", "acos", "asin", "atan", "atan2", "bezier_derivative",
    "bezier_interpolate", "ceil", "ceilf", "ceili", "clamp", "clampf",
    "clampi", "cos", "cosh", "cubic_interpolate", "deg_to_rad", "ease",
    "error_string", "exp", "floor", "floorf", "floori", "fmod", "fposmod",
    "hash", "instance_from_id", "inverse_lerp", "is_equal_approx",
    "is_finite", "is_inf", "is_instance_id_valid", "is_instance_valid",
    "is_nan", "is_zero_approx", "lerp", "lerp_angle", "lerpf", "log",
    "max", "maxf", "maxi", "min", "minf", "mini", "move_toward", "nearest_po2",
    "pingpong", "posmod", "pow", "print", "print_rich", "printerr",
    "printraw", "prints", "printt", "push_error", "push_warning",
    "rad_to_deg", "rand_from_seed", "randf", "randf_range", "randfn",
    "randi", "randi_range", "randomize", "range", "remap", "rid_allocate_id",
    "round", "roundf", "roundi", "seed", "sign", "signf", "signi", "sin",
    "sinh", "smoothstep", "snapped", "snappedf", "snappedi", "sqrt", "step_decimals",
    "str", "str_to_var", "tan", "tanh", "type_convert", "type_string",
    "typeof", "var_to_str", "wrap", "wrapf", "wrapi", "weakref", "len",
    # constants and enum members reached bare
    "PI", "TAU", "INF", "NAN", "OK", "FAILED",
    "HORIZONTAL_ALIGNMENT_LEFT", "HORIZONTAL_ALIGNMENT_CENTER",
    "HORIZONTAL_ALIGNMENT_RIGHT", "HORIZONTAL_ALIGNMENT_FILL",
    "VERTICAL_ALIGNMENT_TOP", "VERTICAL_ALIGNMENT_CENTER",
    "VERTICAL_ALIGNMENT_BOTTOM",
    "TYPE_NIL", "TYPE_BOOL", "TYPE_INT", "TYPE_FLOAT", "TYPE_STRING",
    "TYPE_ARRAY", "TYPE_DICTIONARY", "TYPE_VECTOR2", "TYPE_COLOR",
    "TYPE_PACKED_BYTE_ARRAY", "TYPE_PACKED_STRING_ARRAY", "TYPE_OBJECT",
    "TYPE_PACKED_VECTOR2_ARRAY", "TYPE_PACKED_VECTOR3_ARRAY",
    "TYPE_PACKED_INT32_ARRAY", "TYPE_PACKED_FLOAT32_ARRAY",
    "TYPE_VECTOR2I", "TYPE_VECTOR3", "TYPE_RECT2", "TYPE_RECT2I",
    "TYPE_TRANSFORM2D", "TYPE_CALLABLE", "TYPE_STRING_NAME",
    "NOTIFICATION_PREDELETE", "NOTIFICATION_READY",
    "NOTIFICATION_WM_CLOSE_REQUEST", "NOTIFICATION_APPLICATION_PAUSED",
    "NOTIFICATION_APPLICATION_FOCUS_OUT", "NOTIFICATION_TRANSLATION_CHANGED",
    "KEY_ESCAPE", "KEY_ENTER", "KEY_SHIFT", "KEY_CTRL", "KEY_ALT",
    "MOUSE_BUTTON_LEFT", "MOUSE_BUTTON_RIGHT", "MOUSE_BUTTON_MIDDLE",
    "MOUSE_BUTTON_WHEEL_UP", "MOUSE_BUTTON_WHEEL_DOWN",
    "SIDE_LEFT", "SIDE_TOP", "SIDE_RIGHT", "SIDE_BOTTOM",
    "Error", "Side", "Corner",
}

# Annotations are not identifiers.
ANNOTATION = re.compile(r"@\w+")


def gd_files(root):
    out = []
    for folder in ("scripts", "tests"):
        base = pathlib.Path(root, folder)
        if base.exists():
            out.extend(sorted(base.rglob("*.gd")))
    return out


def strip_noise(text):
    """Comments and string bodies removed."""
    out = []
    for line in text.split("\n"):
        line = ANNOTATION.sub("", line)
        line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
        line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)
        out.append(line.split("#")[0])
    return "\n".join(out)


def func_params(text):
    """The text between the brackets of every `func`, brackets balanced."""
    out = []
    for opened in re.finditer(r"func\s*\w*\s*\(", text):
        depth = 0
        start = opened.end()
        i = start - 1
        while i < len(text):
            if text[i] in "([{":
                depth += 1
            elif text[i] in ")]}":
                depth -= 1
                if depth == 0:
                    out.append(text[start:i])
                    break
            i += 1
    return out


def split_top(params):
    """Splits on the commas that separate parameters, not the ones inside a
    default value's own brackets."""
    parts, depth, held = [], 0, ""
    for ch in params:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(held)
            held = ""
        else:
            held += ch
    parts.append(held)
    return parts


def declared_in(text):
    """Every name this file introduces: members, locals, parameters, loop
    variables, enum members and inner classes.

    Collected across the whole file rather than per function. That is weaker
    than real scoping — a local declared in one function will not be reported
    when used in another — but it is the trade that keeps this quiet enough to
    be run. What it is here to catch is a name that exists *nowhere* in the
    file, which is what a lifted module reaching for its old home looks like.
    """
    # `_` is the wildcard of a `match` and the name given to a value nobody
    # wants. It is never a reference to anything.
    found = {"_"}
    for pattern in (
        r"(?:^|\s)(?:static\s+)?func\s+(\w+)",
        r"(?:^|\s)(?:static\s+)?var\s+(\w+)",
        r"(?:^|\s)const\s+(\w+)",
        r"(?:^|\s)signal\s+(\w+)",
        r"(?:^|\s)enum\s+(\w+)",
        r"^\s*class\s+(\w+)",
        r"\bfor\s+(\w+)\s+in\b",
    ):
        found.update(re.findall(pattern, text, re.M))
    # Signal parameters, which are declarations like any other.
    for params in re.findall(r"signal\s+\w+\s*\(([^)]*)\)", text):
        for part in params.split(","):
            word = part.split(":")[0].strip()
            if re.fullmatch(r"\w+", word or ""):
                found.add(word)
    # Parameters, including those of lambdas.
    #
    # Read by counting brackets rather than by stopping at the first `)`.
    # A default value is allowed to be a call — `progress: Callable =
    # Callable()` is the ordinary way to say "no callback" — and a regex that
    # stops at the first closing bracket takes that as the end of the
    # signature. Every parameter after it then reads as undeclared, which is
    # a false alarm on correct code, and false alarms are how a checker stops
    # being read.
    for params in func_params(text):
        for part in split_top(params):
            word = part.split(":")[0].split("=")[0].strip()
            if re.fullmatch(r"\w+", word or ""):
                found.add(word)
    # Enum members.
    for body in re.findall(r"enum\s*\w*\s*\{([^}]*)\}", text, re.S):
        for part in body.split(","):
            word = part.split("=")[0].strip()
            if re.fullmatch(r"\w+", word or ""):
                found.add(word)
    return found


def base_of(text):
    found = re.search(r"^extends\s+([\w.\"/:]+)", text, re.M)
    return found.group(1) if found else "Object"


def name_of(text):
    found = re.search(r"^class_name\s+(\w+)", text, re.M)
    return found.group(1) if found else None


def autoloads(root):
    out = set()
    cfg = pathlib.Path(root, "project.godot")
    if not cfg.exists():
        return out
    inside = False
    for line in cfg.read_text(encoding="utf-8").split("\n"):
        if line.strip().startswith("["):
            inside = line.strip() == "[autoload]"
            continue
        if inside:
            found = re.match(r"^(\w+)\s*=", line.strip())
            if found:
                out.add(found.group(1))
    return out


def without_engine_inner_classes(text, project_bases):
    """The file with any inner class that extends an engine type blanked out.

    A file can be `RefCounted` at the top and still hold a `class Sheet
    extends Control` inside it — `text_render.gd` does, and that inner class
    calls `draw_string` bare, entirely correctly. Its scope is not knowable
    here, so its lines are set aside rather than guessed at.
    """
    lines = text.split("\n")
    out = []
    skipping = False
    for line in lines:
        head = re.match(r"^class\s+(\w+)(?:\s+extends\s+(\w+))?", line)
        if head:
            base = head.group(2)
            if base is None:
                # `class X:` with `extends` on the next line — read ahead.
                at = lines.index(line) + 1
                if at < len(lines):
                    found = re.match(r"^\s+extends\s+(\w+)", lines[at])
                    base = found.group(1) if found else "RefCounted"
                else:
                    base = "RefCounted"
            skipping = not plain_class("extends %s" % base, project_bases)
            out.append("")
            continue
        if skipping:
            if line.strip() != "" and not line.startswith((" ", "\t")):
                skipping = False
            else:
                out.append("")
                continue
        out.append(line)
    return "\n".join(out)


def plain_class(text, project_bases):
    """Whether this file's ancestry ends at RefCounted or Object, so that
    everything in scope is knowable from the project alone."""
    seen = set()
    base = base_of(text)
    while True:
        if base in ROOTS:
            return True
        if base in seen or base not in project_bases:
            return False
        seen.add(base)
        base = project_bases[base]


def functions_of(text):
    """`(line_number, name, [parameters], body)` for every function."""
    lines = text.split("\n")
    out = []
    at = 0
    while at < len(lines):
        head = re.match(r"^(\s*)(?:static\s+)?func\s+(\w+)\s*\(", lines[at])
        if not head:
            at += 1
            continue
        indent = len(head.group(1))
        # The signature may wrap over several lines.
        signature = lines[at]
        end = at
        while signature.count("(") > signature.count(")") and end + 1 < len(lines):
            end += 1
            signature += " " + lines[end].strip()
        params = []
        inside = signature[signature.index("(") + 1:]
        depth = 1
        collected = ""
        for ch in inside:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
                if depth == 0:
                    break
            collected += ch
        for part in re.split(r",(?![^\[\(]*[\]\)])", collected):
            word = part.split(":")[0].split("=")[0].strip()
            if re.fullmatch(r"\w+", word or ""):
                params.append(word)
        body = []
        n = end + 1
        while n < len(lines):
            line = lines[n]
            if line.strip() == "" or len(line) - len(line.lstrip()) > indent:
                body.append(line)
                n += 1
                continue
            break
        out.append((at + 1, head.group(2), params, "\n".join(body)))
        at = n
    return out


def unused_parameters(text):
    """Parameters a function never mentions.

    Exactly the rule Godot applies, and the reason it is here is that the
    lifting tool produced two of them: `fill_mask` and `premultiply` were
    handed a canvas they had no use for, and every caller then carried one
    for nothing. A leading underscore says the omission is deliberate, which
    is the convention Godot's own warning asks for.
    """
    out = []
    for (n, name, params, body) in functions_of(text):
        for word in params:
            if word.startswith("_"):
                continue
            if re.search(r"(?<![\w.])%s(?![\w])" % re.escape(word), body):
                continue
            out.append((n, name, word))
    return out


def dead_members(files, texts):
    """Private members and signals that nothing anywhere reads.

    Godot reports a private class variable that its own file never mentions,
    which after a class is split into a host and a module is wrong twenty-two
    times out of twenty-two: `_sel_center` is read thirteen times, all of them
    from `canvas_marks.gd`. Those are silenced at the declaration.

    Silencing them costs the warning its point, so the question is asked
    again here and asked properly — across every file rather than inside one.
    A member read from a lifted module is fine; a member nobody reads at all
    is dead code and is reported.
    """
    out = []
    for path in files:
        body = texts[path]
        members = re.findall(
            r"^(?:@\w+\s+)?(?:static\s+)?var\s+(_\w+)", body, re.M)
        signals = re.findall(r"^signal\s+(\w+)", body, re.M)
        for name in members:
            if len(re.findall(r"(?<![\w.])%s(?![\w])" % name, body)) > 1:
                continue
            if any(re.search(r"\.%s(?![\w])" % name, texts[other])
                   for other in files if other != path):
                continue
            out.append((path, name, "variable"))
        for name in signals:
            if re.search(r"(?<![\w.])%s\s*\.\s*emit" % name, body):
                continue
            if any(re.search(r"\.%s\s*\.\s*emit" % name, texts[other])
                   for other in files if other != path):
                continue
            out.append((path, name, "signal"))
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    files = gd_files(root)

    texts = {}
    project_bases = {}
    project_names = set()
    for path in files:
        text = strip_noise(path.read_text(encoding="utf-8"))
        texts[path] = text
        found = name_of(text)
        if found:
            project_names.add(found)
            project_bases[found] = base_of(text)

    known_globals = project_names | autoloads(root) | BUILTIN

    problems = []
    checked = 0
    for path in files:
        text = texts[path]
        if not plain_class(text, project_bases):
            continue
        checked += 1
        here = declared_in(text) | known_globals
        body = without_engine_inner_classes(text, project_bases)
        for n, line in enumerate(body.split("\n"), 1):
            for m in re.finditer(r"(?<![\w.$])([A-Za-z_]\w*)", line):
                word = m.group(1)
                # Skip a name being used as a keyword argument or a label.
                if word in here:
                    continue
                problems.append((path, n, word, line.strip()[:74]))

    # A second pass, over every file rather than only the plain ones: the
    # rule does not depend on what a class inherits.
    idle = []
    for path in files:
        for (n, name, word) in unused_parameters(texts[path]):
            idle.append((path, n, name, word))

    for (path, n, word, line) in problems:
        print("%s:%d  \"%s\" is not declared here and is not a global\n    %s"
              % (path, n, word, line))
    gone = dead_members(files, texts)
    for (path, name, kind) in gone:
        print("%s  the %s \"%s\" is read by nothing, in this file or any "
              "other" % (path, kind, name))

    for (path, n, name, word) in idle:
        print("%s:%d  \"%s\" is never used in %s() — drop it, or say the "
              "omission is deliberate by naming it \"_%s\""
              % (path, n, word, name, word))
    print("--- %d unresolved names in %d plain classes, %d unused "
          "parameters, %d dead members ---"
          % (len(problems), checked, len(idle), len(gone)))
    return 1 if (problems or idle or gone) else 0


if __name__ == "__main__":
    sys.exit(main())
