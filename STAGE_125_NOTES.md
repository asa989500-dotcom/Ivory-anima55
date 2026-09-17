# IVORY Stage 125 — the error, all thirteen warnings, and why they got through

## The error

**`render()` is a coroutine, so it must be called with "await".**

`KnitSettings.render` waits two frames for a `SubViewport` to draw, which makes
it a coroutine. Called without `await` it hands back the coroutine object
itself rather than an `Image`, and GDScript rejects that outright.

Awaiting it makes `_export` a coroutine too, and `_to_animation` with it — so
the two buttons that call them are awaited as well. Fixed at all three levels;
fixing only the innermost would have moved the same error one frame outward.

## The thirteen warnings

**Integer division ×6.** `bits / 8` and `data_len / block` in `audio_bank.gd`,
`raw.size() / block` in `audio_mix.gd` and `lip_sync.gd`, `index / 3` in
`comic_bubble.gd`. Whole division was meant in every one, so the fix is to say
so where the compiler can see it: divide as floats and floor. `bits / 8`
happened three times in `audio_bank.gd`, so it became `_bytes_per()`, which
also gives the reason a home.

**`load` ×3 and `seed` ×1 shadow built-in functions**, in `knit_yarn.gd`. Not
silenced — renamed to `borne` and `mark`. The warning is right: while a
variable called `load` is in scope, `load()` cannot be called at all. It
compiles, and it quietly takes a tool away.

**`bones_requested` and `bones_removed` declared but never used.** Both are
declared in `layers_panel.gd` and were only ever emitted from
`layer_rig_row.gd`. A signal belongs to the class that declares it; one raised
only from elsewhere cannot be found by reading the file that owns it. The panel
now has `ask_for_bones()` and `ask_to_remove_bones()`, two lines each, and it
is the only thing that can raise them. I swept the project for the same shape
and found one more — `animation_layer_requested` — which is fixed the same way.

**A local `row` shadowing a function at line 19.** `timeline_audio.gd`'s own
entry point is `row()`, and I had used `row` for a local `HBoxContainer` inside
it. Renamed to `buttons`. Mine, from stage 121.

## Why all eleven checkers passed

This is the part worth your attention, and it is the second time in two
stages.

The checkers were built one at a time, each for a specific mistake that had
already broken a build. None of them looked at what the *compiler* warns
about — so a whole category was invisible: code that parses, runs, and does not
mean what it looks like.

**`tools/check_warnings.py`** covers the four kinds above:

- integer division between two whole numbers
- a variable or parameter named after a global function
- a local shadowing a function in the same class
- a signal declared in one class and emitted only from another

Each rule is deliberately narrow. The shadowing rule looks only at `var`
declarations *inside a function body* — a member of an inner class may share a
name with an outer method without shadowing anything, and complaining about
that would be complaining about correct code. The division rule leaves anything
ambiguous alone: `size.x / n` is untouched because the member could be a float.

Both were tested by writing a file that breaks all three rules and confirming
it reports all three, then deleting it.

`check_all.py` now runs twelve checks.

## Also

`layers_panel.gd` went over its ceiling while gaining the three emitters, so
the folder settings sheet moved to `scripts/ui/layer_group_row.gd` — the same
seam `LayerRigRow` already follows.

All twelve checks pass.
