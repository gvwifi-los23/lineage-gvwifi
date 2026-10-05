#!/usr/bin/env bash
# Build the Galaxy View HeliBoard fork (WSL) into tools/HeliBoard/out/HeliBoard.apk.
#
#   tools/HeliBoard/build.sh
#
# Upstream HeliBoard $HB_TAG plus patches/*.patch (Samsung SM-T670 stock keyboard layout,
# functional keys and colors, forward Del key, first-boot default IME metadata).
# The APK is unsigned; the ROM build signs it (android_app_import in device/samsung/gvwifi/HeliBoard).
# Toolchain (per-user, no sudo): ~/tools/jdk-17, ~/android-sdk ndk;28.0.13004108.
set -eo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HB_TAG=${HB_TAG:-v4.1}
SRC=${HB_SRC:-$HOME/heliboard}

export JAVA_HOME=${JAVA_HOME:-$HOME/tools/jdk-17}
export ANDROID_HOME=${ANDROID_HOME:-$HOME/android-sdk}
export PATH=$JAVA_HOME/bin:$PATH

[ -d "$SRC/.git" ] || git clone --depth 1 --branch "$HB_TAG" https://github.com/Helium314/HeliBoard.git "$SRC"
cd "$SRC"
git fetch -q --depth 1 origin tag "$HB_TAG" 2>/dev/null || true
# Start from the pristine tag every time (patches are the only source of changes).
git checkout -q -f "$HB_TAG"
git clean -fdq -e build -e .gradle -e local.properties -e .cxx
for p in "$HERE"/patches/*.patch; do
    git apply "$p"
    echo "applied: $(basename "$p")"
done

echo "sdk.dir=$ANDROID_HOME" > local.properties
./gradlew --no-daemon -Dorg.gradle.jvmargs=-Xmx4g :app:assembleRelease

apk=$(ls app/build/outputs/apk/release/*.apk | head -1)
[ -f "$apk" ] || { echo "!! no release APK found"; exit 1; }
mkdir -p "$HERE/out"
cp "$apk" "$HERE/out/HeliBoard.apk"
unzip -l "$HERE/out/HeliBoard.apk" | grep -E 'lib/.*\.so' || true
ls -l "$HERE/out/HeliBoard.apk"
