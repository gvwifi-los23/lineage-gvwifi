# Source for LineageOS 23.2 gvwifi build 2026-09-28 (Galaxy View SM-T670)

The archives here are the exact trees the ROM was built from, with all patches applied.

| File | What |
|---|---|
| `kernel-samsung-universal7580-gvwifi-20260928.tar.xz` | Kernel source (Linux 3.10.108), as built. Defconfig: `arch/arm64/configs/lineageos_gvwifi_defconfig` |
| `device-samsung-gvwifi-20260928.tar.xz` | Device tree, as built |
| `device-samsung-universal7580-common-20260928.tar.xz` | Common device tree, as built |
| `gvwifi-los23-patches-and-scripts-20260928.tar.xz` | Every change as a separate patch (`patches/<project>/`), the build scripts, and the gvwifi Tweaks app source |
| `manifest/gvwifi.xml` | Local manifest (add to a LineageOS 23.2 checkout under `.repo/local_manifests/`) |

## Upstream

The trees are from github.com/gvwifi, at these commits, plus the patches:

| Path | Repo | Commit |
|---|---|---|
| kernel/samsung/universal7580 | https://github.com/gvwifi/android_kernel_samsung_universal7580 | `09ffce033980e53b17547774ebeb9a862a74744e` |
| device/samsung/gvwifi | https://github.com/gvwifi/android_device_samsung_gvwifi | `e0de20bf572362c426a29e4788798b14cf51c539` |
| device/samsung/universal7580-common | https://github.com/gvwifi/android_device_samsung_universal7580-common | `cf868df85d34aa9290adfe04500ebe39c82f0b31` |
| vendor/samsung/gvwifi (unmodified) | https://github.com/gvwifi/android_vendor_samsung_gvwifi | `dd6641b8dbca9409b4e326a0b9942eb24c67a44e` |
| vendor/samsung/universal7580-common (unmodified) | https://github.com/gvwifi/android_vendor_samsung_universal7580-common | `c69bb2c63e6f4b5a135b6b768d31ae1dfdf94e28` |

The vendor trees are Samsung's proprietary files and aren't changed, so they aren't included here.
Get them from the repos above.

## Rebuilding

1. Sync LineageOS 23.2 with `manifest/gvwifi.xml` as a local manifest.
2. Extract the patches archive and run `scripts/apply-patches.sh` (it applies `patches/` to the tree).
3. `source build/envsetup.sh && breakfast gvwifi && m bacon`

Official builds are signed with the maintainer's private release keys, which are not published.
A build of your own will be signed with test keys, so it can't be installed over an official build
without wiping data.
