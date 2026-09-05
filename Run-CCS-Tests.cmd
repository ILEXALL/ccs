@echo off
chcp 65001 >nul
cd /d "%~dp0"
node telegram_auth_server/test/run.cjs
set "test_exit=%errorlevel%"
pause
exit /b %test_exit%
