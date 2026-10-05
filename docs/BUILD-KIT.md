# LineageOS 23.2 (Android 16) for Galaxy View SM-T670 (`gvwifi`)

Unofficial build kit around the `github.com/gvwifi` LineageOS 23.2 bringup
(March 2026). That work has **no published builds, thread, or manifest** —
treat the first build as experimental.

| | |
|---|---|
| SoC | Exynos 7580, 8x Cortex-A53, 2 GB RAM, **32-bit userspace** (`TARGET_ARCH := arm`) |
| Kernel | Linux 3.10.108 + backported eBPF/BTF/ringbuf, MADV_WIPEONFORK, ext4 csum_seed |
| Partitions | no `/vendor` (lives in `/system/vendor`); `HIDDEN` is reformatted as `/metadata` |
| Recovery | **LineageOS Recovery built from this tree.** TWRP 3.2.1-0 (2017) cannot flash Pie+ ROMs. |
| Lunch | `lineage_gvwifi-bp4a-userdebug` |

## Steps

| # | Where | Command |
|---|---|---|
| 0 | Windows PowerShell | `.\scripts\0-setup-wsl.ps1` (run twice: before and after creating the Ubuntu user) |
| 1 | WSL | `~/gvwifi-los23/scripts/1-host-setup.sh` |
| 2 | WSL | `~/gvwifi-los23/scripts/2-sync.sh` (~100 GB download) |
| 3 | WSL | `~/gvwifi-los23/scripts/3-build.sh recovery` then `3-build.sh` |
| 4 | Windows, tablet in TWRP | `.\scripts\device-check.ps1` (**before any flashing**) |

