# gvwifi LineageOS 24.0 (Android 17): changelog

Branch `lineage-24.0`: LineageOS 24.0 (Android 17, `lineage_gvwifi-cp2a-userdebug`) for the Samsung
Galaxy View **SM-T670**. It carries the complete 23.2 patch series (below) plus the Android 17 port.

## 20261017: first Android 17 build
`lineage-24.0-20261017-UNOFFICIAL-gvwifi.zip`, release-keys, security patch 2026-10-01,
ROM zip SHA-256 `10183155a04490fba247738b10a1bf054b49aae237b5484f5f4795852f013e0d`.

- Boots to the home screen with SELinux enforcing; installs over 23.2 without a wipe (same keys).
- Kernel and dt.img prebuilt from the 23.2 tree (LineageOS 24 has no GCC kernel builds).
- Android 17 fixes, all explained in [`docs/ANDROID-17.md`](docs/ANDROID-17.md):
  - BPF on kernel 3.10: 5.4 program variants (`ro.bpf.kver_override`), relaxed loader gate,
    `filterPowerSupplyEvents.o` not shipped, 5.4 traffic-stats programs on Android 17,
    ring-buffer event handlers optional, netd self-test advisory with errors in the kernel log
    (Connectivity 0002-0005, build/make 0001, gvwifi 0015, common 0016);
  - graphics: legacy gralloc mapper accepted, real ION library, `/dev/ion` SELinux label and access
    (common 0017-0019);
  - ART: boot image built for the concurrent-copying GC (no userfaultfd on 3.10; gvwifi 0016);
  - build/HAL updates: VINTF level 7, AIDL light/memtrack, health V5, audio IModule v4, camera shim
    headers, `sysfs_block` (gvwifi 0012-0014, common 0011-0015).

---

# gvwifi LineageOS 23.2 changes (carried into 24.0)

Base: LineageOS 23.2 (Android 16, `lineage_gvwifi-bp4a-userdebug`) from the github.com/gvwifi
trees, kernel 3.10.108 (Exynos 7580), for the Samsung Galaxy View **SM-T670**.
Every source change is a patch in `patches/<project>/`, applied by `scripts/apply-patches.sh`
at build time. Nothing is committed upstream. Current build: 2026-10-16 (`lineage-23.2-20261016-UNOFFICIAL-gvwifi.zip`, security patch 2026-10-01), ROM zip
SHA-256 `2dc6b85a…bfc0`, recovery tar `09ff8f4e…4171`.

---

