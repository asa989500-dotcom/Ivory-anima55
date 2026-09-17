Put the Godot Android library here before building.

After Godot has installed the Android build template (Project > Install
Android Build Template), copy it from:

    android/build/libs/release/godot-lib.template_release.aar

into this folder. It is compiled against, never packaged: the engine already
carries it, and two copies in one APK will not link.

tools/build_android_plugin.sh does this copy for you.
