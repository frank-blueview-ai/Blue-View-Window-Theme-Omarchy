# Blue View OS for Windows 11: shared helpers for install.ps1 and uninstall.ps1.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Written for Windows PowerShell 5.1, which every Windows 11 PC has.

$script:InstallDir = Join-Path $env:LOCALAPPDATA 'BlueViewOS'
$script:WallpaperDir = Join-Path $script:InstallDir 'Wallpapers'
$script:ThemeFile = Join-Path $script:InstallDir 'Blue View OS.theme'

# Packaged app identities (from each app's winget manifest).
$script:TranslucentTB = @{
    Id            = 'CharlesMilette.TranslucentTB'
    FamilyName    = '28017CharlesMilette.TranslucentTB_v826wp6bftszj'
    AppId         = 'TranslucentTB'
    SettingsPath  = 'RoamingState\settings.json'
}
$script:MicaForEveryone = @{
    Id            = 'MicaForEveryone.MicaForEveryone'
    RuntimeId     = 'Microsoft.WindowsAppRuntime.2'
    FamilyName    = 'MicaForEveryone.MicaForEveryone2_eydvrrwaqjtyw'
    SettingsPath  = 'LocalState\settings.json'
    RunValue      = 'BlueViewOS-MicaForEveryone'
}
$script:Windhawk = @{
    Id            = 'RamenSoftware.Windhawk'
}

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Note([string]$Message) {
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Problem([string]$Message) {
    Write-Host "    ! $Message" -ForegroundColor Yellow
}

function Assert-Windows11 {
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 22000) {
        throw "Blue View OS for Windows needs Windows 11 (this PC is build $build)."
    }
}

function Test-Winget {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

# Windows PowerShell 5.1 turns anything a program writes to its error stream
# into an error, which would stop the script, so winget runs with errors allowed.
function Test-WingetPackage([string]$Id) {
    $ErrorActionPreference = 'Continue'
    $null = & winget list --id $Id --exact --accept-source-agreements 2>&1
    return $LASTEXITCODE -eq 0
}

# Installs a winget package unless it's already there. Returns $true on success.
function Install-WingetPackage([string]$Id, [string[]]$ExtraArgs = @()) {
    if (Test-WingetPackage $Id) {
        Write-Note "$Id is already installed."
        return $true
    }
    Write-Note "Installing $Id with winget..."
    $ErrorActionPreference = 'Continue'
    $arguments = @('install', '--id', $Id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements') + $ExtraArgs
    # Send winget's progress to the screen, not into this function's result.
    & winget @arguments | Out-Host
    if ($LASTEXITCODE -eq 0 -or (Test-WingetPackage $Id)) {
        return $true
    }
    Write-Problem "winget could not install $Id (exit code $LASTEXITCODE)."
    return $false
}

function Uninstall-WingetPackage([string]$Id) {
    if (-not (Test-WingetPackage $Id)) {
        return
    }
    Write-Note "Removing $Id..."
    $ErrorActionPreference = 'Continue'
    & winget uninstall --id $Id --exact --silent --accept-source-agreements | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Problem "winget could not remove $Id (exit code $LASTEXITCODE)."
    }
}

function Get-PackageDataPath([hashtable]$App) {
    return Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') $App.FamilyName
}

# Writes text as UTF-8 without a byte-order mark, creating folders as needed.
function Save-TextFile([string]$Path, [string]$Text) {
    $folder = Split-Path -Parent $Path
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

function Set-RegistryValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# Tells open windows and the taskbar that colors changed, as the Settings app does.
function Send-ColorSettingChange {
    if (-not ('BlueViewOS.NativeMethods' -as [type])) {
        Add-Type -Namespace BlueViewOS -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x2
    $result = [UIntPtr]::Zero
    foreach ($area in 'ImmersiveColorSet', 'WindowsThemeElement') {
        [void][BlueViewOS.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, $area, $SMTO_ABORTIFHUNG, 3000, [ref]$result)
    }
}

# Applies a .theme file. First through the Windows theme manager (the same
# component the Settings app uses, so no window opens); if that isn't available,
# by opening the file and closing Settings once it has applied.
function Set-WindowsTheme([string]$Path) {
    if (-not ('BlueViewOS.ThemeManager' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace BlueViewOS
{
    [ComImport, Guid("D23CC733-5522-406D-8DFB-B3CF5EF52A71"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IThemeInfo { }

    [ComImport, Guid("0646EBBE-C1B7-4045-8FD0-FFD65D3FC792"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IWindowsThemeManager
    {
        IThemeInfo CurrentTheme { get; }
        void ApplyTheme([MarshalAs(UnmanagedType.BStr)] string themePath);
    }

    [ComImport, Guid("C04B329E-5823-4415-9C93-BA44688947B0")]
    public class WindowsThemeManager { }

    public static class ThemeManager
    {
        public static void Apply(string themePath)
        {
            var manager = (IWindowsThemeManager)new WindowsThemeManager();
            try { manager.ApplyTheme(themePath); }
            finally { Marshal.ReleaseComObject(manager); }
        }
    }
}
'@
    }

    try {
        [BlueViewOS.ThemeManager]::Apply($Path)
        Write-Note 'Applied through the Windows theme manager.'
    } catch {
        Write-Note 'Theme manager unavailable; applying through Settings instead.'
        Start-Process -FilePath $Path
        Start-Sleep -Seconds 6
    }
    Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Runs windhawk-mod.ps1 as administrator (Windhawk keeps its mods machine-wide).
function Invoke-WindhawkModScript([string[]]$Arguments) {
    $modScript = Join-Path $PSScriptRoot 'windhawk-mod.ps1'
    # Always the 64-bit PowerShell on 64-bit Windows, so registry writes land in the 64-bit view.
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($env:PROCESSOR_ARCHITEW6432) {
        $powershell = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    $baseArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
    if (Test-Administrator) {
        & $powershell @($baseArguments + $modScript + $Arguments) | Out-Host
        return $LASTEXITCODE -eq 0
    }
    Write-Note 'Windows will ask for permission to set up the title bar mod.'
    try {
        # Start-Process joins arguments into one command line, so quote the path.
        $argumentList = $baseArguments + "`"$modScript`"" + $Arguments
        $process = Start-Process -FilePath $powershell -ArgumentList $argumentList -Verb RunAs -Wait -PassThru
        return $process.ExitCode -eq 0
    } catch {
        Write-Problem 'Permission was declined.'
        return $false
    }
}
