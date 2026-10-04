#!/usr/bin/env bash
# Step 3 (WSL): build the ROM zip + LineageOS Recovery, and package the
# recovery as an Odin-flashable .tar.
#
#   ./3-build.sh              full build (mka bacon)
#   ./3-build.sh recovery     recovery only (fast first test: does it boot?)
#   ./3-build.sh kernel       kernel/boot.img only
#   MODULES="a b" ./3-build.sh module   only those modules (on-device testing; clean
#                             out/ before a release build if they aren't in the ROM)
set -eo pipefail
source ~/.profile

TOP=${TOP:-$HOME/android/lineage}
TARGET=${TARGET:-recovery-and-rom}
[ -n "${1:-}" ] && TARGET=$1
# 16 threads but 24 GB WSL RAM: -j12 avoids OOM kills during metalava/R8.
JOBS=${JOBS:-12}

"$(dirname "$0")/apply-patches.sh"

# Signing. Public builds (default) sign with the owner's private release keys
# via LineageOS inline signing (vendor/lineage-priv/keys/keys.mk ->
# "release-keys"). PRIVATE=1 (owner build) stays on AOSP test-keys, so it keeps
# matching the owner's test-keys install. Keys live outside the tree.
RELEASE_KEYS=${RELEASE_KEYS:-$HOME/gvwifi-keys/release}
rm -rf "$TOP/vendor/lineage-priv"
if [ "${PRIVATE:-0}" != 1 ] && [ -f "$RELEASE_KEYS/keys.mk" ]; then
    mkdir -p "$TOP/vendor/lineage-priv/keys"
    cp "$RELEASE_KEYS"/* "$TOP/vendor/lineage-priv/keys/"
    echo "signing: release keys ($RELEASE_KEYS)"
else
    echo "signing: AOSP test-keys"
fi

cd "$TOP"
source build/envsetup.sh
export LINEAGE_BUILDTYPE=UNOFFICIAL
export WITH_GMS=false

# ccache is opt-in (CCACHE=1): the disk budget on this PC can't spare 30 GB,
# and ninja already rebuilds only what changed.
if [ "${CCACHE:-0}" = 1 ]; then
    export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$HOME/.ccache
    mkdir -p "$CCACHE_DIR"
else
    unset USE_CCACHE CCACHE_EXEC
fi

# vendor/lineage/vars/aosp_target_release says bp4a for 23.2; the device
# tree's COMMON_LUNCH_CHOICES still lists bp2a (stale), so lunch directly
# instead of breakfast (which would also try roomservice for a non-official device).
source vendor/lineage/vars/aosp_target_release
lunch "lineage_gvwifi-${aosp_target_release}-userdebug"

# envsetup.sh turns off errexit, so check m's status explicitly.
# dt.img (Exynos DTBH table) is passed to mkbootimg via BOARD_MKBOOTIMG_ARGS
# but only listed in BOOTIMAGE_EXTRA_DEPS, so request it explicitly.
case "$TARGET" in
    recovery) goals="dtimage recoveryimage" ;;
    kernel)   goals="dtimage bootimage" ;;
    module)   goals="${MODULES:?set MODULES}" ;;
    *)        goals="dtimage bacon recoveryimage" ;;
esac
# KEEP_GOING=1 builds everything that can be built, so one run surfaces
# every failing module instead of stopping at the first.
m -j"$JOBS" ${KEEP_GOING:+-k} $goals || { echo "BUILD FAILED ($goals)"; exit 1; }
[ "$TARGET" = module ] && { echo "Built: $goals"; exit 0; }

OUT=$(get_build_var PRODUCT_OUT)
DIST=$HOME/gvwifi-dist/$(date +%Y%m%d-%H%M)
mkdir -p "$DIST"

# Odin wants a ustar tar with the partition image named as on the device.
if [ -f "$OUT/recovery.img" ]; then
    tar -H ustar -C "$OUT" -cf "$DIST/lineage-recovery-gvwifi.tar" recovery.img
    cp "$OUT/recovery.img" "$DIST/"
fi
# The build hard-links every dated zip name in $OUT to the newest zip, so pick
# it by this build's own version string, not by mtime (they all tie).
ver=$(get_build_var LINEAGE_VERSION)
newest="$OUT/lineage-$ver.zip"
[ -f "$newest" ] || { echo "!! $newest not found"; exit 1; }
cp "$newest" "$DIST/" && (cd "$DIST" && sha256sum "$(basename "$newest")" > "$(basename "$newest").sha256")
# Drop the stale dated names (same inode as the new zip) so $OUT stays readable.
find "$OUT" -maxdepth 1 -name 'lineage-23.2-*-gvwifi.zip*' ! -name "lineage-$ver.zip*" -delete
cp "$OUT/boot.img" "$DIST/" 2>/dev/null || true

# Hard size limits from BoardConfig; the bootloader also truncates ramdisks >~12 MB.
for p in boot:33554432 recovery:39845888; do
    img=${p%%:*}; max=${p##*:}
    [ -f "$OUT/$img.img" ] || continue
    sz=$(stat -c %s "$OUT/$img.img")
    printf '%-9s %10d / %10d bytes\n' "$img.img" "$sz" "$max"
    [ "$sz" -le "$max" ] || echo "!! $img.img is too big for its partition"
done

echo "Artifacts: $DIST"
ls -lh "$DIST"
echo "From Windows Explorer: \\\\wsl\$\\Ubuntu-24.04${DIST//\//\\}"
