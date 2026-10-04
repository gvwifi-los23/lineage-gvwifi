# Run BEFORE flashing anything built here. Read-only on the tablet.
#
# Needs: tablet booted into TWRP 3.2.1-0 (it has root adb), USB cable,
#        adb.exe on PATH (Android SDK platform-tools).
#
# 1. Backs up EFS (IMEI/serial/MAC/calibration; cannot be regenerated) to .\backup\
# 2. Prints real partition sizes and compares them to what the 23.2 tree assumes.
$ErrorActionPreference = 'Stop'
$ByName = '/dev/block/platform/13540000.dwmmc0/by-name'

adb wait-for-recovery
$model = (adb shell getprop ro.product.model).Trim()
$device = (adb shell getprop ro.product.device).Trim()
Write-Host "Connected: model='$model' device='$device'"
if ($device -notmatch 'gvwifi' -and $model -notmatch 'T670') {
    Write-Warning "This does not look like an SM-T670 (gvwifi). Stop here."
}

# --- EFS + PIT-relevant backups ----------------------------------------------
$bk = Join-Path $PSScriptRoot "..\backup\$(Get-Date -Format yyyyMMdd-HHmm)"
New-Item -ItemType Directory -Force $bk | Out-Null
$names = (adb shell "ls $ByName") -split '\s+' | Where-Object { $_ }
adb shell "ls -l $ByName" | Set-Content (Join-Path $bk 'by-name.txt')

# Small identity/config partitions: cheap to keep, impossible to regenerate.
$backup = 'EFS','CPEFS','m9kefs1','m9kefs2','m9kefs3','PARAM','PERSDATA','PERSISTENT',
          'CARRIER','DNT','OTA','BOOT','RECOVERY'
foreach ($p in $backup) {
    if ($names -notcontains $p) { Write-Host ("Skipped   {0,-10} (not on this device)" -f $p); continue }
    adb shell "dd if=$ByName/$p of=/tmp/$p.img bs=4096 2>/dev/null"
    adb pull "/tmp/$p.img" (Join-Path $bk "$p.img") | Out-Null
    adb shell "rm /tmp/$p.img"
    Write-Host ("Backed up {0,-10} -> {1}" -f $p, $bk)
}

# --- Partition layout vs. what the build assumes ------------------------------
# Sizes from device/samsung/gvwifi/BoardConfig.mk; mmcblk numbers from
# universal7580-common sepolicy/file_contexts (as patched by this kit).
$expect = [ordered]@{
    SYSTEM   = @{ size = 3145728000; blk = 'mmcblk0p20' }
    BOOT     = @{ size = 33554432;   blk = 'mmcblk0p10' }
    RECOVERY = @{ size = 39845888;   blk = 'mmcblk0p11' }
    CACHE    = @{ size = 16777216;   blk = 'mmcblk0p21' }   # used as /metadata; needs >= 16 MB
    USERDATA = @{ size = 0;          blk = 'mmcblk0p22' }
}
$problems = 0
Write-Host ""
Write-Host ("{0,-10}{1,16}{2,16}  {3,-12} {4}" -f 'Partition','On device','Needs >=','Block dev','')
foreach ($k in $expect.Keys) {
    if ($names -notcontains $k) { Write-Host ("{0,-10}{1,16}" -f $k, 'MISSING'); $problems++; continue }
    $real = [int64](adb shell "blockdev --getsize64 $ByName/$k").Trim()
    $blk  = ((adb shell "readlink $ByName/$k").Trim() -split '/')[-1]
    $bad  = @()
    if ($real -lt $expect[$k].size) { $bad += 'TOO SMALL' }
    if ($blk -ne $expect[$k].blk)   { $bad += "expected $($expect[$k].blk): fix sepolicy/file_contexts" }
    $problems += $bad.Count
    Write-Host ("{0,-10}{1,16:N0}{2,16:N0}  {3,-12} {4}" -f $k, $real, $expect[$k].size, $blk, $(if ($bad) { $bad -join '; ' } else { 'ok' }))
}
if ($names -contains 'HIDDEN') {
    Write-Host "Note: this unit HAS a HIDDEN partition (different PIT); the kit's /metadata patch assumes it does not."
    $problems++
}
Write-Host ""
Write-Host $(if ($problems) { "!! $problems layout problem(s): do not flash until resolved." } else { "Layout matches the build." })
Write-Host ""
Write-Host "Keep $bk somewhere safe (not just this PC)."
