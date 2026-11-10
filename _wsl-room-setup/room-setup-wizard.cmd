@echo off
rem ============================================================
rem  room-setup-wizard.cmd - runs New-SecureRoom.ps1 (in this
rem  folder) in interactive mode: instead of reading room.conf
rem  and room-github.conf, it asks for the same values on screen.
rem  Nothing you type is saved to a file.
rem
rem  Double-click this file in Explorer (or run it from
rem  PowerShell / Command Prompt).
rem
rem  Copy the wsl-room-setup folder to the Windows side and run
rem  the copy. The script stops if it is started from inside a
rem  WSL distribution (\\wsl.localhost\... or \\wsl$\...).
rem
rem  "-ExecutionPolicy Bypass" below applies only to the
rem  powershell.exe started here, which is the same effect as
rem  "Set-ExecutionPolicy -Scope Process Bypass". The execution
rem  policy of this PC is not changed.
rem
rem  Arguments, if any, are passed to New-SecureRoom.ps1 as they
rem  are (for example: room-setup-wizard.cmd -DryRun).
rem
rem  Keep this file ASCII-only with CRLF line endings: cmd.exe
rem  reads batch files in the console code page, not UTF-8.
rem ============================================================
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-SecureRoom.ps1" -Interactive %*
set "RC=%ERRORLEVEL%"
echo.
rem Keep the window open when started by double-click.
pause
exit /b %RC%
