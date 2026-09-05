@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test_driver\run-explorer.ps1" -Choose
pause
