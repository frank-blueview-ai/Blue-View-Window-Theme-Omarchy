# Blue View OS for Windows 11: removes the theme and the apps it installed.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Usage, in PowerShell from this folder:
#   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#   ... -KeepApps         keep TranslucentTB, Mica For Everyone and Windhawk installed
#   ... -KeepWindhawk     remove only our mod from Windhawk, keep Windhawk itself

[CmdletBinding()]
param(
    [switch]$KeepApps,
    [switch]$KeepWindhawk
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host 'Removing Blue View OS for Windows 11' -ForegroundColor White

function Invoke-Quietly([string]$What, [scriptblock]$Action) {
    try { & $Action } catch { Write-Problem "${What}: $($_.Exception.Message)" }
}

Write-Step 'Restoring the Windows dark theme'
Invoke-Quietly 'Theme' {
    $dark = Join-Path $env:SystemRoot 'Resources\Themes\dark.theme'
    if (Test-Path $dark) {
        Set-WindowsTheme $dark
    }
    Send-ColorSettingChange
}

Write-Step 'Removing clean title bars'
Invoke-Quietly 'Title bars' {
    if (Test-WingetPackage $Windhawk.Id) {
        [void](Invoke-WindhawkModScript @('-Action', 'Remove'))
        if (-not $KeepApps -and -not $KeepWindhawk) {
            Uninstall-WingetPackage $Windhawk.Id
        }
    }
}

Write-Step 'Removing glass windows'
Invoke-Quietly 'Glass windows' {
    Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $MicaForEveryone.RunValue -ErrorAction SilentlyContinue
    Get-Process -Name 'MicaForEveryone', 'mfe' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not $KeepApps) {
        Uninstall-WingetPackage $MicaForEveryone.Id
    }
}

Write-Step 'Removing the glass taskbar'
Invoke-Quietly 'Glass taskbar' {
    Get-Process -Name 'TranslucentTB' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if (-not $KeepApps) {
        # Removing TranslucentTB restarts File Explorer, which puts the taskbar back to normal.
        Uninstall-WingetPackage $TranslucentTB.Id
    }
}

Write-Step 'Removing Blue View OS files'
Invoke-Quietly 'Files' {
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force
    }
}

Write-Host ''
Write-Host 'Blue View OS is removed. Windows already open keep their glass until they are closed; signing out clears everything.'
