param(
    # Where cleanup_log.txt goes; SoftwareGuardian.exe passes its own folder.
    [string]$LogDir = $PSScriptRoot
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$LogFile = Join-Path $LogDir "cleanup_log.txt"

$Excl = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
    "Windows", "System32", "SysWOW64", "WindowsPowerShell", "Microsoft",
    "Intel", "AMD", "NVIDIA", "drivers", "System Volume Information", "Boot",
    "Common Files", "Internet Explorer", "Windows Mail", "Windows NT",
    "Windows Defender", "WindowsApps", "Recovery", "Temp", "Config.Msi",
    "Quarantine", "Defender", "Assembly", "DriverStore", "WinSxS",
    '$RECYCLE.BIN'
), [System.StringComparer]::OrdinalIgnoreCase)

$UserDataRx = [regex]::new('\\(Documents|Downloads|Desktop|Pictures|Music|Videos)\\', 'IgnoreCase, Compiled')

# ---- Look: flat dark palette, Windows' own fonts, icons drawn from SVG path data ----
function Hex([string]$H) { [System.Drawing.ColorTranslator]::FromHtml($H) }
# Display scale (1.5 at 150%). The layout is written for 96 DPI and scaled once; owner-drawn parts use Px.
$Dpi = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96
function Px([float]$V) { [int]($V * $Dpi) }
$Palette = @{ White = '#E0E0E0'; Gray = '#6C6C6C'; Cyan = '#2A74E0'; Green = '#34A062'; Red = '#C0303C'; Yellow = '#C2900F'; Orange = '#E36A3A' }
$Tags = @{
    Uninstaller = @{ Tag = 'UNINST'; Color = '#E36A3A'; Group = 'Uninstallers' }
    Folder      = @{ Tag = 'DIR';    Color = '#C2900F'; Group = 'Folders' }
    Registry    = @{ Tag = 'REG';    Color = '#5A7FA3'; Group = 'Registry keys' }
}
$Mono = if ([System.Drawing.FontFamily]::Families.Name -contains 'Cascadia Mono') { 'Cascadia Mono' } else { 'Consolas' }
$Fonts = @{
    Body  = New-Object System.Drawing.Font('Segoe UI', 9.75)
    Small = New-Object System.Drawing.Font('Segoe UI', 8.25)
    Semi  = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    Title = New-Object System.Drawing.Font('Segoe UI Semibold', 11.25)
    Input = New-Object System.Drawing.Font('Segoe UI', 12)
    Mono  = New-Object System.Drawing.Font($Mono, 9)
    Tag   = New-Object System.Drawing.Font($Mono, 7.5, [System.Drawing.FontStyle]::Bold)
}
# 24x24 stroke icons, absolute M/L/C/Z commands only.
$Icons = @{
    Shield  = 'M12 2 L20 5 L20 11 C20 16 16.5 20 12 22 C7.5 20 4 16 4 11 L4 5 Z M8.5 12 L11 14.5 L15.5 9.5'
    Check   = 'M5 12 L10 17 L19 7'
    Search  = 'M18 11 C18 14.87 14.87 18 11 18 C7.13 18 4 14.87 4 11 C4 7.13 7.13 4 11 4 C14.87 4 18 7.13 18 11 Z M16 16 L21 21'
    Refresh = 'M20 12 C20 16.42 16.42 20 12 20 C7.58 20 4 16.42 4 12 C4 7.58 7.58 4 12 4 C14.5 4 16.7 5.1 18.2 6.9 M18.5 2.5 L18.5 7.5 L13.5 7.5'
    Trash   = 'M4 7 L20 7 M9 7 L9 4 L15 4 L15 7 M6 7 L7 20 L17 20 L18 7 M10 11 L10 16.5 M14 11 L14 16.5'
    App     = 'M4 5 L20 5 L20 19 L4 19 Z M4 9 L20 9'
    Back    = 'M20 12 L5 12 M11 6 L5 12 L11 18'
}

function Draw-Svg($G, [string]$D, [float]$X, [float]$Y, [float]$Size, [string]$Color, [float]$Stroke = 2) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $t = @([regex]::Matches($D, '[MLCZ]|-?[\d.]+') | ForEach-Object Value)
    for ($i = 0; $i -lt $t.Count) {
        switch -CaseSensitive ($t[$i]) {
            'M' { $path.StartFigure(); $pt = [System.Drawing.PointF]::new($t[$i+1], $t[$i+2]); $i += 3 }
            'L' { $q = [System.Drawing.PointF]::new($t[$i+1], $t[$i+2]); $path.AddLine($pt, $q); $pt = $q; $i += 3 }
            'C' { $q = [System.Drawing.PointF]::new($t[$i+5], $t[$i+6])
                  $path.AddBezier($pt, [System.Drawing.PointF]::new($t[$i+1], $t[$i+2]), [System.Drawing.PointF]::new($t[$i+3], $t[$i+4]), $q); $pt = $q; $i += 7 }
            'Z' { $path.CloseFigure(); $i++ }
        }
    }
    $m = New-Object System.Drawing.Drawing2D.Matrix; $m.Translate($X, $Y); $m.Scale($Size / 24, $Size / 24); $path.Transform($m)
    $pen = New-Object System.Drawing.Pen((Hex $Color), $Stroke)
    $pen.StartCap = $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
    $G.SmoothingMode = 'AntiAlias'; $G.DrawPath($pen, $path)
    $pen.Dispose(); $path.Dispose()
}

function New-SvgIcon([string]$D, [int]$Size, [string]$Color) {
    $px = Px $Size
    $bmp = New-Object System.Drawing.Bitmap($px, $px)
    $g = [System.Drawing.Graphics]::FromImage($bmp); Draw-Svg $g $D 0 0 $px $Color ($px / 12); $g.Dispose()
    $bmp
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $stamp = Get-Date -Format 'HH:mm:ss'
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.SelectionColor = Hex $Palette[$Color]
    $logBox.AppendText("[$stamp] $Message`r`n")
    [System.Windows.Forms.Application]::DoEvents()
    "[{0}] [{1}] {2}" -f $stamp, $Color, $Message | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# ponytail: scans run on the UI thread and pump messages every 150 ms, so the window repaints but
# closing it mid-scan isn't handled. Upgrade path: move Invoke-Scan into a background runspace.
$ProgressTimer = [System.Diagnostics.Stopwatch]::StartNew()
function Update-ScanProgress([int]$Index, [int]$Total) {
    if ($ProgressTimer.ElapsedMilliseconds -lt 150) { return }
    $ProgressTimer.Restart()
    $barFill.Width = [int]($bar.Width * $Index / $Total)
    [System.Windows.Forms.Application]::DoEvents()
}

# Sidebar steps: 0 Find, 1 Review, 2 Clean; 3 = all done.
function Set-Step([int]$Now, [string[]]$Subs) {
    $script:StepNow = $Now; $script:StepSubs = $Subs
    $stepsPanel.Refresh()
}

function Update-Count {
    $countLabel.Text = "{0} of {1} selected" -f @($list.CheckedItems | Where-Object Tag).Count, @($list.Items | Where-Object Tag).Count
}

function Ask([string]$Text) {
    [System.Windows.Forms.MessageBox]::Show($Text, $form.Text, 'YesNo', 'Question') -eq 'Yes'
}

# Returns $true only when the folder is actually gone; logs the real reason when not.
function Force-DeleteFolder {
    param([string]$TargetPath)

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-Log "Already gone: $TargetPath" "Gray"
        return $true
    }
    Write-Log "Deleting: $TargetPath" "Cyan"

    Remove-Item -LiteralPath $TargetPath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable lastError
    if (-not (Test-Path -LiteralPath $TargetPath)) { Write-Log "  OK - deleted." "Green"; return $true }

    cmd.exe /c "rmdir /s /q `"$TargetPath`"" 2>$null | Out-Null
    if (-not (Test-Path -LiteralPath $TargetPath)) { Write-Log "  OK - deleted (rmdir fallback)." "Green"; return $true }

    Write-Log "  FAILED - folder still exists: $TargetPath" "Red"

    # A process running inside the folder is the likeliest cause; check it before $lastError.
    $lockers = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($TargetPath, [System.StringComparison]::OrdinalIgnoreCase)
    })
    if ($lockers.Count -gt 0) {
        Write-Log "    Reason: a program running from inside this folder still holds it open." "Red"
        foreach ($p in $lockers) { Write-Log "    LOCKED BY: $($p.ProcessName) (PID $($p.Id))" "Yellow" }
        Write-Log "    Close the program(s) above, then run the cleanup again." "Yellow"
    } else {
        if ($lastError) { Write-Log "    Reason: $($lastError[0].Exception.Message)" "Red" }
        Write-Log "    No process found inside this folder - a service, driver or open handle may hold it. Reboot and re-run." "Yellow"
    }
    return $false
}

# Same contract as Force-DeleteFolder, for registry keys given in HKEY_* form.
function Force-DeleteRegistryKey {
    param([string]$KeyPath)

    $psPath = "Registry::$KeyPath"
    if (-not (Test-Path -LiteralPath $psPath)) {
        Write-Log "Already gone: $KeyPath" "Gray"
        return $true
    }
    Write-Log "Deleting Key: $KeyPath" "Cyan"

    Remove-Item -LiteralPath $psPath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable lastError
    if (-not (Test-Path -LiteralPath $psPath)) { Write-Log "  OK - key deleted." "Green"; return $true }

    cmd.exe /c "reg delete `"$KeyPath`" /f >nul 2>&1" | Out-Null
    if (-not (Test-Path -LiteralPath $psPath)) { Write-Log "  OK - key deleted (reg delete fallback)." "Green"; return $true }

    Write-Log "  FAILED - key still exists: $KeyPath" "Red"
    if ($lastError) { Write-Log "    Reason: $($lastError[0].Exception.Message)" "Red" }
    Write-Log "    This key usually needs SYSTEM rights or is protected by a running service." "Yellow"
    return $false
}

