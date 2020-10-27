@echo off
pushd %~dp0
git reset --hard
git pull
PowerShell.exe -NoLogo -ExecutionPolicy Bypass -File .\rndr_start7.ps1
popd