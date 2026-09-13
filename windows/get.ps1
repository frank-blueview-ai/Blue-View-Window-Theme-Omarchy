# Blue View OS for Windows 11: one-command setup.
#
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
#
# In PowerShell:
#   irm https://raw.githubusercontent.com/frank-blueview-ai/Blue-View-Window-Theme-Omarchy/main/windows/get.ps1 | iex
#
# Downloads the newest Blue View OS theme release from GitHub, unpacks it, and
# runs its installer. The unpacked copy stays in %LOCALAPPDATA%\BlueViewOS\Setup,
# with Uninstall.cmd, for later.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'frank-blueview-ai/Blue-View-Window-Theme-Omarchy'
$assetName = 'Blue-View-OS-Windows-11-Theme.zip'

Write-Host 'Blue View OS for Windows 11' -ForegroundColor White
Write-Host '    Finding the newest release...' -ForegroundColor DarkGray

# Newest release first, test releases included, that has the theme attached.
$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases" -Headers @{ 'User-Agent' = 'BlueViewOS-Setup' } -UseBasicParsing
$release = $null
$asset = $null
foreach ($candidate in $releases) {
    $asset = $candidate.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if ($asset) {
        $release = $candidate
        break
    }
}
if (-not $asset) {
    throw "No release with $assetName was found at https://github.com/$repo/releases"
}
Write-Host "    Downloading $($release.name)..." -ForegroundColor DarkGray

if ($env:OS -eq 'Windows_NT') {
    $setupRoot = Join-Path $env:LOCALAPPDATA 'BlueViewOS\Setup'
} else {
    $setupRoot = Join-Path ([IO.Path]::GetTempPath()) 'BlueViewOS-Setup'
}
$zip = Join-Path ([IO.Path]::GetTempPath()) $assetName
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

if (Test-Path $setupRoot) {
    Remove-Item $setupRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $setupRoot -Force | Out-Null
Expand-Archive -Path $zip -DestinationPath $setupRoot -Force
Remove-Item $zip -Force
if ($env:OS -eq 'Windows_NT') {
    # Downloaded files are marked as coming from the internet; the setup copy is trusted.
    Get-ChildItem $setupRoot -Recurse -File | Unblock-File
}

# Older releases put everything inside a folder in the zip.
$installer = Get-ChildItem $setupRoot -Filter 'install.ps1' -Recurse -File | Sort-Object { $_.FullName.Length } | Select-Object -First 1
if (-not $installer) {
    throw "The download doesn't contain install.ps1."
}
$installer = $installer.FullName
$setupRoot = Split-Path -Parent $installer
if ($env:OS -ne 'Windows_NT') {
    Write-Host "    Unpacked to $setupRoot (the installer only runs on Windows)."
    return
}

# A separate PowerShell, so the installer runs from its own folder.
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $powershell -NoProfile -ExecutionPolicy Bypass -File $installer
Write-Host ''
Write-Host "Setup files are kept in $setupRoot. To remove Blue View OS later, run Uninstall.cmd there."
