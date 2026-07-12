@echo off
title Install - Add to Zotero for Windows
echo Installing the right-click "Add to Zotero" menu...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
echo.
pause
