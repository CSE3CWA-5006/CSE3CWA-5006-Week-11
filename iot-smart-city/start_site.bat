@echo off
rem Copyright (C) 2026 Dr Shuo Ding <shuoding@outlook.com>

setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
pause
