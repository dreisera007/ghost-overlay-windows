@echo off
rem Stops the controller and hands the ChatGPT window back (opaque, normal size, not on top).
set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" (
  echo AutoHotkey v2 was not found.
  exit /b 1
)
"%AHK%" "%~dp0GhostOverlay.ahk" --stop
echo ChatGPT Ghost Overlay stopped.