# A locked folder can't be deleted now, but Windows can delete it at the next boot,
# before any program gets to lock it again. Needs Administrator (the queue lives in HKLM).
function Register-DeleteOnReboot {
    param([string]$TargetPath)
    $files = [System.Collections.Generic.List[string]]::new()
    $dirs  = [System.Collections.Generic.List[string]]::new()
    $stack = [System.Collections.Generic.Stack[string]]::new(); $stack.Push($TargetPath)
    while ($stack.Count -gt 0) {
        $d = $stack.Pop(); $dirs.Add($d)
        try {
            # Queue a junction/symlink itself, never walk into it - that would delete what it points at.
            if (([System.IO.File]::GetAttributes($d) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $files.AddRange([System.IO.Directory]::GetFiles($d))
            foreach ($s in [System.IO.Directory]::GetDirectories($d)) { $stack.Push($s) }
        } catch { }
    }
    $dirs.Reverse()   # boot-time deletes run in queue order: files, then folders deepest-first
    # 4 = MOVEFILE_DELAY_UNTIL_REBOOT; a NULL destination means "delete".
    $failed = @(@($files) + @($dirs) | Where-Object { -not [Win32.Ui]::MoveFileEx($_, [NullString]::Value, 4) }).Count
    if ($failed -eq 0) { Write-Log "  QUEUED - will be deleted at next restart: $TargetPath" "Orange" }
    else { Write-Log "  Could not queue $failed item(s) for deletion at restart - run as Administrator." "Red" }
}

# Two-level walk via raw .NET enumeration (~4x faster than Get-ChildItem).
function Add-MatchingFolders([string]$TargetPath) {
    try { $level0 = [System.IO.Directory]::EnumerateDirectories($TargetPath) } catch { return }
    foreach ($d0 in $level0) {
        try { $level1 = @([System.IO.Directory]::EnumerateDirectories($d0)) } catch { $level1 = @() }
        foreach ($d in @($d0) + $level1) {
            $n = [System.IO.Path]::GetFileName($d)
            if ($FolderRx.IsMatch($n) -and -not $Excl.Contains($n) -and -not $UserDataRx.IsMatch($d)) { [void]$folderSet.Add($d) }
        }
    }
}

# Results arrive grouped by type, so a type's header row (Name = type, no Tag) goes in before its first item.
# Value: a path or key, or for an uninstaller its registry entry. Leftover guesses come in unticked.
function Add-Result([string]$Type, [string]$Text, $Value = $Text, [bool]$Checked = $true) {
    if (-not $list.Items.ContainsKey($Type)) { $list.Items.Add($Type, $Tags[$Type].Group, -1).Checked = $Checked }
    $item = $list.Items.Add($Type)
    [void]$item.SubItems.Add($Text)
    $item.Tag = $Value
    $item.Checked = $Checked
}

function Get-FolderBytes([string]$Dir) {
    $bytes = 0
    try { foreach ($f in ([IO.DirectoryInfo]$Dir).EnumerateFiles('*', 'AllDirectories')) { $bytes += $f.Length } } catch {}
    $bytes
}
function Format-Size([double]$Bytes) { if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) } else { '{0:N0} MB' -f [Math]::Max(1, $Bytes / 1MB) } }

# Windows' "installed programs" lists (64-bit, 32-bit, current user).
$UninstallKeys = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                 "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                 "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"

# Same programs "Apps & features" shows: skips system components, updates and entries with no uninstaller.
function Get-InstalledPrograms {
    Get-ItemProperty $UninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.UninstallString -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName } |
        Sort-Object DisplayName -Unique
}

