# Blue View OS for Windows 11: installs the theme.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
#   Theme pack      the Blue View sky wallpapers (a slideshow through the day),
#                   dark mode, and the logo's blue as the accent color
#   Glass windows   frosted glass and dark title bars (Mica For Everyone)
#   Glass taskbar   a nearly invisible taskbar (TranslucentTB)
#   Title bars      clean title bars without icon or text (Windhawk mod)
#   Tiling          Win+Shift+T tiles all windows; drag a tile onto another to swap
#
# Usage, in PowerShell from this folder:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   ... -ThemeOnly             only the wallpapers, dark mode and colors
#   ... -NoGlassWindows -NoGlassTaskbar -NoTitleBars -NoTiling   skip any part
#   ... -KeepTitleText         hide title bar icons but keep window titles

[CmdletBinding()]
param(
    [switch]$ThemeOnly,
    [switch]$NoGlassWindows,
    [switch]$NoGlassTaskbar,
    [switch]$NoTitleBars,
    [switch]$NoTiling,
    [switch]$KeepTitleText
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$results = [ordered]@{}

function Install-ThemePack {
    Write-Step 'Installing the Blue View OS theme pack'

    # Copy the wallpapers and write the theme with this PC's real paths.
    New-Item -ItemType Directory -Path $WallpaperDir -Force | Out-Null
    Get-ChildItem (Join-Path $PSScriptRoot 'wallpapers') -Filter *.jpg | ForEach-Object {
        Copy-Item $_.FullName -Destination $WallpaperDir -Force
    }
    Get-ChildItem $WallpaperDir | Unblock-File

    $template = Get-Content (Join-Path $PSScriptRoot 'Blue View OS.theme.in') -Raw
    $lines = ($template -replace '\{\{WALLPAPERS\}\}', $WallpaperDir) -split "`r?`n" | Where-Object { $_ -notmatch '^\s*;' }
    [IO.File]::WriteAllText($ThemeFile, ($lines -join "`r`n").Trim() + "`r`n", [Text.Encoding]::Unicode)

    # Windows re-compresses JPG wallpapers to 85% quality unless told otherwise.
    Set-RegistryValue 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' 100

    Set-WindowsTheme $ThemeFile

    # Glass stays clear: transparency on, and no accent color on title bars,
    # window borders, Start or the taskbar.
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-RegistryValue $personalize 'EnableTransparency' 1
    Set-RegistryValue $personalize 'ColorPrevalence' 0
    Set-RegistryValue $personalize 'AppsUseLightTheme' 0
    Set-RegistryValue $personalize 'SystemUsesLightTheme' 0
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 0
    Send-ColorSettingChange

    Write-Note "Wallpapers: $WallpaperDir"
    return $true
}

function Install-GlassTaskbar {
    Write-Step 'Installing the glass taskbar (TranslucentTB)'
    if (-not (Install-WingetPackage $TranslucentTB.Id)) { return $false }

    # Settings go in before the first launch, which also skips its welcome window.
    $settings = Join-Path (Get-PackageDataPath $TranslucentTB) $TranslucentTB.SettingsPath
    Save-TextFile $settings (Get-Content (Join-Path $PSScriptRoot 'translucenttb.json') -Raw)

    # Launching it once also turns on its start-with-Windows task. A running copy
    # picks up the new settings file by itself.
    if (-not (Get-Process TranslucentTB -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe "shell:AppsFolder\$($TranslucentTB.FamilyName)!$($TranslucentTB.AppId)"
    }
    Write-Note 'TranslucentTB is running and starts with Windows.'
    return $true
}

function Install-GlassWindows {
    Write-Step 'Installing glass windows (Mica For Everyone)'

    # Its winget manifest names a runtime package that winget no longer has,
    # so install the current runtime first and skip the stale dependency.
    if (-not (Install-WingetPackage $MicaForEveryone.RuntimeId)) { return $false }
    if (-not (Install-WingetPackage $MicaForEveryone.Id @('--skip-dependencies'))) { return $false }

    $settings = Join-Path (Get-PackageDataPath $MicaForEveryone) $MicaForEveryone.SettingsPath
    Save-TextFile $settings (Get-Content (Join-Path $PSScriptRoot 'mica-for-everyone.json') -Raw)

    # Start with Windows, quietly in the tray.
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\mfe.exe'
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' $MicaForEveryone.RunValue "`"$alias`"" 'String'

    if (-not (Get-Process -Name 'MicaForEveryone' -ErrorAction SilentlyContinue)) {
        if (Test-Path $alias) {
            Start-Process -FilePath $alias
        } else {
            Write-Problem 'Mica For Everyone will start after you sign out and back in.'
        }
    }
    Write-Note 'Glass applies to windows as they open. Browsers, File Explorer and a few apps are left as they are.'
    return $true
}

function Install-TitleBars {
    Write-Step 'Installing clean title bars (Windhawk)'
    if (-not (Install-WingetPackage $Windhawk.Id)) { return $false }

    $arguments = @('-Action', 'Install')
    if ($KeepTitleText) { $arguments += '-KeepTitleText' }
    if (-not (Invoke-WindhawkModScript $arguments)) { return $false }

    Write-Note 'Applies to windows as they open.'
    return $true
}

function Install-Tiling {
    Write-Step 'Installing window tiling (Win+Shift+T)'

    # Built on this PC from its source with the C# compiler that comes with Windows.
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) {
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path $csc)) {
        Write-Problem 'The .NET Framework C# compiler was not found.'
        return $false
    }

    Get-Process -Name $Tiling.ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    $source = Join-Path $PSScriptRoot 'tiling\BlueViewTiling.cs'
    $ErrorActionPreference = 'Continue'
    & $csc /nologo /target:winexe /optimize+ "/out:$($Tiling.Exe)" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $source | Out-Host
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Tiling.Exe)) {
        Write-Problem 'Building the tiling helper failed.'
        return $false
    }

    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' $Tiling.RunValue "`"$($Tiling.Exe)`"" 'String'
    Start-Process -FilePath $Tiling.Exe
    Write-Note 'Running in the tray and starts with Windows. Win+Shift+T tiles the windows on the screen under the pointer.'
    return $true
}

