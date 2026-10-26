#!/usr/bin/env bash
# One-time (WSL): generate this build's own release keys in ~/gvwifi-keys/release,
# where 3-build.sh picks them up (LineageOS inline signing, "release-keys").
#
#   CN="Your Name" scripts/4-make-keys.sh
#
# Same files as development/tools/make_key with no password: <name>.pk8 + <name>.x509.pem.
# Never re-run over existing keys: every future update must be signed with the same ones,
# and changing keys on an installed tablet needs a data wipe. Back the folder up offline.
set -euo pipefail

KEYS=${RELEASE_KEYS:-$HOME/gvwifi-keys/release}
CN=${CN:-gvwifi}
SUBJECT=${SUBJECT:-"/C=US/O=gvwifi/CN=$CN"}

if [ -e "$KEYS/releasekey.pk8" ]; then
    echo "!! $KEYS already has keys. Refusing to overwrite them."; exit 1
fi
umask 077
mkdir -p "$KEYS"

# The certificate set from the LineageOS signing guide. APEX modules keep their stock keys.
for name in bluetooth cyngn-app media networkstack nfc platform releasekey sdk_sandbox shared testcert testkey verity; do
    tmp=$(mktemp)
    openssl genrsa -f4 2048 > "$tmp" 2>/dev/null
    openssl req -new -x509 -sha256 -key "$tmp" -out "$KEYS/$name.x509.pem" -days 10000 -subj "$SUBJECT"
    openssl pkcs8 -in "$tmp" -topk8 -outform DER -out "$KEYS/$name.pk8" -nocrypt
    rm -f "$tmp"
    echo "key: $name"
done

# 3-build.sh copies this folder to vendor/lineage-priv/keys/.
# The Bluetooth line matters: without it SELinux keeps the AOSP test key for Bluetooth
# while its APK is signed with ours, and zygote aborts every Bluetooth start.
cat > "$KEYS/keys.mk" <<'MK'
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
PRODUCT_MAINLINE_BLUETOOTH_SEPOLICY_DEV_CERTIFICATES := vendor/lineage-priv/keys
MK
cat > "$KEYS/BUILD.bazel" <<'BZ'
filegroup(
    name = "android_certificate_directory",
    srcs = glob([
        "*.pk8",
        "*.pem",
    ]),
    visibility = ["//visibility:public"],
)
BZ

echo "Keys in $KEYS. Back this folder up somewhere off this PC now."
