@echo off
rem Blue View OS for Windows 11: double-click to remove.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
echo.
pause
