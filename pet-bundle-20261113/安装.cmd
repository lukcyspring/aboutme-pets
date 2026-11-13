@echo off
rem Double-click to install the three pet packs into this machine's DSH.
rem ASCII-only + CRLF on purpose (cmd.exe parses batch files byte-wise).
setlocal
cd /d "%~dp0"
set "PS=powershell.exe"
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
