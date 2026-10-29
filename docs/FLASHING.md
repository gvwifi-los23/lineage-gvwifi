# Galaxy View SM-T670: stock to LineageOS 23.2 (Android 16), unofficial gvwifi build 2026-09-28

Everything here flashes a **Wi-Fi SM-T670 (`gvwifi`)** from Samsung stock firmware to this
build. **Doing this from stock erases the tablet.**

## What to download
| What | Where |
|---|---|
| ROM zip + SHA-256 | [lineage-gvwifi releases](https://github.com/gvwifi-los23/lineage-gvwifi/releases/latest) |
| LineageOS Recovery (Odin tar) | [lineage-recovery-gvwifi releases](https://github.com/gvwifi-los23/lineage-recovery-gvwifi/releases/latest) |
| TWRP (Odin tar), for the backup in step 1 | [twrp-gvwifi releases](https://github.com/gvwifi-los23/twrp-gvwifi/releases/latest) |
| `device-check.ps1` (EFS backup + layout check) | [`scripts/device-check.ps1`](../scripts/device-check.ps1) in this repo (or *Code > Download ZIP*) |
| Odin 3.10.7 | Samsung's Windows flasher; not hosted here, widely mirrored |
| Samsung USB driver, Android SDK Platform-Tools (adb) | Samsung and Google |
| Optional: microG Services + Companion 0.3.17 or newer | [microG releases](https://github.com/microg/GmsCore/releases) / [microg.org](https://microg.org/download.html) |

**Buttons:** the SM-T670 has no Home button. **Download mode:** power off, then hold
**Power + Volume Up + Volume Down** until the warning screen, and press **Volume Up** to continue.
**Recovery:** hold **Power + Volume Up**. **Force restart:** hold **Power + Volume Down** until the
screen goes off.

## You need
- A Windows PC with the **Samsung USB driver** and **adb** (Android SDK Platform-Tools,
  on PATH).
- A micro-USB **data** cable. The SM-T670 charges **only** from its 19 V DC barrel adapter;
  micro-USB doesn't charge it. Keep it on the adapter throughout.
- Tested on bootloader **T670UEU2APJ1** (US). The build needs the layout **without a HIDDEN
  partition** (SYSTEM 3.0 GB = p20, CACHE = p21, USERDATA = p22). Step 1 checks it.

## Steps
**0. On stock Android:** Settings > About > tap *Build number* 7x. In Developer options turn on
**OEM unlock** (if shown) and **USB debugging**. Without OEM unlock, Odin may refuse with
*"Custom binary blocked by FRP lock"*.

**1. Backup and layout check (strongly recommended; EFS can't be regenerated).**
Flash the TWRP tar from [twrp-gvwifi](https://github.com/gvwifi-los23/twrp-gvwifi/releases/latest)
with Odin (same method as step 2) and boot into TWRP (Power + Volume Up). Then on the PC, in the
folder where you saved `device-check.ps1`:
`powershell -ExecutionPolicy Bypass -File device-check.ps1`
It saves EFS and the other small partitions to a `backup\` folder and compares the real
partition sizes with what the build expects. **If it reports a mismatch (e.g. a HIDDEN
partition), stop:** this build would bootloop on that unit.

**2. Flash LineageOS recovery with Odin.**
- Power off. Hold **Power + Volume Up + Volume Down**; at the warning press **Volume Up**.
- Run Odin 3.10.7. The ID:COM box turns blue when the tablet is seen.
- *Options*: **untick Auto Reboot**. **AP** = `lineage-recovery-gvwifi.tar`. Start and wait for **PASS**.
- Hold **Power + Volume Down** until the screen goes off, then **immediately** switch to
  **Power + Volume Up** and hold until LineageOS Recovery appears.

**3. Wipe (required when coming from stock).** In recovery: *Factory reset* > **Format
data / factory reset** > confirm.

**4. Sideload the ROM.** Check the zip first:
`certutil -hashfile lineage-23.2-20261016-UNOFFICIAL-gvwifi.zip SHA256`
must match the `.sha256` file in the release (for 20261016:
`2dc6b85a0aa117557a7b3e5b86fa776a70eefa200be91107ca3eeca6866ebfc0`).
Then in recovery: *Apply update* > *Apply from ADB*, and on the PC:
`adb sideload lineage-23.2-20261016-UNOFFICIAL-gvwifi.zip`
- The PC shows the progress stopping near **47%** with `Total xfer: 1.00x`. That's **normal**.
- If the tablet says *Now send the package* but `adb devices` shows nothing, run
  `adb kill-server` on the PC and try again. If it still doesn't appear, choose *Reboot to
  recovery* on the tablet and start over from *Apply from ADB*. (Recoveries older than this
  build also needed a cable replug here; this one reconnects by itself.)

**5. Reboot.** *Reboot system now*. First boot: Samsung logo, then **several minutes of black
screen with the backlight on**, then the LineageOS animation. Don't interrupt it. If a boot
ever fails to finish, the kernel restarts into recovery after 15 minutes, with the log saved.

**6. Setup wizard.** The ROM already has the performance tuning (0.5x animations, 60 Hz,
1 cached app, battery %, core apps speed-compiled). Everything after this is optional.
- **Apps:** to install an APK (e.g. microG), turn on USB debugging again and run
  `adb install --no-streaming <file>.apk`.
- **gvwifi Tweaks** (in the app drawer): if you installed microG, open it and tap **Apply**
  to grant microG its permissions and battery exemption. It can also disable unused system
  apps (one checkbox each; untick any you use). Nothing changes until you tap Apply.
- PC alternative: [`scripts/post-install.ps1`](../scripts/post-install.ps1) does the same over adb.

## Notes
- **microG:** use official microG 0.3.17 or newer. It includes Google Play's *Age Signals*
  service, which some apps require. Builds after 20261011 no longer accept this ROM's earlier
  maintainer-built Companion. If you installed it, uninstall `com.android.vending` first (the signatures differ), then install the
  official one. Apps installed before the new Companion may show a Google Play license error;
  reinstalling them fixes it.
- Aurora's home page may crash (Aurora bug). Use search, or open an app page from the PC:
  `adb shell am start -a android.intent.action.VIEW -d market://details?id=<package> -p com.aurora.store`
- Updating later: sideload the new zip from recovery, no wipe needed (but see below for
  builds up to 20261004).
- Userdebug build, signed with the maintainer's release keys (release-keys).

## Upgrading from an earlier build of this ROM
**1. Recovery (once).** Recoveries from before this build lose USB after the first sideload
(fixed in this kernel). Flash `lineage-recovery-gvwifi.tar` with Odin (step 2
above). If you skip this, the sideload still works: if the PC loses the tablet afterward,
tap *Reboot system now*.

**2. Sideload the ROM** (step 4 above). From 20261005 on no wipe is needed between builds, but
builds up to 20261004 had a kernel bug (fixed by kernel 0014) that could save files with the wrong encryption key, so a **clean install (Format Data)** is recommended once when coming from them.

**3. Tuning.** The performance tuning is set as a *default*, so it only takes effect on a
fresh install. Upgraded tablets keep their old settings. Open **gvwifi Tweaks** from the app
drawer (it comes with this build), keep *Performance* ticked, and tap **Apply**. It sets 0.5x
animations and battery percentage. The same screen also handles microG permissions and
unused system apps. Apps you disabled can be turned back on in Settings > Apps > (show
system) > Enable.

## What this build is
LineageOS 23.2 from the github.com/gvwifi trees plus the patches in `gvwifi-los23\patches`
(full list in `CHANGELOG.md`):
- Freeze fixes (USB s3c_udc deadlock, cluster hotplug).
- **Real SELinux enforcing**.
- A boot watchdog (recovery and charger aware).
- Crash-loop fixes (BpfNetMaps `ENOSYS`, ART zygote JIT without `memfd_create`).
- Present fences, INT bus floor (no video judder), CPU/GPU ramp tuning.
- Low-RAM tuning, built in as defaults.
- **gvwifi Tweaks** setup app. USB reconnects after mode switches (sideload), and MTP file transfer works.
