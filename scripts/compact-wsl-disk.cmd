@echo off
rem Shrink the WSL Ubuntu disk file so space freed inside Linux returns to C:.
rem Run as Administrator (right-click -> Run as administrator). Takes a few minutes.
rem Usage: compact-wsl-disk.cmd [distro]   (default Ubuntu-24.04)
set DISTRO=%~1
if "%DISTRO%"=="" set DISTRO=Ubuntu-24.04
rem WSL records each distro's folder under HKCU\...\Lxss\{id}\BasePath
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "(Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | Get-ItemProperty | Where-Object DistributionName -eq '%DISTRO%').BasePath"`) do set BASE=%%P
if "%BASE%"=="" (echo WSL distro %DISTRO% not found & pause & exit /b 1)
set VHD=%BASE:\\?\=%\ext4.vhdx
if not exist "%VHD%" (echo %VHD% not found & pause & exit /b 1)
echo Disk: %VHD%

wsl --shutdown
for %%A in ("%VHD%") do echo Before: %%~zA bytes

(
echo select vdisk file="%VHD%"
echo attach vdisk readonly
echo compact vdisk
echo detach vdisk
) > "%TEMP%\compact-wsl.txt"
diskpart /s "%TEMP%\compact-wsl.txt"
del "%TEMP%\compact-wsl.txt"

for %%A in ("%VHD%") do echo After:  %%~zA bytes
pause