# Fills the program list with the programs whose name contains the search text.
function Show-Programs {
    $f = $nameBox.Text.Trim()
    $sorted = switch ($script:SortBy) {
        'Size'   { $Programs | Sort-Object { [double]$SizeCache[$_.DisplayName] } -Descending }   # unknown sizes last
        'Newest' { $Programs | Sort-Object InstallDate -Descending }                             # yyyyMMdd, so text order works
        default  { $Programs }                                                                   # already by name
    }
    $apps.BeginUpdate(); $apps.Items.Clear()
    foreach ($p in $sorted) {
        if ($p.DisplayName.IndexOf($f, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $it = $apps.Items.Add($p.DisplayName); $it.Tag = $p
            [void]$it.SubItems.Add(((@($p.Publisher, $p.DisplayVersion) | Where-Object { $_ }) -join '   '))   # the row's second line
        }
    }
    $apps.EndUpdate()
    # Program screen: Scan, Sort and Find leftovers apply here; Clean and Back belong to the results.
    $list.Visible = $cleanBtn.Visible = $backBtn.Visible = $false; $apps.Visible = $sortBox.Visible = $leftBtn.Visible = $true
    $scanBtn.Text = "Scan"; $script:Leftovers = $false
    $countLabel.Text = "$($apps.Items.Count) installed - Ctrl+click to pick several"
}

# Results screen: swaps the program list and its buttons for the results and Back / Clean.
function Show-Results {
    $list.Items.Clear(); $apps.Visible = $sortBox.Visible = $leftBtn.Visible = $false; $list.Visible = $cleanBtn.Visible = $backBtn.Visible = $true
    $scanBtn.Text = "Rescan"
}

# Several programs picked (Ctrl+click): each gets its own Scan -> review -> Clean, one after another.
function Start-Queue($Picks) { $script:Queue = @($Picks); $script:QueueTotal = $script:Queue.Count; Select-Next }
function Select-Next {
    $p = $script:Queue[0]; $script:Queue = @($script:Queue | Select-Object -Skip 1)
    if ($script:QueueTotal -gt 1) { Write-Log "Program $($script:QueueTotal - $script:Queue.Count) of $($script:QueueTotal): $($p.DisplayName)" "Cyan" }
    Select-Program $p
}

# Folders in the usual install places that no installed program claims: leftovers of programs
# removed long ago. It's a guess by name, so they're listed unticked for you to review.
# Folders changed in the last 30 days are skipped: something still uses them.
# ponytail: matched on the letters of program names, publishers and install folders; a vendor folder
# with an unrelated name shows up as a false hit. Upgrade path: a list of known Windows/vendor folders.
$SystemDirRx = [regex]::new('^(Microsoft|Windows|Package|regid\.|USO|ssh$|Comms$|ConnectedDevicesPlatform|CrashDumps|D3DSCache|Publishers|PeerDistRepub|History$|VirtualStore|IsolatedStorage|NuGet|dotnet|Reference Assemblies|MSBuild|ModifiableWindowsApps|PowerShell|Programs$|SoftwareGuardian|SoftwareDistribution|Uninstall Information|RUXIM|Deployment$|(Elevated)?Diagnostics$|PlaceholderTileLogoFolder|ToastNotificationManagerCompat|speech$|Backup$|Apps$|State$|User Data$|cache$|SquirrelTemp|ProductData|\{?[0-9A-F]{8}-[0-9A-F-]{27}\}?$)', 'IgnoreCase')
function Find-Leftovers {
    Show-Results; $script:Leftovers = $true
    Write-Log "========== LEFTOVERS: folders no installed program claims ==========" "Cyan"
    # What claims a folder: program names and publishers, the last folder and file names of their install,
    # icon and uninstaller paths ("...\Internet Download Manager\IDMan.exe" claims "IDM"), and Store apps.
    $keys = @(foreach ($p in $Programs) {
            $p.DisplayName; $p.Publisher
            foreach ($path in $p.InstallLocation, $p.DisplayIcon, $p.UninstallString) { @("$path" -split '[\\"]' | Where-Object { $_ } | Select-Object -Last 2) -replace '\.(exe|ico|dll).*$' }
        }
        (Get-AppxPackage -ErrorAction SilentlyContinue).Name) |
        ForEach-Object { ("$_" -replace '[^A-Za-z]').ToLower() } | Where-Object { $_.Length -ge 3 } | Sort-Object -Unique
    # One string and one regex instead of a loop per folder: "folder is part of a key" / "a key is part of the folder".
    $joined = '|' + ($keys -join '|') + '|'
    $keyRx = [regex]::new(($keys -join '|'))
    $n = 0; $recent = (Get-Date).AddDays(-30)
    $roots = $env:APPDATA, $env:LOCALAPPDATA, $env:ProgramData, $env:ProgramFiles, ${env:ProgramFiles(x86)}
    for ($i = 0; $i -lt $roots.Count; $i++) {
        $barFill.Width = [int]($bar.Width * ($i + 1) / $roots.Count); [System.Windows.Forms.Application]::DoEvents()   # once per root
        foreach ($d in Get-ChildItem -LiteralPath $roots[$i] -Directory -Force -ErrorAction SilentlyContinue) {
            $k = ($d.Name -replace '[^A-Za-z]').ToLower()
            if ($k.Length -lt 3 -or $d.LastWriteTime -gt $recent -or ($d.Attributes -band 'ReparsePoint') -or $Excl.Contains($d.Name) -or $SystemDirRx.IsMatch($d.Name)) { continue }
            if (-not $joined.Contains($k) -and -not $keyRx.IsMatch($k)) { Add-Result "Folder" $d.FullName -Checked $false; $n++ }
        }
    }
    $barFill.Width = 0; Update-Count
    Set-Step $(if ($n) { 1 } else { 0 }) @('leftovers', "$n found", 'then verify')
    Write-Log $(if ($n) { "Found $n folder(s) no installed program claims. They're unticked: tick only what you recognise, then click Clean." } else { "No leftovers found." }) $(if ($n) { "Yellow" } else { "Green" })
}

# Scans for a program picked from the list, searching by its name without the version.
function Select-Program($P) {
    # "LM Studio 0.4.8+1" -> "LM Studio", "7-Zip 23.01 (x64)" -> "7-Zip"
    $nameBox.Text = ($P.DisplayName -replace '\s*\(.*?\)|\s+v?\d+(\.\d+)+.*$', '').Trim(' ', '-')
    $script:Picked = $P   # set after the text: typing clears it
    Invoke-Scan
}

# Fills the drives list. The system drive is always scanned, so it's shown ticked and locked.
function Update-Drives {
    $was = @($drivesBox.Items | ForEach-Object Tag | Where-Object Pick | ForEach-Object Root)   # keep ticks across Refresh
    $drivesBox.Items.Clear()
    # DriveInfo is instant; WMI (Win32_LogicalDisk) took ~1.5 s. IsReady skips empty card readers.
    foreach ($v in [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -in 'Fixed', 'Removable' }) {
        $usb = $v.DriveType -eq 'Removable'
        $d = [pscustomobject]@{
            Root = $v.Name; System = $v.Name.TrimEnd('\') -eq $env:SystemDrive; Usb = $usb
            Label = if ($v.VolumeLabel) { $v.VolumeLabel } elseif ($usb) { 'USB drive' } else { 'Local disk' }
            Free = $v.AvailableFreeSpace / 1GB; Size = $v.TotalSize / 1GB
            Pick = $v.Name.TrimEnd('\') -eq $env:SystemDrive -or $was -contains $v.Name
        }
        $drivesBox.Items.Add($d.Root).Tag = $d
    }
}

# Lists what would be removed; deletes nothing. Also the verification step after Clean.
function Invoke-Scan {
    $name = $nameBox.Text.Trim()
    if ($name.Length -lt 3) { [void][System.Windows.Forms.MessageBox]::Show("Type at least 3 letters of the program name.", $form.Text); return }
    Show-Results
    # Spaces, hyphens and underscores match each other, so "LM Studio" also finds ".lmstudio".
    $pattern = [regex]::Escape($name) -replace '(\\ |-|_)+', '[\s\-_]*'
    $StrictRegex = "(?i)\b$pattern"
    $FolderRx = [regex]::new("^\.?\b$pattern", 'IgnoreCase, Compiled')
    Write-Log "========== SCAN: $name ==========" "Cyan"

    Get-ItemProperty $UninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.UninstallString -and (($_.DisplayName -match $StrictRegex) -or ($_.Publisher -match $StrictRegex)) } |
        ForEach-Object { Add-Result "Uninstaller" $_.DisplayName $_ }

    $searchRoots = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:ProgramData",
                     "$env:APPDATA", "$env:LOCALAPPDATA", "$env:USERPROFILE") +
                   @($drivesBox.Items | ForEach-Object Tag | Where-Object { $_.Pick -and -not $_.System } | ForEach-Object Root)
    $targets = @(foreach ($root in $searchRoots) {
        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue
        Get-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue   # -Force: C:\ProgramData is hidden
    })
    $folderSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $targets.Count; $i++) {
        Update-ScanProgress $i $targets.Count
        $t = $targets[$i]
        if ($Excl.Contains($t.Name) -and ($searchRoots -notcontains $t.FullName)) { continue }
        Add-MatchingFolders $t.FullName
    }
    # A picked program's own install folder is a sure hit, even when its name doesn't match.
    # Never a drive root, a search root or a folder that contains one (e.g. AppData).
    $loc = if ($script:Picked) { "$($script:Picked.InstallLocation)".Trim('"', ' ').TrimEnd('\') }
    if ($loc -and $loc.Split('\').Count -gt 2 -and (Test-Path -LiteralPath $loc) -and -not $Excl.Contains((Split-Path $loc -Leaf)) -and
        -not ($searchRoots | Where-Object { $_ -eq $loc -or $_.StartsWith("$loc\", [System.StringComparison]::OrdinalIgnoreCase) })) {
        [void]$folderSet.Add($loc)
    }
    foreach ($f in $folderSet) { Add-Result "Folder" $f }

    foreach ($h in "LocalMachine", "CurrentUser") {
        $base = [Microsoft.Win32.Registry]::$h.OpenSubKey("Software")
        $subs = $base.GetSubKeyNames()
        for ($i = 0; $i -lt $subs.Count; $i++) {
            Update-ScanProgress $i $subs.Count
            $n = $subs[$i]
            if ($Excl.Contains($n)) { continue }
            if ($n -match $StrictRegex) { Add-Result "Registry" "$($base.Name)\$n" }
            try {
                $k = $base.OpenSubKey($n)
                foreach ($s in $k.GetSubKeyNames()) {
                    if ($s -match $StrictRegex) { Add-Result "Registry" "$($base.Name)\$n\$s" }
                }
                $k.Close()
            } catch { }
        }
    }
    $barFill.Width = 0
    $found = @($list.Items | Where-Object Tag).Count
    if ($found) {
        Set-Step 1 @($name, "$found items found", 'then verify')
        Write-Log "Found $found item(s). Untick anything you want to keep, then click Clean." "Yellow"
    } else {
        Set-Step 0 @("nothing found", 'untick what to keep', 'then verify')
        Write-Log "Nothing found - the system is clean." "Green"
    }
}

# Runs ticked uninstallers, deletes ticked folders and keys, offers reboot deletion for locked
# folders, then scans again so the list shows exactly what is left.
function Invoke-Clean {
    $items = @($list.CheckedItems | Where-Object Tag)
    if (-not $items) { if ($script:Queue) { Select-Next }; return }   # nothing to remove: on to the next picked program
    if (-not (Ask "Remove the $($items.Count) ticked item(s)? Folders and registry keys are deleted permanently.")) { return }
    $name = if ($script:Leftovers) { 'leftovers' } else { $nameBox.Text.Trim() }
    Set-Step 2 @($name, "$($items.Count) picked", 'in progress')
    foreach ($it in $items | Where-Object Text -eq 'Uninstaller') { Invoke-Uninstaller $it.Tag }
    $freed = 0
    $locked = @(foreach ($it in $items | Where-Object Text -eq 'Folder') {
        $bytes = Get-FolderBytes $it.Tag   # measured first: afterwards there's nothing left to measure
        if (Force-DeleteFolder $it.Tag) { $freed += $bytes } else { $it.Tag }
    })
    foreach ($it in $items | Where-Object Text -eq 'Registry') { [void](Force-DeleteRegistryKey $it.Tag) }
    if ($locked -and (Ask "$($locked.Count) folder(s) are locked and could not be deleted. Delete them automatically at the next restart?")) {
        foreach ($f in $locked) { Register-DeleteOnReboot $f }
    }
    if ($freed) { Write-Log "Freed $(Format-Size $freed) from deleted folders." "Green" }
    $script:Programs = @(Get-InstalledPrograms)   # the uninstalled program drops off the list
    Write-Log "Verifying - scanning again..." "Yellow"
    if ($script:Leftovers) { Find-Leftovers } else { Invoke-Scan }
    # Leftovers come back unticked, so there "left" means: ticked folders that still exist.
    $left = if ($script:Leftovers) { @($items | Where-Object { Test-Path -LiteralPath $_.Tag }).Count } else { @($list.Items | Where-Object Tag).Count }
    Set-Step 3 @($name, $(if ($freed) { "$(Format-Size $freed) freed" } else { "$($items.Count) picked" }), $(if ($left) { "$left still found" } else { 'verified clean' }))
    Start-ProgramDetails
    if ($script:Queue) { Select-Next }
}

# Runs a program's uninstaller. Silent when Windows knows how - the program's QuietUninstallString,
# or msiexec /qn for MSI installs - and then waits for it; otherwise opens it and asks you to say when done.
# ponytail: NSIS/Inno "/S" switches are not guessed; a wrong guess can hang or open the normal wizard.
function Invoke-Uninstaller($U) {
    $quiet = if ($U.QuietUninstallString) { $U.QuietUninstallString }
             elseif ($U.UninstallString -match 'msiexec.*?(\{[0-9A-Fa-f-]{36}\})') { "msiexec.exe /x $($Matches[1]) /qn /norestart" }
    if ($quiet) {
        Write-Log "Uninstalling silently: $($U.DisplayName)" "Cyan"
        $p = Start-Process cmd.exe -ArgumentList "/c `"$quiet`"" -WindowStyle Hidden -PassThru
        while (-not $p.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }   # keep the window alive
        # msiexec: 0 done, 3010 done but needs a restart, 1605 already gone
        $color = if ($p.ExitCode -in 0, 3010, 1605) { "Green" } else { "Red" }
        Write-Log "  Uninstaller finished (exit code $($p.ExitCode))$(if ($p.ExitCode -eq 3010) { ' - restart to finish' })." $color
    } else {
        Write-Log "Launching uninstaller: $($U.DisplayName)" "Cyan"
        Start-Process cmd.exe -ArgumentList "/c `"$($U.UninstallString)`""
        [void][System.Windows.Forms.MessageBox]::Show("Click OK once the $($U.DisplayName) uninstaller has completely finished.", $form.Text)
    }
}

# ---- Window: design A "Night Sidebar" ----
$cs = @'
using System; using System.Collections; using System.Collections.Generic; using System.Drawing; using System.Windows.Forms;
using System.Runtime.InteropServices; using System.Management.Automation;
namespace Win32 {
public static class Ui {
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string src, string dst, int flags);
}
// A dropdown list in the dark theme. The closed box is painted entirely here, double-buffered: Windows'
// own paint (white border/arrow, light hover) would flash through before any paint-over.
public class DarkCombo : ComboBox {
    public Color Border, Accent, Hover;
    bool hot;
    public DarkCombo() {
        DrawMode = DrawMode.OwnerDrawFixed; DropDownStyle = ComboBoxStyle.DropDownList; FlatStyle = FlatStyle.Flat;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }
    protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hot = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnSelectedIndexChanged(EventArgs e) { Invalidate(); base.OnSelectedIndexChanged(e); }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics; Rectangle r = ClientRectangle; int a = Font.Height / 4;
        using (SolidBrush bg = new SolidBrush(hot ? Hover : BackColor)) g.FillRectangle(bg, r);
        using (Pen p = new Pen(hot ? Accent : Border)) g.DrawRectangle(p, 0, 0, r.Width - 1, r.Height - 1);
        Rectangle t = new Rectangle(Font.Height / 3, 0, r.Width - Font.Height * 2, r.Height);
        TextRenderer.DrawText(g, Text, Font, t, ForeColor, TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        float cx = r.Right - Font.Height * 0.8f, cy = r.Height / 2f;
        using (Pen p = new Pen(ForeColor, a / 2.5f)) g.DrawLines(p, new[] { new PointF(cx - a, cy - a / 2f), new PointF(cx, cy + a / 2f), new PointF(cx + a, cy - a / 2f) });
    }
    protected override void OnDrawItem(DrawItemEventArgs e) {
        if (e.Index < 0) return;
        bool hot = (e.State & DrawItemState.Selected) != 0 && (e.State & DrawItemState.ComboBoxEdit) == 0;   // not the closed box
        using (SolidBrush b = new SolidBrush(hot ? Accent : BackColor)) e.Graphics.FillRectangle(b, e.Bounds);
        Rectangle t = new Rectangle(e.Bounds.X + Font.Height / 3, e.Bounds.Y, e.Bounds.Width, e.Bounds.Height);
        TextRenderer.DrawText(e.Graphics, Items[e.Index].ToString(), Font, t, ForeColor, TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }
}
// Draws a program row: icon, name on top, publisher and version below, size on the right.
// C#, not PowerShell: each PowerShell statement costs ~1 ms here, so a row took ~20 ms and scrolling stuttered.
// Each row is drawn once into a bitmap and then only copied (BitBlt), since GDI text/icon drawing
// straight to the screen costs ~5 ms a row on this kind of machine.
public class AppRow {
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, int rop);
    [DllImport("user32.dll")] static extern bool DrawIconEx(IntPtr dc, int x, int y, IntPtr icon, int w, int h, int step, IntPtr brush, int flags);
    public Hashtable Icons, Sizes;          // filled by the background loader, keyed by program name
    public Image NoIcon; public Font Name, Small, Mono; public float Dpi = 1;
    public Color Back, Selected, Accent, Text, Dim;
    Dictionary<string, IntPtr> cache = new Dictionary<string, IntPtr>();   // key -> HBITMAP of the drawn row
    IntPtr mem = CreateCompatibleDC(IntPtr.Zero);
    int Px(float v) { return (int)(v * Dpi); }
    static object Unwrap(object o) { PSObject p = o as PSObject; return p != null ? p.BaseObject : o; }
    public void Attach(ListView lv) { lv.DrawItem += Draw; lv.Resize += delegate { Clear(); }; }
    public void Clear() { foreach (IntPtr h in cache.Values) DeleteObject(h); cache.Clear(); }
    void Draw(object sender, DrawListViewItemEventArgs e) {
        Rectangle b = e.Bounds; ListViewItem it = e.Item;
        Icon ico = Unwrap(Icons[it.Text]) as Icon; object mb = Unwrap(Sizes[it.Text]);
        // A new key (selection, width, icon or size changed) draws the row again.
        string key = it.Text + "|" + it.Selected + "|" + b.Width + "|" + (ico != null) + "|" + mb;
        IntPtr bits;
        if (!cache.TryGetValue(key, out bits)) {
            using (Bitmap bmp = new Bitmap(b.Width, b.Height)) {
                using (Graphics g = Graphics.FromImage(bmp)) Paint(g, new Rectangle(0, 0, b.Width, b.Height), it, ico, mb);
                bits = cache[key] = bmp.GetHbitmap();
            }
        }
        IntPtr hdc = e.Graphics.GetHdc(), old = SelectObject(mem, bits);
        BitBlt(hdc, b.X, b.Y, b.Width, b.Height, mem, 0, 0, 0xCC0020);   // SRCCOPY
        SelectObject(mem, old); e.Graphics.ReleaseHdc(hdc);
    }
    void Paint(Graphics g, Rectangle b, ListViewItem it, Icon ico, object mb) {
        using (SolidBrush bg = new SolidBrush(it.Selected ? Selected : Back)) g.FillRectangle(bg, b);
        if (it.Selected) using (SolidBrush bar = new SolidBrush(Accent)) g.FillRectangle(bar, b.X, b.Y, Px(3), b.Height);   // picked rows stand out
        int size = Px(28);
        Rectangle icon = new Rectangle(b.X + Px(14), b.Y + (b.Height - size) / 2, size, size);
        if (ico != null) {
            // Through Windows' DrawIconEx: GDI+ DrawIcon turns PNG-compressed icons (e.g. Git's) into noise.
            // Drawn at the icon's own size on the row colour, then scaled up smoothly.
            using (Bitmap pic = new Bitmap(ico.Width, ico.Height)) {
                using (Graphics pg = Graphics.FromImage(pic)) {
                    pg.Clear(it.Selected ? Selected : Back);
                    IntPtr dc = pg.GetHdc(); DrawIconEx(dc, 0, 0, ico.Handle, ico.Width, ico.Height, 0, IntPtr.Zero, 3); pg.ReleaseHdc(dc);
                }
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.DrawImage(pic, icon);
            }
        }
        else g.DrawImage(NoIcon, icon.X + Px(2), icon.Y + Px(2), NoIcon.Width, NoIcon.Height);
        int half = b.Height / 2;
        Rectangle top = new Rectangle(icon.Right + Px(12), b.Y, b.Right - icon.Right - Px(120), half);
        Rectangle bottom = new Rectangle(top.X, b.Y + half, top.Width, half);
        TextFormatFlags f = TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis;
        TextRenderer.DrawText(g, it.Text, Name, top, Text, f | TextFormatFlags.Bottom);
        if (it.SubItems.Count > 1) TextRenderer.DrawText(g, it.SubItems[1].Text, Small, bottom, Dim, f);
        if (mb != null) {
            Rectangle right = new Rectangle(b.X, b.Y, b.Width - Px(14), b.Height);
            double total = Math.Max(1.0, Convert.ToDouble(mb));   // MB; 1024 MB and up reads as GB
            string shown = total >= 1024 ? string.Format("{0:N1} GB", total / 1024) : string.Format("{0:N0} MB", total);
            TextRenderer.DrawText(g, shown, Mono, right, Dim,
                                  f | TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
        }
    }
}
}
'@
# Compiling that takes ~2 s, so the DLL is kept in %TEMP% and reused; a code change gives a new file name.
$dll = Join-Path $env:TEMP ("SoftwareGuardian-{0:X8}.dll" -f $cs.GetHashCode())
if (-not (Test-Path $dll)) { Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing, ([psobject].Assembly.Location) -TypeDefinition $cs -OutputAssembly $dll }
Add-Type -Path $dll

$form = New-Object System.Windows.Forms.Form -Property @{
    Text = "Universal Software Guardian"; ClientSize = New-Object System.Drawing.Size(1000, 680)
    MinimumSize = New-Object System.Drawing.Size(860, 600); BackColor = Hex '#1E1E1E'; ForeColor = Hex '#E0E0E0'; Font = $Fonts.Body
    Icon = [System.Drawing.Icon]::FromHandle((New-SvgIcon $Icons.Shield 32 '#2A74E0').GetHicon())
}
$dark = 1; [void][Win32.Ui]::DwmSetWindowAttribute($form.Handle, 20, [ref]$dark, 4)   # dark title bar (Win10 20H1+)

# Owner-drawn list with no header and one full-width column. The image list only sets the row height.
function New-OwnerList([int]$RowHeight, [hashtable]$Props) {
    $lv = New-Object System.Windows.Forms.ListView -Property ($Props + @{
        View = 'Details'; HeaderStyle = 'None'; FullRowSelect = $true; MultiSelect = $false; OwnerDraw = $true; BorderStyle = 'None'
        SmallImageList = New-Object System.Windows.Forms.ImageList -Property @{ ImageSize = New-Object System.Drawing.Size(1, (Px $RowHeight)) }
    })
    [void]$lv.Columns.Add('', $lv.Width)
    $lv.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic, Instance').SetValue($lv, $true)
    $lv.Add_Resize({ $this.Columns[0].Width = $this.ClientSize.Width })
    $lv
}

# Sidebar
$side = New-Object System.Windows.Forms.Panel -Property @{ Dock = 'Left'; Width = 220; BackColor = Hex '#121212' }
$side.Add_Paint({ param($s, $e) $e.Graphics.DrawLine((New-Object System.Drawing.Pen (Hex '#282828')), $s.Width - 1, 0, $s.Width - 1, $s.Height) })
$logo = New-Object System.Windows.Forms.PictureBox -Property @{ Left = 20; Top = 22; Size = New-Object System.Drawing.Size(28, 28); Image = New-SvgIcon $Icons.Shield 28 '#2A74E0' }
$title = New-Object System.Windows.Forms.Label -Property @{ Text = "Software Guardian"; Left = 54; Top = 25; AutoSize = $true; Font = $Fonts.Title }
$stepsLabel  = New-Object System.Windows.Forms.Label -Property @{ Text = "STEPS"; Left = 22; Top = 78; AutoSize = $true; Font = $Fonts.Small; ForeColor = Hex '#6C6C6C' }
$stepsPanel  = New-Object System.Windows.Forms.Panel -Property @{ Left = 14; Top = 98; Width = 192; Height = 150 }
$drivesLabel = New-Object System.Windows.Forms.Label -Property @{ Text = "DRIVES TO SCAN"; Left = 22; Top = 268; AutoSize = $true; Font = $Fonts.Small; ForeColor = Hex '#6C6C6C' }
$drivesBox   = New-OwnerList 56 @{ Left = 14; Top = 290; Width = 192; Height = 228; BackColor = Hex '#121212' }
# Row: checkbox, "E:  Label" + USB/SYSTEM tag, free space, then a usage bar.
$drivesBox.Add_DrawItem({ param($s, $e)
    $d = $e.Item.Tag; $b = $e.Bounds; $g = $e.Graphics
    $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#121212')), $b)
    $g.SmoothingMode = 'AntiAlias'
    $box = New-Object System.Drawing.Rectangle(($b.X + (Px 8)), ($b.Y + (Px 8)), (Px 16), (Px 16))
    if ($d.Pick) {
        $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex $(if ($d.System) { '#4A4A4A' } else { '#2A74E0' }))), $box)
        Draw-Svg $g $Icons.Check ($box.X + (Px 2)) ($box.Y + (Px 2)) (Px 12) '#FFFFFF' (Px 2)
    } else { $g.DrawRectangle((New-Object System.Drawing.Pen (Hex '#4A4A4A')), $box) }
    $x = $box.Right + (Px 10); $w = $b.Right - $x - (Px 8)
    $flags = [System.Windows.Forms.TextFormatFlags]'SingleLine, NoPrefix, EndEllipsis, VerticalCenter'
    $line1 = New-Object System.Drawing.Rectangle($x, ($b.Y + (Px 4)), $w, (Px 24))
    $tag = if ($d.System) { 'SYSTEM', '#6C6C6C' } elseif ($d.Usb) { 'USB', '#C2900F' }
    if ($tag) { [System.Windows.Forms.TextRenderer]::DrawText($g, $tag[0], $Fonts.Tag, $line1, (Hex $tag[1]), $flags -bor 'Right'); $line1.Width -= Px 48 }
    [System.Windows.Forms.TextRenderer]::DrawText($g, ("{0}  {1}" -f $d.Root.TrimEnd('\'), $d.Label), $Fonts.Semi, $line1, (Hex '#E0E0E0'), $flags)
    $line2 = New-Object System.Drawing.Rectangle($x, ($b.Y + (Px 27)), $w, (Px 16))
    [System.Windows.Forms.TextRenderer]::DrawText($g, ("{0:N0} GB free of {1:N0} GB" -f $d.Free, $d.Size), $Fonts.Small, $line2, (Hex '#6C6C6C'), $flags)
    $used = 1 - $d.Free / $d.Size
    $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#282828')), $x, ($b.Y + (Px 46)), $w, (Px 3))
    $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex $(if ($used -gt 0.9) { '#C0303C' } else { '#2A74E0' }))), $x, ($b.Y + (Px 46)), [int]($w * $used), (Px 3))
})
# Clicking anywhere on a row ticks it; the system drive can't be unticked. (No native checkboxes: we draw our own.)
$drivesBox.Add_MouseClick({ param($s, $e)
    $it = $drivesBox.GetItemAt($e.X, $e.Y)
    if ($it -and -not $it.Tag.System) { $it.Tag.Pick = -not $it.Tag.Pick; $drivesBox.Invalidate($it.Bounds) }
})
$drivesBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = " Refresh"; Left = 22; Top = 526; Width = 104; Height = 32; FlatStyle = 'Flat'; ForeColor = Hex '#2A74E0'
    Image = New-SvgIcon $Icons.Refresh 14 '#2A74E0'; TextImageRelation = 'ImageBeforeText'; Cursor = 'Hand'
}
$drivesBtn.FlatAppearance.BorderColor = Hex '#333333'
$side.Controls.AddRange(@($logo, $title, $stepsLabel, $stepsPanel, $drivesLabel, $drivesBox, $drivesBtn))

$StartSubs = 'pick a program', 'untick what to keep', 'then verify'
$script:StepNow = 0; $script:StepSubs = $StartSubs
$script:SortBy = 'Name'; $script:Queue = @()
$stepsPanel.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $names = 'Find', 'Review', 'Clean'
    for ($i = 0; $i -lt 3; $i++) {
        $y = Px ($i * 50); $now = $i -eq $script:StepNow; $done = $i -lt $script:StepNow
        if ($now) {
            $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#232323')), 0, $y, $s.Width, (Px 44))
            $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#2A74E0')), 0, $y, (Px 3), (Px 44))
        }
        $dot = New-Object System.Drawing.Rectangle((Px 12), ($y + (Px 10)), (Px 24), (Px 24))
        if ($done) {
            $g.FillEllipse((New-Object System.Drawing.SolidBrush (Hex '#34A062')), $dot)
            Draw-Svg $g $Icons.Check ($dot.X + (Px 5)) ($dot.Y + (Px 5)) (Px 14) '#FFFFFF' (Px 2.2)
        } else {
            if ($now) { $g.FillEllipse((New-Object System.Drawing.SolidBrush (Hex '#2A74E0')), $dot) }
            else { $g.DrawEllipse((New-Object System.Drawing.Pen (Hex '#4A4A4A')), $dot) }
            [System.Windows.Forms.TextRenderer]::DrawText($g, "$($i + 1)", $Fonts.Semi, $dot, (Hex $(if ($now) { '#FFFFFF' } else { '#6C6C6C' })), [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter')
        }
        $fg = if ($now -or $done) { '#E0E0E0' } else { '#6C6C6C' }
        [System.Windows.Forms.TextRenderer]::DrawText($g, $names[$i], $Fonts.Semi, (New-Object System.Drawing.Point((Px 44), ($y + (Px 3)))), (Hex $fg))
        [System.Windows.Forms.TextRenderer]::DrawText($g, $script:StepSubs[$i], $Fonts.Small, (New-Object System.Drawing.Point((Px 45), ($y + (Px 23)))), (Hex '#6C6C6C'))
    }
})

# Main area: sized up front so anchors are measured against the real size.
$main = New-Object System.Windows.Forms.Panel -Property @{ Dock = 'Fill'; Size = New-Object System.Drawing.Size(780, 680) }

$search = New-Object System.Windows.Forms.Panel -Property @{ Left = 24; Top = 20; Width = 732; Height = 48; BackColor = Hex '#232323'; Anchor = 'Top, Left, Right' }
$search.Add_Paint({ param($s, $e) $e.Graphics.DrawRectangle((New-Object System.Drawing.Pen (Hex '#333333')), 0, 0, $s.Width - 1, $s.Height - 1) })
$searchIcon = New-Object System.Windows.Forms.PictureBox -Property @{ Left = 14; Top = 14; Size = New-Object System.Drawing.Size(20, 20); Image = New-SvgIcon $Icons.Search 20 '#2A74E0' }
$nameBox = New-Object System.Windows.Forms.TextBox -Property @{
    Left = 44; Top = 12; Width = 412; BorderStyle = 'None'; Font = $Fonts.Input; Anchor = 'Top, Left, Right'
    BackColor = Hex '#232323'; ForeColor = Hex '#E0E0E0'
}
$scanBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = "Scan"; Left = 612; Top = 5; Width = 114; Height = 38; Anchor = 'Top, Right'; FlatStyle = 'Flat'; Cursor = 'Hand'
    BackColor = Hex '#2D2D2D'; ForeColor = Hex '#E0E0E0'; Font = $Fonts.Semi
}
$scanBtn.FlatAppearance.BorderColor = Hex '#3D3D3D'
# Sort order for the program list; only shown on the program screen.
$sortBox = New-Object Win32.DarkCombo -Property @{
    Left = 468; Top = 9; Width = 132; Anchor = 'Top, Right'; ItemHeight = Px 24; Cursor = 'Hand'
    BackColor = Hex '#2D2D2D'; ForeColor = Hex '#E0E0E0'; Border = Hex '#3D3D3D'; Accent = Hex '#2A74E0'; Hover = Hex '#333333'; Font = $Fonts.Semi
}
$sortBox.Items.AddRange(@('Sort: Name', 'Sort: Size', 'Sort: Newest')); $sortBox.SelectedIndex = 0
$search.Controls.AddRange(@($searchIcon, $nameBox, $sortBox, $scanBtn))

$bar = New-Object System.Windows.Forms.Panel -Property @{ Left = 24; Top = 76; Width = 732; Height = 3; BackColor = Hex '#282828'; Anchor = 'Top, Left, Right' }
$barFill = New-Object System.Windows.Forms.Panel -Property @{ Left = 0; Top = 0; Width = 0; Height = 3; BackColor = Hex '#2A74E0' }
$bar.Controls.Add($barFill)

$list = New-OwnerList 32 @{ Left = 24; Top = 90; Width = 732; Height = 376; Anchor = 'Top, Bottom, Left, Right'; CheckBoxes = $true; BackColor = Hex '#232323' }
$list.Add_DrawItem({ param($s, $e)
    $it = $e.Item; $b = $e.Bounds; $g = $e.Graphics; $hdr = -not $it.Tag
    $bg = if ($it.Selected) { '#2D2D2D' } elseif ($hdr) { '#282828' } else { '#232323' }
    $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex $bg)), $b)
    $g.SmoothingMode = 'AntiAlias'
    $box = New-Object System.Drawing.Rectangle(($b.X + (Px 6)), ($b.Y + [int](($b.Height - (Px 16)) / 2)), (Px 16), (Px 16))
    if ($it.Checked) {
        $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#2A74E0')), $box)
        Draw-Svg $g $Icons.Check ($box.X + (Px 2)) ($box.Y + (Px 2)) (Px 12) '#FFFFFF' (Px 2)
    } else { $g.DrawRectangle((New-Object System.Drawing.Pen (Hex '#4A4A4A')), $box) }
    $text = New-Object System.Drawing.Rectangle(($b.X + (Px 34)), $b.Y, ($b.Width - (Px 48)), $b.Height)
    $flags = [System.Windows.Forms.TextFormatFlags]'VerticalCenter, SingleLine, NoPrefix'
    if ($hdr) {
        $t = $Tags[$it.Name]
        [System.Windows.Forms.TextRenderer]::DrawText($g, $t.Tag, $Fonts.Tag, $text, (Hex $t.Color), $flags)
        $text.X += Px 50; $text.Width -= Px 50
        [System.Windows.Forms.TextRenderer]::DrawText($g, $t.Group, $Fonts.Semi, $text, (Hex '#E0E0E0'), $flags)
        $n = @($list.Items | Where-Object { $_.Tag -and $_.Text -eq $it.Name }).Count
        [System.Windows.Forms.TextRenderer]::DrawText($g, "$n", $Fonts.Mono, $text, (Hex '#6C6C6C'), $flags -bor 'Right')
    } else {
        $fg = if ($it.Checked) { '#E0E0E0' } else { '#6C6C6C' }
        [System.Windows.Forms.TextRenderer]::DrawText($g, $it.SubItems[1].Text, $Fonts.Mono, $text, (Hex $fg), $flags -bor 'PathEllipsis')
    }
})
# Ticking a group header ticks or unticks every item of that type.
$list.Add_ItemChecked({ param($s, $e)
    $it = $e.Item
    if (-not $it.Tag) { foreach ($c in $list.Items) { if ($c.Tag -and $c.Text -eq $it.Name -and $c.Checked -ne $it.Checked) { $c.Checked = $it.Checked } } }
    Update-Count
})

