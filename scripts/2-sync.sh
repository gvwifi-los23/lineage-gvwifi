#!/usr/bin/env bash
# Step 2 (WSL): download LineageOS 23.2 + the gvwifi trees. Shallow to save ~100 GB.
# Safe to re-run; repo resumes where it stopped.
set -euo pipefail
source ~/.profile

TOP=${TOP:-$HOME/android/lineage}
PROJ=$(cd "$(dirname "$0")/.." && pwd)
JOBS=${JOBS:-8}   # network jobs; more tends to trip GitHub rate limits

mkdir -p "$TOP" && cd "$TOP"

if [ ! -d .repo ]; then
    repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 \
        --git-lfs --no-clone-bundle --depth=1 -g default,-darwin
fi

mkdir -p .repo/local_manifests
cp "$PROJ/local_manifests/gvwifi.xml" .repo/local_manifests/

repo sync -c -j"$JOBS" --force-sync --no-tags --no-clone-bundle --optimized-fetch --prune

du -sh "$TOP" 2>/dev/null || true
echo "Sync done. Next: ~/gvwifi-los23/scripts/3-build.sh"
