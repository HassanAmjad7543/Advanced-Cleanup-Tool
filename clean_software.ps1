param(
    [Parameter(Mandatory=$true)]
    [string]$SoftwareName,
    [switch]$DryRun
)

$ErrorActionPreference = "SilentlyContinue"
$LogFile = "cleanup_log.txt"
"========== STARTING CLEANUP: $SoftwareName ==========" | Out-File -FilePath $LogFile -Append

$GlobalExclusionList = @(
    "Windows", "System32", "SysWOW64", "WindowsPowerShell", "Microsoft", 
    "Intel", "AMD", "NVIDIA", "drivers", "System Volume Information", "Boot",
    "Common Files", "Internet Explorer", "Windows Mail", "Windows NT",
    "Windows Defender", "WindowsApps", "Recovery", "Temp", "Config.Msi",
    "Quarantine", "Defender", "Assembly", "DriverStore", "WinSxS"
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
    "[$Color] $Message" | Out-File -FilePath $LogFile -Append
}

function Get-UserSelection {
    param([string]$Prompt, [array]$Items)
    if ($Items.Count -eq 0) { return @() }
    Write-Log " " "White"
    Write-Log $Prompt "Yellow"
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $c = "Cyan"
        if ($Items[$i] -match "C:\\Windows") { $c = "Yellow" }
        Write-Host "  $($i + 1). $($Items[$i])" -ForegroundColor $c
    }
    Write-Host "  (Type 'all', 'n', or numbers like '1,3')" -ForegroundColor Gray
    $UserChoice = Read-Host "Choice"
    if ($UserChoice -eq 'all') { return $Items }
    if ($UserChoice -eq 'n' -or $UserChoice -eq '') { return @() }
    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($idx in ($UserChoice -split ',')) {
        $idx = $idx.Trim()
        if ($idx -match '^\d+$') {
            $n = [int]$idx
            if ($n -gt 0 -and $n -le $Items.Count) { $selected.Add($Items[$n-1]) }
        }
    }
    return $selected.ToArray()
}

