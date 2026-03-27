# 🚀 Universal Software Guardian (v20.0 - Professional Clean)

A powerful, high-performance PowerShell tool designed to completely uninstall software and permanently eradicate all residual files, folders, and registry keys from a Windows system.

It features state-of-the-art protections against accidental deletion and uses deep-level Windows commands to forcefully remove system-locked remnant folders.

## ✨ Advanced Features

*   **🛡️ The Golden Rule (100% Parent Safety)**: Targets exactly the matching folder name. Parents and surrounding system directories (like `Program Files` or `AppData\Roaming`) are strictly shielded and NEVER deleted.
*   **🔨 Segmented 4-Phase Arsenal**:
    1.  **Uninstaller**: Locates and launches official manufacturer uninstallers.
    2.  **Universal File Sweep**: Scans local drives, `AppData`, and hidden user-roots for branded folders.
    3.  **Turbo .NET Registry Engine**: High-speed, direct registry parsing bypassing slow native commands.
    4.  **Verification & Force-Purge**: Falls back to `cmd.exe` `rmdir /s /q` force-commands for stubborn or locked folders that survive Phase 2.
*   **📡 Modern ASCII Progress Bars**: See exact real-time percentages of registry and folder sweeps without UI-breaking encoded anomalies.
*   **🧠 Selective Eradication**: You are presented with an exact list of matching files and registry keys before anything is moved. You can delete one, all, or skip the phase entirely.
*   **🧪 Dry Run Mode**: Scan your system and see exactly what would happen without modifying a single byte.

## 🚀 Getting Started

### Method 1: The "One-Click" Launcher (Recommended)
1.  Download `Easy-Cleanup.bat` and `clean_software.ps1` to the same folder.
2.  **Double-click `Easy-Cleanup.bat`**.
3.  Choose **Scan Only** (Dry Run) or **Deep Cleanup**.

### Method 2: Manual PowerShell
Run PowerShell as Administrator:
```powershell
.\clean_software.ps1 -SoftwareName "YourAppName"
```
*(Optionally, append `-DryRun` at the end to perform a safe scan).*

## ⚠️ Requirements
*   **Windows 10 / 11**
*   **Administrator Privileges** (Required to delete system-level hooks and registry keys)

## 📜 License
This project is licensed under the **MIT License**. Build, modify, and distribute it freely for the open-source community.
