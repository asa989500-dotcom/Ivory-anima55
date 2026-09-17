# Stage 67 — the turnaround is saved, and the mouth chart exists

## 1. Everything about the bones now survives a save

The hole from last stage's report is closed.

`vault.gd` was writing that a layer *was* a 360 layer and which way it faced,
and throwing away the eight drawings that made it one — so the layer came back
flagged and empty, which is worse than not coming back at all.

`Character360` now has `to_dict(dir, tag)` / `from_dict(doc, dir)`, and the
whole rig picture round-trips:

| what | where it lives now |
|---|---|
| the eight drawings | PNGs beside the layer PNGs |
| which drawing faces which way, ink box, feet, middle | the document |
| the 360 rig — joints, bars, rings, bones | `rig_360` (already saved) |
| the B-Spline curves and 2-D bones | `rig` (already saved) |
| the poses over time, both kinds | `poses` (saved since stage 63) |

**Drawings go out as files, never as text inside the document.** Eight
full-size drawings as base64 would be a several-megabyte document that must be
parsed in one gulp before anything appears on screen — and re-parsed on every
load whether the turnaround is looked at or not.

**The silhouettes are deliberately not written.** They are derived from the
drawings, and derived state in a file is state that can come to disagree with
what it was derived from. They are measured again on load.

**A missing drawing is skipped, not fatal.** Folders get moved, synced badly,
half-copied. Seven eighths of a turnaround beats an error message.

## 2. The mouth chart — `scripts/viseme.gd`

This is the heart of the lip sync, and it is in and tested. **Twenty checks,
all passing.** Read the section after this one — you asked what the keys are
and I have answered it there properly.

Also in: the multilingual tables (Latin, Arabic, kana), the *nearness* table
that says which mouths are alike, and the two smoothing rules — including the
one you described yourself, where a stretch of speech that is all one shape
gets a closure dropped into its middle so the face does not freeze mid-word.

**One thing worth saying plainly.** The enum in this file was called `Key`
when I first wrote it. `Key` is a global enum in Godot, and that exact mistake
cost you eighty-eight errors in `rig_track.gd` two stages ago. The collision
sweep I added afterwards caught it **before this shipped** rather than after.
It is now `Mouth`. The sweep earned its place.

---

# The keys, explained — and the icons you asked about

## Why nine

English has about forty-four sounds. It does not have forty-four **mouths**.

From outside a face, `p`, `b` and `m` are one closed mouth. `k`, `g` and `ng`
all happen at the back of the tongue where nothing shows. `s` and `z` differ
only in whether the throat is switched on. An audience cannot tell any of those
pairs apart, and drawing them separately costs an artist eight drawings to buy
nothing.

So lip sync has always been done on a small chart — **Preston Blair's**, drawn
for Fantasia and still what the whole industry works from. Your eight were
already almost exactly it, which is why I kept your letters.

## The nine keys

| # | key | what the mouth does | what lands here |
|---|---|---|---|
| 0 | **SHUT** | lips together | silence, and `m b p` |
| 1 | **A** | open wide, jaw down | `a ah i`(eye) |
| 2 | **E** | wide, barely open, corners back | `e ee i`(sit) `y` |
| 3 | **O** | round and open | `o oh aw` |
| 4 | **W** | pushed forward, small and round | `w oo u` |
| 5 | **T** | teeth showing, tongue at the front | `t d n s z th f v` |
| 6 | **K** | part open, nothing showing | `k g ng h` + everything unremarkable |
| 7 | **L** | tongue up behind the top teeth | `l` |
| 8 | **R** | corners drawn in, slight round | `r er` |

**Your eight, plus SHUT.** I added the closed mouth because it is not
optional: `m`, `b` and `p` *physically require* closed lips, and without it
"mama" is animated with an open mouth throughout. It is also silence, which
you need anyway. That is nine — inside the limit you set.

**SHUT does two jobs on purpose.** A mouth closed because nobody is speaking
and a mouth closed to say `m` look identical from outside. They differ in the
throat, and the throat is not on camera.

