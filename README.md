# LineageOS 23.2 (Android 16) for the Galaxy View SM-T670 (`gvwifi`)

Unofficial LineageOS 23.2 for the Wi-Fi Galaxy View (Exynos 7580, Linux 3.10.108), built on the
`github.com/gvwifi` bring-up trees plus the patch series in this repo.

| | |
|---|---|
| Lunch | `lineage_gvwifi-bp4a-userdebug` |
| Source | LineageOS 23.2 + [`local_manifests/gvwifi.xml`](local_manifests/gvwifi.xml) (pinned gvwifi trees) |
| Changes | [`patches/<project path>/NNNN-*.patch`](patches), applied by [`scripts/apply-patches.sh`](scripts/apply-patches.sh) (idempotent; nothing is committed into the upstream repos) |
| Latest build | `lineage-23.2-20261005-UNOFFICIAL-gvwifi.zip`, release-keys, security patch 2026-09-01 |

## Related repos
- [`lineage-recovery-gvwifi`](https://github.com/gvwifi-los23/lineage-recovery-gvwifi): the LineageOS recovery built from this tree
- [`twrp-gvwifi`](https://github.com/gvwifi-los23/twrp-gvwifi): TWRP 3.7.1 (twrp-14.1) with FBE decryption for this ROM
- [`microg-companion-gvwifi`](https://github.com/gvwifi-los23/microg-companion-gvwifi): the microG Companion build this ROM allowlists

## Build
1. Windows: `scripts\0-setup-wsl.ps1` (WSL Ubuntu 24.04), then in WSL `scripts/1-host-setup.sh`
2. `scripts/2-sync.sh`: syncs LineageOS 23.2 with the local manifest (~100 GB)
3. `tools/HeliBoard/build.sh`: builds the Galaxy View keyboard APK (HeliBoard v4.1 + `tools/HeliBoard/patches`;
   needs JDK 17 in `~/tools/jdk-17` and an Android SDK with NDK 28.0.13004108 in `~/android-sdk`)
4. `scripts/3-build.sh`: applies the patches, builds ROM zip + recovery (about 2-3 h from scratch, ~80 GB output)
   - `3-build.sh recovery` / `3-build.sh kernel` for partial builds
   - `KEEP_GOING=1`, `CCACHE=1`, `JOBS=N`

Builds are signed with release keys from `~/gvwifi-keys/release` when present (the maintainer's keys are
**not** published); otherwise with AOSP test keys, which can't be installed over a release-keys build
without wiping data.

## Docs
- [`docs/BUILD-KIT.md`](docs/BUILD-KIT.md): every fix and why (freezes, SELinux, HWC fences, BPF, ART, ...)
- [`docs/FLASHING.md`](docs/FLASHING.md): stock to this ROM with Odin + recovery sideload
- [`docs/SOURCES.md`](docs/SOURCES.md): upstream repos and commits
- [`CHANGELOG.md`](CHANGELOG.md)

## Hardware notes
- No accelerometer: the rotation tile toggles landscape/portrait (`frameworks/base` 0001).
- Default keyboard: HeliBoard with the stock Galaxy View layout and colors (`tools/HeliBoard`);
  the AOSP keyboard stays installed as an alternative.
- Charging only via the 19 V barrel adapter; micro-USB is data only.
- The bootloader (S-Boot T670UEU2APJ1) loads the whole boot/recovery image at `0x40204800` and
  copies the ramdisk to `0x42000000`: images over ~31.4 MB don't boot.
- Key combos: recovery = Power + Volume Up; download mode = Power + Volume Down + Home;
  force restart = Power + Volume Down.

## Licenses
Each patch is licensed like the project it modifies (kernel: GPL-2.0; AOSP/LineageOS: Apache-2.0).
The gvwifi Tweaks app (`tools/GvwifiTweaks`) is Apache-2.0. The HeliBoard patches (`tools/HeliBoard`)
are GPL-3.0, like HeliBoard.
