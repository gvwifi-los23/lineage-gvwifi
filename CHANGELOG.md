# gvwifi LineageOS 23.2: changelog of all modifications

Base: LineageOS 23.2 (Android 16, `lineage_gvwifi-bp4a-userdebug`) from the github.com/gvwifi
trees, kernel 3.10.108 (Exynos 7580), for the Samsung Galaxy View **SM-T670**.
Every source change is a patch in `patches/<project>/`, applied by `scripts/apply-patches.sh`
at build time. Nothing is committed upstream. Current build: 2026-09-28 (started 18:18), ROM zip
SHA-256 `28fc8758…2c2e`, recovery tar `bce99ffe…f9ef`.

---

## Kernel: `kernel/samsung/universal7580` (11 patches)

| Patch | Change | Why |
|---|---|---|
| 0001 kbuild mkdir `O=` | Create the output dir before `headers_install` | 23.2's build runs it into a fresh dir; the 3.10 Makefile aborted |
| 0002 uapi `O_TMPFILE` | Add `O_TMPFILE` to `asm-generic/fcntl.h` | bionic 16 fortify headers need it for vendor modules |
| 0003 defconfig: cluster hotplug off | `CONFIG_EXYNOS7580_DYNAMIC_CLUSTER_HOTPLUG` disabled | Constant CPU off/online plus a broken cpufreq "revive" path caused **hard LOCKUP on cpu 0** after about 40 min |
| 0004 configfs `i_rwsem` to `i_mutex` | 3.10 API | Backport didn't build with `CONFIG_LOCKDEP` (debugging) |
| 0005 s3c_udc: drop `dev->lock` around gadget suspend/resume | USB IRQ handler no longer calls `composite_suspend()` holding the lock it re-takes | **The freeze fix.** USB plug/unplug or PC autosuspend self-deadlocked CPU 0 with IRQs off (black/frozen screen). Verified 5/5 plug cycles on a debug kernel |
| 0006 sched_fork: cpufreq stats before `get_cpu()` | Move a `GFP_KERNEL` allocation out of the preempt-disabled section | Sleeping allocation with preemption off on every fork |
| 0007 SELinux: stop forcing permissive | `CONFIG_SECURITY_SELINUX_PERMISSIVE` off; `sel_write_enforce()` no longer rewrites writes to 0 | The kernel injected `androidboot.selinux=permissive` and refused enforcing |
| 0008 SELinux: restore `avc_denied()` enforcement | Upstream check restored | The gvwifi kernel stubbed it to always grant, so "Enforcing" was cosmetic. Now denials really block |
| 0009 bootwatch | New `kernel/bootwatch.c`. If `sys.boot_completed` isn't reached within 900 s, dump all tasks and warm-restart into recovery. Before boot completes, power-off/halt/reboot requests are logged and redirected to recovery | Safety net that keeps the kernel log after a failed boot (cold resets erased it) |
| 0010 bootwatch + SELinux: recovery and charger aware | The watchdog doesn't arm in recovery (`bootmode=2` on the cmdline) or off-mode charging (`androidboot.mode=charger`). In recovery, `sel_write_enforce()` keeps SELinux permissive | Neither mode sets `sys.boot_completed`, so the watchdog would bounce recovery back into recovery and restart charging after 15 min. Recovery's policy was never written for a kernel that really enforces (zip installs need relabel/loop access) |
| 0011 USB: reconnect after gadget rebind | `udc_bind_to_driver()` calls `usb_gadget_connect()` again (Samsung had commented it out for the legacy Android gadget, which isn't built here) | Unbinding the gadget soft-disconnects the controller, and nothing reconnected it after rebinding. So the first USB function change (entering or leaving sideload in recovery, `svc usb setFunctions` in the ROM) dropped adb until reboot, and replugging didn't help because the driver remembered "disconnected". Verified in the ROM (an MTP switch re-enumerates in about 3 s) and in recovery (from a live adb session: Apply from ADB, full sideload with status 0, adb back 4 s later without a replug, `adb reboot` instant) |

## Device trees

### `device/samsung/gvwifi` (10 patches)
| Patch | Change | Why |
|---|---|---|
| 0001 no cache image + `releasetools.py` | No `cache.img`; releasetools supplies `cache_size` | `/cache` isn't mounted any more (see common 0001); fixed `KeyError: /cache` and the blockimgdiff assert |
| 0002 init.target.rc install path + GPU boost | rc installed to `$(TARGET_OUT_VENDOR_ETC)/init/hw`; Mali `highspeed_clock` 668 MHz @ 70% load | The rc was never imported (swappiness, KSM, tuning never ran); GPU sat at 266–350 MHz on 720p video |
| 0003 reliable present fences | `ro.vendor.hwc.present_fence_reliable=true` | Opt in to hardware/interfaces 0001 |
| 0004 props + overlay | `persist.wm.debug` prop moved to system; overlay `config_customizedMaxCachedProcesses=1`, `config_defaultPeakRefreshRate=60` | Low RAM (Plex ANRs from memory thrash); stop 60↔30 Hz render-rate churn |
| 0005 CPU governor ramp | On boot_completed: cpu0 hispeed 1.2 GHz / go_hispeed_load 80 / target_loads "75 1300000:85"; cpu4 hispeed 1.3 GHz / 85 / "80 1500000:90"; above_hispeed_delay 20 ms | Stock interactive tunables ramped too late for touch/scroll (no input boost in the power HAL) |
| 0006 INT bus floor | `bus_int min_freq = 267000` | At 100–160 MHz the MSC scaler/DECON missed a vsync on about 10% of video frames. TimeStats: 58 × (50 ms + 16 ms) judder pairs per 20 s went to **0** |
| 0007 disarm bootwatch | `write /sys/module/bootwatch/parameters/armed 0` on boot_completed | Pairs with kernel 0009 |
| 0008 built-in tuning | SettingsProvider overlay: window/transition/animator scales 50%; LineageSettings overlay: battery % shown; `PRODUCT_DEXPREOPT_SPEED_APPS` Launcher3QuickStep, SystemUI, Settings, LatinIME | The post-install script's tuning is now the ROM default (fresh installs). Upgraded installs keep old settings; see gvwifi Tweaks |
| 0010 ship gvwifi Tweaks | App source under `GvwifiTweaks/` and `PRODUCT_PACKAGES += GvwifiTweaks` | Every install gets the setup screen; no separate APK or PC step |
| 0009 signature allowlist for gvwifi Tweaks | `/system/etc/permissions/signature-permissions-gvwifi-tweaks.xml` lets `org.gvwifi.tweaks` hold WRITE_SECURE_SETTINGS, WRITE_SETTINGS, CHANGE_COMPONENT_ENABLED_STATE, GRANT_RUNTIME_PERMISSIONS, DEVICE_POWER | Android 15+ denies platform signature permissions to a platform-signed app that isn't in the system image unless it is allowlisted ("not in signature permission allowlist") |

### `device/samsung/universal7580-common` (6 patches)
| Patch | Change | Why |
|---|---|---|
| 0001 `/metadata` on CACHE, userdata p22 | fstab: `/metadata` on CACHE (p21), no `/cache`; sepolicy userdata label on p22 | **This SM-T670 has no HIDDEN partition.** A missing first-stage `/metadata` bootlooped |
| 0002 A16 HAL labels, props, 60 Hz | Labels for AIDL health/power/vibrator HALs under `/(vendor\|system/vendor)`, gpsd, odm configs; `vendor_gvwifi_hwc_prop`; vendor_init proc_vm writes; system_server gps fifo; charger props to system; `use_content_detection_for_refresh_rate=false` | Services ran in the wrong domains; groundwork for enforcing |
| 0003 enforcing-ready rules | genfscon charger power_supply → `sysfs_usb_supply`; gralloc as same-process HAL; `ro.vendor.*` build props; camera/composer/gpsd/vendor_init rules | Denials seen in permissive |
| 0004 rules for real enforcing | `set_prop(vendor_init, vendor_gvwifi_hwc_prop)`; fuel gauge `1-000b/power_supply` → `sysfs_batteryinfo`; netd↔gpsd socket tagging; ueventd `sys_nice` | Without the set_prop, **present fences were silently off** under Enforcing |
| 0006 GPS symlinks from a system init script | New `configs/init/gps-links.rc` (installed to `/system/etc/init`) creates `/data/system/gps` and `/data/gps` → `/data/vendor/gps` | Samsung gpsd hardcodes both paths. The vendor rc's `symlink` commands run as `vendor_init`, which may not write core `/data`, so on a fresh install they silently failed and GPS never started (gpsd retried every 5 s). Found on the first clean install of the public build |
| 0005 rules seen under real enforcement | vendor_init `search` on wifi/app/radio/nfc data dirs; vendor_toolbox `sys_admin` (init.baseband.rc strips `security.sehash` on /efs); dontaudit gpsd/tee probes | Denials enforced once kernel 0008 landed |

## Android framework and modules

| Project / patch | Change | Why |
|---|---|---|
| `hardware/interfaces` 0001 | hwc2on1adapter omits `PresentFenceIsNotReliable` when `ro.vendor.hwc.present_fence_reliable` is set | The adapter forced HW vsync on permanently. A/B: fences on uses about 185% vs 198% of a core for SF+composer |
| `frameworks/base` 0001 (public) | SystemUI rotation tile: on devices **without an accelerometer**, a tap switches between landscape (0°) and portrait (90°) via `RotationPolicy.setRotationLockAtAngle`, and the label reads "Landscape"/"Portrait". Devices with an accelerometer are unchanged | The Galaxy View has no accelerometer (DTS: only a bh1733 light and an sx9310 grip sensor), so auto-rotate never worked. Tested on device |
| `frameworks/base` 0002 (public since 2026-09-26; was private 0001) | `ComputerEngine.isMicrogSigned()` also accepts the maintainer's Companion certificate (SHA-256 `fa7fcd26…2871`), **only for `com.android.vending`** | Lets the maintainer-built microG Companion (0.3.16-28, with Play Age Signals; shipped in `flash-kit/4-apps`) spoof the Play Store signature, so apps that query Age Signals work (without it they fail with error GA-5). It was kept private at first; made public once the ROM itself was signed with the maintainer's release keys, since users already trust that maintainer with far more (system updates). That retired the separate private build |
| `frameworks/base` 0003 | SettingsProvider loads `def_animator_duration_scale` (new overlayable default, 100%) into Global `animator_duration_scale` | AOSP only has overlayable defaults for the window and transition scales; needed for gvwifi 0008 |
| `lineage-sdk` 0001 | New overlayable `def_status_bar_show_battery_percent` (default 0), loaded in LineageSettingsProvider | Lets gvwifi 0008 turn on battery % by default |
| `packages/modules/Connectivity` 0001 | `BpfNetMaps.initBpfMaps()` logs and continues on `ENOSYS` when clearing uid-owner / ingress-discard / local_net_access / local_net_blocked_uid maps | The 3.10 BPF backport can't delete from some map types. Every **restart** of system_server crashed, so one crash became a loop. On 2026-09-24 that loop corrupted `packages.xml` + its reserve copy and PackageManager **deleted all user apps and their data** |
| `art` 0001 | `Jit::NotifyZygoteCompilationDone()` sets `kNotifiedFailure` when `fd_methods_ == -1` | No `memfd_create` before kernel 3.17, so the early return left no state and `PostZygoteFork` aborted zygote on its first fork after background boot-method compilation, every few minutes. Verified: 6 launches after 12 min uptime, 0 aborts |

## Build tooling (`scripts/`)
- `apply-patches.sh`: idempotent. For each project it restores every patched file to its
  pristine git blob (`git show HEAD:file`, because `git checkout` skipped same-size edits),
  then applies the full series in order. Files touched by `patches-private/` are always
  restored to stock; those patches are applied only with `PRIVATE=1`
  (owner build: `PRIVATE=1 bash scripts/3-build.sh`; public build: `bash scripts/3-build.sh`).
  Since 2026-09-26 `patches-private/` is empty and there is a single public build; the
  mechanism is kept for future owner-only experiments.
- **Signing:** public builds are signed with the owner's **private release keys** through
  LineageOS inline signing (`vendor/lineage-priv/keys/keys.mk`, copied in from
  `~/gvwifi-keys/release` by `3-build.sh`; tag `release-keys`). `PRIVATE=1` builds stay on AOSP
  test-keys, matching the owner's existing install. Keys are backed up in `keys/release/`.
  Every future public update must be signed with the same keys. Moving an existing install
  between key sets needs a data wipe. APEX modules keep their stock AOSP keys.
  `keys.mk` also sets `PRODUCT_MAINLINE_BLUETOOTH_SEPOLICY_DEV_CERTIFICATES` to the release keys.
  Otherwise SELinux's Bluetooth certificate stays the AOSP test key while the Bluetooth APK is
  signed with the release key, and zygote aborts every Bluetooth start ("Bluetooth keeps
  stopping", seinfo `default`).
- `3-build.sh`: adds `dtimage` to the build goals; ccache opt-in (`CCACHE=1`); `KEEP_GOING=1`;
  copies the newest zip + `.sha256` to `~/gvwifi-dist/<timestamp>`.
- `device-check.ps1`: backs up EFS and small partitions from TWRP, and checks the partition
  layout against what the build expects.
- Debug-only (not in builds): `patches-debug/…/0001` lockdep + spinlock debug (found the USB
  deadlock); `0002` audit `dontaudit` denials, unrated audit printk, 2 MB log buffer.

## gvwifi Tweaks app (`tools/GvwifiTweaks`, in the ROM since the 09-28 build via gvwifi 0010)
The ROM's optional setup screen. Upgraded installs use it for the tuning, which the new
defaults don't apply to. Everyone can use it for microG permissions after installing microG
(no PC or `post-install.ps1` needed). It's a single screen, and nothing happens until the user
taps Apply:
- 0.5× animations and battery %.
- microG permissions and battery exemption.
- Disable the 24 unused system apps, one checkbox each.

Built in-tree with `certificate: "platform"` (release platform key `9d4dc98f…67ad`). From
the 09-28 build it ships as a system app (`/system/app/GvwifiTweaks`, gvwifi 0010). Before that
it was a separate APK that got its permissions through the gvwifi 0009 allowlist; the
allowlist stays so a data-installed copy keeps working. v1.2 has the new intro text. v1.1 dropped the
60 Hz step: the panel has only a 60 Hz mode, and non-system apps may not write
`min/peak_refresh_rate`. Tested on device: all steps applied.

## Changes on the tablet (runtime)
- Tuning (animations, battery %, 60 Hz, 1 cached app, core apps speed-compiled) is built
  into the ROM. Upgraded installs: gvwifi Tweaks or the optional `post-install.ps1`.
- 24 system apps disabled (`disabled-apps.txt`), plus the setup wizard after the 09-24 package loss.
- Apps: microG Services 0.3.16, microG Companion (self-built, see
  `microg-companion-modified/`), Aurora Store, NewPipe 0.29.1 (F-Droid), Plex, YouTube.
- microG: location/phone/accounts/notification permissions and a battery-optimization exemption.
- Apps compiled with `cmd package compile -m speed -f` (redo after each ROM install).

## Known issues and limits
- Charging only from the 19 V DC barrel. Micro-USB is data only (hardware).
- Aurora Store's home page crashes (Aurora bug, duplicate list key). Open app pages with
  `am start -a VIEW -d market://details?id=<pkg> -p com.aurora.store`.
- The Companion only works on this ROM (owner-key allowlist). Switch back to official microG
  once 0.3.17 is released.
- Recovery's kernel stays SELinux-permissive (build 2b / 09-23 recoveries). Enforcing
  recovery is untested.
- This build needs a unit **without** a HIDDEN partition.
- Recoveries older than 09-26 18:58 drop USB after the first sideload (fixed by kernel 0011).
  Flash the current `2-recovery` tar once with Odin; the ROM zip doesn't update recovery.
- The Windows adb server sometimes loses a device that is still configured on the tablet's side
  (the kernel log shows no disconnect). `adb kill-server` fixes it. After recovery's
  5-minute sideload timeout, a second *Apply from ADB* in the same session may not bring USB
  up; reboot to recovery first.