**The one compromise, named rather than hidden:** `f` and `v` are made with
the lower lip under the top teeth, which *is* visible, and Preston Blair gives
it its own drawing. I send it to `T`, which also shows the top teeth. On a wide
shot it is invisible. On a close-up of a face saying "very", you will see it.
Adding a tenth is one row in the file and one drawing from you — say the word.

## Your rule about repeated letters

You said: *if all a word's letters are alike, the app should close the mouth by
itself.* That is exactly right and it is in, as `settle()`.

A stretch of speech that is all one shape freezes the face, and a frozen face
mid-word reads as a **dropped frame**, not as talking. Real mouths do not do it
either — between two identical shapes the jaw always resets through a small
closure, so quick that nobody notices it happening and everybody notices it
missing. So a held shape gets a closure dropped in at the middle of the run,
where a jaw would naturally come back through — never at the ends, which would
only lengthen the neighbouring hold.

The companion rule, `denoise()`, does the opposite: it removes a mouth shape
that lasts one frame between two frames of something else, because at 24fps
that reads as noise on the face. **Except a one-frame SHUT**, which is a `p` or
a `b` and is genuinely that short — removing those is how lip sync loses its
consonants and starts to look like chewing.

## The other languages

- **Arabic** — the long vowels carry the work, since short vowels are marks
  and usually unwritten: ا→A, و→W, ي→E. ب and م close. The emphatics
  ص ض ط ظ are made further back than their plain twins and look identical
  from outside, so they share mouths. The marks are mapped too, for text that
  carries them.
- **Japanese** — the tidiest of the three, because kana are syllables and each
  one *already is* a mouth: the vowel it ends on decides the shape. Only ま行
  and ん close.
- **Latin** — serves English, Spanish, German and French. Accented vowels map
  to their plain mouths, because an accent changes the sound and not the shape.

Verified: every English letter, every Arabic letter and every basic kana maps
to a real key, and all nine keys are reachable.

## Do the keys need icons? — **Yes, and this is the one place I need you**

They need **nine mouth drawings**, and they cannot be generic icons: they are
*your character's* mouth, drawn by you in your line, or the lip sync will look
like a different artist drew the face. This is exactly how Moho, Toon Boom and
every other package works — the app supplies the timing, the artist supplies
the mouths.

What I would ask for:

- **Nine drawings**, one per key above, in the order in the table.
- **The same size and registration** — same canvas, mouth in the same place
  in each. The app aligns them by the layer, so a mouth that wanders between
  drawings will wander on the face.
- **Named for the key** — `shut`, `a`, `e`, `o`, `w`, `t`, `k`, `l`, `r` — so
  they can be read into a switch folder in order without you sorting them.

They go into a **switch folder** (stage 63), which is precisely what that
feature was built for: one folder, nine layers, one showing at a time. The
lip-sync pass then writes one swap key per frame. Nothing new is needed to hold
them.

If you would rather I draw a set of nine *placeholder* mouths so the machinery
can be tested before your art exists, I can do that — plain shapes, clearly
temporary, replaced the moment you have yours.

---

# What is still not done, plainly

**The canvas pose path.** I looked at it properly this time and it is a real
piece of architecture, not a hook. Layers are drawn as a grid of tiled
`Sprite2D`s, and the B-Spline room deforms by baking through a `SubViewport`
and stamping the result — far too heavy for sixty frames a second. Making poses
live on the canvas means giving a rigged layer a `MeshInstance2D` that draws
the layer's art through the rig's own vertices, and hiding the tiles while it
is posed. That is a stage of its own, and it also unblocks **onion skin showing
poses**, which cannot work before it.

**The audio half of lip sync.** Loading a file, reading the waveform, and
turning sound into the run of mouths this file already knows how to smooth.
The chart is the part that had to be right first; the analysis writes into it.

**The sync circle**, and **stick** for eyes and mouths on a turning head.

I did the two you put first, and the piece of the third that could be verified
without a screen. Tell me whether the canvas path or the audio comes next.

## Files touched

new `viseme.gd` · `character360.gd` (to_dict / from_dict) · `vault.gd`
(character written and read)

Static analysis clean: use-before-declaration 0, brackets balanced, no
duplicate functions, no unused parameters, no shadowing, **no global-name
collisions** — including the one caught in this stage's own new file.
