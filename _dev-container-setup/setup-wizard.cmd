@echo off
rem ============================================================
rem  setup-wizard.cmd - runs DevContainerSetup.ps1 (in this folder).
rem  It asks on screen what to do (create a dev environment, redo
rem  its setup, delete it, only verify it, or update everything)
rem  and the values it needs. Nothing you type (including the
rem  GitHub PAT) is saved to a file on Windows. Only the default
rem  of the allowed domains is read from defaults.conf, and the
rem  VS Code extensions from extensions.txt, in this folder.
rem
rem  Double-click this file in Explorer (or run it from
rem  PowerShell / Command Prompt). It takes no arguments.
rem
rem  "-ExecutionPolicy Bypass" below applies only to the
rem  powershell.exe started here, which is the same effect as
rem  "Set-ExecutionPolicy -Scope Process Bypass". The execution
rem  policy of this PC is not changed.
rem
rem  Keep this file ASCII-only with CRLF line endings: cmd.exe
rem  reads batch files in the console code page, not UTF-8.
rem ============================================================
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DevContainerSetup.ps1"
set "RC=%ERRORLEVEL%"
echo.
rem Keep the window open when started by double-click.
pause
exit /b %RC%
