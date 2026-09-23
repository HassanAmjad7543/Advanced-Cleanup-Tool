# Changelog

All notable changes to Universal Software Guardian are listed here.

## [2.0] - 2026-09-23

v2.0 replaces the console script with a desktop window, makes scanning about 10x faster, and makes deletion report what really happened.

### Added
- **Desktop window (dark "Night Sidebar" design)**: no more typing in a console.
  - The sidebar shows the **Find → Review → Clean** steps and the drive picker.
  - Results are grouped under Uninstallers / Folders / Registry keys, with colour tags, counts and a tick-all checkbox for each group.
  - The live colour log is timestamped, and there is a progress bar and an "N of M selected" counter.
  - It uses Segoe UI and Cascadia Mono / Consolas, vector (SVG-path) icons and a dark title bar, and scales correctly at 125% / 150% displays.
- **`SoftwareGuardian.exe`**: a single-file app built by `build.ps1` with the C# compiler that ships with Windows.
  - It hosts PowerShell in-process with the script embedded, so no console window appears and no script is written to `%TEMP%`.
  - It asks for Administrator on launch.
- **Drive & USB picker**: scan extra fixed disks or USB sticks, not only `C:`. The drive list can be refreshed while the app is open.
- **Delete at next restart**: folders locked by a running program can be queued with Windows (`MoveFileEx` delay-until-reboot) and are removed during the next boot. Junctions and symlinks are queued themselves, never followed.
- **Lock diagnosis**: when a folder can't be deleted, the log names the process and PID running from inside it.
- **Group select-all** and a **Scan-first** flow: nothing is deleted until you click Clean and confirm.

### Changed
- **Scanning is ~10x faster** (about 18 s → 1.8 s on the test PC, same results).
  - The progress bar is now updated every 150 ms instead of on every folder, which alone saved most of the time.
  - The file sweep uses direct .NET `EnumerateDirectories` instead of `Get-ChildItem` (4x faster on identical work).
- **The verification step re-checks only what was selected** instead of repeating the whole scan.
- **The log file is UTF-8 with `[HH:mm:ss]` timestamps** (v1.0 wrote UTF-16, which most text tools can't search). It is saved next to the app, not in whatever folder it was started from.
- **`Easy-Cleanup.bat` elevates with a single `Start-Process -Verb RunAs`** instead of writing a `getadmin.vbs` helper to `%TEMP%`.
- **Faster duplicate removal**: results are de-duplicated with case-insensitive hash sets instead of `Select-Object -Unique`.

### Fixed
- **False "deleted" reports**: v1.0 logged `Deleting:` and moved on even when the folder stayed on disk. Every delete is now re-checked, and failures are reported with the reason.
- **Hidden errors**: the global `$ErrorActionPreference = "SilentlyContinue"` hid every failure. Errors are now handled where they happen.
- `C:\ProgramData` (hidden) was skipped because `Get-Item` was called without `-Force`.
- The success message appeared even when you had chosen to keep some items.
- The `.bat` file's argument passing through elevation was broken (`set params = %*:"=""`).

## [1.0] - 2026-03-28

First public release: console PowerShell script with a 4-phase clean (uninstaller, file sweep, registry engine, verification and force-purge), parent-folder safety and regex matching of names written with spaces, hyphens or underscores.
