@echo off
rem The lore editor with the game's data loaded: double-click to open it in the browser. Close this window to stop.
cd /d "%~dp0"
python serve.py %*
if errorlevel 1 pause
