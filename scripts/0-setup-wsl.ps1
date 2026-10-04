# Step 0 (Windows): install the Ubuntu 24.04 WSL2 distro used for the build.
# Run from PowerShell:  .\scripts\0-setup-wsl.ps1
$ErrorActionPreference = 'Stop'
$Distro  = 'Ubuntu-24.04'
$NeedGB  = 260   # ~110 GB shallow source + ~120 GB out/ + ccache headroom

# --- Disk space: the WSL disk (ext4.vhdx) lives on C: by default -----------
$free = [math]::Round((Get-PSDrive C).Free / 1GB)
Write-Host "C: free space: $free GB (need about $NeedGB GB)"
if ($free -lt $NeedGB) {
    Write-Warning "Not enough room on C: for a LineageOS 23.2 build. Free about $($NeedGB - $free) GB first."
    Write-Warning "Do not put the build on a network drive (like Z:). It is too slow, and WSL cannot keep ext4 there."
    if ((Read-Host 'Continue anyway? (y/N)') -ne 'y') { exit 1 }
}

# --- WSL resource limits (only written if you don't already have one) --------
$wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
if (Test-Path $wslconfig) {
    Write-Host ".wslconfig already exists, leaving it alone. Recommended: memory=24GB, swap=32GB, processors=16"
} else {
    @"
[wsl2]
# Android 16 builds need ~32 GB RAM+swap; leave ~7 GB for Windows.
memory=24GB
swap=32GB
processors=16
"@ | Set-Content -Encoding ascii $wslconfig
    Write-Host "Wrote $wslconfig"
    wsl --shutdown
}

# --- Install the distro ------------------------------------------------------
$installed = (wsl -l -q) -replace "`0", '' | Where-Object { $_ -eq $Distro }
if (-not $installed) {
    wsl --install -d $Distro --no-launch
    Write-Host ""
    Write-Host "Next: open '$Distro' from the Start menu once and create your Linux username and password."
    Write-Host "Then run this script again to finish."
    exit 0
}

# Sparse VHD is not enabled: WSL currently refuses it ("potential data
# corruption") unless forced with --allow-unsafe. The ext4.vhdx only grows;
# reclaim space later with `wsl --shutdown` + Optimize-VHD / diskpart compact.

# --- Copy the project into the Linux filesystem (never build under /mnt/c) ---
$proj = Split-Path -Parent $PSScriptRoot
$wslProj = (wsl -d $Distro wslpath -a ($proj -replace '\\', '/')).Trim()
wsl -d $Distro -- bash -lc "mkdir -p ~/gvwifi-los23 && cp -r '$wslProj'/. ~/gvwifi-los23/ && chmod +x ~/gvwifi-los23/scripts/*.sh"
Write-Host "Project copied to ~/gvwifi-los23 inside $Distro."
Write-Host "Next:  wsl -d $Distro -- bash -lc '~/gvwifi-los23/scripts/1-host-setup.sh'"