Disk: ~260 GB on C: (only local drive; Z: is a network share and can't be used).
Peak during the first full build: ~205 GB inside WSL plus the WSL swap file on C:.

Build options: `KEEP_GOING=1` (report every failing module in one run), `CCACHE=1`
(opt-in compiler cache, +30 GB), `JOBS=N`.

## Fixes on top of the gvwifi trees

`3-build.sh` runs `scripts/apply-patches.sh`, which applies `patches/<path>/*.patch`
(idempotent). Nothing is committed into the upstream repos.

| Fix | Why |
|---|---|
| `kernel: 0001` kbuild `mkdir -p` for `O=` | 3.10 Makefile aborts when LineageOS 23.2's `generated_kernel_includes` runs `headers_install` into a fresh sandbox dir |
| `kernel: 0002` uapi `O_TMPFILE` defines | bionic 16's fortify `fcntl.h` needs it; vendor modules (tinycompress) compile against the 3.10 uapi headers |
| `universal7580-common: 0001` `/metadata` on CACHE (p21), userdata label p22 | this SM-T670 has **no HIDDEN partition** (the author's unit does, shifting USERDATA to p23); a missing first-stage `/metadata` device is fatal in init → bootloop |
| `gvwifi: 0001` no cache image + `releasetools.py` | no `/cache` mount any more, so no cache.img (`KeyError: /cache`); non-A/B OTA still needs `cache_size`, supplied by the releasetools hook |
| `kernel: 0003` defconfig: dynamic cluster hotplug off | CPUs 1-7 were offlined/re-onlined constantly; each re-online failed in the bring-up's custom cpufreq "revive" path, and after ~40 min: *Watchdog detected hard LOCKUP on cpu 0* → blank, frozen screen (log in `logs/`) |
| `kernel: 0004` configfs lockdep `i_rwsem`→`i_mutex` | backport didn't build with `CONFIG_LOCKDEP` |
| `kernel: 0005` s3c_udc: drop `dev->lock` around gadget suspend/resume | **the freeze**: on USB bus suspend (plug/unplug, PC autosuspend) the IRQ handler called `composite_suspend()` → `usb_gadget_set_selfpowered()` → `s3c_set_selfpowered()` with `dev->lock` already held → CPU0 self-deadlock with IRQs off → *hard LOCKUP on cpu 0*. Caught with `CONFIG_DEBUG_SPINLOCK` (logs in `logs/`) |
| `kernel: 0006` sched_fork: cpufreq task stats before `get_cpu()` | `GFP_KERNEL` allocation with preemption disabled on every fork |
| `gvwifi: 0002` init.target.rc install path + GPU boost | rc was installed to `/` but imported from `/vendor/etc/init/hw` (never ran); Mali boost 668 MHz @70% |
| `hardware/interfaces: 0001` + `gvwifi: 0003` reliable HWC1 present fences | adapter always set `PresentFenceIsNotReliable`, forcing HW vsync on permanently; s3c_fb/decon retire fences signal after the new frame latches, so gvwifi opts in (`ro.vendor.hwc.present_fence_reliable=true`). Result: `PresentFences=true`, HW vsync off, model converged |
| `kernel: 0007` stop forcing permissive | `CONFIG_SECURITY_SELINUX_PERMISSIVE` made `fs/proc/cmdline.c` inject `androidboot.selinux=permissive`, and `sel_write_enforce()` rewrote every write to 0. Now `getenforce` = Enforcing and userspace checks (property_service, servicemanager) are enforced |
| `universal7580-common: 0002/0003/0004` sepolicy | A16 HAL labels, vendor props, and rules for every denial seen: `vendor_init` may set the present-fence prop (**without it, PresentFences silently stays false under Enforcing**), smart fuel gauge `1-000b/power_supply` → `sysfs_batteryinfo`, netd↔gpsd socket tagging, ueventd `sys_nice` |
| `kernel: 0008` restore `avc_denied()` enforcement + `universal7580-common: 0005` | The gvwifi kernel stubbed `avc_denied()` to always grant, so the kernel never enforced. It's now real (shell is denied sysfs/dmesg). 0005 adds rules for denials seen under real enforcement (vendor_init /data dir search, vendor_toolbox `sys_admin` for the /efs sehash strip, quiet gpsd/tee probes) |
| `kernel: 0009` bootwatch | Safety net: if `sys.boot_completed` isn't reached within 900 s, dump all tasks and warm-restart into recovery (last_kmsg survives). Power-off/reboot requests before boot completes are also redirected to recovery. `gvwifi: 0007` disarms it on boot_completed |
| `packages/modules/Connectivity: 0001` BpfNetMaps tolerates `ENOSYS` | The 3.10 BPF backport can't delete from some map types. Every **restart** of system_server (not the first start) died in `initBpfMaps`, so one crash became a loop. On 2026-09-24 that loop corrupted `packages.xml` + its reserve copy, and PackageManager then **deleted all user apps and their data** |
| `art: 0001` JIT: mark zygote notify failed without memfd | `memfd_create` needs kernel 3.17. With `fd_methods_ == -1`, `NotifyZygoteCompilationDone()` returned without setting a state, so `PostZygoteFork` aborted zygote on the first fork after its background boot-method compile, every few minutes. Verified: 6 launches after 12 min uptime, 0 aborts |
| `frameworks/base: 0001` allow owner-signed microG Companion | Apps that query Play **Age Signals** (`finsky.ageverification.BIND`) fail with error GA-5 without it. microG added it in GmsCore master (PR #3742, release 0.3.17). The self-built Companion is signed with `keys/companion.jks` (**private**), and this patch lets only that cert, only for `com.android.vending`, use microG signature spoofing |
| `gvwifi: 0006` INT bus floor 267 MHz (init.target.rc, boot_completed) | 720p video judder: with INT devfreq at 100-160 MHz, the MSC scaler/DECON missed a vsync on ~10% of frames (TimeStats: 58 × 50 ms + 16 ms pairs per 20 s, latch2present 30 ms). With the 267 MHz floor: 582/597 frames at exactly 33 ms, 0 stutters. The present-fence A/B (fences on is ~185% vs ~198% of a core for SF+composer, same missed-frame counter) kept fences ON; ROT_180 is not a cost (HWC gets Transform None) |
| `kernel: 0012` fscrypt `FS_IOC_GET_ENCRYPTION_POLICY_EX` | declared by the fscrypt v2 backport but never implemented (`-ENOTTY`), so nothing could read back a v2 policy and TWRP Data backups lost every encryption policy |
| `kernel: 0013` FunctionFS `ffs_aio_cancel()` drops the kiocb reference | 3.10's `kiocb_cancel()` takes an extra reference the callback must drop; the backport never did, so every adbd restart leaked the open endpoint files, FunctionFS never reset, and the next adbd failed with `ESRCH` (USB adb offline after `adb root` or any USB mode switch) |
| `system/core: 0001` libprocessgroup: poll `cgroup.events` at most 5 ms at a time | the 3.10 backported `cgroup.events` never raises `POLLPRI`, so every `stop` waited the full 2200 ms; UsbDeviceManager gives `sys.usb.state=none` only 1 s, so **MTP never turned on**. Now adbd stops in 0.5 ms and MTP works |
| `hardware/interfaces: 0002` USB HAL reports a fixed device-mode port | no `dual_role_usb` class on 3.10, so the HAL reported no port and Settings greyed out all USB options |
| `3-build.sh module` (`MODULES=...`) | builds only the named modules, for on-device tests (serve a test binary from a tmpfs bind mount: `/data` is `nosuid`, which blocks the SELinux domain transition) |
| `dtimage` added to build goals | `dt.img` is only a dependency of `bootimage`, so `m recoveryimage` failed |
| ccache off by default | disk budget; also `~/.cache/ccache` got created as a file and broke every compile |
| `gvwifi: 0011` + `tools/HeliBoard` Galaxy View keyboard | HeliBoard v4.1 fork shipped as the default keyboard, matching the stock SM-T670 Samsung Keyboard, with word suggestions (see below) |
| `packages/inputmethods/LatinIME: 0001` not the default IME | Android 16 enables and selects the first system IME that is `isDefault` with a system-locale subtype, so LatinIME would otherwise win. LatinIME stays installed as an alternative (Settings > Keyboard) |
| `kernel: 0014` clear and free per-inode fscrypt/fs-verity info | the backport never cleared `i_crypt_info`/`i_verity_info` on inode reuse nor freed them on eviction: recycled inodes inherited a stale Merkle tree (silent EIO on `packages.xml`/`roles.xml`, system_server crash loop) or another file's key (data garbage after reboot) |
| `frameworks/base: 0004` default system IME with locale-less subtypes | HeliBoard declares its languages at runtime (`method_dummy.xml` has one placeholder subtype without a locale), so it could never match the system locale and first boot fell back to LatinIME. A system IME marked `isDefault` whose XML subtypes name no language now counts as covering any locale |

## Keyboard: HeliBoard, Galaxy View fork

Build the APK before the ROM (`3-build.sh` stops if it is missing):

```bash
~/gvwifi-los23/tools/HeliBoard/build.sh
```

`tools/HeliBoard/patches/0001` on HeliBoard v4.1 (AOSP LatinIME engine: suggestions,
autocorrect, built-in English dictionary, learning):

- **Layout `galaxy_view`** (default for English US) + functional keys `functional_keys_galaxy_view`:
  the stock tablet landscape layout from `SamsungIMEv2_5.apk` (`xml-sw1080dp-land`), PC-style:
  Hide/1-0/Del, Tab/qwerty/Backspace, Caps Lock/asdf/'"/Enter, Shift/zxcv/,!/.?/Up/Shift,
  Ctrl/?123/emoji/space/language/Left/Down/Right. Widths are Samsung's dp ratios. The functional
  rows line up with the number row, which is on by default.
- **Colors `Galaxy View`** (default, day and night): from the stock APK (`#CFCFD6` keypad, black
  letters, `#666666` function labels, 50 % black corner hints, `#00A0CE` shift accent); Enter is
  gray like the stock option keys. Key fills are estimates: Samsung's key images are Qmage (`.qmg`).
- **Del** is a real forward delete (`KEYCODE_FORWARD_DEL`, added to HeliBoard's key codes).
- The SM-T670 reports `config_screen_metrics` < 3, so HeliBoard's tablet check is false; the
  Galaxy View functional keys are the default unconditionally.
- Users can pick any other HeliBoard layout or colors in its settings.
- Toolchain (per-user, no sudo): `~/tools/jdk-17` (Temurin), SDK `ndk;28.0.13004108`.

## First build (2026-09-23)

The first zip (13:08) predates the partition-layout fix and **would bootloop on
this tablet** — it is kept only in `out/superseded-DO-NOT-FLASH/`.

Current: `lineage-23.2-20260923-UNOFFICIAL-gvwifi.zip` (14:08 build, 779 MB,
SHA-256 `01dd804d…e756`). SYSTEM on the tablet is 3.0 GB (system.img 1.57 GB),
boot.img 20.4/33.5 MB, recovery.img 27.7/39.8 MB. `device-check.ps1` reports
"Layout matches the build". **Boots to the setup wizard on the SM-T670**
(first boot: ~3 min black screen with backlight, then the LineageOS animation).
Installed without GApps; hardware not yet tested.

### Charging and USB (hardware facts)

- The SM-T670 **charges only from its 19 V DC barrel adapter** (3.0×1.0 mm,
  ~40 W). Micro-USB is data; the bq24773 is a buck-only charger and cannot
  charge the 3-cell (~11.6 V) pack from 5 V. The battery driver detects the
  adapter via GPIO gpa0-7 (`cable-irq`), not the MUIC. On micro-USB the
  battery shows *Discharging* — expected, not a bug.
- Micro-USB data works when plugged at boot (SM5504 MUIC → `USB DETECTED` →
  UDC enabled, high-speed). One hot-plug was classed as a dedicated charger;
  re-test after the hotplug fix.

### Runtime tuning (applied via adb, persists; redo after a factory reset)

```bash
adb shell device_config put activity_manager max_cached_processes 3
```
```bash
adb shell device_config set_sync_disabled_for_tests persistent
```
```bash
adb shell settings put system min_refresh_rate 60.0
```
```bash
adb shell settings put system peak_refresh_rate 60.0
```

- **Now set to 1** (one app at a time) — see also `disabled-apps.txt` (24
  unused system apps disabled with `pm disable-user`; `pm enable <pkg>` to undo),
  status-bar battery % on (`lineagesettings system
  status_bar_show_battery_percent=2`), plain wallpaper `solid-wallpaper.png`.
  Note: Android 16 does **not** trim cached apps for 10 min after each unlock
  following boot (`no_kill_cached_processes_post_boot_completed_duration_millis`),
  so the limit only bites ~10 min after a reboot. A lighter launcher does not
  help: Trebuchet must keep running as the Recents provider anyway.
- **max_cached_processes 3** (default 16, first step): 1080p Plex + YouTube + a third video app in
  the background filled RAM and the 1 GB zram (95 %), load hit 18 and Plex's
  UI thread ANR'd. After: swap ~65 %, no ANRs. Use `1` for one-app-at-a-time.
- **min/peak refresh 60**: SurfaceFlinger content detection kept switching the
  render rate 60↔30 Hz for 24 fps video (judder, constant "changed render
  timings" churn). Locking to 60 Hz cut SurfaceFlinger from ~153 % to ~64 %
  CPU. The remainder is inherent to HWC1-via-hwc2on1adapter
  (`PresentFenceIsNotReliable` → HW vsync always on).

### Installing apps (microG, Aurora)

- LineageOS 23.2 **userdebug** already spoofs signatures for apps signed with
  microG's official key that declare `fake-signature` (ComputerEngine.java), so
  the official microG APKs install as normal apps — no ROM patch.
- `adb install` must use **`--no-streaming`**: streamed installs fail with
  `splice failed: EINVAL` on the 3.10 kernel.
- USB data stops working after the tablet has been up a while (USB gadget
  issue, not yet investigated). Wireless debugging works: `adb pair` (code on
  the tablet), then `adb connect <ip>:<port>`.
- Installed 2026-09-23 from `apps/`: microG GmsCore 0.3.16.252432 + Companion
  0.3.16.40226 (GitHub, signer SHA-256 `9bd06727…4165`), Aurora Store 4.8.4 (F-Droid).

## Flashing plan (lowest-risk order)

1. **Stock → TWRP 3.2.1-0** (Developer options → OEM unlock; download mode =
   Power + both volume; Odin 3.10.7, AP slot, *Auto Reboot off*; then
   Power+Vol Down, switch to Vol Up when the screen blanks).
2. In TWRP: full backup (Boot, System, Data, **EFS**) to the SD card, then run
   `device-check.ps1`. If `SYSTEM` is smaller than the tree expects, fix
   `BOARD_SYSTEMIMAGE_PARTITION_SIZE` in `device/samsung/gvwifi/BoardConfig.mk`
   and rebuild.
3. **Kernel smoke test:** Odin-flash `lineage-recovery-gvwifi.tar` (AP slot) and
   boot recovery. If it shows the LineageOS Recovery menu and `adb devices`
   lists it, the 3.10 kernel + bootloader ramdisk limits are OK.
4. Recovery → *Factory reset → Format data*, then *Apply update → ADB* and
   `adb sideload lineage-23.2-*-UNOFFICIAL-gvwifi.zip`.
5. Reboot. First boot takes several minutes.

**Bootloop?** Boot back into recovery and grab logs:
`adb pull /sys/fs/pstore/console-ramoops-0` (or `/proc/last_kmsg`).
**Brick-ish?** Download mode always survives; Odin the stock SM-T670 firmware.

## Expectations

- 2 GB RAM + 32-bit A53 running Android 16 will be slow; skip GApps for the first boot.
- Camera: front-only SR261 on HAL3 — least likely thing to work.
- Upstream author's `COMMON_LUNCH_CHOICES` still say `bp2a`; ignore them.
