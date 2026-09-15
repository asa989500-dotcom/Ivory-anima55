# Stage 177 — Native C++ Animation Workspace Buttons

## What changed

The first screen after **New Project → Animation** is now owned by a native
`IvoryAnimationWorkspacePicker : PanelContainer`.

It creates exactly two real Godot `Button` nodes in C++:

1. `Ivory` — emits `workspace_selected("ivory")`
2. `Stretchy Studio` — emits `workspace_selected("stretchy")`

They are stacked vertically with large touch targets. There is no
`ScrollContainer`, list widget, hidden third row, or GDScript-created workspace
button on this screen.

GDScript is only the bridge that mounts the native panel and consumes its
selection signal. The actual panel and buttons are C++.

## Important runtime requirement

The screenshot supplied for this stage shows the existing runtime reporting
that the **native animation launcher is not available**. The project checkout
contains the C++ source, but it does not contain a built `libivory` GDExtension
or a vendored `godot-cpp` checkout. Therefore this environment cannot produce
an Android-native binary here.

This ZIP deliberately does **not** fake the C++ result with GDScript. To see
the two native buttons in the Android build, compile the `native/ivory`
extension for the target Android ABI and place the resulting library at the
paths declared by `ivory.gdextension` (then enable that extension in the
shipping build). Once `IvoryAnimationWorkspacePicker` is registered by that
library, the Animation entry point instantiates it directly.

## Validation

- Native picker static guard: PASS
- Exactly two native `Button` constructions: PASS
- No `ScrollContainer` in native picker: PASS
- Native picker registration: PASS
- Native bridge: PASS
- Animation entry point mounts native picker: PASS
- Indentation: PASS
- GDScript redeclaration check: PASS
- Lambda capture check: PASS
- Return check: PASS
- Continuation check: PASS
- Reference check: PASS
- Native registration check: PASS (36 classes, 0 registration problems)
- Identifier check: PASS
- Type-inference check: PASS

The repository's broad native compile checker still cannot compile three
pre-existing files in this environment because the checkout has no real
`godot-cpp` headers; that limitation is independent of the new picker.
