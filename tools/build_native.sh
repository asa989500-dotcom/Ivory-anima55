#!/usr/bin/env bash
#
# Builds the GDE GoZen native library IVORY needs for MP4 export and for
# decoding MP3, M4A, FLAC and the rest.
#
# This is the step that cannot be done for you. The library is FFmpeg,
# godot-cpp, libvpx and libaom compiled for one specific ABI, and the sources
# are git submodules that have to be fetched over the network — so it needs a
# machine with the network, a compiler, and for Android, the NDK.
#
# Usage
# -----
#   tools/build_native.sh android          # arm64 release, the phone build
#   tools/build_native.sh android debug
#   tools/build_native.sh linux            # for testing on a desktop
#   tools/build_native.sh windows
#
# Before the first run
# --------------------
#   Android: install the NDK (r26 or later) and export ANDROID_NDK_ROOT.
#   All:     python3, scons, git, make, yasm/nasm, pkg-config.
#
#     pip install scons
#     sudo apt install git make yasm nasm pkg-config
#
# What comes out
# --------------
#   addons/gde_gozen/bin/libgozen.android.template_release.arm64.so
#
# and the .gdextension file already points at exactly that path, so there is
# nothing to wire up afterwards. Open the project and MP4 export works.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE="$HERE/native/gde_gozen"
BIN="$HERE/addons/gde_gozen/bin"

PLATFORM="${1:-android}"
MODE="${2:-release}"
ARCH="${3:-arm64}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!!  %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- the tools

command -v git >/dev/null || die "git is not installed."
command -v python3 >/dev/null || die "python3 is not installed."
command -v scons >/dev/null || die "scons is not installed.  pip install scons"

if [ "$PLATFORM" = "android" ]; then
	NDK="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
	[ -n "$NDK" ] || die "Set ANDROID_NDK_ROOT to your NDK folder first."
	[ -d "$NDK" ] || die "ANDROID_NDK_ROOT points at nothing: $NDK"
	say "NDK: $NDK"
fi

# ----------------------------------------------------------- the submodules
#
# Shallow, because none of the history of FFmpeg is wanted here and a full
# clone of these five is several gigabytes.

say "Fetching submodules (this is the slow part, once)"
cd "$NATIVE"
git submodule update --init --recursive --depth 1 \
	|| die "Could not fetch the submodules. This step needs the network."

for each in ffmpeg godot_cpp; do
	[ -n "$(ls -A "$NATIVE/$each" 2>/dev/null)" ] \
		|| die "$each is still empty — the submodule fetch did not work."
done

# ---------------------------------------------------------------- the build

say "Building $PLATFORM $MODE $ARCH"
cd "$NATIVE"

if [ -f build.py ]; then
	python3 build.py "$PLATFORM" "$ARCH" "$MODE" \
		|| die "The GoZen builder failed. Its own log is above."
else
	scons platform="$PLATFORM" target="template_$MODE" arch="$ARCH" \
		|| die "scons failed. Its own log is above."
fi

# --------------------------------------------------------------- the result

mkdir -p "$BIN"
FOUND=""
while IFS= read -r one; do
	FOUND="$one"
	cp -f "$one" "$BIN/"
	say "Placed $(basename "$one")"
done < <(find "$NATIVE" -name "libgozen.*${ARCH}*" -type f 2>/dev/null)

[ -n "$FOUND" ] || die "The build produced no library. Check the log above."

say "Done. Open IVORY — MP4 export and MP3 import are now live."
echo
echo "What this build gives you that a build without it does not:"
echo "  · MP4/H.264 export with AAC sound"
echo "  · MP3, M4A, AAC, FLAC, WMA, AIFF, Opus and the rest, decoded"
echo "  · hardware H.264 on Android where the device offers it"
