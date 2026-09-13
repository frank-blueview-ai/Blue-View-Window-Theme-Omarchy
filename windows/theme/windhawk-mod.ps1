# Blue View OS for Windows 11: installs or removes the title bar mod in Windhawk.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# Run as administrator by install.ps1 / uninstall.ps1. Does what Windhawk's own
# "Install" button does for a mod from its catalog: downloads the precompiled
# mod, places it in Windhawk's engine folder, and registers it with its settings.
# Windhawk watches its registry key and loads the mod without a restart.
#
# The mod, "Hide Titlebar Icon and Text" (hide-titlebar-elements, MIT, by
# darkthemer), hides the icon and title text so title bars are clean and slim.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Remove')]
    [string]$Action,

    [switch]$KeepTitleText
)

$ErrorActionPreference = 'Stop'

$ModId = 'hide-titlebar-elements'
$ModVersion = '1.0'
$ModsUrl = 'https://mods.windhawk.net/mods/'
$ModSourceUrl = 'https://raw.githubusercontent.com/ramensoftware/windhawk-mods/main/mods/hide-titlebar-elements.wh.cpp'

function Get-WindhawkFolder {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($entry in Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue) {
        if ($entry.DisplayName -like 'Windhawk*' -and $entry.InstallLocation -and (Test-Path (Join-Path $entry.InstallLocation 'windhawk.ini'))) {
            return $entry.InstallLocation
        }
    }
    $default = Join-Path $env:ProgramFiles 'Windhawk'
    if (Test-Path (Join-Path $default 'windhawk.ini')) {
        return $default
    }
    throw 'Windhawk is not installed.'
}

# Reads the [Storage] section of windhawk.ini, where Windhawk records where it keeps mods.
function Get-WindhawkStorage([string]$Folder) {
    $storage = @{}
    $inSection = $false
    foreach ($line in Get-Content (Join-Path $Folder 'windhawk.ini')) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $inSection = $Matches[1] -eq 'Storage'
        } elseif ($inSection -and $trimmed -match '^([^=;]+)=(.*)$') {
            $storage[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    if ($storage['Portable'] -eq '1') {
        throw 'This is a portable Windhawk; install the regular version.'
    }
    if (-not $storage['AppDataPath'] -or -not $storage['RegistryKey']) {
        throw 'windhawk.ini is missing AppDataPath or RegistryKey.'
    }

    # Paths are relative to the Windhawk folder and may use environment variables.
    $appData = [Environment]::ExpandEnvironmentVariables(($storage['AppDataPath'] -replace '%ProgramFiles%', '%ProgramW6432%'))
    if (-not [IO.Path]::IsPathRooted($appData)) {
        $appData = Join-Path $Folder $appData
    }

    $key = $storage['RegistryKey']
    $root, $subKey = $key -split '\\', 2
    switch ($root.ToUpperInvariant()) {
        { $_ -in 'HKLM', 'HKEY_LOCAL_MACHINE' } { $root = 'HKEY_LOCAL_MACHINE' }
        { $_ -in 'HKCU', 'HKEY_CURRENT_USER' } { $root = 'HKEY_CURRENT_USER' }
        default { throw "Unsupported Windhawk registry key: $key" }
    }

    return @{
        AppDataPath = $appData
        ModKey      = "Registry::$root\$subKey\Engine\Mods\$ModId"
    }
}

# The mod targets every process and declares no architectures, which Windhawk
# treats as 32- and 64-bit (and ARM64 on ARM PCs).
function Get-ArchitectureFolders {
    $folders = @('32', '64')
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        $folders += 'arm64'
    }
    return $folders
}

function Install-Mod($Storage) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $dllName = '{0}_{1}_{2}.dll' -f $ModId, $ModVersion, (Get-Random -Minimum 100000 -Maximum 999999)

    foreach ($arch in Get-ArchitectureFolders) {
        $folder = Join-Path $Storage.AppDataPath "Engine\Mods\$arch"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $url = "$ModsUrl$ModId/${ModVersion}_$arch.dll"
        Write-Host "    Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $folder $dllName) -UseBasicParsing
    }

    # Keep a copy of the source so the mod shows up normally in Windhawk.
    try {
        $sourceFolder = Join-Path $Storage.AppDataPath 'ModsSource'
        New-Item -ItemType Directory -Path $sourceFolder -Force | Out-Null
        Invoke-WebRequest -Uri $ModSourceUrl -OutFile (Join-Path $sourceFolder "$ModId.wh.cpp") -UseBasicParsing
    } catch {
        Write-Host '    (Could not download the mod source; the mod still works.)'
    }

    $key = $Storage.ModKey
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty -Path $key -Name 'LibraryFileName' -Value $dllName -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'Disabled' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $key -Name 'Include' -Value '*' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'Exclude' -Value '' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'Architecture' -Value '' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $key -Name 'Version' -Value $ModVersion -PropertyType String -Force | Out-Null

    $settings = "$key\Settings"
    New-Item -Path $settings -Force | Out-Null
    New-ItemProperty -Path $settings -Name 'hideIcon' -Value 1 -PropertyType DWord -Force | Out-Null
    $hideText = 1
    if ($KeepTitleText) { $hideText = 0 }
    New-ItemProperty -Path $settings -Name 'hideText' -Value $hideText -PropertyType DWord -Force | Out-Null

    $changeTime = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -band 0x7fffffff)
    New-ItemProperty -Path $key -Name 'SettingsChangeTime' -Value $changeTime -PropertyType DWord -Force | Out-Null

    # Remove older copies of this mod's DLL from previous installs.
    foreach ($arch in Get-ArchitectureFolders) {
        Get-ChildItem (Join-Path $Storage.AppDataPath "Engine\Mods\$arch") -Filter "${ModId}_*.dll" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $dllName } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Remove-Mod($Storage) {
    $key = $Storage.ModKey
    if (Test-Path $key) {
        # Disable first so Windhawk unloads it, then remove its registration.
        New-ItemProperty -Path $key -Name 'Disabled' -Value 1 -PropertyType DWord -Force | Out-Null
        Start-Sleep -Seconds 2
        Remove-Item -Path $key -Recurse -Force
    }
    foreach ($arch in '32', '64', 'arm64') {
        Get-ChildItem (Join-Path $Storage.AppDataPath "Engine\Mods\$arch") -Filter "${ModId}_*.dll" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Remove-Item (Join-Path $Storage.AppDataPath "ModsSource\$ModId.wh.cpp") -Force -ErrorAction SilentlyContinue
}

try {
    $storage = Get-WindhawkStorage (Get-WindhawkFolder)
    if ($Action -eq 'Install') {
        Install-Mod $storage
        Write-Host '    Title bar mod installed.'
    } else {
        Remove-Mod $storage
        Write-Host '    Title bar mod removed.'
    }
    exit 0
} catch {
    Write-Host "    ! $($_.Exception.Message)" -ForegroundColor Yellow
    # When run in its own administrator window, leave the message on screen for a moment.
    Start-Sleep -Seconds 8
    exit 1
}
