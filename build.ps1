# Builds SoftwareGuardian.exe with the C# compiler that ships with Windows (.NET Framework 4.x).
# The exe embeds clean_software.ps1 and asks for Administrator when it starts.
$manifest = Join-Path $env:TEMP "SoftwareGuardian.manifest"
@'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges>
    <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
  </requestedPrivileges></security></trustInfo>
  <application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings>
    <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
  </windowsSettings></application>
</assembly>
'@ | Set-Content -LiteralPath $manifest -Encoding UTF8

& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize `
    "/reference:$([PSObject].Assembly.Location)" /reference:System.Windows.Forms.dll `
    "/win32manifest:$manifest" "/resource:$PSScriptRoot\clean_software.ps1,clean_software.ps1" `
    "/out:$PSScriptRoot\SoftwareGuardian.exe" "$PSScriptRoot\launcher.cs"
