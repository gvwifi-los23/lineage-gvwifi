# Android 17 (LineageOS 24.0) port

LineageOS 24.0 (Android 17, `cp2a`, API 37) on the Galaxy View SM-T670. The starting point is the
complete 23.2 patch series ([`BUILD-KIT.md`](BUILD-KIT.md)); this page covers only what Android 17 needed
on top. First successful boot: 2026-10-17, build `lineage-24.0-20261017-UNOFFICIAL-gvwifi.zip`.

Most of the work comes from one fact: Android 17 assumes kernel 5.10 or newer in several places, and this
tablet runs Linux 3.10.108 with backports. Kernel 3.10 has ION but no DMA-BUF heaps, no userfaultfd, and a BPF
backport at roughly the 5.4 level (no `bpf_sk_storage_get`, no ring buffers).

## Build system

| Patch | Change | Why |
|---|---|---|
| gvwifi 0013 + common 0015 | Boot image uses a **prebuilt kernel and dt.img** (`TARGET_FORCE_PREBUILT_KERNEL`, `BOARD_KERNEL_PREBUILT_DT`; `mkbootimg.mk` copies a prebuilt dt.img) | LineageOS 24 dropped GCC kernel builds; the 3.10 kernel only builds with GCC 4.9. The kernel comes from the 23.2 tree (`scripts/3-build.sh kernel` on `main`) |
| gvwifi 0014 | Device manifest `target-level="7"` | Android 17 ships compatibility matrices from level 7 up; level 5 fails the VINTF check |
| gvwifi 0012, common 0011 | HIDL light and memtrack replaced by the AIDL services; health HAL V5 | The HIDL versions are no longer accepted by the framework matrices |
| common 0012 | `libcamera_client_shim` gets `libcutils_headers` | Header no longer exported transitively |
| common 0013 | Drop the device's own `sysfs_block` type | It is now a platform type (duplicate declaration) |
| common 0014 | Audio `IModule` v4: `getFlushFromFrameSupport()` returns unsupported | New method in the v4 interface |
| `local_manifests/trim24.xml` | Removes ~40 Qualcomm projects | Not used on Exynos; cuts Soong analysis memory |

## Boot blockers, in the order they appeared

| Symptom | Cause | Fix |
|---|---|---|
| Reboot `bpfloader-failed`: `unknown func bpf_sk_storage_get` in `netd.o` | The kernel reports 5.10 to the BPF loader, so it picks the 5.10 programs, which use socket storage the backport doesn't have | gvwifi 0015 `ro.bpf.kver_override=5.4.302` (the 5.4 programs); Connectivity 0002 turns NetBpfLoad's "25Q4 requires kernel 5.10" into a warning |
| Hang at "Platform BpfLoader loading critical for healthd" | Android 17's `filterPowerSupplyEvents.o` hangs the loader on the 3.10 backport; init waits forever | build/make 0001: not shipped (the health HAL reads power-supply uevents unfiltered, as before) |
| Reboot `netd1shot-fail` (netd SIGABRT, no log) | New `netd oneshot` boot self-test; its error went to logcat, which a reboot loses | Connectivity 0003: the new loopback TCP self-test only warns, and init errors are also written to `/dev/kmsg` (survives in `/proc/last_kmsg`); common 0016 lets netd write there |
| `Failed to get program ... prog_netd_egress_stats` | Every Android 17 (26Q2) ingress/egress stats program needs kernel 5.10; the 5.4 ones stopped at 25Q4 | Connectivity 0004: the 5.4 stats programs also load on 25Q4+ (5.10+ kernels keep their own) |
| Composer aborts: `gralloc-mapper is missing` | `libui` only accepts gralloc mapper 4/5 unless built with `LEGACY_GRALLOC`; this device has mapper 2.0 | common 0017: `libui` `legacy_gralloc=true` |
| Zygote: `ValidateOatFile found read barrier state mismatch` | The boot image is compiled for the userfaultfd GC; kernel 3.10 has no userfaultfd, so ART runs the concurrent-copying GC and rejects the image | gvwifi 0016: `PRODUCT_ENABLE_UFFD_GC := false` |
| SurfaceFlinger aborts: `output buffer not gpu writeable`; every buffer allocation fails | (1) Android 17's `libion` is a stub that returns -1 unless `legacy_impl` is set. (2) Platform policy no longer labels `/dev/ion` or allows it | common 0019: `libion` `legacy_impl=true` (the real ION library); common 0018: `/dev/ion` labelled `ion_device` again and `allow domain ion_device:chr_file r_file_perms` (the pre-DMA-BUF-heap AOSP rule) |
| system_server crash loop in `BpfRingbuf<LocalNetNoteOp>` | The local-network-access and loopback event handlers open BPF ring buffers (kernel 5.10+); the constructor aborts when the map doesn't exist | Connectivity 0005: no ring buffer, no events (handlers return null, Java listener skips a null fd) |

Also rebased from 23.2: Connectivity 0001 (tolerate `ENOSYS` when clearing BPF maps) and
frameworks/base 0001 (rotation tile).

## Effects
- Without the 5.10 BPF features: no per-app local-network-access notes/metrics and no loopback
  metrics. Network access rules, data saver, firewall and traffic stats use the same 5.4 programs as 23.2.
- One allocation format the 2016 gralloc doesn't support (RGBA_FP16) still fails, only while SurfaceFlinger
  primes its shader cache; harmless.
- An upgrade from 23.2 (same release keys) keeps data and apps. TWRP 3.7.1_14-A16 decrypts `/data` after
  Android 17 has run.

## Debugging notes
- `bootwatch` (kernel 0009/0010) sends any reboot before `sys.boot_completed` to recovery and fires
  after 900 s, so a failed boot always ends in recovery with the kernel log in `/proc/last_kmsg`.
- Errors from early oneshot services are lost with logcat; route them to `/dev/kmsg` (as Connectivity 0003)
  and allow the domain to write `kmsg_device` while debugging.
- A missing SELinux label on a device node often shows **no** denial (the generic `device` type is
  dontaudited): compare `ls -Z /dev/...` and the fds in `/proc/<pid>/fd` instead.
