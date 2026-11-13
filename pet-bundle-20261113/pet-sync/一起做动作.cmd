@echo off
rem ============================================================
rem  Make every desktop pet play the same animation at once.
rem
rem  Double-click: numbered list, pick one, then asks about looping.
rem  With arguments (action name typed in Chinese):
rem    run ACTION
rem    run ACTION --loop
rem    run ACTION --repeat 5
rem    run ACTION --loop --random
rem  Keep this file ASCII-only with CRLF line endings: cmd.exe parses
rem  batch files byte-wise and UTF-8 / LF breaks the parsing.
rem  No "chcp 65001" here on purpose: changing the codepage makes cmd
rem  drop redirected stdin, and the prompts below would read nothing.
rem  Chinese text comes from PowerShell, which writes to the console
rem  through the console API and shows correctly regardless of codepage.
rem ============================================================
setlocal
cd /d "%~dp0"

set "PS=powershell.exe"
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not "%~1"=="" goto play

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0petsync.ps1" numbers
if errorlevel 1 (
  echo.
  pause
  exit /b 1
)
echo.
set "PICK="
set /p "PICK=Number or action name - blank to quit: "
if not defined PICK goto done

echo.
set "LOOP="
set /p "LOOP=Loop it? [y/N]: "
if /i not "%LOOP%"=="y" goto once

set "SECS="
set /p "SECS=Seconds between rounds [10]: "
if not defined SECS set "SECS=10"
echo.
echo   Looping every %SECS%s. Press Ctrl+C to stop.
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0petsync.ps1" "%PICK%" --loop --interval %SECS%000
goto after

:once
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0petsync.ps1" "%PICK%"

:after
echo.
pause
endlocal
exit /b 0

:play
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0petsync.ps1" %*
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%

:done
endlocal
exit /b 0
