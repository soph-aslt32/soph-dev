@echo off
rem ============================================================
rem  room-setup.cmd - runs New-SecureRoom.ps1 (in this folder)
rem  without "Set-ExecutionPolicy -Scope Process Bypass".
rem
rem  "-ExecutionPolicy Bypass" below applies only to the
rem  powershell.exe started here, which is the same effect as
rem  "Set-ExecutionPolicy -Scope Process Bypass". The execution
rem  policy of this PC is not changed.
rem
rem  Usage (PowerShell, Command Prompt, or double-click):
rem    room-setup.cmd
rem    room-setup.cmd -DryRun
rem    room-setup.cmd -RoomName dev -Resume
rem    room-setup.cmd -RoomName dev -VerifyOnly
rem  All arguments are passed to New-SecureRoom.ps1 as they are.
rem
rem  Keep this file ASCII-only with CRLF line endings: cmd.exe
rem  reads batch files in the console code page, not UTF-8.
rem ============================================================
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-SecureRoom.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
rem Keep the window open when started by double-click.
pause
exit /b %RC%
