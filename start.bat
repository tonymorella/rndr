@echo off
pushd %~dp0
PowerShell.exe -NoLogo -ExecutionPolicy Bypass -File .\kill.ps1
REM PowerShell.exe -ExecutionPolicy Bypass -File .\Start-Cleanup.ps1
PowerShell.exe -NoLogo -ExecutionPolicy Bypass -File .\rndr_start7.ps1
popd
