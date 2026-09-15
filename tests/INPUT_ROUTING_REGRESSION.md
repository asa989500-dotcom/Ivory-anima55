# Input-routing regression

The canvas must remain drawable when a floating tool panel is open.
The full-screen dismiss layer is visual-only (`MOUSE_FILTER_IGNORE`).
A press outside the panel closes the panel from `MainRoom._input()` and the
same event is allowed to continue to `CanvasView`, so the first stroke after
closing a panel is not lost.
