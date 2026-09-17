# Stage 89d — the logo, and a note about the errors

## The errors in the screenshot

**All three were already fixed in stage 89c**, the file sent just before this
one. The screenshot shows the earlier build — its debugger timestamps
(`0:00:06:670`, `0:00:07:018`) are identical to the previous screenshot, and the
error is on the same line of the same file.

Verified in the source being shipped here:

| reported | in this build |
|---|---|
| `LIGHT_NAMES` not found | the name does not appear anywhere in the project |
| `snapped` shadows a built-in | no `var snapped` anywhere |
| integer division | `packed.size() / 3` gone; whole-project sweep is 0 |

If Godot still shows them after opening this build, it is holding a cached
`.godot/` folder from the old one. Deleting that folder next to `project.godot`
forces a clean reimport.

One change made anyway: the comment explaining the fix used to contain the dead
name as a literal token, so searching the project for `LIGHT_NAMES` landed on
the explanation instead of coming back empty. Reworded — a search should find
nothing.

## The logo

Installed as the application icon, replacing Godot's triangle-and-dot.

- `icon.png` — 1024×1024, and `project.godot` now points at it
- `icon.svg` — removed
- `assets/logo/ivory_logo.png` — the full artwork, for an about page or splash
- `assets/logo_supplied/` — the original file exactly as sent

### How the square was chosen

An app icon is square and the artwork is 1599×899, so something had to be
decided rather than cropped by eye.

**The planet was measured, not guessed.** At the leftmost point of a circle the
`y` coordinate *is* the centre's `y` — no fitting needed — so the disc was found
from its leftmost and lowest points: **centre (745, 453), diameter 564**. The
cream dots scattered around the picture kept contaminating that measurement
until a run-length filter was added: a dot is thirty pixels across and the
planet is nearly six hundred, so requiring a run of 150 keeps the disc and drops
every dot. The result was drawn back over the artwork and checked by eye before
being used.

**The canvas was extended rather than the subject cropped.** The background is
one flat teal, so padding it is invisible — and that is what lets the planet sit
dead centre with real margin, instead of being shoved against an edge by the
shape of the original picture. The first two attempts did exactly that and
looked it.

The planet fills 72% of the frame, which leaves the rings sweeping right across
and still survives being rounded off into a circle by Android or squircled by
iOS.

### Not done

There is no `export_presets.cfg` in the project, so there is nowhere yet to set
the Android adaptive icon — the foreground/background pair Android uses to mask
the icon to the launcher's shape. Once an export preset exists, that wants
setting too, or Android will letterbox this one inside a white rounded square.
