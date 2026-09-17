# Building the native C++ picker

The picker is part of `native/ivory/src` and is registered from
`register_types.cpp`.

Build the extension with the project's normal `godot-cpp` checkout and the
Godot target/ABI you ship. For Android arm64, the expected command pattern is:

    cd native/ivory
    scons platform=android arch=arm64 target=template_release

The generated library must be copied to the Android release path declared by
`ivory.gdextension`.

Do not replace `IvoryAnimationWorkspacePicker` with GDScript buttons if the
requirement is native C++; the GDScript file only mounts the C++ panel and
handles its `workspace_selected` signal.
