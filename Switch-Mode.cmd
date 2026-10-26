@echo off
rem Switches the Ghost Overlay presentation mode and restarts the controller in that mode.
rem   Switch-Mode.cmd Document   - chatgpt.com in a Chrome app window, document look
rem   Switch-Mode.cmd ChatGPT    - the native ChatGPT desktop app (original mode)
rem   Switch-Mode.cmd Classic    - ChatGPT Classic
if "%~1"=="" (
  echo Usage: Switch-Mode.cmd Document^|ChatGPT^|Classic
  exit /b 1
)
set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" (
  echo AutoHotkey v2 was not found. Install it from https://www.autohotkey.com/ and try again.
  pause
  exit /b 1
)
start "" "%AHK%" "%~dp0GhostOverlay.ahk" --mode %~1
