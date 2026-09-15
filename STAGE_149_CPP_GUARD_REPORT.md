# Stage 149 — C++ Integrity Guard + Parse/Warn Cleanup

## Fixed from the reported screenshots

1. `scripts/canvas_view_draw.gd`
   - Fixed `draw_layer_rig()` using `host` without declaring it.
   - Signature is now `draw_layer_rig(host: CanvasView)`.

2. `scripts/puppet_warp.gd`
   - Intentional cross-module private storage is explicitly marked with
     `@warning_ignore("unused_private_class_variable")` so Godot does not
     report false-positive private-member warnings.

3. `scripts/puppet_warp_build.gd` and `scripts/puppet_warp_arap.gd`
   - Static `_area()` is called explicitly as `PuppetWarp._area(...)`, removing
     the "static function called from an instance" warning.

4. `scripts/anim_player.gd`
   - Unused Character 360 runtime parameters are now explicitly named
     `_rest_a` and `_rest_b`.

5. `scripts/ui/bone_room.gd`
   - Removed the genuinely dead `_character360_controller` member.

## New C++ inspection instruments

`native/ivory/src/ivory_diagnostics.{h,cpp}` adds `IvoryDiagnostics` with five
independent checks:

- mesh integrity: vertex/triangle/neighbour/rim sizes, finite coordinates,
  valid indices, and degenerate-triangle detection;
- pose integrity: array length, NaN/Inf detection, and displacement limit;
- pin integrity: matching arrays, finite data, and valid mesh vertex indices;
- bounds integrity: detects a vertex escaping the configured canvas;
- frame watchdog: reports native solve time exceeding a configurable budget.

`health()` aggregates the five instruments into one machine-readable report.

The class is registered in `register_types.cpp`, exposed through
`scripts/native.gd`, and the Puppet Warp mesh is validated once at the native
boundary before the native solver is allowed to consume it. If the diagnostic
rejects the mesh, IVORY safely falls back to the existing GDScript solver
rather than continuing with corrupted geometry.

## Verification completed in this environment

- Project checker: **15/15 checks passed**.
- Native C++ syntax/type checker: **18/18 native sources passed**.
- New C++ diagnostic unit test: **12/12 checks passed**.

The full Godot editor/compiler was not available in this container, so the
final Godot runtime parse/build still needs to be performed on the machine
with Godot 4.7.2 and the real `godot-cpp` checkout. The existing project is
structured to build the extension through `native/ivory/SConstruct`.
