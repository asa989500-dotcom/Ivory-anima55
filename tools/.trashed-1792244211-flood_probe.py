#!/usr/bin/env python3
"""A faithful port of `FloodFill.run` used to settle one question offline.

This is not part of the app. It exists because the fill tool cannot be run
here — there is no Godot in this container — and a claim about whether it
fills or not should be demonstrated rather than asserted.

Run it with `--fixed` to use the corrected coarse map, and without to use the
one that shipped.
"""

import sys

TOL = 56
CORE_ALPHA = 128
COARSE_BRIDGES = [0, 1, 2, 3]


def same(px, seed, tol=TOL):
    if abs(px[3] - seed[3]) > tol:
        return False
    if px[3] < 8 and seed[3] < 8:
        return True
    return (abs(px[0] - seed[0]) <= tol and abs(px[1] - seed[1]) <= tol
            and abs(px[2] - seed[2]) <= tol)


def flood(blocked, w, h, sx, sy):
    """Gives up (None) the moment the colour reaches the window edge."""
    mask = bytearray(w * h)
    stack = [sy * w + sx]
    while stack:
        idx = stack.pop()
        if mask[idx]:
            continue
        y, x = divmod(idx, w)
        if y == 0 or y == h - 1:
            return None
        xl = x
        while xl > 0 and not mask[y * w + xl - 1] and not blocked[y * w + xl - 1]:
            xl -= 1
        xr = x
        while xr < w - 1 and not mask[y * w + xr + 1] and not blocked[y * w + xr + 1]:
            xr += 1
        if xl == 0 or xr == w - 1:
            return None
        above = below = False
        for i in range(xl, xr + 1):
            mask[y * w + i] = 1
            up = (y - 1) * w + i
            ok_up = not mask[up] and not blocked[up]
            if ok_up and not above:
                stack.append(up)
            above = ok_up
            dn = (y + 1) * w + i
            ok_dn = not mask[dn] and not blocked[dn]
            if ok_dn and not below:
                stack.append(dn)
            below = ok_dn
    return mask


def grow(src, w, h, steps):
    cur = src
    for _ in range(steps):
        nxt = bytearray(cur)
        for y in range(h):
            row = y * w
            for x in range(w):
                i = row + x
                if cur[i]:
                    continue
                if ((x > 0 and cur[i - 1]) or (x < w - 1 and cur[i + 1])
                        or (y > 0 and cur[i - w]) or (y < h - 1 and cur[i + w])):
                    nxt[i] = 1
        cur = nxt
    return cur


def solve(blocked, w, h, sx, sy):
    cur = blocked
    grown = 0
    seed = sy * w + sx
    for bridge in COARSE_BRIDGES:
        if bridge > grown:
            cur = grow(cur, w, h, bridge - grown)
            grown = bridge
        if cur[seed]:
            continue
        mask = flood(cur, w, h, sx, sy)
        if mask is not None:
            return mask, bridge
    return None, -1


def run(pixels, w, h, sx, sy, fixed):
    """`pixels` is a flat list of (r,g,b,a). Returns (outcome, bridge, count)."""
    scale = max(2, min(12, round(max(w, h) / 200)))
    w -= w % scale
    h -= h % scale
    qw, qh = w // scale, h // scale
    seed = pixels[sy * w + sx]

    matches = bytearray(w * h)
    blocked = bytearray(qw * qh)
    for y in range(h):
        row = y * w
        qrow = (y // scale) * qw
        for x in range(w):
            i = row + x
            if same(pixels[i], seed):
                matches[i] = 1
            else:
                matches[i] = 0
                if fixed:
                    blocked[qrow + x // scale] = 1
            if not fixed:
                blocked[qrow + x // scale] = 1

    coarse, bridge = solve(blocked, qw, qh, sx // scale, sy // scale)
    if coarse is None:
        return "open", -1, 0

    allowed = grow(coarse, qw, qh, bridge + 2)
    fine = bytearray(w * h)
    for y in range(h):
        row = y * w
        qrow = (y // scale) * qw
        for x in range(w):
            fine[row + x] = 0 if (allowed[qrow + x // scale] and matches[row + x]) else 1
    if fine[sy * w + sx]:
        return "blocked-seed", bridge, 0

    # _flood_open: same walk without the escape test.
    mask = bytearray(w * h)
    stack = [sy * w + sx]
    while stack:
        idx = stack.pop()
        if mask[idx]:
            continue
        y, x = divmod(idx, w)
        xl = x
        while xl > 0 and not mask[y * w + xl - 1] and not fine[y * w + xl - 1]:
            xl -= 1
        xr = x
        while xr < w - 1 and not mask[y * w + xr + 1] and not fine[y * w + xr + 1]:
            xr += 1
        above = below = False
        for i in range(xl, xr + 1):
            mask[y * w + i] = 1
            if y > 0:
                up = (y - 1) * w + i
                ok_up = not mask[up] and not fine[up]
                if ok_up and not above:
                    stack.append(up)
                above = ok_up
            if y < h - 1:
                dn = (y + 1) * w + i
                ok_dn = not mask[dn] and not fine[dn]
                if ok_dn and not below:
                    stack.append(dn)
                below = ok_dn
    count = sum(mask)
    if count == 0:
        return "nothing", bridge, 0
    return "filled", bridge, count


# ------------------------------------------------------------------ scenes

def canvas(w, h):
    return [(0, 0, 0, 0)] * (w * h)


def circle(w, h, cx, cy, r, gap_degrees=0.0):
    px = canvas(w, h)
    import math
    steps = 4000
    for i in range(steps):
        deg = 360.0 * i / steps
        if deg < gap_degrees:
            continue
        a = math.radians(deg)
        for t in (-1, 0, 1):
            x = int(round(cx + (r + t) * math.cos(a)))
            y = int(round(cy + (r + t) * math.sin(a)))
            if 0 <= x < w and 0 <= y < h:
                px[y * w + x] = (16, 16, 20, 255)
    return px


def main():
    fixed = "--fixed" in sys.argv
    w = h = 400
    print("coarse map:", "corrected" if fixed else "as shipped")
    for name, gap in [("closed circle", 0.0), ("circle with a small gap", 1.2),
                      ("circle broken wide open", 40.0)]:
        px = circle(w, h, 200, 200, 120, gap)
        outcome, bridge, count = run(px, w, h, 200, 200, fixed)
        print("  %-26s -> %-13s bridge %2d  %6d px"
              % (name, outcome, bridge, count))
    outcome, bridge, count = run(canvas(w, h), w, h, 200, 200, fixed)
    print("  %-26s -> %-13s bridge %2d  %6d px"
          % ("empty canvas", outcome, bridge, count))


if __name__ == "__main__":
    main()
