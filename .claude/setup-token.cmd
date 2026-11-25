@echo off
rem Double-click: save your GitLab / GitHub token once.
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0scripts\setup-token.ps1"
