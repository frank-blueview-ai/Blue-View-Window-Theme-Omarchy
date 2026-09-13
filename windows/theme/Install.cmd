@echo off
rem Blue View OS for Windows 11: double-click to install.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
