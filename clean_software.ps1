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
$Palette = @{ White = '#E6E8EB'; Gray = '#6B7482'; Cyan = '#5EB1FF'; Green = '#4ADE80'; Red = '#FF7B7B'; Yellow = '#F2C94C'; Orange = '#FF9E64' }
$Tags = @{
    Uninstaller = @{ Tag = 'UNINST'; Color = '#FF9E64'; Group = 'Uninstallers' }
    Folder      = @{ Tag = 'DIR';    Color = '#F2C94C'; Group = 'Folders' }
    Registry    = @{ Tag = 'REG';    Color = '#4FD1C5'; Group = 'Registry keys' }
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
    Add-Type -Namespace Win32 -Name Native -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string src, string dst, int flags);'
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
    $failed = @(@($files) + @($dirs) | Where-Object { -not [Win32.Native]::MoveFileEx($_, [NullString]::Value, 4) }).Count
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
function Add-Result([string]$Type, [string]$Text, [string]$Value = $Text) {
    if (-not $list.Items.ContainsKey($Type)) { $list.Items.Add($Type, $Tags[$Type].Group, -1).Checked = $true }
    $item = $list.Items.Add($Type)
    [void]$item.SubItems.Add($Text)
    $item.Tag = $Value
    $item.Checked = $true
}

function Update-Drives {
    $drivesBox.Items.Clear()
    foreach ($v in Get-CimInstance Win32_LogicalDisk -Filter "DriveType=2 OR DriveType=3" -ErrorAction SilentlyContinue |
                   Where-Object { $_.DeviceID -ne $env:SystemDrive -and $_.FreeSpace -ne $null }) {
        $kind = if ($v.DriveType -eq 2) { "usb" } else { "hdd" }
        [void]$drivesBox.Items.Add(("{0}\  {1}  {2}" -f $v.DeviceID, $kind, $v.VolumeName))
    }
}