# Installed programs list: shown until a scan, in the same spot as the results.
$apps = New-OwnerList 44 @{ Left = 24; Top = 90; Width = 732; Height = 376; Anchor = 'Top, Bottom, Left, Right'; BackColor = Hex '#232323' }
# Where a program's icon can be found, best first:
#   1. DisplayIcon ("C:\app.exe,0" or an .ico) - what "Apps & features" uses
#   2. MSI installs: the product icon Windows Installer keeps (key is the GUID in "packed" order)
#   3. an .exe in the install folder named like the program (Discord.exe, PacketTracer.exe)
function Get-IconFiles($P) {
    $file = "$($P.DisplayIcon)".Split(',')[0].Trim('"', ' ')
    if ($file) { return $file }
    if ($P.PSChildName -match '^\{[0-9A-F-]{36}\}$') {
        $g = $P.PSChildName -replace '[{}-]'
        $packed = (-join $g[7..0]) + (-join $g[11..8]) + (-join $g[15..12]) + (-join (16..31 | ForEach-Object { $g[$_ -bxor 1] }))
        (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\Installer\Products\$packed" -ErrorAction SilentlyContinue).ProductIcon
    }
    if ($P.InstallLocation -and (Test-Path -LiteralPath $P.InstallLocation)) {
        $key = $P.DisplayName -replace '[^A-Za-z]'
        Get-ChildItem -LiteralPath $P.InstallLocation -Filter *.exe -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName.Length -ge 3 -and $key.IndexOf(($_.BaseName -replace '[^A-Za-z]'), [System.StringComparison]::OrdinalIgnoreCase) -ge 0 } |
            Select-Object -First 1 -ExpandProperty FullName
    }
}

