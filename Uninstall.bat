@echo off
title Uninstall - Add to Zotero for Windows
echo Removing the right-click "Add to Zotero" menu...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
echo.
pause
