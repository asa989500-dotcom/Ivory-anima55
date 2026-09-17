# Stage 165 — Build Validation

## Validation performed

### Native unit/regression tests

The following passed with C++17 and strict warnings (`-Wall -Wextra -Wpedantic -Werror` for the new RigCore/Animation modules):

- `test_rigcore`: passed
- `test_rigcore_pole`: **6 checks, 0 failures**
- `test_animation`: **6 checks, 0 failures**
- `test_character360_ultra`: **70 checks, 0 failures**
- `test_smartbone`: **2003 checks, 0 failures**
- `test_deform`: **427 checks, 0 failures**
- `test_diagnostics`: **12 checks, 0 failures**
- Existing suite also passed through `test_rig360` (110 checks), plus comic/store/lang/brush/blend/pose/arbiter/field/spline/depth.

## Defects found and fixed during this validation

1. `std::clamp(double, int, int)` in `ivory_rigcore.cpp` prevented strict compilation. Bounds are now explicit doubles.
2. Two unused variables produced warnings in `fk()` and `two_bone()` and were removed.
3. Angle shortest-path sampling had an ambiguous `-pi/+pi` boundary. The canonicalization now maps the wrap boundary consistently to `+pi`; the animation regression test passes.
4. `tools/run_native_tests.sh` now includes `test_rigcore`, `test_rigcore_pole`, and `test_animation`, so these regressions are not omitted from the normal suite.

## Full Godot/GDExtension build status

A complete GoZen/Godot native build was attempted with `tools/build_native.sh linux`.

It could not start because the supplied environment does not contain `scons`, and network access is unavailable here, so installing SCons or fetching the native submodules is impossible in this environment.

The build script itself therefore correctly fails with:

`!! scons is not installed. pip install scons`

This is an environment/toolchain limitation, **not evidence of a successful full Godot/GDExtension link**. The ZIP intentionally does not claim otherwise.

## Required external final build

On a development machine with SCons and the required submodules/toolchain:

```bash
chmod +x tools/build_native.sh tools/run_native_tests.sh
./tools/build_native.sh linux
./tools/run_native_tests.sh
```

For Android:

```bash
export ANDROID_NDK_ROOT=/path/to/android-ndk
./tools/build_native.sh android release arm64
./tools/run_native_tests.sh
```
