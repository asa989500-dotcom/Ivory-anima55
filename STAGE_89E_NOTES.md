# Stage 89e — my bug, and the checker that would have caught it

## What was wrong

`exporters.gd:223`, in `save_sprite_sheet`:

```gdscript
static func save_sprite_sheet(p: ProjectManager.Project) -> String:
    ...
    if sheet == null:
        return null        # <- declared String
```

This was **mine**, added one stage ago with the memory guards. The check itself
was right — a sprite sheet is frames × frame size and genuinely unbounded, and
it must not be attempted blind. **The way it gave up was wrong.**

GDScript rejects it at parse time, so it did not break sprite sheets. It broke
**the whole project**: nothing compiled, in any file. That is why the symptom
landed nowhere near the cause.

You were right and I was wrong to point at a stale build. The last two errors
genuinely were already fixed — but this is a *new* one, in the file I sent, and
it is exactly the kind that a diff-and-lint pass misses because every linter I
had was looking at structure rather than types.

## The fix

`return ""`. This function hands back a *path*, and every caller reads its
answer as "somewhere, or nowhere" — `save_flat` and the frame writer above it
already fail that way. The empty string is this function's kind of nothing.

## Why it will not happen again

Every function that returns a *thing* signals failure with `null`; one that
returns a *path* signals it with `""`; one that returns a *count* signals it
with `0` or `-1`. Adding a failure path means picking the right kind of
nothing, and I picked the wrong one while adding eight of them at once.

`tools/check_returns.py` now reads every function's declared return type and
every `return` in its body, and flags the pairs that are impossible.

**Proved rather than assumed.** The bug was re-injected into the file, the
checker was run, and it reported it:

```
scripts/exporters.gd:228  returns String, but gives back null
    static func save_sprite_sheet(p: ProjectManager.Project) -> String:
    return null
--- 1 impossible returns ---   (exit 1)
```

Then the fix was restored and it reports zero. It exits non-zero on failure, so
it can gate a build.

It is deliberately narrow — only pairs that *cannot* be right, never guesses at
anything subtler. A checker that cries wolf is a checker people stop running.

## Checks now run before shipping

| | result |
|---|---|
| `check_returns.py` (new) | 0 impossible returns |
| `check_continuations.py` | 0 suspect continuations |
| `check_shadow.py` | 0 redeclarations |
| symbol resolution across all 52 scripts | 0 unresolved |

The logo from the previous stage is untouched and in place — `icon.png` is
visible in your FileSystem panel in the screenshot.
