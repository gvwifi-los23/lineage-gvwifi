#!/usr/bin/env bash
# Apply patches/<project path>/*.patch to the synced tree, in order.
#
# Idempotent: for every project, the files touched by its patches are first
# restored to the project's checked-out revision (files a patch creates are
# removed), then all of its patches are applied in sequence. Later patches may
# therefore touch the same hunks as earlier ones. Only files named in the
# patches are touched.
#
# patches-private/ holds owner-only changes (the microG Companion key
# allowlist). Their files are always restored to stock; the patches themselves
# are applied only with PRIVATE=1, so a default (public) build never carries them.
set -euo pipefail
TOP=${TOP:-$HOME/android/lineage}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PUBLIC="$ROOT/patches"
PRIVATE_DIR="$ROOT/patches-private"
PRIVATE=${PRIVATE:-0}

projects() {
    for d in "$PUBLIC" "$PRIVATE_DIR"; do
        [ -d "$d" ] && (cd "$d" && find . -name '*.patch' -printf '%h\n' | sed 's#^\./##')
    done | sort -u
}

if [ "$PRIVATE" = 1 ]; then echo "PRIVATE=1: including patches-private/"
else echo "public build: patches-private/ excluded"; fi

projects | while read -r proj; do
    repo="$TOP/$proj"
    pub=$(ls "$PUBLIC/$proj"/*.patch 2>/dev/null | sort || true)
    priv=$(ls "$PRIVATE_DIR/$proj"/*.patch 2>/dev/null | sort || true)
    series="$pub"
    [ "$PRIVATE" = 1 ] && series="$pub $priv"

    # Files touched by any patch, public or private (both sides, so new files are included).
    files=$(grep -hE '^(\+\+\+|---) [ab]/' $pub $priv | sed -E 's#^(\+\+\+|---) [ab]/##' | sort -u)

    for f in $files; do
        if git -C "$repo" cat-file -e "HEAD:$f" 2>/dev/null; then
            # Write the pristine blob directly: 'git checkout' trusts the stat
            # cache and skips same-size edits (e.g. i_rwsem -> i_mutex).
            git -C "$repo" show "HEAD:$f" > "$repo/$f"
        else
            git -C "$repo" rm -q --cached --ignore-unmatch -- "$f" >/dev/null
            rm -f "$repo/$f"
        fi
    done

    for p in $series; do
        git -C "$repo" apply "$p"
        echo "applied: $proj  $(basename "$p")"
    done
done
