# Stage 157 — Comic Cutter + Distortion C++

- Removed Free Cut from the comic UI and disabled CUT_FREE in native C++.
- Rectangle, square, circle and line remain deterministic native cutter modes.
- Kept polygon splitting in C++ and moved the cutter bounding-box calculation outside the per-panel loop.
- Added `IvoryDistort` native C++ image processor with Lean, Arch, Swell, Twist and Pinch.
- Distortion uses inverse-mapped bilinear sampling so it changes actual pixels instead of only storing UI state.
- Added optional native bridge in `Native`; when the extension is built, active floating selections update immediately from an immutable selection snapshot, avoiding cumulative degradation while dragging the amount slider.
- GDScript remains a fallback when the native extension is absent.