# Icons and sizes are filled by Start-ProgramDetails on a background thread; rows only read these.
# $null = no icon anywhere (the row gets the plain App icon) or no size known.
$IconCache = [hashtable]::Synchronized(@{})
$SizeCache = [hashtable]::Synchronized(@{})
function Get-ProgramIcon($P) {
    if (-not $IconCache.ContainsKey($P.DisplayName)) {
        $IconCache[$P.DisplayName] = $null
        foreach ($file in @(Get-IconFiles $P)) {
            if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            # .exe/.dll: extract. Anything else is an .ico (even without the extension, e.g. MSI "NodeIcon").
            # Never open an exe as an .ico: it reads the whole file first (1-2 s for a 150 MB Electron app).
            $ico = try {
                if ($file -match '\.(exe|dll)$') { [System.Drawing.Icon]::ExtractAssociatedIcon($file) } else { New-Object System.Drawing.Icon($file) }
            } catch { try { [System.Drawing.Icon]::ExtractAssociatedIcon($file) } catch { $null } }
            if ($ico) { $IconCache[$P.DisplayName] = $ico; break }
        }
    }
    $IconCache[$P.DisplayName]
}
# Size in MB: the registry's EstimatedSize, else measure the install folder once (IDM, OBS, VLC... skip EstimatedSize).
function Get-ProgramSize($P) {
    if ($P.EstimatedSize) { $SizeCache[$P.DisplayName] = $P.EstimatedSize / 1024 }
    elseif (-not $SizeCache.ContainsKey($P.DisplayName)) {
        $SizeCache[$P.DisplayName] = $null
        $dir = "$($P.InstallLocation)".Trim('"', ' ')
        # No InstallLocation: use the Program Files folder the icon lives in (bin\64bit\obs64.exe -> obs-studio).
        if (-not $dir -and "$($P.DisplayIcon)" -match '[A-Z]:\\Program Files[^\\]*\\[^\\",]+') { $dir = $Matches[0] }
        if ($dir -and $dir.TrimEnd('\').Split('\').Count -ge 3 -and (Test-Path -LiteralPath $dir -PathType Container)) {
            $bytes = Get-FolderBytes $dir
            if ($bytes) { $SizeCache[$P.DisplayName] = $bytes / 1MB }
        }
    }
    $SizeCache[$P.DisplayName]
}
# Loads every program's icon and size on a background thread (~2-10 s, mostly disk), so the window never
# freezes; the timer below repaints the list while it runs. Already-cached programs are skipped.
function Start-ProgramDetails {
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('IconCache', $IconCache)
    $rs.SessionStateProxy.SetVariable('SizeCache', $SizeCache)
    $defs = 'Get-IconFiles', 'Get-ProgramIcon', 'Get-ProgramSize', 'Get-FolderBytes' | ForEach-Object { "function $_ {$((Get-Item "function:$_").Definition)}" }
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript("Add-Type -AssemblyName System.Drawing`n" + ($defs -join "`n") + "`n" + 'foreach ($p in $args[0]) { [void](Get-ProgramIcon $p); [void](Get-ProgramSize $p) }').AddArgument($script:Programs)
    $script:Loading = $ps.BeginInvoke()
    $repaint.Start()
}
# Repaints the program list while the loader runs; stops itself when it's done.
$repaint = New-Object System.Windows.Forms.Timer -Property @{ Interval = 250 }
$repaint.Add_Tick({
    $apps.Invalidate()
    # All sizes known now: re-sort, unless you've already picked programs (rebuilding would drop them).
    if ($script:Loading.IsCompleted) { $repaint.Stop(); if ($apps.Visible -and $script:SortBy -eq 'Size' -and -not $apps.SelectedItems.Count) { Show-Programs } }
})
(New-Object Win32.AppRow -Property @{
    Icons = $IconCache; Sizes = $SizeCache; Dpi = $Dpi; NoIcon = New-SvgIcon $Icons.App 24 '#6C6C6C'
    Name = $Fonts.Semi; Small = $Fonts.Small; Mono = $Fonts.Mono
    Back = Hex '#232323'; Selected = Hex '#2D2D2D'; Accent = Hex '#2A74E0'; Text = Hex '#E0E0E0'; Dim = Hex '#6C6C6C'
}).Attach($apps)
$apps.MultiSelect = $true   # Ctrl/Shift+click picks several programs to remove one after another
$apps.Add_DoubleClick({ if ($apps.SelectedItems.Count) { Busy { Start-Queue $apps.SelectedItems[0].Tag } } })

$logWrap = New-Object System.Windows.Forms.Panel -Property @{
    Left = 24; Top = 480; Width = 732; Height = 112; Anchor = 'Bottom, Left, Right'
    BackColor = Hex '#121212'; Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
}
$logBox = New-Object System.Windows.Forms.RichTextBox -Property @{
    Dock = 'Fill'; ReadOnly = $true; HideSelection = $false; BorderStyle = 'None'; ScrollBars = 'Vertical'
    BackColor = Hex '#121212'; ForeColor = Hex '#6C6C6C'; Font = $Fonts.Mono
    Text = "Ready - pick an installed program and press Scan, or type the name of one that's already uninstalled.`r`n"
}
$logWrap.Controls.Add($logBox)

$countLabel = New-Object System.Windows.Forms.Label -Property @{ Text = "0 of 0 selected"; Left = 24; Top = 620; AutoSize = $true; Anchor = 'Bottom, Left'; Font = $Fonts.Mono; ForeColor = Hex '#A0A0A0' }
$cleanBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = " Clean selected"; Left = 580; Top = 606; Width = 176; Height = 44; Anchor = 'Bottom, Right'; FlatStyle = 'Flat'; Cursor = 'Hand'
    BackColor = Hex '#2A74E0'; ForeColor = Hex '#FFFFFF'; Font = $Fonts.Semi
    Image = New-SvgIcon $Icons.Trash 18 '#FFFFFF'; TextImageRelation = 'ImageBeforeText'
}
$cleanBtn.FlatAppearance.BorderSize = 0
$backBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = " Back"; Left = 456; Top = 606; Width = 112; Height = 44; Anchor = 'Bottom, Right'; FlatStyle = 'Flat'; Cursor = 'Hand'
    BackColor = Hex '#2D2D2D'; ForeColor = Hex '#E0E0E0'; Font = $Fonts.Semi
    Image = New-SvgIcon $Icons.Back 18 '#E0E0E0'; TextImageRelation = 'ImageBeforeText'
}
$backBtn.FlatAppearance.BorderColor = Hex '#3D3D3D'
# Program screen button, in the same spot as Clean on the results screen.
$leftBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = " Find leftovers"; Left = 580; Top = 606; Width = 176; Height = 44; Anchor = 'Bottom, Right'; FlatStyle = 'Flat'; Cursor = 'Hand'
    BackColor = Hex '#2D2D2D'; ForeColor = Hex '#E0E0E0'; Font = $Fonts.Semi
    Image = New-SvgIcon $Icons.Search 18 '#E0E0E0'; TextImageRelation = 'ImageBeforeText'
}
$leftBtn.FlatAppearance.BorderColor = Hex '#3D3D3D'
$main.Controls.AddRange(@($search, $bar, $list, $apps, $logWrap, $countLabel, $backBtn, $cleanBtn, $leftBtn))

