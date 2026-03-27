@echo off
setlocal

>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"

cls
echo ============================================================
echo           ADVANCED SOFTWARE CLEANUP TOOL (v1.0)
echo ============================================================
echo.
echo  1. Deep Cleanup (Delete Remnants)
echo  2. Scan Only (Dry Run - No Changes)
echo.
set /p mode="Select operation [1-2]: "

set dry_run=
if "%mode%" == "2" set dry_run=-DryRun

echo.
set /p SoftwareName="Enter the name of the software to clean (min 3 chars): "

if "%SoftwareName%" == "" (
    echo ERROR: No name entered.
    pause
    exit /B
)

echo.
echo Searching for "%SoftwareName%"...
if "%dry_run%" NEQ "" echo [DRY RUN MODE ENABLED]
echo.

powershell.exe -ExecutionPolicy Bypass -File "clean_software.ps1" -SoftwareName "%SoftwareName%" %dry_run%

echo.
echo ============================================================
echo Operation Finished. Review the log file for details.
echo ============================================================
pause