# Lists what would be removed; deletes nothing. Also the verification step after Clean.
function Invoke-Scan {
    $name = $nameBox.Text.Trim()
    if ($name.Length -lt 3) { [void][System.Windows.Forms.MessageBox]::Show("Type at least 3 letters of the program name.", $form.Text); return }
    $list.Items.Clear()
    # Spaces, hyphens and underscores match each other, so "LM Studio" also finds ".lmstudio".
    $pattern = [regex]::Escape($name) -replace '(\\ |-|_)+', '[\s\-_]*'
    $StrictRegex = "(?i)\b$pattern"
    $FolderRx = [regex]::new("^\.?\b$pattern", 'IgnoreCase, Compiled')
    Write-Log "========== SCAN: $name ==========" "Cyan"

    Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                     "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                     "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.UninstallString -and (($_.DisplayName -match $StrictRegex) -or ($_.Publisher -match $StrictRegex)) } |
        ForEach-Object { Add-Result "Uninstaller" $_.DisplayName $_.UninstallString }

    $searchRoots = @("$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:ProgramData",
                     "$env:APPDATA", "$env:LOCALAPPDATA", "$env:USERPROFILE") +
                   @($drivesBox.CheckedItems | ForEach-Object { ($_ -split '\s+')[0] })
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
    if (-not $items -or -not (Ask "Remove the $($items.Count) ticked item(s)? Folders and registry keys are deleted permanently.")) { return }
    $name = $nameBox.Text.Trim()
    Set-Step 2 @($name, "$($items.Count) picked", 'in progress')
    foreach ($it in $items | Where-Object Text -eq 'Uninstaller') {
        Write-Log "Launching uninstaller: $($it.SubItems[1].Text)" "Cyan"
        Start-Process cmd.exe -ArgumentList "/c `"$($it.Tag)`""
        [void][System.Windows.Forms.MessageBox]::Show("Click OK once the $($it.SubItems[1].Text) uninstaller has completely finished.", $form.Text)
    }
    $locked = @(foreach ($it in $items | Where-Object Text -eq 'Folder') { if (-not (Force-DeleteFolder $it.Tag)) { $it.Tag } })
    foreach ($it in $items | Where-Object Text -eq 'Registry') { [void](Force-DeleteRegistryKey $it.Tag) }
    if ($locked -and (Ask "$($locked.Count) folder(s) are locked and could not be deleted. Delete them automatically at the next restart?")) {
        foreach ($f in $locked) { Register-DeleteOnReboot $f }
    }
    Write-Log "Verifying - scanning again..." "Yellow"
    Invoke-Scan
    $left = @($list.Items | Where-Object Tag).Count
    Set-Step 3 @($name, "$($items.Count) picked", $(if ($left) { "$left still found" } else { 'verified clean' }))
}

# ---- Window: design A "Night Sidebar" ----
Add-Type -Namespace Win32 -Name Ui -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string id);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
'@

$form = New-Object System.Windows.Forms.Form -Property @{
    Text = "Universal Software Guardian"; ClientSize = New-Object System.Drawing.Size(1000, 680); StartPosition = 'CenterScreen'
    MinimumSize = New-Object System.Drawing.Size(860, 600); BackColor = Hex '#0E1116'; ForeColor = Hex '#E6E8EB'; Font = $Fonts.Body
    Icon = [System.Drawing.Icon]::FromHandle((New-SvgIcon $Icons.Shield 32 '#5EB1FF').GetHicon())
}
$dark = 1; [void][Win32.Ui]::DwmSetWindowAttribute($form.Handle, 20, [ref]$dark, 4)   # dark title bar (Win10 20H1+)

# Sidebar
$side = New-Object System.Windows.Forms.Panel -Property @{ Dock = 'Left'; Width = 220; BackColor = Hex '#0A0C10' }
$side.Add_Paint({ param($s, $e) $e.Graphics.DrawLine((New-Object System.Drawing.Pen (Hex '#1E232D')), $s.Width - 1, 0, $s.Width - 1, $s.Height) })
$logo = New-Object System.Windows.Forms.PictureBox -Property @{ Left = 20; Top = 22; Size = New-Object System.Drawing.Size(28, 28); Image = New-SvgIcon $Icons.Shield 28 '#5EB1FF' }
$title = New-Object System.Windows.Forms.Label -Property @{ Text = "Software Guardian"; Left = 54; Top = 25; AutoSize = $true; Font = $Fonts.Title }
$stepsLabel  = New-Object System.Windows.Forms.Label -Property @{ Text = "STEPS"; Left = 22; Top = 78; AutoSize = $true; Font = $Fonts.Small; ForeColor = Hex '#6B7482' }
$stepsPanel  = New-Object System.Windows.Forms.Panel -Property @{ Left = 14; Top = 98; Width = 192; Height = 150 }
$drivesLabel = New-Object System.Windows.Forms.Label -Property @{ Text = "DRIVES"; Left = 22; Top = 268; AutoSize = $true; Font = $Fonts.Small; ForeColor = Hex '#6B7482' }
$sysDrive    = New-Object System.Windows.Forms.Label -Property @{ Text = "$env:SystemDrive\  system (always)"; Left = 22; Top = 292; AutoSize = $true; Font = $Fonts.Mono; ForeColor = Hex '#6B7482' }
$drivesBox   = New-Object System.Windows.Forms.CheckedListBox -Property @{
    Left = 18; Top = 314; Width = 188; Height = 96; CheckOnClick = $true; BorderStyle = 'None'
    BackColor = Hex '#0A0C10'; ForeColor = Hex '#E6E8EB'; Font = $Fonts.Mono
}
$drivesBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = " Refresh"; Left = 22; Top = 418; Width = 104; Height = 32; FlatStyle = 'Flat'; ForeColor = Hex '#5EB1FF'
    Image = New-SvgIcon $Icons.Refresh 14 '#5EB1FF'; TextImageRelation = 'ImageBeforeText'; Cursor = 'Hand'
}
$drivesBtn.FlatAppearance.BorderColor = Hex '#262C37'
$side.Controls.AddRange(@($logo, $title, $stepsLabel, $stepsPanel, $drivesLabel, $sysDrive, $drivesBox, $drivesBtn))

$script:StepNow = 0; $script:StepSubs = @('type a program name', 'untick what to keep', 'then verify')
$stepsPanel.Add_Paint({ param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
    $names = 'Find', 'Review', 'Clean'
    for ($i = 0; $i -lt 3; $i++) {
        $y = Px ($i * 50); $now = $i -eq $script:StepNow; $done = $i -lt $script:StepNow
        if ($now) {
            $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#161A22')), 0, $y, $s.Width, (Px 44))
            $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#5EB1FF')), 0, $y, (Px 3), (Px 44))
        }
        $dot = New-Object System.Drawing.Rectangle((Px 12), ($y + (Px 10)), (Px 24), (Px 24))
        if ($done) {
            $g.FillEllipse((New-Object System.Drawing.SolidBrush (Hex '#4ADE80')), $dot)
            Draw-Svg $g $Icons.Check ($dot.X + (Px 5)) ($dot.Y + (Px 5)) (Px 14) '#0E1116' (Px 2.2)
        } else {
            if ($now) { $g.FillEllipse((New-Object System.Drawing.SolidBrush (Hex '#5EB1FF')), $dot) }
            else { $g.DrawEllipse((New-Object System.Drawing.Pen (Hex '#3A4250')), $dot) }
            [System.Windows.Forms.TextRenderer]::DrawText($g, "$($i + 1)", $Fonts.Semi, $dot, (Hex $(if ($now) { '#0E1116' } else { '#6B7482' })), [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter')
        }
        $fg = if ($now -or $done) { '#E6E8EB' } else { '#6B7482' }
        [System.Windows.Forms.TextRenderer]::DrawText($g, $names[$i], $Fonts.Semi, (New-Object System.Drawing.Point((Px 44), ($y + (Px 3)))), (Hex $fg))
        [System.Windows.Forms.TextRenderer]::DrawText($g, $script:StepSubs[$i], $Fonts.Small, (New-Object System.Drawing.Point((Px 45), ($y + (Px 23)))), (Hex '#6B7482'))
    }
})

# Main area: sized up front so anchors are measured against the real size.
$main = New-Object System.Windows.Forms.Panel -Property @{ Dock = 'Fill'; Size = New-Object System.Drawing.Size(780, 680) }

$search = New-Object System.Windows.Forms.Panel -Property @{ Left = 24; Top = 20; Width = 732; Height = 48; BackColor = Hex '#161A22'; Anchor = 'Top, Left, Right' }
$search.Add_Paint({ param($s, $e) $e.Graphics.DrawRectangle((New-Object System.Drawing.Pen (Hex '#262C37')), 0, 0, $s.Width - 1, $s.Height - 1) })
$searchIcon = New-Object System.Windows.Forms.PictureBox -Property @{ Left = 14; Top = 14; Size = New-Object System.Drawing.Size(20, 20); Image = New-SvgIcon $Icons.Search 20 '#5EB1FF' }
$nameBox = New-Object System.Windows.Forms.TextBox -Property @{
    Left = 44; Top = 12; Width = 552; BorderStyle = 'None'; Font = $Fonts.Input; Anchor = 'Top, Left, Right'
    BackColor = Hex '#161A22'; ForeColor = Hex '#E6E8EB'
}
$scanBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = "Scan"; Left = 612; Top = 5; Width = 114; Height = 38; Anchor = 'Top, Right'; FlatStyle = 'Flat'; Cursor = 'Hand'
    BackColor = Hex '#1E2430'; ForeColor = Hex '#E6E8EB'; Font = $Fonts.Semi
}
$scanBtn.FlatAppearance.BorderColor = Hex '#2E3747'
$search.Controls.AddRange(@($searchIcon, $nameBox, $scanBtn))

$bar = New-Object System.Windows.Forms.Panel -Property @{ Left = 24; Top = 76; Width = 732; Height = 3; BackColor = Hex '#1E232D'; Anchor = 'Top, Left, Right' }
$barFill = New-Object System.Windows.Forms.Panel -Property @{ Left = 0; Top = 0; Width = 0; Height = 3; BackColor = Hex '#5EB1FF' }
$bar.Controls.Add($barFill)

$list = New-Object System.Windows.Forms.ListView -Property @{
    Left = 24; Top = 90; Width = 732; Height = 376; Anchor = 'Top, Bottom, Left, Right'
    View = 'Details'; CheckBoxes = $true; FullRowSelect = $true; MultiSelect = $false; HeaderStyle = 'None'
    OwnerDraw = $true; BorderStyle = 'None'; BackColor = Hex '#161A22'
    SmallImageList = New-Object System.Windows.Forms.ImageList -Property @{ ImageSize = New-Object System.Drawing.Size(1, (Px 32)) }   # row height
}
[void]$list.Columns.Add("Item", 732)
$list.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic, Instance').SetValue($list, $true)
$list.Add_Resize({ $list.Columns[0].Width = $list.ClientSize.Width })
$list.Add_DrawItem({ param($s, $e)
    $it = $e.Item; $b = $e.Bounds; $g = $e.Graphics; $hdr = -not $it.Tag
    $bg = if ($it.Selected) { '#1E2430' } elseif ($hdr) { '#1A1F29' } else { '#161A22' }
    $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex $bg)), $b)
    $g.SmoothingMode = 'AntiAlias'
    $box = New-Object System.Drawing.Rectangle(($b.X + (Px 6)), ($b.Y + [int](($b.Height - (Px 16)) / 2)), (Px 16), (Px 16))
    if ($it.Checked) {
        $g.FillRectangle((New-Object System.Drawing.SolidBrush (Hex '#5EB1FF')), $box)
        Draw-Svg $g $Icons.Check ($box.X + (Px 2)) ($box.Y + (Px 2)) (Px 12) '#0E1116' (Px 2)
    } else { $g.DrawRectangle((New-Object System.Drawing.Pen (Hex '#3A4250')), $box) }
    $text = New-Object System.Drawing.Rectangle(($b.X + (Px 34)), $b.Y, ($b.Width - (Px 48)), $b.Height)
    $flags = [System.Windows.Forms.TextFormatFlags]'VerticalCenter, SingleLine, NoPrefix'
    if ($hdr) {
        $t = $Tags[$it.Name]
        [System.Windows.Forms.TextRenderer]::DrawText($g, $t.Tag, $Fonts.Tag, $text, (Hex $t.Color), $flags)
        $text.X += Px 50; $text.Width -= Px 50
        [System.Windows.Forms.TextRenderer]::DrawText($g, $t.Group, $Fonts.Semi, $text, (Hex '#E6E8EB'), $flags)
        $n = @($list.Items | Where-Object { $_.Tag -and $_.Text -eq $it.Name }).Count
        [System.Windows.Forms.TextRenderer]::DrawText($g, "$n", $Fonts.Mono, $text, (Hex '#6B7482'), $flags -bor 'Right')
    } else {
        $fg = if ($it.Checked) { '#E6E8EB' } else { '#6B7482' }
        [System.Windows.Forms.TextRenderer]::DrawText($g, $it.SubItems[1].Text, $Fonts.Mono, $text, (Hex $fg), $flags -bor 'PathEllipsis')
    }
})
# Ticking a group header ticks or unticks every item of that type.
$list.Add_ItemChecked({ param($s, $e)
    $it = $e.Item
    if (-not $it.Tag) { foreach ($c in $list.Items) { if ($c.Tag -and $c.Text -eq $it.Name -and $c.Checked -ne $it.Checked) { $c.Checked = $it.Checked } } }
    Update-Count
})

$logWrap = New-Object System.Windows.Forms.Panel -Property @{
    Left = 24; Top = 480; Width = 732; Height = 112; Anchor = 'Bottom, Left, Right'
    BackColor = Hex '#0A0C10'; Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
}
$logBox = New-Object System.Windows.Forms.RichTextBox -Property @{
    Dock = 'Fill'; ReadOnly = $true; HideSelection = $false; BorderStyle = 'None'; ScrollBars = 'Vertical'
    BackColor = Hex '#0A0C10'; ForeColor = Hex '#6B7482'; Font = $Fonts.Mono
    Text = "Ready - type a program name, tick any extra drives, then press Scan.`r`n"
}
$logWrap.Controls.Add($logBox)

$countLabel = New-Object System.Windows.Forms.Label -Property @{ Text = "0 of 0 selected"; Left = 24; Top = 620; AutoSize = $true; Anchor = 'Bottom, Left'; Font = $Fonts.Mono; ForeColor = Hex '#9BA4B2' }
$cleanBtn = New-Object System.Windows.Forms.Button -Property @{
    Text = " Clean selected"; Left = 580; Top = 606; Width = 176; Height = 44; Anchor = 'Bottom, Right'; FlatStyle = 'Flat'; Cursor = 'Hand'
    BackColor = Hex '#5EB1FF'; ForeColor = Hex '#0E1116'; Font = $Fonts.Semi
    Image = New-SvgIcon $Icons.Trash 18 '#0E1116'; TextImageRelation = 'ImageBeforeText'
}
$cleanBtn.FlatAppearance.BorderSize = 0
$main.Controls.AddRange(@($search, $bar, $list, $logWrap, $countLabel, $cleanBtn))

$scanBtn.Add_Click({ $scanBtn.Enabled = $cleanBtn.Enabled = $false; try { Invoke-Scan } finally { $scanBtn.Enabled = $cleanBtn.Enabled = $true } })
$cleanBtn.Add_Click({ $scanBtn.Enabled = $cleanBtn.Enabled = $false; try { Invoke-Clean } finally { $scanBtn.Enabled = $cleanBtn.Enabled = $true } })
$drivesBtn.Add_Click({ Update-Drives })
$form.AcceptButton = $scanBtn
$form.Controls.AddRange(@($main, $side))   # Fill first: docking runs back to front
$form.Scale((New-Object System.Drawing.SizeF($Dpi, $Dpi)))
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea   # scaled up it can be taller than the screen
$form.Size = New-Object System.Drawing.Size([Math]::Min($form.Width, $wa.Width), [Math]::Min($form.Height, $wa.Height))
$form.StartPosition = 'Manual'   # the handle already exists, so CenterScreen would use the pre-scale size
$form.Location = New-Object System.Drawing.Point(($wa.X + [int](($wa.Width - $form.Width) / 2)), ($wa.Y + [int](($wa.Height - $form.Height) / 2)))
[void][Win32.Ui]::SetWindowTheme($list.Handle, "DarkMode_Explorer", $null)       # dark scrollbar
[void][Win32.Ui]::SendMessage($nameBox.Handle, 0x1501, [IntPtr]1, "Program name, e.g. LM Studio")   # EM_SETCUEBANNER
Update-Drives

# Open the window only when run - not when dot-sourced, which is how the tests load the functions.
if ($MyInvocation.InvocationName -ne '.') { [void]$form.ShowDialog() }
