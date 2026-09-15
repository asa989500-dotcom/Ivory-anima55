#!/usr/bin/env python3
"""Moves a set of whole functions out of a class and into a module.

Not a general refactoring tool and not meant to be one. It does the one
transformation that is safe to do by machine and dangerous to do by hand:

  * take named functions out of a file, unchanged, in order
  * turn each into a static function whose first parameter is the object the
    code used to be inside
  * prefix every reference to that object's own members with it
  * leave a delegating one-liner behind, so no caller anywhere changes

Then it lists every bare identifier in the result that it could not account
for, which is the part that matters: a member it failed to prefix shows up in
that list rather than in a crash on a tablet three days later.

Usage:
  python3 tools/lift_module.py <source.gd> <target.gd> <ClassName> <fn> [fn...]
"""

import re
import sys
import pathlib

# Names that are neither members nor locals: the language, the engine, and
# the project's own global classes. Anything left over after these is
# reported for a human to look at.
BUILTIN = {
    "var", "const", "func", "static", "return", "if", "elif", "else", "for",
    "while", "in", "and", "or", "not", "true", "false", "null", "self",
    "break", "continue", "pass", "as", "is", "match", "await", "super",
    "int", "float", "bool", "String", "Array", "Dictionary", "Variant",
    "Vector2", "Vector2i", "Rect2", "Rect2i", "Color", "Font", "Image",
    "Texture2D", "ImageTexture", "StyleBoxFlat", "PackedByteArray",
    "PackedInt32Array", "PackedVector2Array", "PackedFloat32Array",
    "PackedStringArray", "Control", "Button", "Node", "Node2D", "Object",
    "RefCounted", "Callable", "Signal", "Transform2D", "ThemeDB", "Time",
    "OS", "JSON", "FileAccess", "DirAccess", "Marshalls", "Engine", "Input",
    "range", "len", "min", "max", "abs", "absf", "absi", "sign", "signf",
    "clamp", "clampf", "clampi", "min", "mini", "maxi", "minf", "maxf",
    "floor", "floori", "ceil", "ceili", "round", "roundi", "sqrt", "pow",
    "sin", "cos", "tan", "atan2", "lerp", "lerpf", "deg_to_rad",
    "rad_to_deg", "fmod", "posmod", "snapped", "str", "print", "printt",
    "typeof", "is_instance_valid", "randf", "randi", "PI", "INF", "TAU",
    "HORIZONTAL_ALIGNMENT_LEFT", "HORIZONTAL_ALIGNMENT_CENTER",
    "HORIZONTAL_ALIGNMENT_RIGHT", "VERTICAL_ALIGNMENT_CENTER",
    "TYPE_DICTIONARY", "TYPE_ARRAY", "OK", "ease",
}


def top_level_members(text):
    """Everything the class declares at column zero: the names that have to
    be reached through the object once the code lives somewhere else."""
    found = set()
    for pattern in (
        r"^(?:static\s+)?func\s+(\w+)",
        r"^(?:@\w+\s+)?(?:static\s+)?var\s+(\w+)",
        r"^const\s+(\w+)",
        r"^signal\s+(\w+)",
        r"^enum\s+(\w+)",
        r"^class\s+(\w+)",
    ):
        found.update(re.findall(pattern, text, re.M))
    return found


