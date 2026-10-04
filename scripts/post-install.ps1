# OPTIONAL. Run after the ROM has booted to the home screen (setup wizard finished)
# and USB debugging is enabled (Settings > About > tap Build number 7x, then
# Developer options > USB debugging). Needs adb.exe on PATH.
#
# The ROM already ships this build's performance tuning as defaults: 0.5x
# animations, 60 Hz, 1 cached background app, battery %, and the launcher,
# SystemUI, Settings and keyboard compiled for speed.
#
# This script only does what a ROM can't decide for you:
#   - grants microG its permissions, if microG is installed
#   - disables unused system apps from disabled-apps.txt (saves RAM; edit the
#     list first if you use any of them, e.g. Calendar, Recorder, Backup)
# It installs no apps, never launches apps, and waits until the tablet is idle.
$ErrorActionPreference = 'Stop'

function Sh([string]$cmd) { (adb shell $cmd) -join "`n" }
function Installed([string]$pkg) { (Sh "pm path $pkg") -match 'package:' }

Write-Host 'Waiting for the tablet (allow USB debugging on its screen)...'
adb wait-for-device
while ((Sh 'getprop sys.boot_completed').Trim() -ne '1') { Start-Sleep 3 }

Write-Host 'Waiting until the system is idle (load < 2)...'
for ($i = 0; $i -lt 100; $i++) {
    $load = [double](((Sh 'cat /proc/loadavg').Trim() -split '\s+')[0])
    if ($load -lt 2) { break }
    Start-Sleep 6
}
Write-Host "  load now $load"

# --- microG (only if already installed) ---------------------------------------
if (Installed 'com.google.android.gms') {
    Write-Host 'microG found: permissions + battery exemption'
    foreach ($perm in 'ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION','ACCESS_BACKGROUND_LOCATION',
                      'READ_PHONE_STATE','GET_ACCOUNTS','POST_NOTIFICATIONS','READ_CONTACTS') {
        adb shell pm grant com.google.android.gms android.permission.$perm 2>$null
    }
    adb shell dumpsys deviceidle whitelist +com.google.android.gms | Out-Null
} else {
    Write-Host 'microG not installed: skipping its permissions'
}

# --- unused system apps -------------------------------------------------------
Write-Host 'Disabling unused system apps (disabled-apps.txt)'
Get-Content (Join-Path $PSScriptRoot 'disabled-apps.txt') |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object { adb shell pm disable-user --user 0 $_.Trim() | Out-Null }

Write-Host ''
Write-Host 'Done.'
Write-Host '  - Re-enable any of them later with: adb shell pm enable <package>'
Write-Host '  - Installing apps from a PC: adb install --no-streaming <app>.apk   (kernel 3.10 splice bug)'
Write-Host '  - Rerun this script after installing microG to grant its permissions.'
