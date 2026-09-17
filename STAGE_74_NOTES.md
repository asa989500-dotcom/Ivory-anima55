# Stage 74 — making and adjusting are two different acts

## The split

You were right that these are two things, and the old panel proved it by
needing a separator and a line of explanation to hold them together.

Everything a settings menu holds is about a thing that **already exists** —
its language, its storage, its export, its name. Making a project is the one
act with no subject yet. It was sitting in the same list as *Storage* and
*App information*, which is why it had to be pointed at.

Split apart, neither list needs explaining:

**The plus** — your icon — holds three lines, and every line makes a project:
Drawing, Animation, Comic. Its panel is 268 wide and 250 tall, because **a
panel with three choices should not be the size of a panel with twelve.** The
width is set explicitly for that reason rather than left at the default.

**The gear** is settings, all the way down. With nothing open: Language,
Storage, App information. With a project open: that project's own settings,
exactly as before.

The plus sits **before** the gear, because it is what an empty workspace is
for and what a full one is used for most often. And it is deliberately **not**
gated on having a project open — a button for making the first project must
work when there is no project.

## The thing that would have broken quietly

`_back` always returned to the gear's menu. For a long time that was safe:
there was only one menu to return to.

After the split it would have stranded you — reach *New drawing* from the plus,
press Back, and land in a list you never opened, hunting for a way back to one
you did. That is worse than having no Back at all, and it is exactly the kind
of fault a split like this leaves behind.

`_back` now takes where to return to, and the project-making pages return to
the plus. Every other page keeps the old behaviour by default, so nothing else
changed.

## Checked rather than assumed

Every page id that anything asks for — `new`, `animation_new`, `comic`,
`language`, `storage`, `information`, `export`, `share`, `animation` — is
routed, plus the new `make`. No id can now be requested that lands nowhere.

## Files touched

`settings_panels.gd` (`make_menu`, a shorter `workspace_menu`, `_back` takes a
destination) · `main.gd` (the plus button, its dispatch, its page route) ·
`assets/icons/add_project.png`

Static analysis clean throughout.

---

## What is still open, unchanged from last stage

Strengthening the two rooms further · the animation layer for B-Spline bones ·
faster layer adding · the brushes.

Each is a stage rather than a paragraph. Tell me which one and I will take it
properly — the pattern that has been working is one thing at a time, looked at
closely, with the maths tested where testing is possible.
