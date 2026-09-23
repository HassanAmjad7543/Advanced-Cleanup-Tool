@echo off
REM Opens the Software Guardian window as Administrator, without building SoftwareGuardian.exe.
REM ponytail: breaks if this folder's path contains an apostrophe ('). Upgrade path: use the .exe.
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0clean_software.ps1\"'"
