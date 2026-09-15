#!/usr/bin/env python3
"""Stops a file growing past what it is already allowed.

Why this exists
---------------
Three files reached three thousand lines, and the reason they did is that no
single change ever made one of them noticeably worse. Every build added fifty
lines to something that was already too long, and fifty lines is never worth
stopping for.

So the sizes are written down. A file may shrink freely, and it may not grow
past its entry here. New files get `LIMIT`, which is about the length at which
a file stops being readable in one sitting.

This does not demand that the big files be split. It demands that they stop
getting bigger, and that when one is split the ledger comes down with it — the
number below becomes the new ceiling, and there is no way back up.

Usage:  python3 tools/check_size.py [project_dir]
        python3 tools/check_size.py [project_dir] --write   (re-record after
                                                             a split)
"""

import sys
import pathlib

# What a file written from today is allowed to be.
LIMIT = 1200

# The sum of every long file's excess over LIMIT, as recorded. This is the
# number that is actually meant to come down.
#
# The per-file ceilings are a freeze and the freeze is not quite the right
# rule on its own: a file can legitimately gain a feature. So a ceiling may be
# re-recorded with `--write`, and `--write` refuses when the total debt has
# gone up. Growth is allowed, and it has to be paid for out of another file.
# That is the discipline the three-thousand-line files never had — every
# change that made one worse was small enough not to argue with.
TOTAL_DEBT = 5889

# Room to work in.
#
# Recorded ceilings sat exactly on the current line counts, which made every
# one-line addition to a long file a failed build. That is too tight to
# survive contact: a check that fails on a comment being added is a check that
# gets commented out, and then it is not there for the change that matters.
#
# So there is an allowance. A long file may drift a little either way; what
# may not happen is a file jumping past its record by more than this, or the
# project's total debt climbing past its record by more than this. Both are
# the size of a small feature, which is exactly the size at which somebody
# should have to decide rather than drift.
GRACE = 40

# What the long-standing files are allowed to be, recorded when the ledger was
# introduced at stage 90. Every one of these is a debt, and the only permitted
# direction is down.
#
# Marked down at stage 109, when Character 360 was taken out: main.gd by 302,
# canvas_view.gd by 18, layer_stack.gd by 27 and tool_panels.gd by 42. A
# ledger that keeps yesterday's allowance after the code has shrunk is not a
# ledger, it is a ceiling nobody is under any pressure to reach.
#
# Stage 114 added a whole project kind and cost these two 43 lines between
# them — the canvas hands touches to the board and draws it, and main holds
# the boards and writes them. The bar itself is in `ui/knit_bar.gd` because
# the checker refused it here, which was the right call: a bar is not
# something main has to know about.
#
# Back up 27 at stage 110: main.gd carries the comic modes' way out — the one
# place every tool button arrives at, which is where leaving a mode belongs.
#
# And 25 more at stage 111, for the stored text box on the layer and the
# rendering-at-scale that goes with it. canvas_view.gd came *down* 17 on the
# same build: three hand-rolled gizmos became one shared HandleBox.
LEDGER = {
    "scripts/brush_library.gd": 1311,
    "scripts/canvas_view.gd": 3105,
    "scripts/layer_stack.gd": 1434,
    "scripts/main.gd": 2312,
    "scripts/ui/bspline_room.gd": 2080,
    "scripts/ui/timeline_panel.gd": 2707,
    "scripts/ui/tool_panels.gd": 1340,
}


def measure(root):
    out = {}
    for folder in ("scripts", "tests"):
        base = pathlib.Path(root, folder)
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.gd")):
            rel = path.relative_to(root).as_posix()
            out[rel] = len(path.read_text(encoding="utf-8").split("\n"))
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    sizes = measure(root)

    debt = sum(max(0, v - LIMIT) for v in sizes.values())

    if "--write" in sys.argv:
        if debt > TOTAL_DEBT + GRACE:
            print("refusing: the total debt would go from %d to %d."
                  % (TOTAL_DEBT, debt))
            print("A file may grow. It has to be paid for out of another one.")
            print("Lift a section out with tools/lift_module.py.")
            return 1
        over = {k: v for k, v in sorted(sizes.items()) if v > LIMIT}
        print("TOTAL_DEBT = %d" % debt)
        print("LEDGER = {")
        for name, count in over.items():
            print('    "%s": %d,' % (name, count))
        print("}")
        return 0

    problems = []
    for name, count in sorted(sizes.items()):
        allowed = LEDGER.get(name, LIMIT)
        if name in LEDGER:
            allowed += GRACE
        if count > allowed:
            if name in LEDGER:
                problems.append(
                    "%s  %d lines — %d past its recorded %d, which is more "
                    "than the %d of room a long file gets. Lift a section "
                    "out with tools/lift_module.py."
                    % (name, count, count - LEDGER[name], LEDGER[name],
                       GRACE))
            else:
                problems.append(
                    "%s  %d lines — %d over the %d a new file gets. Lift a "
                    "section out with tools/lift_module.py."
                    % (name, count, count - LIMIT, LIMIT))

    # A ledger entry for a file that has since shrunk is not a failure, but it
    # is worth saying, because the ceiling should be brought down to match.
    slack = []
    for name, allowed in sorted(LEDGER.items()):
        count = sizes.get(name)
        if count is None:
            slack.append("%s is in the ledger and no longer exists" % name)
        elif count < allowed - 120:
            slack.append("%s is now %d lines against a recorded %d — lower it"
                         % (name, count, allowed))

    if debt > TOTAL_DEBT + GRACE:
        problems.append(
            "the project's total debt is %d lines against a recorded %d. "
            "A file may grow; it has to be paid for out of another one."
            % (debt, TOTAL_DEBT))

    for line in problems:
        print(line)
    for line in slack:
        print("note: %s" % line)
    print("total debt %d lines over %d, recorded at %d"
          % (debt, LIMIT, TOTAL_DEBT))
    print("--- %d files over their limit ---" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
