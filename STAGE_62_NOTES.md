# Stage 62 — why the B-Spline room would not open, and the twenty entries

## The one that blocked you

```
bspline_room.gd:346 @ _frame_page(): Parameter "data.tree" is null.
BSplineRoom._frame_page: Invalid access to property or key 'process_frame'
                         on a base object of type 'null instance'.
```

`_frame_page()` began with `await get_tree().process_frame`, and it was called
from the last line of `setup()`.

But look at the order in `main.gd`:

```gdscript
var room: BSplineRoom = BSplineRoom.new()
if not room.setup(view):        # <- setup runs HERE
    room.queue_free()
    return
...
_ui.add_child(room)             # <- and the room joins the tree HERE
```

`setup()` deliberately runs first, because if it fails the room is thrown away
and never added to anything. So at the moment `_frame_page()` ran, the room was
a loose object with no tree above it. `get_tree()` on a node outside the tree
returns null, and `null.process_frame` is the error. The room died on the way
in, every time.

Nothing needed to be awaited at all. A Control is *told* when it is given a
size — that is what `resized` is for. So the room waits to be told:

```gdscript
func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    resized.connect(_frame_page)
    _frame_page()

func _frame_page() -> void:
    if _framed:
        return
    ...
    _framed = true
```

It frames once, the first moment both the page and the screen have a size, and
never fights the user's own zooming afterwards.

**The same fault was waiting in the timeline.** `_float_sheet()` also awaits
`get_tree().process_frame`. It has always been called from a node that happened
to be in the tree, so it never fired — but it is one refactor away from the
same crash. It is now guarded on both sides of the wait: before, because the
tree may not be there; after, because a frame is long enough for the panel to
have been closed and freed while we were away.

## The second error

```
cel_track.gd:342 @ to_dict(): Condition "ret.is_empty()" is true. Returning: ret
```

That is Godot's own `Marshalls.raw_to_base64` refusing empty bytes. A cel with
no pixels was being handed to it on every save. A frame with nothing in it is
now written as a hole and read back as one, rather than as an error line.

## The warnings — all of them

| what it said | where | what it was |
|---|---|---|
| `"seed"` has the same name as a built-in function | `puppet_warp.gd` ×2 | `Pin.seed` → `Pin.vertex` |
| local `"scale"` shadows a property in base class `Node2D` | `puppet_warp.gd` | → `push` |
| local `"scale"` shadows a property in base class `Control` | `room360.gd` | → `stretch` |
| parameter `"at"` shadows a function at line 151 | `bspline.gd` ×2 | `add_point`/`insert_point` param → `where` |
| parameter `"stack"` never used | `anim.gd play_span()` | → `_stack` |
| parameter `"thin"` never used | `room360.gd _draw_joint()` | → `_thin` |
| Integer division. Decimal part discarded | 9 sites | now `floori(float(a) / b)` — the intent stated, not implied |

The nine division sites were all *deliberate* integer division, which is why
they had gone unfixed: the code was right and the compiler was still right to
complain, because "I meant to throw the fraction away" and "I forgot this was
an int" look identical when you write `steps / 6`. They say which one they mean
now.

## Rendering — what actually changed

Honest framing first: nothing here makes the app "a hundred times" anything,
and any change that claimed to would be worth distrusting. What is here is
real and measurable.

**The good news is that the heavy lifting was already right.** `perf.gd`
measures real frame times and moves between three tiers; `Engine.max_fps` drops
to 8–12 while nothing is happening; `PaintSurface.flush()` returns immediately
when no tile is dirty; long strokes fold back into memory so the per-frame
redraw cannot grow without bound. That is the architecture that keeps a tablet
cool, and it did not need replacing.

**What was wasteful** was two panels sitting in the engine's process list for
the entire life of the app, waking on every single frame to compare two
numbers — numbers that are only ever different during the third of a second
after a finger goes down. The layers panel and the timeline now switch
themselves on when a press begins and off the moment it resolves. On an idle
screen that is two fewer nodes ticking, forever.

That is a small win stated accurately, rather than a large one stated
inaccurately. If the app still feels hot on your tablet after this, the place
to look is the tile wake budget and the mipmap tier in `perf.gd` — tell me what
it feels like and I will take that apart next.

## Files touched

`bspline_room.gd`, `cel_track.gd`, `puppet_warp.gd`, `room360.gd`, `anim.gd`,
`character360.gd`, `bspline.gd`, `layers_panel.gd`, `timeline_panel.gd`

## The same caveat as last time

No Godot binary and no network here, so this is static analysis of the source,
not a compile. It is reliable for exactly these classes of fault. Open the
project, check the error counter, and try the compass → B-Spline door first.