function Force-DeleteFolder {
    param([string]$TargetPath)
    Write-Log "Deleting: $TargetPath" "Cyan"
    Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $TargetPath) { cmd.exe /c "rmdir /s /q `"$TargetPath`"" 2>$null }
    if (Test-Path -LiteralPath $TargetPath) {
        cmd.exe /c "del /f /s /q `"$TargetPath\*`" >nul 2>&1"
        cmd.exe /c "rmdir /s /q `"$TargetPath`"" 2>$null
    }
}

if ($SoftwareName.Length -lt 3) {
    Write-Log "ERROR: Name too short." "Red"
    exit
}

$StrictRegex = "(?i)\b$SoftwareName"
$FolderRegex = "(?i)^\.?\b$SoftwareName"

Write-Log "========== SOFTWARE CLEANUP: $SoftwareName ==========" "Cyan"
if ($DryRun) { Write-Log "[DRY RUN MODE ACTIVE]" "Magenta" }

# -------------------------------------------------------------------------
# Phase 1: Uninstall Phase
# -------------------------------------------------------------------------
Write-Log "[1/4] Searching for uninstallers..." "Yellow"
$unPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$appsFound = Get-ItemProperty $unPaths | Where-Object { ($_.DisplayName -match $StrictRegex) -or ($_.Publisher -match $StrictRegex) }
if ($appsFound) {
    foreach ($app in $appsFound) {
        Write-Log "FOUND: $($app.DisplayName)" "Green"
        if ($DryRun) { continue }
        $ans = Read-Host "Run uninstaller? (y/n)"
        if ($ans -eq 'y') { Start-Process cmd -ArgumentList "/c $($app.UninstallString)" -Wait }
    }
}

# -------------------------------------------------------------------------
# Phase 2: File Scan Phase
# -------------------------------------------------------------------------
Write-Log "[2/4] Searching for leftover folders..." "Yellow"
$configs = @(
    @{ Root = "$env:ProgramFiles"; Depth = 2 }, @{ Root = "${env:ProgramFiles(x86)}"; Depth = 2 },
    @{ Root = "$env:ProgramData"; Depth = 2 }, @{ Root = "$env:APPDATA"; Depth = 3 },
    @{ Root = "$env:LOCALAPPDATA"; Depth = 4 }, @{ Root = "$env:USERPROFILE"; Depth = 1 }
)
$searchRoots = $configs | ForEach-Object { $_.Root }
$targets = @()
foreach ($cfg in $configs) {
    if (Test-Path $cfg.Root) {
        $subs = Get-ChildItem -Path $cfg.Root -Directory -Force
        if ($subs) { $targets += $subs }
        $targets += Get-Item -Path $cfg.Root
    }
}
$folders = @()
for ($i = 0; $i -lt $targets.Count; $i++) {
    $t = $targets[$i]
    $p = [int](($i / $targets.Count) * 100)
    Write-Progress -Activity "[SCAN] File Search" -Status "$p% - $($t.Name)" -PercentComplete $p
    if ($GlobalExclusionList -contains $t.Name -and ($searchRoots -notcontains $t.FullName)) { continue }
    $m = Get-ChildItem -Path $t.FullName -Directory -Recurse -Depth 1 -Force | Where-Object { $_.Name -match $FolderRegex }
    if ($t.Name -match $FolderRegex) { $m += $t }
    foreach ($item in $m) {
        if ($item.FullName -match "\\(Documents|Downloads|Desktop|Pictures|Music|Videos)\\") { continue }
        if (-not ($GlobalExclusionList -contains $item.Name)) { $folders += $item.FullName }
    }
}
Write-Progress -Activity "[SCAN] File Search" -Completed
$toDel = Get-UserSelection "Select folders to delete:" ($folders | Select-Object -Unique)
foreach ($path in $toDel) { if ($DryRun) { Write-Log "DRY: $path" "Gray" } else { Force-DeleteFolder -TargetPath $path } }

# -------------------------------------------------------------------------
# Phase 3: Registry Phase
# -------------------------------------------------------------------------
Write-Log "[3/4] Scanning Registry..." "Yellow"
$regItems = @()
foreach ($h in "LocalMachine", "CurrentUser") {
    $base = [Microsoft.Win32.Registry]::$h.OpenSubKey("Software")
    $subs = $base.GetSubKeyNames()
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $n = $subs[$i]
        $p = [int](($i / $subs.Count) * 100)
        Write-Progress -Activity "[SCAN] Registry Scan" -Status "$p% - $n" -PercentComplete $p
        if ($GlobalExclusionList -contains $n) { continue }
        if ($n -match $StrictRegex) { $regItems += "HKEY_$($h.ToUpper())\Software\$n" }
        try {
            $k = $base.OpenSubKey($n)
            foreach ($s in $k.GetSubKeyNames()) { if ($s -match $StrictRegex) { $regItems += "HKEY_$($h.ToUpper())\Software\$n\$s" } }
            $k.Close()
        } catch {}
    }
}
Write-Progress -Activity "[SCAN] Registry Scan" -Completed
$toDelReg = Get-UserSelection "Select registry keys to delete:" ($regItems | Select-Object -Unique)
foreach ($kr in $toDelReg) {
    if ($DryRun) { Write-Log "DRY: $kr" "Gray" } else {
        $pPath = $kr -replace 'HKEY_CURRENT_USER', 'HKCU:' -replace 'HKEY_LOCAL_MACHINE', 'HKLM:'
        Write-Log "Deleting Key: $kr" "Cyan"; Remove-Item -LiteralPath $pPath -Recurse -Force
    }
}

# -------------------------------------------------------------------------
# Phase 4: Final Verification Phase
# -------------------------------------------------------------------------
Write-Log "[4/4] Verification Check..." "Yellow"
$rem = @()
for ($i = 0; $i -lt $targets.Count; $i++) {
    $t = $targets[$i]
    $p = [int](($i / $targets.Count) * 100)
    Write-Progress -Activity "[VERIFY] Check" -Status "$p% - $($t.Name)" -PercentComplete $p
    $m = Get-ChildItem -Path $t.FullName -Directory -Recurse -Depth 1 -Force | Where-Object { $_.Name -match $FolderRegex }
    if ($t.Name -match $FolderRegex) { $m += $t }
    foreach ($item in $m) {
        if ($item.FullName -match "\\(Documents|Downloads|Desktop|Pictures|Music|Videos)\\") { continue }
        if (-not ($GlobalExclusionList -contains $item.Name)) { $rem += $item.FullName }
    }
}
Write-Progress -Activity "[VERIFY] Check" -Completed
foreach ($h in "LocalMachine", "CurrentUser") {
    $base = [Microsoft.Win32.Registry]::$h.OpenSubKey("Software")
    $subs = $base.GetSubKeyNames()
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $n = $subs[$i]
        $p = [int](($i / $subs.Count) * 100)
        Write-Progress -Activity "[VERIFY] Registry" -Status "$p% - $n" -PercentComplete $p
        if ($GlobalExclusionList -contains $n) { continue }
        if ($n -match $StrictRegex) { $rem += "HKEY_$($h.ToUpper())\Software\$n [REGISTRY KEY]" }
        try {
            $k = $base.OpenSubKey($n)
            foreach ($s in $k.GetSubKeyNames()) { if ($s -match $StrictRegex) { $rem += "HKEY_$($h.ToUpper())\Software\$n\$s [REGISTRY KEY]" } }
            $k.Close()
        } catch {}
    }
}
Write-Progress -Activity "[VERIFY] Registry" -Completed

if ($rem.Count -gt 0) {
    $final = Get-UserSelection "STUBBORN REMNANTS DETECTED!" ($rem | Select-Object -Unique)
    foreach ($ri in $final) { 
        if ($ri -match " \[REGISTRY KEY\]$") {
            $cItem = $ri -replace " \[REGISTRY KEY\]$", ""
            $pPath = $cItem -replace 'HKEY_CURRENT_USER', 'HKCU:' -replace 'HKEY_LOCAL_MACHINE', 'HKLM:'
            Write-Log "Force Deleting Key: $cItem" "Red"
            Remove-Item -LiteralPath $pPath -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $pPath) {
                cmd.exe /c "reg delete `"$cItem`" /f >nul 2>&1"
            }
        } else {
            Force-DeleteFolder -TargetPath $ri 
        }
    }
} else { Write-Log "System is clean." "Green" }

Write-Log "========== CLEANUP FINISHED ==========" "Cyan"
Invoke-Item $LogFile
