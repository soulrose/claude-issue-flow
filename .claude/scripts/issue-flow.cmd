@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0issue-flow.ps1" %*
exit /b %ERRORLEVEL%