# Scan and Clean are disabled while either runs, so a second click can't start another pass.
function Busy([scriptblock]$Work) { $scanBtn.Enabled = $cleanBtn.Enabled = $false; try { & $Work } finally { $scanBtn.Enabled = $cleanBtn.Enabled = $true } }
# Scan uses the selected program if there is one, otherwise the typed name (for leftovers of removed programs).
$scanBtn.Add_Click({ Busy {
    if ($apps.Visible -and $apps.SelectedItems.Count) { Start-Queue ($apps.SelectedItems | ForEach-Object Tag) }
    elseif ($script:Leftovers) { Find-Leftovers } else { Invoke-Scan }
} })
$sortBox.Add_SelectedIndexChanged({ $script:SortBy = ('Name', 'Size', 'Newest')[$sortBox.SelectedIndex]; Show-Programs })
$leftBtn.Add_Click({ Busy { Find-Leftovers } })
$nameBox.Add_TextChanged({ $script:Picked = $null; Show-Programs })
$cleanBtn.Add_Click({ Busy { Invoke-Clean } })
# Back to the program list: clearing the box shows every program again (TextChanged -> Show-Programs).
$backBtn.Add_Click({
    Set-Step 0 $StartSubs; $script:Queue = @()   # also drops any programs still waiting
    if ($nameBox.Text) { $nameBox.Clear() } else { Show-Programs }
})
$drivesBtn.Add_Click({ Update-Drives })
$form.AcceptButton = $scanBtn
$form.Controls.AddRange(@($main, $side))   # Fill first: docking runs back to front
$form.Scale((New-Object System.Drawing.SizeF($Dpi, $Dpi)))
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea   # scaled up it can be taller than the screen
$form.Size = New-Object System.Drawing.Size([Math]::Min($form.Width, $wa.Width), [Math]::Min($form.Height, $wa.Height))
$form.StartPosition = 'Manual'   # the handle already exists, so CenterScreen would use the pre-scale size
$form.Location = New-Object System.Drawing.Point(($wa.X + [int](($wa.Width - $form.Width) / 2)), ($wa.Y + [int](($wa.Height - $form.Height) / 2)))
# ponytail: scrollbars stay light; Windows 10 ignores dark themes on these controls. Upgrade path: draw a custom scrollbar.
[void][Win32.Ui]::SendMessage($nameBox.Handle, 0x1501, [IntPtr]1, "Search installed programs, or type a name")   # EM_SETCUEBANNER
Update-Drives
$script:Programs = @(Get-InstalledPrograms)
Show-Programs
# Invisible until every control has painted once, so the half-drawn window (white blocks) never shows.
$form.Opacity = 0
$form.Add_Shown({
    $form.Refresh(); $form.Opacity = 1
    Start-ProgramDetails   # after the first paint, so the loader doesn't slow it down
})

# Open the window only when run - not when dot-sourced, which is how the tests load the functions.
if ($MyInvocation.InvocationName -ne '.') { [void]$form.ShowDialog() }
