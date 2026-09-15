#!/usr/bin/env bash
#
# Builds the IVORY media plugin: MP4 export, audio decoding and gallery
# publishing, through Android's own MediaCodec.
#
# This is what replaced the FFmpeg .so. What it needs is far less than that
# did — no NDK, no submodules, no cross-compiled C — just the Android SDK and
# a JDK, which anybody exporting an APK already has.
#
# Once, before the first run
# --------------------------
#   1. Android Studio, or the command-line SDK tools, with platform 34.
#   2. JDK 17.
#   3. In Godot:  Project ▸ Install Android Build Template
#   4. export ANDROID_HOME=/path/to/Android/Sdk
#
# Then
# ----
#   tools/build_android_plugin.sh
#
# and export the APK as usual. The plugin lands in android/plugins/ where
# Godot picks it up on its own.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/android/plugin_src"
OUT="$HERE/android/plugins"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!!  %s\033[0m\n' "$*" >&2; exit 1; }

[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ] \
	|| die "Set ANDROID_HOME to your Android SDK folder first."

# The engine's own library, compiled against and never packaged.
say "Looking for the Godot Android library"
GODOT_AAR=""
for guess in \
	"$HERE/android/build/libs/release/godot-lib.template_release.aar" \
	"$HERE/android/build/libs/debug/godot-lib.template_debug.aar"; do
	if [ -f "$guess" ]; then
		GODOT_AAR="$guess"
		break
	fi
done
[ -n "$GODOT_AAR" ] \
	|| die "Not found. In Godot: Project > Install Android Build Template."
mkdir -p "$SRC/ivory_media/libs"
cp -f "$GODOT_AAR" "$SRC/ivory_media/libs/"
say "Using $(basename "$GODOT_AAR")"

say "Building the plugin"
cd "$SRC"
if [ -x ./gradlew ]; then
	./gradlew :ivory_media:assembleRelease || die "Gradle failed."
else
	command -v gradle >/dev/null || die "Install Gradle, or add a gradlew here."
	gradle :ivory_media:assembleRelease || die "Gradle failed."
fi

BUILT="$(find "$SRC/ivory_media/build/outputs/aar" -name '*release*.aar' \
	-type f 2>/dev/null | head -n 1)"
[ -n "$BUILT" ] || die "The build produced no .aar. Check the log above."

mkdir -p "$OUT"
cp -f "$BUILT" "$OUT/ivory_media.aar"
say "Placed android/plugins/ivory_media.aar"

echo
echo "Now, in the export preset, make sure:"
echo "  gradle_build/use_gradle_build = true"
echo "and export the APK as usual. MP4 runs on the phone's own encoder."