## Kernel: `kernel/samsung/universal7580` (17 patches)

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
| 0012 fscrypt: implement `FS_IOC_GET_ENCRYPTION_POLICY_EX` | `fscrypt_ioctl_get_policy_ex()` in `fs/crypto/policy.c` plus the ext4 ioctl case | The fscrypt v2 backport declared it but never implemented it, so the ioctl returned `-ENOTTY` and nothing could read back a v2 policy: TWRP Data backups lost every directory's encryption policy |
| 0013 USB FunctionFS: drop the kiocb reference in aio cancel | `ffs_aio_cancel()` calls `aio_put_req()` | On 3.10, `kiocb_cancel()` takes an extra reference before calling the cancel callback and expects the callback to drop it (as gadgetfs' `ep_aio_cancel()` does). The backported FunctionFS callback follows the 3.15+ convention and never did, so each read adbd had pending when it stopped leaked its kiocb, and with it the endpoint file. FunctionFS never reset and every new adbd failed with "failed to write USB descriptors: No such process": `adb root`, turning USB debugging off, or any USB mode switch left USB adb offline until a reboot. Verified: `adb root` over USB reconnects |
| 0014 fs: clear and free per-inode fscrypt / fs-verity info | `inode_init_always()` sets `i_crypt_info` and `i_verity_info` to NULL; `ext4_clear_inode()` calls `fscrypt_put_encryption_info()` and `fsverity_cleanup_inode()`; `ext4_alloc_inode()` clears the legacy ext4 key | **Data integrity.** The fscrypt/fs-verity backport added both fields but never cleared or freed them, so an inode recycled from the slab kept the previous file's info. A stale `i_verity_info` (left by an evicted fs-verity APK) made reads of ordinary files fail verification with a silent EIO: after a few framework restarts `packages.xml`, `roles.xml` and `package-restrictions.xml` became unreadable and system_server crash-looped ("Failed to read roles.xml ... EIO"). A stale `i_crypt_info` means data written with another file's key, which reads back as garbage after a reboot (the likely cause of the 2026-09-24 `packages.xml` loss). Verified: 0 read errors over the whole of `/data/system`, `/data/misc(_de)`, `/data/app` after 8 framework restarts (several per scan before) |
| 0015 ION: keep multi-heap allocations out of secure heaps (since build 20261014) | `__ion_alloc()` skips a secure heap (`secure` in the device tree, e.g. `video`) for an unprotected request that names more than one heap; new helper `ion_heap_is_secure()` | Android 16's Codec2 ION allocator asks for every heap (`~0`), so a software decoder's buffer (a 32 KB Vorbis block at boot, kept by a leaked reference) landed in the secure `video` heap. While any unprotected buffer sits there the heap can't switch to protected mode, so every protected allocation failed with EPERM and secure video decoding could not start. Requests that name only the secure heap (Exynos OMX) are unchanged. Verified: the heap stays empty after boot and enters protected mode on demand; Widevine L3 playback (720p, hardware decoder) still works |
| 0016 serial: no magic SysRq from the UARTs (since build 20261015) | `SUPPORT_SYSRQ` no longer defined in `drivers/tty/serial/samsung.c` | **The warm-reboot hang.** On a warm reboot (TWRP → system, `adb reboot`, system → recovery) UART1 (`13810000.uart`) receives a break plus junk, which the serial core turned into SysRq commands; SysRq `f` (OOM kill) at ~2.8 s panicked with "Out of memory and no killable processes" and the tablet hung after the Galaxy View logo (cold boots were fine). Verified: 3/3 warm reboots boot in 41 s, no UART SysRq in the log. `/proc/sysrq-trigger` still works |
| 0017 battery: smart fuel gauge releases its I2C lock (since build 20261015) | `smart_fg_read_block_data()` now unlocks `i2c_lock` | The lock was never released, so the first read of the gauge's firmware byte (the `present` property of `smart-fuelgauge`) blocked every later gauge access: the battery monitor hung and Android showed a frozen percentage, voltage and current until reboot. Verified: values update after reading that property |

## Device trees

### `device/samsung/gvwifi` (11 patches)
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
| 0011 ship HeliBoard (Galaxy View keyboard) | `HeliBoard/Android.bp` (`android_app_import`, signed by the build) and `PRODUCT_PACKAGES += HeliBoard`; `3-build.sh` copies `tools/HeliBoard/out/HeliBoard.apk` there | The default keyboard: HeliBoard v4.1 with the stock SM-T670 Samsung Keyboard layout and colors and word suggestions (see `README`/`BUILD-KIT`, "Keyboard"). LatinIME stays installed as an alternative |

### `device/samsung/universal7580-common` (10 patches)
| Patch | Change | Why |
|---|---|---|
| 0001 `/metadata` on CACHE, userdata p22 | fstab: `/metadata` on CACHE (p21), no `/cache`; sepolicy userdata label on p22 | **This SM-T670 has no HIDDEN partition.** A missing first-stage `/metadata` bootlooped |
| 0002 A16 HAL labels, props, 60 Hz | Labels for AIDL health/power/vibrator HALs under `/(vendor\|system/vendor)`, gpsd, odm configs; `vendor_gvwifi_hwc_prop`; vendor_init proc_vm writes; system_server gps fifo; charger props to system; `use_content_detection_for_refresh_rate=false` | Services ran in the wrong domains; groundwork for enforcing |
| 0003 enforcing-ready rules | genfscon charger power_supply → `sysfs_usb_supply`; gralloc as same-process HAL; `ro.vendor.*` build props; camera/composer/gpsd/vendor_init rules | Denials seen in permissive |
| 0004 rules for real enforcing | `set_prop(vendor_init, vendor_gvwifi_hwc_prop)`; fuel gauge `1-000b/power_supply` → `sysfs_batteryinfo`; netd↔gpsd socket tagging; ueventd `sys_nice` | Without the set_prop, **present fences were silently off** under Enforcing |
| 0006 GPS symlinks from a system init script | New `configs/init/gps-links.rc` (installed to `/system/etc/init`) creates `/data/system/gps` and `/data/gps` → `/data/vendor/gps` | Samsung gpsd hardcodes both paths. The vendor rc's `symlink` commands run as `vendor_init`, which may not write core `/data`, so on a fresh install they silently failed and GPS never started (gpsd retried every 5 s). Found on the first clean install of the public build |
| 0005 rules seen under real enforcement | vendor_init `search` on wifi/app/radio/nfc data dirs; vendor_toolbox `sys_admin` (init.baseband.rc strips `security.sehash` on /efs); dontaudit gpsd/tee probes | Denials enforced once kernel 0008 landed |
| 0007 Widevine: legacy CDM may use `/data/mediadrm` | `hal_drm_default` gets the `data_between_core_and_vendor_violators` attribute and create/read/write on `media_data_file` dirs and files | The 2016 Widevine CDM (`libwvdrmengine.so`, including its obfuscated L3 code) hardcodes `/data/mediadrm`, a core data path that Treble forbids to vendor HALs. Every Widevine session failed, so apps saw only ClearKey and protected video wouldn't play. Verified: Widevine L3 (system ID 4445) provisions online, opens sessions and generates license requests under Enforcing |
| 0008 Bluetooth profile services (since build 20261016) | `bluetooth.profile.*.enabled=true` for A2DP source, AVRCP target, GATT, HFP AG, HID device/host, MAP server, OPP, PAN NAP/PANU, PBAP server | Android 13+ starts a Bluetooth profile service only when its property is true. None were set, so only GATT and hearing aid ran: headsets and speakers paired but never connected |
| 0009 Bluetooth audio: AIDL `IModule/bluetooth` + audio provider (since build 20261016) | New `android.hardware.audio.service.bluetooth.universal7580`: AOSP's reference Bluetooth module (with its port configuration) as `IModule/bluetooth`, which also starts `IBluetoothAudioProviderFactory/default` (software A2DP data path). The policy config includes `bluetooth_audio_policy_configuration_7_0.xml`. The service restarts whenever audioserver does | The AIDL audio HAL only had `IModule/default`, so A2DP had no audio module and media kept playing on the speaker. `Module::createInstance(type)` alone gives an empty configuration (no ports), so the reference ports are passed explicitly. audioserver.rc restarts only the stock HAL services; without restarting this one too, it keeps the old A2DP connection after an audioserver crash and A2DP fails ("already connected") until reboot. Verified: music plays on a Bluetooth headset |
| 0010 Audio HAL: Bluetooth SCO and stream routing (since build 20261016) | Primary AIDL HAL wrapper: Bluetooth SCO device ports (headset/car kit out, headset mic) with routes and legacy device mapping; each patch now re-routes the open stream (`routing=` on the stream, which is the only place the legacy HAL switches devices); an `IBluetooth` that passes SCO wideband/NREC to the legacy HAL; connected external devices get their own port ID and routes; `binder_call(hal_audio_default, hal_audio_default)` | The legacy HAL (`audio_hw.c`) already supports SCO over the BT chip's I2S/PCM link (`bt-sco-*` mixer paths), but the wrapper never exposed it, so the headset mic and call audio stayed on the tablet. Streams also never followed a new patch after opening. Returning the template's port ID from `connectExternalDevice` made audioserver abort ("duplicate port ID") when a SCO headset connected. Verified: headset mic and call audio in a WebRTC call (wideband mSBC), music still on A2DP |

## Android framework and modules

| Project / patch | Change | Why |
|---|---|---|
| `hardware/interfaces` 0001 | hwc2on1adapter omits `PresentFenceIsNotReliable` when `ro.vendor.hwc.present_fence_reliable` is set | The adapter forced HW vsync on permanently. A/B: fences on uses about 185% vs 198% of a core for SF+composer |
| `hardware/interfaces` 0002 | USB HAL 1.0: without `/sys/class/dual_role_usb`, report one fixed port (`otg_default`, UFP, data role device, power role sink, no role switching) | The 3.10 kernel has no dual_role_usb or typec class, so the HAL reported no ports, the framework's data role stayed NONE and Settings greyed out every USB option (file transfer, PTP, MIDI, no data). Micro-USB on this tablet is device-only. Verified: the options work |
| `frameworks/base` 0001 (public) | SystemUI rotation tile: on devices **without an accelerometer**, a tap switches between landscape (0°) and portrait (90°) via `RotationPolicy.setRotationLockAtAngle`, and the label reads "Landscape"/"Portrait". Devices with an accelerometer are unchanged | The Galaxy View has no accelerometer (DTS: only a bh1733 light and an sx9310 grip sensor), so auto-rotate never worked. Tested on device |
| ~~`frameworks/base` 0002~~ (removed in build 20261014) | Accepted the maintainer-built microG Companion's certificate for `com.android.vending` signature spoofing | Official microG 0.3.17 includes Play Age Signals, so the maintainer-built Companion and this allowlist are no longer needed. Builds after 20261011 accept only official microG signatures |
| `frameworks/base` 0003 | SettingsProvider loads `def_animator_duration_scale` (new overlayable default, 100%) into Global `animator_duration_scale` | AOSP only has overlayable defaults for the window and transition scales; needed for gvwifi 0008 |
| `lineage-sdk` 0001 | New overlayable `def_status_bar_show_battery_percent` (default 0), loaded in LineageSettingsProvider | Lets gvwifi 0008 turn on battery % by default |
| `frameworks/base` 0004 | `InputMethodInfoUtils.isSystemImeThatHasSubtypeOf()`: a system IME marked `isDefault` whose XML subtypes name no language counts as matching the system locale | First boot picks a default keyboard only among system IMEs that are `isDefault` **and** declare a subtype for the system locale. HeliBoard declares its languages at runtime (`method_dummy.xml` has one placeholder subtype without a locale), so it never qualified and LatinIME was chosen. Only affects default system IMEs whose subtypes are all locale-less |
| `frameworks/av` 0001 (since build 20261014) | `DrmHalHidl`: for drm@1.0-1.2 factories, `getSupportedSchemes()` probes the well-known scheme UUIDs (Widevine, ClearKey, W3C common, PlayReady), and `isCryptoSchemeSupported()` with a security level answers from the content type for the software levels and "no" for the hardware levels | The 2016 Widevine HAL (drm@1.0) was missing from `MediaDrm.getSupportedCryptoSchemes()`, and asking for Widevine at any security level threw `UnsupportedOperationException`, so apps that check this way decided there was no Widevine. Verified: Widevine is listed, software levels report supported, hardware levels report unsupported, L3 playback unchanged |
| `frameworks/av` 0002 (since build 20261014-b) | `DrmHalHidl::getSecurityLevel()`: for a drm@1.0 plugin (no per-session security level), answer from the plugin's `securityLevel` property: L1 → HW_SECURE_ALL, L2 → HW_SECURE_CRYPTO, L3 → SW_SECURE_CRYPTO; anything else still returns ERROR_DRM_CANNOT_HANDLE | Media3/ExoPlayer on Android 12+ asks for the session's security level before choosing a decoder; with the 2016 Widevine HAL that failed (`Failed to get security level: ERROR_DRM_CANNOT_HANDLE`, app error 1009R/1004) and playback stopped, although the web player worked. Verified: `getSecurityLevel(session)` returns SW_SECURE_CRYPTO, L3 playback unchanged |
| `packages/inputmethods/LatinIME` 0001 | LatinIME's `method.xml`: `isDefault="false"` | Otherwise LatinIME is also a default candidate and, having an English subtype, wins the final pick. It stays installed as an alternative (Settings > System > Keyboard) |
| `packages/modules/Connectivity` 0001 | `BpfNetMaps.initBpfMaps()` logs and continues on `ENOSYS` when clearing uid-owner / ingress-discard / local_net_access / local_net_blocked_uid maps | The 3.10 BPF backport can't delete from some map types. Every **restart** of system_server crashed, so one crash became a loop. On 2026-09-24 that loop corrupted `packages.xml` + its reserve copy and PackageManager **deleted all user apps and their data** |
| `art` 0001 | `Jit::NotifyZygoteCompilationDone()` sets `kNotifiedFailure` when `fd_methods_ == -1` | No `memfd_create` before kernel 3.17, so the early return left no state and `PostZygoteFork` aborted zygote on its first fork after background boot-method compilation, every few minutes. Verified: 6 launches after 12 min uptime, 0 aborts |

### `system/core`

| Project / patch | Change | Why |
|---|---|---|
| `system/core` 0001 | libprocessgroup `KillProcessGroup()` waits on `cgroup.events` in polls of at most 5 ms | Android 16 waits for `POLLPRI` on `cgroup.events` until a 2200 ms deadline. The 3.10 kernel's backported `cgroup.events` reports `populated` correctly but never raises `POLLPRI`, so every `stop` (and every process-group kill) took 2.2 s even though the process died in milliseconds. UsbDeviceManager waits only 1 s for `sys.usb.state=none`, so **MTP never turned on** ("waitForState(none) FAILED", then Failsafe back to adb). With kernel 0013: init clears adbd's cgroup in 0.5 ms and an MTP switch completes in about 0.6 s. Verified: Windows browses the tablet over MTP |

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
- Charging only from the 19 V DC barrel. Micro-USB does not charge: the bq24773 charger can't step
  5 V up to the 3-cell pack, Android shows *Discharging* on USB (measured about -23 mA with the
  screen off) and the tablet shows no off-mode charging screen on USB.
- Aurora Store's home page crashes (Aurora bug, duplicate list key). Open app pages with
  `am start -a VIEW -d market://details?id=<pkg> -p com.aurora.store`.
- microG: use official microG 0.3.17 or newer (2026-09-29; includes Play Age Signals). Builds
  after 20261011 no longer accept the earlier maintainer-built Companion (`frameworks/base` 0002
  removed); replace it with the official one.
- Recovery's kernel stays SELinux-permissive (build 2b / 09-23 recoveries). Enforcing
  recovery is untested.
- This build needs a unit **without** a HIDDEN partition.
- Widevine is L3 only (software; SD-quality streams in most apps). L1 isn't supported: it needs
  Samsung's matching TEE (MobiCore t-base 302A) software, and the stock Android 5.1 OEMCrypto
  library implements an older API than the 2016 Widevine engine expects. DRM Info lists only
  ClearKey because the 2016 Widevine HAL (drm@1.0) can't report its schemes; apps that ask for
  Widevine directly get it.
- Recoveries older than 09-26 18:58 drop USB after the first sideload (fixed by kernel 0011).
  Flash the current `2-recovery` tar once with Odin; the ROM zip doesn't update recovery.
- The Windows adb server sometimes loses a device that is still configured on the tablet's side
  (the kernel log shows no disconnect). `adb kill-server` fixes it. After recovery's
  5-minute sideload timeout, a second *Apply from ADB* in the same session may not bring USB
  up; reboot to recovery first.
