# Stage 169 — Secondary motion from Stretchy Studio, in C++

Two additive classes, nothing else touched:

- `IvoryJigglePhysics` (`native/ivory/src/ivory_jigglephysics.{h,cpp}`) — a
  live pendulum-chain solver, carrying over the vertex vocabulary
  (`radius`/`mobility`/`delay`/`acceleration`) from Stretchy Studio's
  `src/io/live2d/cmo3/physics.js`.
- `IvoryFaceParallax` (`native/ivory/src/ivory_faceparallax.{h,cpp}`) — a
  live dome-rotation face warp with protected regions, carrying over the
  geometry from `src/io/live2d/cmo3/faceParallax.js`.

Both reference files are XML *export* emitters for Cubism Editor — static
data, no per-frame solver. Neither new class is a byte-for-byte port for
that reason; there was no runtime to port. What was ported is the authoring
vocabulary and the geometry, now evaluated live at whatever angle a touch
drag produces instead of baked at nine fixed keyframes.

## Wired in this stage

- `register_types.cpp` registers both classes, same optional pattern as
  every class before them.
- `scripts/native.gd` gets `has_jiggle_physics()` / `jiggle_physics()` and
  `has_face_parallax()` / `face_parallax()`, same pattern as `smartbone()`.
- `scripts/stretchy_studio_room.gd`: the room now holds a jiggle-physics
  handle, builds one chain from it when the existing "Enable Stretchy
  physics" checkbox is on, and steps it every frame. `dial_swing_deg()`
  exposes the result.

## Left for the next stage

`dial_swing_deg()` and `IvoryFaceParallax.compute()` are not yet read by
`CanvasView` or any bridge that moves mesh points — the same place
`native_smartbone`'s corrections sat before `_apply_pose_to_canvas` existed.
Wiring a real head/body angle in (rather than the placeholder dial angle)
and reading the output back onto the canvas mesh is bridge work that
touches files this stage did not, and was left alone on purpose.

## Validation

Both new `.cpp`/`.h` pairs were checked for balanced delimiters. `M_PI` and
`CLAMP` were avoided in favor of the project's own local-constant and
`clampd` conventions, since neither is guaranteed to exist in every
godot-cpp checkout. A full Godot/Android build could not be run in this
sandbox — no `godot-cpp` checkout and no build toolchain are present here,
same limitation noted in `STAGE_165_BUILD_VALIDATION.md`.