function Invoke-Part([string]$Name, [scriptblock]$Action) {
    try {
        $results[$Name] = [bool](& $Action | Select-Object -Last 1)
    } catch {
        Write-Problem $_.Exception.Message
        $results[$Name] = $false
    }
}

# ---- Run ----------------------------------------------------------------------

Write-Host 'Blue View OS for Windows 11' -ForegroundColor White
Assert-Windows11

Invoke-Part 'Theme pack' { Install-ThemePack }
if (-not $ThemeOnly -and -not $NoTiling) { Invoke-Part 'Window tiling' { Install-Tiling } }

if (-not $ThemeOnly) {
    if (-not (Test-Winget)) {
        Write-Problem 'winget is missing. Install "App Installer" from the Microsoft Store, then run this again for the glass parts.'
    } else {
        if (-not $NoGlassTaskbar) { Invoke-Part 'Glass taskbar' { Install-GlassTaskbar } }
        if (-not $NoGlassWindows) { Invoke-Part 'Glass windows' { Install-GlassWindows } }
        if (-not $NoTitleBars) { Invoke-Part 'Clean title bars' { Install-TitleBars } }
    }
}

Write-Host ''
Write-Host 'Summary' -ForegroundColor White
foreach ($part in $results.Keys) {
    if ($results[$part]) {
        Write-Host "  [ok]      $part" -ForegroundColor Green
    } else {
        Write-Host "  [failed]  $part" -ForegroundColor Yellow
    }
}
Write-Host ''
Write-Host 'Open apps pick up the glass the next time they open. To undo everything: .\uninstall.ps1'