def function_span(lines, name):
    """The line range of a function, its leading doc comments included."""
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^(?:static\s+)?func\s+%s\s*\(" % re.escape(name), line):
            start = i
            break
    if start is None:
        return None
    # Walk back over the comment block that belongs to it.
    top = start
    while top > 0 and lines[top - 1].startswith("#"):
        top -= 1
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line.strip() == "" or line.startswith((" ", "\t")):
            end += 1
            continue
        break
    # Trim trailing blank lines back to the function.
    while end > start and lines[end - 1].strip() == "":
        end -= 1
    return (top, end)


def locals_of(body):
    """Names that belong to the function itself and must not be prefixed."""
    found = set()
    found.update(re.findall(r"\bvar\s+(\w+)", body))
    found.update(re.findall(r"\bfor\s+(\w+)\s+in\b", body))
    for params in re.findall(r"func\s*\w*\s*\(([^)]*)\)", body):
        for part in params.split(","):
            word = part.split(":")[0].split("=")[0].strip()
            if word:
                found.add(word)
    # Lambda parameters.
    for params in re.findall(r"func\s*\(([^)]*)\)\s*:", body):
        for part in params.split(","):
            word = part.split(":")[0].strip()
            if word:
                found.add(word)
    return found


# Methods the class inherits from the engine rather than declaring. They are
# called bare in the source and have to be prefixed too — the lift cannot read
# Godot's own class list, so the ones this project actually calls are listed
# here. A name reached this way that is missing from the list shows up in the
# report at the end as an unaccounted bare call.
INHERITED = {
    "queue_redraw", "get_viewport", "get_viewport_rect", "get_tree",
    "call_deferred", "set_deferred", "notification", "emit_signal",
    "get_window", "get_global_mouse_position", "get_local_mouse_position",
    "accept_event", "grab_focus", "release_focus", "add_child",
    "remove_child", "get_node_or_null", "has_node", "queue_free",
    "set_process", "set_physics_process", "get_canvas_transform",
    "make_canvas_position_local", "get_index", "move_child", "is_inside_tree",
}


def lift(body, members, holder, skip):
    """Every member reference prefixed with the holder."""
    def swap(m):
        word = m.group(0)
        if word in skip:
            return word
        if word not in members and word not in INHERITED:
            return word
        return "%s.%s" % (holder, word)
    # String literals are put aside first and put back at the end.
    #
    # Without this the rewrite reaches inside quotes, and it did: a field
    # called `ai` turned `open_panel = "ai"` into `open_panel = "p.ai"`, and
    # `call_deferred("_fit_panel_to_content")` — which names a method as text
    # — became a call to a method that does not exist. Both parse perfectly
    # and fail at run time, which is the exact class of fault this whole
    # exercise is meant to stop producing.
    kept = []

    def stow(m):
        kept.append(m.group(0))
        return "\x00%d\x00" % (len(kept) - 1)

    body = re.sub(r'"(?:[^"\\]|\\.)*"' + r"|'(?:[^'\\]|\\.)*'",
                  stow, body)

    # Comments are put aside too. They were not, and the result was prose:
    # "it becomes its own p.layers, which is the whole point", "throws away
    # every p.view the model drew". Fifteen sentences across three files, all
    # of them still compiling perfectly and none of them meaning anything.
    body = "\n".join(
        stow(re.match(r".*", line)) if line.strip().startswith("#") else line
        for line in body.split("\n"))

    # `self` meant the object the code was inside, and it still has to.
    body = re.sub(r"(?<![\w.$])self(?![\w])", holder, body)
    # Not after a dot, and not immediately before a colon in a declaration.
    body = re.sub(r"(?<![\w.$])[A-Za-z_]\w*", swap, body)

    return re.sub(r"\x00(\d+)\x00", lambda m: kept[int(m.group(1))], body)


def main():
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    source = pathlib.Path(sys.argv[1])
    target = pathlib.Path(sys.argv[2])
    holder_class = sys.argv[3]
    wanted = sys.argv[4:]

    text = source.read_text(encoding="utf-8")
    members = top_level_members(text)
    lines = text.split("\n")

    moved = []
    unused_holder = set()
    spans = []
    for name in wanted:
        span = function_span(lines, name)
        if span is None:
            print("!! no function named %s in %s" % (name, source))
            return 1
        spans.append((span, name))
    spans.sort(key=lambda s: s[0][0], reverse=True)

    # The name the moved code will reach the old object through.
    #
    # It used to be `p`, always, and that produced a build that would not
    # parse: three of the moved functions already declared
    # `var p: ProjectManager.Project` and GDScript will not have a local with
    # the same name as a parameter. So the name is now chosen against what the
    # code being moved actually uses, and if every candidate is taken the lift
    # stops rather than producing something that looks right.
    taken = set(re.findall(r"[A-Za-z_]\w*", text))
    holder = ""
    for candidate in ("host", "owner_", "outer", "holder", "the_object"):
        if candidate not in taken:
            holder = candidate
            break
    if holder == "":
        print("!! every candidate holder name is already used in %s" % source)
        return 1
    print("reaching the object through `%s`" % holder)
    pieces = {}
    for (top, end), name in spans:
        block = "\n".join(lines[top:end])
        head = re.search(r"^(?:static\s+)?func\s+%s\s*\((.*?)\)\s*->\s*(.+?):"
                         % re.escape(name), block, re.M | re.S)
        params = head.group(1).strip()
        returns = head.group(2).strip()
        # The function's own name must not be prefixed, or the
        # header stops looking like a header.
        skip = locals_of(block) | {holder, name}
        lifted = lift(block, members, holder, skip)

        public = name[1:] if name.startswith("_") else name
        new_params = "%s: %s" % (holder, holder_class)
        if params:
            new_params += ", " + params
        lifted = re.sub(
            r"^(?:static\s+)?func\s+%s\s*\(.*?\)\s*->\s*.+?:"
            % re.escape(name),
            "static func %s(%s) -> %s:" % (public, new_params, returns),
            lifted, count=1, flags=re.M | re.S)
        # A function that never mentions the object does not get handed it.
        # `_premultiply` was arithmetic on an image and nothing else, and the
        # lift gave it a host parameter it had no use for — which then had to
        # be threaded through every caller for no reason at all.
        if not re.search(r"(?<![\w.])%s\." % holder, lifted):
            lifted = lifted.replace("(%s: %s, " % (holder, holder_class), "(",
                                    1)
            lifted = lifted.replace("(%s: %s)" % (holder, holder_class), "()",
                                    1)
            unused_holder.add(name)
        pieces[name] = lifted

        # What is left behind: a delegate with the same name and signature.
        bare = ", ".join(
            part.split(":")[0].split("=")[0].strip()
            for part in params.split(",") if part.strip())
        first = "" if name in unused_holder else "self"
        joiner = ", " if (first and bare) else ""
        call = "%s.%s(%s%s%s)" % (target.stem.title().replace("_", ""),
                                  public, first, joiner, bare)
        keep = "func %s(%s) -> %s:\n\t%s%s" % (
            name, params, returns,
            "" if returns == "void" else "return ", call)
        lines[top:end] = [keep]
        moved.append((name, public))

    source.write_text("\n".join(lines), encoding="utf-8")

    out = []
    for name in wanted:
        out.append(pieces[name])
    target.write_text("\n\n".join(out) + "\n", encoding="utf-8")

    # The report: anything in the moved code this could not account for.
    body = "\n".join(out)
    known = set(members) | BUILTIN | {holder}
    unknown = {}
    for n, line in enumerate(body.split("\n"), 1):
        code = re.sub(r'"[^"]*"', "", line).split("#")[0]
        for m in re.finditer(r"(?<![\w.$])([A-Za-z_]\w*)", code):
            word = m.group(1)
            if word in known or word in locals_of(body):
                continue
            unknown.setdefault(word, []).append(n)
    print("moved %d functions into %s" % (len(moved), target))
    if unknown:
        print("names to check by eye (globals are fine, members are not):")
        for word in sorted(unknown):
            print("   %-28s lines %s" % (word, unknown[word][:6]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
