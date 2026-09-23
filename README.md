# 🚀 Universal Software Guardian (v2.5)

A powerful, high-performance Windows tool that completely uninstalls software and permanently removes every leftover file, folder and registry key it leaves behind.

It's a **one-window desktop app**: pick a program from your installed list (or type the name of one already removed), click **Scan**, untick anything you want to keep, click **Clean**. No commands to type. See [CHANGELOG.md](CHANGELOG.md) for everything that changed in each version.

## ✨ Features

*   **📋 Installed Programs List** *(new in 2.5)*: the app opens on everything installed on your PC, the same list "Apps & features" shows, with each program's **icon, publisher, version and size**.
    *   Type to filter it; double-click a program (or select it and press **Scan**) to start.
    *   Picking from the list also finds the program's own install folder, even when its name doesn't match.
    *   Still works for leftovers: type the name of a program that's already uninstalled and press **Scan**.
    *   **Back** returns to the list from the results.
*   **🖥️ One-Window App**: A dark "Night Sidebar" window in the style of CCleaner, in a neutral black theme.
    *   **Sidebar steps**: **Find → Review → Clean** light up as you go and finish with *verified clean*.
    *   **Grouped results**: Uninstallers, Folders and Registry keys, each with a colour tag and a count. Tick a group header to select or clear the whole group.
    *   **Live colour log**: every action is timestamped in the window and saved to `cleanup_log.txt`.
    *   Built with Windows' own fonts (Segoe UI, Cascadia Mono / Consolas) and vector icons, and stays sharp at 125% / 150% display scaling.
    *   **Fast and smooth** *(2.5)*: icons and sizes load in the background, the list scrolls smoothly, and the window never appears half-drawn.
*   **🛡️ The Golden Rule (100% Parent Safety)**: Targets exactly the matching folder name. Parents and system directories (like `Program Files` or `AppData\Roaming`) are shielded and NEVER deleted, and personal folders (Documents, Downloads, Desktop, Pictures, Music, Videos) are always skipped.
*   **🔨 The Cleanup Pipeline**:
    1.  **Uninstaller**: Finds and launches the official manufacturer uninstaller.
    2.  **Universal File Sweep**: Scans `Program Files`, `ProgramData`, `AppData`, your user folder and any extra drives you pick, using direct .NET enumeration (about 10x faster than v1.0).
    3.  **Turbo .NET Registry Engine**: Direct registry parsing of `HKLM\Software` and `HKCU\Software`.
    4.  **Verification**: After cleaning it scans again, so the list shows exactly what is left.
*   **♻️ Delete at Next Restart**: A folder a running program keeps locked can be queued with Windows. Windows removes it during boot, before any program can lock it again.
*   **💾 Drive & USB Picker**: Lists every fixed disk and attached USB drive with its free space and a usage bar (red when over 90% full). The system drive is always scanned and extras are opt-in: click a drive to tick it. **Refresh** picks up a USB stick plugged in later.
*   **🔍 Honest Deletion Reporting**: Every delete is re-checked on disk. If a folder survives, the log says so and names the **process and PID holding it open** instead of silently reporting success.
*   **🧪 Scan First**: **Scan** only lists what it found. Nothing is removed until you click **Clean** and confirm.

## 🚀 Getting Started

### Method 1: `SoftwareGuardian.exe` (Recommended)
1.  Download `SoftwareGuardian.exe` from the [latest release](https://github.com/HassanAmjad7543/Advanced-Cleanup-Tool/releases/latest), or build it yourself (below).
2.  **Double-click it** and allow the Administrator prompt.
3.  Double-click a program in the list (or type the name of one already removed and click **Scan**), untick anything to keep, then click **Clean**.

The exe is a single file with the script built in, so it runs on any Windows 10/11 PC on its own. It is not code-signed, so Windows SmartScreen may show *"Windows protected your PC"* the first time: click **More info → Run anyway**.

**Building the exe:** right-click `build.ps1` → **Run with PowerShell**. It uses the C# compiler that ships with Windows, so there is nothing to install. Rebuild after changing `clean_software.ps1`.

### Method 2: `Easy-Cleanup.bat` (no build needed)
Keep `Easy-Cleanup.bat` and `clean_software.ps1` in the same folder and double-click the `.bat`. It asks for Administrator and opens the same window.

## 📁 Project Files

| File | What it is |
|---|---|
| `clean_software.ps1` | The whole app: scan and clean logic plus the window |
| `launcher.cs` | Tiny C# host that runs the embedded script inside `SoftwareGuardian.exe` |
| `build.ps1` | Builds `SoftwareGuardian.exe` (Administrator + high-DPI manifest) |
| `Easy-Cleanup.bat` | Opens the window as Administrator without building the exe |
| `CHANGELOG.md` | What changed in each version |

## ⚠️ Requirements
*   **Windows 10 / 11**
*   **Administrator Privileges**: both launchers ask for them automatically. They are needed to delete system-level folders and registry keys, and to queue deletes for the next restart.

## 📜 License
This project is licensed under the **MIT License**. Build, modify, and distribute it freely for the open-source community.
