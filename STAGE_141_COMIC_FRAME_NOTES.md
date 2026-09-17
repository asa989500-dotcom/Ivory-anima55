# STAGE 141 — Comic Cutter Frame Lock

This stage focuses only on the comic page cutter.

## Core repair

The comic overlay is a child of `World` and is already positioned at the active
page origin. The cutter previously converted its panel geometry to screen
coordinates and then let `World` apply pan/zoom again. That double transform
made the division guide appear detached from the project frame.

The cutter now stays page-local all the way through rendering:

- panel outlines are drawn in page-local coordinates;
- closed-shape cutter guides are drawn in the same page-local coordinates;
- stroke width is converted from screen pixels to page units by the current zoom;
- the project frame is the cutter's hard visible region;
- closed-shape cuts cannot begin outside the project frame;
- closed-shape endpoints are clamped to that frame;
- pan, pinch zoom and view rotation transform the page and cutter together;
- the cutter does not own a second transform and cannot float over the canvas.

The actual comic geometry engine remains responsible for clipping a cut to the
panel it touches, so the visible guide and the resulting frame stay consistent.

## Boundary verification

Five project-frame cases were added for 320x240, 800x600, 1920x1080, 4096x4096,
and 12000x8000 pages. Each verifies that the generated frame remains inset and
inside the project and that its dimensions are derived from the project size,
not the viewport.

A focused GDScript smoke test also covers the cutter clamp and page-local
coordinate contract.
