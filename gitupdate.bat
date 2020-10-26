@echo off
pushd %~dp0
git reset --hard
git pull
popd