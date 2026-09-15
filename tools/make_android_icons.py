#!/usr/bin/env python3
"""Builds the Android launcher icons from `icon.png`.

Why this exists
---------------
Android does not take one square picture any more. A launcher wants three
things and will invent bad answers for the two it is not given:

  main_192x192            the plain icon, for older launchers
  adaptive_foreground     the artwork, on transparency, inside the safe circle
  adaptive_background     what shows behind it while the launcher masks,
                          rotates and parallaxes the foreground

Hand the same square to all three and every round-masked launcher crops the
artwork's corners off. So the foreground is built by lifting the artwork off
its flat backdrop and shrinking it into the safe zone — the middle 66% that
survives every mask shape Android ships.

The monochrome layer is for Android 13 themed icons: one silhouette, tinted
by the system to the user's wallpaper palette.

Usage:  python3 tools/make_android_icons.py [project_dir]
Output: android/icons/*.png  (referenced from export_presets.cfg)
"""

import pathlib
import sys

from PIL import Image, ImageFilter

# The share of the 432 px canvas the artwork may occupy. Android's own
# guidance is 66%; a little under it leaves room for the parallax shift a
# launcher applies when the user scrolls the home screen.
SAFE = 0.62

# How far a pixel may sit from the flat backdrop colour and still count as
# backdrop. The icon is flat vector art, so this can be tight.
BACKDROP_TOLERANCE = 26


def flatten_backdrop(src):
    """The artwork on transparency, with the flat backdrop removed.

    Takes the corner pixel as the backdrop colour rather than assuming one,
    so re-running this after the icon is redrawn keeps working.
    """
    src = src.convert("RGBA")
    w, h = src.size
    back = src.getpixel((2, 2))[:3]
    pixels = src.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            near = (
                abs(r - back[0]) + abs(g - back[1]) + abs(b - back[2])
            )
            if near <= BACKDROP_TOLERANCE:
                pixels[x, y] = (r, g, b, 0)
    return src, back


def artwork_box(img):
    """The bounding box of everything that is not transparent."""
    box = img.getbbox()
    if box is None:
        return (0, 0, img.size[0], img.size[1])
    return box


def fit_into(art, canvas_size, share):
    """The artwork centred on a transparent canvas, at `share` of its width."""
    box = artwork_box(art)
    cut = art.crop(box)
    room = int(canvas_size * share)
    scale = min(room / cut.size[0], room / cut.size[1])
    size = (max(int(cut.size[0] * scale), 1), max(int(cut.size[1] * scale), 1))
    cut = cut.resize(size, Image.LANCZOS)
    out = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    out.paste(
        cut,
        ((canvas_size - size[0]) // 2, (canvas_size - size[1]) // 2),
        cut,
    )
    return out


def monochrome_of(fore):
    """A single-colour silhouette, softened so thin details survive tinting."""
    alpha = fore.getchannel("A").filter(ImageFilter.MaxFilter(3))
    out = Image.new("RGBA", fore.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    white = Image.new("RGBA", fore.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    return white


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    source = root / "icon.png"
    if not source.exists():
        print("no icon.png at %s" % source)
        return 1

    out_dir = root / "android" / "icons"
    out_dir.mkdir(parents=True, exist_ok=True)

    src = Image.open(source)
    art, back = flatten_backdrop(src)

    # 1. The plain launcher icon: the picture as drawn, square.
    src.convert("RGB").resize((192, 192), Image.LANCZOS).save(
        out_dir / "launcher_192.png"
    )

    # 2. The adaptive foreground: artwork only, inside the safe zone.
    fore = fit_into(art, 432, SAFE)
    fore.save(out_dir / "adaptive_foreground_432.png")

    # 3. The adaptive background: the backdrop colour the artwork was lifted
    #    from, so the two together read as the icon the user already knows.
    Image.new("RGB", (432, 432), back).save(
        out_dir / "adaptive_background_432.png"
    )

    # 4. The themed-icon silhouette.
    monochrome_of(fore).save(out_dir / "adaptive_monochrome_432.png")

    # 5. A 512 store icon, since it is asked for every time and takes a line.
    src.convert("RGB").resize((512, 512), Image.LANCZOS).save(
        out_dir / "store_512.png"
    )

    print("backdrop colour: #%02x%02x%02x" % back)
    for name in sorted(p.name for p in out_dir.glob("*.png")):
        print("  android/icons/%s" % name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
