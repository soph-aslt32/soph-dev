@echo off
rem ==========================================================================
rem  VS Code setup launcher
rem  Double-click this file. It runs install.ps1 in the same folder.
rem  (-ExecutionPolicy Bypass also allows running a downloaded install.ps1)
rem
rem  Keep this file ASCII only (no Japanese), and CRLF line endings.
rem ==========================================================================
title VS Code Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
