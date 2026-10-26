#!/usr/bin/env bash
# Monthly (WSL): pull the build kit's new fixes, sync LineageOS 23.2 (the month's
# security merge), and build. Runs 2-sync.sh and 3-build.sh; their options still apply.
#
#   scripts/5-monthly.sh
#
# UPSTREAM_REMOTE (default "upstream") is gvwifi-los23/lineage-gvwifi, merged into this
# fork when it has new commits. A merge conflict stops the script before anything else runs.
set -euo pipefail
source ~/.profile

TOP=${TOP:-$HOME/android/lineage}
PROJ=$(cd "$(dirname "$0")/.." && pwd)
UPSTREAM_REMOTE=${UPSTREAM_REMOTE:-upstream}
LAST="$HOME/gvwifi-dist/.last-security-patch"

# 1. The kit itself: this fork, then the original maintainer's new work.
cd "$PROJ"
git pull --ff-only
if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    git fetch -q "$UPSTREAM_REMOTE"
    new=$(git log --oneline "HEAD..$UPSTREAM_REMOTE/main")
    if [ -n "$new" ]; then
        echo "New upstream kit commits:"; echo "$new"
        git merge --no-edit "$UPSTREAM_REMOTE/main" || { echo "!! merge conflict: resolve it, then re-run"; exit 1; }
    fi
fi

# 2. Report (don't follow) new commits on the pinned gvwifi trees: a bump needs review.
tr '\n' ' ' < local_manifests/gvwifi.xml | grep -oE 'name="gvwifi/[^"]+"[^/]*revision="[0-9a-f]{40}"' |
while read -r line; do
    name=$(echo "$line" | sed -E 's/name="([^"]+)".*/\1/')
    pin=$(echo "$line" | sed -E 's/.*revision="([0-9a-f]+)".*/\1/')
    head=$(git ls-remote "https://github.com/$name" refs/heads/lineage-23.2 | cut -c1-40) || true
    [ -n "$head" ] || { echo "note: could not reach $name"; continue; }
    [ "$head" = "$pin" ] || echo "note: $name has new commits (pinned ${pin:0:8}, head ${head:0:8})"
done

# 3. Put patched files back to stock so repo sync can move the projects.
#    Same restore as apply-patches.sh; it re-applies everything during the build.
if [ -d "$TOP/.repo" ]; then
    (cd "$PROJ/patches" && find . -name '*.patch' -printf '%h\n' | sed 's#^\./##' | sort -u) |
    while read -r proj; do
        repo="$TOP/$proj"
        [ -d "$repo" ] || continue
        for f in $(grep -hE '^(\+\+\+|---) [ab]/' "$PROJ/patches/$proj"/*.patch | sed -E 's#^(\+\+\+|---) [ab]/##' | sort -u); do
            if git -C "$repo" cat-file -e "HEAD:$f" 2>/dev/null; then
                git -C "$repo" show "HEAD:$f" > "$repo/$f"
            else
                rm -f "$repo/$f"
            fi
        done
    done
fi

# 4. Sync, then rebuild the keyboard only if its patches changed since the last APK.
"$PROJ/scripts/2-sync.sh"
HB="$PROJ/tools/HeliBoard"
if [ ! -f "$HB/out/HeliBoard.apk" ] || [ -n "$(find "$HB/patches" "$HB/build.sh" -newer "$HB/out/HeliBoard.apk")" ]; then
    "$HB/build.sh"
fi

# 5. Build, then say whether this month actually moved the security patch.
"$PROJ/scripts/3-build.sh"
prop="$TOP/out/target/product/gvwifi/system/build.prop"
spl=$(grep -m1 '^ro.build.version.security_patch=' "$prop" | cut -d= -f2)
prev=$(cat "$LAST" 2>/dev/null || echo none)
echo "Security patch: $spl (last build: $prev)"
[ "$spl" = "$prev" ] && echo "!! Same as last build: LineageOS may not have merged this month's patch yet."
echo "$spl" > "$LAST"
