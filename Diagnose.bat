@echo off
title Diagnose - Add to Zotero for Windows
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Zotero.ps1"
echo.
pause
