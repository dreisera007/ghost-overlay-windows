@echo off
rem Starts the ChatGPT Ghost Overlay controller (no admin rights needed).
set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" (
  echo AutoHotkey v2 was not found. Install it from https://www.autohotkey.com/ and try again.
  pause
  exit /b 1
)
start "" "%AHK%" "%~dp0GhostOverlay.ahk"
