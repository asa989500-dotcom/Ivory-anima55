# Stage 89f — the workspace bar, and the room you could not leave

## 1 & 2. One button in the workspace, none inside a project

The workspace bar had a plus and a gear side by side. Two marks, and the only
way to know which one held *Language* was to have opened both.

- The gear is gone from the workspace. Its three entries — Language, Storage,
  App information — now sit under a rule at the bottom of the plus panel, with
  the three ways of making a project above them.
- The old `workspace_menu` is **deleted**, not merely unused. `menu()` routes
  there when nothing is open, and every workspace settings page's Back control
  lands on it — so leaving a second list behind would have meant Back returning
  the user to a list they had never seen.
- Inside a project the plus is hidden outright. It makes projects, and a
  project is not something you make from inside another one; it was an act with
  no subject sitting in a bar otherwise entirely about the drawing in front of
  you.
- The bar is a container, so one visible child shrinks it to one button — after
  `reset_size()`, which it now gets.

## 3. The room you could not leave

**The exit button was on screen the whole time, one full screen width to the
right of the screen.**

```gdscript
leave.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
leave.position = Vector2(size.x - UiKit.s(118.0), UiKit.s(14.0))
```

With the anchor on the right, `position` is an offset *from the right edge*. So
a button meant to sit 118 px in from the right corner was placed at
`width + width − 118` — entirely off the display. There is a comment above
those two lines saying the way out must never need looking for. Every word of
it was true and the control it described was not visible.

Anchored top-left now, which makes `position` mean the distance from the left
edge that the arithmetic already assumed. It is also placed again in `_ready`,
because `size` is nothing until the room has been laid out once.

### And the hardware Back button

It quit the app. Unconditionally, from anywhere:

```gdscript
if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
    get_tree().quit()
```

So a user trapped in a full-screen room who reached for the system's way out
**closed the whole application**. That is the worst possible reading of that
gesture on a phone.

`Main._step_back` now peels one layer at a time, innermost first — the order
the user went in:

1. a room (B-Spline, 360) → leave it
2. an open panel → close it
3. focused on a project → leave focus
4. nothing left → park and quit

`config/quit_on_go_back=false` is set in `project.godot`, or Godot quits on its
own before any of that runs. `_park()` still runs on the quit path, so nothing
is lost. The room's own handler was removed rather than added to: the
notification reaches every node, so two handlers would close the room and then
act on the same press again. Escape still works there for desktop testing.

## 4. Apply "never works"

Three separate silent `return`s — an empty mesh, no view, a layer that could no
longer be found. The button did nothing, with nothing on screen to say why or
even that anything had been tried.

"It never works" is the only conclusion available to someone standing in front
of that, and it is a fair one.

Each is now a sentence naming its own cause, e.g. *"There is no artwork here to
put down. Draw on this layer first."* — the mesh is built from the ink itself,
so an empty one means there was nothing under the rig to carry.

**This is diagnosis, not a cure.** If Apply still refuses, it will now tell you
which of the three it is, and that names the real bug precisely.

---

## What I have NOT done — and why I stopped

You asked for five things. I have done three and a half, and I am stopping
rather than guessing at the rest, because last stage I shipped a guard that
broke the whole build by giving up in the wrong way. Half-doing these carries
exactly that risk again.

**The timeline being slow.** Not touched. Making it "1000% faster" means finding
what it actually spends its time on, and the honest tool for that is Godot's
profiler running on your tablet — not me reading 3,000 lines and picking a
suspect. Open the timeline, let it be slow, then send me the **Profiler** tab
sorted by Self time. The top five lines will tell us more than a week of my
guessing.

**Bones not testable in Move mode.** There is a fifth mode button, **Pose**
(*تحريك العظام*), which is where bones swing — Move is for the curve's points
and refuses to touch bones on purpose. If Pose is on your bar and swinging a
joint does nothing, that is a real bug and a different one; if the button is not
there at all, that is a third. Tell me which and I will fix that one.

**Two joined bone points showing as two.** Real, and I believe you. I did not
open it because merging joints touches the bind that every pose is computed
from, and a wrong change there bends the figure silently rather than erroring.
It is the first thing I will do next.
